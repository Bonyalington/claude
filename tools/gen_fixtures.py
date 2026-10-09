"""Generate the Monkey C replay fixtures from the Python reference model.

Steps scripted_night(0)[0] through SleepStateMachine, RemDetector and CueController
(Config(calibration_mode=False)), in the same order as night.py run_night, and prints a
`(:test) module Fixtures` Monkey C source holding the inputs, the expected outputs, and
a checkpoint of every unit's internal state at the start of each replay chunk.

Each generated test testReplayNN restores fresh Monkey C units from chunk NN's
checkpoint and replays only that chunk, so the chunks are independent (the Connect IQ
test runner resets module state between test functions).

Usage (from the repo root):
  .venv/bin/python tools/gen_fixtures.py > lucidcue/test/Fixtures.mc
"""
import os
import sys
import textwrap
from collections import deque

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "model"))

from lucidcue_model.config import BASE_EPOCHS, Config  # noqa: E402
from lucidcue_model.cue import CueController  # noqa: E402
from lucidcue_model.night import EpochResult  # noqa: E402
from lucidcue_model.rem import RemDetector  # noqa: E402
from lucidcue_model.sleep_state import ASLEEP, AWAKE, SETTLING, SleepStateMachine  # noqa: E402
from lucidcue_model.synth import scripted_night  # noqa: E402

# Matches the Monkey C enum in SleepStateMachine.mc.
STATE_NUM = {AWAKE: 0, SETTLING: 1, ASLEEP: 2}
NULL_DBL = "-1.0d"
NULL_NUM = "-1"
PER_LINE = 10
# Epochs per generated replay test (ReplayFix.runChunk). Halve it and regenerate if a
# replay test trips the watchdog ("Code Executed Too Long").
CHUNK = 60

# Checkpoint layout: (Python attribute, kind), in the order the Monkey C restore()
# methods take them. Kinds: "state" (STATE_NUM), "int", "int?" (-1 = None),
# "float", "float?" (-1.0d = None), "bool" (1 / 0).
SM_FIELDS = [
    ("state", "state"),
    ("onset_t", "int?"),
    ("epoch_index", "int"),
    ("ref_sum", "float"),
    ("ref_count", "int"),
    ("ref", "float?"),
    ("wake_run", "int"),
    ("wake_run_start_t", "int"),
    ("awake_since", "int?"),
    ("onset_run", "int"),
    ("run_start_t", "int"),
]
RD_FIELDS = [
    ("still_run", "int"),
    ("rem_run", "int"),
    ("non_rem_run", "int"),
    ("episode_active", "bool"),
    ("episode_id", "int"),
]
RD_HR = "base_hr"    # deque of float, emitted oldest -> newest ("float")
RD_VAR = "base_var"  # deque of float or None, emitted oldest -> newest ("float?")
CC_FIELDS = [
    ("base_level", "int"),
    ("cooldown", "int"),
    ("last_cue_t", "int?"),
    ("pending_reaction", "bool"),
    ("last_cue_absorbed", "bool"),
    ("cur_episode_id", "int"),
    ("cues_in_episode", "int"),
    ("finished_episode_id", "int?"),
    ("_cues_tonight", "int"),
    ("_wakes_after_cue", "int"),
]
CC_LOG = "_cue_log"  # list of (t, level), emitted flat: t0, level0, t1, level1, ...


# --- Snapshot / restore (the Python side of the Monkey C restore() methods) ---------

def snapshot(sm: SleepStateMachine, rd: RemDetector, cc: CueController) -> dict:
    """Every internal field of the three units (all but cfg), as plain values."""
    return {
        "sm": {name: getattr(sm, name) for name, _ in SM_FIELDS},
        "rd": dict(
            {name: getattr(rd, name) for name, _ in RD_FIELDS},
            **{RD_HR: list(rd.base_hr), RD_VAR: list(rd.base_var)},
        ),
        "cc": dict(
            {name: getattr(cc, name) for name, _ in CC_FIELDS},
            **{CC_LOG: list(cc._cue_log)},
        ),
    }


def restore(snap: dict, cfg: Config):
    """Fresh units with every field of `snap` written back. Does not change any rule."""
    sm, rd, cc = SleepStateMachine(cfg), RemDetector(cfg), CueController(cfg)
    for name, value in snap["sm"].items():
        setattr(sm, name, value)
    for name, value in snap["rd"].items():
        if name in (RD_HR, RD_VAR):
            value = deque(value, maxlen=BASE_EPOCHS)
        setattr(rd, name, value)
    for name, value in snap["cc"].items():
        setattr(cc, name, [tuple(p) for p in value] if name == CC_LOG else value)
    return sm, rd, cc


