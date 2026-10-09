"""tools/gen_fixtures.py: Monkey C replay fixtures and per-chunk checkpoints."""
import ast
import os
import re
import subprocess
import sys
from collections import deque

import pytest

from lucidcue_model.config import BASE_EPOCHS, Config
from lucidcue_model.cue import CueController
from lucidcue_model.night import run_night
from lucidcue_model.rem import RemDetector
from lucidcue_model.sleep_state import ASLEEP, AWAKE, SETTLING, SleepStateMachine
from lucidcue_model.synth import scripted_night

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GEN = os.path.join(ROOT, "tools", "gen_fixtures.py")
COMMITTED = os.path.join(ROOT, "lucidcue", "test", "Fixtures.mc")
SOURCE = os.path.join(ROOT, "lucidcue", "source")
sys.path.insert(0, os.path.join(ROOT, "tools"))

import gen_fixtures as gf  # noqa: E402

N = 960
EPOCH_NAMES = ["T", "MOTION", "HR", "VAR", "EXP_STATE", "EXP_REM", "EXP_EPISODE",
               "EXP_FIRE_LEVEL"]
SNAP_NAMES = ["SNAP_SM", "SNAP_RD", "SNAP_BASE_HR", "SNAP_BASE_VAR", "SNAP_CC",
              "SNAP_CUE_LOG"]
STATE_NUM = {AWAKE: 0, SETTLING: 1, ASLEEP: 2}
NUM_STATE = {v: k for k, v in STATE_NUM.items()}
CFG = Config(calibration_mode=False)


@pytest.fixture(scope="module")
def src():
    out = subprocess.run([sys.executable, GEN], capture_output=True, text=True, check=True)
    return out.stdout


@pytest.fixture(scope="module")
def consts(src):
    return _consts(src)


@pytest.fixture(scope="module")
def night():
    """The uninterrupted run: (epochs, results, snapshot before every epoch and at end)."""
    epochs = scripted_night(0)[0]
    units = (SleepStateMachine(CFG), RemDetector(CFG), CueController(CFG))
    results, snaps = [], []
    for e in epochs:
        snaps.append(gf.snapshot(*units))
        results.append(gf.step(units, e))
    snaps.append(gf.snapshot(*units))
    return epochs, results, snaps


# --- Parsing the emitted Monkey C ----------------------------------------------------

def _values(text):
    """Python values for Monkey C literals: `61.5d` -> 61.5, nested [...] -> lists."""
    # Every literal with a decimal point must carry the Double suffix.
    assert not re.search(r"\d\.\d+(?![\dd])", text), "Double literal without d suffix"
    return ast.literal_eval("[" + re.sub(r"(?<=\d)d\b", "", text) + "]")


def _consts(src):
    """{name: list} for every `const NAME = [ ... ];` (flat or nested) in the source."""
    return {m.group(1): _values(m.group(2))
            for m in re.finditer(r"const (\w+) = \[(.*?)\n    \];", src, re.S)}


def _decode(value, kind):
    """Mirror of ReplayFix's decoding of a checkpoint value."""
    if kind == "state":
        return NUM_STATE[value]
    if kind == "int":
        assert type(value) is int and value >= 0, value
        return value
    if kind == "int?":
        assert type(value) is int and value >= -1, value
        return None if value == -1 else value
    if kind == "float":
        assert type(value) is float and value >= 0.0, value
        return value
    if kind == "float?":
        assert type(value) is float and (value >= 0.0 or value == -1.0), value
        return None if value == -1.0 else value
    if kind == "bool":
        return {0: False, 1: True}[value]
    raise ValueError(kind)


def _decode_snapshot(row):
    """A snapshot dict from one chunk's decoded rows {SNAP_NAME: list}."""
    log = row["SNAP_CUE_LOG"]
    assert len(log) % 2 == 0
    return {
        "sm": {name: _decode(v, kind)
               for (name, kind), v in zip(gf.SM_FIELDS, row["SNAP_SM"], strict=True)},
        "rd": dict(
            {name: _decode(v, kind)
             for (name, kind), v in zip(gf.RD_FIELDS, row["SNAP_RD"], strict=True)},
            **{gf.RD_HR: [_decode(v, "float") for v in row["SNAP_BASE_HR"]],
               gf.RD_VAR: [_decode(v, "float?") for v in row["SNAP_BASE_VAR"]]},
        ),
        "cc": dict(
            {name: _decode(v, kind)
             for (name, kind), v in zip(gf.CC_FIELDS, row["SNAP_CC"], strict=True)},
            **{gf.CC_LOG: [(log[j], log[j + 1]) for j in range(0, len(log), 2)]},
        ),
    }


