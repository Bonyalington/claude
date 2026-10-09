"""Scoring and grid search on the scripted night."""
import json
import os
import subprocess
import sys
from dataclasses import replace

from lucidcue_model.config import Config
from lucidcue_model.logparse import load_garmin_stages, parse_log
from lucidcue_model.night import run_night

DATA = os.path.join(os.path.dirname(__file__), "data")
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from calibrate import grid_search, score  # noqa: E402


def _load():
    with open(os.path.join(DATA, "sample_log.txt")) as f:
        night = parse_log(f.read())[0]
    with open(os.path.join(DATA, "sample_sleep.json")) as f:
        stages = load_garmin_stages(json.load(f))
    return night, stages


def test_score_on_scripted_night():
    night, stages = _load()
    res = run_night(night.epochs, Config())
    s = score(res, stages)
    assert s["precision"] >= 0.6
    assert s["recall"] > 0.0
    assert s["tp"] > 0
    assert 0.0 <= s["f05"] <= 1.0


def test_score_exact_values():
    night, _ = _load()
    res = run_night(night.epochs[:4], Config())   # rem_like all False
    t = res[0].epoch.t
    # Two epochs truth-REM (missed), two truth-light; epoch 3 uncovered -> excluded.
    stages = [(t, t + 60, "rem"), (t + 60, t + 90, "light")]
    s = score(res, stages)
    assert (s["tp"], s["fp"], s["fn"]) == (0, 0, 2)
    assert s["precision"] == 0.0 and s["recall"] == 0.0 and s["f05"] == 0.0


def test_score_f05_formula():
    night, stages = _load()
    s = score(run_night(night.epochs, Config()), stages)
    p, r = s["precision"], s["recall"]
    assert abs(s["f05"] - 1.25 * p * r / (0.25 * p + r)) < 1e-12


def test_grid_search_returns_in_range():
    night, stages = _load()
    short = type(night)(night.start_t, night.epochs[:300], night.events, night.battery)
    hr, vr, best = grid_search([short], [stages], Config())
    assert 0.0 <= hr <= 0.2
    assert 1.0 <= vr <= 2.0
    assert set(best) >= {"precision", "recall", "f05"}


def test_grid_search_skips_nights_without_stages():
    night, stages = _load()
    short = type(night)(night.start_t, night.epochs[:200], night.events, night.battery)
    a = grid_search([short], [stages], Config())
    b = grid_search([short, short], [stages, None], Config())
    assert a == b


def test_cli_smoke(tmp_path):
    out = tmp_path / "calib"
    p = subprocess.run(
        [sys.executable, os.path.join(ROOT, "tools", "calibrate.py"),
         os.path.join(DATA, "sample_log.txt"), os.path.join(DATA, "sample_sleep.json"),
         "--out", str(out)],
        capture_output=True, text=True, timeout=600)
    assert p.returncode == 0, p.stderr
    assert "hrRise" in p.stdout and "varRatio" in p.stdout
    assert len(list(out.glob("*.png"))) == 1


def test_match_stages_picks_largest_overlap_and_none():
    from lucidcue_model.features import Epoch
    from lucidcue_model.logparse import Night
    from calibrate import match_stages, battery_drop, percentile

    n1 = Night(0, [Epoch(0, 0, None, None), Epoch(30, 0, None, None)])
    n2 = Night(10_000, [Epoch(10_000, 0, None, None), Epoch(10_030, 0, None, None)])
    n3 = Night(50_000, [Epoch(50_000, 0, None, None)])
    a = [(0, 60, "light")]
    b = [(10_000, 10_030, "rem"), (0, 10, "rem")]
    out = match_stages([n1, n2, n3], [a, b])
    assert out == [a, b, None]
    assert battery_drop(n1) is None
    n1.battery = [(0, 90.0), (5, 87.5), (9, 84.0)]
    assert battery_drop(n1) == 6.0
    assert [percentile(list(range(101)), p) for p in (50, 90, 99)] == [50, 90, 99]
