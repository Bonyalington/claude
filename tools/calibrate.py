"""Calibration: compare the model's REM guesses with Garmin sleep stages, suggest thresholds.

Usage:
  python tools/calibrate.py LUCIDCUE.BAK LUCIDCUE.TXT sleep_2026-10-10.json [more ...] --out calib/
  python tools/calibrate.py LUCIDCUE.BAK LUCIDCUE.TXT --out calib/   (log check only)
  python tools/calibrate.py LUCIDCUE.BAK LUCIDCUE.TXT --dump        (print decoded log)

Files ending in .json (any case) are Garmin sleep files; every other file is a watch log
(LUCIDCUE.TXT, LUCIDCUE.BAK, dated copies). Log files may come in any order and from
several mornings: they are joined in the time order of their first line. Wildcards
(logs/*/LUCIDCUE.*, sleep_*.json) are expanded here too, for Windows Command Prompt.

Exit status 2 means no thresholds are recommended (see NO_RECOMMENDATION).
"""
import argparse
import glob
import json
import os
import sys
from dataclasses import replace

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "model"))

from lucidcue_model.config import EPOCH_SEC, Config  # noqa: E402
from lucidcue_model.logparse import (decode_payload, join_logs, load_garmin_stages,  # noqa: E402
                                     parse_log)
from lucidcue_model.night import run_night  # noqa: E402
from lucidcue_model.sleep_state import ASLEEP  # noqa: E402

HR_RISE_GRID = [i / 100 for i in range(0, 21)]
VAR_RATIO_GRID = [1 + i / 20 for i in range(0, 21)]
STAGE_NUM = {"deep": 0, "light": 1, "rem": 2, "awake": 3}
NO_RECOMMENDATION = ("NO RECOMMENDATION — keep current thresholds; "
                     "check the sleep files / STAGE_MAP")


def _stage_at(t, stages):
    """Stage name covering t (intervals are [start, end)), or None."""
    for (start, end, name) in stages:
        if start <= t < end:
            return name
    return None


def score(results, stages) -> dict:
    """Per-epoch rem_like vs Garmin rem. Epochs outside every stage interval are excluded."""
    tp = 0
    fp = 0
    fn = 0
    for r in results:
        name = _stage_at(r.epoch.t, stages)
        if name is None:
            continue
        truth = name == "rem"
        pred = r.rem.rem_like
        if pred and truth:
            tp += 1
        elif pred and not truth:
            fp += 1
        elif truth and not pred:
            fn += 1
    precision = tp / (tp + fp) if tp + fp > 0 else 0.0
    recall = tp / (tp + fn) if tp + fn > 0 else 0.0
    if precision == 0.0 and recall == 0.0:
        f05 = 0.0
    else:
        f05 = 1.25 * precision * recall / (0.25 * precision + recall)
    return {"precision": precision, "recall": recall, "f05": f05, "tp": tp, "fp": fp, "fn": fn}


MIN_PRECISION = 0.60   # spec success criterion: >= 60% of REM-flagged epochs in Garmin REM
TIE = 1e-9             # scores closer than this count as equal


def evaluate(scored, cfg) -> dict:
    """Mean precision / recall / F0.5 over (night, stages) pairs, plus summed tp / fp / fn."""
    out = {"precision": 0.0, "recall": 0.0, "f05": 0.0, "tp": 0, "fp": 0, "fn": 0}
    if not scored:
        return out
    for (night, stages) in scored:
        s = score(run_night(night.epochs, cfg), stages)
        for key in out:
            out[key] += s[key]
    k = len(scored)
    for key in ("precision", "recall", "f05"):
        out[key] = out[key] / k
    return out


def _better(a, b):
    """True if trial a beats trial b. A trial is (f05, precision, hr_rise, var_ratio).
    Higher F0.5 wins; on a tie, higher precision; then the stricter (higher) hrRise,
    then the higher varRatio. Ties never go to looser thresholds (fewer false cues)."""
    if abs(a[0] - b[0]) > TIE:
        return a[0] > b[0]
    if abs(a[1] - b[1]) > TIE:
        return a[1] > b[1]
    if a[2] != b[2]:
        return a[2] > b[2]
    return a[3] > b[3]


def grid_search(nights, stages_by_night, cfg):
    """Return (best_hr_rise, best_var_ratio, metrics) maximising mean F0.5 (ties: see
    _better). metrics is evaluate()'s dict for the chosen cell."""
    scored = [(n, st) for (n, st) in zip(nights, stages_by_night) if st is not None]
    if not scored:
        return (cfg.hr_rise, cfg.var_ratio, evaluate(scored, cfg))
    best = None
    best_key = None
    for hr_rise in HR_RISE_GRID:
        for var_ratio in VAR_RATIO_GRID:
            m = evaluate(scored, replace(cfg, hr_rise=hr_rise, var_ratio=var_ratio))
            key = (m["f05"], m["precision"], hr_rise, var_ratio)
            if best_key is None or _better(key, best_key):
                best_key = key
                best = (hr_rise, var_ratio, m)
    return best


