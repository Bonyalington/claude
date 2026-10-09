import Toybox.Lang;

// Cue controller: decides when the watch buzzes, based on sleep and REM state.
// Rule-for-rule port of model/lucidcue_model/cue.py (same order of operations).
// Python's step() returns a CueDecision; here step() stores it and fire() / level() /
// event() read it back. The REM inputs (episode id, episode active, HR baseline) are
// read from the RemDetector after its step() for the same epoch.
class CueController {
    var mCfg as LcConfig;
    var mBaseLevel as Number;
    var mCooldown as Number;
    var mLastCueT as Number or Null = null;          // time of the most recent cue
    var mPendingReaction as Boolean = false;         // a cue fired on the previous epoch
    var mLastCueAbsorbed as Boolean = false;         // the most recent cue was judged absorbed
    var mCurEpisodeId as Number = 0;                 // episode the per-episode counters belong to
    var mCuesInEpisode as Number = 0;
    var mFinishedEpisodeId as Number or Null = null;
    var mCuesTonight as Number = 0;
    var mWakesAfterCue as Number = 0;
    var mCueLog as Array<Array<Number>>;             // [t, level] per cue
    // Decision of the last step() (Python CueDecision).
    var mFire as Boolean = false;
    var mLevel as Number;                            // base level when not firing
    var mEvent as String or Null = null;             // null | "wake_after_cue" | "absorbed"

    function initialize(cfg as LcConfig) {
        mCfg = cfg;
        mBaseLevel = cfg.startLevel;
        mCooldown = LcConst.COOLDOWN_SEC;
        mCueLog = [] as Array<Array<Number>>;
        mLevel = mBaseLevel;
    }

    function fire() as Boolean {
        return mFire;
    }

    // The cue level when fire() is true; otherwise the current base level.
    function level() as Number {
        return mLevel;
    }

    // Reaction to the previous epoch's cue: null, "wake_after_cue" or "absorbed".
    function event() as String or Null {
        return mEvent;
    }

    function cuesTonight() as Number {
        return mCuesTonight;
    }

    function wakesAfterCue() as Number {
        return mWakesAfterCue;
    }

    // A copy of the cue log: one [t, level] pair per cue, in firing order.
    function cueLog() as Array<Array<Number>> {
        var out = [] as Array<Array<Number>>;
        for (var k = 0; k < mCueLog.size(); k++) {
            var p = mCueLog[k];
            out.add([p[0], p[1]] as Array<Number>);
        }
        return out;
    }

    function step(e as Epoch, state as Number, onsetT as Number or Null,
            rem as RemDetector) as Void {
        mEvent = null;

        // 1. Reaction check (only the epoch right after a cue).
        if (mPendingReaction) {
            mPendingReaction = false;
            var woke = e.motion > mCfg.wakeMotionThreshold;
            var hr = e.hrMean;
            var baseHr = rem.hrBase();
            if (!woke && hr != null && baseHr != null
                    && hr >= baseHr * (1.0d + LcConst.WAKE_HR_JUMP)) {
                woke = true;
            }
            if (woke) {
                mEvent = "wake_after_cue";
                var lowered = mBaseLevel - mCfg.levelStep;
                if (lowered < mCfg.levelMin) { // max(level_min, base_level - level_step)
                    lowered = mCfg.levelMin;
                }
                mBaseLevel = lowered;
                mCooldown = LcConst.WAKE_COOLDOWN_SEC;
                mFinishedEpisodeId = mCurEpisodeId;
                mWakesAfterCue += 1;
                mLastCueAbsorbed = false;
            } else {
                mEvent = "absorbed";
                mCooldown = LcConst.COOLDOWN_SEC;
                mLastCueAbsorbed = true;
            }
        }

        // A new episode id starts fresh.
        var epId = rem.episodeId();
        if (epId != mCurEpisodeId) {
            mCurEpisodeId = epId;
            mCuesInEpisode = 0;
        }

        // 2. Gates.
        var gatesOk = false;
        var onset = onsetT;
        if (state == STATE_ASLEEP && rem.episodeActive() && onset != null) {
            gatesOk = (e.t - onset).toDouble() >= mCfg.earliestCueHours * 3600.0d
                && mCuesTonight < mCfg.maxCuesPerNight
                && mFinishedEpisodeId != mCurEpisodeId;
        }
        if (!gatesOk) {
            mFire = false;
            mLevel = mBaseLevel;
            return;
        }

        var lvl = mBaseLevel;
        var doFire = false;
        var lastT = mLastCueT;
        if (mCuesInEpisode == 0) {
            // 3. First cue in an episode.
            if (lastT == null) {
                doFire = true;
            } else if (e.t - (lastT as Number) >= mCooldown) {
                doFire = true;
            }
        } else if (lastT != null) {
            // 4. Ramp cue. (A cue fired this episode, so lastT is never null here.)
            if (e.t - (lastT as Number) >= LcConst.RAMP_SEC && mLastCueAbsorbed) {
                doFire = true;
                lvl = mBaseLevel + mCfg.levelStep * mCuesInEpisode;
                if (lvl > mCfg.levelMax) { // min(level_max, ...)
                    lvl = mCfg.levelMax;
                }
            }
        }

        if (!doFire) {
            mFire = false;
            mLevel = mBaseLevel;
            return;
        }

        mCuesInEpisode += 1;
        mCuesTonight += 1;
        mLastCueT = e.t;
        mLastCueAbsorbed = false;
        mPendingReaction = true;
        mCueLog.add([e.t, lvl] as Array<Number>);

        // 5. Episode is finished after MAX_PER_EPISODE cues (or the night cap).
        if (mCuesInEpisode >= LcConst.MAX_PER_EPISODE || mCuesTonight >= mCfg.maxCuesPerNight) {
            mFinishedEpisodeId = mCurEpisodeId;
        }
        mFire = true;
        mLevel = lvl;
    }
}
