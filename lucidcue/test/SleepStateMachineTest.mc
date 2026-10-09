import Toybox.Lang;
import Toybox.Test;

// Unit tests for SleepStateMachine. One-to-one port of model/tests/test_sleep_state.py
// (same values). Python's `f.last.state` / `f.last.onset_t` read the status of the
// last step; here they are f.sm.state() / f.sm.onsetT() after the last step.

// Fixtures. A (:test) module, so ep() and asleepFeeder() are not (:test) functions
// (the runner would call those as tests). Globals are referenced with $. from inside.
(:test)
module SsmFix {
    const T0 = 1760000000;
    const STILL = 100;
    const MOD = 2000;
    const WAKE = 8000;

    function ep(i as Number, motion as Number, hr as Double or Null) as Epoch {
        return new $.Epoch(T0 + 30 * i, motion, hr, 20.0d);
    }

    // Steps a machine with consecutive epochs, tracking the next epoch index.
    class Feeder {
        var sm as SleepStateMachine;
        var i as Number = 0;

        function initialize() {
            sm = new $.SleepStateMachine(new $.LcConfig());
        }

        // Step n epochs; returns the first epoch index fed in this call.
        function feed(n as Number, motion as Number, hr as Double or Null) as Number {
            var first = i;
            for (var k = 0; k < n; k++) {
                sm.step($.SsmFix.ep(i, motion, hr));
                i += 1;
            }
            return first;
        }
    }

    function asleepFeeder() as Feeder {
        var f = new Feeder();
        f.feed(20, STILL, 66.0d);
        f.feed(30, STILL, 60.0d);
        Test.assertEqual(f.sm.state(), $.STATE_ASLEEP);
        $.LcTestUtil.assertNum(f.sm.onsetT(), T0 + 30 * 20);
        return f;
    }
}

(:test)
function testStartsAwakeMovesToSettlingOnStill(logger as Test.Logger) as Boolean {
    var f = new SsmFix.Feeder();
    f.feed(1, SsmFix.MOD, 66.0d);
    Test.assertEqual(f.sm.state(), STATE_AWAKE);
    Test.assert(f.sm.onsetT() == null);
    f.feed(1, SsmFix.STILL, 66.0d);
    Test.assertEqual(f.sm.state(), STATE_SETTLING);
    return true;
}

(:test)
function testOnsetAfterRefAnd30LowEpochs(logger as Test.Logger) as Boolean {
    var f = new SsmFix.Feeder();
    f.feed(20, SsmFix.STILL, 66.0d);
    f.feed(29, SsmFix.STILL, 60.0d);
    Test.assertEqual(f.i - 1, 48);
    Test.assertEqual(f.sm.state(), STATE_SETTLING);
    f.feed(1, SsmFix.STILL, 60.0d);
    Test.assertEqual(f.i - 1, 49);
    Test.assertEqual(f.sm.state(), STATE_ASLEEP);
    LcTestUtil.assertNum(f.sm.onsetT(), SsmFix.T0 + 30 * 20);
    return true;
}

(:test)
function testHrAtOrAboveRefBlocksOnset(logger as Test.Logger) as Boolean {
    var f = new SsmFix.Feeder();
    f.feed(20, SsmFix.STILL, 66.0d);
    f.feed(40, SsmFix.STILL, 66.0d);
    Test.assertEqual(f.sm.state(), STATE_SETTLING);
    Test.assert(f.sm.onsetT() == null);
    return true;
}

(:test)
function testNullHrResetsOnsetRun(logger as Test.Logger) as Boolean {
    var f = new SsmFix.Feeder();
    f.feed(20, SsmFix.STILL, 66.0d);
    f.feed(29, SsmFix.STILL, 60.0d);
    f.feed(1, SsmFix.STILL, null);
    f.feed(29, SsmFix.STILL, 60.0d);
    Test.assertEqual(f.sm.state(), STATE_SETTLING);
    f.feed(1, SsmFix.STILL, 60.0d);
    Test.assertEqual(f.sm.state(), STATE_ASLEEP);
    LcTestUtil.assertNum(f.sm.onsetT(), SsmFix.T0 + 30 * 50);
    return true;
}

(:test)
function testThreeWakeEpochsNotEnough(logger as Test.Logger) as Boolean {
    var f = SsmFix.asleepFeeder();
    f.feed(3, SsmFix.WAKE, 80.0d);
    Test.assertEqual(f.sm.state(), STATE_ASLEEP);
    return true;
}

(:test)
function testFourWakeEpochsToAwake(logger as Test.Logger) as Boolean {
    var f = SsmFix.asleepFeeder();
    f.feed(4, SsmFix.WAKE, 80.0d);
    Test.assertEqual(f.sm.state(), STATE_AWAKE);
    return true;
}

