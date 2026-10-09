"""User-tunable settings and fixed algorithm constants for the LucidCue model."""
from dataclasses import dataclass, replace

# Fixed constants (not user-tunable); ported verbatim to Monkey C.
EPOCH_SEC = 30
REF_EPOCHS = 20
ONSET_EPOCHS = 30
WAKE_EPOCHS = 4
ONSET_RESET_SEC = 1800
BASE_EPOCHS = 120
BASE_MIN_EPOCHS = 10
STILL_RUN_EPOCHS = 10
EPISODE_START = 6
EPISODE_END = 2
COOLDOWN_SEC = 600
WAKE_COOLDOWN_SEC = 1200
RAMP_SEC = 120
MAX_PER_EPISODE = 3
WAKE_HR_JUMP = 0.15


@dataclass(frozen=True)
class Config:
    noise_floor_mg: int = 30
    still_threshold: int = 500
    wake_motion_threshold: int = 5000
    hr_rise: float = 0.05
    var_ratio: float = 1.3
    earliest_cue_hours: float = 4.5
    max_cues_per_night: int = 6
    start_level: int = 30
    level_step: int = 15
    level_max: int = 80
    level_min: int = 10
    train_reps: int = 5
    calibration_mode: bool = True
    vibe_by_length: bool = False


def _clip(value, lo, hi):
    return max(lo, min(hi, value))


def clamp(cfg: Config) -> Config:
    """Return cfg with user-settable fields forced into their allowed ranges."""
    return replace(
        cfg,
        earliest_cue_hours=_clip(cfg.earliest_cue_hours, 2.0, 7.0),
        max_cues_per_night=_clip(cfg.max_cues_per_night, 1, 10),
        start_level=_clip(cfg.start_level, 10, 80),
        train_reps=_clip(cfg.train_reps, 3, 10),
        hr_rise=_clip(cfg.hr_rise, 0.00, 0.20),
        var_ratio=_clip(cfg.var_ratio, 1.0, 2.0),
    )
