# Phase 1 Wiring — Review Brief for Claude

- **Date:** 8 September 2026
- **Requested by:** Jack
- **Purpose:** Claude reviews the Phase 1 wiring pass before it is committed. Review only — do not modify code without Jack's approval.
- **Spec to review against:** `specs/specs_Phase_1_Wiring_Specs.txt`
- **Base to review on top of:** branch `phase1-storage` @ `4f1e19b` — the earlier review's fixes (ConversationStore close fix, `flutter_secure_storage` removal, regression tests) are already committed there. Prior review context: `specs/Phase_1_review_brief.md` and `specs/CLAUDE_REVIEW_specs_Phase_1_Storage_&_History.txt`.

## Repo state

- `5e8b370` baseline + `4f1e19b` feat(phase1) are committed on `phase1-storage` and pushed to origin.
- This wiring pass is **uncommitted** on top of `4f1e19b`. It adds no new services or business logic — only call sites, navigation, and shared dependency wiring, per the wiring spec.

## Files in this pass

### Modified (tracked)
```
flutter_app/lib/main.dart                          # async main: builds one ConversationStore + createGoogleDriveProvider(), passes into LookWhosTalkingApp(store, cloud)
flutter_app/lib/models/job_result.dart             # JobStatusResponse.rawResultJson — backend result payload captured at parse time
flutter_app/lib/screens/home_screen.dart           # Stateful; AppBar history icon → HistoryScreen; post-first-frame cleanup prompt dialog
flutter_app/lib/screens/processing_screen.dart     # accepts store/cloud/sourceFilename/retainAudio; persists completed job before navigating; recordingDisplayName() helper
flutter_app/lib/screens/record_screen.dart         # passes store/cloud + "Recording YYYY-MM-DD HH:mm" label + retainAudio: true
flutter_app/lib/screens/upload_screen.dart         # passes store/cloud + picked filename + retainAudio: false
flutter_app/lib/services/conversation_store.dart   # dropped unused meta import/@visibleForTesting (analyzer depend_on_referenced_packages); debugDatabase seam retained, doc-only
flutter_app/lib/view_models/history_view_model.dart# refreshCloudAuth(): provider errors read as "not authenticated"
flutter_app/test/widget_test.dart                  # smoke test updated for injected store/cloud
```

### New (untracked)
```
flutter_app/lib/services/persist_completed_job.dart      # persistCompletedJob(): best-effort save + background sync, never throws
flutter_app/test/unit/persist_completed_job_test.dart    # 10 tests (raw JSON capture, save/sync error paths)
flutter_app/test/widget/home_screen_test.dart            # 7 tests (History nav, cleanup prompt + all three actions)
flutter_app/test/helpers/fakes.dart                      # shared MemoryStore + FakeCloud for widget tests
```

## Interpretation decisions made while wiring (not bugs)

1. **Save point:** ProcessingScreen persists at job completion, *before* navigating to **NameReviewScreen** (the app's real flow is Processing → Name review → Results, so this is still "before any results navigation" — earlier than the spec's literal wording).
2. **Raw JSON:** `rawResultJson` = `jsonEncode` of the decoded `result` payload inside `JobStatusResponse.fromJson` — payload-faithful (same keys/values/order as received), deliberately *not* a re-serialisation of the parsed Dart models.
3. **History entry:** AppBar trailing history icon (spec option b) — avoids adding a third card that would risk vertical overflow on small screens.
4. **audioPath semantics:** recordings live in app documents → `retainAudio: true` persists the path. Uploads live in the file-picker's cache → path is not persisted (`audioPath: null`), so History never points at a file the OS may clean up.
5. **Display name:** RecordScreen stamps "Recording YYYY-MM-DD HH:mm" at stop time; UploadScreen passes the picked filename; ProcessingScreen keeps the same fallback for any null source.
6. **Cloud is non-nullable** through the tree (per spec), but every auth/sync call site degrades gracefully: `persistCompletedJob` treats auth-check failures as "not signed in", and `HistoryViewModel.refreshCloudAuth()` now catches provider errors → `cloudAuthenticated = false`, so History never crashes on hosts without the sign-in plugin.
7. **Cleanup prompt:** shown post-first-frame; the "90 days" text reads `StorageCleanupService.defaultOlderThanDays` (no magic-number drift); actions exactly per spec (Delete audio → delete + `recordPromptShown()`; Keep for now → `recordPromptShown()`; Remind me later → nothing). All failure paths swallowed — a launch nicety, never startup-blocking.
8. **Persistence helper as a standalone function** (`persist_completed_job.dart`) so the save+sync wiring is unit-testable headless per the test-every-function skill, rather than buried in a widget.

## Verification status

- **174/174 `flutter test` green** (156 before this pass + 10 persist-helper unit tests + 7 home widget tests + updated smoke), **`flutter analyze` no issues** — run in-sandbox with Flutter 3.47.1 (git-ignored `.dsh/` copy). The analyzer still logs file-descriptor-limit noise in this sandbox; that is environmental, not a code issue.
- New tests cover: raw-JSON capture (present on completion / null before), save happy path + all fields, null audioPath, save-failure swallowed without cloud contact, auth-check failure tolerated, sync fired only when authenticated, sync failure swallowed; Home renders actions + History icon, History navigation, prompt shown for old recordings / hidden for recent, and the three dialog actions' effects incl. next-launch behaviour.
- Widget tests note: the cleanup path touches `shared_preferences`, whose mock resolves through real-async platform channels, so those tests drive pumps inside `tester.runAsync`; "relaunch" unmounts the tree first because pumping the same widget type would reuse HomeScreen state and skip `initState`.

## Not verified (needs a device, not a sandbox)

- Real Google sign-in/OAuth + actual Drive upload/restore round-trip.
- End-to-end on-device flow: record/upload → processing → save → History entry appears → audio playback; cleanup prompt on a real install; sqflite on real Android.

## What Claude should do

1. Read the wiring spec, then each changed file; check the three wiring points (ProcessingScreen persistence, HomeScreen History navigation, HomeScreen cleanup prompt) and the shared-instance wiring in `main.dart`.
2. Confirm the interpretation decisions above are acceptable — especially save-before-name-review, the raw-JSON derivation, and `retainAudio`.
3. Re-run `flutter test` and `flutter analyze` (Flutter 3.47.1 on this machine; `.dsh/` copy works too).
4. Recommend commit shape for this pass (single commit on `phase1-storage`? anything to split?), noting `specs/` is already committed in `4f1e19b`.
5. **Outcome:** approve, or list required changes for Jack to action. Do not modify code without approval.
