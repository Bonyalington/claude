"""tools/gen_fixtures.py: Monkey C replay fixtures from the scripted night."""
import os
import re
import subprocess
import sys

from lucidcue_model.config import Config
from lucidcue_model.night import run_night
from lucidcue_model.sleep_state import ASLEEP, AWAKE, SETTLING
from lucidcue_model.synth import scripted_night

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GEN = os.path.join(ROOT, "tools", "gen_fixtures.py")
COMMITTED = os.path.join(ROOT, "lucidcue", "test", "Fixtures.mc")
NAMES = ["T", "MOTION", "HR", "VAR", "EXP_STATE", "EXP_REM", "EXP_EPISODE", "EXP_FIRE_LEVEL"]
STATE_NUM = {AWAKE: 0, SETTLING: 1, ASLEEP: 2}


def _generate():
    out = subprocess.run([sys.executable, GEN], capture_output=True, text=True, check=True)
    return out.stdout


def _arrays(src):
    """{name: [token, ...]} for every `const NAME = [ ... ];` in the source."""
    arrays = {}
    for m in re.finditer(r"const (\w+) = \[(.*?)\];", src, re.S):
        arrays[m.group(1)] = [tok.strip() for tok in m.group(2).split(",") if tok.strip()]
    return arrays


def _dbl(tok):
    assert tok.endswith("d"), tok
    v = float(tok[:-1])
    return None if v == -1.0 else v


def _expected():
    epochs = scripted_night(0)[0]
    return epochs, run_night(epochs, Config(calibration_mode=False))


def test_is_a_test_module_with_all_arrays():
    src = _generate()
    assert "(:test)\nmodule Fixtures {" in src
    arrays = _arrays(src)
    assert sorted(arrays) == sorted(NAMES)
    for name in NAMES:
        assert len(arrays[name]) == 960, name


def test_epoch_values_round_trip_exactly():
    arrays = _arrays(_generate())
    epochs, _ = _expected()
    assert [int(x) for x in arrays["T"]] == [e.t for e in epochs]
    assert [int(x) for x in arrays["MOTION"]] == [e.motion for e in epochs]
    assert [_dbl(x) for x in arrays["HR"]] == [e.hr_mean for e in epochs]
    assert [_dbl(x) for x in arrays["VAR"]] == [e.hr_var for e in epochs]


def test_expected_outputs_match_run_night():
    arrays = _arrays(_generate())
    _, results = _expected()
    assert [int(x) for x in arrays["EXP_STATE"]] == [STATE_NUM[r.sleep.state] for r in results]
    assert [int(x) for x in arrays["EXP_REM"]] == [1 if r.rem.rem_like else 0 for r in results]
    assert [int(x) for x in arrays["EXP_EPISODE"]] == [r.rem.episode_id for r in results]
    assert [int(x) for x in arrays["EXP_FIRE_LEVEL"]] == [
        r.cue.level if r.cue.fire else 0 for r in results
    ]
    # The night exercises every path the replay test checks.
    assert set(int(x) for x in arrays["EXP_STATE"]) == {0, 1, 2}
    assert any(int(x) > 0 for x in arrays["EXP_FIRE_LEVEL"])


def test_committed_fixtures_are_current():
    with open(COMMITTED) as f:
        assert f.read() == _generate()


def test_replay_split_into_ordered_chunk_tests():
    src = _generate()
    chunk = int(re.search(r"const CHUNK = (\d+);", src).group(1))
    assert chunk == 60
    tests = re.findall(
        r"\(:test\)\nfunction (testReplay\d+)\(logger as Test\.Logger\) as Boolean \{\n"
        r"    return ReplayFix\.runChunk\(logger, (\d+)\);\n\}",
        src,
    )
    n_chunks = (960 + chunk - 1) // chunk
    assert [int(k) for _, k in tests] == list(range(n_chunks))
    names = [name for name, _ in tests]
    assert names == ["testReplay%02d" % k for k in range(n_chunks)]
    assert names == sorted(names)  # name order == declaration order
    assert (n_chunks - 1) * chunk < 960 <= n_chunks * chunk  # chunks cover every epoch
    assert "import Toybox.Test;" in src
