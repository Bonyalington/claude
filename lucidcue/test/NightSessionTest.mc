import Toybox.Attention;
import Toybox.Lang;
import Toybox.Test;

// Tests for NightSession (orchestration and logging), summaryLines and Vibe.profiles.
//
// Ruling R14: the 960-epoch Fixtures night is NOT replayed here (watchdog). NsFix.runNight
// feeds a short synthetic night of 130 epochs instead, with earliestCueHours = 0.0d set
// directly (no clamping) so cues can fire. Traced with the Python model (run_night with
// Config(earliest_cue_hours=0.0)): ASLEEP at epoch 49 with onset_t = T0 + 600 (epoch 20),
// REM-like epochs 110..129, episode 1 active from epoch 115; fires at epochs 115, 119, 123
// with levels 30, 45, 60; "absorbed" reactions at epochs 116, 120, 124.

(:test)
module NsFix {
    const T0 = 1760000000;
    const EPOCHS = 130;   // epochs fed by runNight

    // Collects the lines NightSession writes (duck-typed stand-in for NightLog's sink).
    class FakeLog {
        var lines as Array<String>;

        function initialize() {
            lines = [] as Array<String>;
        }

        function write(line as String) as Void {
            lines.add(line);
        }
    }

    // Records the levels NightSession asks to play (duck-typed stand-in for Vibe).
    class FakeVibe {
        var levels as Array<Number>;

        function initialize() {
            levels = [] as Array<Number>;
        }

        function play(level as Number) as Void {
            levels.add(level);
        }
    }

    // Defaults, but cues allowed from onset on (set directly, bypassing clampConfig).
    function cfg(calibration as Boolean) as LcConfig {
        var c = new $.LcConfig();
        c.earliestCueHours = 0.0d;
        c.calibrationMode = calibration;
        return c;
    }

    // Feeds n epochs starting at epoch index i; returns the next index.
    function feed(s as NightSession, i as Number, n as Number, motion as Number,
            hr as Double, hrVar as Double) as Number {
        for (var k = 0; k < n; k++) {
            s.onEpoch(new $.Epoch(T0 + 30 * i, motion, hr, hrVar));
            i += 1;
        }
        return i;
    }

    // The synthetic night (EPOCHS epochs, see the header comment).
    function runNight(s as NightSession) as Void {
        var i = 0;
        i = feed(s, i, 20, 2000, 66.0d, 20.0d);   // lying awake (MOD): HR reference 66
        i = feed(s, i, 30, 100, 55.0d, 20.0d);    // still, HR below reference -> onset
        i = feed(s, i, 60, 100, 55.0d, 20.0d);    // still baseline
        i = feed(s, i, 20, 100, 59.0d, 20.0d);    // REM-like: HR >= base * 1.05
    }

    function hasSub(s as String, sub as String) as Boolean {
        return s.find(sub) != null;
    }

    function startsWith(s as String, prefix as String) as Boolean {
        var at = s.find(prefix);
        return at != null && (at as Number) == 0;
    }

    // Number of lines containing sub.
    function countSub(lines as Array<String>, sub as String) as Number {
        var n = 0;
        for (var k = 0; k < lines.size(); k++) {
            if (hasSub(lines[k], sub)) {
                n += 1;
            }
        }
        return n;
    }

    // Number of lines equal to line.
    function countEq(lines as Array<String>, line as String) as Number {
        var n = 0;
        for (var k = 0; k < lines.size(); k++) {
            if (lines[k].equals(line)) {
                n += 1;
            }
        }
        return n;
    }

    function hasLine(lines as Array<String>, line as String) as Boolean {
        return countEq(lines, line) > 0;
    }

    // Number of lines starting with prefix.
    function countPrefix(lines as Array<String>, prefix as String) as Number {
        var n = 0;
        for (var k = 0; k < lines.size(); k++) {
            if (startsWith(lines[k], prefix)) {
                n += 1;
            }
        }
        return n;
    }

