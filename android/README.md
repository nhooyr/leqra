# leqra for Android

Native Kotlin, hardware-accelerated Canvas graphics, low-latency PCM sound and
Android Keystore account storage. There is no WebView or JavaScript game runtime.

## Build and run

1. Install Android Studio, including Android SDK Platform 36 and Build Tools 36.
2. Open this `android` directory as the Android Studio project. Let Gradle sync.
   Use Android Studio's bundled JDK for Gradle (Settings → Build, Execution,
   Deployment → Build Tools → Gradle). The Gradle 9.9.1 wrapper supports JDK
   17–27; OpenJDK 27 works too. The compiler toolchain is separately pinned to
   JDK 17, which Gradle downloads automatically if it is not already installed.
3. Select the `app` run configuration and an emulator or connected Android phone,
   then click **Run ▶**. For a phone, enable Developer options and USB debugging,
   connect it, and accept its debugging prompt.

The app supports Android 8.0 (API 26) and newer. It uses the entire display in
portrait and landscape, with safe touch controls around camera cutouts and system
gestures. High refresh rate is enabled by default and requests the fastest
compatible display mode. The actual refresh rate depends on the device and its
system settings.

From the repository root, with `JAVA_HOME` pointing to a supported JDK and
`ANDROID_HOME` pointing to the Android SDK:

```sh
./android/gradlew -p android :app:assembleDebug
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.leqra/com.leqra.android.MainActivity
```

The debug APK is signed with the local Android debug key. `local.properties`
and build output are ignored. No personal signing configuration, device
identifiers or SDK paths belong in version control.

The package version and online protocol handshake read `../scripts/version.sh`,
which derives the version from `../src/main.go`. Build the Android app and server
from the same release.

The build uses Gradle 9.9.1 and Android Gradle Plugin 9.5.1. The app uses the
Android plugin's built-in Kotlin support; the shared JVM core uses Kotlin 2.4.21.

## Signed Play Store builds

Configure the upload key once in your private `~/.gradle/gradle.properties`
(or `$GRADLE_USER_HOME/gradle.properties` if set), not this repository's
`android/gradle.properties`:

```properties
leqraUploadStoreFile=/absolute/path/to/leqra-upload.jks
leqraUploadStorePassword=YOUR_KEYSTORE_PASSWORD
leqraUploadKeyAlias=leqra-upload
leqraUploadKeyPassword=YOUR_KEY_PASSWORD
```

Use the upload key already registered in Play Console for an existing app.
For a new app, create a key outside the repository; this command prompts for
its password and certificate details without putting the password in shell
history:

```sh
keytool -genkeypair -keystore /absolute/path/to/leqra-upload.jks \
  -alias leqra-upload -keyalg RSA -keysize 2048 -validity 10000
```

With the settings saved, build a signed Android App Bundle from the repository
root:

```sh
./android/gradlew -p android :app:bundleRelease
```

Upload `android/app/build/outputs/bundle/release/app-release.aab` to Play Console.
For a signed APK instead, run `:app:assembleRelease`; its output is
`android/app/build/outputs/apk/release/app-release.apk`.

CI can supply `LEQRA_UPLOAD_STORE_FILE`, `LEQRA_UPLOAD_STORE_PASSWORD`,
`LEQRA_UPLOAD_KEY_ALIAS`, and `LEQRA_UPLOAD_KEY_PASSWORD` as environment secrets.
Each Gradle property takes precedence over its corresponding environment
variable. Keystore paths may be absolute or relative to the `android` directory;
use an absolute path for a key stored elsewhere. Keep the keystore and passwords
out of version control and retain a secure backup.

Release packaging fails if any signing setting is missing or the keystore file
does not exist; it never falls back to an unsigned release or the debug key.
Debug builds, IDE sync, and unit tests do not require upload credentials.

## Play

Infinity, Elimination, Capture the flag, King of the hill and Survival run locally
with native physics, bots and all ten power-ups. Public Infinity, private rooms,
room rules, bots, teams, paint, matchmaking and leaderboards use the same
authoritative server as the web and iOS apps. Account-key buttons beside the
callsigns manage independent P1 and P2 accounts. Import a key to move an account
between platforms; the newest Public Infinity device takes over its tank. Every
callsign has its own account and score. Changing callsigns starts a new account
at zero; earlier names and keys stay in encrypted storage for switching back.
Successful changes return to the ready room; failures keep the current account.
Accounts expire after one month without signing in.

