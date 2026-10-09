import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// What the Summary screen shows after a night.
class NightSummary {
    var startT as Number = 0;
    var endT as Number = 0;
    var onsetT as Number or Null = null;
    var cues as Array<Array<Number>>;     // [t, level] per cue (CueController.cueLog())
    var wakesAfterCue as Number = 0;
    var batteryStart as Float = 0.0;
    var batteryEnd as Float = 0.0;
    // True when cues were only logged, never played: calibration mode, or cues
    // suppressed for a missing accelerometer (suppressCues). Summary then says "Would-cues".
    var calibration as Boolean = false;

    function initialize() {
        cues = [] as Array<Array<Number>>;
    }
}

// One night: steps each epoch through sleep state -> REM -> cue (as night.py run_night),
// buzzes (live mode) or only logs "wouldcue" (calibration mode, or after suppressCues()),
// and writes the log.
//
// log and vibe are duck-typed so tests can pass fakes: log needs write(line as String),
// vibe needs play(level as Number). The real caller passes a NightLog and a Vibe.
class NightSession {
    var mCfg as LcConfig;
    var mLog;                              // duck-typed: write(line as String) as Void
    var mVibe;                             // duck-typed: play(level as Number) as Void
    var mFmt as NightLog;                  // line formatting
    var mSleep as SleepStateMachine;
    var mRem as RemDetector;
    var mCue as CueController;
    var mStartT as Number;
    var mBatteryStart as Float;
    var mLoggedOnsetT as Number or Null = null;   // onset time last written as an X line
    var mStopped as Boolean = false;
    var mSuppressed as Boolean = false;           // suppressCues(): fires log "wouldcue" only
    var mSummary as NightSummary or Null = null;  // cached by the first stop()

    function initialize(cfg as LcConfig, log, vibe, startT as Number, battery as Float) {
        mCfg = cfg;
        mLog = log;
        mVibe = vibe;
        mFmt = new NightLog();
        mSleep = new SleepStateMachine(cfg);
        mRem = new RemDetector(cfg);
        mCue = new CueController(cfg);
        mStartT = startT;
        mBatteryStart = battery;
        logEvent(startT, "night_start", $.lcSettingsDetail(cfg));
        logEvent(startT, "battery", battery.format("%.1f"));
    }

    function onEpoch(e as Epoch) as Void {
        if (mStopped) {
            return;
        }
        // Same order as run_night: state, then REM (with the new state), then cue.
        mSleep.step(e);
        var state = mSleep.state();
        var onset = mSleep.onsetT();
        mRem.step(e, state);
        mCue.step(e, state, onset, mRem);

        var cueEvent = "";
        var level = 0;
        if (mCue.fire()) {
            level = mCue.level();
            if (mCfg.calibrationMode || mSuppressed) {
                cueEvent = "wouldcue";
            } else {
                mVibe.play(level);
                cueEvent = "cue";
            }
        }
        mLog.write(mFmt.epochLine(e, state, mRem, cueEvent, level));

        // Reaction to the previous epoch's cue: "wake_after_cue" or "absorbed".
        var reaction = mCue.event();
        if (reaction != null) {
            logEvent(e.t, reaction as String, "");
        }
        // Onset: on the first onset, and again whenever the onset time changes.
        if (onset != null) {
            var logged = mLoggedOnsetT;
            if (logged == null || (logged as Number) != (onset as Number)) {
                logEvent(e.t, "onset", (onset as Number).toString());
                mLoggedOnsetT = onset;
            }
        }
    }

    // Overlay text for the Night screen: elapsed time, state, cues so far.
    function statusText() as String {
        var elapsed = Time.now().value() - mStartT;
        if (elapsed < 0) {
            elapsed = 0;
        }
        var h = elapsed / 3600;
        var m = (elapsed % 3600) / 60;
        return h.toString() + ":" + m.format("%02d") + "\n" + $.stateName(mSleep.state())
            + "\nCues: " + mCue.cuesTonight();
    }

    // No-vibrate mode for the rest of the night (R16a: no accelerometer data means
    // motion reads as perfectly still, which could buzz an awake user). From now on a
    // fire is logged as "wouldcue" and never played. The cue logic itself is unchanged.
    function suppressCues() as Void {
        mSuppressed = true;
    }

    function stopped() as Boolean {
        return mStopped;
    }

    function cuesSuppressed() as Boolean {
        return mSuppressed;
    }

