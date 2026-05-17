# Sparkle Website Handoff For Model Meter

Model Meter is a macOS menu bar app distributed outside the Mac App Store. It now embeds Sparkle for app updates.

This document is the website-side brief for Claude Code or whoever manages the Abokado Labs website.

## Required Public Paths

Create and support these URLs:

```text
https://abokadolabs.com/model-meter/
https://abokadolabs.com/model-meter/appcast.xml
https://abokadolabs.com/model-meter/releases/
```

The app is already configured with:

```text
SUFeedURL = https://abokadolabs.com/model-meter/appcast.xml
SUPublicEDKey = DHBZqhT/krLFIHtzcVR4zUku0yFgVleeRIK8toESI0E=
```

## What The Website Must Host

For each release, host:

```text
/model-meter/releases/Model-Meter-<version>.zip
/model-meter/appcast.xml
```

Example:

```text
/model-meter/releases/Model-Meter-1.0.0.zip
/model-meter/appcast.xml
```

## Appcast Generation

The appcast should be generated with Sparkle's `generate_appcast` tool, not handwritten.

On Bob's Mac, Sparkle's tools are available after building the app with Xcode, currently under a path like:

```bash
/Users/bobkitchen/Library/Developer/Xcode/DerivedData/ModelMeter-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast
```

Suggested release folder structure for generation:

```text
sparkle-release-staging/
  Model-Meter-1.0.0.zip
  release-notes/
    1.0.0.html
```

Then run:

```bash
/path/to/generate_appcast sparkle-release-staging
```

That should create or update `appcast.xml` with Sparkle signature metadata.

## Security Notes

Do not edit Sparkle signatures manually.

The private Sparkle signing key is stored in Bob's macOS Keychain under account:

```text
com.abokadolabs.ModelMeter
```

The website only needs the public appcast and release archive.

The private key must not be committed, uploaded, or placed on the website.

Release archives should be Apple Developer ID signed and notarized before being published.

## MIME And Hosting Requirements

Make sure the website serves:

```text
.xml  -> application/xml or text/xml
.zip  -> application/zip
.html -> text/html
```

The files should be downloadable directly without auth, login redirects, or blocked bot protection.

## Caching

Avoid aggressive caching for:

```text
/model-meter/appcast.xml
```

Recommended header:

```http
Cache-Control: no-cache
```

Release ZIPs can be cached long-term because they are versioned.

## Website Page

Create a simple download page at:

```text
https://abokadolabs.com/model-meter/
```

It should include:

- App name: Model Meter
- Short description: macOS menu bar tracker for Codex/OpenAI and Claude usage balances
- Download latest version button
- Link to GitHub repo if available
- Link to privacy policy
- Link to license
- Note: "Not affiliated with OpenAI, Anthropic, Claude, ChatGPT, Codex, or Apple."

## First Release Target

Assume first public version:

```text
Version: 1.0.0
Build: 1
Minimum macOS: 14.0
Archive name: Model-Meter-1.0.0.zip
Appcast URL: https://abokadolabs.com/model-meter/appcast.xml
Download URL: https://abokadolabs.com/model-meter/releases/Model-Meter-1.0.0.zip
```

## Acceptance Checks

After deployment, these should work:

```bash
curl -I https://abokadolabs.com/model-meter/appcast.xml
curl -I https://abokadolabs.com/model-meter/releases/Model-Meter-1.0.0.zip
```

Expected:

- HTTP 200
- Appcast is public XML
- ZIP is public and downloadable
- No auth redirects
- No Cloudflare or challenge page
- Appcast references the correct HTTPS download URL

## App-Side Repo

The Model Meter app-side changes already exist in:

```text
/Users/bobkitchen/Documents/GitHub/gtpusage
```

The release instructions are in:

```text
DISTRIBUTION.md
```
