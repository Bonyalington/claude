# LucidCue — Garmin REM-Cue App for Lucid Dreaming

**Date:** 2026-10-09
**Status:** Draft for review
**Target device:** Garmin Epix Pro (Gen 2)
**Distribution:** Personal sideload only (not published to the Connect IQ Store)

## 1. Purpose

A Connect IQ watch app that estimates when the wearer is in REM sleep and
delivers a gentle, recognisable vibration ("the cue"). With pre-sleep
training, the wearer learns to recognise the cue inside a dream and realise
they are dreaming (become lucid).

The user is new to lucid dreaming, so the app includes the training that
makes a cue meaningful, not only the night-time cue.

### Success criteria

- The cue is felt during dreams without regularly waking the wearer.
- Cues fire mostly during REM. Measured during calibration: at least 60% of
  REM-flagged epochs fall in Garmin-reported REM.
- Battery drain is acceptable overnight (target: ≤ 10% per night; measured
  during calibration).
- The morning log shows, over weeks, whether cues are felt and whether
  lucidity is happening, so settings can be tuned.

### Non-goals

Phone companion app, cloud backend, Connect IQ Store publishing, audio cues,
medical-grade sleep staging.

## 2. Constraints and known unknowns

- Garmin's built-in sleep stages are **not** available to apps in real time.
  REM must be estimated on-watch from raw sensors.
- Background services are limited (≈ every 5 min, ≈ 30 s run time), too
  coarse for this. Night mode therefore runs as a **foreground watch app**
  all night with the display off.
- The Epix Pro has an AMOLED display. Night mode must keep the screen black
  and suppress backlight. Display is shown only on button press, dimmed.

**To verify on the first device build.** Garmin docs were unreachable from
the authoring environment:

| Unknown | If supported | If not |
|---|---|---|
| `heartBeatIntervals` (beat-to-beat) via sensor data listener on Epix Pro | Use RMSSD for variability | Use within-epoch HR standard deviation; condition 2b can be disabled |
| `Attention.VibeProfile` duty cycle (intensity) honoured | Ramp intensity | Ramp by pulse count / pulse length instead |
| Vibration from a background service | Daytime reality-check prompts on watch | Daytime prompts via phone reminders; cue learned via bedtime training only |
| `System.println` → `GARMIN/APPS/LOGS/<APP>.TXT` on sideloaded app (found: ~5 KB cap plus one `.BAK`, §4.7) | Primary log export | Fall back to `Application.Storage` and dump on Summary screen |

## 3. User flow

Main menu: **Train**, **Start Night**, **Buzz test**, **Settings**. Buzz test plays levels
10/30/50/80 so the user can check whether intensity is honoured.

### 3.1 Train (bedtime, ~5 min)

1. User opens LucidCue → **Train**.
2. The watch plays the signature cue `trainReps` times (default 5), ~30 s apart.
3. At each cue the user does a reality check (look at hands, or pinch nose
   and try to breathe) and thinks: *"When I feel this, I'm dreaming."*
4. The final screen offers **Start Night** (one press).

### 3.2 Night (all night, screen off)

Runs sensing → sleep state → REM detection → cue control → logging
(Section 4). Pressing a button shows a dim status screen: elapsed time,
state, cues fired. Back is ignored in Night mode. Pressing START again while the
status screen is up asks "End night?", and Yes opens Morning.

### 3.3 Morning check-in (~20 s)

Three yes/no prompts:
1. Remember a dream?
2. Felt the cue in a dream?
3. Became lucid?

Then a Summary screen: sleep-onset time, cue times and levels, wake-after-cue
count. Answers and the summary are appended to the log.

### 3.4 Calibration (first 3 nights)

`calibrationMode = true` (default on first install): everything runs and
logs, but `CueController` never vibrates. Logged "would-have-cued" events are
recorded. After 3 nights, the calibration script (Section 6) is run against
Garmin Connect sleep stages to set thresholds and measure battery. Then the
user sets `calibrationMode = false`.

## 4. Night-mode logic

### 4.1 Sensing — `SensorSampler`

- Accelerometer at ~10 Hz plus heart rate (and beat intervals if available)
  via the sensor data listener.
- Every 30 s, emits raw buffers for one **epoch** to `EpochFeatures`.

### 4.2 Features — `EpochFeatures` (pure)

Per 30 s epoch:
- `motion`: sum over samples of |‖a‖ − 1 g| above a small noise floor
  (activity-count style).
