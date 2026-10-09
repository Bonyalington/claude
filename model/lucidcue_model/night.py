"""Night pipeline: run every epoch through sleep state, REM detector and cue controller."""
from dataclasses import dataclass

from .config import Config
from .cue import CueController, CueDecision
from .features import Epoch
from .rem import RemDetector, RemStatus
from .sleep_state import SleepStateMachine, SleepStatus


@dataclass(frozen=True)
class EpochResult:
    epoch: Epoch
    sleep: SleepStatus
    rem: RemStatus
    cue: CueDecision


def run_night(epochs: list[Epoch], cfg: Config) -> list[EpochResult]:
    sleep_machine = SleepStateMachine(cfg)
    rem_detector = RemDetector(cfg)
    cue_controller = CueController(cfg)
    results = []
    for e in epochs:
        s = sleep_machine.step(e)
        r = rem_detector.step(e, s)
        c = cue_controller.step(e, s, r)
        results.append(EpochResult(e, s, r, c))
    return results
