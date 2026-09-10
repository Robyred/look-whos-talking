# Phase 1 Human-readable Cloud Folder Names — Review Brief for Claude

- **Date:** 8 September 2026
- **Requested by:** Jack
- **Purpose:** Claude reviews this implementation before it is committed. Review only — do not modify code without Jack's approval.
- **Spec:** `specs/specs_Phase_1_Human-readable_cloud_folder_names.txt` (still untracked in the working tree).
- **Base:** branch `phase1-storage` @ `05d2568` (pushed).

## What changed

### New remote layout
```
conversations/{slug}_{id}/result.json
conversations/{slug}_{id}/manifest.json
conversations/{slug}_{id}/audio.<ext>   ← real source extension (.m4a/.mp3/…)
```
`{slug}` = human-readable slug of the conversation filename.

### `lib/services/sync_service.dart`
- Removed `audioFileName = 'audio.aac'`; added `_audioRemoteName(localPath) => 'audio${p.extension(localPath)}'`.
- Added `_remoteSlug(filename)`: strip extension → lowercase → collapse runs of non-alphanumerics to `-` → strip leading/trailing `-` → truncate to 40 → `'recording'` if empty.
- Added `_idFromFolderName(folderName)`: the substring after the last `_` (or the whole name when there is none) — used for legacy folders.
- `_conversationDir(id, filename)` → `conversations/{slug}_{id}`; `_remotePath(id, filename, name)` delegates to it.
- `_syncConversationUnsafe`: all uploads now use `record.filename`; audio upload uses `_audioRemoteName(audioPath)`.
- `deleteConversationFromCloud(String id, String filename)`: deletes `result.json` + `manifest.json`, then whatever `_findRemoteAudio` reports.
- `_hasRemoteAudio(id)` replaced by `_findRemoteAudio(remoteDir) → Future<String?>` (first file starting with `audio.`).
- `_metaFor(folderName, …)`: cloud paths built as `conversations/{folderName}/…`; success branch returns `id: manifest.id` (authoritative) with `remoteDir: folderName`; legacy branch uses `_idFromFolderName(folderName)` as id and the folder name as the display filename.
- `downloadConversation(String remoteDir)`: `remoteDir` used only for cloud paths; local record id comes from `manifest.id` (legacy: uuid from the folder name); audio downloaded to `'{manifest.id}{extension of remote audio}'`.

### `lib/models/cloud_models.dart`
- `RemoteConversationMeta` gained `final String remoteDir` (the remote folder name), constructor updated.

### `lib/view_models/history_view_model.dart`
- `deleteConversationFromCloud(record.id, record.filename)`.
- `restoreFromCloud` → `downloadConversation(meta.remoteDir)`.

### `conversation_manifest.dart`
- Unchanged, as the spec states (the `id` field already existed).

## Tests
Updated `sync_service_test.dart` path expectations to the new `{slug}_{id}` layout and legacy-folder tests to uuid-style folder names; added a **"human-readable folder names"** group covering: slugified name with extension, punctuation/apostrophes (`"Interview — Jan '26.m4a"` → `interview-jan-26`), 40-char truncation, empty-slug → `recording`, and remote audio extension (`audio.m4a`, no `audio.aac`). Added `remoteDir` to `RemoteConversationMeta` constructions in `cloud_models_test.dart` and `history_view_model_test.dart`.

**`flutter analyze`:** no issues (two `unintended_html_in_doc_comment` infos fixed by backticking `<ext>`/`<uuid>`). **`flutter test`:** **216/216 green.**

## Breaking change (per spec)
Existing `conversations/{uuid}/` folders on the cloud are orphaned — Restore will not surface them (no manifest at the old path). Jack can ignore or delete them manually; acceptable for development (no production users). Re-syncing the same conversations recreates them under the new `{slug}_{id}` names.

## Not yet verified
- On-device: sync a conversation and confirm the Google Drive folder now reads e.g. `my-interview_9212d114-…`, the audio file carries the true extension, delete-from-cloud removes it, and Restore still works against the new layout.

## Follow-up after device testing: prune empty conversation folders (8 Sep 2026)
Device result: delete-from-cloud removed the files correctly, and "Sync all" re-created the folder using the human-readable name — but the **empty conversation folder was left behind** in Drive.
Fix:
- `CloudStorageProvider.deleteFile`'s documented contract is "deletes the entry at remotePath", so `GoogleDriveProvider.deleteFile` now resolves a **file** first and, if none, resolves a **folder** and deletes that — folder pruning with no interface change.
- `SyncService.deleteConversationFromCloud(id, filename)` now deletes the conversation folder after its files (`provider.deleteFile(dir)`), so no empty folders remain.
- Spec `specs/specs_Phase_1_History_Sync_Management.txt` §4 updated: folder pruning is now **in** scope (previously deferred).
Tests: Drive provider test that `deleteFile('conversations/<id>')` removes the empty folder; sync test asserting the folder path is among the deleted entries. **`flutter analyze` no issues, 217/217 green.** Not yet re-verified on device.

## What Claude should do
1. Review the changes against the spec (slug rule order, id-from-manifest, legacy uuid extraction, audio extension handling).
2. Re-run `flutter test` / `flutter analyze` (**216/216**).
3. Confirm the commit: `feat(phase1): human-readable cloud folder names and correct audio extension` (spec-provided message).
4. **Outcome:** approve, or list required changes for Jack to action. Do not modify code without approval.
