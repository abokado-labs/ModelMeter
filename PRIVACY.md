# Model Meter Privacy Policy

_Last updated: July 14, 2026_

Model Meter is developed by Abokado Labs. Contact: hello@abokadolabs.com.

Model Meter is designed as a local-first macOS menu bar app. Provider usage values, prompts, credentials, and local files stay between your Mac and the providers you enable. Model Meter includes optional first-party anonymous product analytics described below.

## Data Model Meter Reads

### Codex

If Codex is enabled, Model Meter can refresh Codex balances from either the live Codex/ChatGPT route or local Codex files, depending on the data source you select. The default is the live route because it is usually more current.

For live Codex checks, Model Meter may ask Codex app-server for the current account balance. If that is not available, it may use Codex's existing ChatGPT OAuth session from `auth.json` to request live 5-hour and weekly balance data from ChatGPT/OpenAI endpoints. Model Meter does not store your OpenAI password or ask for it directly.

For local Codex file checks, the app may read:

- `sessions/**/*.jsonl` for local Codex rate-limit snapshots.
- `state_5.sqlite` for local token/thread usage detail, queried with `/usr/bin/sqlite3` in read-only mode.

Model Meter does not upload Codex logs, prompts, transcripts, local databases, OAuth tokens, or usage snapshots to Abokado Labs.

### Claude

If Claude is enabled and connected, Model Meter uses your authenticated Claude session to request usage information directly from Claude. Claude credentials are stored in macOS Keychain.

Model Meter does not send Claude credentials to Abokado Labs.

### Gemini

If Gemini is enabled and connected, Model Meter uses an embedded persistent WebKit session to load `https://gemini.google.com/usage` directly from Google and parse the usage percentages and reset times shown there. Model Meter stores only the parsed usage snapshot locally. Google/Gemini web session data remains in WebKit website storage and is not copied into Model Meter Keychain records.

Model Meter does not send Google/Gemini session data to Abokado Labs.

## Network Access

Model Meter requires network access for live Codex balance checks, Claude sign-in and usage checks, Gemini sign-in and usage checks, provider status checks, and Sparkle update checks. If you choose **Local Codex files** as the Codex data source, Codex balance checks avoid the live Codex/ChatGPT balance route but can be stale or incomplete.

## Credential Storage

Claude session credentials are stored in macOS Keychain under Model Meter's Keychain service. Gemini uses WebKit website storage for its embedded web session and stores only parsed usage values locally. You can remove Claude credentials with **Reset Claude credentials** and clear Gemini WebKit session data with **Reset Gemini session** in Settings.

## Software update checks

Model Meter uses Sparkle to check for app updates. When update checks run, Sparkle contacts the Model Meter appcast URL hosted by Abokado Labs. This request may include standard network metadata such as your IP address and user agent, as with any ordinary web request. Model Meter does not send Codex usage, Claude usage, Gemini usage, provider credentials, or local session contents as part of update checks.

## Anonymous Product Analytics

Unless disabled in Settings, Model Meter sends small first-party events for
install, launch, daily active use, update adoption, popover opens, and settings
opens. Events may include the app version/build, macOS major version, CPU
architecture, and a random per-app installation identifier that is hashed
before upload. They do not include prompts, provider usage values, account
identifiers, credentials, or local files. The identifier is not shared across
other Meter apps.

## Data Sharing

Model Meter does not sell, rent, or share your data. There is no Abokado Labs
account system for Model Meter. Abokado Labs receives only the optional
anonymous product events described above and ordinary update/download request
metadata; it does not receive provider usage data.

## Your Controls

You can:

- Disable Codex tracking in Settings.
- Change the Codex home folder.
- Disable Claude tracking in Settings.
- Reset Claude credentials from Settings.
- Disable Gemini tracking in Settings.
- Reset Gemini session data from Settings.
- Disable anonymous usage statistics in Settings.
- Delete the app to stop all local processing.

## Third-Party Services

Model Meter can interact with services you already use: Codex/OpenAI locally through files on your Mac, Claude/Anthropic through an authenticated web session, and Gemini/Google through an authenticated web session. Those services have their own terms and privacy policies.

## Changes

This policy may be updated as Model Meter changes. Material privacy changes should be reflected in the app release notes.
