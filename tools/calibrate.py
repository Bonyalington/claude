"""Calibration: compare the model's REM guesses with Garmin sleep stages, suggest thresholds.

Usage:
  python tools/calibrate.py LUCIDCUE.TXT sleep_2026-10-10.json [more.json ...] --out calib/
"""
import argparse
import json
import os
import sys
from dataclasses import replace

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "model"))

from lucidcue_model.config import EPOCH_SEC, Config  # noqa: E402
from lucidcue_model.logparse import load_garmin_stages, parse_log  # noqa: E402
from lucidcue_model.night import run_night  # noqa: E402
from lucidcue_model.sleep_state import ASLEEP  # noqa: E402

HR_RISE_GRID = [i / 100 for i in range(0, 21)]
VAR_RATIO_GRID = [1 + i / 20 for i in range(0, 21)]
STAGE_NUM = {"deep": 0, "light": 1, "rem": 2, "awake": 3}


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


def grid_search(nights, stages_by_night, cfg):
    """Return (best_hr_rise, best_var_ratio, {precision, recall, f05}) maximising mean F0.5."""
    scored = [(n, st) for (n, st) in zip(nights, stages_by_night) if st is not None]
    best = (cfg.hr_rise, cfg.var_ratio, {"precision": 0.0, "recall": 0.0, "f05": 0.0})
    if not scored:
        return best
    best_f05 = -1.0
    for hr_rise in HR_RISE_GRID:
        for var_ratio in VAR_RATIO_GRID:
            trial = replace(cfg, hr_rise=hr_rise, var_ratio=var_ratio)
            sum_p = 0.0
            sum_r = 0.0
            sum_f = 0.0
            for (night, stages) in scored:
                s = score(run_night(night.epochs, trial), stages)
                sum_p += s["precision"]
                sum_r += s["recall"]
                sum_f += s["f05"]
            k = len(scored)
            if sum_f / k > best_f05:   # strict: ties go to the first found
                best_f05 = sum_f / k
                best = (hr_rise, var_ratio,
                        {"precision": sum_p / k, "recall": sum_r / k, "f05": sum_f / k})
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


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("log")
    ap.add_argument("sleep_json", nargs="+")
    ap.add_argument("--out", default="calib")
    args = ap.parse_args(argv)

    with open(args.log) as f:
        nights = parse_log(f.read())
    stage_sets = []
    for p in args.sleep_json:
        with open(p) as f:
            stage_sets.append(load_garmin_stages(json.load(f)))
    stages_by_night = match_stages(nights, stage_sets)

    cfg = Config()
    os.makedirs(args.out, exist_ok=True)
    print("%d night(s) in log, %d sleep file(s)" % (len(nights), len(stage_sets)))

    asleep_motion = []
    for i, (night, stages) in enumerate(zip(nights, stages_by_night)):
        results = run_night(night.epochs, cfg)
        for r in results:
            if r.sleep.state == ASLEEP:
                asleep_motion.append(r.epoch.motion)
        drop = battery_drop(night)
        drop_txt = "n/a" if drop is None else "%.1f%%" % drop
        stage_txt = "no stages" if stages is None else "matched stages"
        print("night %d (start %d): %d epochs, %s, battery drop %s"
              % (i + 1, night.start_t, len(night.epochs), stage_txt, drop_txt))
        png = os.path.join(args.out, "night_%d_%d.png" % (i + 1, night.start_t))
        plot_night(night, results, stages, png)
        print("  plot: " + png)

    if any(st is not None for st in stages_by_night):
        hr_rise, var_ratio, best = grid_search(nights, stages_by_night, cfg)
        print("best hrRise=%.2f varRatio=%.2f" % (hr_rise, var_ratio))
        print("  precision=%.3f recall=%.3f f05=%.3f"
              % (best["precision"], best["recall"], best["f05"]))
    else:
        print("no nights matched a sleep file; skipping grid search")

    if asleep_motion:
        print("motion in ASLEEP epochs: p50=%d p90=%d p99=%d" % (
            percentile(asleep_motion, 50), percentile(asleep_motion, 90),
            percentile(asleep_motion, 99)))
    else:
        print("motion in ASLEEP epochs: n/a (no ASLEEP epochs)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
