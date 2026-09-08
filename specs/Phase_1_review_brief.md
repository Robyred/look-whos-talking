# Phase 1 Storage & History — Review Brief for Claude

- **Date:** 8 September 2026
- **Requested by:** Jack
- **Purpose:** Claude reviews and approves the Phase 1 implementation before it is committed. Review only — do not modify code without Jack's approval.
- **Spec to review against:** `specs/specs_Phase_1_Storage_&_History.txt`
- **Claude review:** `specs/CLAUDE_REVIEW_specs_Phase_1_Storage_&_History.txt` (8 Sep) — verdict **Approved pending two fixes**; spec conformance and documented deviations all confirmed. Both fixes are now applied and re-verified (see "Review fixes applied" below).

## Review fixes applied (8 Sep)

Claude's two required fixes, both done and re-verified:

1. **Database handle leak in `ConversationStore.close()`** — `_open()` now assigns the opened database to the `_db` field (`return _db = await _factory.openDatabase(...)`), so `close()` closes the real handle instead of `null?.close()`. Two regression tests added under `test/unit/conversation_store_test.dart` (group `close`): the handle is genuinely closed (`db.isOpen == false`, `debugDatabase` nulled) and the store re-opens cleanly afterwards. Test seam: `@visibleForTesting Database? get debugDatabase`.
2. **Dead dependency `flutter_secure_storage`** — removed from `pubspec.yaml`; `flutter pub get` dropped it and its 5 transitive packages from `pubspec.lock`. Nothing in `lib/` imports it (tokens stay owned by `google_sign_in` 7.x).

**Re-verification after fixes:** `flutter test` **156/156 green** (154 original + 2 new), `flutter analyze` reports **No issues found** (the analysis server still logs file-descriptor-limit noise in this sandbox — same environmental issue Claude noted; not a code issue).

**Still outstanding (unchanged):** device-side verification — real Google sign-in/OAuth, sqflite on real Android, actual Drive round-trip. Plus Jack's decision on the commit plan.

## What to review

All implementation and test files below were produced from the spec on 8 Sep 2026 (current repo state). They are **new, untracked files** under `flutter_app/`.

### Implementation (`flutter_app/lib/`)
```
lib/models/conversation_record.dart          # 8-field record, UTC-normalised timestamps
lib/models/cloud_models.dart                 # RemoteFileInfo, RemoteConversationMeta
lib/models/sync_summary.dart                 # SyncSummary
lib/services/conversation_store.dart         # sqflite CRUD: save/list/get/delete/deleteAudio/markSynced
lib/services/cloud_storage_provider.dart     # abstract interface + AuthException/StorageException
lib/services/google_drive_provider.dart      # provider logic: app-folder auto-create, overwrite-not-duplicate, idempotent delete, account-switch cache invalidation
lib/services/google_drive_gateway_impl.dart  # real googleapis adapter (query building, mapping)
lib/services/google_drive_services.dart      # google_sign_in OAuth — compile-verified only, not device-tested
lib/services/conversation_manifest.dart      # manifest.json model for cross-device restore
lib/services/sync_service.dart               # syncConversation/syncAll/fetchRemoteIndex/downloadConversation
lib/services/storage_cleanup_service.dart    # 90-day threshold, audio-only deletion, 30-day prompt suppression, injectable clock
lib/view_models/history_view_model.dart      # load/delete/deleteAudio/syncAll/restoreFromCloud + loading/loaded/error states
lib/screens/history_screen.dart              # History UI: rows, tap→Results, swipe-delete, sync/restore actions
```

### Tests (`flutter_app/test/`)
```
test/unit/conversation_record_test.dart
test/unit/cloud_models_test.dart
test/unit/conversation_store_test.dart
test/unit/google_drive_provider_test.dart
test/unit/google_drive_gateway_impl_test.dart
test/unit/sync_service_test.dart
test/unit/storage_cleanup_service_test.dart
test/unit/history_view_model_test.dart
test/unit/auth_header_client_test.dart
test/widget/history_screen_test.dart
```

### Supporting change
`flutter_app/pubspec.yaml` / `pubspec.lock` — new dependencies: `sqflite`, `shared_preferences`, `googleapis`, `google_sign_in`; dev: `sqflite_common_ffi`. (`flutter_secure_storage` was initially added, then **removed as unused** per Claude's review — see "Review fixes applied".)

## Things Jack wants you to know before reviewing

1. **The History screen is deliberately not wired into the app yet.** No screen navigates to `HistoryScreen`, and nothing calls `ConversationStore.save()` from the processing flow. That integration was explicitly deferred as a follow-up (along with the cleanup `shouldPrompt()` call in HomeScreen). Review the implementation *against the spec*, not end-to-end app behaviour.
2. **Everything listed here is untracked — and the repo is missing a pre-existing baseline too.** Only 17 files under `flutter_app/` are tracked (last commit `03c0a3c`, 3 Sep). Files that *predate* Phase 1 and are also untracked include `lib/main.dart`, `lib/config.dart`, `lib/models/job_result.dart`, `lib/models/insights.dart`, `lib/utils/`, `lib/screens/record_screen.dart`, and the `android/ ios/ linux/ macos/ web/ windows/` platform folders. So: not every untracked file is Phase 1 output, and a clean commit history may need a baseline commit first. Please recommend a commit plan.

## Decisions already made with Jack (not bugs)

- **Drive folder model — Option A:** a *visible* "Look Who's Talking" app folder in My Drive. The spec contradicted itself (hidden app folder cannot contain subfolders, yet paths like `conversations/{id}/result.json` are required).
- **Sync/restore design:** a small `manifest.json` per conversation (carrying filename/createdAt/durationSec/speakerCount) uploaded beside `result.json` and optional `audio.aac`, so a new device restores real metadata.
- **Deliberate deviation from the spec:** tokens are *not* mirrored into `flutter_secure_storage`. `google_sign_in` 7.x already persists/refreshes its session in platform secure storage; mirroring would create stale-copy bugs. Documented in `google_drive_services.dart`. Consequently the unused `flutter_secure_storage` dependency was removed from `pubspec.yaml` (review fix #2).
- **UTC-normalised timestamps** in `ConversationRecord` because SQL `ORDER BY` on wall-clock strings mis-sorts across DST.
- Cloud upload paths use `.aac` extension (`conversations/{id}/audio.aac`) per the spec's remote-path convention.

## Verification status at hand-off

- Reported green at hand-off: **154/154 `flutter test`, `flutter analyze` zero issues**, run with Flutter 3.47.1 inside the DeepSeek sandbox (a copy of the SDK lives under git-ignored `.dsh/` — ≈2.3 GB, deletable). Now **156/156** after the two review fixes (see "Review fixes applied").
- **Not yet verified (needs a device, not a sandbox):** real Google sign-in/OAuth flow (`google_drive_services.dart`), sqflite on real Android, an actual Drive upload/restore round-trip.

## What Claude should do

1. Read the spec, then read each implementation file and check conformance section by section (data models, ConversationStore, CloudStorageProvider/GoogleDriveProvider, SyncService incl. manifest, StorageCleanupService, HistoryViewModel + History screen).
2. Confirm the decisions above are reflected and intentional — don't "correct" them.
3. Re-run `flutter test` and `flutter analyze` (Flutter 3.47.1 is available on this machine; the `.dsh/` copy also works).
4. Sanity-check the deferred-wiring plan and recommend a commit structure given the untracked baseline.
5. **Outcome:** approve, or list required changes for Jack to action. Do not modify code without approval.
