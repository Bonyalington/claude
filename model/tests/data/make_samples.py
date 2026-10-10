"""Regenerate sample_log.txt and sample_sleep.json from scripted_night(0) + run_night.

The log uses the watch's compact format (spec §4.7, NightLog.mc / NightSession.mc),
written by the Python mirror in tests/logwriter.py: D lines of 20 epochs, X lines for
events (wouldcue, reactions, onset, caps), and the night ends with night_end then
morning. A truncated D line is appended last (the parser must skip it).

sample_log_old.txt is a hand-kept excerpt of the old one-E-line-per-epoch format (for the
backward-compatibility test); this script does not write it.

Run from the model/ directory:  ../.venv/bin/python tests/data/make_samples.py
"""
import json
import os
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, ".."))

from lucidcue_model.config import Config  # noqa: E402
from lucidcue_model.night import run_night  # noqa: E402
from lucidcue_model.synth import scripted_night  # noqa: E402
from logwriter import write_night  # noqa: E402


def gmt(t):
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.0")


def build_log(results):
    # Config() is a calibration night, so fires are logged as wouldcue.
    w = write_night(results, calibration=True)
    w.lines.append("D,1760028000,H0KUf")  # truncated final line
    return w.text()


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
