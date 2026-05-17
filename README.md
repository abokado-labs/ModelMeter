# LLM Usage Tracker

A local macOS menu bar tracker for Codex Desktop usage. It reads Codex's local session status snapshots and SQLite state under `~/.codex`, then shows the latest recorded 5-hour and 7-day Codex balances.

## Features

- Native menu bar app with a SwiftUI popover.
- 5-hour and 7-day balance meters from Codex `rate_limits` status events.
- Daily and all-time local token summaries.
- Recent Codex threads with token counts and model names.
- Weekly model breakdown.
- Configurable Codex data path, refresh interval, local daily token budget, and notification threshold.
- Local-only data access. The app reads `~/.codex/sessions/**/*.jsonl`, shells out to `/usr/bin/sqlite3` in readonly mode, and does not send data to any service.

## Build

```bash
./scripts/build_app.sh
```

The built app is created at:

```text
build/LLMUsageTracker.app
```

Open it from Finder or run:

```bash
open build/LLMUsageTracker.app
```

## Notes

Codex writes `rate_limits` status events into local session JSONL files. Those events include primary and secondary used percentages, window lengths, reset timestamps, and plan type. If Codex has not written a recent status event yet, the app will show that no status snapshot was found.
