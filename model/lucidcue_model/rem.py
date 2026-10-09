"""REM detector: HR rise or HR-variability rise over a rolling still-sleep baseline."""
from collections import deque
from dataclasses import dataclass

from .config import (
    Config,
    BASE_EPOCHS,
    BASE_MIN_EPOCHS,
    STILL_RUN_EPOCHS,
    EPISODE_START,
    EPISODE_END,
)
from .features import Epoch
from .sleep_state import ASLEEP, SleepStatus


@dataclass(frozen=True)
class RemStatus:
    rem_like: bool
    episode_active: bool
    episode_id: int  # last episode number; 0 before the first episode
    hr_base: float | None
    var_base: float | None


class RemDetector:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.base_hr = deque(maxlen=BASE_EPOCHS)   # hr_mean of baseline epochs
        self.base_var = deque(maxlen=BASE_EPOCHS)  # hr_var of baseline epochs (may be None)
        self.still_run = 0       # consecutive still epochs (any state)
        self.rem_run = 0         # consecutive rem_like epochs
        self.non_rem_run = 0     # consecutive non-rem_like epochs
        self.episode_active = False
        self.episode_id = 0

    def step(self, e: Epoch, s: SleepStatus) -> RemStatus:
        is_still = e.motion < self.cfg.still_threshold
        if is_still:
            self.still_run += 1
        else:
            self.still_run = 0

        # Baselines are computed before the current epoch is added.
        hr_base = None
        var_base = None
        if len(self.base_hr) >= BASE_MIN_EPOCHS:
            total = 0.0
            for v in self.base_hr:
                total += v
            hr_base = total / len(self.base_hr)
            var_total = 0.0
            var_count = 0
            for v in self.base_var:
                if v is not None:
                    var_total += v
                    var_count += 1
            if var_count > 0:
                var_base = var_total / var_count

        asleep = s.state == ASLEEP

        rem_like = False
        if (
            asleep
            and self.still_run >= STILL_RUN_EPOCHS
            and e.hr_mean is not None
            and hr_base is not None
        ):
            if e.hr_mean >= hr_base * (1 + self.cfg.hr_rise):
                rem_like = True
            elif (
                e.hr_var is not None
                and var_base is not None
                and e.hr_var >= var_base * self.cfg.var_ratio
            ):
                rem_like = True

        # Baseline entry: asleep, still, non-null HR (rem_like epochs included).
        if asleep and is_still and e.hr_mean is not None:
            self.base_hr.append(e.hr_mean)
            self.base_var.append(e.hr_var)

        # Episode bookkeeping.
        if not asleep:
            self.episode_active = False
            self.rem_run = 0
            self.non_rem_run = 0
        elif rem_like:
            self.rem_run += 1
            self.non_rem_run = 0
            if not self.episode_active and self.rem_run >= EPISODE_START:
                self.episode_active = True
                self.episode_id += 1
        else:
            self.non_rem_run += 1
            self.rem_run = 0
            if self.episode_active and self.non_rem_run >= EPISODE_END:
                self.episode_active = False

        return RemStatus(rem_like, self.episode_active, self.episode_id, hr_base, var_base)
