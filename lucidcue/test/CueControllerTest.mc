import Toybox.Lang;
import Toybox.Test;

// Unit tests for CueController. One-to-one port of model/tests/test_cue.py (same values).
// Python's step() returns a CueDecision; here the step helpers return the controller,
// and fire() / level() / event() read the decision of that step.
// Python's rem(ep_id, active) RemStatus is a RemDetector whose last-step outputs are
// set directly (its fields are public), so the controller reads the same values.

(:test)
module CueFix {
    const T0 = 1760000000;
    const T = 1760016200;   // Python T = T0 + H with H = int(4.5 * 3600) = 16200: the first cue

    // Python rem(ep_id, active): RemStatus(True, active, ep_id, 55.0, 20.0).
    function rem(epId as Number, active as Boolean) as RemDetector {
        var r = new $.RemDetector(new $.LcConfig());
        r.mRemLike = true;
        r.mEpisodeActive = active;
        r.mEpisodeId = epId;
        r.mHrBase = 55.0d;
        r.mVarBase = 20.0d;
        return r;
    }

    // Python step(c, t, ep_id, active, s, motion, hr); S_OK is (ASLEEP, T0).
    function stepAll(c as CueController, t as Number, epId as Number, active as Boolean,
            state as Number, motion as Number, hr as Double) as CueController {
        c.step(new $.Epoch(t, motion, hr, 20.0d), state, T0, rem(epId, active));
        return c;
    }

    // Python step(c, t) with the defaults ep_id=1, active=True, s=S_OK, motion=100, hr=55.0.
    function step(c as CueController, t as Number) as CueController {
        return stepAll(c, t, 1, true, $.STATE_ASLEEP, 100, 55.0d);
    }

    // Python step(c, t, ep_id=epId).
    function stepEp(c as CueController, t as Number, epId as Number) as CueController {
        return stepAll(c, t, epId, true, $.STATE_ASLEEP, 100, 55.0d);
    }

    // Python step(c, t, motion=motion).
    function stepMotion(c as CueController, t as Number, motion as Number) as CueController {
        return stepAll(c, t, 1, true, $.STATE_ASLEEP, motion, 55.0d);
    }

    // Python step(c, t, hr=hr).
    function stepHr(c as CueController, t as Number, hr as Double) as CueController {
        return stepAll(c, t, 1, true, $.STATE_ASLEEP, 100, hr);
    }

    // Asserts (fire, level) of the controller's last decision.
    function assertFire(c as CueController, fire as Boolean, level as Number) as Void {
        Test.assertEqual(c.fire(), fire);
        Test.assertEqual(c.level(), level);
    }

    function cfgWith(maxCues as Number, startLevel as Number) as LcConfig {
        var cfg = new $.LcConfig();
        cfg.maxCuesPerNight = maxCues;
        cfg.startLevel = startLevel;
        return cfg;
    }
}

(:test)
function testNoCueBeforeEarliest(logger as Test.Logger) as Boolean {
    var c = new CueController(new LcConfig());
    Test.assertEqual(CueFix.step(c, CueFix.T - 30).fire(), false);
    CueFix.step(c, CueFix.T);
    Test.assertEqual(c.fire(), true);
    Test.assertEqual(c.level(), 30);
    return true;
}

(:test)
function testRequiresActiveEpisodeAndAsleep(logger as Test.Logger) as Boolean {
    var c = new CueController(new LcConfig());
    Test.assertEqual(CueFix.stepAll(c, CueFix.T, 1, false, STATE_ASLEEP, 100, 55.0d).fire(), false);
    Test.assertEqual(CueFix.stepAll(c, CueFix.T + 30, 1, true, STATE_AWAKE, 100, 55.0d).fire(), false);
    Test.assertEqual(c.cuesTonight(), 0);
    return true;
}

(:test)
function testRampWithinEpisode(logger as Test.Logger) as Boolean {
    var c = new CueController(new LcConfig());
    CueFix.assertFire(CueFix.step(c, CueFix.T), true, 30);
    CueFix.step(c, CueFix.T + 30);
    Test.assertEqual(c.fire(), false);
    LcTestUtil.assertStr(c.event(), "absorbed");
    CueFix.assertFire(CueFix.step(c, CueFix.T + 120), true, 45);
    CueFix.assertFire(CueFix.step(c, CueFix.T + 240), true, 60);
    Test.assertEqual(CueFix.step(c, CueFix.T + 360).fire(), false);
    Test.assertEqual(c.cuesTonight(), 3);
    return true;
}

(:test)
function testNewEpisodeRespectsCooldown(logger as Test.Logger) as Boolean {
    var c = new CueController(new LcConfig());
    Test.assertEqual(CueFix.step(c, CueFix.T).fire(), true);
    LcTestUtil.assertStr(CueFix.step(c, CueFix.T + 30).event(), "absorbed");
    Test.assertEqual(CueFix.stepEp(c, CueFix.T + 300, 2).fire(), false);
    Test.assertEqual(CueFix.stepEp(c, CueFix.T + 570, 2).fire(), false);
    CueFix.assertFire(CueFix.stepEp(c, CueFix.T + 600, 2), true, 30);
    return true;
}

