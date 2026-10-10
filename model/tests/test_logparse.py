"""Log parser and Garmin stage loader."""
import json
import os
from datetime import datetime, timezone

from lucidcue_model.features import Epoch
from lucidcue_model.logparse import STAGE_MAP, Night, load_garmin_stages, parse_log

DATA = os.path.join(os.path.dirname(__file__), "data")


def _read(name):
    with open(os.path.join(DATA, name)) as f:
        return f.read()


def test_parse_single_night_and_skips_truncated():
    text = _read("sample_log.txt")
    nights = parse_log(text)
    assert len(nights) == 1
    n = nights[0]
    assert isinstance(n, Night)
    assert text.splitlines()[-1] == "D,1760028000,H0KUf"   # truncated: skipped
    assert len(n.epochs) == 960
    assert len(n.battery) == 2
    assert n.battery[0][1] == 90.0 and n.battery[1][1] == 84.0
    assert n.start_t == 1_760_000_000
    assert n.epochs[0].t == n.start_t
    assert [e.t for e in n.epochs] == [n.start_t + 30 * k for k in range(960)]
    names = [ev[1] for ev in n.events]
    assert names[:3] == ["night_start", "battery", "caps"]
    assert names[-3:] == ["battery", "night_end", "morning"]
    assert names.count("wouldcue") == 6 and names.count("onset") == 1
    assert (1_760_017_220, "wouldcue", "level=30") in n.events


def test_sample_log_lines_match_watch_format():
    # NightSession.mc: D lines of up to 20 epochs (6 base64url chars each), X lines with
    # 4 fields, nothing else; times non-decreasing in file order.
    import re
    d_line = re.compile(r"^D,\d{10},([A-Za-z0-9_-]{6}){1,20}$")
    lines = _read("sample_log.txt").splitlines()[:-1]    # last line is the truncated one
    assert all(d_line.match(ln) or (ln.startswith("X,") and ln.count(",") == 3)
               for ln in lines)
    full = [ln for ln in lines if ln.startswith("D,") and len(ln.split(",")[2]) == 120]
    assert len(full) > 40
    times = [int(ln.split(",")[1]) for ln in lines]
    assert times == sorted(times)


def test_sample_log_decodes_to_scripted_night():
    # Quantisation: motion to a multiple of 4 below, hr to 0.1, var to 0.01.
    from lucidcue_model.synth import scripted_night
    epochs = scripted_night(0)[0]
    n = parse_log(_read("sample_log.txt"))[0]
    assert len(n.epochs) == len(epochs)
    for a, b in zip(epochs, n.epochs):
        assert a.t == b.t and 0 <= a.motion - b.motion <= 3
        assert (a.hr_mean is None) == (b.hr_mean is None)
        assert (a.hr_var is None) == (b.hr_var is None)
        if a.hr_mean is not None:
            assert abs(a.hr_mean - b.hr_mean) <= 0.05 + 1e-9
        if a.hr_var is not None:
            assert abs(a.hr_var - b.hr_var) <= 0.005 + 1e-9


def test_old_format_e_line_fixture_still_parses():
    # Backward compatibility: a log in the old one-E-line-per-epoch format (excerpt of
    # the old sample_log.txt: 40 E lines, one of them a cue line).
    text = _read("sample_log_old.txt")
    (n,) = parse_log(text)
    assert n.start_t == 1_760_000_000
    assert len(n.epochs) == 41
    assert n.epochs[0] == Epoch(1_760_000_000, 2000, 66.3, 20.52)
    assert n.epochs[-1] == Epoch(1_760_017_220, 100, 58.7, 29.92)
    assert n.epochs[20].hr_mean == 54.5 and n.epochs[20].motion == 100
    assert [ev[1] for ev in n.events] == ["night_start", "battery", "battery", "night_end",
                                          "morning"]
    # The same epochs written in the new format decode to the same values (they are on
    # the quantisation grid: motion multiple of 4, hr 1 decimal, var 2 decimals).
    from logwriter import LogWriter
    w = LogWriter()
    for e in n.epochs:
        w.epoch(e)
    w.flush()
    (m,) = parse_log("X,1760000000,night_start,\n" + w.text())
    assert m.epochs == n.epochs


