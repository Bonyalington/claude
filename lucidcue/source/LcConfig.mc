import Toybox.Application;
import Toybox.Lang;

// Settings for one night. Port of model/lucidcue_model/config.py `Config`
// (same defaults, camelCase names). User-editable fields are read from
// Application.Properties by loadConfig(); the rest are fixed.
class LcConfig {
    // Fixed (not exposed in settings).
    var noiseFloorMg as Number = 30;
    var stillThreshold as Number = 500;
    var wakeMotionThreshold as Number = 5000;
    var levelStep as Number = 15;
    var levelMax as Number = 80;
    var levelMin as Number = 10;

    // User-editable (properties.xml / settings.xml).
    var hrRise as Double = 0.05d;
    var varRatio as Double = 1.3d;
    var earliestCueHours as Double = 4.5d;
    var maxCuesPerNight as Number = 6;
    var startLevel as Number = 30;
    var trainReps as Number = 5;
    var calibrationMode as Boolean = true;
    var vibeByLength as Boolean = false;

    function initialize() {
    }
}

// max(lo, min(hi, v)), as Python _clip.
function lcClipNumber(v as Number, lo as Number, hi as Number) as Number {
    if (v > hi) {
        v = hi;
    }
    if (v < lo) {
        v = lo;
    }
    return v;
}

function lcClipDouble(v as Double, lo as Double, hi as Double) as Double {
    if (v > hi) {
        v = hi;
    }
    if (v < lo) {
        v = lo;
    }
    return v;
}

// Forces the user-settable fields into their allowed ranges. Port of config.clamp().
// Unlike Python (which returns a copy) this clamps c in place and returns it.
function clampConfig(c as LcConfig) as LcConfig {
    c.earliestCueHours = lcClipDouble(c.earliestCueHours, 2.0d, 7.0d);
    c.maxCuesPerNight = lcClipNumber(c.maxCuesPerNight, 1, 10);
    c.startLevel = lcClipNumber(c.startLevel, 10, 80);
    c.trainReps = lcClipNumber(c.trainReps, 3, 10);
    c.hrRise = lcClipDouble(c.hrRise, 0.0d, 0.2d);
    c.varRatio = lcClipDouble(c.varRatio, 1.0d, 2.0d);
    return c;
}

// Raw property value, or null if the key is missing or unreadable.
function lcReadProperty(key as String) as Application.PropertyValueType or Null {
    try {
        return Application.Properties.getValue(key);
    } catch (e) {
        return null;
    }
}

// Whole-number property; a missing or wrongly typed value yields dflt.
function lcReadNumber(key as String, dflt as Number) as Number {
    var v = lcReadProperty(key);
    if (v instanceof Number) {
        return v as Number;
    }
    if (v instanceof Float) {
        return (v as Float).toNumber();
    }
    if (v instanceof Double) {
        return (v as Double).toNumber();
    }
    if (v instanceof Long) {
        return (v as Long).toNumber();
    }
    return dflt;
}

// Properties store floats as Float; convert to Double so REM maths matches Python.
function lcReadDouble(key as String, dflt as Double) as Double {
    var v = lcReadProperty(key);
    if (v instanceof Float) {
        return (v as Float).toDouble();
    }
    if (v instanceof Double) {
        return v as Double;
    }
    if (v instanceof Number) {
        return (v as Number).toDouble();
    }
    if (v instanceof Long) {
        return (v as Long).toDouble();
    }
    return dflt;
}

function lcReadBoolean(key as String, dflt as Boolean) as Boolean {
    var v = lcReadProperty(key);
    if (v instanceof Boolean) {
        return v as Boolean;
    }
    return dflt;
}

// Reads the user-editable settings from Application.Properties, then clamps them.
// Values from the phone are never trusted: wrong types fall back to the defaults
// and out-of-range values are clamped.
function loadConfig() as LcConfig {
    var c = new LcConfig();
    c.calibrationMode = lcReadBoolean("calibrationMode", c.calibrationMode);
    c.earliestCueHours = lcReadDouble("earliestCueHours", c.earliestCueHours);
    c.maxCuesPerNight = lcReadNumber("maxCuesPerNight", c.maxCuesPerNight);
    c.startLevel = lcReadNumber("startLevel", c.startLevel);
    c.trainReps = lcReadNumber("trainReps", c.trainReps);
    c.hrRise = lcReadDouble("hrRise", c.hrRise);
    c.varRatio = lcReadDouble("varRatio", c.varRatio);
    c.vibeByLength = lcReadBoolean("vibeByLength", c.vibeByLength);
    return clampConfig(c);
}
