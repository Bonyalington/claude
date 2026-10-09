import Toybox.Lang;
import Toybox.Test;

// Unit tests for EpochFeatures. One-to-one port of model/tests/test_features.py
// (same values). Array literals are cast to the parameter's element type so the
// type checker sees Array<Number> / Array<Number or Null>.

// |a - b| < tol, false when a is null. Test-only helper.
(:test)
function lcNear(a as Double or Null, b as Double, tol as Double) as Boolean {
    if (a == null) {
        return false;
    }
    var d = (a as Double) - b;
    if (d < 0.0d) {
        d = -d;
    }
    return d < tol;
}

// Asserts a nullable Double is non-null and exactly equal to expected. Test-only helper.
(:test)
function lcAssertDbl(actual as Double or Null, expected as Double) as Void {
    Test.assert(actual != null);
    Test.assertEqual(actual as Double, expected);
}

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
    lcAssertDbl(EpochFeatures.hrMean([60, 0, null, 62] as Array<Number or Null>), 61.0d);
    return true;
}

(:test)
function testHrMeanEmptyIsNone(logger as Test.Logger) as Boolean {
    Test.assert(EpochFeatures.hrMean([] as Array<Number or Null>) == null);
    return true;
}

(:test)
function testHrStdPopulation(logger as Test.Logger) as Boolean {
    lcAssertDbl(EpochFeatures.hrStd([60, 62] as Array<Number or Null>), 1.0d);
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
    Test.assert(lcNear(r, 15.8114d, 0.001d));
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
    Test.assert(lcNear(e.hrVar, 15.8114d, 0.001d));
    lcAssertDbl(e.hrMean, 61.0d);
    Test.assertEqual(e.t, 5);
    return true;
}

(:test)
function testEpochFallsBackToHrStd(logger as Test.Logger) as Boolean {
    var e = EpochFeatures.build(5, [0] as Array<Number>, [0] as Array<Number>,
        [1000] as Array<Number>, [60, 62] as Array<Number or Null>,
        [] as Array<Number>, new LcConfig());
    lcAssertDbl(e.hrVar, 1.0d);
    return true;
}
