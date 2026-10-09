"""Cue controller: decides when the watch buzzes, based on sleep and REM state."""
from dataclasses import dataclass

from .config import (
    Config,
    COOLDOWN_SEC,
    WAKE_COOLDOWN_SEC,
    RAMP_SEC,
    MAX_PER_EPISODE,
    WAKE_HR_JUMP,
)
from .features import Epoch
from .sleep_state import ASLEEP, SleepStatus
from .rem import RemStatus


@dataclass(frozen=True)
class CueDecision:
    fire: bool
    level: int            # only meaningful when fire is True
    event: str | None     # None | "wake_after_cue" | "absorbed" (reaction to the previous epoch's cue)


class CueController:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.base_level = cfg.start_level
        self.cooldown = COOLDOWN_SEC
        self.last_cue_t = None          # time of the most recent cue
        self.pending_reaction = False   # a cue fired on the previous epoch
        self.last_cue_absorbed = False  # the most recent cue was judged absorbed
        self.cur_episode_id = 0         # episode id the per-episode counters belong to
        self.cues_in_episode = 0
        self.finished_episode_id = None
        self._cues_tonight = 0
        self._wakes_after_cue = 0
        self._cue_log = []

    @property
    def cues_tonight(self) -> int:
        return self._cues_tonight

    @property
    def wakes_after_cue(self) -> int:
        return self._wakes_after_cue

    @property
    def cue_log(self) -> list:
        return list(self._cue_log)

    def step(self, e: Epoch, s: SleepStatus, r: RemStatus) -> CueDecision:
        cfg = self.cfg
        event = None

        # 1. Reaction check (only the epoch right after a cue).
        if self.pending_reaction:
            self.pending_reaction = False
            woke = e.motion > cfg.wake_motion_threshold
            if (not woke and e.hr_mean is not None and r.hr_base is not None
                    and e.hr_mean >= r.hr_base * (1 + WAKE_HR_JUMP)):
                woke = True
            if woke:
                event = "wake_after_cue"
                self.base_level = max(cfg.level_min, self.base_level - cfg.level_step)
                self.cooldown = WAKE_COOLDOWN_SEC
                self.finished_episode_id = self.cur_episode_id
                self._wakes_after_cue += 1
                self.last_cue_absorbed = False
            else:
                event = "absorbed"
                self.cooldown = COOLDOWN_SEC
                self.last_cue_absorbed = True

        # A new episode id starts fresh.
        if r.episode_id != self.cur_episode_id:
            self.cur_episode_id = r.episode_id
            self.cues_in_episode = 0

        # 2. Gates.
        gates_ok = (
            s.state == ASLEEP
            and r.episode_active
            and s.onset_t is not None
            and e.t - s.onset_t >= cfg.earliest_cue_hours * 3600
            and self._cues_tonight < cfg.max_cues_per_night
            and self.finished_episode_id != self.cur_episode_id
        )
        if not gates_ok:
            return CueDecision(False, self.base_level, event)

        level = self.base_level
        fire = False
        if self.cues_in_episode == 0:
            # 3. First cue in an episode.
            if self.last_cue_t is None or e.t - self.last_cue_t >= self.cooldown:
                fire = True
        else:
            # 4. Ramp cue.
            if e.t - self.last_cue_t >= RAMP_SEC and self.last_cue_absorbed:
                fire = True
                level = min(cfg.level_max, self.base_level + cfg.level_step * self.cues_in_episode)

        if not fire:
            return CueDecision(False, self.base_level, event)

        self.cues_in_episode += 1
        self._cues_tonight += 1
        self.last_cue_t = e.t
        self.last_cue_absorbed = False
        self.pending_reaction = True
        self._cue_log.append((e.t, level))

        # 5. Episode is finished after MAX_PER_EPISODE cues (or the night cap).
        if self.cues_in_episode >= MAX_PER_EPISODE or self._cues_tonight >= cfg.max_cues_per_night:
            self.finished_episode_id = self.cur_episode_id
        return CueDecision(True, level, event)
