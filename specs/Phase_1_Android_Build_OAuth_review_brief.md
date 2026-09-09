# Phase 1 Android Build & OAuth Fixes — Review Brief for Claude

- **Date:** 8 September 2026
- **Requested by:** Jack
- **Purpose:** Claude reviews the uncommitted Android build + OAuth fixes before they are committed. Review only — do not modify code without Jack's approval.
- **Base commit:** `17f2e9b` on `phase1-storage`. **Note:** `17f2e9b` is the pre-fix state and will not build on this project's Android SDK/AGP — every fix below is **uncommitted in the working tree** and must land before the branch is buildable.
- Related context: `specs/Phase_1_Settings_Share_review_brief.md` (full history of the Settings/Share pass).

## Repo state
All fixes below are uncommitted working-tree changes on top of `17f2e9b`. The committed version contains `flutter_appauth: ^8.0.0`, `flutter_secure_storage: ^11.0.0`, `android:taskAffinity=""`, hostless redirect filters, and no Google `serverClientId` — i.e. a state that fails the Android build and the OAuth hand-back. The working tree corrects all of these.

## Files changed (device-build + OAuth fixes only)

### `flutter_app/pubspec.yaml` (+ `pubspec.lock`)
- `flutter_appauth: ^8.0.0` → **`^12.0.0`** (resolves **12.1.0**). 8.0.3's plugin compiles against Android SDK 31 while its transitive AndroidX deps need 33/34 → `checkDebugAarMetadata` failed with ~20 issues. 12.1.0 uses `compileSdkVersion 35`, `minSdk 24`, same Dart API (verified — analyzer clean, our code unchanged).
- `flutter_secure_storage: ^11.0.0` → **`^10.0.0`** (resolves **10.3.1**). 11.0.0 hard-codes `compileSdk = 37`; the project compiles at SDK 36 (AGP 9.1.0's recommended max). 10.3.1 uses `compileSdk 36` / `minSdk 23`, and its Windows impl (4.2.2) avoids the `^9.0.0` win32 conflict with `share_plus`.

### `flutter_app/android/app/build.gradle.kts`
- Added, inside `defaultConfig`:
  ```kotlin
  manifestPlaceholders["appAuthRedirectScheme"] = "lookwhostalking"
  ```
  Required because `flutter_appauth`'s manifest merge references the `${appAuthRedirectScheme}` placeholder; the build failed with "no value for <appAuthRedirectScheme> is provided" until it was set. The Dropbox `db-…` scheme is declared directly in the main manifest.

### `flutter_app/android/app/src/main/AndroidManifest.xml`
- **Removed `android:taskAffinity=""` from `.MainActivity`** — the `flutter_appauth` documented cause of "OAuth flow does not return to the app after login." This is the shared fix for all three providers (Dropbox, OneDrive/Microsoft, Google) that were completing auth then going to a white screen instead of returning to the app.
- **Redirect intent-filters made precise** on `net.openid.appauth.RedirectUriReceiverActivity`:
  - OneDrive: `scheme=lookwhostalking`, `host=auth` (matches `lookwhostalking://auth`).
  - Dropbox: `scheme=db-ypxmmh1ye0mzpby`, `host=2`, `pathPrefix=/token` (matches `db-ypxmmh1ye0mzpby://2/token`).

### `flutter_app/lib/services/google_drive_services.dart`
- Added `const _googleServerClientId = '<web-oauth-client-id>'` and passed it to `GoogleSignIn.instance.initialize(serverClientId: …)`. `google_sign_in` 7.x on Android requires a `serverClientId` (the Client ID of a Google Cloud **Web application** OAuth client) to request the Drive scope; without it, connect fails with `serverClientId must be provided on Android`. Jack has created the client and filled in the value.

### `flutter_app/lib/screens/settings_screen.dart` (+ its widget test)
- The not-connected row's `Connect` `FilledButton` inherited the app theme's full-width `minimumSize: Size.fromHeight(52)`, overflowing `ListTile.trailing` → blank Settings screen. Fixed by giving that button a bounded style (`minimumSize: Size(96, 40)`). Added a regression widget test that renders SettingsScreen under the app's full-width-button theme.

## Verification status
- **`flutter analyze`:** no issues. **`flutter test`:** 200/200 green (199 + 1 new Settings regression test). Run in-sandbox with Flutter 3.47.1 (`.dsh/` copy); analyzer file-descriptor noise is environmental.
- **On-device (Jack, `flutter run`):** the build now succeeds; Settings renders with the three provider rows.
- **On-device retest after removing `taskAffinity` (latest):** ✅ **OneDrive and Dropbox both connect** (row shows "Connected") and **Disconnect works**. ❌ **Google Drive still fails.**
- **Google Drive failure — `GoogleSignInException`, error 28444:** code 28444 means *"Developer console is not set up correctly"* (Google Credential Manager). Root cause found: the value wired into `_googleServerClientId` was the **Android** OAuth client ID; `serverClientId` must be the **Web application** OAuth client's ID (the Android client is matched automatically by package+SHA-1 and never appears in code). Fixed: Jack created a **Web** OAuth client in the same project ("My First Project") and set `_googleServerClientId` to its ID (`1054824041438-qcikh0mkhrcib5r0dr627g1vo43n9u5h.apps.googleusercontent.com`). **Status: pending device re-verify** (Google propagation delay noted).
- **Open on-device checks:** silent refresh and real upload/download still need confirming for the providers that now connect.

## Security note
The identifiers in the code (`_odClientId`, `_dbAppKey`, `_googleServerClientId`) are **public client identifiers** for native PKCE/OAuth2 apps — no client/app secret is used, so committing them is fine. Please confirm **no client secret / app secret** is present anywhere.

## What Claude should do
1. Review the diffs above against the reported causes; confirm each fix is correct and minimal.
2. Re-run `flutter test` and `flutter analyze` (Flutter 3.47.1; `.dsh/` copy works).
3. Sanity-check that committing this working-tree state onto `phase1-storage` (e.g. `fix(android): build + OAuth redirect fixes`) will produce a buildable, testable branch replacing the broken `17f2e9b`.
4. **Outcome:** approve, or list required changes for Jack to action. Do not modify code without approval.
