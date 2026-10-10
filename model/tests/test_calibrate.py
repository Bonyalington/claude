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
    assert p.returncode == 0, p.stderr + p.stdout
    assert "default hrRise=0.05 varRatio=1.30: precision=" in p.stdout
    assert "best hrRise=" in p.stdout and "NO RECOMMENDATION" not in p.stdout
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


def _short_night(n_epochs):
    night, _ = _load()
    return type(night)(night.start_t, night.epochs[:n_epochs], night.events, night.battery)


def _all_light(night):
    return [(night.epochs[0].t, night.epochs[-1].t + 30, "light")]


def _fake_results(epochs, flagged):
    from types import SimpleNamespace as NS
    return [NS(epoch=e, rem=NS(rem_like=(k in flagged))) for k, e in enumerate(epochs)]


def _fake_night(n_epochs):
    from lucidcue_model.features import Epoch
    from lucidcue_model.logparse import Night
    return Night(0, [Epoch(30 * k, 0, None, None) for k in range(n_epochs)])


def test_grid_search_ties_pick_strictest_cell():
    # No REM in the truth: every cell scores F0.5 = 0. The tie must go to the strictest
    # cell (highest hrRise, then varRatio), never the loosest (0.00, 1.00).
    short = _short_night(40)
    hr, vr, best = grid_search([short], [_all_light(short)], Config())
    assert (hr, vr) == (0.20, 2.0)
    assert best["tp"] == 0 and best["f05"] == 0.0


def test_grid_search_finds_true_maximiser(monkeypatch):
    import calibrate
    night = _fake_night(10)
    stages = [(0, 90, "light"), (90, 180, "rem"), (180, 300, "light")]   # epochs 3..5 REM

    def fake_run_night(epochs, cfg):
        if abs(cfg.hr_rise - 0.07) < 1e-9 and abs(cfg.var_ratio - 1.25) < 1e-9:
            flagged = {3, 4, 5}                 # perfect: F0.5 = 1
        elif cfg.hr_rise < 0.07:
            flagged = {2, 3, 4, 5, 6}           # too loose: precision 0.6
        else:
            flagged = {4}                       # too strict: recall 1/3
        return _fake_results(epochs, flagged)

    monkeypatch.setattr(calibrate, "run_night", fake_run_night)
    hr, vr, best = grid_search([night], [stages], Config())
    assert (round(hr, 2), round(vr, 2)) == (0.07, 1.25)
    assert best["f05"] == 1.0 and best["precision"] == 1.0 and best["tp"] == 3


def test_grid_search_f05_tie_prefers_higher_precision(monkeypatch):
    import calibrate
    night = _fake_night(12)
    stages = [(0, 180, "rem"), (180, 360, "light")]   # epochs 0..5 REM

    def fake_run_night(epochs, cfg):
        if cfg.hr_rise == 0.0:
            flagged = {0, 1}                    # precision 1, recall 1/3: F0.5 = 5/7
        else:
            flagged = set(range(9))             # precision 2/3, recall 1: F0.5 = 5/7
        return _fake_results(epochs, flagged)

    monkeypatch.setattr(calibrate, "run_night", fake_run_night)
    hr, vr, best = grid_search([night], [stages], Config())
    assert (hr, vr) == (0.0, 2.0)
    assert best["precision"] == 1.0


def _write_short_log(path, n_epochs):
    """night_start plus the first n_epochs of the sample night, as D lines."""
    from logwriter import LogWriter
    night, _ = _load()
    w = LogWriter()
    w.event(night.start_t, "night_start", "")
    for e in night.epochs[:n_epochs]:
        w.epoch(e)
    w.flush()
    path.write_text(w.text())


def test_main_all_zero_truth_gives_no_recommendation(tmp_path, capsys):
    import calibrate
    log = tmp_path / "LUCIDCUE.TXT"
    _write_short_log(log, 40)
    night = parse_log(log.read_text())[0]
    sleep = tmp_path / "sleep.json"
    t0, t1, _ = _all_light(night)[0]
    sleep.write_text(json.dumps({"sleepLevels": [
        {"startGMT": _gmt(t0), "endGMT": _gmt(t1), "activityLevel": 1}]}))
    rc = calibrate.main([str(log), str(sleep), "--out", str(tmp_path / "calib")])
    out = capsys.readouterr().out
    assert rc != 0
    assert "NO RECOMMENDATION" in out
    assert "best" not in out
    assert "default hrRise=0.05 varRatio=1.30" in out


def _gmt(t):
    from datetime import datetime, timezone
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.0")


def test_night_stats_counts_epochs_hours_gaps_and_end():
    from calibrate import night_stats
    from lucidcue_model.features import Epoch
    from lucidcue_model.logparse import Night
    n = Night(0, [Epoch(t, 0, None, None) for t in (0, 30, 60, 150, 180)])
    n.events = [(0, "night_start", ""), (210, "night_end", ""), (215, "morning", "")]
    st = night_stats(n)
    assert st["epochs"] == 5
    assert abs(st["hours"] - 210 / 3600) < 1e-12
    assert abs(st["per_hour"] - 5 / (210 / 3600)) < 1e-9
    assert st["gaps"] == 1                     # 60 -> 150 skips two epochs
    assert st["ended"] is True
    n.events = [(0, "night_start", ""), (100, "battery", "80.0")]
    assert night_stats(n)["ended"] is False   # log cut short: no night_end / morning
    empty = night_stats(Night(0))
    assert (empty["epochs"], empty["hours"], empty["per_hour"], empty["gaps"]) == (0, 0.0, 0.0, 0)


def test_main_skips_sleep_file_without_stages(tmp_path, capsys):
    import calibrate
    log = tmp_path / "LUCIDCUE.TXT"
    _write_short_log(log, 40)
    empty = tmp_path / "sleep_empty.json"
    empty.write_text(json.dumps({"sleepLevels": None}))
    missing = tmp_path / "sleep_missing.json"
    missing.write_text("{}")
    rc = calibrate.main([str(log), str(empty), str(missing), "--out", str(tmp_path / "c")])
    out = capsys.readouterr().out
    assert out.count("no sleep stages") == 2 and "skipped" in out
    assert "0 sleep file(s) with stages" in out
    assert "NO RECOMMENDATION" in out and rc != 0
    assert "40 epochs over 0.33 h" in out and "per hour" in out


def test_main_log_check_only_without_sleep_files(tmp_path, capsys):
    import calibrate
    log = tmp_path / "LUCIDCUE.TXT"
    _write_short_log(log, 40)
    rc = calibrate.main([str(log), "--out", str(tmp_path / "c")])
    out = capsys.readouterr().out
    assert rc == 0
    assert "log check only" in out and "40 epochs over 0.33 h" in out
    assert "best" not in out and "NO RECOMMENDATION" not in out

