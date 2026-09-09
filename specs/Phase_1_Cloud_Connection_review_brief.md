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

**"Sync all" reports `Synced 0, 4 failed`** — 4 stored conversations all fail to sync. Two sequential causes were found and resolved:
1. **Google Drive API disabled** → `DetailedAPIRequestError(status: 403, … not been used in project … or it is disabled …)`. Fixed (console): enabled **Google Drive API** (APIs & Services → Library). After enabling, the error changed to a 400.
2. **Apostrophe in the app-folder name breaks Drive `q` queries** → `DetailedAPIRequestError(status: 400, … Invalid Value)`. The default Google app-folder name was **"Look Who's Talking"**; the gateway builds `q` as `name = '$name' …`, and a single quote can't be escaped inside a Drive name search — so every folder lookup returned 400. Fixed (code): renamed the GoogleDriveProvider default `appFolderName` to **"Look Whos Talking"** (no apostrophe). No existing folder to migrate (lookups failed before any create). Drive-provider unit tests updated for the new default name, plus a regression test asserting the default folder name contains no apostrophe. `flutter analyze` clean; full suite green.
(For reference: OneDrive keeps "Look Who's Talking" as a Graph *path* folder — not a query — so it is unaffected.)

Error-surfacing changes were added to `history_screen.dart` `_syncAll()` (first reason in the snackbar + full reasons logged to the console); these made both diagnoses possible and stay.

## Planned next (not started)
1. ~~Re-test "Sync all"~~ ✅ done — all 4 conversations now sync to Google Drive.
2. Then add a **select-which-conversations-to-sync** feature (multi-select in History) — proposed as its own small spec + review brief. Note for that spec: sync currently always runs through the single Google provider regardless of which provider was most recently connected.
3. **Jack requirement (must appear in that spec):** cloud sync should be **opt-in, not the default behaviour** — i.e. auto-sync-on-completion should be off by default, and syncing should be an explicit manual action ("Sync All" + the selective per-conversation control). This removes the current surprise where "Sync All" never appears because every job auto-syncs. If this is not in the drafted spec, Jack asked to be reminded.

## Verification status
- **`flutter analyze`:** no issues. **`flutter test`:** 201/201 green (incl. the new apostrophe regression test). On-device builds succeed.
- **On-device sync re-test:** after the two fixes, "Sync all" now completes — all four stored conversations synced to Google Drive (final message "Synced 4"). The "Sync all" action hides once nothing is unsynced (expected `hasUnsynced` behaviour); it reappears when a new unsynced conversation is saved.

## What Claude should do
1. Confirm the provider-connection work above is sound and the current state is understood.
2. Note the two resolved "Sync all fails 0/4" causes (Drive API disabled → console; apostrophe in folder name → code fix + regression test) and confirm the fix approach.
3. Sanity-check the error-surfacing change and the plan to scope "select-which-to-sync" as a separate spec.
4. **Outcome:** confirm current state. Do not modify code without Jack's approval.
