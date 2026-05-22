# Changelog

## 1.1.0 - Unreleased

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