def step(units, e) -> EpochResult:
    """One epoch through the three units, exactly as night.py run_night."""
    sm, rd, cc = units
    s = sm.step(e)
    r = rd.step(e, s)
    c = cc.step(e, s, r)
    return EpochResult(e, s, r, c)


def replay(epochs, cfg):
    """(results, snapshots, end_cues): run_night's results, the snapshot taken before
    epoch k * CHUNK for each chunk k, and cues_tonight after each chunk's last epoch."""
    units = (SleepStateMachine(cfg), RemDetector(cfg), CueController(cfg))
    results, snaps, end_cues = [], [], []
    for i, e in enumerate(epochs):
        if i % CHUNK == 0:
            snaps.append(snapshot(*units))
        results.append(step(units, e))
        if (i + 1) % CHUNK == 0 or i + 1 == len(epochs):
            end_cues.append(units[2].cues_tonight)
    return results, snaps, end_cues


# --- Monkey C literals ---------------------------------------------------------------

def dbl(v):
    """Monkey C Double literal. repr() is the shortest string that round-trips exactly."""
    if v is None:
        return NULL_DBL
    s = repr(float(v))
    # Real HR / variability values are non-negative plain decimals; -1.0d is reserved for
    # null, and exponent forms are avoided so the literal syntax stays simple.
    assert v >= 0.0 and "e" not in s and "n" not in s and "." in s, s
    return s + "d"


def num(v):
    """Monkey C Number literal for a non-negative int that fits in 32 bits."""
    assert type(v) is int and 0 <= v < 2 ** 31, v
    return str(v)


def encode(value, kind):
    if kind == "state":
        return str(STATE_NUM[value])
    if kind == "int":
        return num(value)
    if kind == "int?":
        return NULL_NUM if value is None else num(value)
    if kind == "float":
        assert value is not None
        return dbl(value)
    if kind == "float?":
        return dbl(value)
    if kind == "bool":
        assert type(value) is bool, value
        return "1" if value else "0"
    raise ValueError(kind)


def snapshot_rows(snap: dict) -> dict:
    """{Fixtures array name: tokens} for one checkpoint."""
    rd, cc = snap["rd"], snap["cc"]
    assert len(rd[RD_HR]) == len(rd[RD_VAR]) <= BASE_EPOCHS
    return {
        "SNAP_SM": [encode(snap["sm"][name], kind) for name, kind in SM_FIELDS],
        "SNAP_RD": [encode(rd[name], kind) for name, kind in RD_FIELDS],
        "SNAP_BASE_HR": [encode(v, "float") for v in rd[RD_HR]],
        "SNAP_BASE_VAR": [encode(v, "float?") for v in rd[RD_VAR]],
        "SNAP_CC": [encode(cc[name], kind) for name, kind in CC_FIELDS],
        "SNAP_CUE_LOG": [num(x) for t, level in cc[CC_LOG] for x in (t, level)],
    }


def _wrap(tokens, indent):
    lines = []
    for i in range(0, len(tokens), PER_LINE):
        lines.append(indent + ", ".join(tokens[i:i + PER_LINE]) + ",")
    if lines:
        lines[-1] = lines[-1][:-1]  # no trailing comma after the last element
    return lines


def _const(name, tokens, comment):
    lines = ["    // %s" % comment, "    const %s = [" % name]
    lines += _wrap(tokens, "        ")
    lines.append("    ];")
    return "\n".join(lines)


def _nested_const(name, rows, comment):
    """const NAME = [ row for chunk 0, row for chunk 1, ... ]; each row an array."""
    lines = ["    // %s" % line for line in comment] + ["    const %s = [" % name]
    for k, toks in enumerate(rows):
        sep = "," if k + 1 < len(rows) else ""
        if len(toks) <= 12:  # a checkpoint row (or a short cue log) stays on one line
            lines.append("        [%s]%s" % (", ".join(toks), sep))
        else:
            lines.append("        [")
            lines += _wrap(toks, "            ")
            lines.append("        ]" + sep)
    lines.append("    ];")
    return "\n".join(lines)


def _fields(fields, tail=""):
    """Comment lines naming the fields in checkpoint order."""
    text = ", ".join(name.lstrip("_") for name, _ in fields) + tail
    return textwrap.wrap(text, 88)


