import Toybox.Lang;
import Toybox.System;

// Night log lines (plan Global Constraints). An empty field means null; floats are
// written to 1 decimal place. On a sideloaded app System.println goes to
// GARMIN/APPS/LOGS/LUCIDCUE.TXT. Lines must parse with model/lucidcue_model/logparse.py:
//   E,<t>,<state>,<motion>,<hrMean>,<hrVar>,<hrBase>,<varBase>,<remLike 0|1>,<episodeId>,<cueEvent>,<level>
//   X,<t>,<name>,<detail>        (detail must contain no commas: use ;-separated k=v)
class NightLog {
    function initialize() {
    }

    function epochLine(e as Epoch, state as Number, rem as RemDetector, cueEvent as String,
            level as Number) as String {
        return "E," + e.t + "," + $.stateName(state) + "," + e.motion
            + "," + $.lcFmt1(e.hrMean) + "," + $.lcFmt1(e.hrVar)
            + "," + $.lcFmt1(rem.hrBase()) + "," + $.lcFmt1(rem.varBase())
            + "," + (rem.remLike() ? "1" : "0") + "," + rem.episodeId()
            + "," + cueEvent + "," + level;
    }

    function eventLine(t as Number, name as String, detail as String) as String {
        return "X," + t + "," + name + "," + detail;
    }

    function write(line as String) as Void {
        System.println(line);
    }
}

// A nullable Double to 1 decimal place ("%.1f"); null -> "".
function lcFmt1(x as Double or Null) as String {
    if (x == null) {
        return "";
    }
    return (x as Double).format("%.1f");
}
