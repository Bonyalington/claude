import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Bedtime training: plays the cue at startLevel trainReps times, 30 s apart (the first
// right away). Between buzzes it shows the reality-check prompt and "n / reps"; it ends
// on "Start Night →", and START then starts the night (replacing this view, so the
// stack is [Menu, Night]). Back returns to the menu.
class TrainView extends WatchUi.View {
    const REP_MS = 30000;

    var mVibe as Vibe;
    var mLevel as Number;
    var mReps as Number;
    var mRep as Number = 0;            // cues played so far
    var mTimer as Timer.Timer or Null = null;

    function initialize() {
        View.initialize();
        var cfg = $.loadConfig();
        mVibe = new Vibe(cfg.vibeByLength);
        mLevel = cfg.startLevel;
        mReps = cfg.trainReps;
    }

    function done() as Boolean {
        return mRep >= mReps;
    }

    // Starts (or, after being hidden, resumes) the 30 s cue timer.
    function onShow() as Void {
        if (mTimer != null || done()) {
            return;
        }
        if (mRep == 0) {
            onRep();
        }
        if (!done()) {
            var t = new Timer.Timer();
            t.start(method(:onRep), REP_MS, true);
            mTimer = t;
        }
    }

    function onHide() as Void {
        stopTimer();
    }

    function onRep() as Void {
        if (done()) {
            stopTimer();
            return;
        }
        mRep += 1;
        mVibe.play(mLevel);
        if (done()) {
            stopTimer();
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
        var count = mRep.toString() + " / " + mReps;
        if (done()) {
            $.lcDrawScreen(dc, [count, "Start Night →"] as Array<String>);
        } else {
            $.lcDrawScreen(dc, ["Look at your hands", "Am I dreaming?", count] as Array<String>);
        }
    }
}

class TrainDelegate extends WatchUi.BehaviorDelegate {
    var mView as TrainView;

    function initialize(view as TrainView) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    // START after the last cue starts the night; before that it does nothing.
    function onSelect() as Boolean {
        if (mView.done()) {
            $.lcStartNight(true);
        }
        return true;
    }
}
