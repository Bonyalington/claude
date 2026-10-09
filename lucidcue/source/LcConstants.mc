import Toybox.Lang;

// Fixed algorithm constants (not user-tunable). Verbatim port of the module
// constants in model/lucidcue_model/config.py. Used as LcConst.REF_EPOCHS etc.
module LcConst {
    const EPOCH_SEC = 30;
    const REF_EPOCHS = 20;
    const ONSET_EPOCHS = 30;
    const WAKE_EPOCHS = 4;
    const ONSET_RESET_SEC = 1800;
    const BASE_EPOCHS = 120;
    const BASE_MIN_EPOCHS = 10;
    const STILL_RUN_EPOCHS = 10;
    const EPISODE_START = 6;
    const EPISODE_END = 2;
    const COOLDOWN_SEC = 600;
    const WAKE_COOLDOWN_SEC = 1200;
    const RAMP_SEC = 120;
    const MAX_PER_EPISODE = 3;
    const WAKE_HR_JUMP = 0.15d;
}