    // The first line starting with prefix, or "" if there is none.
    function lineWithPrefix(lines as Array<String>, prefix as String) as String {
        for (var k = 0; k < lines.size(); k++) {
            if (startsWith(lines[k], prefix)) {
                return lines[k];
            }
        }
        return "";
    }
}

(:test)
function testCalibrationModeNeverVibrates(logger as Test.Logger) as Boolean {
    var log = new NsFix.FakeLog();
    var vibe = new NsFix.FakeVibe();
    var s = new NightSession(NsFix.cfg(true), log, vibe, NsFix.T0, 90.0);
    NsFix.runNight(s);
    Test.assertEqual(vibe.levels.size(), 0);
    Test.assertEqual(NsFix.countSub(log.lines, ",wouldcue,"), 3);
    Test.assertEqual(NsFix.countSub(log.lines, ",cue,"), 0);
    // The controller still decided 3 cues (it never reads calibrationMode).
    Test.assertEqual(s.mCue.cuesTonight(), 3);
    // night_start + battery + one E line per epoch + onset + 3 reactions.
    Test.assertEqual(NsFix.countPrefix(log.lines, "E,"), NsFix.EPOCHS);
    Test.assertEqual(log.lines.size(), 2 + NsFix.EPOCHS + 1 + 3);
    return true;
}

(:test)
function testLiveModeVibratesAtCueLevels(logger as Test.Logger) as Boolean {
    var log = new NsFix.FakeLog();
    var vibe = new NsFix.FakeVibe();
    var s = new NightSession(NsFix.cfg(false), log, vibe, NsFix.T0, 90.0);
    NsFix.runNight(s);
    var cues = s.mCue.cueLog();
    Test.assert(cues.size() >= 1);
    Test.assertEqual(vibe.levels.size(), cues.size());
    for (var k = 0; k < cues.size(); k++) {
        Test.assertEqual(vibe.levels[k], cues[k][1]);
    }
    // Python trace: three cues ramping 30 / 45 / 60.
    Test.assertEqual(vibe.levels.size(), 3);
    Test.assertEqual(vibe.levels[0], 30);
    Test.assertEqual(vibe.levels[1], 45);
    Test.assertEqual(vibe.levels[2], 60);
    Test.assertEqual(NsFix.countSub(log.lines, ",cue,"), 3);
    Test.assertEqual(NsFix.countSub(log.lines, ",wouldcue,"), 0);
    // The E line of the first cue (epoch 115) carries the event and the level.
    var line = NsFix.lineWithPrefix(log.lines, "E,1760003450,");
    logger.debug(line);
    Test.assert(NsFix.startsWith(line, "E,1760003450,ASLEEP,"));
    Test.assert(NsFix.hasSub(line, ",1,1,cue,30"));   // remLike 1, episode 1
    return true;
}

(:test)
function testOnsetAndReactionEventsLogged(logger as Test.Logger) as Boolean {
    var log = new NsFix.FakeLog();
    var s = new NightSession(NsFix.cfg(true), log, new NsFix.FakeVibe(), NsFix.T0, 90.0);
    NsFix.runNight(s);
    // Onset detected at epoch 49 (t = T0 + 1470); onset time is epoch 20 (T0 + 600).
    Test.assertEqual(NsFix.countSub(log.lines, ",onset,"), 1);
    Test.assert(NsFix.hasLine(log.lines, "X,1760001470,onset,1760000600"));
    Test.assertEqual(NsFix.countSub(log.lines, ",absorbed,"), 3);
    Test.assert(NsFix.hasLine(log.lines, "X,1760003480,absorbed,"));
    Test.assertEqual(NsFix.countSub(log.lines, ",wake_after_cue,"), 0);
    return true;
}

