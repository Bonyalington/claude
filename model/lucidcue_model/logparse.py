"""Parse the watch's LUCIDCUE.TXT log and Garmin sleep-stage JSON for calibration."""
import calendar
import time
from dataclasses import dataclass, field

from .features import Epoch

# Garmin sleepLevels activityLevel -> stage name. This mapping lives only here.
STAGE_MAP = {0: "deep", 1: "light", 2: "rem", 3: "awake"}

E_FIELDS = 12
X_FIELDS = 4


@dataclass
class Night:
    start_t: int
    epochs: list[Epoch] = field(default_factory=list)
    events: list[tuple[int, str, str]] = field(default_factory=list)
    battery: list[tuple[int, float]] = field(default_factory=list)


def _opt_float(s):
    """Empty string -> None; otherwise float(s) (raises ValueError if malformed)."""
    if s == "":
        return None
    return float(s)


def _parse_epoch(parts):
    """Return Epoch for a well-formed E line's fields, or None if malformed."""
    if len(parts) != E_FIELDS:
        return None
    try:
        t = int(parts[1])
        motion = int(parts[3])
        hr_mean = _opt_float(parts[4])
        hr_var = _opt_float(parts[5])
        _opt_float(parts[6])   # hrBase, varBase: validated but not kept
        _opt_float(parts[7])
    except ValueError:
        return None
    return Epoch(t, motion, hr_mean, hr_var)


def _parse_event(parts):
    """Return (t, name, detail, battery_pct_or_None) for a well-formed X line, else None."""
    if len(parts) != X_FIELDS:
        return None
    try:
        t = int(parts[1])
        pct = float(parts[3]) if parts[2] == "battery" else None
    except ValueError:
        return None
    return (t, parts[2], parts[3], pct)


def parse_log(text: str) -> list[Night]:
    """Split the log into nights (one per night_start). Malformed lines are skipped."""
    nights = []
    current = None
    for raw in text.split("\n"):
        line = raw.rstrip("\r")
        parts = line.split(",")
        if parts[0] == "X":
            ev = _parse_event(parts)
            if ev is None:
                continue
            t, name, detail, pct = ev
            if name == "night_start":
                current = Night(t)
                nights.append(current)
            if current is None:
                continue
            current.events.append((t, name, detail))
            if pct is not None:
                current.battery.append((t, pct))
        elif parts[0] == "E":
            if current is None:
                continue
            epoch = _parse_epoch(parts)
            if epoch is not None:
                current.epochs.append(epoch)
    return nights


def _gmt_to_unix(s: str) -> int:
    """'2026-10-10T03:15:00.0' (or without fraction) as UTC -> Unix seconds."""
    base = s.split(".")[0]
    return calendar.timegm(time.strptime(base, "%Y-%m-%dT%H:%M:%S"))


def load_garmin_stages(obj: dict) -> list[tuple[int, int, str]]:
    """Return [(start_unix, end_unix, stage)] from obj['sleepLevels']."""
    stages = []
    for lv in obj["sleepLevels"]:
        stage = STAGE_MAP.get(int(lv["activityLevel"]))
        if stage is None:
            continue
        stages.append((_gmt_to_unix(lv["startGMT"]), _gmt_to_unix(lv["endGMT"]), stage))
    return stages
