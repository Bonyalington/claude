"""Compact night-log format (spec §4.7): D-line encoder/decoder, parse_logs, size budget.

The golden vectors below are repeated with identical values in
lucidcue/test/NightLogTest.mc, so the Monkey C encoder and this decoder agree.
"""
import random

from logwriter import (DEFAULT_NIGHT_START_DETAIL, LogWriter, b64x2, batch_line,
                       encode_epoch, write_night)
from lucidcue_model.config import Config
from lucidcue_model.features import Epoch
from lucidcue_model.logparse import decode_payload, parse_log, parse_logs
from lucidcue_model.night import run_night

T0 = 1_760_000_000

# (value, 2 characters): lcB64x2.
B64_GOLDEN = [(0, "AA"), (63, "A_"), (64, "BA"), (1251, "Tj"), (4094, "_-"), (4095, "__")]

# (motion, hrMean, hrVar) -> 6 characters: lcEncodeEpoch.
EPOCH_GOLDEN = [
    ((0, 0.0, 0.0), "AAAAAA"),           # zero
    ((0, None, None), "AA____"),         # null sentinels (4095)
    ((16376, 409.4, 40.94), "_-_-_-"),   # largest values that fit (4094)
    ((99999, 500.0, 99.0), "_-_-_-"),    # capped at 4094
    ((16380, None, None), "_-____"),     # motion cap: 16380 / 4 = 4095 -> 4094
    ((3, 60.25, 1.125), "AAJbBx"),       # .5 rounds up: 602.5 -> 603, 112.5 -> 113
    ((3, 60.24, 0.375), "AAJaAm"),       # 602.4 -> 602, 37.5 -> 38
    ((499, None, None), "B8____"),       # 499 / 4 = 124
    ((500, None, None), "B9____"),       # 125
    ((5004, None, None), "Tj____"),      # 1251
    ((100, 59.0, 20.0), "AZJOfQ"),       # NightSessionTest REM epoch
    ((2000, 66.3, 20.52), "H0KXgE"),     # sample_log first epoch
    ((2000, 66.0, 20.0), "H0KUfQ"),      # NightSessionTest awake epoch
]

BATCH_GOLDEN = ((T0, "AAAAAA" + "AZJOfQ"), "D,1760000000,AAAAAAAZJOfQ")


def test_b64x2_golden():
    for v, s in B64_GOLDEN:
        assert b64x2(v) == s, v


def test_encode_epoch_golden():
    for (m, hr, var), s in EPOCH_GOLDEN:
        assert encode_epoch(Epoch(T0, m, hr, var)) == s, (m, hr, var)


def test_batch_line_golden():
    (t0, payload), line = BATCH_GOLDEN
    assert batch_line(t0, payload) == line


def test_decode_golden():
    got = decode_payload(T0, "AZJOfQ" + "AA____" + "_-_-_-" + "H0KXgE" + "AAJbBx")
    assert got == [Epoch(T0, 100, 59.0, 20.0), Epoch(T0 + 30, 0, None, None),
                   Epoch(T0 + 60, 16376, 409.4, 40.94), Epoch(T0 + 90, 2000, 66.3, 20.52),
                   Epoch(T0 + 120, 0, 60.3, 1.13)]


def test_decode_batch_line_into_night():
    text = "X,%d,night_start,\n%s\n" % (T0, BATCH_GOLDEN[1])
    (n,) = parse_log(text)
    assert n.epochs == [Epoch(T0, 0, 0.0, 0.0), Epoch(T0 + 30, 100, 59.0, 20.0)]


def test_round_trip_error_bounds():
    rng = random.Random(7)
    for k in range(5000):
        m = rng.randrange(0, 16376)
        hr = rng.uniform(30.0, 200.0)
        var = rng.uniform(0.0, 40.0)
        (d,) = decode_payload(T0, encode_epoch(Epoch(T0, m, hr, var)))
        assert 0 <= m - d.motion <= 3
        assert abs(d.hr_mean - hr) <= 0.05 + 1e-9
        assert abs(d.hr_var - var) <= 0.005 + 1e-9


def _decoded_motion(m):
    return decode_payload(T0, encode_epoch(Epoch(T0, m, None, None)))[0].motion


def test_motion_thresholds_survive_quantisation():
    cfg = Config()
    assert _decoded_motion(499) < cfg.still_threshold
    assert _decoded_motion(500) >= cfg.still_threshold
    assert _decoded_motion(5004) > cfg.wake_motion_threshold


def test_malformed_d_lines_skipped():
    good = "AZJOfQ"
    text = (
        "X,%d,night_start,\n" % T0
        + "D,%d,%s\n" % (T0, good)
        + "D,%d,AZJOf\n" % (T0 + 30)           # bad length (truncated)
        + "D,%d,\n" % (T0 + 60)                 # empty payload
        + "D,%d,AZJ*fQ\n" % (T0 + 90)           # bad character
        + "D,%d,AZJ=fQ\n" % (T0 + 90)           # bad character (base64 padding)
        + "D,notint,%s\n" % good                # bad t
        + "D,%d\n" % (T0 + 120)                 # too few fields
        + "D,%d,%s,extra\n" % (T0 + 150, good)  # too many fields
        + "D,%d,%s\r\n" % (T0 + 180, good)      # CRLF is fine
    )
    (n,) = parse_log(text)
    assert [e.t for e in n.epochs] == [T0, T0 + 180]


