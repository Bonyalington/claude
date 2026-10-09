import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Night screen: black on every update. START shows a dim (dark grey) status overlay
// for 5 s; START while it is up asks "End night?". Back is consumed (no exit).
class NightView extends WatchUi.View {
    const OVERLAY_MS = 5000;

    var mCtrl as NightController or Null;
    var mOverlay as Boolean = false;
    var mText as String = "";
    var mTimer as Timer.Timer or Null = null;

    function initialize(ctrl as NightController or Null) {
        View.initialize();
        mCtrl = ctrl;
    }

    function overlayOn() as Boolean {
        return mOverlay;
    }

    function showOverlay() as Void {
        var ctrl = mCtrl;
        if (ctrl != null) {
            mText = ctrl.statusText();
        }
        mOverlay = true;
        stopTimer();
        var t = new Timer.Timer();
        t.start(method(:hideOverlay), OVERLAY_MS, false);
        mTimer = t;
        WatchUi.requestUpdate();
    }

    // Also the 5 s timer callback.
    function hideOverlay() as Void {
        stopTimer();
        mOverlay = false;
        WatchUi.requestUpdate();
    }

    function stopTimer() as Void {
        var t = mTimer;
        if (t != null) {
            t.stop();
            mTimer = null;
        }
    }

    // Covered by "End night?" or replaced by Morning: drop the overlay and its timer.
    function onHide() as Void {
        stopTimer();
        mOverlay = false;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.clear();
        if (mOverlay) {
            $.lcDrawLines(dc, $.lcSplitLines(mText), Graphics.COLOR_DK_GRAY);
        }
    }
}

// Input for the Night screen. ctrl may be null (tests): then START does nothing.
class NightDelegate extends WatchUi.BehaviorDelegate {
    const NAV_DELAY_MS = 100;

    var mCtrl as NightController or Null;
    var mView as NightView or Null = null;
    var mFlow as MorningFlow or Null = null;
    var mNavTimer as Timer.Timer or Null = null;

    function initialize(ctrl as NightController or Null) {
        BehaviorDelegate.initialize();
        mCtrl = ctrl;
    }

    function setView(view as NightView) as Void {
        mView = view;
    }

    // Back is ignored all night (consumed so the app does not exit).
    function onBack() as Boolean {
        return true;
    }

    // START: show the status overlay; START while it is up: "End night?".
    function onSelect() as Boolean {
        if (mFlow != null) {
            return true;
        }
        var view = mView;
        if (view == null) {
            return true;
        }
        if (!view.overlayOn()) {
            view.showOverlay();
        } else {
            view.hideOverlay();
            WatchUi.pushView(new WatchUi.Confirmation("End night?"), new EndNightDelegate(self),
                WatchUi.SLIDE_IMMEDIATE);
        }
        return true;
    }

    // Yes on "End night?": stop the sampler and session now (the log is complete even if
    // the app is closed), then go to Morning. The switch is deferred by a short timer so
    // the Confirmation has been dismissed first, whatever order the firmware pops it in;
    // MorningFlow.begin() then replaces this Night view, so no stale Night view remains.
    function endNight() as Void {
        if (mFlow != null) {
            return;
        }
        var ctrl = mCtrl;
        if (ctrl == null) {
            return;
        }
        var summary = ctrl.stop();
        mFlow = new MorningFlow(ctrl.session(), summary);
        var t = new Timer.Timer();
        t.start(method(:onNav), NAV_DELAY_MS, false);
        mNavTimer = t;
    }

    function onNav() as Void {
        mNavTimer = null;
        var flow = mFlow;
        if (flow != null) {
            flow.begin();
        }
    }
}

class EndNightDelegate extends WatchUi.ConfirmationDelegate {
    var mNight as NightDelegate;

    function initialize(night as NightDelegate) {
        ConfirmationDelegate.initialize();
        mNight = night;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            mNight.endNight();
        }
        return true;
    }
}
