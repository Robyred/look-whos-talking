# Phase 1 Settings, Cloud Storage & Extended Share — Review Brief for Claude

- **Date:** 8 September 2026
- **Requested by:** Jack
- **Purpose:** Claude reviews this pass before it is committed. Review only — do not modify code without Jack's approval.
- **Spec to review against:** `specs/specs_Phase_1_Settings_Share.txt`
- **Base to review on top of:** branch `phase1-storage` @ `5472be9` (baseline + Phase 1 storage/history + wiring, all pushed). Prior review context: `specs/Phase_1_review_brief.md`, `specs/CLAUDE_REVIEW_specs_Phase_1_Storage_&_History.txt`, `specs/Phase_1_Wiring_review_brief.md`.

## Repo state

This pass is **uncommitted** on top of `5472be9`. It implements the four spec features: Settings screen (HomeScreen gear icon), OneDrive + Dropbox providers (connect/disconnect only — sync wiring out of scope per spec §9.5), and extended share on the Overview and Q&A tabs.

## Files in this pass

### New
```
flutter_app/lib/services/oauth2.dart            # shared OAuth seams (see deviations)
flutter_app/lib/services/onedrive_provider.dart # OneDriveProvider + constants + factory file (onedrive_services.dart)
flutter_app/lib/services/dropbox_provider.dart  # DropboxProvider + constants + factory file (dropbox_services.dart)
flutter_app/lib/screens/settings_screen.dart    # provider rows: connect/disconnect
flutter_app/test/helpers/provider_fakes.dart    # InMemoryTokenStore + FakeTokenBroker
flutter_app/test/unit/onedrive_provider_test.dart
flutter_app/test/unit/dropbox_provider_test.dart
flutter_app/test/widget/settings_screen_test.dart
```

### Modified
```
flutter_app/lib/services/cloud_storage_provider.dart   # + displayName getter on the abstract interface
flutter_app/lib/services/google_drive_provider.dart    # displayName → 'Google Drive'
flutter_app/lib/screens/home_screen.dart               # cloudProviders param + gear icon (left of History)
flutter_app/lib/screens/results_screen.dart            # Overview: _ShareBar + _metricsText; Q&A: "Share Q&A" button
flutter_app/lib/main.dart                              # constructs google + oneDrive + dropbox; passes list
flutter_app/pubspec.yaml / pubspec.lock                # + flutter_appauth, flutter_secure_storage
flutter_app/android/app/src/main/AndroidManifest.xml   # RedirectUriReceiverActivity (MSAL + Dropbox schemes)
flutter_app/test/helpers/fakes.dart + 4 test doubles   # displayName on every CloudStorageProvider fake
```

## Interpretation decisions & deviations from the spec (not bugs)

1. **`flutter_secure_storage` version:** spec says `^9.0.0`; that cannot resolve — `flutter_secure_storage_windows` 3.x needs win32 ^5 which conflicts with `share_plus` ^13 (win32 ^6). Pub's own suggestion (`^11.0.0`) was used — the same version the earlier Phase-1 spec had. **Final change:** the Android build with `^11.0.0` failed because 11.x hard-codes `compileSdk = 37` while the project compiles at SDK 36 (AGP 9.1.0's recommended max). Pinned to **`^10.0.0` → resolved 10.3.1** (`compileSdk = 36`, `minSdk 23`, Windows impl 4.2.2 — no win32 conflict). API used is identical across these.
2. **Testability seams (new `oauth2.dart`):** the spec sketch hard-wires `FlutterAppAuth`, `FlutterSecureStorage` and top-level `http` calls, which cannot run headless. Following the GoogleDriveProvider precedent (DriveGateway/AuthGateway), each provider now accepts injectable `http.Client`, a `TokenStore` seam (real impl `SecureTokenStore` over flutter_secure_storage) and a `TokenBroker` seam (real impl `FlutterAppAuthBroker` over flutter_appauth, mapping the typed user-cancelled exception to `AuthException` so the UI treats cancel as quiet). Behaviour is unchanged; the logic is unit-testable.
3. **No constructor access-token injection:** tests reach authenticated state through the real silent-refresh path (stored refresh token + broker), so no test-only token plumbing exists in the providers.
4. **Settings row subtitle:** the interface has no account-email API, so rows show "Connected"/"Not connected" only. Spec's "account email if available" needs an interface addition (or per-provider extension) — deferred rather than inventing a half-interface.
5. **Q&A share text:** spec sketch reads `msg.content`; `ChatMessage` stores `text` (same data) — implemented with `msg.text`.
6. **Remote path shape (flag for the future sync task, not this pass):** upload/download/delete flatten `remotePath` to the filename (spec sketch); OneDrive `listFiles` returns `remotePath` prefixed with the app-folder name while Dropbox returns `/name` (path_lower). Shapes are provisional until these providers get real SyncService wiring.
7. **Placeholders:** Azure client id (`YOUR_AZURE_CLIENT_ID`), Dropbox app key + scheme (`db-YOUR_DROPBOX_APP_KEY`). The OneDrive MSAL redirect scheme is concrete (real applicationId `com.lookwhostalking.look_whos_talking` → `msauth.com.lookwhostalking.look_whos_talking://auth`). Real auth needs the §3.1/§4.1 registrations.
8. **Analyzer nicety:** `'Content-Type': ?contentType` (null-aware map element, Dart 3.8).

