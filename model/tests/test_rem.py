from lucidcue_model.config import Config
from lucidcue_model.features import Epoch
from lucidcue_model.sleep_state import AWAKE, SETTLING, ASLEEP, SleepStatus
from lucidcue_model.rem import RemDetector

T0 = 1_760_000_000
STILL = 100
MOD = 2000
ASLEEP_S = SleepStatus(ASLEEP, T0)


class Feeder:
    """Steps a RemDetector with consecutive epochs, tracking the epoch index."""

    def __init__(self):
        self.rd = RemDetector(Config())
        self.i = 0
        self.last = None

    def feed(self, n, motion, hr, var, status=ASLEEP_S):
        """Step n epochs; returns the list of RemStatus results."""
        out = []
        for _ in range(n):
            e = Epoch(t=T0 + 30 * self.i, motion=motion, hr_mean=hr, hr_var=var)
            self.i += 1
            self.last = self.rd.step(e, status)
            out.append(self.last)
        return out


def base_feeder(n=60):
    f = Feeder()
    f.feed(n, STILL, 55.0, 20.0)
    return f


def test_no_baseline_no_rem():
    f = base_feeder(9)
    r = f.feed(1, STILL, 70.0, 40.0)[0]
    assert r.rem_like is False
    assert r.hr_base is None


def test_hr_rise_triggers():
    f = base_feeder()
    assert f.feed(1, STILL, 57.75, 20.0)[0].rem_like is True
    g = base_feeder()
    assert g.feed(1, STILL, 57.7, 20.0)[0].rem_like is False


def test_var_ratio_triggers():
    f = base_feeder()
    assert f.feed(1, STILL, 55.0, 26.0)[0].rem_like is True
    g = base_feeder()
    assert g.feed(1, STILL, 55.0, 25.9)[0].rem_like is False


def test_null_var_uses_hr_only():
    f = base_feeder()
    assert f.feed(1, STILL, 55.0, None)[0].rem_like is False
    assert f.feed(1, STILL, 58.0, None)[0].rem_like is True


def test_requires_ten_still_epochs():
    # The brief used HR 58 here, but the nine pre-qualifying 58s enter the baseline
    # (hr_base -> 55.39, threshold 58.16), so 58 would miss on the 10th. Use 60.
    f = base_feeder()
    f.feed(1, MOD, 55.0, 20.0)
    first_nine = f.feed(9, STILL, 60.0, 20.0)
    assert [r.rem_like for r in first_nine] == [False] * 9
    assert f.feed(1, STILL, 60.0, 20.0)[0].rem_like is True


def test_not_rem_like_unless_asleep():
    f = base_feeder()
    r = f.feed(1, STILL, 58.0, 20.0, SleepStatus(SETTLING, T0))[0]
    assert r.rem_like is False


def test_null_hr_not_rem_like_and_not_in_baseline():
    f = base_feeder()
    out = f.feed(20, STILL, None, None)
    assert all(r.rem_like is False for r in out)
    assert all(r.hr_base == 55.0 for r in out)
    assert f.last.hr_base == 55.0


def test_episode_starts_on_sixth_and_ends_after_two():
    f = base_feeder()
    first_five = f.feed(5, STILL, 58.0, 20.0)
    assert all(r.episode_active is False for r in first_five)
    r6 = f.feed(1, STILL, 58.0, 20.0)[0]
    assert r6.episode_active is True
    assert r6.episode_id == 1
    r = f.feed(1, STILL, 55.0, 20.0)[0]
    assert r.rem_like is False
    assert r.episode_active is True
    r = f.feed(1, STILL, 55.0, 20.0)[0]
    assert r.episode_active is False
    assert r.episode_id == 1
    # The baseline drifts upward as REM-like epochs enter it, so use a
    # clearly elevated HR for the second episode.
    second = f.feed(6, STILL, 65.0, 20.0)
    assert all(x.rem_like for x in second)
    assert not any(x.episode_active for x in second[:5])
    assert second[-1].episode_active is True
    assert second[-1].episode_id == 2


def test_wake_ends_episode_immediately():
    f = base_feeder()
    r = f.feed(6, STILL, 58.0, 20.0)[-1]
    assert r.episode_active is True
    r = f.feed(1, STILL, 58.0, 20.0, SleepStatus(AWAKE, T0))[0]
    assert r.episode_active is False
    assert r.rem_like is False
    assert r.episode_id == 1


def test_var_base_mean_of_non_null_and_none_when_all_null():
    f = Feeder()
    f.feed(5, STILL, 55.0, 10.0)
    f.feed(5, STILL, 55.0, None)
    r = f.feed(1, STILL, 55.0, 20.0)[0]
    assert r.var_base == 10.0
    g = Feeder()
    g.feed(10, STILL, 55.0, None)
    assert g.feed(1, STILL, 55.0, 20.0)[0].var_base is None


def test_baseline_window_keeps_last_120():
    f2 = Feeder()
    f2.feed(120, STILL, 50.0, 20.0)
    f2.feed(120, STILL, 60.0, 20.0)
    assert f2.feed(1, STILL, 60.0, 20.0)[0].hr_base == 60.0


def test_non_still_epochs_not_in_baseline():
    f = base_feeder()
    f.feed(30, MOD, 90.0, 20.0)
    assert f.feed(1, STILL, 55.0, 20.0)[0].hr_base == 55.0


def test_leaving_asleep_resets_rem_counter():
    f = base_feeder()
    f.feed(5, STILL, 60.0, 20.0)  # rem_run = 5, one short of EPISODE_START
    f.feed(1, STILL, 60.0, 20.0, SleepStatus(SETTLING, T0))
    r = f.feed(1, STILL, 60.0, 20.0)[0]
    assert r.rem_like is True
    assert r.episode_active is False  # without the reset rem_run would be 6


def test_leaving_asleep_resets_non_rem_counter():
    f = base_feeder()
    assert f.feed(6, STILL, 65.0, 20.0)[-1].episode_active is True
    assert f.feed(1, STILL, 55.0, 20.0)[0].episode_active is True  # non_rem_run = 1
    r = f.feed(1, STILL, 65.0, 20.0, SleepStatus(AWAKE, T0))[0]
    assert r.episode_active is False
    second = f.feed(6, STILL, 65.0, 20.0)
    assert not any(x.episode_active for x in second[:5])
    assert second[-1].episode_active is True
    assert second[-1].episode_id == 2
    # First non-REM epoch after re-entering must not end the new episode.
    assert f.feed(1, STILL, 55.0, 20.0)[0].episode_active is True
