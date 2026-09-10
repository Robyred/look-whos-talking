# Phase 1 Transcript Share — Review Brief for Claude

- **Date:** 8 September 2026
- **Requested by:** Jack
- **Purpose:** Claude reviews this UI fix before it is committed. Review only — do not modify code without Jack's approval.
- **Base:** branch `phase1-storage` @ `9a26ffb` (pushed).

## Problem reported
On device, the **Transcript** tab appeared to have no share action, while Q&A ("Share Q&A") and Insights (inline share icons) did.

## Root cause
The Transcript tab *did* have a share control, but it was a `_ShareBar` pinned to the very bottom of the tab inside the Results screen's `SafeArea(top: false, bottom: false)`. With `bottom: false` the bar sat **behind the Android system navigation bar**, so it was effectively invisible/untappable. Q&A and Insights use inline controls higher up the content, which is why they looked fine.

Secondary bug found while fixing: `_ShareBar` hard-coded the label `'Share transcript'`, so the **Overview** tab's share bar was also mislabelled "Share transcript" even though it shares speaker metrics.

## Changes (`lib/screens/results_screen.dart`)
1. **Transcript tab** — replaced the bottom `_ShareBar` with an **inline share button at the top of the transcript** (`TextButton.icon`, `Icons.share`, label "Share transcript"), matching the placement/style of the Q&A share. It shares the same `_asText()` transcript text.
2. **`_ShareBar` now takes a `label`** (default `'Share'`; `label: Text(label)`), so each usage names what it shares.
3. **Overview tab** — its share bar is wrapped in `SafeArea(top: false)` so it clears the navigation bar, and is labelled **"Share metrics"** (was "Share transcript").
4. No behaviour change to Q&A or Insights share.

## Tests
- New `test/widget/results_screen_test.dart`: pumps `ResultsScreen` with a one-segment transcript, asserts the Overview shows "Share metrics", switches to the Transcript tab and asserts "Share transcript" is present.
- **`flutter analyze`:** no issues. **`flutter test`:** **218/218 green.**

## Not yet verified
- On-device: open a conversation with a transcript, confirm "Share transcript" is visible at the top of the Transcript tab and the native share sheet opens; also confirm Overview reads "Share metrics".

## What Claude should do
1. Review the fix and confirm the diagnosis (bottom bar under the nav bar) and that inline placement matches Q&A/Insights.
2. Re-run `flutter test` / `flutter analyze` (**218/218**).
3. Suggest the commit message when approved (e.g. `fix(phase1): make transcript share visible and label share bars correctly`).
4. **Outcome:** approve, or list required changes for Jack to action. Do not modify code without approval.
