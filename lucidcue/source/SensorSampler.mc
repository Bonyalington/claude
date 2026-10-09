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

    function start() as Void {
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
                // No accelerometer / interval data: epochs then have motion 0 and the
                // HR-std fallback for variability. The night still runs on HR.
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
    function onTimer() as Void {
        var e = EpochFeatures.build(Time.now().value(), mXs, mYs, mZs, mHr, mIntervals, mCfg);
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