(:test)
function testNightStartLoggedWithSettings(logger as Test.Logger) as Boolean {
    var log = new NsFix.FakeLog();
    var s = new NightSession(new LcConfig(), log, new NsFix.FakeVibe(), NsFix.T0, 90.0);
    Test.assert(s != null);
    Test.assertEqual(log.lines.size(), 2);
    var first = log.lines[0];
    logger.debug(first);
    Test.assert(NsFix.startsWith(first, "X,"));
    Test.assert(NsFix.hasSub(first, ",night_start,"));
    Test.assert(NsFix.hasSub(first, "hrRise=0.05"));
    LcTestUtil.assertStr(first, "X,1760000000,night_start,v1;noiseFloorMg=30;stillThreshold=500;"
        + "wakeMotionThreshold=5000;hrRise=0.05;varRatio=1.30;earliestCueHours=4.5;"
        + "maxCuesPerNight=6;startLevel=30;levelStep=15;levelMax=80;levelMin=10;trainReps=5;"
        + "calibrationMode=true;vibeByLength=false;");
    Test.assertEqual(NightLogFix.fieldCount(first), 4);
    LcTestUtil.assertStr(log.lines[1], "X,1760000000,battery,90.0");
    return true;
}

// Review Focus 5: ending a night before sleep was detected must not crash on a null onset.
(:test)
function testStopWithoutSleep(logger as Test.Logger) as Boolean {
    var log = new NsFix.FakeLog();
    var s = new NightSession(NsFix.cfg(false), log, new NsFix.FakeVibe(), NsFix.T0, 90.0);
    NsFix.feed(s, 0, 10, 2000, 66.0d, 20.0d);
    var summary = s.stop(NsFix.T0 + 300, 89.5);
    Test.assert(summary.onsetT == null);
    Test.assertEqual(summary.cues.size(), 0);
    Test.assertEqual(summary.startT, NsFix.T0);
    Test.assertEqual(summary.endT, NsFix.T0 + 300);
    var lines = summaryLines(summary);
    Test.assertEqual(lines.size(), 3);
    Test.assert(NsFix.hasLine(lines, "No sleep detected"));
    Test.assert(NsFix.hasLine(lines, "No cues"));
    LcTestUtil.assertStr(lines[2], "Battery -0.5%");
    // stop() logs the end battery, then night_end.
    var n = log.lines.size();
    LcTestUtil.assertStr(log.lines[n - 2], "X,1760000300,battery,89.5");
    Test.assert(NsFix.startsWith(log.lines[n - 1], "X,1760000300,night_end,"));
    Test.assertEqual(NightLogFix.fieldCount(log.lines[n - 1]), 4);
    return true;
}

(:test)
function testSummaryLinesWithCues(logger as Test.Logger) as Boolean {
    var log = new NsFix.FakeLog();
    var s = new NightSession(NsFix.cfg(false), log, new NsFix.FakeVibe(), NsFix.T0, 90.0);
    NsFix.runNight(s);
    var summary = s.stop(NsFix.T0 + 30 * NsFix.EPOCHS, 88.0);
    LcTestUtil.assertNum(summary.onsetT, NsFix.T0 + 600);
    Test.assertEqual(summary.cues.size(), 3);
    Test.assertEqual(summary.wakesAfterCue, 0);
    Test.assertEqual(summary.calibration, false);
    // Clock strings are device-local: assert shapes, not exact times.
    var lines = summaryLines(summary);
    for (var k = 0; k < lines.size(); k++) {
        logger.debug(lines[k]);
    }
    Test.assertEqual(lines.size(), 6);
    Test.assert(NsFix.startsWith(lines[0], "Slept "));
    LcTestUtil.assertStr(lines[1], "Cues: 3 (0 woke you)");
    Test.assert(NsFix.hasSub(lines[2], " L30"));
    Test.assert(NsFix.hasSub(lines[3], " L45"));
    Test.assert(NsFix.hasSub(lines[4], " L60"));
    LcTestUtil.assertStr(lines[5], "Battery -2.0%");
    return true;
}

(:test)
function testLogMorning(logger as Test.Logger) as Boolean {
    var log = new NsFix.FakeLog();
    var s = new NightSession(new LcConfig(), log, new NsFix.FakeVibe(), NsFix.T0, 90.0);
    s.logMorning(NsFix.T0 + 100, true, false, true);
    LcTestUtil.assertStr(log.lines[log.lines.size() - 1],
        "X,1760000100,morning,dream=1;felt=0;lucid=1");
    return true;
}

