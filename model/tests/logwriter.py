"""Python mirror of the watch's night-log writer (NightLog.mc encoder + NightSession.mc
batching). Test support only, and the one place the Python side encodes: the tests and
tests/data/make_samples.py use it. The decoder is lucidcue_model/logparse.py.

Line formats (spec §4.7):
  D,<t0>,<payload>        20 epochs (10 min) per line; epoch i is at t0 + 30*i
  X,<t>,<name>,<detail>   events, e.g. X,<t>,cue,level=30
Each epoch is 6 base64url characters: motion/4, round(hr*10), round(var*100), as 12-bit
values (high 6 bits first); 4094 is the cap and 4095 means null (hr / var only).
"""
from lucidcue_model.config import EPOCH_SEC
from lucidcue_model.logparse import B64, Q_MAX, Q_NULL

BATCH_EPOCHS = 20      # NightSession.BATCH_EPOCHS
BATCH_SLACK_SEC = 10   # NightSession.BATCH_SLACK_SEC: off-grid tolerance before a split

# NightSession's night_start detail for LcConfig defaults (NightSessionTest asserts it).
DEFAULT_NIGHT_START_DETAIL = (
    "v1;noiseFloorMg=30;stillThreshold=500;wakeMotionThreshold=5000;hrRise=0.050;"
    "varRatio=1.300;earliestCueHours=4.50;maxCuesPerNight=6;startLevel=30;levelStep=15;"
    "levelMax=80;levelMin=10;trainReps=5;calibrationMode=true;vibeByLength=false;")


def b64x2(v: int) -> str:
    """A 12-bit value as 2 base64url characters, high 6 bits first (lcB64x2)."""
    return B64[(v >> 6) & 63] + B64[v & 63]


def quant(x, scale: float) -> int:
    """lcQuant: round half up of x*scale, clamped to 0..Q_MAX; None -> Q_NULL. Same double
    operations as Monkey C's (x * scale + 0.5d).toNumber()."""
    if x is None:
        return Q_NULL
    d = x * scale + 0.5
    if d >= float(Q_MAX):
        return Q_MAX
    if d < 0.0:
        return 0
    return int(d)


def quant_motion(motion: int) -> int:
    return max(0, min(Q_MAX, motion // 4))


def encode_epoch(e) -> str:
    """lcEncodeEpoch: 6 characters for one Epoch."""
    return (b64x2(quant_motion(e.motion)) + b64x2(quant(e.hr_mean, 10.0))
            + b64x2(quant(e.hr_var, 100.0)))


def batch_line(t0: int, payload: str) -> str:
    return "D,%d,%s" % (t0, payload)


class LogWriter:
    """NightSession's line sink: batches epochs into D lines and flushes the pending
    batch before every X line, so times are non-decreasing in file order."""

    def __init__(self):
        self.lines = []
        self._payload = ""
        self._t0 = 0
        self._n = 0

    def epoch(self, e) -> None:
        if self._n > 0:
            off = e.t - (self._t0 + EPOCH_SEC * self._n)
            if off > BATCH_SLACK_SEC or off < -BATCH_SLACK_SEC:
                self.flush()
        if self._n == 0:
            self._t0 = e.t
        self._payload += encode_epoch(e)
        self._n += 1
        if self._n >= BATCH_EPOCHS:
            self.flush()

    def flush(self) -> None:
        if self._n == 0:
            return
        self.lines.append(batch_line(self._t0, self._payload))
        self._payload = ""
        self._n = 0

    def event(self, t: int, name: str, detail: str = "") -> None:
        self.flush()
        self.lines.append("X,%d,%s,%s" % (t, name, detail))

    def text(self, newline: str = "\n") -> str:
        return newline.join(self.lines) + newline


def write_night(results, start_t=None, end_t=None, calibration=True,
                detail=DEFAULT_NIGHT_START_DETAIL, battery=(90.0, 84.0),
                caps_after=2, morning=True) -> LogWriter:
    """The lines NightSession (+ NightController's caps line, + MorningFlow) writes for
    run_night results: night_start, battery, caps after `caps_after` epochs, then per
    epoch the epoch, a cue / wouldcue line, the reaction and onset changes; then battery,
    night_end and morning."""
    w = LogWriter()
    t_first = results[0].epoch.t if start_t is None else start_t
    t_last = results[-1].epoch.t if end_t is None else end_t
    w.event(t_first, "night_start", detail)
    w.event(t_first, "battery", "%.1f" % battery[0])
    logged_onset = None
    cues = 0
    wakes = 0
    for k, r in enumerate(results):
        e = r.epoch
        w.epoch(e)
        if r.cue.fire:
            cues += 1
            w.event(e.t, "wouldcue" if calibration else "cue", "level=%d" % r.cue.level)
        if r.cue.event is not None:
            if r.cue.event == "wake_after_cue":
                wakes += 1
            w.event(e.t, r.cue.event, "")
        onset = r.sleep.onset_t
        if onset is not None and onset != logged_onset:
            w.event(e.t, "onset", str(onset))
            logged_onset = onset
        if k + 1 == caps_after:
            w.event(e.t, "caps", "hbi=0;acc=1")
    w.flush()
    w.event(t_last, "battery", "%.1f" % battery[1])
    w.event(t_last, "night_end", "cues=%d;wakes=%d" % (cues, wakes))
    if morning:
        w.event(t_last, "morning", "dream=0;felt=0;lucid=0")
    return w
