import Toybox.Lang;
import Toybox.Test;

// Tests for the Night screen's input delegate (Task 11). A null controller is allowed so
// the delegate can be built without starting sensors, timers or a session.

(:test)
function testNightBackIsConsumed(logger as Test.Logger) as Boolean {
    var d = new NightDelegate(null);   // null controller allowed in tests
    Test.assertEqual(d.onBack(), true);
    return true;
}

// START with no view attached (test setup) is consumed and must not crash.
(:test)
function testNightSelectWithoutViewIsConsumed(logger as Test.Logger) as Boolean {
    var d = new NightDelegate(null);
    Test.assertEqual(d.onSelect(), true);
    return true;
}
