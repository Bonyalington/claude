# LucidCue setup guide

This guide takes you from a fresh computer to LucidCue running on your Garmin
Epix Pro (Gen 2). It also covers copying the night log off the watch,
calibrating the REM thresholds, and the first-build checklist.

Nothing here needs prior Garmin development experience. Commands are shown for
macOS / Linux (Terminal) and, where they differ, Windows (PowerShell or
Command Prompt). Run every command from the **repository root**, the folder
that contains `lucidcue/`, `model/`, `tools/` and `docs/`.

> Garmin renames menus and buttons between SDK versions. Wherever this guide
> names an SDK Manager, simulator or VS Code menu item, the exact wording
> **may differ by SDK version**. Look for the closest match.

---

## 0. Find your watch size and its device id

The Epix Pro (Gen 2) comes in three sizes. Each size is a separate "device" for
the compiler, so you must build for yours.

| Watch size | Device id (`-d …`) |
|---|---|
| 42 mm | `epix2pro42mm` |
| 47 mm | `epix2pro47mm` |
| 51 mm | `epix2pro51mm` |

Ways to find your size, easiest first:

1. **The box or receipt** names the size, e.g. "epix Pro (Gen 2) 47 mm".
2. **The back of the watch** is usually engraved with the model and size.
3. **Garmin Connect app** on your phone: tap the watch picture or *Devices*,
   pick the watch, then look for *About* / *Device info*. That screen shows the
   model name and often the size (may differ by app version).
4. **Over USB:** plug the watch in and open `GARMIN/GarminDevice.xml` in a text
   editor. The `<Description>` and part-number fields identify the model. As a
   rough guide, 42 mm ≈ 010-02802, 47 mm ≈ 010-02803, 51 mm ≈ 010-02804. Trust
   the box over these numbers if they disagree.

All commands below use `epix2pro47mm`. **If your watch is 42 mm or 51 mm,
replace `epix2pro47mm` with your id everywhere.**

The ids above are our best knowledge. In step 1, check them against SDK
Manager's device list. If Garmin uses different ids, use theirs in the
commands and fix the three `<iq:product id="…"/>` lines in
`lucidcue/manifest.xml`.

---

## 1. Install the Connect IQ SDK and the Epix Pro device files

1. Install **Java** if you don't have it. The compiler (`monkeyc`) runs on
   Java. Any current JDK (17 or newer) works, for example from
   <https://adoptium.net>. Check it with `java -version`.
2. Download **Connect IQ SDK Manager** from Garmin's developer site
   (developer.garmin.com → Connect IQ → SDK). Install and open it, then sign in
   with your Garmin account if it asks.
3. In SDK Manager:
   - **SDK tab:** download the newest SDK and click *Use as current SDK* (or a
     similar button).
   - **Devices tab:** search for "epix". Download the **epix Pro (Gen 2)**
     entries for your size, or all three. Note the device id shown for each,
     e.g. `epix2pro47mm` (see step 0).
4. Put the SDK's `bin` folder on your `PATH` so `monkeyc`, `monkeydo` and
   `connectiq` work in a terminal. The SDK usually lives in one of these
   places (the version number in the folder name varies):
   - macOS: `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-<version>/bin`
   - Windows: `%APPDATA%\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-<version>\bin`
   - Linux: `~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-<version>/bin`

   macOS / Linux: add this line to `~/.zshrc` or `~/.bashrc`, then open a new
   terminal:
   ```sh
   export PATH="$PATH:<the bin folder above>"
   ```
   Windows: open *Start* → "Edit the system environment variables" →
   *Environment Variables* → under your user, edit **Path** → *New* → paste
   the bin folder, then open a new terminal.
5. Check it worked: `monkeyc --version` should print a version number.

## 2. (Optional) Install VS Code and the Monkey C extension

You don't need this to build. It gives syntax highlighting, error squiggles
and build buttons.

1. Install Visual Studio Code.
2. Open *Extensions*, search for **Monkey C** (publisher: Garmin), and install
   it.
3. Run *Monkey C: Verify Installation* from the command palette
   (Ctrl/Cmd+Shift+P). The command name may differ by extension version.