def _round_trip(snap):
    """snap -> emitted literals -> parsed -> decoded, as the Monkey C replay sees it."""
    rows = gf.snapshot_rows(snap)
    return _decode_snapshot({name: _values(", ".join(toks)) for name, toks in rows.items()})


def _unit_fields(unit):
    return set(vars(unit)) - {"cfg"}


# --- Per-epoch arrays (unchanged) ----------------------------------------------------

def test_is_a_test_module_with_all_arrays(src, consts):
    assert "(:test)\nmodule Fixtures {" in src
    assert sorted(consts) == sorted(EPOCH_NAMES + SNAP_NAMES + ["END_CUES"])
    for name in EPOCH_NAMES:
        assert len(consts[name]) == N, name
    n_chunks = gf.chunk_count(N)
    for name in SNAP_NAMES + ["END_CUES"]:
        assert len(consts[name]) == n_chunks, name


def test_epoch_values_round_trip_exactly(consts, night):
    epochs, _, _ = night
    dbl = lambda v: None if v == -1.0 else v  # noqa: E731
    assert consts["T"] == [e.t for e in epochs]
    assert consts["MOTION"] == [e.motion for e in epochs]
    assert [dbl(x) for x in consts["HR"]] == [e.hr_mean for e in epochs]
    assert [dbl(x) for x in consts["VAR"]] == [e.hr_var for e in epochs]


def test_expected_outputs_match_run_night(consts, night):
    epochs, _, _ = night
    results = run_night(epochs, CFG)
    assert consts["EXP_STATE"] == [STATE_NUM[r.sleep.state] for r in results]
    assert consts["EXP_REM"] == [1 if r.rem.rem_like else 0 for r in results]
    assert consts["EXP_EPISODE"] == [r.rem.episode_id for r in results]
    assert consts["EXP_FIRE_LEVEL"] == [r.cue.level if r.cue.fire else 0 for r in results]
    # The night exercises every path the replay test checks.
    assert set(consts["EXP_STATE"]) == {0, 1, 2}
    fires = sum(1 for x in consts["EXP_FIRE_LEVEL"] if x > 0)
    assert fires > 0
    # END_CUES: cues_tonight after each chunk; the last equals the night's fires.
    assert consts["END_CUES"] == [
        sum(1 for r in results[:min(N, (k + 1) * gf.CHUNK)] if r.cue.fire)
        for k in range(gf.chunk_count(N))
    ]
    assert consts["END_CUES"][-1] == fires


def test_committed_fixtures_are_current(src):
    with open(COMMITTED) as f:
        assert f.read() == src


def test_replay_split_into_independent_chunk_tests(src):
    chunk = int(re.search(r"const CHUNK = (\d+);", src).group(1))
    # Follows the generator's constant, so SETUP's "halve CHUNK" stays green.
    assert chunk == gf.CHUNK
    assert 1 <= chunk <= N
    tests = re.findall(
        r"\(:test\)\nfunction (testReplay\d+)\(logger as Test\.Logger\) as Boolean \{\n"
        r"    return ReplayFix\.runChunk\(logger, (\d+)\);\n\}",
        src,
    )
    n_chunks = (N + chunk - 1) // chunk
    assert [int(k) for _, k in tests] == list(range(n_chunks))
    names = [name for name, _ in tests]
    assert names == ["testReplay%02d" % k for k in range(n_chunks)]
    assert names == sorted(names)
    assert (n_chunks - 1) * chunk < N <= n_chunks * chunk  # chunks cover every epoch
    assert "import Toybox.Test;" in src


# --- Checkpoints ---------------------------------------------------------------------

