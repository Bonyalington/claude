import Toybox.Lang;
import Toybox.Test;

// Test-only assertion helpers. They live in a (:test) module, not as (:test) global
// functions, because the test runner calls every (:test) function as a test with a
// Logger. Call them qualified: LcTestUtil.near(...).
(:test)
module LcTestUtil {

    // |a - b| < tol; false when a is null.
    function near(a as Double or Null, b as Double, tol as Double) as Boolean {
        if (a == null) {
            return false;
        }
        var d = (a as Double) - b;
        if (d < 0.0d) {
            d = -d;
        }
        return d < tol;
    }

    // Asserts a nullable Double is non-null and exactly equal to expected.
    function assertDbl(actual as Double or Null, expected as Double) as Void {
        Test.assert(actual != null);
        Test.assertEqual(actual as Double, expected);
    }

    // Asserts a nullable Number is non-null and equal to expected.
    function assertNum(actual as Number or Null, expected as Number) as Void {
        Test.assert(actual != null);
        Test.assertEqual(actual as Number, expected);
    }

    // Asserts a nullable String is non-null and has the same characters as expected.
    // String.equals compares contents; == on Strings would compare references.
    function assertStr(actual as String or Null, expected as String) as Void {
        Test.assert(actual != null);
        Test.assert((actual as String).equals(expected));
    }
}