## 3. Generate a developer key (once)

Every build is signed with your own private key. Generate it once and keep it.
**Never commit it.** The repository's `.gitignore` already ignores `*.der` and
`*.pem`, but the safest place is outside the repository.

macOS / Linux (Windows: run the same command in **Git Bash**, which includes
`openssl`):

```sh
openssl genrsa -out developer_key.pem 4096 && openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

This creates `developer_key.pem` and `developer_key.der`. The build uses the
`.der` file. The commands below assume it sits in the repository root. If you
moved it, for example to `~/garmin/developer_key.der`, change the path after
`-y` to match.

Without `openssl`, VS Code's *Monkey C: Generate a Developer Key* command does
the same job.

Back the key up. Builds signed with a different key may not be able to read
the app's saved data.

## 4. Build the app

```sh
mkdir -p bin
monkeyc -f lucidcue/monkey.jungle -d epix2pro47mm -o bin/LucidCue.prg -y developer_key.der
```

(Windows Command Prompt: `mkdir bin`, then the same `monkeyc` line.)

The output **must** be named `LucidCue.prg`. The watch names the log file
after the PRG, so this name gives you `LUCIDCUE.TXT`.

On success the compiler prints `BUILD SUCCESSFUL` (or similar) and creates
`bin/LucidCue.prg`. A warning that the launcher icon is "not the expected
size" and will be scaled is harmless.

### 4.1 If the build or tests fail

The app was written without access to the Connect IQ compiler, so a few API
details are educated guesses. If the build, the tests (§5) or the simulator
walk-through fail, find the symptom below. Each row names the file to change
and the most likely fix. The code expects Gradual type checking, the
default. If your setup uses a stricter level, add `-l 1` to the `monkeyc`
commands. File paths are relative to `lucidcue/`, except `tools/…`. Note
every fix you make in "Device findings".

**Build errors**

| Symptom | File | Likely fix |
|---|---|---|
| Syntax or type error on `getInitialView() as [Views] or [Views, InputDelegates]` | `source/LucidCueApp.mc` | The tuple return type needs SDK 7 or newer: update the SDK (§1). On an older SDK, use `as Array<Views or InputDelegates>?` and cast the return value to that type. |
| `Application.PropertyValueType` not found | `source/LcConfig.mc` (`lcReadProperty`) | Change the return type to `Lang.Object or Null`. |
| Resource compiler rejects decimal `min` / `max` (`0.0`/`0.2`, `2.0`/`7.0`, `1.0`/`2.0`) | `resources/settings.xml` | Delete `min` and `max` on the float settings. `clampConfig` still enforces the ranges. |
| `STATE_AWAKE` / `STATE_SETTLING` / `STATE_ASLEEP` not typed as `Number` | `source/SleepStateMachine.mc` (anonymous `enum`) | Add `as Number` where the error points, or replace the enum with three `const`s (0, 1, 2). |
| "may be null" error inside an `if (a != null && …)` compound condition | the file and line named (`SleepStateMachine.mc`, `RemDetector.mc`, `CueController.mc`) | The checker didn't narrow the type. Copy the value into a local, or cast it at the use: `(hr as Double) < (refHr as Double)`. |
| "Undefined symbol" for a global (`Epoch`, `STATE_ASLEEP`, `LcConfig`) used inside a `module` | `source/EpochFeatures.mc`, the test modules in `test/` | Qualify it with `$.`, e.g. `new $.Epoch(...)`, `as $.LcConfig`. |
| Type error on the options dictionary passed to `Sensor.registerSensorDataListener` | `source/SensorSampler.mc` (`start`) | Put the nested `{ :period => 1, :accelerometer => {…}, :heartBeatIntervals => {…} }` literal in an untyped local (`var opts = {…};`) and pass `opts`, or cast it with `as Sensor.SensorDataListenerOptions` if the SDK names that type. |
| Errors on `mLog.write(...)` / `mVibe.play(...)` | `source/NightSession.mc` | These members are duck-typed and need Gradual checking (`-l 1`). Don't build with `-l 2`/`-l 3`. Otherwise, type them as `NightLog` / `Vibe` and make the test fakes `FakeLog extends NightLog` / `FakeVibe extends Vibe`. |
| Error on `new Vibe(true).profiles(50)` | `test/NightSessionTest.mc` | Split the chained call: `var v = new Vibe(true); var p = v.profiles(50);`. |
| "Redefinition of variable `k`" | `source/views/LcDraw.mc` (`lcDrawLines`, two `for (var k …)` loops) | Rename the second loop's variable to `j`. |
| `Graphics.ColorType` not found | `source/views/LcDraw.mc` | Change the `color` parameter type to `Number`. |
| Error (not a warning) about the launcher icon size (the PNG is 40×40) | `resources/launcher_icon.png` | Re-save the PNG at the size the message names. The scaling warning on its own is harmless. |
| Signature error on `onTap` | `source/views/NightView.mc` (`NightDelegate`) | Match the SDK's `onTap(clickEvent as WatchUi.ClickEvent) as Boolean`. |
| Unknown product / device id | `manifest.xml` | Use the ids SDK Manager shows (§0). |

**Unit test failures (§5)**

| Symptom | File | Likely fix |
|---|---|---|
| Helper functions such as `LcTestUtil.near` or `NsFix.feed` are run as tests and fail | the `(:test) module`s in `test/` | The runner treats functions inside `(:test)` modules as tests. Move the helpers into a class inside the module (only functions are run as tests) and call them through it. |
| Out of memory, or "Watchdog Tripped" before any replay test has run | `test/Fixtures.mc` (about 7,700 literals that initialise at load) | Change `tools/gen_fixtures.py` to return each array from a function (`Fixtures.hr()` and so on), and update `test/ReplayTest.mc` to match. |
| `testReplay00`, `testReplay01`, … fail with "Watchdog Tripped" / "Code Executed Too Long" | `tools/gen_fixtures.py` (`CHUNK`) | Halve `CHUNK`, regenerate `lucidcue/test/Fixtures.mc` (§5), rebuild. The Python tests follow the new value. |
| `testReplay01` and later fail with "… the testReplayNN chunks must run in order" | `test/ReplayTest.mc` | The runner reorders tests, or resets module state between them. Run the full suite, not a filtered test. If it still fails, the replay needs a per-chunk state checkpoint (a code change). Record it. |
| `testLoadConfigReadsAndClampsProperties` errors on `Properties.setValue` | `test/LcConfigTest.mc` | Properties aren't writable in test mode. Delete that one test (the clamp and default tests cover the logic), then reset the simulator's app data. |
| `testSqrtReturnsDouble` fails | `source/EpochFeatures.mc` | `Math.sqrt` returns a 32-bit Float. Motion and HR maths then differ slightly from the Python model. Record it. The fix is a Double square root (Newton refinement), which is a code change. |
| Exact-string tests fail by one digit in the last decimal | `test/NightLogTest.mc`, `test/NightSessionTest.mc` | `Double.format` rounds differently from C `printf`. Record it. Only the expected strings need to change. |

**Simulator walk-through and device behaviour**

| Symptom | File | Likely fix |
|---|---|---|
| A morning question is skipped, or the Summary never appears, after a Confirmation | `source/views/NightView.mc` (`NAV_DELAY_MS`), `source/views/MorningFlow.mc` (`STEP_DELAY_MS`) | The Confirmation pops later than expected. Raise both from 100 to 300 ms. |
| A Settings toggle saves the opposite of what it shows | `source/views/MainMenu.mc` (`SettingsMenuDelegate.onSelect`) | `ToggleMenuItem.isEnabled()` returns the old state in `onSelect` on your firmware. Store `!isEnabled()` instead. |
| Back on a morning question records "No" and moves on | `source/views/MorningFlow.mc` | Expected: Back on a Confirmation means No. If Back instead just closes the question, START re-asks it. Both are fine. |
| A screen tap on the Night screen shows the status or does anything else | `source/views/NightView.mc` (`NightDelegate.onTap`) | The tap reached a different handler. Record it. START is the only intended control. |
| `E` lines with motion exactly `500` (the still threshold) in the middle of a night | `source/SensorSampler.mc` (`lcSampledEpoch`) | By design: the accelerometer delivered no samples in that epoch. The epoch then counts as "not still", so it is never REM-like and doesn't count toward sleep onset (a motion of 0 would have looked perfectly still). Note in "Device findings" how often it happens. Long runs mean the accelerometer stops with the display off. |

## 5. Run the unit tests (in the simulator)

Build the test version, start the simulator, then run the tests in it:

```sh
monkeyc -f lucidcue/monkey.jungle -d epix2pro47mm -o bin/LucidCueTest.prg -y developer_key.der -t
connectiq &
monkeydo bin/LucidCueTest.prg epix2pro47mm -t
```

- `connectiq &` starts the simulator in the background. Wait until its window
  appears before running `monkeydo`. On Windows, run `connectiq` in a
  **separate** terminal window instead of using `&`. You can also start the
  simulator from VS Code.
- `monkeydo … -t` runs every `(:test)` function and prints a PASS/FAIL line
  for each, plus a summary. Every test should PASS.
- To run one test: `monkeydo bin/LucidCueTest.prg epix2pro47mm -t testClampConfig`.
- The replay tests `testReplay00`, `testReplay01`, … replay one scripted night
  in chunks, in order, so they only pass as part of the full run. Run on its own,
  a single replay test fails by design. If they fail with "Watchdog Tripped" or
  "Code Executed Too Long", halve `CHUNK` in `tools/gen_fixtures.py`, then
  regenerate with `.venv/bin/python tools/gen_fixtures.py > lucidcue/test/Fixtures.mc`
  and rebuild.

The `testLoadConfig…` test writes settings into the simulator's app storage
and then restores the defaults. If it ever fails partway, reset the
simulator's app data (*File → Reset All App Data*, or similar).

### Simulator walk-through (after the tests pass)

Build the normal app (§4), then run it in the simulator:

```sh
monkeydo bin/LucidCue.prg epix2pro47mm
```

In the simulator, START is the *Enter* / select button (or click the top-right
button on the watch picture) and Back is *Esc* / the lower-right button. The
names may differ by SDK version. Simulated heart rate and accelerometer data
come from the simulator's *Simulation → Sensor* menu (or similar); without
it, a night still runs but logs empty heart rate.

- [ ] The app opens on a menu with **Train**, **Start Night**, **Buzz test**
      and **Settings**.
- [ ] **Train** buzzes at once and shows "Look at your hands", "Am I
      dreaming?" and "1 / 5". About every 30 s it buzzes again and the count
      goes up. After the last one it shows "Start Night >". START opens the
      black Night screen.
- [ ] **Start Night** (from the menu) shows a black screen. Back does
      nothing.
- [ ] On the Night screen, START shows dim grey status text (elapsed time,
      state, cues) that disappears after about 5 s.
- [ ] START while the status text is up asks **End night?**. *No* returns to
      the black screen. *Yes* asks "Remember a dream?", "Felt the cue in a
      dream?" and "Became lucid?" in turn, then shows the summary.
- [ ] Back on the summary returns to the menu.
- [ ] **Buzz test** shows "Level 10", "Level 30", "Level 50", "Level 80",
      about 3 s apart, then "Buzz test done".
- [ ] **Settings** shows **Calibration mode** (on) and **Buzz by length**
      (off). Toggle one, go back, open Settings again: it kept the new value.
      Set it back.
- [ ] The simulator's console (or the log) shows the `X,…,night_start,…`,
      `X,…,caps,hbi=…;acc=…` (after 60 s), `E,…`, `X,…,battery,…`,
      `X,…,night_end,…` and `X,…,morning,…` lines.
- [ ] If the night ran over 60 s **without** simulated accelerometer data, the
      caps line says `acc=0` and the status text adds "No motion sensor:
      buzzing off".

## 6. Sideload the app onto the watch (USB)

1. Connect the watch to the computer with its USB cable.
2. Open the watch's storage:
   - **Windows:** it appears in File Explorer as a device (e.g. "epix Pro").
     Open *Internal Storage* (or similar).
   - **macOS:** macOS can't open Garmin watches (MTP devices) by itself.
     Install **OpenMTP** (<https://openmtp.ganeshrvel.com>), quit Garmin
     Express if it is running, then open OpenMTP and pick the watch.
   - **Linux:** most file managers (GNOME Files, Dolphin) show the watch as an
     MTP device. If yours doesn't, install `jmtpfs` or `go-mtpfs` and mount
     it.
3. Copy `bin/LucidCue.prg` into the watch's **`GARMIN/APPS/`** folder.
4. **Create the log file (once).** On your computer, create an empty text file
   named exactly `LUCIDCUE.TXT`:
   - macOS / Linux: `touch LUCIDCUE.TXT`
   - Windows: `type nul > LUCIDCUE.TXT` (Command Prompt), or create it in
     Notepad and save it with no content. Make sure Windows didn't add `.txt`
     twice.

   On the watch, open `GARMIN/APPS/`. Create a folder **`LOGS`** there if it
   doesn't exist, and copy the empty `LUCIDCUE.TXT` into it, giving
   **`GARMIN/APPS/LOGS/LUCIDCUE.TXT`**. The watch writes to this file only
   if it already exists.
5. Safely eject or disconnect the watch. LucidCue appears in the watch's
   apps list (press START → scroll to *LucidCue*). You may need to add it via
   *Edit apps* / *Add* on some firmware.

To update the app later, rebuild (§4) and copy the new `LucidCue.prg` over the
old one. Don't delete `LOGS/LUCIDCUE.TXT`.

### Changing settings on a sideloaded app

The settings are `calibrationMode`, `earliestCueHours`, `maxCuesPerNight`,
`startLevel`, `trainReps`, `hrRise`, `varRatio` and `vibeByLength`. The watch
clamps every value to its allowed range when it loads them.

**`calibrationMode` and `vibeByLength` can be changed on the watch:** open
LucidCue → **Settings** and toggle **Calibration mode** or **Buzz by length**.
The change is saved at once and applies from the **next** Start Night (the
app reads its settings when a night starts). This is the easiest way, and it
is how you go live. The options below also work for these two.

**Sideloaded apps often don't show up in the phone's Connect IQ app settings.**
Garmin delivers phone settings through the Store. For the other settings
(`earliestCueHours`, `maxCuesPerNight`, `startLevel`, `trainReps`, `hrRise`,
`varRatio`), use whichever option works for you:

- **A. Phone settings.** Open the Connect IQ app (or Garmin Connect) on your
  phone, find LucidCue under your watch's apps, and change the settings. Use
  this if LucidCue appears there.
- **B. Change the defaults and rebuild.** Edit the value in
  `lucidcue/resources/properties.xml`, for example
  `<property id="calibrationMode" type="boolean">false</property>`, then
  rebuild (§4) and re-copy the PRG (§6). **Important:** the watch keeps saved
  setting values in `GARMIN/APPS/SETTINGS/LUCIDCUE.SET`. Phone settings and
  the app's on-watch toggles both create this file, and it survives app
  updates. While it exists, the watch ignores your new defaults. So when you
  copy the new PRG, also **delete `GARMIN/APPS/SETTINGS/LUCIDCUE.SET` if it
  is there**. Afterwards, redo any on-watch toggles you had changed: deleting
  the file resets every setting to the new defaults.
- **C. Simulator settings file (advanced, may differ by SDK version).** In the
  simulator, open *File → Edit Application.Properties* (or *App Settings
  Editor*), set the values, and run the app once. Then copy the generated
  `LUCIDCUE.SET` from the simulator's temporary `GARMIN/APPS/SETTINGS/` folder
  to the watch's `GARMIN/APPS/SETTINGS/`.

Where this guide says "set X in settings", use the watch's **Settings** menu
for `calibrationMode` and `vibeByLength`. For the others use A if you can,
otherwise B.

**Always confirm that a change took effect.** At the start of every night the
app writes the settings it is actually using into `LUCIDCUE.TXT`, as `k=v`
pairs on the `night_start` line (e.g. `…,night_start,…hrRise=0.070…`; `hrRise`
and `varRatio` show 3 decimals, `earliestCueHours` 2). After
changing a setting, start a short night (or check the next morning's log) and
make sure the line shows your new values. If it shows the old ones, a saved
`LUCIDCUE.SET` is overriding them (see B).

---

## 7. Get Garmin's sleep stages as JSON (for calibration)

Calibration compares LucidCue's REM guesses with the sleep stages Garmin
Connect shows for the same night. You fetch those with the unofficial
`garminconnect` Python library.

**One-time setup** (from the repository root):

```sh
python3 -m venv .venv
.venv/bin/pip install -r model/requirements.txt
.venv/bin/pip install garminconnect
```

Windows: use `py -m venv .venv`, then `.venv\Scripts\pip install -r model\requirements.txt`
and `.venv\Scripts\pip install garminconnect`.

**Each morning:** first let the watch sync to Garmin Connect on your phone.
Then save this as `fetch_sleep.py`, anywhere outside the repository or in a
git-ignored folder:

```python
import getpass
import json
import sys

