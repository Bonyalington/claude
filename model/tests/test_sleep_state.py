from lucidcue_model.config import Config
from lucidcue_model.features import Epoch
from lucidcue_model.sleep_state import (
    AWAKE,
    SETTLING,
    ASLEEP,
    SleepStateMachine,
)

T0 = 1_760_000_000
STILL = 100
MOD = 2000
WAKE = 8000


def ep(i, motion, hr):
    return Epoch(t=T0 + 30 * i, motion=motion, hr_mean=hr, hr_var=20.0)


class Feeder:
    """Steps a machine with consecutive epochs, tracking the next epoch index."""

    def __init__(self):
        self.sm = SleepStateMachine(Config())
        self.i = 0
        self.last = None

    def feed(self, n, motion, hr):
        """Step n epochs; returns the first epoch index fed in this call."""
        first = self.i
        for _ in range(n):
            self.last = self.sm.step(ep(self.i, motion, hr))
            self.i += 1
        return first


def asleep_feeder():
    f = Feeder()
    f.feed(20, STILL, 66)
    f.feed(30, STILL, 60)
    assert f.last.state == ASLEEP
    assert f.last.onset_t == T0 + 30 * 20
    return f


def test_starts_awake_moves_to_settling_on_still():
    f = Feeder()
    f.feed(1, MOD, 66)
    assert f.last.state == AWAKE
    assert f.last.onset_t is None
    f.feed(1, STILL, 66)
    assert f.last.state == SETTLING


def test_onset_after_ref_and_30_low_epochs():
    f = Feeder()
    f.feed(20, STILL, 66)
    f.feed(29, STILL, 60)
    assert f.i - 1 == 48
    assert f.last.state == SETTLING
    f.feed(1, STILL, 60)
    assert f.i - 1 == 49
    assert f.last.state == ASLEEP
    assert f.last.onset_t == T0 + 30 * 20


def test_hr_at_or_above_ref_blocks_onset():
    f = Feeder()
    f.feed(20, STILL, 66)
    f.feed(40, STILL, 66)
    assert f.last.state == SETTLING
    assert f.last.onset_t is None


def test_null_hr_resets_onset_run():
    f = Feeder()
    f.feed(20, STILL, 66)
    f.feed(29, STILL, 60)
    f.feed(1, STILL, None)
    f.feed(29, STILL, 60)
    assert f.last.state == SETTLING
    f.feed(1, STILL, 60)
    assert f.last.state == ASLEEP
    assert f.last.onset_t == T0 + 30 * 50


def test_three_wake_epochs_not_enough():
    f = asleep_feeder()
    f.feed(3, WAKE, 80)
    assert f.last.state == ASLEEP


def test_four_wake_epochs_to_awake():
    f = asleep_feeder()
    f.feed(4, WAKE, 80)
    assert f.last.state == AWAKE


def test_non_wake_movement_keeps_asleep():
    f = asleep_feeder()
    f.feed(10, MOD, 70)
    assert f.last.state == ASLEEP
    assert f.last.onset_t == T0 + 600


def test_short_wake_keeps_onset():
    f = asleep_feeder()
    f.feed(4, WAKE, 80)
    f.feed(30, STILL, 60)
    assert f.last.state == ASLEEP
    assert f.last.onset_t == T0 + 600


def test_long_wake_resets_onset():
    f = asleep_feeder()
    f.feed(80, WAKE, 80)
    assert f.last.state == AWAKE
    first = f.feed(30, STILL, 60)
    assert first == 50 + 80
    assert f.last.state == ASLEEP
    assert f.last.onset_t == T0 + 30 * first
    assert f.last.onset_t != T0 + 600


def test_second_wake_streak_does_not_reset_awake_since():
    f = asleep_feeder()
    f.feed(4, WAKE, 80)             # A1: first wake streak after sleep
    f.feed(100, STILL, 66)          # ~50 min SETTLING, hr == ref so no onset
    assert f.last.state == SETTLING
    f.feed(4, WAKE, 80)             # A2: must not overwrite awake_since
    assert f.last.state == AWAKE
    first = f.feed(30, STILL, 60)
    assert first == 50 + 4 + 100 + 4
    assert f.last.state == ASLEEP
    assert f.last.onset_t == T0 + 30 * first


def test_awake_to_settling_epoch_counts_toward_onset_run():
    f = Feeder()
    f.feed(20, MOD, 66)
    assert f.last.state == AWAKE
    f.feed(29, STILL, 60)
    assert f.i - 1 == 48
    assert f.last.state == SETTLING
    f.feed(1, STILL, 60)
    assert f.i - 1 == 49
    assert f.last.state == ASLEEP
    assert f.last.onset_t == T0 + 600


def test_still_epoch_before_ref_does_not_start_run():
    f = Feeder()
    f.feed(10, STILL, 70)
    f.feed(10, STILL, 50)           # ref = 60; indices 10-19 are low but < REF_EPOCHS
    f.feed(29, STILL, 50)           # indices 20-48
    assert f.last.state == SETTLING
    f.feed(1, STILL, 50)            # index 49: run of 30 starting at index 20
    assert f.last.state == ASLEEP
    assert f.last.onset_t == T0 + 600
