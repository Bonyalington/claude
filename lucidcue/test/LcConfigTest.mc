import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

// Unit tests for LcConfig defaults, clampConfig and loadConfig.
// Mirrors model/tests/test_config.py. Double fields are asserted with `d` literals.

(:test)
function testClampConfig(logger as Test.Logger) as Boolean {
    var c = new LcConfig();
    c.earliestCueHours = 12.0d; c.maxCuesPerNight = 0; c.startLevel = 95;
    c.trainReps = 50; c.hrRise = -1.0d; c.varRatio = 9.0d;
    c = clampConfig(c);
    Test.assertEqual(c.earliestCueHours, 7.0d); Test.assertEqual(c.maxCuesPerNight, 1);
    Test.assertEqual(c.startLevel, 80); Test.assertEqual(c.trainReps, 10);
    Test.assertEqual(c.hrRise, 0.0d); Test.assertEqual(c.varRatio, 2.0d);
    return true;
}

(:test)
function testClampConfigLowBounds(logger as Test.Logger) as Boolean {
    var c = new LcConfig();
    c.earliestCueHours = 0.5d; c.maxCuesPerNight = 99; c.startLevel = 0;
    c.trainReps = 1; c.hrRise = 0.9d; c.varRatio = 0.5d;
    c = clampConfig(c);
    Test.assertEqual(c.earliestCueHours, 2.0d); Test.assertEqual(c.maxCuesPerNight, 10);
    Test.assertEqual(c.startLevel, 10); Test.assertEqual(c.trainReps, 3);
    Test.assertEqual(c.hrRise, 0.2d); Test.assertEqual(c.varRatio, 1.0d);
    return true;
}

(:test)
function testClampConfigKeepsInRangeValues(logger as Test.Logger) as Boolean {
    var c = new LcConfig();
    c.earliestCueHours = 3.25d; c.maxCuesPerNight = 4; c.startLevel = 45;
    c.trainReps = 7; c.hrRise = 0.08d; c.varRatio = 1.6d;
    c = clampConfig(c);
    Test.assertEqual(c.earliestCueHours, 3.25d); Test.assertEqual(c.maxCuesPerNight, 4);
    Test.assertEqual(c.startLevel, 45); Test.assertEqual(c.trainReps, 7);
    Test.assertEqual(c.hrRise, 0.08d); Test.assertEqual(c.varRatio, 1.6d);
    return true;
}

(:test)
function testDefaults(logger as Test.Logger) as Boolean {
    var c = new LcConfig();
    Test.assertEqual(c.calibrationMode, true); Test.assertEqual(c.maxCuesPerNight, 6);
    Test.assertEqual(c.noiseFloorMg, 30); Test.assertEqual(c.stillThreshold, 500);
    Test.assertEqual(c.wakeMotionThreshold, 5000); Test.assertEqual(c.hrRise, 0.05d);
    Test.assertEqual(c.varRatio, 1.3d); Test.assertEqual(c.earliestCueHours, 4.5d);
    Test.assertEqual(c.startLevel, 30); Test.assertEqual(c.levelStep, 15);
    Test.assertEqual(c.levelMax, 80); Test.assertEqual(c.levelMin, 10);
    Test.assertEqual(c.trainReps, 5); Test.assertEqual(c.vibeByLength, false);
    return true;
}

// Writes out-of-range and in-range values into Application.Properties, loads, then
// restores the defaults BEFORE asserting so a failure cannot leave the simulator dirty.
// Float properties are chosen so Float -> Double conversion is exact (3.0, 1.5) or
// clamped to an exact bound (0.5 -> 0.2d).
(:test)
function testLoadConfigReadsAndClampsProperties(logger as Test.Logger) as Boolean {
    Application.Properties.setValue("calibrationMode", false);
    Application.Properties.setValue("earliestCueHours", 3.0);
    Application.Properties.setValue("maxCuesPerNight", 0);
    Application.Properties.setValue("startLevel", 95);
    Application.Properties.setValue("trainReps", 8);
    Application.Properties.setValue("hrRise", 0.5);
    Application.Properties.setValue("varRatio", 1.5);
    Application.Properties.setValue("vibeByLength", true);
    var c = loadConfig();

    Application.Properties.setValue("calibrationMode", true);
    Application.Properties.setValue("earliestCueHours", 4.5);
    Application.Properties.setValue("maxCuesPerNight", 6);
    Application.Properties.setValue("startLevel", 30);
    Application.Properties.setValue("trainReps", 5);
    Application.Properties.setValue("hrRise", 0.05);
    Application.Properties.setValue("varRatio", 1.3);
    Application.Properties.setValue("vibeByLength", false);

    Test.assertEqual(c.calibrationMode, false); Test.assertEqual(c.earliestCueHours, 3.0d);
    Test.assertEqual(c.maxCuesPerNight, 1); Test.assertEqual(c.startLevel, 80);
    Test.assertEqual(c.trainReps, 8); Test.assertEqual(c.hrRise, 0.2d);
    Test.assertEqual(c.varRatio, 1.5d); Test.assertEqual(c.vibeByLength, true);
    // Fixed fields are never read from properties.
    Test.assertEqual(c.noiseFloorMg, 30); Test.assertEqual(c.levelMax, 80);
    return true;
}
