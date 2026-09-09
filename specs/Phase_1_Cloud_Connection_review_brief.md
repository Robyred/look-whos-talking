# Phase 1 Cloud Connection Services — Status Brief for Claude

- **Date:** 8 September 2026
- **Requested by:** Jack
- **Purpose:** Bring Claude fully up to date on the cloud-connection work (all three providers) **before** we proceed to fixing saving/sync and adding a select-which-conversations feature. Review only — no code changes without Jack's approval.
- **Base commit:** `17f2e9b` on `phase1-storage`. All changes since are **uncommitted working-tree** edits (the committed `17f2e9b` is the pre-fix state that would not build).
- Related context: `specs/Phase_1_Settings_Share_review_brief.md`, `specs/Phase_1_Android_Build_OAuth_review_brief.md`.

## Where we are — provider connection status (all on-device)

All three providers now **connect and disconnect** from the Settings screen. Each had a distinct blocker that is now resolved:

| Provider | Mechanism | Resolved blocker | Status |
|---|---|---|---|
| **Google Drive** | google_sign_in 7.2 (Credential Manager) | ① `serverClientId` was the **Android** client ID → must be the **Web** client ID (error 28444). ② OAuth consent screen in **Testing** → added Jack's gmail as a **test user** (was 403 "verification not complete"). | ✅ Connects + disconnects |
| **OneDrive** | flutter_appauth 12.1 | Redirect hand-back broke for all appauth providers because `MainActivity` had `android:taskAffinity=""` → removed. | ✅ Connects + disconnects |
| **Dropbox** | flutter_appauth 12.1 | Same `taskAffinity` fix + precise redirect intent-filter (`host=2`, `pathPrefix=/token`). | ✅ Connects + disconnects |

Supporting facts Claude should know:
- Google/OneDrive/Dropbox identifiers in code are **public client IDs** (PKCE/no secret) — safe to commit.
- Google `_googleServerClientId` (`1054824041438-qcikh0mkhrcib5r0dr627g1vo43n9u5h.apps.googleusercontent.com`) is the **Web** OAuth client ID; the **Android** OAuth client (package `com.lookwhostalking.look_whos_talking` + debug SHA-1) is registered in the console only and does not appear in code. Both are in project "My First Project".
- OAuth consent screen is in **Testing** with Jack's account as a test user — fine for development; refresh tokens in Testing expire after ~7 days; shipping needs Production + verification (for the sensitive `drive.file` scope).

## Current open problem — saving/sync

**"Sync all" reports `Synced 0, 4 failed`** — 4 stored conversations all fail to sync. All failing together suggests a single systemic cause in the upload path (hypothesis: the Drive provider uses the `drive.file` scope but `GoogleDriveProvider` tries to manage a named **folder** under My Drive — find/list/create folder — which that scope may not permit, so every upload fails). **Not yet diagnosed** — the app previously showed only the failed *count*.

Recent uncommitted change to help diagnose: `history_screen.dart` `_syncAll()` snackbar now shows the **first failure reason** (truncated to 220 chars) when any sync fails. Status: **pending a device re-run of "Sync all"** to capture the real error text and confirm/refute the scope hypothesis.

## Planned next (not started)
1. Fix the "Sync all" failures (root cause above) so uploads actually succeed.
2. Then add a **select-which-conversations-to-sync** feature (multi-select in History) — proposed as its own small spec + review brief.

## Verification status
- **`flutter analyze`:** no issues. **`flutter test`:** 200/200 green (as of the last full run). On-device builds succeed.

## What Claude should do
1. Confirm the provider-connection work above is sound and the current state is understood.
2. Note the open "Sync all fails 0/4" item and the working hypothesis; weigh in on whether the `drive.file`-vs-My-Drive-folder mismatch is the likely cause and what the correct fix is (e.g. use the Drive **appDataFolder** scope/space, or create files app-owned at a permitted location) before we change code.
3. Sanity-check the error-surfacing change and the plan to scope "select-which-to-sync" as a separate spec.
4. **Outcome:** confirm current state / advise on the sync fix approach. Do not modify code without Jack's approval.