SNAP_COMMENTS = {
    "SNAP_SM": [
        "SleepStateMachine checkpoint per chunk, for SleepStateMachine.restore():",
        *_fields(SM_FIELDS, "."),
        "state uses the STATE_ numbers; -1 / -1.0d = null.",
    ],
    "SNAP_RD": [
        "RemDetector checkpoint per chunk (with SNAP_BASE_HR / SNAP_BASE_VAR):",
        *_fields(RD_FIELDS, "; episode_active 1 = true."),
    ],
    "SNAP_BASE_HR": [
        "RemDetector baseline window per chunk: hr_mean, oldest -> newest (deque order).",
    ],
    "SNAP_BASE_VAR": [
        "RemDetector baseline window per chunk: hr_var, oldest -> newest; -1.0d = null.",
    ],
    "SNAP_CC": [
        "CueController checkpoint per chunk (with SNAP_CUE_LOG), for CueController.restore():",
        *_fields(CC_FIELDS, "."),
        "Booleans 1 = true; -1 = null.",
    ],
    "SNAP_CUE_LOG": [
        "CueController cue log per chunk, flat: t0, level0, t1, level1, ...",
    ],
}


def chunk_count(n: int) -> int:
    return (n + CHUNK - 1) // CHUNK


def _replay_tests(n):
    """One global test per chunk; zero-padded names so name order == declaration order."""
    width = max(2, len(str(chunk_count(n) - 1)))
    out = [
        "// Independent replay chunks; see ReplayTest.mc. Each one restores the units from",
        "// its checkpoint, so any chunk can run on its own or in any order.",
    ]
    for k in range(chunk_count(n)):
        out += [
            "(:test)",
            "function testReplay%0*d(logger as Test.Logger) as Boolean {" % (width, k),
            "    return ReplayFix.runChunk(logger, %d);" % k,
            "}",
            "",
        ]
    return "\n".join(out).rstrip("\n")


def generate() -> str:
    epochs = scripted_night(0)[0]
    results, snaps, end_cues = replay(epochs, Config(calibration_mode=False))
    assert len(snaps) == len(end_cues) == chunk_count(len(results))
    arrays = [
        ("T", [num(r.epoch.t) for r in results], "Epoch start, Unix seconds."),
        ("MOTION", [num(r.epoch.motion) for r in results], "Motion score (mg)."),
        ("HR", [dbl(r.epoch.hr_mean) for r in results], "HR mean; -1.0d = null."),
        ("VAR", [dbl(r.epoch.hr_var) for r in results], "HR variability; -1.0d = null."),
        ("EXP_STATE", [str(STATE_NUM[r.sleep.state]) for r in results],
         "Expected sleep state (STATE_AWAKE=0, STATE_SETTLING=1, STATE_ASLEEP=2)."),
        ("EXP_REM", ["1" if r.rem.rem_like else "0" for r in results],
         "Expected rem_like (1 = true)."),
        ("EXP_EPISODE", [str(r.rem.episode_id) for r in results], "Expected REM episode id."),
        ("EXP_FIRE_LEVEL", [str(r.cue.level if r.cue.fire else 0) for r in results],
         "Expected cue level when the cue fires; 0 = no fire."),
        ("END_CUES", [num(c) for c in end_cues],
         "Expected cues_tonight after each chunk's last epoch."),
    ]
    rows = [snapshot_rows(s) for s in snaps]
    parts = [
        "// GENERATED by tools/gen_fixtures.py -- do not edit by hand.",
        "// Regenerate: .venv/bin/python tools/gen_fixtures.py > lucidcue/test/Fixtures.mc",
        "// Source: scripted_night(0)[0] stepped as run_night with Config(calibration_mode=False),",
        "// %d epochs. SNAP_* hold each unit's state before epoch k * CHUNK (row k = chunk k)."
        % len(results),
        "import Toybox.Lang;",
        "import Toybox.Test;",
        "",
        "(:test)",
        "module Fixtures {",
        "    // Epochs per replay test (halve and regenerate if the watchdog trips).",
        "    const CHUNK = %d;" % CHUNK,
        "",
    ]
    blocks = [_const(name, toks, comment) for name, toks, comment in arrays]
    blocks += [_nested_const(name, [r[name] for r in rows], SNAP_COMMENTS[name])
               for name in SNAP_COMMENTS]
    parts.append("\n\n".join(blocks))
    parts.append("}")
    parts.append("")
    parts.append(_replay_tests(len(results)))
    return "\n".join(parts) + "\n"


if __name__ == "__main__":
    sys.stdout.write(generate())
