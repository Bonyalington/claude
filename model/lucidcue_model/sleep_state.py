"""Sleep state machine: AWAKE -> SETTLING -> ASLEEP, with wake detection and onset time."""
from dataclasses import dataclass

from .config import (
    Config,
    REF_EPOCHS,
    ONSET_EPOCHS,
    WAKE_EPOCHS,
    ONSET_RESET_SEC,
)
from .features import Epoch

AWAKE, SETTLING, ASLEEP = "AWAKE", "SETTLING", "ASLEEP"


@dataclass(frozen=True)
class SleepStatus:
    # onset_t persists after the first onset; consumers must gate on state == ASLEEP.
    state: str
    onset_t: int | None


class SleepStateMachine:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.state = AWAKE
        self.onset_t = None        # current sleep onset time (kept across short wakes)
        self.epoch_index = 0       # epochs stepped so far
        self.ref_sum = 0.0         # pre-sleep HR reference accumulation
        self.ref_count = 0
        self.ref = None            # fixed once REF_EPOCHS epochs have been seen
        self.wake_run = 0          # consecutive wake epochs
        self.wake_run_start_t = 0  # t of the first epoch of the current wake run
        self.awake_since = None    # t of the first epoch of the wake run that caused AWAKE
        self.onset_run = 0         # consecutive qualifying epochs while SETTLING
        self.run_start_t = 0       # t of the first epoch of the onset run

    def step(self, e: Epoch) -> SleepStatus:
        index = self.epoch_index
        self.epoch_index += 1

        # Pre-sleep reference: mean of non-null HR over the first REF_EPOCHS epochs.
        if index < REF_EPOCHS:
            if e.hr_mean is not None:
                self.ref_sum += e.hr_mean
                self.ref_count += 1
            if index == REF_EPOCHS - 1 and self.ref_count > 0:
                self.ref = self.ref_sum / self.ref_count

        is_still = e.motion < self.cfg.still_threshold
        is_wake = e.motion > self.cfg.wake_motion_threshold

        # Wake check first, from any state.
        if is_wake:
            if self.wake_run == 0:
                self.wake_run_start_t = e.t
            self.wake_run += 1
            self.onset_run = 0
            if self.wake_run >= WAKE_EPOCHS:
                if self.state == ASLEEP:  # only the first wake streak after being asleep
                    self.awake_since = self.wake_run_start_t
                self.state = AWAKE
            return SleepStatus(self.state, self.onset_t)
        self.wake_run = 0

        if self.state == AWAKE:
            if not is_still:
                return SleepStatus(self.state, self.onset_t)
            self.state = SETTLING
            self.onset_run = 0

        if self.state == SETTLING:
            qualifies = (
                is_still
                and index >= REF_EPOCHS
                and self.ref is not None
                and e.hr_mean is not None
                and e.hr_mean < self.ref
            )
            if qualifies:
                if self.onset_run == 0:
                    self.run_start_t = e.t
                self.onset_run += 1
                if self.onset_run >= ONSET_EPOCHS:
                    self.state = ASLEEP
                    if (
                        self.onset_t is None
                        or self.run_start_t - self.awake_since > ONSET_RESET_SEC
                    ):
                        self.onset_t = self.run_start_t
            else:
                self.onset_run = 0

        return SleepStatus(self.state, self.onset_t)