(:test)
function testNonWakeMovementKeepsAsleep(logger as Test.Logger) as Boolean {
    var f = SsmFix.asleepFeeder();
    f.feed(10, SsmFix.MOD, 70.0d);
    Test.assertEqual(f.sm.state(), STATE_ASLEEP);
    LcTestUtil.assertNum(f.sm.onsetT(), SsmFix.T0 + 600);
    return true;
}

(:test)
function testShortWakeKeepsOnset(logger as Test.Logger) as Boolean {
    var f = SsmFix.asleepFeeder();
    f.feed(4, SsmFix.WAKE, 80.0d);
    f.feed(30, SsmFix.STILL, 60.0d);
    Test.assertEqual(f.sm.state(), STATE_ASLEEP);
    LcTestUtil.assertNum(f.sm.onsetT(), SsmFix.T0 + 600);
    return true;
}

(:test)
function testLongWakeResetsOnset(logger as Test.Logger) as Boolean {
    var f = SsmFix.asleepFeeder();
    f.feed(80, SsmFix.WAKE, 80.0d);
    Test.assertEqual(f.sm.state(), STATE_AWAKE);
    var first = f.feed(30, SsmFix.STILL, 60.0d);
    Test.assertEqual(first, 50 + 80);
    Test.assertEqual(f.sm.state(), STATE_ASLEEP);
    LcTestUtil.assertNum(f.sm.onsetT(), SsmFix.T0 + 30 * first);
    Test.assert(f.sm.onsetT() != SsmFix.T0 + 600);
    return true;
}

(:test)
function testSecondWakeStreakDoesNotResetAwakeSince(logger as Test.Logger) as Boolean {
    var f = SsmFix.asleepFeeder();
    f.feed(4, SsmFix.WAKE, 80.0d);       // A1: first wake streak after sleep
    f.feed(100, SsmFix.STILL, 66.0d);    // ~50 min SETTLING, hr == ref so no onset
    Test.assertEqual(f.sm.state(), STATE_SETTLING);
    f.feed(4, SsmFix.WAKE, 80.0d);       // A2: must not overwrite awakeSince
    Test.assertEqual(f.sm.state(), STATE_AWAKE);
    var first = f.feed(30, SsmFix.STILL, 60.0d);
    Test.assertEqual(first, 50 + 4 + 100 + 4);
    Test.assertEqual(f.sm.state(), STATE_ASLEEP);
    LcTestUtil.assertNum(f.sm.onsetT(), SsmFix.T0 + 30 * first);
    return true;
}

(:test)
function testAwakeToSettlingEpochCountsTowardOnsetRun(logger as Test.Logger) as Boolean {
    var f = new SsmFix.Feeder();
    f.feed(20, SsmFix.MOD, 66.0d);
    Test.assertEqual(f.sm.state(), STATE_AWAKE);
    f.feed(29, SsmFix.STILL, 60.0d);
    Test.assertEqual(f.i - 1, 48);
    Test.assertEqual(f.sm.state(), STATE_SETTLING);
    f.feed(1, SsmFix.STILL, 60.0d);
    Test.assertEqual(f.i - 1, 49);
    Test.assertEqual(f.sm.state(), STATE_ASLEEP);
    LcTestUtil.assertNum(f.sm.onsetT(), SsmFix.T0 + 600);
    return true;
}

(:test)
function testStillEpochBeforeRefDoesNotStartRun(logger as Test.Logger) as Boolean {
    var f = new SsmFix.Feeder();
    f.feed(10, SsmFix.STILL, 70.0d);
    f.feed(10, SsmFix.STILL, 50.0d);     // ref = 60; indices 10-19 are low but < REF_EPOCHS
    f.feed(29, SsmFix.STILL, 50.0d);     // indices 20-48
    Test.assertEqual(f.sm.state(), STATE_SETTLING);
    f.feed(1, SsmFix.STILL, 50.0d);      // index 49: run of 30 starting at index 20
    Test.assertEqual(f.sm.state(), STATE_ASLEEP);
    LcTestUtil.assertNum(f.sm.onsetT(), SsmFix.T0 + 600);
    return true;
}

// Monkey C only (no Python counterpart): Python uses the strings as the states.
(:test)
function testStateNames(logger as Test.Logger) as Boolean {
    Test.assertEqual(stateName(STATE_AWAKE), "AWAKE");
    Test.assertEqual(stateName(STATE_SETTLING), "SETTLING");
    Test.assertEqual(stateName(STATE_ASLEEP), "ASLEEP");
    return true;
}