Touch controls steer on the left and fire on the right. Touch near your tank to
point it exactly toward your finger without moving; drag there to adjust aim.
Enable P2 manually to keep touch on P1 and route keyboard and mouse controls to P2.
Both W/A/S/D and arrow keys work; move the mouse to aim and hold its left button
to fire. With one local tank, those controls belong to P1. Gamepads retain their
separate seats. Full controls are listed in the app's Controls panel.
Local bot names, paint, difficulty and teams are editable and retained
when publishing the same roster online. Sound effects mix with music from other
apps, including when launching muted. The default sound volume is 50%.

Quick Tour opens on the first visit to the ready room and can be replayed from
Controls. The same panel holds the input, display, audio and account settings.
Show FPS and ping is enabled by default. During local battles the status bar
shows FPS, and online battles also show the measured ping.

Controls also opens the frozen Showcase battle using the native arena renderer.
It includes the normal header, touch controls, and loadout bar. Portrait uses a
closer arrangement of tanks and pickups; landscape keeps the wide scene.
Escape returns to Controls. On touch devices, switch away from the app and return
to exit Showcase. Previewing it does not join a room or change the current account.

Rules describes each power-up using the selected mode and maze size. Fixed mazes
allow pickup-rate and type changes; Infinity always includes all ten types.
With Public Infinity selected, room settings keep the room name and sharing;
turn it off to choose a room mode or edit its rules and presets.

For local server development, run `./dev.sh` at the repository root. Launch a
debug build with a development server address using the `server` intent extra:

```sh
adb shell am force-stop com.leqra
adb shell am start -n com.leqra/com.leqra.android.MainActivity --es server http://10.0.2.2:8080
```

Use your development server's address on a physical phone. Release builds use
`https://leqra.com`. Account keys are scoped to each server origin.

## Validation

```sh
./android/gradlew -p android :core:test :app:testDebugUnitTest :app:lintDebug
./android/gradlew -p android :app:connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.server=http://10.0.2.2:8080
```

The connected tests need a fresh local server of the same version. Use an
isolated temporary `LEQRA_DATA` database, not a live leaderboard. Core regressions
consume the shared Go/browser maze, steering and wall-launch fixtures. Tests
cover all game modes, power combinations, high-speed motion, Starman load,
account cryptography, token rotation/recovery, server protocol and lifecycle.
Audio regressions compare synthesized voices and the processed mix against web
audio references.

The debug-only `RenderPerformanceTest` renders fixed and Infinity scenes in both
orientations with all power-up visuals and hundreds of projectiles. It records
Android Window FrameMetrics and saves PNGs and timings under the app's
`cache/render-benchmark` directory. These are generated test results, not source
assets. Emulator timings are useful regressions, not physical-phone performance
claims. `MainAppPerformanceTest` measures the actual Activity, including its HUD,
status and open leaderboard, with the same stress scene. It saves timings and
screenshots in `cache/main-app-benchmark`; reported deadline misses use Android's
per-frame deadline, rather than assuming every display has a 16.7 ms budget.
`PickupFirePerformanceTest` collects and fires with each regular/power-up loadout
through the actual Activity in fixed/Infinity scenes with audio on/off, recording
the same event window in `cache/pickup-fire-benchmark`. `NativeArtPerformanceTest`
checks lazy/prepared bitmap pixel parity and reports first-use versus prepared
artwork CPU costs. These reports describe the device/emulator used for that run.
`NativeAudioIntegrationTest` exercises muted launch, bounded cue scheduling,
preview lifecycle, pause/resume and native audio output. Run UI and performance
checks in a disposable emulator with an isolated local server.

## Implementation

`core` is an Android-independent Kotlin simulation. Authoritative movement runs
at 60 Hz; continuous motion presentation and a bounded input/reconciliation
timeline run at the display cadence. P1 and P2 have independent prediction and
acknowledgement histories while sharing remote interpolation. Collision and bot
pathfinding use reusable primitive storage. The renderer batches rapid-fire
projectiles, rebases large world coordinates before GPU float conversion, and
prepares cached tank/power-up artwork and bounded maze textures on workers.
Artwork uploads are scheduled before first use. The native HUD caches
text layout while animating progress at display cadence. The audio mixer uses the
web recipes with a bounded voice pool, common compressor/limiter and lazy
AudioTrack output without requesting audio focus. Its bounded command queue never waits for waveform
synthesis or joins an output worker on the UI thread; stale cues are discarded
after an interrupted or cold audio start.

Account secrets use origin-scoped AES-GCM storage with a device-only Android
Keystore key and atomic, synced writes outside backups. New P2 credentials and
replacement-key candidates are persisted before registration or rotation. Secret
HTTP requests reject redirects. Public scores, hits and ownership are always
decided by the server; clients send controls, never scores.

Account controls can also release the current or a saved callsign from the offline ready room. After confirmation, Release permanently deletes that account's score, frees its callsign for reuse, invalidates its key on every device, and removes its saved credentials from this device. Other accounts stay saved.