def test_cue_lines_are_events():
    text = ("X,%d,night_start,\nX,%d,cue,level=30\nX,%d,absorbed,\nX,%d,wouldcue,level=45\n"
            % (T0, T0 + 30, T0 + 60, T0 + 90))
    (n,) = parse_log(text)
    assert n.events[1:] == [(T0 + 30, "cue", "level=30"), (T0 + 60, "absorbed", ""),
                            (T0 + 90, "wouldcue", "level=45")]


def _epochs(n, start=T0, step=30):
    return [Epoch(start + step * k, 100 + 4 * k, 55.0 + k / 10, 20.0 + k / 100)
            for k in range(n)]


def test_writer_batches_20_epochs_per_line_and_partial_tail():
    w = LogWriter()
    for e in _epochs(45):
        w.epoch(e)
    assert len(w.lines) == 2                       # full batches are written at once
    w.flush()
    assert [len(ln.split(",")[2]) for ln in w.lines] == [120, 120, 30]
    assert w.lines[1].startswith("D,%d," % (T0 + 600))


def test_writer_flushes_before_events():
    w = LogWriter()
    for e in _epochs(3):
        w.epoch(e)
    w.event(T0 + 60, "caps", "hbi=0;acc=1")
    assert w.lines[0].startswith("D,%d," % T0) and len(w.lines[0].split(",")[2]) == 18
    assert w.lines[1] == "X,%d,caps,hbi=0;acc=1" % (T0 + 60)


def test_non_contiguous_batch_split():
    # A Timer stall: epochs at T0, T0+30, then T0+120. The gap starts a new batch so
    # t0 + 30*i holds. A 1 s jitter (T0+151 instead of T0+150) stays in the batch.
    w = LogWriter()
    for t in (T0, T0 + 30, T0 + 120, T0 + 151):
        w.epoch(Epoch(t, 100, 59.0, 20.0))
    w.flush()
    assert w.lines == ["D,%d,AZJOfQAZJOfQ" % T0, "D,%d,AZJOfQAZJOfQ" % (T0 + 120)]
    (n,) = parse_log("X,%d,night_start,\n" % T0 + w.text())
    assert [e.t for e in n.epochs] == [T0, T0 + 30, T0 + 120, T0 + 150]


def _split_like_watch(text, cap=5000):
    """The watch's log rotation: when LUCIDCUE.TXT would pass `cap` bytes it becomes
    LUCIDCUE.BAK (overwriting the old one) and a new TXT starts. Returns (bak, txt)."""
    bak = ""
    cur = ""
    for line in text.splitlines(keepends=True):
        if len(cur) + len(line) > cap:
            bak = cur
            cur = ""
        cur += line
    return bak, cur


def _night_results(n_epochs):
    from lucidcue_model.synth import scripted_night
    epochs = scripted_night(0)[0]
    while len(epochs) < n_epochs:   # extend with still, steady epochs
        last = epochs[-1]
        epochs.append(Epoch(last.t + 30, 100, 55.0, 20.0))
    return run_night(epochs[:n_epochs], Config())


def test_parse_logs_joins_bak_then_txt_in_time_order():
    w = write_night(_night_results(960))
    bak, txt = _split_like_watch(w.text())
    assert bak and txt
    whole = parse_log(w.text())
    for texts in ([bak, txt], [txt, bak]):   # argument order does not matter
        (n,) = parse_logs(texts)
        assert n.epochs == whole[0].epochs and n.events == whole[0].events
        assert len(n.epochs) == 960
    # TXT alone (BAK lost): no night_start, so no night.
    assert parse_logs([txt]) == []


def test_parse_logs_skips_empty_files_and_orders_nights():
    a = "X,100,night_start,\nD,100,AZJOfQ\n"
    b = "X,5000,night_start,\nD,5000,AZJOfQAZJOfQ\n"
    nights = parse_logs(["", b, "\n", a])
    assert [n.start_t for n in nights] == [100, 5000]
    assert [len(n.epochs) for n in nights] == [1, 2]


def test_ten_hour_night_fits_watch_log_budget():
    # 1,200 epochs plus typical events (caps, onset, cues and reactions, battery,
    # night_end, morning), written with CRLF line ends to be safe.
    results = _night_results(1200)
    w = write_night(results, detail=DEFAULT_NIGHT_START_DETAIL)
    names = [ln.split(",")[2] for ln in w.lines if ln.startswith("X,")]
    assert names.count("wouldcue") >= 3 and "onset" in names and "caps" in names
    size = len(w.text("\r\n").encode("ascii"))
    print("10 h night: %d bytes, %d lines" % (size, len(w.lines)))
    assert size <= 9500
    # And it survives the watch's 5 KB TXT + one BAK.
    bak, txt = _split_like_watch(w.text("\r\n"))
    (n,) = parse_logs([bak, txt])
    assert len(n.epochs) == 1200
