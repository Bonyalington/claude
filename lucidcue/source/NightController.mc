import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// The night that is running (or last ran), so LucidCueApp.onStop can end it cleanly.
var lcActiveNight as NightController or Null = null;

// Starts a night and shows the Night screen. replace = true swaps out the current view
// (Train -> Start Night); false pushes onto it (Menu -> Start Night). Either way the
// stack is [Menu, Night].
function lcStartNight(replace as Boolean) as Void {
    var ctrl = new NightController();
    lcActiveNight = ctrl;
    var view = new NightView(ctrl);
    var del = new NightDelegate(ctrl);
    del.setView(view);
    if (replace) {
        WatchUi.switchToView(view, del, WatchUi.SLIDE_LEFT);
    } else {
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
    }
}

// Wires one night together so the views stay thin: config, log, vibe, session and
// sampler, plus the one-shot 60 s capability check.
class NightController {
    const CAPS_DELAY_MS = 60000;
    const NO_ACCEL_TEXT = "No motion sensor:\nbuzzing off";

    var mCfg as LcConfig;
    var mSession as NightSession;
    var mSampler as SensorSampler;
    var mCapsTimer as Timer.Timer or Null = null;
    var mStopped as Boolean = false;

    // Settings are read here, so a change made in Settings applies from the next night.
    function initialize() {
        mCfg = $.loadConfig();
        var log = new NightLog();
        var vibe = new Vibe(mCfg.vibeByLength);
        mSession = new NightSession(mCfg, log, vibe, Time.now().value(),
            System.getSystemStats().battery);
        mSampler = new SensorSampler(mCfg, method(:onEpoch));
        mSampler.start();
        var t = new Timer.Timer();
        t.start(method(:onCaps), CAPS_DELAY_MS, false);
        mCapsTimer = t;
    }

    function session() as NightSession {
        return mSession;
    }

    // SensorSampler callback, every 30 s.
    function onEpoch(e as Epoch) as Void {
        mSession.onEpoch(e);
    }

    // 60 s after start: log X,<t>,caps,hbi=<0|1>;acc=<0|1>. Without accelerometer data
    // motion reads as perfectly still, so buzzing is turned off for the night (R16a).
    function onCaps() as Void {
        mCapsTimer = null;
        if (mStopped) {
            return;
        }
        var acc = mSampler.hasAccel();
        mSession.logCaps(Time.now().value(), mSampler.hasBeatIntervals(), acc);
        if (!acc) {
            mSession.suppressCues();
        }
    }

    // Status overlay text: elapsed time, state, cues, and the no-accelerometer note.
    function statusText() as String {
        var text = mSession.statusText();
        if (mSession.cuesSuppressed()) {
            text = text + "\n" + NO_ACCEL_TEXT;
        }
        return text;
    }

    // Ends the night: stops the timers and sensors, logs battery + night_end via
    // NightSession.stop(). Idempotent (NightSession.stop() returns its cached summary).
    function stop() as NightSummary {
        mStopped = true;
        var t = mCapsTimer;
        if (t != null) {
            t.stop();
            mCapsTimer = null;
        }
        mSampler.stop();
        return mSession.stop(Time.now().value(), System.getSystemStats().battery);
    }
}
