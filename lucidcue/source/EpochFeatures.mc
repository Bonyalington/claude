import Toybox.Lang;
import Toybox.Math;

// Per-epoch feature extraction from raw accelerometer, HR and interval data.
// Rule-for-rule port of model/lucidcue_model/features.py. HR maths is in Double.
module EpochFeatures {

    // Sum of per-sample deviation of |accel| from 1 g (1000 mg), minus the noise floor.
    // Like Python zip(), mismatched axes are truncated to the shortest.
    function motionScore(xs as Array<Number>, ys as Array<Number>, zs as Array<Number>,
            noiseFloorMg as Number) as Number {
        var n = xs.size();
        if (ys.size() < n) {
            n = ys.size();
        }
        if (zs.size() < n) {
            n = zs.size();
        }
        var total = 0;
        for (var k = 0; k < n; k++) {
            var x = xs[k].toDouble();
            var y = ys[k].toDouble();
            var z = zs[k].toDouble();
            // Round half up: floor(sqrt + 0.5). The value is >= 0, so toNumber()
            // (truncation toward zero) equals floor().
            var mag = (Math.sqrt(x * x + y * y + z * z).toDouble() + 0.5d).toNumber();
            var dev = mag - 1000;
            if (dev < 0) {
                dev = -dev;
            }
            dev = dev - noiseFloorMg;
            if (dev > 0) {
                total += dev;
            }
        }
        return total;
    }

    // Valid HR samples, as Python _valid(): `if s` drops None and 0 (negatives are kept).
    // hrMean and hrStd apply the same filter inline.
    function hrMean(samples as Array<Number or Null>) as Double or Null {
        var sum = 0;
        var count = 0;
        for (var k = 0; k < samples.size(); k++) {
            var s = samples[k];
            if (s != null && s != 0) {
                sum += s;
                count += 1;
            }
        }
        if (count == 0) {
            return null;
        }
        return sum.toDouble() / count.toDouble();
    }

    // Population standard deviation; null with fewer than 2 valid samples.
    function hrStd(samples as Array<Number or Null>) as Double or Null {
        var sum = 0;
        var count = 0;
        for (var k = 0; k < samples.size(); k++) {
            var s = samples[k];
            if (s != null && s != 0) {
                sum += s;
                count += 1;
            }
        }
        if (count < 2) {
            return null;
        }
        var m = sum.toDouble() / count.toDouble();
        var sq = 0.0d;
        for (var j = 0; j < samples.size(); j++) {
            var s2 = samples[j];
            if (s2 != null && s2 != 0) {
                var d = s2.toDouble() - m;
                sq += d * d;
            }
        }
        return Math.sqrt(sq / count.toDouble()).toDouble();
    }

    // Root mean square of successive differences; null with fewer than 2 intervals.
    // Squares are summed in Double: exact for integers, and no 32-bit overflow.
    function rmssd(intervals as Array<Number>) as Double or Null {
        var n = intervals.size();
        if (n < 2) {
            return null;
        }
        var sq = 0.0d;
        for (var k = 1; k < n; k++) {
            var d = (intervals[k] - intervals[k - 1]).toDouble();
            sq += d * d;
        }
        return Math.sqrt(sq / (n - 1).toDouble()).toDouble();
    }

    // Port of epoch_features(): RMSSD when there are >= 2 intervals, else HR std.
    function build(t as Number, xs as Array<Number>, ys as Array<Number>,
            zs as Array<Number>, hrSamples as Array<Number or Null>,
            intervals as Array<Number>, cfg as LcConfig) as Epoch {
        var hrVar = (intervals.size() >= 2) ? rmssd(intervals) : hrStd(hrSamples);
        return new Epoch(t, motionScore(xs, ys, zs, cfg.noiseFloorMg),
            hrMean(hrSamples), hrVar);
    }
}