def overlap_seconds(night, stages):
    if not night.epochs:
        return 0
    n_start = night.epochs[0].t
    n_end = night.epochs[-1].t + EPOCH_SEC
    total = 0
    for (s, e, _) in stages:
        lo = max(s, n_start)
        hi = min(e, n_end)
        if hi > lo:
            total += hi - lo
    return total


def match_stages(nights, stage_sets):
    """For each night, the stage list (from stage_sets) overlapping it most, else None."""
    out = []
    for night in nights:
        best = None
        best_ov = 0
        for stages in stage_sets:
            ov = overlap_seconds(night, stages)
            if ov > best_ov:
                best_ov = ov
                best = stages
        out.append(best)
    return out


def percentile(values, p):
    s = sorted(values)
    if not s:
        return None
    return s[int(round(p / 100.0 * (len(s) - 1)))]


GAP_SEC = 45   # consecutive epochs further apart than 1.5 epochs: epochs are missing
END_EVENTS = ("night_end", "morning")


def night_stats(night) -> dict:
    """Log-survival check for one night: epoch count, hours spanned, epochs per hour
    (about 120 for an intact log), gaps between epochs, and whether the night's last
    event is night_end / morning (False: the log was cut short)."""
    n = len(night.epochs)
    hours = 0.0
    if n > 0:
        hours = (night.epochs[-1].t - night.epochs[0].t + EPOCH_SEC) / 3600.0
    gaps = 0
    for k in range(1, n):
        if night.epochs[k].t - night.epochs[k - 1].t > GAP_SEC:
            gaps += 1
    ended = len(night.events) > 0 and night.events[-1][1] in END_EVENTS
    return {"epochs": n, "hours": hours, "per_hour": n / hours if hours > 0 else 0.0,
            "gaps": gaps, "ended": ended}


def battery_drop(night):
    if len(night.battery) < 2:
        return None
    return night.battery[0][1] - night.battery[-1][1]


