import Toybox.Lang;
import Toybox.Test;

// Tests for lcSampledEpoch, the pure epoch builder behind SensorSampler.onTimer
// (accelerometer dropout rule).

// No accelerometer samples at all: motion = stillThreshold ("not still"), HR kept.
(:test)
function testSampledEpochNoAccelIsNotStill(logger as Test.Logger) as Boolean {
    var cfg = new LcConfig();
    var e = lcSampledEpoch(1760000000, [] as Array<Number>, [] as Array<Number>,
        [] as Array<Number>, [60, 62] as Array<Number or Null>, [] as Array<Number>, cfg);
    Test.assertEqual(e.t, 1760000000);
    Test.assertEqual(e.motion, 500);
    Test.assert(!(e.motion < cfg.stillThreshold));            // not still
    Test.assert(!(e.motion > cfg.wakeMotionThreshold));       // not a wake either
    LcTestUtil.assertDbl(e.hrMean, 61.0d);
    LcTestUtil.assertDbl(e.hrVar, 1.0d);                      // HR std fallback
    return true;
}

// The motion follows the configured stillThreshold, and one empty axis is enough.
(:test)
function testSampledEpochEmptyAxisUsesStillThreshold(logger as Test.Logger) as Boolean {
    var cfg = new LcConfig();
    cfg.stillThreshold = 700;
    var e = lcSampledEpoch(1760000030, [0] as Array<Number>, [0] as Array<Number>,
        [] as Array<Number>, [] as Array<Number or Null>, [] as Array<Number>, cfg);
    Test.assertEqual(e.motion, 700);
    Test.assert(e.hrMean == null);
    return true;
}

// With accelerometer samples the motion is the normal motionScore (1100 mg: 100 - 30 = 70).
(:test)
function testSampledEpochWithAccelUsesMotionScore(logger as Test.Logger) as Boolean {
    var cfg = new LcConfig();
    var e = lcSampledEpoch(1760000060, [0, 0] as Array<Number>, [0, 0] as Array<Number>,
        [1000, 1100] as Array<Number>, [55] as Array<Number or Null>, [] as Array<Number>, cfg);
    Test.assertEqual(e.motion, 70);
    LcTestUtil.assertDbl(e.hrMean, 55.0d);
    Test.assert(e.hrVar == null);
    return true;
}
