# Contributing to Model Meter

Thanks for considering a contribution. Model Meter is a small, opinionated app, but it has a real surface area — Codex's session files, Claude's authenticated endpoints, the macOS menu bar, Keychain, Sparkle updates — and there's plenty that could be better.

This guide covers how to get set up, what kinds of contributions are welcome, and how to send a change that has the best chance of landing quickly.

## TL;DR

1. Open an issue first for anything bigger than a typo, so we can agree on the shape of the change before you spend time on it.
2. Fork, branch off `main`, make focused commits.
3. Build with Xcode 16 or `scripts/build_app.sh`, run `swift test`, then open a PR against `main`.
4. The maintainer is [@bobkitchen](https://github.com/bobkitchen). Expect a response within a few days.

## Project layout

```
ModelMeter.xcodeproj/   Generated Xcode project (sourced from project.yml)
project.yml             XcodeGen project definition — source of truth
Package.swift           SwiftPM manifest (Sparkle dependency)
Sources/ModelMeter/     Swift source — most app logic lives here
ModelMeter/             App entitlements + Info.plist
Assets.xcassets/        App icon + image assets
Tests/                  Unit tests (swift test)
scripts/build_app.sh    One-shot debug build to ./build/
DISTRIBUTION.md         Release flow: sign, notarize, Sparkle appcast
```

If you change source layout or add a target, regenerate the Xcode project from `project.yml` — don't hand-edit `ModelMeter.xcodeproj/`.

## Setting up

You need:

- **macOS 14 or newer** — the app uses APIs from macOS 14, and Xcode runs there comfortably.
- **Xcode 16 or newer** — for the Swift toolchain and SwiftUI features the app relies on.
- **(Optional) [XcodeGen](https://github.com/yonaskolb/XcodeGen)** — if you change `project.yml` and need to regenerate `ModelMeter.xcodeproj/`. `brew install xcodegen`.

Clone and open:

```bash
git clone https://github.com/abokado-labs/ModelMeter.git
cd ModelMeter
open ModelMeter.xcodeproj
```

In Xcode, pick the `ModelMeter` scheme and "My Mac" as the destination, then press Run. The app lives in the menu bar, not the Dock.

Or build from the command line:

```bash
./scripts/build_app.sh
open "build/Model Meter.app"
```

For testing Codex integration, you need to have actually used Codex locally so there's data in `~/.codex` for the app to read. For Claude, sign in via Settings — credentials live in macOS Keychain.

## What kinds of contributions are welcome

**Definitely welcome:**

- Bug fixes — especially around Codex session parsing, Claude session handling, or menu-bar rendering edge cases.
- Performance — anything that reduces refresh CPU, file-watching cost, or memory.
- Reliability — better error recovery when Codex hasn't written a snapshot, Claude session expires, Keychain is locked, etc.
- New menu-bar customization options that respect the existing settings model.
- Documentation, comments, and inline reasoning for non-obvious code.
- Test coverage for the usage-reader parsing logic.

**Worth opening an issue first:**

- Support for an additional provider (Google AI Studio, OpenRouter, etc) — depends on whether there's a stable, authenticated, non-fragile data source.
- Major UI changes to the popover or menu bar — the current shape is intentional but not sacred.
- Anything that changes the data flow (introducing a server, adding telemetry, sending data anywhere).

**Probably not a fit:**

- Telemetry, analytics, crash reporting that phones home. The app is local-first by design and the [privacy policy](https://abokadolabs.com/model-meter/privacy.html) reflects that.
- A Windows or Linux port — the app is tightly coupled to AppKit, Keychain, and the macOS menu bar.
- An iOS version — Codex data lives on a Mac, so an iOS app would have nothing to read.

If you're not sure whether something is a fit, open an issue and ask.

## Coding conventions

- **Swift style**: follow the surrounding code. No tabs. Lines under ~120 chars where reasonable. Use `// MARK: -` to section files. Prefer explicit types in public APIs.
- **Comments**: explain *why*, not *what*. If a workaround exists, leave a comment with enough context that a future contributor (or you, six months from now) can decide whether the workaround is still needed.
- **Logging**: use `OSLog` via the existing `Logger` instances. Don't `print()` in production paths.
- **Threading**: SwiftUI work stays on the main actor. Network and file IO go on detached tasks. Avoid `Task { @MainActor in ... }` deep inside business logic — pass actors explicitly.
- **Errors**: prefer typed errors over throwing `NSError`. The existing `VaultKeyStoreError` style is the model.
- **Dependencies**: prefer Apple frameworks. New SwiftPM dependencies should be discussed in an issue first; the only current dependency is Sparkle.

## Tests

Run all tests:

```bash
swift test
```

Or in Xcode: `Cmd-U`.

If you're changing usage-reader logic (Codex session parsing, Claude usage parsing), add a unit test that covers the new shape. Sample input fixtures can go under `Tests/ModelMeterTests/Fixtures/`.

## Commits and PRs

- **Commits**: imperative mood, short subject line ("Add provider toggle for Anthropic", not "Added provider toggle"). Body explains *why* if it's not obvious from the diff.
- **Branches**: branch off `main`. Name them `fix/short-description` or `feat/short-description`.
- **PRs**: one concern per PR. A 200-line PR that does one thing is easier to land than a 2000-line PR that does ten. Reference the issue you're solving in the description.
- **CI**: there's no CI yet. Run `swift test` locally and confirm the app builds before opening the PR.

## Releasing (maintainers)

See [DISTRIBUTION.md](DISTRIBUTION.md) for the full release flow: build, Developer ID sign, notarize, generate Sparkle appcast, deploy to the website. Contributors don't need to worry about this — releases happen on the maintainer's machine because the Sparkle EdDSA private key lives in their Keychain.

## Code of conduct

Be considerate. Disagree with ideas, not people. Assume good faith. If something feels off, open an issue or email [hello@abokadolabs.com](mailto:hello@abokadolabs.com).

## License

By contributing, you agree that your contributions will be licensed under the same license as the project. See [LICENSE](LICENSE).
