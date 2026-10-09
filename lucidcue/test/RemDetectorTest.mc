import Toybox.Lang;
import Toybox.Test;

// Unit tests for RemDetector. One-to-one port of model/tests/test_rem.py (same values).
// Python's step() returns a RemStatus; here Feeder.feed() snapshots the detector's
// getters after each step into a RemFix.Res, so `out[k].remLike` reads like Python's
// `out[k].rem_like`. Python's SleepStatus argument is just the state number here.

(:test)
module RemFix {
    const T0 = 1760000000;
    const STILL = 100;
    const MOD = 2000;

    // The detector's outputs after one step (Python RemStatus).
    class Res {
        var remLike as Boolean;
        var episodeActive as Boolean;
        var episodeId as Number;
        var hrBase as Double or Null;
        var varBase as Double or Null;

        function initialize(rd as RemDetector) {
            remLike = rd.remLike();
            episodeActive = rd.episodeActive();
            episodeId = rd.episodeId();
            hrBase = rd.hrBase();
            varBase = rd.varBase();
        }
    }

    // Steps a RemDetector with consecutive epochs, tracking the epoch index.
    class Feeder {
        var rd as RemDetector;
        var i as Number = 0;
        var last as Res or Null = null;

        function initialize() {
            rd = new $.RemDetector(new $.LcConfig());
        }

        // Step n epochs in state ASLEEP; returns the results.
        function feed(n as Number, motion as Number, hr as Double or Null,
                v as Double or Null) as Array<Res> {
            return feedState(n, motion, hr, v, $.STATE_ASLEEP);
        }

        // Step n epochs in the given sleep state; returns the results.
        function feedState(n as Number, motion as Number, hr as Double or Null,
                v as Double or Null, state as Number) as Array<Res> {
            var out = [] as Array<Res>;
            for (var k = 0; k < n; k++) {
                var e = new $.Epoch($.RemFix.T0 + 30 * i, motion, hr, v);
                i += 1;
                rd.step(e, state);
                var r = new $.RemFix.Res(rd);
                last = r;
                out.add(r);
            }
            return out;
        }
    }

    function baseFeeder(n as Number) as Feeder {
        var f = new $.RemFix.Feeder();
        f.feed(n, STILL, 55.0d, 20.0d);
        return f;
    }
}

(:test)
function testNoBaselineNoRem(logger as Test.Logger) as Boolean {
    var f = RemFix.baseFeeder(9);
    var r = f.feed(1, RemFix.STILL, 70.0d, 40.0d)[0];
    Test.assertEqual(r.remLike, false);
    Test.assert(r.hrBase == null);
    return true;
}

(:test)
function testHrRiseTriggers(logger as Test.Logger) as Boolean {
    var f = RemFix.baseFeeder(60);
    Test.assertEqual(f.feed(1, RemFix.STILL, 57.75d, 20.0d)[0].remLike, true);
    var g = RemFix.baseFeeder(60);
    Test.assertEqual(g.feed(1, RemFix.STILL, 57.7d, 20.0d)[0].remLike, false);
    return true;
}

(:test)
function testVarRatioTriggers(logger as Test.Logger) as Boolean {
    var f = RemFix.baseFeeder(60);
    Test.assertEqual(f.feed(1, RemFix.STILL, 55.0d, 26.0d)[0].remLike, true);
    var g = RemFix.baseFeeder(60);
    Test.assertEqual(g.feed(1, RemFix.STILL, 55.0d, 25.9d)[0].remLike, false);
    return true;
}

(:test)
function testNullVarUsesHrOnly(logger as Test.Logger) as Boolean {
    var f = RemFix.baseFeeder(60);
    Test.assertEqual(f.feed(1, RemFix.STILL, 55.0d, null)[0].remLike, false);
    Test.assertEqual(f.feed(1, RemFix.STILL, 58.0d, null)[0].remLike, true);
    return true;
}

// As in Python: HR 60, not 58, because the nine pre-qualifying epochs enter the
// baseline (hr_base -> 55.39, threshold 58.16).
(:test)
function testRequiresTenStillEpochs(logger as Test.Logger) as Boolean {
    var f = RemFix.baseFeeder(60);
    f.feed(1, RemFix.MOD, 55.0d, 20.0d);
    var firstNine = f.feed(9, RemFix.STILL, 60.0d, 20.0d);
    Test.assertEqual(firstNine.size(), 9);
    for (var k = 0; k < firstNine.size(); k++) {
        Test.assertEqual(firstNine[k].remLike, false);
    }
    Test.assertEqual(f.feed(1, RemFix.STILL, 60.0d, 20.0d)[0].remLike, true);
    return true;
}

(:test)
function testNotRemLikeUnlessAsleep(logger as Test.Logger) as Boolean {
    var f = RemFix.baseFeeder(60);
    var r = f.feedState(1, RemFix.STILL, 58.0d, 20.0d, STATE_SETTLING)[0];
    Test.assertEqual(r.remLike, false);
    return true;
}

(:test)
function testNullHrNotRemLikeAndNotInBaseline(logger as Test.Logger) as Boolean {
    var f = RemFix.baseFeeder(60);
    var out = f.feed(20, RemFix.STILL, null, null);
    for (var k = 0; k < out.size(); k++) {
        Test.assertEqual(out[k].remLike, false);
    }
    for (var j = 0; j < out.size(); j++) {
        LcTestUtil.assertDbl(out[j].hrBase, 55.0d);
    }
    var last = f.last;
    Test.assert(last != null);
    LcTestUtil.assertDbl((last as RemFix.Res).hrBase, 55.0d);
    return true;
}

