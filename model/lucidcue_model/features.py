"""Per-epoch feature extraction from raw accelerometer, HR and interval data."""
import math
from dataclasses import dataclass

from .config import Config


@dataclass(frozen=True)
class Epoch:
    t: int
    motion: int
    hr_mean: float | None
    hr_var: float | None


def motion_score(xs: list[int], ys: list[int], zs: list[int], noise_floor_mg: int) -> int:
    """Sum of per-sample deviation of |accel| from 1 g (1000 mg), minus the noise floor."""
    total = 0
    for x, y, z in zip(xs, ys, zs):
        mag = math.floor(math.sqrt(x * x + y * y + z * z) + 0.5)  # round half up
        total += max(0, abs(mag - 1000) - noise_floor_mg)
    return total


def _valid(samples: list[int | None]) -> list[int]:
    return [s for s in samples if s]  # drops None and 0


def hr_mean(samples: list[int | None]) -> float | None:
    v = _valid(samples)
    return sum(v) / len(v) if v else None


def hr_std(samples: list[int | None]) -> float | None:
    """Population standard deviation; None with fewer than 2 valid samples."""
    v = _valid(samples)
    if len(v) < 2:
        return None
    m = sum(v) / len(v)
    return math.sqrt(sum((s - m) ** 2 for s in v) / len(v))


def rmssd(intervals_ms: list[int]) -> float | None:
    """Root mean square of successive differences; None with fewer than 2 intervals."""
    if len(intervals_ms) < 2:
        return None
    diffs = [b - a for a, b in zip(intervals_ms, intervals_ms[1:])]
    return math.sqrt(sum(d * d for d in diffs) / len(diffs))


def epoch_features(t, xs, ys, zs, hr_samples, intervals_ms, cfg: Config) -> Epoch:
    hr_var = rmssd(intervals_ms) if len(intervals_ms) >= 2 else hr_std(hr_samples)
    return Epoch(
        t=t,
        motion=motion_score(xs, ys, zs, cfg.noise_floor_mg),
        hr_mean=hr_mean(hr_samples),
        hr_var=hr_var,
    )