    // Sensor capabilities, as X,<t>,caps,hbi=<0|1>;acc=<0|1>.
    function logCaps(t as Number, hbi as Boolean, acc as Boolean) as Void {
        logEvent(t, "caps", "hbi=" + $.lcBit(hbi) + ";acc=" + $.lcBit(acc));
    }

    // Ends the night: logs the end battery and night_end, and returns the summary.
    // Idempotent: a second call returns the first call's summary and writes nothing.
    function stop(endT as Number, battery as Float) as NightSummary {
        var done = mSummary;
        if (done != null) {
            return done;
        }
        mStopped = true;
        logEvent(endT, "battery", battery.format("%.1f"));
        logEvent(endT, "night_end", "cues=" + mCue.cuesTonight() + ";wakes=" + mCue.wakesAfterCue());
        var s = new NightSummary();
        s.startT = mStartT;
        s.endT = endT;
        s.onsetT = mSleep.onsetT();
        s.cues = mCue.cueLog();
        s.wakesAfterCue = mCue.wakesAfterCue();
        s.batteryStart = mBatteryStart;
        s.batteryEnd = battery;
        s.calibration = mCfg.calibrationMode || mSuppressed;
        mSummary = s;
        return s;
    }

    // The morning answers, as X,<t>,morning,dream=1;felt=0;lucid=0.
    function logMorning(t as Number, dream as Boolean, felt as Boolean, lucid as Boolean) as Void {
        logEvent(t, "morning", "dream=" + $.lcBit(dream) + ";felt=" + $.lcBit(felt)
            + ";lucid=" + $.lcBit(lucid));
    }

    function logEvent(t as Number, name as String, detail as String) as Void {
        mLog.write(mFmt.eventLine(t, name, detail));
    }
}

function lcBit(b as Boolean) as String {
    return b ? "1" : "0";
}

function lcBool(b as Boolean) as String {
    return b ? "true" : "false";
}

// night_start detail: "v1;" then "k=v;" for every LcConfig field (Python Config order).
// No commas (the X line has exactly 4 fields). Decimals are wide enough to reproduce any
// user input: hrRise / varRatio at 3 places (default "hrRise=0.050"), earliestCueHours at 2.
function lcSettingsDetail(c as LcConfig) as String {
    return "v1;"
        + "noiseFloorMg=" + c.noiseFloorMg + ";"
        + "stillThreshold=" + c.stillThreshold + ";"
        + "wakeMotionThreshold=" + c.wakeMotionThreshold + ";"
        + "hrRise=" + c.hrRise.format("%.3f") + ";"
        + "varRatio=" + c.varRatio.format("%.3f") + ";"
        + "earliestCueHours=" + c.earliestCueHours.format("%.2f") + ";"
        + "maxCuesPerNight=" + c.maxCuesPerNight + ";"
        + "startLevel=" + c.startLevel + ";"
        + "levelStep=" + c.levelStep + ";"
        + "levelMax=" + c.levelMax + ";"
        + "levelMin=" + c.levelMin + ";"
        + "trainReps=" + c.trainReps + ";"
        + "calibrationMode=" + lcBool(c.calibrationMode) + ";"
        + "vibeByLength=" + lcBool(c.vibeByLength) + ";";
}

// Local clock time HH:MM for a Unix time (device time zone).
function lcClock(t as Number) as String {
    var info = Gregorian.info(new Time.Moment(t), Time.FORMAT_SHORT);
    return (info.hour as Number).format("%02d") + ":" + (info.min as Number).format("%02d");
}

// Summary screen lines:
//   "Slept HH:MM" | "No sleep detected"
//   "Cues: N (W woke you)" | "Would-cues: N" (calibration) | "No cues"
//   "HH:MM L<level>" per cue
//   "Battery -X.X%"
function summaryLines(s as NightSummary) as Array<String> {
    var out = [] as Array<String>;
    var onset = s.onsetT;
    if (onset == null) {
        out.add("No sleep detected");
    } else {
        out.add("Slept " + lcClock(onset as Number));
    }
    var n = s.cues.size();
    if (n == 0) {
        out.add("No cues");
    } else if (s.calibration) {
        out.add("Would-cues: " + n);
    } else {
        out.add("Cues: " + n + " (" + s.wakesAfterCue + " woke you)");
    }
    for (var k = 0; k < n; k++) {
        var c = s.cues[k];
        out.add(lcClock(c[0]) + " L" + c[1]);
    }
    var drop = s.batteryStart - s.batteryEnd;
    if (drop >= 0.0) {
        out.add("Battery -" + drop.format("%.1f") + "%");
    } else {
        out.add("Battery +" + (-drop).format("%.1f") + "%");
    }
    return out;
}
