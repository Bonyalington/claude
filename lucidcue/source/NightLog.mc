import Toybox.Lang;
import Toybox.System;

// Night log lines (spec §4.7). On a sideloaded app System.println goes to
// GARMIN/APPS/LOGS/LUCIDCUE.TXT. The watch caps that file at about 5 KB: a full file is
// renamed LUCIDCUE.BAK (replacing the old one) and a new TXT starts, so a whole night
// must fit in about 9 KB. Lines must parse with model/lucidcue_model/logparse.py:
//   D,<t0>,<payload>        a batch of epochs (NightSession: 20, fewer at a flush);
//                           epoch i is at t0 + 30*i; 6 payload characters per epoch
//                           (lcEncodeEpoch)
//   X,<t>,<name>,<detail>   (detail must contain no commas: use ;-separated k=v)
class NightLog {
    function initialize() {
    }

    function batchLine(t0 as Number, payload as String) as String {
        return "D," + t0 + "," + payload;
    }

    function eventLine(t as Number, name as String, detail as String) as String {
        return "X," + t + "," + name + "," + detail;
    }

    function write(line as String) as Void {
        System.println(line);
    }
}

// base64url alphabet (no commas). Mirrored by B64 in model/lucidcue_model/logparse.py.
const LC_B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
const LC_Q_MAX = 4094;    // largest stored 12-bit value (larger inputs are capped)
const LC_Q_NULL = 4095;   // null hrMean / hrVar

// A 12-bit value (0..4095) as 2 base64url characters, high 6 bits first.
function lcB64x2(v as Number) as String {
    var chars = $.LC_B64.toCharArray();
    return chars[(v >> 6) & 63].toString() + chars[v & 63].toString();
}

// x * scale rounded half up, clamped to 0..LC_Q_MAX; null -> LC_Q_NULL. Same double
// operations as the Python mirror (model/tests/logwriter.py quant).
function lcQuant(x as Double or Null, scale as Double) as Number {
    if (x == null) {
        return $.LC_Q_NULL;
    }
    var d = (x as Double) * scale + 0.5d;
    if (d >= 4094.0d) {
        return $.LC_Q_MAX;
    }
    if (d < 0.0d) {
        return 0;
    }
    return d.toNumber();
}

// One epoch as 6 characters: motion / 4 (capped at 4094), round(hrMean * 10) and
// round(hrVar * 100) (capped at 4094, 4095 for null). Decoded: motion q*4, hr q/10.0,
// var q/100.0. Motion thresholds that are multiples of 4 (500, 5000) keep their side.
function lcEncodeEpoch(e as Epoch) as String {
    var m = e.motion / 4;
    if (m > $.LC_Q_MAX) {
        m = $.LC_Q_MAX;
    }
    if (m < 0) {
        m = 0;
    }
    return $.lcB64x2(m) + $.lcB64x2($.lcQuant(e.hrMean, 10.0d))
        + $.lcB64x2($.lcQuant(e.hrVar, 100.0d));
}
