"""Replay tests: the scripted synthetic night run through the full pipeline."""
from lucidcue_model.config import Config, EPISODE_END, EPOCH_SEC
from lucidcue_model.night import EpochResult, run_night
from lucidcue_model.sleep_state import ASLEEP
from lucidcue_model.synth import scripted_night

T0 = 1_760_000_000
CFG = Config()

# A REM episode only ends after EPISODE_END consecutive non-REM-like epochs, so
# a ramp cue may legitimately fire in the one epoch after a REM span ends.
EPISODE_TAIL_SEC = EPISODE_END * EPOCH_SEC


def _night(seed=0):
    epochs, spans, wake_t = scripted_night(seed)
    return epochs, spans, wake_t, run_night(epochs, CFG)


def _fires(results):
    return [r for r in results if r.cue.fire]


def test_scripted_night_shape():
    epochs, spans, wake_t = scripted_night(0)
    assert len(epochs) == 960
    assert epochs[0].t == T0
    assert all(b.t - a.t == EPOCH_SEC for a, b in zip(epochs, epochs[1:]))
    assert len(spans) == 5
    assert all(a < b for a, b in spans)
    assert wake_t == T0 + (20 + 180 + 180) * EPOCH_SEC


def test_run_night_returns_one_result_per_epoch():
    epochs, _, _, results = _night()
    assert len(results) == len(epochs)
    assert all(isinstance(r, EpochResult) for r in results)
    assert [r.epoch for r in results] == epochs


def test_onset_detected_early():
    _, _, _, results = _night()
    first = next(r for r in results if r.sleep.state == ASLEEP)
    assert 600 <= first.sleep.onset_t - T0 <= 2400


def test_bathroom_wake_keeps_onset():
    _, _, _, results = _night()
    asleep = [r for r in results if r.sleep.state == ASLEEP]
    assert asleep[0].sleep.onset_t == asleep[-1].sleep.onset_t
    # The bathroom wake really did drop the state out of ASLEEP in between.
    _, _, wake_t, _ = _night()
    during = [r for r in results if wake_t <= r.epoch.t < wake_t + 10 * EPOCH_SEC]
    assert any(r.sleep.state != ASLEEP for r in during)


def test_no_cues_before_earliest():
    _, _, _, results = _night()
    fires = _fires(results)
    assert fires
    for r in fires:
        assert r.epoch.t - r.sleep.onset_t >= CFG.earliest_cue_hours * 3600


def test_cues_inside_rem_spans():
    _, spans, _, results = _night()
    for r in _fires(results):
        t = r.epoch.t
        assert any(s <= t < e + EPISODE_TAIL_SEC for s, e in spans), t


def test_cue_count_in_bounds():
    _, _, _, results = _night()
    assert 1 <= len(_fires(results)) <= 6


def test_deterministic():
    a = run_night(scripted_night(0)[0], CFG)
    b = run_night(scripted_night(0)[0], CFG)
    assert a == b


def test_seed_changes_jitter():
    assert scripted_night(0)[0] != scripted_night(1)[0]
