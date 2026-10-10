import Toybox.Lang;
import Toybox.Test;

// Unit tests for NightLog line formatting and the epoch encoder (spec §4.7). Lines must
// also parse with model/lucidcue_model/logparse.py (3 fields per D line, 4 per X line).
// The golden strings are repeated with identical values in model/tests/test_logformat.py
// (B64_GOLDEN, EPOCH_GOLDEN, BATCH_GOLDEN), so this encoder and the Python decoder agree.

(:test)
module NightLogFix {
    const T = 1760000000;

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

    function enc(motion as Number, hr as Double or Null, hrVar as Double or Null) as String {
        return $.lcEncodeEpoch(new $.Epoch(T, motion, hr, hrVar));
    }
}

(:test)
function testB64x2(logger as Test.Logger) as Boolean {
    LcTestUtil.assertStr(lcB64x2(0), "AA");
    LcTestUtil.assertStr(lcB64x2(63), "A_");
    LcTestUtil.assertStr(lcB64x2(64), "BA");
    LcTestUtil.assertStr(lcB64x2(1251), "Tj");
    LcTestUtil.assertStr(lcB64x2(4094), "_-");
    LcTestUtil.assertStr(lcB64x2(4095), "__");
    return true;
}

// Zero, null sentinels (4095), the largest values that fit (4094) and the caps.
(:test)
function testEncodeEpochZeroNullMax(logger as Test.Logger) as Boolean {
    LcTestUtil.assertStr(NightLogFix.enc(0, 0.0d, 0.0d), "AAAAAA");
    LcTestUtil.assertStr(NightLogFix.enc(0, null, null), "AA____");
    LcTestUtil.assertStr(NightLogFix.enc(16376, 409.4d, 40.94d), "_-_-_-");
    LcTestUtil.assertStr(NightLogFix.enc(99999, 500.0d, 99.0d), "_-_-_-");
    LcTestUtil.assertStr(NightLogFix.enc(16380, null, null), "_-____");   // 4095 -> 4094
    return true;
}

// Round half up at an exact .5: 60.25 * 10 = 602.5 -> 603, 1.125 * 100 = 112.5 -> 113
// (banker's rounding would give 112); 602.4 -> 602, 37.5 -> 38. Motion 3 / 4 = 0.
(:test)
function testEncodeEpochRoundsHalfUp(logger as Test.Logger) as Boolean {
    LcTestUtil.assertStr(NightLogFix.enc(3, 60.25d, 1.125d), "AAJbBx");
    LcTestUtil.assertStr(NightLogFix.enc(3, 60.24d, 0.375d), "AAJaAm");
    return true;
}

// motion / 4: 499 -> 124 (decodes to 496 < stillThreshold 500), 500 -> 125 (500),
// 5004 -> 1251 (5004 > wakeMotionThreshold 5000).
(:test)
function testEncodeEpochMotionThresholds(logger as Test.Logger) as Boolean {
    LcTestUtil.assertStr(NightLogFix.enc(499, null, null), "B8____");
    LcTestUtil.assertStr(NightLogFix.enc(500, null, null), "B9____");
    LcTestUtil.assertStr(NightLogFix.enc(5004, null, null), "Tj____");
    return true;
}

// Full epochs: 100 / 59.0 / 20.0 -> 25, 590, 2000; 2000 / 66.3 / 20.52 -> 500, 663, 2052.
(:test)
function testEncodeEpochFull(logger as Test.Logger) as Boolean {
    LcTestUtil.assertStr(lcEncodeEpoch(new Epoch(1760003450, 100, 59.0d, 20.0d)), "AZJOfQ");
    LcTestUtil.assertStr(NightLogFix.enc(2000, 66.3d, 20.52d), "H0KXgE");
    LcTestUtil.assertStr(NightLogFix.enc(2000, 66.0d, 20.0d), "H0KUfQ");
    return true;
}

(:test)
function testBatchLineFormat(logger as Test.Logger) as Boolean {
    var log = new NightLog();
    var line = log.batchLine(1760000000, "AAAAAA" + "AZJOfQ");
    logger.debug(line);
    LcTestUtil.assertStr(line, "D,1760000000,AAAAAAAZJOfQ");
    Test.assertEqual(NightLogFix.fieldCount(line), 3);
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