- `hrMean`: mean heart rate.
- `hrVar`: RMSSD of beat intervals if available, else standard deviation of
  HR samples.

### 4.3 Sleep state — `SleepStateMachine` (pure)

States: `AWAKE → SETTLING → ASLEEP`.
- `AWAKE → SETTLING`: motion below `stillThreshold` for an epoch.
- `SETTLING → ASLEEP`: 15 consecutive min (30 epochs) of low motion with
  `hrMean` below the pre-sleep reference (mean HR of the first 10 min after
  Night starts). Records `sleepOnsetTime`.
- Any state → `AWAKE`: sustained high motion (≥ 2 min above
  `wakeMotionThreshold`). A later return to `ASLEEP` keeps the original
  `sleepOnsetTime` unless awake lasted > 30 min. In that case onset is reset.

### 4.4 REM detection — `RemDetector` (pure)

Maintains **rolling baselines** over the last 60 min of still `ASLEEP`
epochs: `hrBase`, `varBase`.

An epoch is **REM-like** when:
1. Motion has been below `stillThreshold` for ≥ 5 min (atonia proxy), and
2. Either:
   a. `hrMean ≥ hrBase × (1 + hrRise)` (default `hrRise` = 0.05), or
   b. `hrVar ≥ varBase × varRatio` (default `varRatio` = 1.3).

A **REM episode** is declared after 6 consecutive REM-like epochs (3 min).
It ends after 2 consecutive non-REM-like epochs or any wake.

Defaults are placeholders. Calibration replaces `hrRise` and `varRatio`.

### 4.5 Cue control — `CueController` (pure decision + `Vibe` side effect)

A cue may fire only when all of these hold:
- A REM episode is active.
- `now − sleepOnsetTime ≥ earliestCueHours` (default 4.5 h).
- `now − lastCueTime ≥ 10 min` (or 20 min after a wake-after-cue).
- `cuesTonight < maxCuesPerNight` (default 6).
- `calibrationMode == false` (otherwise log a "would-cue" event only).

**Ramp within an episode:** first cue at `level`. If still in REM and no
motion response 2 min later, repeat at `level + step`. At most 3 cues per
episode. Repeat cues within an episode are exempt from the 10-min cooldown
but count toward `maxCuesPerNight`.

**Wake-after-cue:** motion above `wakeMotionThreshold` within 30 s of a cue,
or HR jumping ≥ 15% over `hrBase`, counts as a wake. Then `level` is lowered by
one step for the rest of the night, the cooldown becomes 20 min, and the
episode ends.

**No response:** logged as either "absorbed" or "too faint". The morning
answers distinguish these over time.

### 4.6 Signature cue — `Vibe`

Three short pulses (~150 ms on / 150 ms off). Intensity starts at
`startLevel` (default 30% duty) with `step` = 15%, capped at 80%. If duty
cycle is not honoured on device, levels map to longer pulses instead
(150 → 250 → 400 ms). Train mode uses the exact same pattern at the current
`startLevel`.

### 4.7 Logging — `NightLog`

**Device finding (first real night):** the watch caps the sideload log at
about 5 KB. When `LUCIDCUE.TXT` is full it is renamed `LUCIDCUE.BAK`
(replacing the previous `.BAK`) and a new `.TXT` starts, so only those two
files survive. The first format, one ~50-byte CSV line per epoch (~50 KB a
night), kept only the last ~66 minutes (the `.BAK` was 5,137 bytes). A whole
night of up to 10–11 h, events included, must therefore fit in about 9 KB.

**Epoch batches:** `D,<t0>,<payload>`, one line per 20 epochs (10 min).
- `t0` is the Unix time of the batch's first epoch; epoch `i` is at
  `t0 + 30*i`.
- The payload has 6 characters per epoch: three 12-bit values, each as 2
  characters of the base64url alphabet
  `A–Z a–z 0–9 - _` (no commas), high 6 bits first:
  - motion: `q = min(4094, motion / 4)`, decoded `q*4`;
  - hrMean: `round(hr*10)` (half up), capped at 4094, 4095 = null, decoded
    `q/10`;
  - hrVar: `round(var*100)` (half up), capped at 4094, 4095 = null, decoded
    `q/100`.

  So motion is stored 0–3 mg low (the 500 and 5000 thresholds keep their side),
  HR to ±0.05 and variability to ±0.005, the same precision as the old 1- and
  2-decimal fields.