## Verification status

- **199/199 `flutter test` green** (174 before + 10 OneDrive + 9 Dropbox + 5 Settings + 1 net new persist-case fix), **`flutter analyze` no issues** — in-sandbox Flutter 3.47.1 (`.dsh/` copy). Analyzer file-descriptor noise is environmental.
- New coverage: OneDrive (upload session→PUT with body/headers, session failure, download via downloadUrl, delete 404-idempotent/204, authenticate stores refresh token, isAuthenticated silent-refresh/no-token/failed-refresh, signOut clears); Dropbox (upload Dropbox-API-Arg + body, error, download arg, listFiles skips folders, delete 409-idempotent/200, authenticate offline token + `token_access_type`, silent-refresh paths, signOut); Settings widget (3 rows render, Connect updates only that provider, Disconnect confirm/cancel, AuthException → no snackbar, generic error → snackbar). Fake doubles all gained `displayName`.

## Not verified (needs a device + real registrations)

- Live OAuth2: Azure (MSAL) and Dropbox interactive sign-in, redirect handling through `RedirectUriReceiverActivity`, token refresh, and real upload/download round-trips. Requires the §3.1/§4.1 app registrations and replacing the placeholder ids/scheme.
- Manual UI check of the Settings screen and both new share buttons on-device.

## What Claude should do

1. Read the spec, then each new/modified file; confirm conformance per section (Settings screen, interface `displayName`, OneDrive, Dropbox, extended share, manifest, pubspec).
2. Confirm the deviations above are acceptable — especially the `^11.0.0` secure-storage version, the `oauth2.dart` seams, and the flattened-path note.
3. Re-run `flutter test` and `flutter analyze` (Flutter 3.47.1; `.dsh/` copy works).
4. Sanity-check the commit shape (spec §8 suggests one commit `feat(phase1): settings screen, OneDrive + Dropbox providers, extended share` on `phase1-storage`) and whether the placeholder registrations should block or accompany the commit.
5. **Outcome:** approve, or list required changes for Jack to action. Do not modify code without approval.

---

## Addendum — credentials configured by Jack (8 Sep 2026)

Since the brief was written, Jack completed the OneDrive/Azure and Dropbox app registrations and filled in the real identifiers. Deviation #7 (placeholders) is therefore resolved.

### OneDrive / Azure
- **Client ID** (`_odClientId` in `lib/services/onedrive_provider.dart`): `85bd1269-8a45-47a1-93e5-6394edf7fd6b`
- **Redirect URI** (`_odRedirectUrl`): `lookwhostalking://auth`
- Android manifest scheme (line 43): `lookwhostalking`
- Registered on Azure under **Mobile and desktop applications** with the same redirect URI.

**Scheme correction:** the original `msauth.com.lookwhostalking.look_whos_talking://auth` was rejected by Azure — the pre-`://` part is an invalid URI scheme because it contains underscores. Replaced with the valid custom scheme `lookwhostalking://auth` in all three places (provider constant, manifest, Azure).

### Dropbox
- **App key** (`_dbAppKey` in `lib/services/dropbox_provider.dart`): `ypxmmh1ye0mzpby`
- **Redirect URI** (`_dbRedirectUrl`): `db-ypxmmh1ye0mzpby://2/token`
- Android manifest scheme (line 49): `db-ypxmmh1ye0mzpby`

