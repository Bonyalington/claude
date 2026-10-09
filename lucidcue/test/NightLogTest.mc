import Toybox.Lang;
import Toybox.Test;

// Unit tests for NightLog line formatting (plan Global Constraints, log line formats).
// Lines must also parse with model/lucidcue_model/logparse.py (12 fields per E line,
// 4 per X line).

(:test)
module NightLogFix {
    // Number of comma-separated fields in a line (empty fields count).
    function fieldCount(line as String) as Number {
        var n = 1;
        var chars = line.toCharArray();
        for (var k = 0; k < chars.size(); k++) {
            if (chars[k] == ',') {
                n += 1;
            }
        }
        return n;
    }
}

// Ruling R2: fresh RemDetector (null bases, not REM, episode 0), null hrVar, no cue.
(:test)
function testEpochLineFormat(logger as Test.Logger) as Boolean {
    var log = new NightLog();
    var rem = new RemDetector(new LcConfig());
    var line = log.epochLine(new Epoch(1760000000, 100, 55.04d, null), STATE_ASLEEP, rem, "", 0);
    logger.debug(line);
    LcTestUtil.assertStr(line, "E,1760000000,ASLEEP,100,55.0,,,,0,0,,0");
    Test.assertEqual(NightLogFix.fieldCount(line), 12);
    return true;
}

// All fields set: hrMean / hrBase at 1 decimal, hrVar / varBase at 2, remLike 1,
// episode id, cue event and level.
(:test)
function testEpochLineAllFields(logger as Test.Logger) as Boolean {
    var log = new NightLog();
    var rem = new RemDetector(new LcConfig());
    rem.mRemLike = true;
    rem.mEpisodeId = 2;
    rem.mHrBase = 55.26d;
    rem.mVarBase = 19.956d;
    var line = log.epochLine(new Epoch(1760003450, 7, 59.0d, 30.444d), STATE_SETTLING, rem,
        "wouldcue", 45);
    logger.debug(line);
    LcTestUtil.assertStr(line, "E,1760003450,SETTLING,7,59.0,30.44,55.3,19.96,1,2,wouldcue,45");
    Test.assertEqual(NightLogFix.fieldCount(line), 12);
    return true;
}

(:test)
function testEventLineFormat(logger as Test.Logger) as Boolean {
    var log = new NightLog();
    LcTestUtil.assertStr(log.eventLine(1760000000, "battery", "90.0"),
        "X,1760000000,battery,90.0");
    var empty = log.eventLine(1760000030, "absorbed", "");
    LcTestUtil.assertStr(empty, "X,1760000030,absorbed,");
    Test.assertEqual(NightLogFix.fieldCount(empty), 4);
    return true;
}
