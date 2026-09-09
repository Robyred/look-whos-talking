# Phase 1 Sync Duplicate Prevention — Review Brief for Claude

- **Date:** 8 September 2026
- **Requested by:** Jack
- **Purpose:** Claude reviews the duplicate-prevention changes before they are committed. Review only — do not modify code without Jack's approval.
- **Base:** uncommitted working tree on `phase1-storage` (committed `17f2e9b` is stale/pre-fix; this brief covers only the sync-duplicate fix on top of the earlier build/OAuth/sync fixes).
- Related context: `specs/Phase_1_Cloud_Connection_review_brief.md`, `specs/Phase_1_Android_Build_OAuth_review_brief.md`.

## Problem
"Sync all" uploaded correctly, but repeated runs created **duplicates in Google Drive** (extra copies of the same `conversations/<id>/…` files). Cause: the upload path is **find-then-create, which is not atomic**. When two syncs for the same conversation overlap — a background auto-sync (fired when a job completes) racing a manual "Sync all", or a double tap — both can observe "no remote file yet" and each create a fresh copy. Google Drive permits duplicate names in a folder, so nothing stops it.

## Fix (two small changes)

### 1. Per-conversation in-flight guard — `lib/services/sync_service.dart`
`syncConversation(id)` now guards on a `_inFlight` id set: a second overlapping call for the same id no-ops instead of uploading. The upload body was extracted into `_syncConversationUnsafe(id)` and is wrapped in `try { … } finally { remove id }` so the guard always clears. This is the real fix for the race (including the background auto-sync vs manual "Sync all" overlap, and double taps across separate `syncAll` runs).

### 2. Disable action buttons while running — `lib/screens/history_screen.dart`
Added a `_busy` state to `_HistoryScreenState`. `_syncAll()` and `_restore()` set it around their await (with `try/finally`), and the "Sync all" / "Restore from cloud" buttons are disabled (`onPressed: _busy ? null : …`) while a run is in flight, preventing a double tap from starting two overlapping runs. This screen already surfaces the first failure reason in the snackbar and logs full reasons to the console (added earlier for diagnosis) — that stays.

### Regression test — `test/unit/sync_service_test.dart`
Added "overlapping syncs for the same id upload only once": fires two concurrent `syncConversation('job_1')` calls and asserts the cloud sees exactly **one** upload set (2 uploads — result.json + manifest.json) rather than two.

## Existing duplicates
The duplicates already uploaded to Drive are **not** auto-cleaned by this change (cleaning live Drive data by script is risky). Recommendation: Jack removes the extra `conversations/<id>/` copies by hand, keeping one set per job. A "clean duplicates" tool could be scoped later with the select-which-to-sync feature.

## Verification status
- **`flutter analyze`:** no issues. **`flutter test`:** **202/202 green** (added 1 sync regression test). Run in-sandbox with Flutter 3.47.1 (`.dsh/` copy); analyzer file-descriptor noise is environmental.
- On-device re-test of duplicate-free sync is **pending** (Jack to rebuild and confirm repeated "Sync all" no longer adds copies).

## What Claude should do
1. Review the two changes against the described race; confirm the guard and button-disable are correct and sufficient.
2. Re-run `flutter test` and `flutter analyze`.
3. Confirm the decision to leave existing duplicates for manual cleanup (and note it if a "clean duplicates" tool is worth scoping with the select-which-to-sync feature).
4. **Outcome:** approve, or list required changes for Jack to action. Do not modify code without approval.