(:test)
function testStatusTextShowsState(logger as Test.Logger) as Boolean {
    var s = new NightSession(new LcConfig(), new NsFix.FakeLog(), new NsFix.FakeVibe(),
        NsFix.T0, 90.0);
    NsFix.feed(s, 0, 10, 2000, 66.0d, 20.0d);
    var text = s.statusText();
    logger.debug(text);
    Test.assert(NsFix.hasSub(text, "AWAKE"));
    Test.assert(NsFix.hasSub(text, "Cues: 0"));
    return true;
}

(:test)
function testVibeProfilesByLength(logger as Test.Logger) as Boolean {
    var p = new Vibe(true).profiles(50);
    Test.assertEqual(p.size(), 6);
    for (var k = 0; k < 6; k += 2) {
        Test.assertEqual(p[k].dutyCycle, 100);
        Test.assertEqual(p[k].length, 250);
        Test.assertEqual(p[k + 1].dutyCycle, 0);
        Test.assertEqual(p[k + 1].length, 150);
    }
    return true;
}

(:test)
function testVibeProfilesByDuty(logger as Test.Logger) as Boolean {
    var p = new Vibe(false).profiles(45);
    Test.assertEqual(p.size(), 6);
    for (var k = 0; k < 6; k += 2) {
        Test.assertEqual(p[k].dutyCycle, 45);
        Test.assertEqual(p[k].length, 150);
        Test.assertEqual(p[k + 1].dutyCycle, 0);
        Test.assertEqual(p[k + 1].length, 150);
    }
    return true;
}

// vibeByLength pulse steps: < 45 -> 150 ms, < 60 -> 250 ms, else 400 ms.
(:test)
function testVibeLengthSteps(logger as Test.Logger) as Boolean {
    var v = new Vibe(true);
    Test.assertEqual(v.profiles(44)[0].length, 150);
    Test.assertEqual(v.profiles(45)[0].length, 250);
    Test.assertEqual(v.profiles(59)[0].length, 250);
    Test.assertEqual(v.profiles(60)[0].length, 400);
    Test.assertEqual(v.profiles(80)[0].dutyCycle, 100);
    return true;
}

// R16a: with cues suppressed (no accelerometer) a live night only logs would-cues.
(:test)
function testSuppressCuesNeverVibrates(logger as Test.Logger) as Boolean {
    var log = new NsFix.FakeLog();
    var vibe = new NsFix.FakeVibe();
    var s = new NightSession(NsFix.cfg(false), log, vibe, NsFix.T0, 90.0);
    s.suppressCues();
    Test.assert(s.cuesSuppressed());
    NsFix.runNight(s);
    Test.assertEqual(vibe.levels.size(), 0);
    Test.assertEqual(NsFix.countSub(log.lines, ",wouldcue,"), 3);
    Test.assertEqual(NsFix.countSub(log.lines, ",cue,"), 0);
    // Same lines as a calibration night: suppression adds no log lines of its own.
    Test.assertEqual(log.lines.size(), 2 + NsFix.EPOCHS + 1 + 3);
    var summary = s.stop(NsFix.T0 + 30 * NsFix.EPOCHS, 88.0);
    Test.assertEqual(summary.calibration, true);
    return true;
}