from garminconnect import Garmin

date = sys.argv[1]  # the date you WOKE UP, e.g. 2026-10-10
email = input("Garmin email: ")
pw = getpass.getpass("Garmin password: ")
api = Garmin(email, pw)
api.login()
data = api.get_sleep_data(date)
with open("sleep_%s.json" % date, "w") as f:
    json.dump(data, f)
print("saved sleep_%s.json (%d sleepLevels)" % (date, len(data.get("sleepLevels") or [])))
```

Run it with the morning's date:

```sh
.venv/bin/python fetch_sleep.py 2026-10-10
```

- Garmin files a night under the date you **woke up**: the night of 9→10 Oct
  is `2026-10-10`.
- If the script reports `0 sleepLevels`, Garmin has no stages for that night.
  Check the watch synced, and that Garmin Connect shows deep/light/REM for it.
- If your account uses two-factor authentication, the library may prompt for
  a code, or need a newer version (`pip install -U garminconnect`).
- Your password is typed at the prompt, not stored. Don't hard-code it in the
  script.

---

## 8. Calibration routine (first 3 nights)

New installs start with `calibrationMode = true`. Everything runs and logs,
but the watch **never vibrates at night**. It only logs `wouldcue` events.
After 3 nights you tune the REM thresholds to your own heart, then switch the
cues on.

**Before night 1**, create a folder for the log copies (from the repository
root): `mkdir -p logs` on macOS / Linux, or `mkdir logs` on Windows. These
logs are your personal health data: don't commit them.

**Each of the 3 nights:**

1. At bedtime, open LucidCue and run **Train** if you want to practise the
   cue. Then choose **Start Night** and go to sleep wearing the watch snugly.
   The screen stays black.
2. In the morning, press START to show the status screen, press START again,
   and confirm **End night**. Answer the three morning questions.
3. Connect the watch over USB and copy `GARMIN/APPS/LOGS/LUCIDCUE.TXT` to
   your computer as a dated copy, e.g. `logs/LUCIDCUE_2026-10-10.TXT`.
4. Replace the watch's `LUCIDCUE.TXT` with a fresh **empty** one (same name,
   same folder). Each copy then holds exactly one night, and the file never
   grows too large.
5. Fetch that night's sleep stages (§7), e.g. `sleep_2026-10-10.json`. Check
   Garmin Connect still shows sleep stages for the night. If LucidCue running
   all night stopped Garmin's own sleep tracking, note it.
6. **After night 1 only: check the log survived the whole night.** Open the
   dated copy in a text editor. The first line should be an
   `X,…,night_start,…` line, and the last lines should be `X,…,night_end,…`
   and then `X,…,morning,…`. Then run the calibration script on that night
   alone:
   ```sh
   .venv/bin/python tools/calibrate.py logs/LUCIDCUE_2026-10-10.TXT sleep_2026-10-10.json --out calib/
   ```
   Ignore its threshold lines for now (one night is too few). Its `night 1`
   line reads `N epochs over H h = R per hour (expect about 120), G gap(s)`. Check that N is about 120 × the hours you were in bed, R
   is close to 120, G is 0, and the next line says `ends with
   night_end/morning`. If any check fails, the log was cut short or the app
   was paused during the night. Record it in "Device findings" (§9): the
   design's fallback (spec §2) is to keep the log in `Application.Storage`
   and show it on the Summary screen, which needs a code change.

**After night 3**, join the three logs into one file and run the calibration
script:

```sh
cat logs/LUCIDCUE_2026-10-10.TXT logs/LUCIDCUE_2026-10-11.TXT logs/LUCIDCUE_2026-10-12.TXT > LUCIDCUE.TXT
.venv/bin/python tools/calibrate.py LUCIDCUE.TXT sleep_2026-10-10.json sleep_2026-10-11.json sleep_2026-10-12.json --out calib/
```

Windows (Command Prompt):
`copy /b logs\LUCIDCUE_2026-10-10.TXT+logs\LUCIDCUE_2026-10-11.TXT+logs\LUCIDCUE_2026-10-12.TXT LUCIDCUE.TXT`,
then `.venv\Scripts\python tools\calibrate.py LUCIDCUE.TXT sleep_2026-10-10.json sleep_2026-10-11.json sleep_2026-10-12.json --out calib\`.
(macOS / Linux can also write `sleep_*.json`.)

The script prints, for each night, the epoch count, the battery drop and the
path of a plot in `calib/`. It then prints a `default hrRise=0.05
varRatio=1.30: precision=… recall=…` line, which scores the current
thresholds. If the search found a good setting, it next prints a
`best hrRise=… varRatio=…` line with its precision and recall. Otherwise it
prints `NO RECOMMENDATION — keep current thresholds; check the sleep files /
STAGE_MAP` and exits with an error status. That happens when no thresholds
reach precision 0.60 (the spec's success criterion) or none find any REM.
Last come the motion percentiles while asleep. Then:

1. **Set the thresholds:** only set them if precision ≥ 0.60 and the tool
   printed a recommendation (a `best hrRise=… varRatio=…` line). Then set
   `hrRise` and `varRatio` to the reported values (§6, "Changing settings"),
   and confirm that the next `night_start` line in `LUCIDCUE.TXT` shows the
   new values. After `NO RECOMMENDATION`, keep the current values, and check
   that each `sleep_*.json` has sleep stages for the right night.
2. **Check stillness:** if the ASLEEP motion p90 is near or above 500, the
   `stillThreshold` (fixed at 500 in the app) is too low for you. Note the
   numbers so it can be changed in code.
3. **Check battery:** the drop should be ≤ 10% per night. If it's more, note
   it. The fix is lowering the accelerometer rate to 5 Hz in code.
4. **Look at the plots** in `calib/`. Do the REM-like flags line up with
   Garmin's REM blocks?
5. **Go live:** on the watch, open LucidCue → **Settings** and turn
   **Calibration mode** off (§6). Then confirm that the next `night_start`
   line shows `calibrationMode=false`. From now on the watch buzzes
   during detected REM, no earlier than `earliestCueHours` after you fall
   asleep. Keep training every bedtime, and review your morning answers
   weekly.

---

## 9. First-build probe checklist (do this before the calibration nights)

These checks answer the open questions in the design spec (§2). Do them on
the first evening the app is on the watch, while awake (about 15 min, plus a
30–60 min hands-off run). Write the results in the "Device findings" section
at the end of this file.

- [ ] **Build and sideload** the app (§4, §6), with `LOGS/LUCIDCUE.TXT`
      created.
- [ ] **Vibration strength:** open LucidCue → **Buzz test**. It plays strength
      10, 30, 50 and 80. Do the later buzzes feel stronger?
  - Yes: strength works. Keep `vibeByLength = false`.
  - No difference: open LucidCue → **Settings** and turn **Buzz by length**
    on (sets `vibeByLength = true`, §6). The app will then ramp by pulse
    length instead. Buzz test itself always varies strength, not length.
- [ ] **Sleep Mode / Do Not Disturb:** turn on the watch's Sleep Mode (or
      DND), the way it will be at night, and run **Buzz test** again. Does it
      still vibrate?
  - Yes: good.
  - No (silent): this is a **blocker**. The app cannot cue you during sleep.
    Record it and stop here.
- [ ] **2-minute Night run:** choose **Start Night**, wait at least 2 minutes,
      then press START, START again and confirm **End night**. Answer the
      morning questions. Copy `LUCIDCUE.TXT` to the computer and open it in
      a text editor. It should contain:
  - [ ] an `X,…,night_start,…` line
  - [ ] an `X,…,caps,hbi=…;acc=…` line
  - [ ] at least 3 `E,…` lines (one every 30 seconds)
  - [ ] an `X,…,morning,…` line
  - [ ] an `X,…,night_end,…` line
- [ ] **Beat-to-beat data:** in the `caps` line, is it `hbi=1` or `hbi=0`?
  - `hbi=1`: beat-to-beat intervals are available. Variability uses RMSSD.
  - `hbi=0`: not available on your watch or firmware. The app automatically
    falls back to heart-rate standard deviation. Note it.
- [ ] **Accelerometer data:** in the same line, is it `acc=1` or `acc=0`?
  - `acc=1`: good.
  - `acc=0`: no motion data reached the app, so it could not tell awake from
    asleep. The app then **turns buzzing off for that night** (cues are only
    logged as `wouldcue`), and the status text says "No motion sensor:
    buzzing off". Record it: the app cannot cue you until this works.
- [ ] If `LUCIDCUE.TXT` stayed empty: check the file is exactly
      `GARMIN/APPS/LOGS/LUCIDCUE.TXT`, and that the app file is exactly
      `LucidCue.prg`. Record it if it still doesn't work.
- [ ] **Log survival probe (30–60 min):** empty `LUCIDCUE.TXT` (or note
      where the new night starts), choose **Start Night**, and leave the
      watch untouched with the display off for 30–60 minutes. If Sleep Mode
      is scheduled for the evening, let the run go through its start time,
      or turn Sleep Mode on by hand during the run. Then end the night as
      above and copy `LUCIDCUE.TXT` to the computer. Check it with the
      calibration script (no sleep file needed):
      ```sh
      .venv/bin/python tools/calibrate.py LUCIDCUE.TXT --out calib/
      ```
  - [ ] the `night 1` line shows about 120 epochs per hour (60 for a
        30-minute run, 120 for an hour) and `0 gap(s)`
  - [ ] the next line says `ends with night_end/morning`
  - If either check fails, the watch paused or stopped the app with the
    display off, or lost log lines. Record it in "Device findings". The
    design's fallback (spec §2) is to keep the log in `Application.Storage`
    and show it on the Summary screen, which needs a code change.
- [ ] **3 calibration nights** with `calibrationMode = true` (§8).
- [ ] **Settings reach the watch:** change one setting by the method you will
      use (§6 A, B or C), run a short night, and check that the `night_start`
      line in `LUCIDCUE.TXT` shows the new value. If you used B, also check
      that a stale `GARMIN/APPS/SETTINGS/LUCIDCUE.SET` was deleted. Note
      which method worked.
- [ ] **After night 1:** check the log survived the whole night (§8, step 6).
- [ ] **Run `tools/calibrate.py`** and, only if it printed a `best hrRise=…
      varRatio=…` recommendation, set those values (§8). Confirm them on the
      next `night_start` line.
- [ ] Note any `stillThreshold` or battery issues reported (§8).
- [ ] **Go live:** LucidCue → **Settings** → turn **Calibration mode** off,
      and confirm `calibrationMode=false` on the next `night_start` line.

---

## Device findings

_Fill in after the checklist above: watch size and device id, firmware
version, Buzz test result, Sleep Mode result, `hbi` and `acc` values, log
survival (probe run and night 1: epochs per hour, gaps, does the log end with
`night_end`/`morning`; if not, note the spec §2 `Application.Storage`
fallback is needed), how often mid-night `E` lines show motion `500`
(accelerometer dropouts, §4.1), battery drop per night, calibrated `hrRise` /
`varRatio`, and any build or test fixes from §4.1._
