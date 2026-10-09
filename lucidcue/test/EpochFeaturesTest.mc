import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

// Unit tests for EpochFeatures. One-to-one port of model/tests/test_features.py
// (same values). Array literals are cast to the parameter's element type so the
// type checker sees Array<Number> / Array<Number or Null>.

(:test)
function testMotionZeroAtRest(logger as Test.Logger) as Boolean {
    var m = EpochFeatures.motionScore([0] as Array<Number>, [0] as Array<Number>,
        [1000] as Array<Number>, 30);
    Test.assertEqual(m, 0);
    return true;
}

(:test)
function testMotionSubtractsGravityAndFloor(logger as Test.Logger) as Boolean {
    var m = EpochFeatures.motionScore([0] as Array<Number>, [0] as Array<Number>,
        [1100] as Array<Number>, 30);
    Test.assertEqual(m, 70);
    return true;
}

(:test)
function testMotionCountsBelow1gToo(logger as Test.Logger) as Boolean {
    var m = EpochFeatures.motionScore([0, 0] as Array<Number>, [0, 0] as Array<Number>,
        [1000, 900] as Array<Number>, 30);
    Test.assertEqual(m, 70);
    return true;
}

(:test)
function testMotionIgnoresNoise(logger as Test.Logger) as Boolean {
    var m = EpochFeatures.motionScore([0] as Array<Number>, [0] as Array<Number>,
        [1025] as Array<Number>, 30);
    Test.assertEqual(m, 0);
    return true;
}

(:test)
function testHrMeanIgnoresZeroAndNone(logger as Test.Logger) as Boolean {
    LcTestUtil.assertDbl(EpochFeatures.hrMean([60, 0, null, 62] as Array<Number or Null>), 61.0d);
    return true;
}

(:test)
function testHrMeanEmptyIsNone(logger as Test.Logger) as Boolean {
    Test.assert(EpochFeatures.hrMean([] as Array<Number or Null>) == null);
    return true;
}

(:test)
function testHrStdPopulation(logger as Test.Logger) as Boolean {
    LcTestUtil.assertDbl(EpochFeatures.hrStd([60, 62] as Array<Number or Null>), 1.0d);
    return true;
}

(:test)
function testHrStdNeedsTwo(logger as Test.Logger) as Boolean {
    Test.assert(EpochFeatures.hrStd([60] as Array<Number or Null>) == null);
    return true;
}

(:test)
function testRmssd(logger as Test.Logger) as Boolean {
    var r = EpochFeatures.rmssd([1000, 1010, 990] as Array<Number>);
    Test.assert(LcTestUtil.near(r, 15.8114d, 0.001d));
    return true;
}

(:test)
function testRmssdNeedsTwo(logger as Test.Logger) as Boolean {
    Test.assert(EpochFeatures.rmssd([1000] as Array<Number>) == null);
    return true;
}

(:test)
function testEpochPrefersRmssd(logger as Test.Logger) as Boolean {
    var e = EpochFeatures.build(5, [0] as Array<Number>, [0] as Array<Number>,
        [1000] as Array<Number>, [60, 62] as Array<Number or Null>,
        [1000, 1010, 990] as Array<Number>, new LcConfig());
    Test.assert(LcTestUtil.near(e.hrVar, 15.8114d, 0.001d));
    LcTestUtil.assertDbl(e.hrMean, 61.0d);
    Test.assertEqual(e.t, 5);
    return true;
}

(:test)
function testEpochFallsBackToHrStd(logger as Test.Logger) as Boolean {
    var e = EpochFeatures.build(5, [0] as Array<Number>, [0] as Array<Number>,
        [1000] as Array<Number>, [60, 62] as Array<Number or Null>,
        [] as Array<Number>, new LcConfig());
    LcTestUtil.assertDbl(e.hrVar, 1.0d);
    return true;
}

// Off-axis rounding: sqrt(3 * 577^2) = sqrt(998787) ~ 999.39 -> 999, deviation 1.
// Matches Python motion_score([577], [577], [577], 0) == 1.
(:test)
function testMotionOffAxisRounding(logger as Test.Logger) as Boolean {
    var m = EpochFeatures.motionScore([577] as Array<Number>, [577] as Array<Number>,
        [577] as Array<Number>, 0);
    Test.assertEqual(m, 1);
    return true;
}

// Monkey C only: probes that Math.sqrt on a Double returns a full-precision Double
// (a 32-bit Float would be off by ~1e-8), which the HR and motion maths rely on.
(:test)
function testSqrtReturnsDouble(logger as Test.Logger) as Boolean {
    var r = Math.sqrt(2.0d);
    Test.assert(r instanceof Lang.Double);
    Test.assert(LcTestUtil.near(r.toDouble(), 1.4142135623730951d, 0.000000000001d));
    return true;
}
