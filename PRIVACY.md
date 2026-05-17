# Model Meter Privacy Policy

_Last updated: May 17, 2026_

Model Meter is developed by Abokado Labs. Contact: hello@abokadolabs.com.

Model Meter is designed as a local-first macOS menu bar app. It does not use an Abokado Labs server and does not include analytics or telemetry.

## Data Model Meter Reads

### Codex

If Codex is enabled, Model Meter reads local Codex files from the Codex home folder you configure, normally `~/.codex`.

The app may read:

- `sessions/**/*.jsonl` for local Codex rate-limit snapshots.
- `state_5.sqlite` for local token/thread usage detail, queried with `/usr/bin/sqlite3` in read-only mode.

This data stays on your Mac. Model Meter does not upload Codex logs, prompts, transcripts, local databases, or usage snapshots to Abokado Labs.

### Claude

If Claude is enabled and connected, Model Meter uses your authenticated Claude session to request usage information directly from Claude. Claude credentials are stored in macOS Keychain.

Model Meter does not send Claude credentials to Abokado Labs.

## Network Access

Model Meter requires network access only for Claude sign-in and Claude usage checks. Codex usage is read locally.

## Credential Storage

Claude session credentials are stored in macOS Keychain under Model Meter's Keychain service. You can remove them from Settings using **Reset Claude credentials**.

## Software update checks

Model Meter uses Sparkle to check for app updates. When update checks run, Sparkle contacts the Model Meter appcast URL hosted by Abokado Labs. This request may include standard network metadata such as your IP address and user agent, as with any ordinary web request. Model Meter does not send Codex usage, Claude usage, Claude credentials, or local session contents as part of update checks.

## Data Sharing

Model Meter does not sell, rent, or share your data. There is no Abokado Labs account system for Model Meter, and no Abokado Labs backend receives your usage data.

## Your Controls

You can:

- Disable Codex tracking in Settings.
- Change the Codex home folder.
- Disable Claude tracking in Settings.
- Reset Claude credentials from Settings.
- Delete the app to stop all local processing.

## Third-Party Services

Model Meter can interact with services you already use: Codex/OpenAI locally through files on your Mac, and Claude/Anthropic through an authenticated web session. Those services have their own terms and privacy policies.

## Changes

This policy may be updated as Model Meter changes. Material privacy changes should be reflected in the app release notes.
