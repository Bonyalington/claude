import Toybox.Lang;

// Sleep state machine: AWAKE -> SETTLING -> ASLEEP, with wake detection and onset time.
// Rule-for-rule port of model/lucidcue_model/sleep_state.py (same order of operations).

enum {
    STATE_AWAKE = 0,
    STATE_SETTLING = 1,
    STATE_ASLEEP = 2
}

// The Python model's state strings, for logs and display.
function stateName(s as Number) as String {
    if (s == STATE_AWAKE) {
        return "AWAKE";
    }
    if (s == STATE_SETTLING) {
        return "SETTLING";
    }
    if (s == STATE_ASLEEP) {
        return "ASLEEP";
    }
    return "UNKNOWN";
}

class SleepStateMachine {
    var mCfg as LcConfig;
    var mState as Number = STATE_AWAKE;
    // Current sleep onset time (kept across short wakes). Persists after the first
    // onset; consumers must gate on state() == STATE_ASLEEP.
    var mOnsetT as Number or Null = null;
    var mEpochIndex as Number = 0;        // epochs stepped so far
    var mRefSum as Double = 0.0d;         // pre-sleep HR reference accumulation
    var mRefCount as Number = 0;
    var mRef as Double or Null = null;    // fixed once REF_EPOCHS epochs have been seen
    var mWakeRun as Number = 0;           // consecutive wake epochs
    var mWakeRunStartT as Number = 0;     // t of the first epoch of the current wake run
    var mAwakeSince as Number or Null = null; // t of first epoch of the wake run that caused AWAKE
    var mOnsetRun as Number = 0;          // consecutive qualifying epochs while SETTLING
    var mRunStartT as Number = 0;         // t of the first epoch of the onset run

    function initialize(cfg as LcConfig) {
        mCfg = cfg;
    }

    function state() as Number {
        return mState;
    }

    function onsetT() as Number or Null {
        return mOnsetT;
    }

    // Used by tests only (test/ReplayTest.mc): sets every field from a checkpoint of
    // the Python SleepStateMachine (tools/gen_fixtures.py SM_FIELDS, same order).
    function restore(aState as Number, aOnsetT as Number or Null, aEpochIndex as Number,
            aRefSum as Double, aRefCount as Number, aRef as Double or Null,
            aWakeRun as Number, aWakeRunStartT as Number, aAwakeSince as Number or Null,
            aOnsetRun as Number, aRunStartT as Number) as Void {
        mState = aState;
        mOnsetT = aOnsetT;
        mEpochIndex = aEpochIndex;
        mRefSum = aRefSum;
        mRefCount = aRefCount;
        mRef = aRef;
        mWakeRun = aWakeRun;
        mWakeRunStartT = aWakeRunStartT;
        mAwakeSince = aAwakeSince;
        mOnsetRun = aOnsetRun;
        mRunStartT = aRunStartT;
    }

    function step(e as Epoch) as Void {
        var index = mEpochIndex;
        mEpochIndex += 1;

        // Pre-sleep reference: mean of non-null HR over the first REF_EPOCHS epochs.
        if (index < LcConst.REF_EPOCHS) {
            var hr0 = e.hrMean;
            if (hr0 != null) {
                mRefSum += hr0;
                mRefCount += 1;
            }
            if (index == LcConst.REF_EPOCHS - 1 && mRefCount > 0) {
                mRef = mRefSum / mRefCount.toDouble();
            }
        }

        var isStill = e.motion < mCfg.stillThreshold;
        var isWake = e.motion > mCfg.wakeMotionThreshold;

        // Wake check first, from any state.
        if (isWake) {
            if (mWakeRun == 0) {
                mWakeRunStartT = e.t;
            }
            mWakeRun += 1;
            mOnsetRun = 0;
            if (mWakeRun >= LcConst.WAKE_EPOCHS) {
                if (mState == STATE_ASLEEP) { // only the first wake streak after being asleep
                    mAwakeSince = mWakeRunStartT;
                }
                mState = STATE_AWAKE;
            }
            return;
        }
        mWakeRun = 0;

        if (mState == STATE_AWAKE) {
            if (!isStill) {
                return;
            }
            // The epoch that leaves AWAKE also counts toward the onset run (below).
            mState = STATE_SETTLING;
            mOnsetRun = 0;
        }

        if (mState == STATE_SETTLING) {
            var hr = e.hrMean;
            var refHr = mRef;
            var qualifies = false;
            if (isStill && index >= LcConst.REF_EPOCHS && refHr != null && hr != null) {
                qualifies = hr < refHr;
            }
            if (qualifies) {
                if (mOnsetRun == 0) {
                    mRunStartT = e.t;
                }
                mOnsetRun += 1;
                if (mOnsetRun >= LcConst.ONSET_EPOCHS) {
                    mState = STATE_ASLEEP;
                    // Python: onset_t is None or run_start_t - awake_since > ONSET_RESET_SEC.
                    // mOnsetT != null implies a wake out of ASLEEP happened, which set
                    // mAwakeSince; the null check only satisfies the type checker.
                    var since = mAwakeSince;
                    if (mOnsetT == null) {
                        mOnsetT = mRunStartT;
                    } else if (since != null) {
                        if (mRunStartT - since > LcConst.ONSET_RESET_SEC) {
                            mOnsetT = mRunStartT;
                        }
                    }
                }
            } else {
                mOnsetRun = 0;
            }
        }
    }
}
