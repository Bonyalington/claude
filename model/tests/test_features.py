from lucidcue_model.config import Config
from lucidcue_model.features import (
    epoch_features,
    hr_mean,
    hr_std,
    motion_score,
    rmssd,
)


def test_motion_zero_at_rest(): assert motion_score([0], [0], [1000], 30) == 0
def test_motion_subtracts_gravity_and_floor(): assert motion_score([0], [0], [1100], 30) == 70
def test_motion_counts_below_1g_too(): assert motion_score([0, 0], [0, 0], [1000, 900], 30) == 70
def test_motion_ignores_noise(): assert motion_score([0], [0], [1025], 30) == 0
def test_hr_mean_ignores_zero_and_none(): assert hr_mean([60, 0, None, 62]) == 61.0
def test_hr_mean_empty_is_none(): assert hr_mean([]) is None
def test_hr_std_population(): assert hr_std([60, 62]) == 1.0
def test_hr_std_needs_two(): assert hr_std([60]) is None
def test_rmssd(): assert abs(rmssd([1000, 1010, 990]) - 15.8114) < 1e-3
def test_rmssd_needs_two(): assert rmssd([1000]) is None


def test_epoch_prefers_rmssd():
    e = epoch_features(5, [0], [0], [1000], [60, 62], [1000, 1010, 990], Config())
    assert abs(e.hr_var - 15.8114) < 1e-3 and e.hr_mean == 61.0 and e.t == 5


def test_epoch_falls_back_to_hr_std():
    assert epoch_features(5, [0], [0], [1000], [60, 62], [], Config()).hr_var == 1.0