- The pending batch is written early (a partial line) before every `X` line,
  at the end of the night, and when an epoch is more than 10 s off the
  batch's 30 s grid (a Timer stall), so `t0 + 30*i` holds and line times
  never go backwards in the file.
- Sleep state, baselines, REM flag and episode are no longer logged. The
  calibration script recomputes them from the epochs with the Python model.

**Event lines:** `X,<t>,<name>,<detail>` (no commas in the detail; `;`-separated
`k=v`): `night_start` (all settings), `caps`, `onset`, `cue` / `wouldcue`
(`level=<n>`), `wake_after_cue`, `absorbed`, `battery` (start and end),
`night_end`, `morning`.

**Size:** about 0.9 KB per hour. A 10-hour night is about 9.0 KB (1,200
epochs plus ~0.8 KB of events; `model/tests/test_logformat.py` checks ≤ 9,500
bytes).

Primary export: `System.println` to the sideload log file
(`GARMIN/APPS/LOGS/LUCIDCUE.TXT`, which the user creates once). Each morning
the user copies `LUCIDCUE.TXT` and `LUCIDCUE.BAK` off over USB, then empties
the `.TXT` and deletes the `.BAK`. `tools/calibrate.py` takes both files (in
any order) and still reads the old one-`E`-line-per-epoch format.

## 5. Settings (Connect IQ phone app)

| Setting | Default | Range |
|---|---|---|
| `calibrationMode` | true | bool |
| `earliestCueHours` | 4.5 | 2.0–7.0 |
| `maxCuesPerNight` | 6 | 1–10 |
| `startLevel` | 30 | 10–80 (% duty) |
| `trainReps` | 5 | 3–10 |
| `hrRise` | 0.05 | 0.00–0.20 |
| `varRatio` | 1.3 | 1.0–2.0 |
| `vibeByLength` | false | bool (ramp by pulse length when intensity is not honoured) |

`calibrationMode` and `vibeByLength` are also on the watch (main menu → Settings), since phone settings may not appear for a sideloaded app; a change applies from the next night.

## 6. Calibration script (desktop, Python)

`tools/calibrate.py`:
- Reads `LUCIDCUE.TXT` + `LUCIDCUE.BAK` (§4.7) and a Garmin Connect
  sleep-stage export for the same night.
- Plots motion, HR, variability, REM-like flags and Garmin stages on one
  timeline.
- Grid-searches `hrRise` and `varRatio` to maximise agreement with Garmin
  REM (precision-weighted, since false cues cost more than missed ones).
- Reports battery drain per night.

## 7. Code layout

```
lucidcue/
  manifest.xml            # target epixpro gen2 variants, Sensor permission
  monkey.jungle
  resources/
    properties.xml settings.xml strings.xml
  source/
    LucidCueApp.mc        # entry, mode routing
    SensorSampler.mc
    EpochFeatures.mc      # pure
    SleepStateMachine.mc  # pure
    RemDetector.mc        # pure
    CueController.mc      # pure decisions
    Vibe.mc
    NightLog.mc
    views/ TrainView.mc NightView.mc MorningView.mc SummaryView.mc
  test/                   # (:test) unit tests run in simulator
model/                    # Python reference model of the pure logic (pytest); used by tools
tools/
  calibrate.py
  gen_fixtures.py         # writes Monkey C replay fixtures from the Python model
docs/
  SETUP.md                # SDK install, dev key, build, sideload, log retrieval
```

## 8. Testing

- **Unit tests** (Connect IQ `(:test)`, run in the simulator) for
  `EpochFeatures`, `SleepStateMachine`, `RemDetector` and `CueController`:
  state transitions, baseline maths, cooldowns, caps, ramp and wake-backoff.
- **Replay test:** a scripted night (awake → onset → NREM/REM cycles → wake)
  fed epoch by epoch, asserting cue times and counts.
- **On-device:** first build run for one evening to confirm the Section 2
  unknowns. Then 3 calibration nights.

## 9. Build environment

The Connect IQ SDK and developer key are needed on the user's own computer
(macOS, Windows or Linux). The authoring environment cannot reach Garmin's
servers, so code is written here and built and sideloaded by the user.
`docs/SETUP.md` covers this step by step.

## 10. Future ideas (not in v1)

Daytime cue prompts (pending the background-vibration check), adaptive
`earliestCueHours` from REM history, phone companion for log sync, and
MILD/WBTB-aware scheduling once the user progresses.