### Security note for Claude's review
- These are **public client identifiers** for a native PKCE/OAuth2 app (no client secret is used — that is the point of the PKCE flow), so committing them is fine.
- Please confirm **no client/app secret** was introduced anywhere (none is present in the current files). Azure *client secrets* and any Dropbox *app secret* must never be added to the repo or the review brief.

### Cleanup + re-verification (same day)
- The stale "Replace with real values…" comment lines in `onedrive_provider.dart` and `dropbox_provider.dart` were removed (the identifiers now live there).
- Re-ran the gate after Jack's identifier/manifest edits and the comment cleanup: **`flutter analyze` no issues, `flutter test` 199/199 green** (no functional code changed — identifier/comment/XML only).

### Claude's addendum review — required fix applied (same day)
Claude reviewed the credential/scheme changes (`specs/Phase_1_Settings_Share_addendum_Credentials_&_scheme_correction.md`) and flagged one required fix that is now done:
- **`_odGraphBase` slash fix** — `onedrive_provider.dart` used `.../special/approot:$_odAppFolder`; Graph path-based addressing requires the `/` after `approot:` (i.e. `approot:/<path>`), otherwise every upload/list/download/delete returns 400/404. Corrected to `approot:/$_odAppFolder`, and a regression assertion was added to the OneDrive upload test (`session.url.path` must contain `special/approot:/`).
- Stale **manifest comment** (the "msauth scheme… placeholders must be replaced" note) was also cleaned up, matching the now-real schemes.
- Re-ran the gate: **`flutter analyze` no issues, `flutter test` 199/199 green**.

Minor note from Claude (non-blocking, no change yet): `lookwhostalking://auth` is a short generic custom scheme and could theoretically be hijacked by another app registering the same scheme. Reverse-DNS (e.g. `com.lookwhostalking://auth`) is more collision-resistant but requires an Azure redirect-URI update. Deferred — worth doing before a public release; Jack's decision.

### Android build fixes (device testing, 8 Sep 2026)

Two errors surfaced when Jack ran `flutter run` to build the APK on his phone; both fixed.

