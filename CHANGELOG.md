# Changelog

## 1.3 - 2026-07-14

Aligns Model Meter with the Meter family settings and privacy controls.

### Changed
- Refined settings layout and navigation.
- Added a clear control for optional first-party anonymous usage statistics.
- Added reliability and maintenance improvements.

## 1.2 - 2026-06-13

Adds usage history with 24-hour and 7-day graph views, clarifies Codex live balance behavior, and improves reading reliability.

### Changed
- Live Codex refresh now tries Codex app-server first, then falls back to Codex's ChatGPT OAuth session in `auth.json`.
- README and privacy policy now disclose live Codex balance checks and distinguish them from Local Codex files mode.
- Provider cards now show a separate reading-confidence line, such as fresh live reading, local fallback reading, last good reading, or unavailable.
- The dashboard now includes a compact history chart for recent provider readings.
- History now plots hourly usage buckets in the 24-hour view and daily peak buckets in the 7-day view.
- History charts now show percentage and time-axis labels.
- Reset labels now show a countdown, with the exact reset time available on hover.
- Reset labels can now be switched between countdown and calendar date/time formats.
- Menu bar display can now be reduced to all providers, lowest available provider, warning-only text, or icon-only.
- The menu-bar dashboard remains a popover and includes a bottom-right resize handle; Model Meter remembers the last dashboard size.
- The history legend now follows the same provider letter/icon setting as the menu bar.

### Fixed
- Claude and Gemini refreshes no longer overlap when a timer refresh and manual refresh happen at the same time.
- Codex and Claude preserve the last good balance reading when a later refresh fails.
- Provider outage status, reading confidence, and usage pace warnings are shown as separate signals.
- Gemini now also preserves the last good parsed usage reading when a later refresh fails.
- Sparse history charts now show visible sample dots instead of appearing empty before a line can be drawn.
- Provider connection, plan/source, and updated-at metadata are now combined into one concise row.
- Footer controls now leave clear space for the resize grip.

## 1.1.2 - 2026-05-23

Improves Codex balance tracking and makes the data source explicit.

### Added
- Codex data source selector in Settings with `Live ChatGPT` and `Local Codex files` options.
- Xcode logging for the selected Codex route and live refresh result.

### Changed
- Codex now defaults to the live ChatGPT usage route for current 5-hour and weekly balances.
- Local Codex file reading remains available as an explicit fallback.

### Fixed
- Codex could show no reading or fall back to stale local data even when the live usage endpoint was returning valid balances.

## 1.1.1 - 2026-05-22

Small typographic fix for the menu-bar readout.

### Fixed
- Menu-bar text was rendering one pixel high relative to the provider icons next to it — mathematically centered but optically off because of the icons' template rendering. Baseline calculation now nudges the text down by one pixel so it sits visually flush with the icons.

### Notes
- No functional or behavioral change. If you're on 1.1.0 and you're happy with the alignment, this release is purely cosmetic.

## 1.1.0 - 2026-05-22

Adds a third provider and overhauls the settings experience.

### Added
- **Gemini support.** Optional authenticated tracking of Google Gemini usage percentages by loading `https://gemini.google.com/usage` in an embedded persistent WebKit session and parsing the rendered values. No Gemini API key required; nothing is estimated.
- **Reset Gemini session** action in Settings to clear the WebKit session data and parsed snapshots.
- Three-provider menu bar readouts (e.g. `C 74%  Cl 98%  G 82%`) with the same letters/icons toggle as Codex and Claude.
- Persistent Gemini snapshot caching so transient failures preserve the last good readout instead of blanking the menu bar.

### Changed
- **Settings UI overhauled** for clarity at three providers, with grouped sections, clearer enable toggles, and a live menu-bar preview that reflects every change immediately.
- Privacy policy and third-party notices updated to cover the Gemini integration, WebKit website storage, and the Google Gemini logomark.
- README, requirements list, and attribution list updated to reflect Gemini.

### Notes
- Gemini sign-in uses WebKit website storage, not Keychain, because the Google session is browser-style rather than a bearer token. Claude sign-in continues to use Keychain.
- Codex remains entirely local-first; nothing changed there.

## 1.0.0 - 2026-05-17

Initial public release.

- Native macOS menu bar app for Codex and Claude usage windows.
- Codex local rate-limit snapshot reader.
- Claude authenticated usage integration.
- 5-hour and weekly used/available balance views.
- Configurable menu bar metric, labels, icons, font size, provider visibility, and pace warnings.
- Keychain storage and reset action for Claude credentials.
- Sparkle-based update checks (EdDSA-signed appcast).
- Local-first privacy documentation and third-party notices.
