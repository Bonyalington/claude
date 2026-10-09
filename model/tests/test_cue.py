from dataclasses import replace

from lucidcue_model.config import Config
from lucidcue_model.features import Epoch
from lucidcue_model.sleep_state import AWAKE, ASLEEP, SleepStatus
from lucidcue_model.rem import RemStatus
from lucidcue_model.cue import CueController

T0 = 1_760_000_000
H = int(4.5 * 3600)
T = T0 + H  # time of the first cue
S_OK = SleepStatus(ASLEEP, T0)


def rem(ep_id, active=True):
    return RemStatus(True, active, ep_id, 55.0, 20.0)


def quiet(t):
    return Epoch(t, 100, 55.0, 20.0)


def step(c, t, ep_id=1, active=True, s=S_OK, motion=100, hr=55.0):
    return c.step(Epoch(t, motion, hr, 20.0), s, rem(ep_id, active))


def test_no_cue_before_earliest():
    c = CueController(Config())
    assert step(c, T - 30).fire is False
    d = step(c, T)
    assert d.fire is True
    assert d.level == 30


def test_requires_active_episode_and_asleep():
    c = CueController(Config())
    assert step(c, T, active=False).fire is False
    assert step(c, T + 30, s=SleepStatus(AWAKE, T0)).fire is False
    assert c.cues_tonight == 0


def test_ramp_within_episode():
    c = CueController(Config())
    d = step(c, T)
    assert (d.fire, d.level) == (True, 30)
    d = step(c, T + 30)
    assert d.fire is False
    assert d.event == "absorbed"
    d = step(c, T + 120)
    assert (d.fire, d.level) == (True, 45)
    d = step(c, T + 240)
    assert (d.fire, d.level) == (True, 60)
    assert step(c, T + 360).fire is False
    assert c.cues_tonight == 3


def test_new_episode_respects_cooldown():
    c = CueController(Config())
    assert step(c, T).fire is True
    assert step(c, T + 30).event == "absorbed"
    assert step(c, T + 300, ep_id=2).fire is False
    assert step(c, T + 570, ep_id=2).fire is False
    d = step(c, T + 600, ep_id=2)
    assert (d.fire, d.level) == (True, 30)


def test_max_cues_per_night():
    c = CueController(replace(Config(), max_cues_per_night=2))
    assert step(c, T).fire is True
    step(c, T + 30)
    assert step(c, T + 120).fire is True
    step(c, T + 150)
    assert step(c, T + 240).fire is False
    assert step(c, T + 360).fire is False
    assert c.cues_tonight == 2


def test_wake_after_cue_motion_backs_off():
    c = CueController(Config())
    assert step(c, T).fire is True
    d = step(c, T + 30, motion=6000)
    assert d.event == "wake_after_cue"
    assert d.fire is False
    assert step(c, T + 240).fire is False  # same episode is finished
    assert step(c, T + 900, ep_id=2).fire is False
    d = step(c, T + 1230, ep_id=2)
    assert (d.fire, d.level) == (True, 15)
    assert c.wakes_after_cue == 1


def test_wake_after_cue_hr_jump():
    c = CueController(Config())
    assert step(c, T).fire is True
    assert step(c, T + 30, hr=63.3).event == "wake_after_cue"
    c = CueController(Config())
    assert step(c, T).fire is True
    assert step(c, T + 30, hr=63.2).event == "absorbed"


def test_event_only_for_epoch_after_cue():
    c = CueController(Config())
    assert step(c, T - 30).event is None
    assert step(c, T).event is None
    assert step(c, T + 30).event == "absorbed"
    assert step(c, T + 60).event is None


def test_missing_hr_is_not_a_wake():
    c = CueController(Config())
    assert step(c, T).fire is True
    d = c.step(Epoch(T + 30, 100, None, None), S_OK, rem(1))
    assert d.event == "absorbed"


def test_level_floor():
    c = CueController(replace(Config(), start_level=10))
    assert step(c, T).level == 10
    assert step(c, T + 30, motion=6000).event == "wake_after_cue"
    d = step(c, T + 1230, ep_id=2)
    assert (d.fire, d.level) == (True, 10)


def test_level_cap():
    c = CueController(replace(Config(), start_level=70))
    levels = []
    for t in (T, T + 120, T + 240):
        d = step(c, t)
        assert d.fire is True
        levels.append(d.level)
        step(c, t + 30)
    assert levels == [70, 80, 80]


def test_cue_log_records_time_and_level():
    c = CueController(Config())
    for t in (T, T + 30, T + 120, T + 240, T + 360):
        step(c, t)
    assert c.cue_log == [(T, 30), (T + 120, 45), (T + 240, 60)]
