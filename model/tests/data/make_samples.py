"""Regenerate sample_log.txt and sample_sleep.json from scripted_night(0) + run_night.

Run from the model/ directory:  ../.venv/bin/python tests/data/make_samples.py
"""
import json
import os
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", ".."))

from lucidcue_model.config import Config  # noqa: E402
from lucidcue_model.night import run_night  # noqa: E402
from lucidcue_model.synth import scripted_night  # noqa: E402


def f1(x):
    return "" if x is None else "%.1f" % x


def gmt(t):
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.0")


def build_log(results):
    t_first = results[0].epoch.t
    t_last = results[-1].epoch.t
    lines = ["X,%d,night_start," % t_first, "X,%d,battery,90.0" % t_first]
    for r in results:
        e = r.epoch
        fired = r.cue.fire
        lines.append(",".join([
            "E", str(e.t), r.sleep.state, str(e.motion),
            f1(e.hr_mean), f1(e.hr_var), f1(r.rem.hr_base), f1(r.rem.var_base),
            "1" if r.rem.rem_like else "0", str(r.rem.episode_id),
            "cue" if fired else "", str(r.cue.level if fired else 0),
        ]))
    lines.append("X,%d,battery,84.0" % t_last)
    lines.append("E,1760028000,ASL")  # truncated final line
    return "\n".join(lines) + "\n"


def build_sleep(epochs, rem_spans):
    t_end = epochs[-1].t
    levels = []
    cur = epochs[0].t
    for (s, e) in rem_spans:
        if s > cur:
            levels.append((cur, s, 1))
        levels.append((s, e, 2))
        cur = e
    if cur <= t_end:
        levels.append((cur, t_end, 1))
    return {"sleepLevels": [
        {"startGMT": gmt(s), "endGMT": gmt(e), "activityLevel": lvl}
        for (s, e, lvl) in levels if e > s
    ]}


def main():
    epochs, spans, _ = scripted_night(0)
    results = run_night(epochs, Config())
    with open(os.path.join(HERE, "sample_log.txt"), "w", newline="\n") as f:
        f.write(build_log(results))
    with open(os.path.join(HERE, "sample_sleep.json"), "w") as f:
        json.dump(build_sleep(epochs, spans), f, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
