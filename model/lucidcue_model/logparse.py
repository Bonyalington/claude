"""Parse the watch's night log (LUCIDCUE.TXT / LUCIDCUE.BAK) and Garmin sleep-stage JSON
for calibration.

Log lines (spec §4.7):
  D,<t0>,<payload>   a batch of epochs (20 = 10 min, fewer at the end of a night or after
                     a Timer stall); epoch i is at t0 + 30*i. The payload is 6 base64url
                     characters per epoch: three 12-bit values, high 6 bits first:
                     motion/4, round(hrMean*10), round(hrVar*100); 4095 = null.
  X,<t>,<name>,<detail>   events (night_start, caps, onset, cue, wouldcue, ...)
  E,<t>,<state>,<motion>,<hrMean>,<hrVar>,... (12 fields)   the old one-line-per-epoch
                     format, still accepted.
"""
import calendar
import time
from dataclasses import dataclass, field

from .config import EPOCH_SEC
from .features import Epoch

# Garmin sleepLevels activityLevel -> stage name. This mapping lives only here.
STAGE_MAP = {0: "deep", 1: "light", 2: "rem", 3: "awake"}

E_FIELDS = 12
X_FIELDS = 4
D_FIELDS = 3

B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
_B64_INDEX = {c: i for i, c in enumerate(B64)}
EPOCH_CHARS = 6    # 3 values x 2 characters
Q_MAX = 4094       # largest stored value (larger inputs are capped)
Q_NULL = 4095      # null hrMean / hrVar


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


def decode_payload(t0: int, payload: str) -> list[Epoch] | None:
    """Epochs of a D line's payload, or None if it is malformed (empty, a length that is
    not a multiple of 6, or a character outside the base64url alphabet)."""
    if len(payload) == 0 or len(payload) % EPOCH_CHARS != 0:
        return None
    vals = []
    for k in range(0, len(payload), 2):
        hi = _B64_INDEX.get(payload[k])
        lo = _B64_INDEX.get(payload[k + 1])
        if hi is None or lo is None:
            return None
        vals.append(hi * 64 + lo)
    epochs = []
    for i in range(len(vals) // 3):
        m, h, v = vals[3 * i:3 * i + 3]
        epochs.append(Epoch(t0 + EPOCH_SEC * i, m * 4,
                            None if h == Q_NULL else h / 10.0,
                            None if v == Q_NULL else v / 100.0))
    return epochs


def _parse_batch(parts):
    """Return the epochs of a well-formed D line's fields, or None if malformed."""
    if len(parts) != D_FIELDS:
        return None
    try:
        t0 = int(parts[1])
    except ValueError:
        return None
    return decode_payload(t0, parts[2])


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
    """Split the log into nights (one per night_start). Malformed lines are skipped, and
    so are epoch lines before the first night_start."""
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
        elif parts[0] == "D":
            if current is None:
                continue
            batch = _parse_batch(parts)
            if batch is not None:
                current.epochs.extend(batch)
        elif parts[0] == "E":
            if current is None:
                continue
            epoch = _parse_epoch(parts)
            if epoch is not None:
                current.epochs.append(epoch)
    return nights


def _first_time(text: str):
    """The timestamp (second field) of the first line that has an integer one, or None."""
    for raw in text.split("\n"):
        parts = raw.strip().split(",")
        if len(parts) < 2:
            continue
        try:
            return int(parts[1])
        except ValueError:
            continue
    return None


def join_logs(texts: list[str]) -> str:
    """Several log files' contents (e.g. LUCIDCUE.BAK and LUCIDCUE.TXT, or several
    mornings' copies) joined in the time order of their first line. Files with no timed
    line (empty) go last. The watch renames a full TXT to BAK, so BAK holds the start
    of the night and TXT the rest."""
    keyed = []
    for k, text in enumerate(texts):
        t = _first_time(text)
        keyed.append((t is None, t if t is not None else 0, k, text))
    keyed.sort(key=lambda x: x[:3])
    return "\n".join(x[3] for x in keyed)


def parse_logs(texts: list[str]) -> list[Night]:
    """parse_log of join_logs(texts)."""
    return parse_log(join_logs(texts))


def _gmt_to_unix(s: str) -> int:
    """'2026-10-10T03:15:00.0' as UTC -> Unix seconds. The fraction is optional, and a
    trailing 'Z' or '+00:00' is accepted."""
    s = s.strip()
    if s.endswith("Z"):
        s = s[:-1]
    elif s.endswith("+00:00"):
        s = s[:-6]
    base = s.split(".")[0]
    return calendar.timegm(time.strptime(base, "%Y-%m-%dT%H:%M:%S"))


def load_garmin_stages(obj: dict) -> list[tuple[int, int, str]]:
    """Return [(start_unix, end_unix, stage)] from obj['sleepLevels'].

    A missing or null sleepLevels (Garmin has no stages for that night) gives [].
    """
    stages = []
    for lv in obj.get("sleepLevels") or []:
        stage = STAGE_MAP.get(int(lv["activityLevel"]))
        if stage is None:
            continue
        stages.append((_gmt_to_unix(lv["startGMT"]), _gmt_to_unix(lv["endGMT"]), stage))
    return stages