def test_snapshot_covers_every_field(night):
    """Every attribute the units set (but cfg) is in the checkpoint, and nothing else.
    A field added to a model class later fails here until the checkpoint carries it."""
    _, _, snaps = night
    units = (SleepStateMachine(CFG), RemDetector(CFG), CueController(CFG))
    for key, unit in zip(("sm", "rd", "cc"), units):
        assert set(snaps[0][key]) == _unit_fields(unit), key
        assert set(snaps[-1][key]) == _unit_fields(unit), key
    # restore() writes every checkpoint field onto fresh units.
    restored = gf.restore(snaps[-1], CFG)
    for key, unit in zip(("sm", "rd", "cc"), restored):
        assert {k: getattr(unit, k) for k in snaps[-1][key]} == {
            k: (deque(v, maxlen=BASE_EPOCHS) if k in (gf.RD_HR, gf.RD_VAR)
                else ([tuple(p) for p in v] if k == gf.CC_LOG else v))
            for k, v in snaps[-1][key].items()
        }
    assert restored[1].base_hr.maxlen == restored[1].base_var.maxlen == BASE_EPOCHS


def test_emitted_checkpoints_decode_to_the_snapshots(consts, night):
    _, _, snaps = night
    for k in range(gf.chunk_count(N)):
        row = {name: consts[name][k] for name in SNAP_NAMES}
        assert _decode_snapshot(row) == snaps[k * gf.CHUNK], k


def test_each_chunk_replays_alone_from_its_checkpoint(consts, night):
    """The parity proof for ReplayFix.runChunk: fresh units restored from chunk k's
    emitted checkpoint replay that chunk exactly as the uninterrupted night does, and
    end in the state the next checkpoint (or the end of the night) records."""
    epochs, results, snaps = night
    for k in range(gf.chunk_count(N)):
        row = {name: consts[name][k] for name in SNAP_NAMES}
        units = gf.restore(_decode_snapshot(row), CFG)
        start, end = k * gf.CHUNK, min(N, (k + 1) * gf.CHUNK)
        for i in range(start, end):
            assert gf.step(units, epochs[i]) == results[i], (k, i)
        assert gf.snapshot(*units) == snaps[end], k
        assert units[2].cues_tonight == consts["END_CUES"][k], k


def test_restore_at_every_epoch_matches(night):
    """Stronger than the chunk boundaries (where e.g. no episode is active and no cue
    reaction is pending): restoring the round-tripped checkpoint before any epoch and
    stepping it gives the same result and the same next state."""
    epochs, results, snaps = night
    for i, e in enumerate(epochs):
        units = gf.restore(_round_trip(snaps[i]), CFG)
        assert gf.step(units, e) == results[i], i
        assert gf.snapshot(*units) == snaps[i + 1], i


def test_checkpoints_cover_interesting_states(night):
    """The per-epoch restore test above passes through every non-default value."""
    _, _, snaps = night
    seen = lambda key, name: {s[key][name] for s in snaps}  # noqa: E731
    assert seen("rd", "episode_active") == {False, True}
    assert seen("cc", "pending_reaction") == {False, True}
    assert seen("cc", "last_cue_absorbed") == {False, True}
    assert None in seen("cc", "finished_episode_id") and len(seen("cc", "finished_episode_id")) > 1
    assert {len(s["rd"][gf.RD_HR]) for s in snaps} >= {0, BASE_EPOCHS}


# --- Monkey C restore() mirrors the checkpoint field for field -----------------------

def _camel(name):
    parts = name.strip("_").split("_")
    return "".join(p.capitalize() for p in parts)


def _restore_source(filename):
    with open(os.path.join(SOURCE, filename)) as f:
        text = f.read()
    m = re.search(r"function restore\((.*?)\) as Void \{(.*?)\n    \}", text, re.S)
    assert m, filename
    params = [p.split(" as ")[0].strip() for p in re.split(r",\s*(?=a[A-Z])", m.group(1))]
    return params, m.group(2)


@pytest.mark.parametrize("filename, fields, extra_first, extra_last", [
    ("SleepStateMachine.mc", gf.SM_FIELDS, [], []),
    ("RemDetector.mc", gf.RD_FIELDS, [gf.RD_HR, gf.RD_VAR], []),
    ("CueController.mc", gf.CC_FIELDS, [], [gf.CC_LOG]),
])
def test_monkey_c_restore_takes_every_checkpoint_field(filename, fields, extra_first,
                                                       extra_last):
    params, body = _restore_source(filename)
    names = extra_first + [name for name, _ in fields] + extra_last
    assert params == ["a" + _camel(n) for n in names]
    for name, _ in fields:  # scalar fields are assigned straight from their parameter
        assert re.search(r"\bm%s = a%s;" % (_camel(name), _camel(name)), body), name