def test_parse_null_fields():
    text = "X,100,night_start,\nE,100,AWAKE,2000,,,,,0,0,,0\nE,130,ASLEEP,50,60.5,12.3,,,0,0,,0\n"
    n = parse_log(text)[0]
    assert n.epochs[0].hr_mean is None
    assert n.epochs[0].hr_var is None
    assert n.epochs[1].hr_mean == 60.5
    assert n.epochs[1].hr_var == 12.3


def test_two_night_starts_two_nights():
    text = (
        "E,10,AWAKE,1,50.0,5.0,,,0,0,,0\n"            # before first night_start: ignored
        "X,100,night_start,\n"
        "E,100,AWAKE,2000,66.0,20.0,,,0,0,,0\n"
        "X,130,night_end,\n"
        "X,5000,night_start,\r\n"
        "E,5000,ASLEEP,100,55.0,20.0,,,0,0,,0\r\n"
        "E,5030,ASLEEP,100,55.0,20.0,,,0,0,,0\r\n"
    )
    nights = parse_log(text)
    assert len(nights) == 2
    assert nights[0].start_t == 100 and len(nights[0].epochs) == 1
    assert nights[1].start_t == 5000 and len(nights[1].epochs) == 2
    assert [ev[1] for ev in nights[0].events] == ["night_start", "night_end"]


def test_malformed_lines_skipped():
    text = (
        "X,100,night_start,\n"
        "E,100,AWAKE,2000,66.0,20.0,,,0,0,,0\n"
        "E,130,AWAKE,abc,66.0,20.0,,,0,0,,0\n"      # bad motion
        "E,160,AWAKE,10,6x.0,20.0,,,0,0,,0\n"       # bad float
        "E,190,AWAKE,10,66.0,20.0,,,0,0,,0,extra\n"  # too many fields
        "X,200,battery\n"                            # too few fields
        "X,notint,battery,80.0\n"                    # bad t
        "garbage\n"
        "\n"
        "E,220,AWAKE,10,66.0,20.0,,,0,0,,0\n"
    )
    n = parse_log(text)[0]
    assert [e.t for e in n.epochs] == [100, 220]
    assert n.events == [(100, "night_start", "")]


def test_stage_map_and_gmt_parse():
    assert STAGE_MAP == {0: "deep", 1: "light", 2: "rem", 3: "awake"}
    obj = json.loads(_read("sample_sleep.json"))
    stages = load_garmin_stages(obj)
    first = obj["sleepLevels"][0]
    t0 = int(datetime.strptime(first["startGMT"], "%Y-%m-%dT%H:%M:%S.0")
             .replace(tzinfo=timezone.utc).timestamp())
    assert t0 == 1_760_000_000
    assert stages[0][0] == t0 and stages[0][2] == "light"
    assert all(isinstance(s[0], int) and isinstance(s[1], int) for s in stages)
    assert any(s[2] == "rem" for s in stages)


def test_gmt_without_fraction():
    obj = {"sleepLevels": [{"startGMT": "2026-10-10T03:15:00", "endGMT": "2026-10-10T03:45:00.0",
                            "activityLevel": 2}]}
    (s,) = load_garmin_stages(obj)
    assert s == (1_791_602_100, 1_791_603_900, "rem")


def test_missing_or_null_sleep_levels_gives_no_stages():
    assert load_garmin_stages({}) == []
    assert load_garmin_stages({"sleepLevels": None}) == []
    assert load_garmin_stages({"sleepLevels": []}) == []


def test_gmt_with_z_or_utc_offset():
    for start, end in [("2026-10-10T03:15:00Z", "2026-10-10T03:45:00.0Z"),
                       ("2026-10-10T03:15:00+00:00", "2026-10-10T03:45:00.000+00:00")]:
        obj = {"sleepLevels": [{"startGMT": start, "endGMT": end, "activityLevel": 2}]}
        (s,) = load_garmin_stages(obj)
        assert s == (1_791_602_100, 1_791_603_900, "rem")
