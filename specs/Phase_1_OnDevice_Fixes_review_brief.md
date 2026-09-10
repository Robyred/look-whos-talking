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

## Spec approved & implemented (8 Sep 2026)
Claude approved `specs/specs_Phase_1_History_Sync_Management.txt` with one change: the Settings **Auto-sync switch is REQUIRED, not optional** (spec wording updated accordingly). Claude's sequencing was followed:
1. **`f96f80e`** `fix(phase1): sync, playback, restore on-device fixes` — the accumulated working-tree fixes above.
2. **`179c0ce`** `feat(phase1): opt-in + selective cloud sync, always-available Sync all, cloud-aware delete` — the spec + implementation in one commit.
3. **`1349602`** `docs(phase1): auto-sync switch is required; record implementation + device verification` — spec wording + this brief.

Implementation summary: auto-sync is opt-in (background sync gated on the required Settings switch, default OFF); "Sync all" shows whenever a provider is authenticated and syncs every conversation (overwrite/recreate); multi-select → "Sync selected (N)"; cloud-aware delete (local only vs delete & remove from cloud); per-row "Sync to cloud"; restore count reporting.

### Follow-up added after device testing: bulk delete (spec §3b)
Jack found Select mode had no delete action (it was never in the spec). Added to the spec as §3b and implemented in **`3b8aae1`** `feat(phase1): delete selected conversations from History`:
- Select mode now shows **both** "Sync selected (N)" and **"Delete selected (N)"**.
- The bulk dialog offers local-only, or "Delete & remove from cloud" when any selected row is synced and a provider is authenticated (same cloud-aware path as single delete).
- Exits selection and reports a summary snackbar; guarded by the same busy flag.

Minor UI follow-up (**`c246c40`** `feat(phase1): use icon buttons for History select mode`): the AppBar Select/Done text button became an IconButton — `Icons.checklist` ("Select conversations") to enter selection mode, `Icons.close` ("Exit selection") to leave it. The action-bar buttons and long-press row menu are unchanged; widget tests updated to icon finders.

## Verification status
- **`flutter analyze`:** no issues. **`flutter test`:** **211/211 green** (in-sandbox Flutter 3.47.1; analyzer file-descriptor noise is environmental).
- On-device confirmations across the session: build succeeds; all three providers connect/disconnect; sync completes; uploads are playable from History; Restore reports honestly.
- **On-device, post-implementation:** ✅ selective sync ("Sync selected") works; ✅ the Auto-sync switch works (opt-in behaviour confirmed). **Pending on device:** bulk "Delete selected", cloud-aware delete dialog, per-row "Sync to cloud", and re-sync after deleting the remote copy.

## What Claude should do
1. Read this brief (and the referenced per-fix briefs as needed) to become current.
2. Confirm the commits match the approved spec — including the required Auto-sync switch and the §3b bulk-delete addition.
3. Re-run `flutter test` / `flutter analyze` to confirm current state (**211/211**).
4. **Outcome:** confirm, or list required changes for Jack to action. Do not modify code without Jack's approval.
