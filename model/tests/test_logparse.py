"""Log parser and Garmin stage loader."""
import json
import os
from datetime import datetime, timezone

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
    e_lines = [ln for ln in text.splitlines() if ln.startswith("E,")]
    assert len(n.epochs) == len(e_lines) - 1
    assert len(n.battery) == 2
    assert n.battery[0][1] == 90.0 and n.battery[1][1] == 84.0
    assert n.start_t == 1_760_000_000
    assert n.epochs[0].t == n.start_t
    assert [ev[1] for ev in n.events] == ["night_start", "battery", "battery"]


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
