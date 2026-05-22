# Model Meter

**A native macOS menu bar app for tracking Codex, Claude, and Gemini usage windows.**

🌐 **Website**: [abokadolabs.com/model-meter](https://abokadolabs.com/model-meter/) &nbsp;·&nbsp;
📦 **Download**: [Latest release](https://abokadolabs.com/model-meter/releases/Model-Meter-1.0.0.zip) &nbsp;·&nbsp;
🔒 **Privacy**: [Policy](https://abokadolabs.com/model-meter/privacy.html) &nbsp;·&nbsp;
🤝 **Contributing**: [Guide](CONTRIBUTING.md)

---

Model Meter is a native macOS menu bar app for tracking AI assistant usage windows. It currently supports local Codex/OpenAI usage data, optional authenticated Claude usage data, and optional authenticated Gemini usage percentages from Google's Gemini usage page.

The app is designed for people who use Codex, Claude, and Gemini heavily and want a small, always-visible indication of remaining capacity without opening each product.

Made by [Abokado Labs](https://abokadolabs.com) — a small dev shop building considered software for everyday problems.

## What It Shows

Model Meter shows two usage windows for each enabled provider:

- **5-hour window**: short-term usage for the current rolling/session window.
- **Weekly window**: longer-term usage for the current weekly allowance window.

For each window, the popover shows:

- **Used** percentage.
- **Available** percentage.
- A progress bar showing usage.
- A time marker showing how far through the current reset window you are.
- The next reset time.

The menu bar can show Codex, Claude, and Gemini values at the same time, for example:

```text
C 74%  Cl 98%  G 82%
```

You can choose whether that value means used or available, and whether it represents the 5-hour or weekly window.

## Data Sources

### Codex / OpenAI

Model Meter reads Codex data locally from your Codex folder, normally:

```text
~/.codex
```

It reads:

- `sessions/**/*.jsonl` for Codex rate-limit snapshots.
- `state_5.sqlite` for local token/thread detail, using `/usr/bin/sqlite3` in read-only mode.

Codex balance data is not fetched from an official public OpenAI usage-balance API. The app surfaces the local rate-limit snapshots that Codex writes on your machine. If Codex has not written a recent snapshot, Model Meter cannot invent one and will show that status is unavailable.

### Claude

Claude usage is optional. If enabled, Model Meter signs in through a Claude web session and stores the session credentials in macOS Keychain. It then calls Claude's authenticated usage endpoint to display the same 5-hour and weekly format used for Codex.

Claude credentials are stored locally in Keychain. Model Meter does not store them in plain text files.

### Gemini

Gemini usage is optional. If enabled, Model Meter opens `https://gemini.google.com/usage` in an embedded WebKit sign-in window. It keeps that WebKit session persistent across app restarts, refreshes the rendered usage page in the background, and stores only the parsed usage percentages and reset times locally.

Gemini support does not use the Gemini API and does not estimate usage. Safari does not need to be open. If Google does not expose percentages on the usage page, Model Meter preserves the last good snapshot and shows Gemini as unavailable rather than guessing.

## License

Model Meter is distributed under the MIT License. See [`LICENSE`](LICENSE).

Third-party trademark and attribution notes are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Privacy And Security

Model Meter is intended to be local-first. See [`PRIVACY.md`](PRIVACY.md) for the full privacy policy.

- Codex data is read from local files on your Mac.
- Claude access is optional and uses your authenticated Claude session.
- Gemini access is optional and uses your authenticated Google/Gemini web session.
- Claude credentials are stored in macOS Keychain; Gemini uses WebKit website storage and stores only parsed usage values locally.
- The app does not upload your Codex history or local usage database to a third-party service.
- The app requires network access for Claude sign-in/usage checks, Gemini sign-in/usage checks, and Sparkle update checks.

For distribution, the app should be signed and notarized with a stable Developer ID certificate so Keychain trust behaves consistently for users.

## Requirements

- macOS 14 or newer.
- Xcode 16 or newer for local development.
- Codex installed and used locally if you want Codex data.
- Claude account if you want Claude data.
- Google account with Gemini usage percentages visible at `https://gemini.google.com/usage` if you want Gemini data.

## Attribution

Model Meter is not affiliated with, endorsed by, or sponsored by OpenAI, Anthropic, Google, Gemini, Claude, ChatGPT, Codex, or Apple. Provider names and optional provider icons are used only to identify the services the user has chosen to track.

## Installation For Users

Once a signed release is available:

1. Download the latest release from GitHub or the Model Meter website.
2. Open the downloaded `.dmg` or `.zip`.
3. Move **Model Meter.app** to your `Applications` folder.
4. Open **Model Meter**.
5. If macOS warns that the app was downloaded from the internet, choose **Open**.
6. The app appears in the macOS menu bar, not the Dock.

If the menu bar is crowded, macOS may hide some menu bar items. Move or hide other menu bar apps if Model Meter is not visible.

## Updates

Model Meter includes Sparkle for app updates outside the Mac App Store. Users can check manually from **Settings > About & Privacy > Check for Updates** or by right-clicking the menu bar item and choosing **Check for Updates...**. Updates are verified with Sparkle signing before installation.

## Running From Xcode

For development:

1. Open the project:

```bash
open ModelMeter.xcodeproj
```

2. Select the `ModelMeter` scheme.
3. Select **My Mac** as the run destination.
4. Press **Run** in Xcode.

The app runs as a menu bar app. It will not show a normal Dock icon or main window.

## Manual Build

A local build script is also available. It builds through Xcode so Swift Package dependencies such as Sparkle are embedded correctly:

```bash
./scripts/build_app.sh
```

The script prints the built `.app` path when it finishes.

For release signing, notarization, and Sparkle appcast publishing, use Xcode Archive. See [`DISTRIBUTION.md`](DISTRIBUTION.md).

## First-Time Setup

### Codex

Codex is enabled by default.

1. Open Model Meter from the menu bar.
2. Click the gear icon to open Settings.
3. Confirm **Enable Codex** is on.
4. Confirm **Codex home** points to your Codex folder, normally:

```text
/Users/YOUR_USER/.codex
```

5. Click **Save and Refresh**.

If Codex data is missing, open Codex and use it normally. Model Meter depends on Codex writing local session snapshots before it can show balance data.

### Claude

Claude is optional.

1. Open Model Meter from the menu bar.
2. Click the gear icon to open Settings.
3. Turn on **Enable Claude**.
4. Click **Sign in with Claude**.
5. Complete the Claude sign-in flow in the web window.
6. Click **Use This Session** when the app detects the signed-in Claude session.
7. Click **Save and Refresh**.

If Claude credentials become stale or Keychain access behaves oddly, use **Reset Claude credentials**, then sign in again.

### Gemini

Gemini is optional.

1. Open Model Meter from the menu bar.
2. Click the gear icon to open Settings.
3. Turn on **Enable Gemini**.
4. Click **Sign in with Gemini**.
5. Sign in to Google/Gemini in the web window and wait for the Usage Limits page to show real percentages.
6. Click **Connect**.
7. Click **Refresh Gemini** or **Save and Refresh**.

Model Meter refreshes Gemini through its own embedded WebKit session. Safari does not need to be open. If the Gemini web session becomes stale, use **Reset Gemini session**, then sign in again. If Google changes the usage page or hides percentages, Model Meter preserves the last good snapshot and shows a clear error rather than guessing.

## Settings Reference

### Providers

**Enable Codex**  
Turns the Codex section on or off. When enabled, Model Meter reads local Codex rate-limit and usage files.

**Codex home**  
The folder where Codex stores local state. The default is `~/.codex`.

**Enable Claude**  
Turns the Claude section on or off. Claude requires sign-in before usage data can be shown.

**Sign in with Claude**  
Opens a Claude sign-in window and captures the authenticated session for usage checks.

**Organization ID**  
The Claude organization ID used for usage calls. The app attempts to detect this during sign-in.

**Session key**  
A Claude session credential. It is stored in Keychain when saved or captured from sign-in.

**Reset Claude credentials**  
Deletes Model Meter's Claude credentials from Keychain, including older legacy credential entries. Use this if Claude sign-in breaks, credentials expire, or macOS repeatedly asks for Keychain access.

**Enable Gemini**  
Turns the Gemini section on or off. Gemini requires sign-in before usage percentages can be shown.

**Sign in with Gemini**  
Opens the Gemini usage page in an embedded WebKit sign-in window. After the Usage Limits page renders, click **Connect** to confirm the session and store the parsed usage snapshot.

**Refresh Gemini**  
Reloads `https://gemini.google.com/usage` through Model Meter's persistent WebKit session and parses the displayed usage percentages and reset times. Safari does not need to be open.

**Reset Gemini session**  
Clears Model Meter's stored Gemini snapshot and removes Google/Gemini website data from Model Meter's embedded WebKit session. Use this if Gemini sign-in breaks or Google requires a fresh login.

### Menu Bar

**Show Codex in menu bar**  
Shows or hides the Codex value in the menu bar.

**Show Claude in menu bar**  
Shows or hides the Claude value in the menu bar.

**Show Gemini in menu bar**  
Shows or hides the Gemini value in the menu bar.

**Metric**  
Chooses which percentage appears in the menu bar:

- **5-hour used**: percentage consumed in the 5-hour window.
- **5-hour available**: percentage remaining in the 5-hour window.
- **7-day used**: percentage consumed in the weekly window.
- **7-day available**: percentage remaining in the weekly window.

**Provider labels**  
Chooses how providers are identified in the menu bar:

- **Letters**: `C` for Codex, `Cl` for Claude, and `G` for Gemini.
- **Icons**: compact provider icons.

**Icon**  
Shows or hides the overall Model Meter status icon in the menu bar.

**Font size**  
Adjusts the menu bar text size. Smaller sizes help if your menu bar is crowded.

**Warn when ahead of pace**  
Turns the selected menu bar value red when usage is ahead of the elapsed-time marker for the current reset window. The time marker in the popover bars is always shown; this setting only controls the warning color in the menu bar.

**Current menu bar**  
Shows a preview of what will appear in the menu bar with the current settings.

## How To Read The Popover

Each provider has its own section.

- The green check means the provider is configured and has refreshed successfully.
- A question mark means the provider is not configured or has no current data.
- The left tile is the 5-hour window.
- The right tile is the weekly window.
- The colored bar shows used capacity.
- The white vertical marker shows elapsed time in the reset period.

If the colored usage bar is ahead of the white time marker, you are using that provider faster than the current period's pace.

## Troubleshooting

### Model Meter is not visible in the menu bar

Model Meter is a menu bar app and does not show a normal Dock icon. If it is running but not visible, your menu bar may be crowded. Try hiding other menu bar items or reducing Model Meter's menu bar font size.

### Codex shows no data

Check that:

- Codex is enabled in settings.
- `Codex home` points to the correct `.codex` folder.
- You have used Codex recently enough for it to write local session snapshots.
- `~/.codex/sessions` contains recent `rollout-*.jsonl` files.

### Codex shows 0% used after a reset

That can be correct. If the 5-hour window has just reset, Codex may report `0% used` for the new window while the weekly value remains non-zero.

### Claude shows not connected

Open Settings and sign in with Claude. If the session has expired, use **Reset Claude credentials** and sign in again.

### Gemini shows not connected or unavailable

Open Settings and sign in with Gemini. Make sure the web window is showing `https://gemini.google.com/usage` with real percentages before clicking **Connect**. If the session has expired, use **Reset Gemini session** and sign in again.

### macOS asks for Keychain access

Claude credentials are stored in Keychain. Gemini uses Model Meter's embedded WebKit website data store rather than storing Google cookies in Keychain. A signed release build should have stable Keychain identity. Development builds can prompt more often, especially after rebuilds. If prompts keep recurring for Claude, reset Claude credentials, then sign in again.

## Development Notes

The app is Swift/SwiftUI with an AppKit menu bar host.

Useful commands:

```bash
swift test
xcodebuild -project ModelMeter.xcodeproj -scheme ModelMeter -configuration Debug build
```

The Xcode project is generated/configured around:

- `ModelMeter.xcodeproj`
- `project.yml`
- `Sources/ModelMeter`
- `Assets.xcassets`
- `ModelMeter/ModelMeter.entitlements`

## Current Limitations

- Codex balance data depends on local Codex snapshots; there is no official OpenAI balance API used by the app.
- Claude integration depends on an authenticated Claude web session and may need to be refreshed if Claude changes its session behavior.
- Gemini integration depends on `https://gemini.google.com/usage` exposing visible percentages for the signed-in account and may need to be refreshed if Google changes that page.
- App Sandbox is currently off because the app reads `~/.codex`, uses Keychain, launches `/usr/bin/sqlite3` read-only, and uses WebKit for Claude/Gemini sign-in.

## Distribution

Before publishing, review:

- [`DISTRIBUTION.md`](DISTRIBUTION.md) for signing, notarization, and release packaging.
- [`PRIVACY.md`](PRIVACY.md) for privacy copy.
- [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for attribution and trademark notes.
- [`CHANGELOG.md`](CHANGELOG.md) for release notes.
