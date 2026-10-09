"""Deterministic synthetic night used for replay tests and Monkey C fixtures."""
import random

from .config import EPOCH_SEC
from .features import Epoch

T0 = 1_760_000_000
STILL = 100
MOD = 2000
WAKE_MOTION = 9000

NIGHT_EPOCHS = 960          # 8 h
CYCLE_EPOCHS = 180          # 90 min
REM_MINUTES = [10, 15, 20, 25, 30, 30]
LEADIN_EPOCHS = 20          # lying awake
FINAL_WAKE_EPOCHS = 20      # last 10 min
BATHROOM_WAKE_EPOCHS = 10
BATHROOM_SETTLE_EPOCHS = 30
BATHROOM_AFTER_CYCLE = 1    # cycle index after which the bathroom wake happens

VAR_BASE = 20.0


def _epoch(rng, i, motion, hr_base, var_base):
    # Fixed draw order per epoch: HR jitter, then variability jitter.
    hr = hr_base + rng.uniform(-0.5, 0.5)
    var = var_base + rng.uniform(-1.0, 1.0)
    return Epoch(T0 + i * EPOCH_SEC, motion, hr, var)


def scripted_night(seed: int = 0) -> tuple[list[Epoch], list[tuple[int, int]], int]:
    """Return (epochs, REM spans (start_t, end_t) end-exclusive, bathroom-wake start t)."""
    rng = random.Random(seed)
    body_len = NIGHT_EPOCHS - FINAL_WAKE_EPOCHS
    epochs = []
    spans = []
    bathroom_t = None

    for _ in range(LEADIN_EPOCHS):
        epochs.append(_epoch(rng, len(epochs), MOD, 66.0, VAR_BASE))

    k = 0
    while len(epochs) < body_len:
        rem_len = REM_MINUTES[k] * 2
        nrem_len = CYCLE_EPOCHS - rem_len
        for j in range(nrem_len):
            if len(epochs) >= body_len:
                break
            motion = MOD if j == nrem_len - 1 else STILL
            epochs.append(_epoch(rng, len(epochs), motion, 55.0, VAR_BASE))
        if len(epochs) < body_len:
            start_i = len(epochs)
            for _ in range(rem_len):
                if len(epochs) >= body_len:
                    break
                epochs.append(_epoch(rng, len(epochs), STILL, 59.0, 30.0))
            spans.append((T0 + start_i * EPOCH_SEC, T0 + len(epochs) * EPOCH_SEC))
        if k == BATHROOM_AFTER_CYCLE:
            bathroom_t = T0 + len(epochs) * EPOCH_SEC
            for _ in range(BATHROOM_WAKE_EPOCHS):
                epochs.append(_epoch(rng, len(epochs), WAKE_MOTION, 75.0, VAR_BASE))
            for _ in range(BATHROOM_SETTLE_EPOCHS):
                epochs.append(_epoch(rng, len(epochs), STILL, 60.0, VAR_BASE))
        k += 1

    for _ in range(FINAL_WAKE_EPOCHS):
        epochs.append(_epoch(rng, len(epochs), WAKE_MOTION, 72.0, VAR_BASE))

    return epochs, spans, bathroom_t
