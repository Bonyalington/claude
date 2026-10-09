import Toybox.Lang;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.Timer;

// Collects raw sensor data and turns it into one Epoch every 30 s.
//   - Accelerometer x/y/z (mg) at 10 Hz and beat-to-beat intervals (ms), delivered once
//     a second by the sensor data listener (:period => 1).
//   - Heart rate (bpm) at 1 Hz from Sensor.enableSensorEvents (info.heartRate, may be null).
//   - A 30 000 ms repeating timer builds the epoch with EpochFeatures.build, clears the
//     buffers and calls onEpoch.
// The sensor callbacks only append to buffers; all maths runs in the 30 s callback.
class SensorSampler {
    var mCfg as LcConfig;
    var mOnEpoch as Method(e as Epoch) as Void;
    var mXs as Array<Number>;
    var mYs as Array<Number>;
    var mZs as Array<Number>;
    var mHr as Array<Number or Null>;
    var mIntervals as Array<Number>;
    var mHasBeatIntervals as Boolean = false;
    var mHasAccel as Boolean = false;
    var mStarted as Boolean = false;
    var mListening as Boolean = false;
    var mTimer as Timer.Timer or Null = null;

    function initialize(cfg as LcConfig, onEpoch as Method(e as Epoch) as Void) {
        mCfg = cfg;
        mOnEpoch = onEpoch;
        mXs = [] as Array<Number>;
        mYs = [] as Array<Number>;
        mZs = [] as Array<Number>;
        mHr = [] as Array<Number or Null>;
        mIntervals = [] as Array<Number>;
    }

    // True once any non-empty beat-to-beat interval array has arrived.
    function hasBeatIntervals() as Boolean {
        return mHasBeatIntervals;
    }

    // True once any non-empty accelerometer array has arrived.
    function hasAccel() as Boolean {
        return mHasAccel;
    }

    // Idempotent: a second start() while running does nothing.
    function start() as Void {
        if (mStarted) {
            return;
        }
        mStarted = true;
        clearBuffers();
        if (Sensor has :registerSensorDataListener) {
            try {
                Sensor.registerSensorDataListener(method(:onSensorData), {
                    :period => 1,
                    :accelerometer => {
                        :enabled => true,
                        :sampleRate => 10
                    },
                    :heartBeatIntervals => {
                        :enabled => true
                    }
                });
                mListening = true;
            } catch (ex) {
                // No accelerometer / interval data: epochs then have motion =
                // stillThreshold (lcSampledEpoch) and the HR-std fallback for
                // variability. hasAccel() stays false, so NightController also turns
                // buzzing off at the 60 s caps check (R16a).
                mListening = false;
            }
        }
        if (Sensor has :setEnabledSensors) {
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE] as Array<Sensor.SensorType>);
        }
        if (Sensor has :enableSensorEvents) {
            Sensor.enableSensorEvents(method(:onSensorInfo));
        }
        var timer = new Timer.Timer();
        timer.start(method(:onTimer), LcConst.EPOCH_SEC * 1000, true);
        mTimer = timer;
    }

    function stop() as Void {
        mStarted = false;
        var timer = mTimer;
        if (timer != null) {
            timer.stop();
            mTimer = null;
        }
        if (mListening && (Sensor has :unregisterSensorDataListener)) {
            Sensor.unregisterSensorDataListener();
        }
        mListening = false;
        if (Sensor has :enableSensorEvents) {
            Sensor.enableSensorEvents(null);
        }
        if (Sensor has :setEnabledSensors) {
            Sensor.setEnabledSensors([] as Array<Sensor.SensorType>);
        }
    }

    // Sensor data listener: 10 accelerometer samples per axis and any beat intervals.
    function onSensorData(data as Sensor.SensorData) as Void {
        var acc = data.accelerometerData;
        if (acc != null) {
            var xs = acc.x;
            var ys = acc.y;
            var zs = acc.z;
            if (xs != null && ys != null && zs != null) {
                mXs.addAll(xs);
                mYs.addAll(ys);
                mZs.addAll(zs);
                if (xs.size() > 0) {
                    mHasAccel = true;
                }
            }
        }
        var hrd = data.heartRateData;
        if (hrd != null) {
            var ibi = hrd.heartBeatIntervals;
            if (ibi != null && ibi.size() > 0) {
                mIntervals.addAll(ibi);
                mHasBeatIntervals = true;
            }
        }
    }

    // 1 Hz sensor event: one HR sample (null when there is no reading).
    function onSensorInfo(info as Sensor.Info) as Void {
        mHr.add(info.heartRate);
    }

    // Every 30 s: build the epoch from the buffers, clear them, hand the epoch on.
    // An epoch without accelerometer samples gets motion = stillThreshold (see
    // lcSampledEpoch), so a mid-night accelerometer dropout never reads as "still".
    function onTimer() as Void {
        var e = $.lcSampledEpoch(Time.now().value(), mXs, mYs, mZs, mHr, mIntervals, mCfg);
        clearBuffers();
        mOnEpoch.invoke(e);
    }

    function clearBuffers() as Void {
        mXs = [] as Array<Number>;
        mYs = [] as Array<Number>;
        mZs = [] as Array<Number>;
        mHr = [] as Array<Number or Null>;
        mIntervals = [] as Array<Number>;
    }
}

// Builds one epoch from the sampler's buffers (pure, so it can be unit-tested).
// Accelerometer dropout rule: if any accelerometer axis has no samples this epoch (the
// listener stopped delivering mid-night), motionScore would return 0, which reads as
// perfectly still and lets REM-like and onset progress build up on no data. Such an
// epoch instead gets motion = cfg.stillThreshold: "not still" (still means motion <
// stillThreshold) but far below wakeMotionThreshold, so it breaks the still / onset runs
// and cannot be REM-like, without counting toward a wake. HR fields are unchanged.
// This is a sampler rule, not part of the Python model (which never sees empty buffers).
function lcSampledEpoch(t as Number, xs as Array<Number>, ys as Array<Number>,
        zs as Array<Number>, hr as Array<Number or Null>, intervals as Array<Number>,
        cfg as LcConfig) as Epoch {
    var e = EpochFeatures.build(t, xs, ys, zs, hr, intervals, cfg);
    if (xs.size() == 0 || ys.size() == 0 || zs.size() == 0) {
        e.motion = cfg.stillThreshold;
    }
    return e;
}
