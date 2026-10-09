import Toybox.Attention;
import Toybox.Lang;

// The cue: 3 pulses, 150 ms on / 150 ms off. By default the strength is the pulse duty
// cycle (= level). With byLength (setting vibeByLength, for motors whose strength does
// not change with duty) the duty is 100 and the pulse length grows with the level:
// 150 ms below 45, 250 ms below 60, otherwise 400 ms.
class Vibe {
    var mByLength as Boolean;

    function initialize(byLength as Boolean) {
        mByLength = byLength;
    }

    // on, off, on, off, on, off.
    function profiles(level as Number) as Array<Attention.VibeProfile> {
        var duty = level;
        var len = 150;
        if (mByLength) {
            duty = 100;
            if (level < 45) {
                len = 150;
            } else if (level < 60) {
                len = 250;
            } else {
                len = 400;
            }
        }
        // VibeProfile duty cycle is 0..100.
        if (duty > 100) {
            duty = 100;
        }
        if (duty < 0) {
            duty = 0;
        }
        var out = [] as Array<Attention.VibeProfile>;
        for (var k = 0; k < 3; k++) {
            out.add(new Attention.VibeProfile(duty, len));
            out.add(new Attention.VibeProfile(0, 150));
        }
        return out;
    }

    function play(level as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate(profiles(level));
        }
    }
}