1. **`flutter_secure_storage` 11.0.0 requires compileSdk 37.**
   `flutter run` failed with: *"Dependency ':flutter_secure_storage' requires … compile against version 37 … :app is currently compiled against android-36 … maximum recommended compile SDK version for AGP 9.1.0 is 36."*
   Cause: 11.0.0 hard-codes `compileSdk = 37` in its Android plugin; the project compiles at SDK 36 (AGP 9.1.0's recommended max).
   Fix: pin `flutter_secure_storage` to **`^10.0.0` → resolves 10.3.1** (`compileSdk = 36`, `minSdk 23`, Windows impl 4.2.2 — no win32 conflict with `share_plus`). API used is identical. Re-ran the gate: analyze no issues, 199/199 tests green.

2. **flutter_appauth manifest placeholder `appAuthRedirectScheme` unset.**
   `flutter run` failed during `:app:processDebugMainManifest` with: *"Attribute data@scheme at AndroidManifest.xml requires a placeholder substitution but no value for <appAuthRedirectScheme> is provided."*
   Cause: `flutter_appauth` registers its OAuth redirect receiver against a Gradle manifest placeholder named `appAuthRedirectScheme`; no value was ever set, so the manifest merger failed. (The source of the `${appAuthRedirectScheme}` reference could not be found in the committed tree — it appears only at merge time; the placeholder value is required regardless.)
   Fix: in `android/app/build.gradle.kts`, inside `defaultConfig`, added:
   ```kotlin
   manifestPlaceholders["appAuthRedirectScheme"] = "lookwhostalking"
   ```
   The Dropbox `db-…` scheme is declared directly in the main manifest and is unaffected.
   Status: **verification pending** — the agent sandbox cannot run the Gradle build (it needs to write to `~/.gradle` outside the workspace), so Jack is re-running `flutter run` to confirm.

3. **flutter_appauth 8.0.3 plugin compiles against Android SDK 31 (AAR metadata failure).**
   After fix #2, the build progressed further then failed at `:flutter_appauth:checkDebugAarMetadata` with ~20 issues, all of the form *"Dependency 'androidx.<…>' requires … compile against version 33/34 or later … :flutter_appauth is currently compiled against android-31."*
   Cause: the spec's `flutter_appauth: ^8.0.0` constraint resolved to **8.0.3**, an old plugin whose own `build.gradle` sets `compileSdkVersion 31`, while Gradle resolved its transitive AndroidX deps (fragment 1.7.1, lifecycle 2.7.0, activity 1.8.1, …) up to SDK 34 — so the library module cannot check its AAR metadata.
   Fix: upgrade to **`flutter_appauth: ^12.0.0` → resolves 12.1.0** (`compileSdkVersion 35`, `minSdk 24`, still `net.openid:appauth:0.11.1`). The Dart API used here (`const FlutterAppAuth()`, `authorizeAndExchangeCode`, `token`, `FlutterAppAuthUserCancelledException`) is unchanged in 12.x. Re-ran the gate: analyze no issues, 199/199 tests green.
   Status: **verified** — build succeeded on Jack's device after these fixes. Working dependency set for the current SDK/AGP: `flutter_appauth` 12.1.0 and `flutter_secure_storage` 10.3.1.

4. **Settings screen renders blank (ListTile trailing overflow).**
   On device, opening Settings crashed the layout: *"Trailing widget consumes the entire tile width … ListTile … settings_screen.dart:138."* Cause: the app theme sets `FilledButton.minimumSize` to `Size.fromHeight(52)` (i.e. infinite width). The not-connected row's `Connect` `FilledButton` sits in `ListTile.trailing`, so it expanded to the full tile width and overflowed. Fix: give that button a bounded style in `_ProviderRow` (`FilledButton.styleFrom(minimumSize: Size(96, 40), …)`). Added a regression widget test that renders SettingsScreen under the app's full-width-button theme (would previously throw). Gate re-run: analyze no issues, **200/200 tests green**.

### On-device OAuth testing — first results + fixes (8 Sep 2026)
Jack built and ran on a phone. Settings now renders; connecting each provider surfaced one issue each:
1. **Google Drive — `GoogleSignInException(clientConfigurationError, serverClientId must be provided on Android, null)`.** `google_sign_in` 7.x on Android requires a `serverClientId` (the Client ID of a Google Cloud *Web application* OAuth client) to request the Drive scope; none was configured. Fix (code): added a `_googleServerClientId` constant in `google_drive_services.dart` (placeholder `YOUR_GOOGLE_WEB_CLIENT_ID`) and passed it to `GoogleSignIn.instance.initialize(serverClientId: …)`. **Open:** Jack must create the Google Cloud "Web application" OAuth client for this app and replace the constant (registration step, like Azure/Dropbox). Not re-verified on device yet.
2. **Dropbox — white screen with *"302 The resource was found at db-ypxmmh1ye0mzpby://2/token?code=…&state=…; you should be redirected automatically".*** OAuth completed but the custom-scheme redirect was not handed back to the app. Cause: the `RedirectUriReceiverActivity` intent-filters declared only `android:scheme`; AppAuth matching needs scheme **+ host** (+ path) to capture `db-…://2/token`. Fix (code): added `android:host="2"` + `android:pathPrefix="/token"` to the Dropbox filter and `android:host="auth"` to the OneDrive filter in `AndroidManifest.xml`. **Not re-verified on device yet.**
3. **OneDrive — flow started but could not restart cleanly; generic Microsoft "Cannot Complete Request".** Likely a transient/state issue (the previous flow was still open when Connect was re-tapped), not a code bug yet. **Open:** retest after the manifest fix; if it recurs, we'll investigate stale in-progress sessions and Microsoft session state. (Settings already guards against double-taps via its `_loading` flag while the call is in flight.)

Analyzer clean after these edits.

### On-device OAuth testing — second round (8 Sep 2026): redirect hand-back fails for all providers
Retest after the above fixes: **Google and OneDrive now get past account selection / MFA, then all three providers die at the same step** — the auth server returns a redirect to the custom scheme but the browser goes white instead of returning control to the app (Dropbox: "302 … you should be redirected automatically"; Microsoft: white screen, window "Object moved / login.microsoftonline.com"; Google: account chosen then `GoogleSignInException` ~error 28444).

Root cause (shared): **`android:taskAffinity=""` on `.MainActivity`**. This is the `flutter_appauth` documented cause of "authorization flow does not return to the Flutter app after login even though the intent filter is correct." Because all three providers share the same hand-back mechanism, one fix covers them.
Fix (code): removed `android:taskAffinity=""` from `MainActivity` in `AndroidManifest.xml`.
Status: **verification pending** — Jack rebuilding to confirm all three now return cleanly.

### Remaining (unchanged)
- Device-side verification is still required for all three providers: interactive sign-ins, redirect hand-back through `RedirectUriReceiverActivity`, silent refresh, and real upload/download round-trips.