def plot_night(night, results, stages, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    ts = [r.epoch.t for r in results]
    hr = [r.epoch.hr_mean for r in results]
    var = [r.epoch.hr_var for r in results]
    hr_base = [r.rem.hr_base for r in results]
    var_base = [r.rem.var_base for r in results]
    fig, axes = plt.subplots(5, 1, sharex=True, figsize=(12, 10))
    axes[0].plot(ts, [r.epoch.motion for r in results], lw=0.6)
    axes[0].set_ylabel("motion")
    axes[1].plot(ts, hr, lw=0.6, label="hr")
    axes[1].plot(ts, hr_base, lw=0.8, label="hr_base")
    axes[1].set_ylabel("HR")
    axes[1].legend(loc="upper right")
    axes[2].plot(ts, var, lw=0.6, label="var")
    axes[2].plot(ts, var_base, lw=0.8, label="var_base")
    axes[2].set_ylabel("HR var")
    axes[2].legend(loc="upper right")
    axes[3].step(ts, [1 if r.rem.rem_like else 0 for r in results], where="post")
    axes[3].set_ylabel("rem_like")
    if stages:
        xs = []
        ys = []
        for (s, e, name) in sorted(stages):
            xs.extend([s, e])
            ys.extend([STAGE_NUM[name], STAGE_NUM[name]])
        axes[4].step(xs, ys, where="post")
    axes[4].set_ylim(-0.2, 3.2)
    axes[4].set_ylabel("Garmin\n0 deep 1 light 2 rem 3 awake")
    axes[4].set_xlabel("unix time (s)")
    fig.suptitle("night starting %d" % night.start_t)
    fig.savefig(path, dpi=80)
    plt.close(fig)


def _opt(x, fmt):
    return "" if x is None else fmt % x


def dump(text) -> None:
    """Print the joined log in file order with each D line decoded into readable
    E,<t>,<motion>,<hrMean>,<hrVar> lines (empty = null). Other lines are printed as they
    are; lines before the first night_start are left out (parse_log ignores them too)."""
    n = 0
    for raw in text.split("\n"):
        line = raw.strip()
        parts = line.split(",")
        if parts[0] == "X" and len(parts) == 4 and parts[2] == "night_start":
            n += 1
            print("# night %d (start %s)" % (n, parts[1]))
        if n == 0 or not line:
            continue
        if parts[0] != "D":
            print(line)
            continue
        epochs = None
        if len(parts) == 3 and parts[1].isdigit():
            epochs = decode_payload(int(parts[1]), parts[2])
        if epochs is None:
            print("# malformed, skipped: " + line)
            continue
        for e in epochs:
            print("E,%d,%d,%s,%s" % (e.t, e.motion, _opt(e.hr_mean, "%.1f"),
                                     _opt(e.hr_var, "%.2f")))


def _read_text(path):
    with open(path, encoding="utf-8-sig", errors="replace") as f:
        return f.read()


def main(argv=None):
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", metavar="FILE",
                    help="watch logs (LUCIDCUE.TXT / LUCIDCUE.BAK, any name not ending "
                         "in .json) and Garmin sleep files (*.json)")
    ap.add_argument("--out", default="calib")
    ap.add_argument("--dump", action="store_true",
                    help="print the decoded log (E,<t>,<motion>,<hrMean>,<hrVar> and X lines) "
                         "and exit")
    args = ap.parse_args(argv)
    files = []
    for p in args.files:
        if any(c in p for c in "*?[") and not os.path.exists(p):
            matches = sorted(glob.glob(p))
            if not matches:
                ap.error("no file matches %s" % p)
            files.extend(matches)
        else:
            files.append(p)
    logs = [p for p in files if not p.lower().endswith(".json")]
    sleep_json = [p for p in files if p.lower().endswith(".json")]
    if not logs:
        ap.error("no log file given (LUCIDCUE.TXT / LUCIDCUE.BAK)")

    text = join_logs([_read_text(p) for p in logs])
    if args.dump:
        dump(text)
        return 0
    nights = parse_log(text)
    stage_sets = []
    for p in sleep_json:
        with open(p) as f:
            stages = load_garmin_stages(json.load(f))
        if not stages:
            print("warning: %s has no sleep stages (sleepLevels missing or empty); skipped" % p)
            continue
        stage_sets.append(stages)
    stages_by_night = match_stages(nights, stage_sets)

    cfg = Config()
    os.makedirs(args.out, exist_ok=True)
    print("%d log file(s), %d night(s) in log, %d sleep file(s) with stages"
          % (len(logs), len(nights), len(stage_sets)))
    first = next((ln for ln in text.splitlines() if ln.strip()), "")
    if not first.startswith("X,") or ",night_start," not in first:
        print("warning: the log does not start with a night_start line "
              "(if the watch had a LUCIDCUE.BAK, pass it too)")

    asleep_motion = []
    for i, (night, stages) in enumerate(zip(nights, stages_by_night)):
        results = run_night(night.epochs, cfg)
        for r in results:
            if r.sleep.state == ASLEEP:
                asleep_motion.append(r.epoch.motion)
        drop = battery_drop(night)
        drop_txt = "n/a" if drop is None else "%.1f%%" % drop
        stage_txt = "no stages" if stages is None else "matched stages"
        st = night_stats(night)
        end_txt = "ends with night_end/morning" if st["ended"] else \
            "MISSING night_end/morning (log cut short?)"
        print("night %d (start %d): %d epochs over %.2f h = %.1f per hour (expect about 120), "
              "%d gap(s)" % (i + 1, night.start_t, st["epochs"], st["hours"], st["per_hour"],
                             st["gaps"]))
        print("  %s, %s, battery drop %s" % (end_txt, stage_txt, drop_txt))
        png = os.path.join(args.out, "night_%d_%d.png" % (i + 1, night.start_t))
        plot_night(night, results, stages, png)
        print("  plot: " + png)

    status = 0
    scored = [(n, st) for (n, st) in zip(nights, stages_by_night) if st is not None]
    if scored:
        d = evaluate(scored, cfg)
        print("default hrRise=%.2f varRatio=%.2f: precision=%.3f recall=%.3f f05=%.3f tp=%d"
              % (cfg.hr_rise, cfg.var_ratio, d["precision"], d["recall"], d["f05"], d["tp"]))
        hr_rise, var_ratio, best = grid_search(nights, stages_by_night, cfg)
        if best["tp"] == 0 or best["precision"] < MIN_PRECISION:
            print(NO_RECOMMENDATION)
            print("  (top grid cell: precision=%.3f recall=%.3f f05=%.3f tp=%d; "
                  "needs precision >= %.2f and tp > 0)"
                  % (best["precision"], best["recall"], best["f05"], best["tp"], MIN_PRECISION))
            status = 2
        else:
            print("best hrRise=%.2f varRatio=%.2f: precision=%.3f recall=%.3f f05=%.3f tp=%d"
                  % (hr_rise, var_ratio, best["precision"], best["recall"], best["f05"],
                     best["tp"]))
    elif not sleep_json:
        print("no sleep files given: log check only, no threshold search")
    else:
        print("no nights matched a sleep file")
        print(NO_RECOMMENDATION)
        status = 2

    if asleep_motion:
        print("motion in ASLEEP epochs: p50=%d p90=%d p99=%d" % (
            percentile(asleep_motion, 50), percentile(asleep_motion, 90),
            percentile(asleep_motion, 99)))
    else:
        print("motion in ASLEEP epochs: n/a (no ASLEEP epochs)")
    return status


if __name__ == "__main__":
    sys.exit(main())
