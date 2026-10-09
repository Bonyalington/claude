import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Buzz test: plays levels 10, 30, 50, 80 by duty (Vibe(false), whatever vibeByLength
// says), 3 s apart, labelling the current level, so the user can feel whether strength
// changes. START when done plays them again. Back returns to the menu.
class BuzzTestView extends WatchUi.View {
    const STEP_MS = 3000;

    var mVibe as Vibe;
    var mLevels as Array<Number>;
    var mNext as Number = 0;           // index of the next level to play
    var mDone as Boolean = false;
    var mTimer as Timer.Timer or Null = null;

    function initialize() {
        View.initialize();
        mVibe = new Vibe(false);
        mLevels = [10, 30, 50, 80] as Array<Number>;
    }

    function isDone() as Boolean {
        return mDone;
    }

    function onShow() as Void {
        if (mTimer == null && !mDone) {
            startTimer();
        }
    }

    function onHide() as Void {
        stopTimer();
    }

    // Plays from the first level again.
    function restart() as Void {
        mNext = 0;
        mDone = false;
        startTimer();
    }

    // Plays the next level now, then every 3 s; one tick after the last level: done.
    function startTimer() as Void {
        stopTimer();
        if (mNext == 0) {
            onTick();
        }
        var t = new Timer.Timer();
        t.start(method(:onTick), STEP_MS, true);
        mTimer = t;
    }

    function onTick() as Void {
        if (mNext >= mLevels.size()) {
            stopTimer();
            mDone = true;
        } else {
            mVibe.play(mLevels[mNext]);
            mNext += 1;
        }
        WatchUi.requestUpdate();
    }

    function stopTimer() as Void {
        var t = mTimer;
        if (t != null) {
            t.stop();
            mTimer = null;
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        if (mDone) {
            $.lcDrawScreen(dc, ["Buzz test done", "START: again", "Back: menu"] as Array<String>);
        } else if (mNext == 0) {
            $.lcDrawScreen(dc, ["Buzz test"] as Array<String>);
        } else {
            $.lcDrawScreen(dc, ["Buzz test", "Level " + mLevels[mNext - 1],
                mNext.toString() + " / " + mLevels.size()] as Array<String>);
        }
    }
}

class BuzzTestDelegate extends WatchUi.BehaviorDelegate {
    var mView as BuzzTestView;

    function initialize(view as BuzzTestView) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onSelect() as Boolean {
        if (mView.isDone()) {
            mView.restart();
        }
        return true;
    }
}
