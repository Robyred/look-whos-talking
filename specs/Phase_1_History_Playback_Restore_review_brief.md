# Phase 1 History Playback & Restore Messaging — Review Brief for Claude

- **Date:** 8 September 2026
- **Requested by:** Jack
- **Purpose:** Claude reviews two small device-found fixes before they are committed. Review only — no code changes without Jack's approval.
- **Base:** uncommitted working tree on `phase1-storage` (supersedes the earlier build/OAuth/sync briefs). Related: `specs/Phase_1_Cloud_Connection_review_brief.md`, `specs/Phase_1_Sync_Duplicates_review_brief.md`.

## Problems found on-device (after sync was working)
1. **No playback for a recording opened from History.** A recording's History row correctly shows a sound icon, but opening it produced no Playback tab. Cause: `_openRecord` in `history_screen.dart` pushed `ResultsScreen(jobId, result)` **without the audio file**, and `ResultsScreen` only adds the Playback tab when `audioFile != null`. The three *uploaded* conversations have no audio by design (uploaded files aren't retained), so no playback there is correct.
2. **Misleading "Restored from cloud".** After the user deleted the remote folder (or when there is nothing new), "Restore from cloud" still showed *"Restored from cloud"* even though nothing was downloaded.

## Fixes
1. **`history_screen.dart` `_openRecord`** now loads the stored audio: it builds `File(record.audioPath)` when `audioPath` is present *and the file exists*, and passes it as `ResultsScreen.audioFile`. Recordings opened from History now get their Playback tab back.
2. **Honest restore result.** `HistoryViewModel.restoreFromCloud()` now returns the number of conversations actually downloaded; the History snackbar reports *"Restored N conversation(s) from cloud"* or *"Nothing new to restore"* when the count is 0 (e.g. empty remote, or everything already present locally).

## Noted behaviour (not changed — clarify for the future)
- **Local DB is the source of truth.** `isSynced` is a local flag set after a successful upload; deleting the remote folder externally does **not** reset it, so "Sync all" stays hidden (`hasUnsynced` false) even though the remote copy is gone. This was confusing during testing. Whether to offer an explicit "re-upload / mark-unsynced" affordance (or treat a missing remote as unsynced on restore) is worth deciding when the **select-which-to-sync** feature is specced — flagged here so it isn't lost.

## Verification status
- **`flutter analyze`:** no issues. **`flutter test`:** **202/202 green**.
- **On-device re-test (done, 8 Sep 2026):** ✅ Restore reports "Nothing new to restore" when the remote is empty. ✅ A recording opened from History now shows its Playback tab (audio loads from the stored path).

## What Claude should do
1. Review the two fixes; confirm they're correct and minimal.
2. Re-run `flutter test` / `flutter analyze`.
3. Weigh in on the "re-sync after external delete / local-is-truth" UX question above so it can inform the select-which-to-sync spec.
4. **Outcome:** approve, or list required changes for Jack to action. Do not modify code without approval.
