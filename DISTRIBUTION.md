# Model Meter Distribution

## Xcode setup

1. Open `ModelMeter.xcodeproj`.
2. Select the `ModelMeter` target.
3. In **Signing & Capabilities**, choose your Apple Developer team.
4. Confirm the bundle identifier. The generated default is `com.bobkitchen.ModelMeter`; change it if you want it tied to your website domain.
5. Confirm **Hardened Runtime** is enabled for Release builds.
6. Keep App Sandbox off. Model Meter needs to read `~/.codex`, use Keychain, launch `/usr/bin/sqlite3` read-only, and load Claude sign-in through WebKit.

## Release archive

From Xcode:

1. Choose **Any Mac** as the run destination.
2. Select **Product > Archive**.
3. In Organizer, choose **Distribute App**.
4. Choose **Developer ID**.
5. Let Xcode sign and notarize the app.
6. Export the notarized app and package it as a `.dmg` or `.zip` for GitHub/website distribution.

## Command-line archive

```bash
xcodebuild \
  -project ModelMeter.xcodeproj \
  -scheme ModelMeter \
  -configuration Release \
  -destination "generic/platform=macOS" \
  archive \
  -archivePath build/ModelMeter.xcarchive
```

Then export with your Developer ID export options from Xcode Organizer or an `ExportOptions.plist` that includes your team ID.

## Sparkle updates

Model Meter uses Sparkle for direct updates outside the Mac App Store. The current appcast URL is:

```text
https://abokadolabs.com/model-meter/appcast.xml
```

The Sparkle public key embedded in the app is:

```text
DHBZqhT/krLFIHtzcVR4zUku0yFgVleeRIK8toESI0E=
```

The matching private signing key is stored in this Mac's login Keychain under Sparkle account `com.abokadolabs.ModelMeter`. Keep that private key secure. It is required to sign future updates.

Release update flow:

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Run `xcodegen generate`.
3. Archive, sign, and notarize the Release app with Developer ID.
4. Package the notarized app as a `.zip` or `.dmg`.
5. Put the packaged update and release notes in a staging folder.
6. Run Sparkle's `generate_appcast` tool against that folder. Xcode stores the tool under DerivedData after the Sparkle package resolves, for example `SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast`.
7. Upload the packaged update and generated `appcast.xml` to the website path above.
8. Use **Check for Updates...** from the menu bar context menu or Settings to verify the feed.

## Before public release

- Confirm the AppIcon looks correct in Finder, Dock, app bundle preview, and the DMG/ZIP.
- Confirm `LICENSE`, `PRIVACY.md`, `THIRD_PARTY_NOTICES.md`, and `CHANGELOG.md` are included in the repository.
- Confirm the bundled Settings links open Privacy and Licenses from the app resources.
- Confirm the app displays the Abokado Labs copyright metadata.
- Confirm Sparkle `SUFeedURL` points at the production Abokado Labs appcast.
- Confirm the Sparkle public key matches the private signing key in Keychain before publishing.
- Confirm provider icons are optional and letter labels remain available.
- Confirm the app says it is not affiliated with OpenAI, Anthropic, Claude, ChatGPT, Codex, or Apple.
- Test first launch, Codex-only use, Claude sign-in, Claude credential reset, and quit/reopen behavior.
- Test the signed and notarized download on a different Mac or clean user account.
- Create a GitHub release with the notarized artifact and release notes from `CHANGELOG.md`.
