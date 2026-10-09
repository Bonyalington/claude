import Toybox.Lang;

// REM detector: HR rise or HR-variability rise over a rolling still-sleep baseline.
// Rule-for-rule port of model/lucidcue_model/rem.py (same order of operations).
// Python's step() returns a RemStatus; here step() stores it and the getters
// (remLike, episodeActive, episodeId, hrBase, varBase) read it back.
class RemDetector {
    var mCfg as LcConfig;
    // Baseline window: the last BASE_EPOCHS qualifying epochs (Python's two
    // deque(maxlen=BASE_EPOCHS), always appended together). Ring buffers sharing a
    // write index and a count; means iterate oldest -> newest like the deques, so
    // the Double sums are added in the same order as Python's loops.
    var mBaseHr as Array<Double>;            // hr_mean of baseline epochs
    var mBaseVar as Array<Double or Null>;   // hr_var of baseline epochs (may be null)
    var mBaseNext as Number = 0;             // next write index
    var mBaseCount as Number = 0;            // entries held, <= BASE_EPOCHS
    var mStillRun as Number = 0;             // consecutive still epochs (any state)
    var mRemRun as Number = 0;               // consecutive rem_like epochs
    var mNonRemRun as Number = 0;            // consecutive non-rem_like epochs
    var mEpisodeActive as Boolean = false;
    var mEpisodeId as Number = 0;            // last episode number; 0 before the first
    // Outputs of the last step() (Python RemStatus rem_like / hr_base / var_base).
    var mRemLike as Boolean = false;
    var mHrBase as Double or Null = null;
    var mVarBase as Double or Null = null;

    function initialize(cfg as LcConfig) {
        mCfg = cfg;
        mBaseHr = new [LcConst.BASE_EPOCHS] as Array<Double>;
        mBaseVar = new [LcConst.BASE_EPOCHS] as Array<Double or Null>;
    }

    function remLike() as Boolean {
        return mRemLike;
    }

    function episodeActive() as Boolean {
        return mEpisodeActive;
    }

    function episodeId() as Number {
        return mEpisodeId;
    }

    function hrBase() as Double or Null {
        return mHrBase;
    }

    function varBase() as Double or Null {
        return mVarBase;
    }

    function step(e as Epoch, state as Number) as Void {
        var isStill = e.motion < mCfg.stillThreshold;
        if (isStill) {
            mStillRun += 1;
        } else {
            mStillRun = 0;
        }

        // Baselines are computed before the current epoch is added.
        mHrBase = null;
        mVarBase = null;
        if (mBaseCount >= LcConst.BASE_MIN_EPOCHS) {
            // Oldest entry: index 0 until the buffer first wraps, then mBaseNext.
            var start = mBaseNext - mBaseCount;
            if (start < 0) {
                start += LcConst.BASE_EPOCHS;
            }
            var total = 0.0d;
            for (var k = 0; k < mBaseCount; k++) {
                total += mBaseHr[(start + k) % LcConst.BASE_EPOCHS];
            }
            mHrBase = total / mBaseCount.toDouble();
            var varTotal = 0.0d;
            var varCount = 0;
            for (var j = 0; j < mBaseCount; j++) {
                var v = mBaseVar[(start + j) % LcConst.BASE_EPOCHS];
                if (v != null) {
                    varTotal += v;
                    varCount += 1;
                }
            }
            if (varCount > 0) {
                mVarBase = varTotal / varCount.toDouble();
            }
        }
        var baseHr = mHrBase;
        var baseVar = mVarBase;

        var asleep = state == STATE_ASLEEP;
        var hr = e.hrMean;
        var hrVar = e.hrVar;

        var isRem = false;
        if (asleep && mStillRun >= LcConst.STILL_RUN_EPOCHS && hr != null && baseHr != null) {
            if (hr >= baseHr * (1.0d + mCfg.hrRise)) {
                isRem = true;
            } else if (hrVar != null && baseVar != null && hrVar >= baseVar * mCfg.varRatio) {
                isRem = true;
            }
        }
        mRemLike = isRem;

        // Baseline entry: asleep, still, non-null HR (rem_like epochs included).
        if (asleep && isStill && hr != null) {
            mBaseHr[mBaseNext] = hr;
            mBaseVar[mBaseNext] = hrVar;
            mBaseNext = (mBaseNext + 1) % LcConst.BASE_EPOCHS;
            if (mBaseCount < LcConst.BASE_EPOCHS) {
                mBaseCount += 1;
            }
        }

        // Episode bookkeeping.
        if (!asleep) {
            mEpisodeActive = false;
            mRemRun = 0;
            mNonRemRun = 0;
        } else if (isRem) {
            mRemRun += 1;
            mNonRemRun = 0;
            if (!mEpisodeActive && mRemRun >= LcConst.EPISODE_START) {
                mEpisodeActive = true;
                mEpisodeId += 1;
            }
        } else {
            mNonRemRun += 1;
            mRemRun = 0;
            if (mEpisodeActive && mNonRemRun >= LcConst.EPISODE_END) {
                mEpisodeActive = false;
            }
        }
    }
}
