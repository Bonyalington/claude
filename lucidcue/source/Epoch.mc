import Toybox.Lang;

// One 30 s epoch of features. Port of model/lucidcue_model/features.py `Epoch`.
// t is Unix seconds; motion is the summed accelerometer deviation (mg);
// hrMean / hrVar are null when there was too little valid data.
class Epoch {
    var t as Number = 0;
    var motion as Number = 0;
    var hrMean as Double or Null = null;
    var hrVar as Double or Null = null;

    function initialize(aT as Number, aMotion as Number, aHrMean as Double or Null,
            aHrVar as Double or Null) {
        t = aT;
        motion = aMotion;
        hrMean = aHrMean;
        hrVar = aHrVar;
    }
}