(:test)
function testMaxCuesPerNight(logger as Test.Logger) as Boolean {
    var c = new CueController(CueFix.cfgWith(2, 30));
    Test.assertEqual(CueFix.step(c, CueFix.T).fire(), true);
    CueFix.step(c, CueFix.T + 30);
    Test.assertEqual(CueFix.step(c, CueFix.T + 120).fire(), true);
    CueFix.step(c, CueFix.T + 150);
    Test.assertEqual(CueFix.step(c, CueFix.T + 240).fire(), false);
    Test.assertEqual(CueFix.step(c, CueFix.T + 360).fire(), false);
    Test.assertEqual(c.cuesTonight(), 2);
    return true;
}

(:test)
function testWakeAfterCueMotionBacksOff(logger as Test.Logger) as Boolean {
    var c = new CueController(new LcConfig());
    Test.assertEqual(CueFix.step(c, CueFix.T).fire(), true);
    CueFix.stepMotion(c, CueFix.T + 30, 6000);
    LcTestUtil.assertStr(c.event(), "wake_after_cue");
    Test.assertEqual(c.fire(), false);
    Test.assertEqual(CueFix.step(c, CueFix.T + 240).fire(), false); // same episode is finished
    Test.assertEqual(CueFix.stepEp(c, CueFix.T + 900, 2).fire(), false);
    CueFix.assertFire(CueFix.stepEp(c, CueFix.T + 1230, 2), true, 15);
    Test.assertEqual(c.wakesAfterCue(), 1);
    return true;
}

(:test)
function testWakeAfterCueHrJump(logger as Test.Logger) as Boolean {
    var c = new CueController(new LcConfig());
    Test.assertEqual(CueFix.step(c, CueFix.T).fire(), true);
    LcTestUtil.assertStr(CueFix.stepHr(c, CueFix.T + 30, 63.3d).event(), "wake_after_cue");
    c = new CueController(new LcConfig());
    Test.assertEqual(CueFix.step(c, CueFix.T).fire(), true);
    LcTestUtil.assertStr(CueFix.stepHr(c, CueFix.T + 30, 63.2d).event(), "absorbed");
    return true;
}

(:test)
function testEventOnlyForEpochAfterCue(logger as Test.Logger) as Boolean {
    var c = new CueController(new LcConfig());
    Test.assert(CueFix.step(c, CueFix.T - 30).event() == null);
    Test.assert(CueFix.step(c, CueFix.T).event() == null);
    LcTestUtil.assertStr(CueFix.step(c, CueFix.T + 30).event(), "absorbed");
    Test.assert(CueFix.step(c, CueFix.T + 60).event() == null);
    return true;
}

(:test)
function testMissingHrIsNotAWake(logger as Test.Logger) as Boolean {
    var c = new CueController(new LcConfig());
    Test.assertEqual(CueFix.step(c, CueFix.T).fire(), true);
    c.step(new Epoch(CueFix.T + 30, 100, null, null), STATE_ASLEEP, CueFix.T0, CueFix.rem(1, true));
    LcTestUtil.assertStr(c.event(), "absorbed");
    return true;
}

(:test)
function testLevelFloor(logger as Test.Logger) as Boolean {
    var c = new CueController(CueFix.cfgWith(6, 10));
    Test.assertEqual(CueFix.step(c, CueFix.T).level(), 10);
    LcTestUtil.assertStr(CueFix.stepMotion(c, CueFix.T + 30, 6000).event(), "wake_after_cue");
    CueFix.assertFire(CueFix.stepEp(c, CueFix.T + 1230, 2), true, 10);
    return true;
}

(:test)
function testLevelCap(logger as Test.Logger) as Boolean {
    var c = new CueController(CueFix.cfgWith(6, 70));
    var times = [CueFix.T, CueFix.T + 120, CueFix.T + 240] as Array<Number>;
    var levels = [] as Array<Number>;
    for (var k = 0; k < times.size(); k++) {
        var t = times[k];
        CueFix.step(c, t);
        Test.assertEqual(c.fire(), true);
        levels.add(c.level());
        CueFix.step(c, t + 30);
    }
    Test.assertEqual(levels.size(), 3);
    Test.assertEqual(levels[0], 70);
    Test.assertEqual(levels[1], 80);
    Test.assertEqual(levels[2], 80);
    return true;
}

(:test)
function testCueLogRecordsTimeAndLevel(logger as Test.Logger) as Boolean {
    var c = new CueController(new LcConfig());
    var times = [CueFix.T, CueFix.T + 30, CueFix.T + 120, CueFix.T + 240, CueFix.T + 360]
        as Array<Number>;
    for (var k = 0; k < times.size(); k++) {
        CueFix.step(c, times[k]);
    }
    // Python: c.cue_log == [(T, 30), (T + 120, 45), (T + 240, 60)].
    var entries = c.cueLog();
    Test.assertEqual(entries.size(), 3);
    Test.assertEqual(entries[0][0], CueFix.T);
    Test.assertEqual(entries[0][1], 30);
    Test.assertEqual(entries[1][0], CueFix.T + 120);
    Test.assertEqual(entries[1][1], 45);
    Test.assertEqual(entries[2][0], CueFix.T + 240);
    Test.assertEqual(entries[2][1], 60);
    return true;
}
