# Phase 1 — On-Device Fixes & Current State (Update Brief for Claude)

- **Date:** 8 September 2026
- **Requested by:** Jack
- **Purpose:** Bring Claude fully up to date on everything worked on since the earlier Phase 1 review briefs. This is the single catch-up document; detailed per-fix briefs are referenced for depth.
- **Base commit:** `17f2e9b` on `phase1-storage`. **Everything below is uncommitted working-tree state** (the committed base is the pre-fix state that would not build).

## Repo state
- Settings & Share pass is committed at `17f2e9b`, but it will **not** build on this project's Android SDK/AGP and has the OAuth/sync bugs fixed since. All fixes described here are uncommitted and must land for a buildable branch.

## Cumulative on-device fixes (each with a detailed brief)
1. **Android build fixes** — `flutter_secure_storage` 11.x→10.3.1 (compileSdk 37 → 36); `flutter_appauth` 8.x→12.1.0 (SDK 31 plugin vs AndroidX 34); added the `appAuthRedirectScheme` manifest placeholder. → `specs/Phase_1_Android_Build_OAuth_review_brief.md`
2. **OAuth hand-back** — removed `android:taskAffinity=""` from `MainActivity` (all appauth providers now return to the app); precise redirect intent-filters. Same brief.
3. **Provider connections verified on-device** — Google Drive, OneDrive, Dropbox all connect/disconnect. Google needed the Web (not Android) client id as `serverClientId` and a Testing-mode consent screen + test user. → `specs/Phase_1_Cloud_Connection_review_brief.md`
4. **Sync failures root-caused** — (a) Google Drive API disabled in console (403); (b) apostrophe in the "Look Who's Talking" folder name broke Drive `q` queries (400) → renamed default Google folder to "Look Whos Talking" + regression test. Sync now works.
5. **Duplicate prevention** — `syncConversation` per-id in-flight guard + Sync/Restore buttons disabled while running (upload path is find-then-create and not atomic). → `specs/Phase_1_Sync_Duplicates_review_brief.md`
6. **History playback** — opening a recording from History now passes its stored audio, restoring the Playback tab. Uploads also now retain a durable copy of the picked audio (uploaded files are playable + sync audio).
7. **Restore messaging** — `restoreFromCloud` returns a count; History says "Restored N" or "Nothing new to restore" instead of a false success. → `specs/Phase_1_History_Playback_Restore_review_brief.md`

## New spec drafted — NOT yet implemented
**`specs/specs_Phase_1_History_Sync_Management.txt`** — opt-in sync (auto-sync off by default), always-available "Sync all", selective (multi-select) sync, cloud-aware delete, re-sync after external delete. This is Jack's requested next feature and is ready for Claude review/approval. It consolidates requirements the user asked not to lose (auto-sync opt-in is explicitly listed as a must-keep item in the spec).

## Verification status
- **`flutter analyze`:** no issues. **`flutter test`:** **202/202 green** (in-sandbox Flutter 3.47.1; analyzer file-descriptor noise is environmental).
- On-device confirmations across the session: build succeeds; all three providers connect/disconnect; sync completes; uploads are playable from History; Restore reports honestly.

## What Claude should do
1. Read this brief (and the referenced per-fix briefs as needed) to become current on the uncommitted fixes.
2. Review the drafted **History & Sync Management** spec (next feature) for approval.
3. Re-run `flutter test` / `flutter analyze` to confirm current state.
4. Recommend the commit grouping for the accumulated uncommitted fixes so `phase1-storage` becomes buildable/current.
5. **Outcome:** approve the fixes and the next-feature spec, or list required changes for Jack to action. Do not modify code without Jack's approval.
