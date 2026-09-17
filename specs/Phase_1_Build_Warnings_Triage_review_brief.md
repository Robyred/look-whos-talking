# Build/Run Warnings Triage — Review Brief for Claude

- **Date:** 8 September 2026
- **Requested by:** Jack
- **Purpose:** Record the triage of the `flutter run` warnings Jack captured in `flutter_app/ERROR MESSAGES/Warnings_260917.txt`, and the one change made as a result. Review only — do not modify code without Jack's approval.
- **Base:** branch `phase1-storage` @ `7a9444f` (pushed).

## Headline
The build **succeeded** and the app installed and ran (`✓ Built build/app/outputs/flutter-apk/app-debug.apk`). None of the captured messages are errors; most are Android/Xiaomi-MIUI logcat noise or environment notices.

## Change made (the only repo-side item)
**`android/app/src/main/AndroidManifest.xml`** — added to `<application>`:
```xml
android:enableOnBackInvokedCallback="true"
```
Reason: the log repeatedly emitted
`W/WindowOnBackDispatcher: OnBackInvokedCallback is not enabled for the application. Set 'android:enableOnBackInvokedCallback="true"' in the application manifest.`
With `targetSdk 36`, Android expects apps to opt into the modern (predictive) back API. This is the standard opt-in.

**Back-navigation impact — reasoning (not device-verified):**
- Flutter's `PopScope` still governs whether a route pops; the manifest flag only switches the platform to the modern back dispatch. The Processing screen uses `PopScope(canPop: configuring || failed)`, i.e. back is blocked only while analysis is running, which remains the behaviour.
- Not verifiable in the sandbox (needs a device + Gradle). **Device check:** during *Analyzing*, back should be ignored; during *Configure*, back should leave the screen.

## Deliberately not changed
- **Do not update Flutter before the beta.** The toolchain is deliberately stable (Flutter 3.47.1, AGP 9.1.0, `compileSdk 36`) with dependency pins chosen to avoid the compileSdk-37 requirement. Upgrade later on a branch with `7a9444f` as fallback.
- Gradle/JDK native-access warnings, the Android Studio vs cmdline-tools "SDK XML version 4" notice, and the "43 packages have newer versions" line — all environmental/expected.
- Startup "Skipped 153 frames" — expected in debug (JIT, first DB open, shader warm-up). Re-check in a profile/release build before beta rather than chasing it now.

## Watched, not fixed
- `E/ActivityThread: fail in deliverResultsIfNeeded … NullPointerException` — framework-level, seen near a file-picker/Credential-Manager interaction, almost certainly MIUI noise (the flows worked). If a picker or sign-in ever returns nothing, this line is the clue.
- `Lost connection to device.` — end of the `flutter run` session, not a crash (no Dart exception in the log).
- `W/WavHeaderReader: Ignoring unknown WAV chunk` — ExoPlayer/just_audio on a non-standard WAV chunk; harmless unless playback sounds wrong.
- MIUI/vendor lines (`LB fail to open`, `DynamicFPS`, `libmbrainSDK`, `MirrorManager`, `Access denied finding property "ro.vendor…"`, `ApkAssets … weak references`) — device noise.

## Verification
- `flutter analyze`: no issues. `flutter test`: **218/218 green** (manifest change doesn't affect Dart tests).
- Device verification pending: warning gone + back behaviour unchanged.

## What Claude should do
1. Confirm the manifest opt-in is the right call for a `targetSdk 36` beta build.
2. Flag any of the "watched" items you would escalate before shipping.
3. **Outcome:** approve, or list required changes for Jack to action.
