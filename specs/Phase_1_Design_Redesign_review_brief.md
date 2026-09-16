# Phase 1 UI Redesign (DESIGN_PLAN_v1) — Review Brief for Claude

- **Date:** 8 September 2026
- **Requested by:** Jack
- **Purpose:** Claude reviews the design implementation before/instead of further iteration. Review only — do not modify code without Jack's approval.
- **Plan:** `Jack's documentation etc/DESIGN_PLAN_v1.md`
- **Base:** branch `phase1-storage` @ `bea8c19` (pushed).

## What was implemented (plan §6 order)

| # | Step | Commit |
|---|---|---|
| 1-2 | Dark theme + brand speaker palette | `fdfc0c4` |
| 3 | Home screen (wordmark, tagline, mark, card colours) | `3820cac` |
| 4 + 5.6 | Results single-row scrollable `TabBar` + human-readable file name | `197a212` |
| 5 | History cards, status colours, delete-dialog hierarchy | `81663dd` |
| 6-7 | Record (coral button + pulse ring) and Upload (drop zone) | `0a4d0ac` |
| 8 | Settings (cards, uppercase headings, teal connected) | `cd55dac` |
| 9-11 + 5.7-5.11 | Results tabs styling (Overview, Transcript, Insights, Q&A, Playback) | `84834e7` |
| §8 | Branded Android launcher icon | `3cf125c` |

### Key implementation notes
- **`lib/theme.dart`** holds the palette constants and `buildAppTheme()`: `ColorScheme.dark` with background `#0F1117`, surface `#161B27`, coral primary, teal/amber/violet accents, plus AppBar, card, button, divider, dialog, input, switch, tab-bar, list-tile and progress themes. Deprecation-safe (`surfaceContainerHighest`, `activeThumbColor`, `withValues`) so `flutter analyze` stays clean.
- **Speaker colours** (`speaker_utils.colorForSpeaker`): coral/teal/amber/violet; speakers 5+ repeat the palette at 70% opacity.
- **Home layout made scroll-safe** (`LayoutBuilder` + `SingleChildScrollView` + `IntrinsicHeight`): the larger hero block overflowed short viewports, and this also protects small phones.
- **Results tabs**: `TabBar` (scrollable, coral underline, muted inactive) driven by an internal `TabController`, with `IndexedStack` retained so chat/insights state survives tab switches. `NavButton` is no longer used by Results (widget + tests still exist).
- **Human-readable name**: `ResultsScreen.displayName`, threaded from History (`record.filename`) and from Processing → NameReview (`sourceFilename` or `Recording <timestamp>`); falls back to the backend filename.
- **Launcher icon**: adaptive icon = `#0F1117` background + foreground rasterised from `lwt_icon_v2.svg` with its background rect removed (§8), icon placed inside the 66% safe zone; legacy `ic_launcher.png` replaced at all densities.
- **Asset approach**: the logo mark is rasterised to PNG (1x/2x/3x) with `rsvg-convert` rather than adding a `flutter_svg` dependency.

## Decisions taken with Jack
- Launcher icon **included** in this pass.
- The Insights `SPEAKER_0x`-in-minutes backend bug (plan §5.9) was **deliberately not fixed** here — Jack chose to keep it as a separate task.
- Work was committed in grouped steps (above) so each could be tested incrementally.

## Verification
- **`flutter analyze`:** no issues. **`flutter test`:** **218/218 green** (one settings assertion updated for the new uppercase section heading; speaker-palette tests rewritten for the 4-colour mapping and the 5+ fade).
- Not verifiable in the sandbox: the Android build/launcher icon rendering (Gradle writes outside the workspace) — **on-device check needed**.

## Not yet verified on device
- Overall dark theme across every screen; tab bar; pulse ring while recording; launcher icon (may need an uninstall/reinstall or launcher cache clear to refresh).
- Something to watch: theme-level `FilledButton`/`OutlinedButton` remain full-width (`Size.fromHeight(52)`) as before, so rows that embed them still need bounded styles (the Settings Connect button already does).

## What Claude should do
1. Check the implementation against the plan section by section (palette values, typography, component styling, per-screen changes).
2. Flag anything visually off-spec or any regression risk from the theme-level defaults.
3. Confirm the two deliberate omissions (backend speaker-name bug; `NavButton` now unused) are acceptable.
4. **Outcome:** approve, or list required changes for Jack to action.