(:test)
function testEpisodeStartsOnSixthAndEndsAfterTwo(logger as Test.Logger) as Boolean {
    var f = RemFix.baseFeeder(60);
    var firstFive = f.feed(5, RemFix.STILL, 58.0d, 20.0d);
    for (var k = 0; k < firstFive.size(); k++) {
        Test.assertEqual(firstFive[k].episodeActive, false);
    }
    var r6 = f.feed(1, RemFix.STILL, 58.0d, 20.0d)[0];
    Test.assertEqual(r6.episodeActive, true);
    Test.assertEqual(r6.episodeId, 1);
    var r = f.feed(1, RemFix.STILL, 55.0d, 20.0d)[0];
    Test.assertEqual(r.remLike, false);
    Test.assertEqual(r.episodeActive, true);
    r = f.feed(1, RemFix.STILL, 55.0d, 20.0d)[0];
    Test.assertEqual(r.episodeActive, false);
    Test.assertEqual(r.episodeId, 1);
    // The baseline drifts upward as REM-like epochs enter it, so use a
    // clearly elevated HR for the second episode.
    var second = f.feed(6, RemFix.STILL, 65.0d, 20.0d);
    for (var j = 0; j < second.size(); j++) {
        Test.assertEqual(second[j].remLike, true);
    }
    for (var m = 0; m < 5; m++) {
        Test.assertEqual(second[m].episodeActive, false);
    }
    Test.assertEqual(second[5].episodeActive, true);
    Test.assertEqual(second[5].episodeId, 2);
    return true;
}

(:test)
function testWakeEndsEpisodeImmediately(logger as Test.Logger) as Boolean {
    var f = RemFix.baseFeeder(60);
    var r = f.feed(6, RemFix.STILL, 58.0d, 20.0d)[5];
    Test.assertEqual(r.episodeActive, true);
    r = f.feedState(1, RemFix.STILL, 58.0d, 20.0d, STATE_AWAKE)[0];
    Test.assertEqual(r.episodeActive, false);
    Test.assertEqual(r.remLike, false);
    Test.assertEqual(r.episodeId, 1);
    return true;
}

(:test)
function testVarBaseMeanOfNonNullAndNoneWhenAllNull(logger as Test.Logger) as Boolean {
    var f = new RemFix.Feeder();
    f.feed(5, RemFix.STILL, 55.0d, 10.0d);
    f.feed(5, RemFix.STILL, 55.0d, null);
    var r = f.feed(1, RemFix.STILL, 55.0d, 20.0d)[0];
    LcTestUtil.assertDbl(r.varBase, 10.0d);
    var g = new RemFix.Feeder();
    g.feed(10, RemFix.STILL, 55.0d, null);
    Test.assert(g.feed(1, RemFix.STILL, 55.0d, 20.0d)[0].varBase == null);
    return true;
}

(:test)
function testBaselineWindowKeepsLast120(logger as Test.Logger) as Boolean {
    var f2 = new RemFix.Feeder();
    f2.feed(120, RemFix.STILL, 50.0d, 20.0d);
    f2.feed(120, RemFix.STILL, 60.0d, 20.0d);
    LcTestUtil.assertDbl(f2.feed(1, RemFix.STILL, 60.0d, 20.0d)[0].hrBase, 60.0d);
    return true;
}

(:test)
function testNonStillEpochsNotInBaseline(logger as Test.Logger) as Boolean {
    var f = RemFix.baseFeeder(60);
    f.feed(30, RemFix.MOD, 90.0d, 20.0d);
    LcTestUtil.assertDbl(f.feed(1, RemFix.STILL, 55.0d, 20.0d)[0].hrBase, 55.0d);
    return true;
}

(:test)
function testLeavingAsleepResetsRemCounter(logger as Test.Logger) as Boolean {
    var f = RemFix.baseFeeder(60);
    f.feed(5, RemFix.STILL, 60.0d, 20.0d); // rem_run = 5, one short of EPISODE_START
    f.feedState(1, RemFix.STILL, 60.0d, 20.0d, STATE_SETTLING);
    var r = f.feed(1, RemFix.STILL, 60.0d, 20.0d)[0];
    Test.assertEqual(r.remLike, true);
    Test.assertEqual(r.episodeActive, false); // without the reset rem_run would be 6
    return true;
}

(:test)
function testLeavingAsleepResetsNonRemCounter(logger as Test.Logger) as Boolean {
    var f = RemFix.baseFeeder(60);
    Test.assertEqual(f.feed(6, RemFix.STILL, 65.0d, 20.0d)[5].episodeActive, true);
    // non_rem_run = 1
    Test.assertEqual(f.feed(1, RemFix.STILL, 55.0d, 20.0d)[0].episodeActive, true);
    var r = f.feedState(1, RemFix.STILL, 65.0d, 20.0d, STATE_AWAKE)[0];
    Test.assertEqual(r.episodeActive, false);
    var second = f.feed(6, RemFix.STILL, 65.0d, 20.0d);
    for (var k = 0; k < 5; k++) {
        Test.assertEqual(second[k].episodeActive, false);
    }
    Test.assertEqual(second[5].episodeActive, true);
    Test.assertEqual(second[5].episodeId, 2);
    // First non-REM epoch after re-entering must not end the new episode.
    Test.assertEqual(f.feed(1, RemFix.STILL, 55.0d, 20.0d)[0].episodeActive, true);
    return true;
}