// Suppressing mid-night: the cue already played stays a cue, later fires are would-cues.
// Fires are at epochs 115, 119 and 123; suppression happens after epoch 116.
(:test)
function testSuppressCuesMidNight(logger as Test.Logger) as Boolean {
    var log = new NsFix.FakeLog();
    var vibe = new NsFix.FakeVibe();
    var s = new NightSession(NsFix.cfg(false), log, vibe, NsFix.T0, 90.0);
    var i = 0;
    i = NsFix.feed(s, i, 20, 2000, 66.0d, 20.0d);
    i = NsFix.feed(s, i, 30, 100, 55.0d, 20.0d);
    i = NsFix.feed(s, i, 60, 100, 55.0d, 20.0d);
    i = NsFix.feed(s, i, 7, 100, 59.0d, 20.0d);    // epochs 110..116: first fire at 115
    Test.assertEqual(vibe.levels.size(), 1);
    s.suppressCues();
    i = NsFix.feed(s, i, 13, 100, 59.0d, 20.0d);   // epochs 117..129
    Test.assertEqual(i, NsFix.EPOCHS);
    Test.assertEqual(vibe.levels.size(), 1);
    Test.assertEqual(vibe.levels[0], 30);
    Test.assertEqual(NsFix.countSub(log.lines, ",cue,"), 1);
    Test.assertEqual(NsFix.countSub(log.lines, ",wouldcue,"), 2);
    // The controller still ramps: the would-cues carry levels 45 and 60.
    Test.assert(NsFix.hasSub(NsFix.lineWithPrefix(log.lines, "E,1760003570,"), ",wouldcue,45"));
    Test.assert(NsFix.hasSub(NsFix.lineWithPrefix(log.lines, "E,1760003690,"), ",wouldcue,60"));
    return true;
}

// R16b: a second stop() returns the same summary and writes nothing new.
(:test)
function testSecondStopWritesNothing(logger as Test.Logger) as Boolean {
    var log = new NsFix.FakeLog();
    var s = new NightSession(NsFix.cfg(false), log, new NsFix.FakeVibe(), NsFix.T0, 90.0);
    NsFix.feed(s, 0, 10, 2000, 66.0d, 20.0d);
    var first = s.stop(NsFix.T0 + 300, 89.5);
    var n = log.lines.size();
    var second = s.stop(NsFix.T0 + 400, 80.0);
    Test.assertEqual(log.lines.size(), n);
    Test.assert(first == second);
    Test.assertEqual(second.endT, NsFix.T0 + 300);
    Test.assertEqual(NsFix.countSub(log.lines, ",night_end,"), 1);
    Test.assertEqual(NsFix.countSub(log.lines, ",battery,"), 2);
    // Epochs arriving after stop() are ignored too.
    NsFix.feed(s, 10, 2, 2000, 66.0d, 20.0d);
    Test.assertEqual(log.lines.size(), n);
    return true;
}

// R16a: the caps line, X,<t>,caps,hbi=<0|1>;acc=<0|1> (4 fields, no extra commas).
(:test)
function testLogCaps(logger as Test.Logger) as Boolean {
    var log = new NsFix.FakeLog();
    var s = new NightSession(new LcConfig(), log, new NsFix.FakeVibe(), NsFix.T0, 90.0);
    s.logCaps(NsFix.T0 + 60, true, false);
    var line = log.lines[log.lines.size() - 1];
    LcTestUtil.assertStr(line, "X,1760000060,caps,hbi=1;acc=0");
    Test.assertEqual(NightLogFix.fieldCount(line), 4);
    s.logCaps(NsFix.T0 + 61, false, true);
    LcTestUtil.assertStr(log.lines[log.lines.size() - 1], "X,1760000061,caps,hbi=0;acc=1");
    return true;
}

// Calibration nights label cues as would-cues and never say "woke you".
(:test)
function testSummaryLinesCalibration(logger as Test.Logger) as Boolean {
    var log = new NsFix.FakeLog();
    var s = new NightSession(NsFix.cfg(true), log, new NsFix.FakeVibe(), NsFix.T0, 90.0);
    NsFix.runNight(s);
    var summary = s.stop(NsFix.T0 + 30 * NsFix.EPOCHS, 88.0);
    Test.assertEqual(summary.calibration, true);
    var lines = summaryLines(summary);
    for (var k = 0; k < lines.size(); k++) {
        logger.debug(lines[k]);
    }
    Test.assertEqual(lines.size(), 6);
    Test.assert(NsFix.startsWith(lines[0], "Slept "));
    LcTestUtil.assertStr(lines[1], "Would-cues: 3");
    Test.assertEqual(NsFix.countSub(lines, "woke you"), 0);
    Test.assert(NsFix.hasSub(lines[2], " L30"));
    Test.assert(NsFix.hasSub(lines[4], " L60"));
    LcTestUtil.assertStr(lines[5], "Battery -2.0%");
    return true;
}
