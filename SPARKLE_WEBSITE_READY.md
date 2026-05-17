# Sparkle Website — Ready Confirmation

Return handoff to Codex from the Abokado Labs website side.

The website infrastructure described in `SPARKLE_WEBSITE_HANDOFF.md` is live and verified. Model Meter's app-side release flow can now proceed without further coordination — drop the signed assets into the documented paths, run `generate_appcast`, and deploy.

## Public URLs (live, verified)

```text
https://abokadolabs.com/model-meter/                  → 200, landing page
https://abokadolabs.com/model-meter/appcast.xml       → 200, valid empty Sparkle XML
https://abokadolabs.com/model-meter/privacy.html      → 200, privacy policy
https://abokadolabs.com/model-meter/releases/         → directory, empty, ready for ZIPs
```

Hosting is Cloudflare Pages. Deploys are manual via `wrangler pages deploy` from Bob's machine (`~/Documents/GitHub/abokadolabs-site`). No CI is wired up.

## Appcast — current state

The published appcast is a deliberate placeholder: valid Sparkle 2.0 XML, zero `<item>` entries, no signatures. Sparkle interprets that as "no updates available" and stays quiet. It exists so the URL responds 200 from app launch one.

```text
File on disk:    ~/Documents/GitHub/abokadolabs-site/model-meter/appcast.xml
Public URL:      https://abokadolabs.com/model-meter/appcast.xml
SUFeedURL:       (matches — already baked into the app)
SUPublicEDKey:   DHBZqhT/krLFIHtzcVR4zUku0yFgVleeRIK8toESI0E= (matches)
```

**Do not handwrite signatures.** Replace the file with one produced by `generate_appcast` against the real signed release.

## Release directory

```text
Path on disk:    ~/Documents/GitHub/abokadolabs-site/model-meter/releases/
Public URL:      https://abokadolabs.com/model-meter/releases/
Naming:          Model-Meter-<version>.zip
Example:         Model-Meter-1.0.0.zip → /model-meter/releases/Model-Meter-1.0.0.zip
```

Directory is currently empty. Drop signed/notarized ZIPs in directly — no manifest to update on the website side.

## Headers — configured

Cloudflare Pages is serving `/_headers` at the site root:

```text
/model-meter/appcast.xml
  Cache-Control: no-cache, no-store, must-revalidate
  Content-Type: application/xml; charset=utf-8

/model-meter/releases/*
  Cache-Control: public, max-age=31536000, immutable
  Content-Type: application/zip
```

Verified via `curl -I`:

- Appcast returns `cache-control: no-cache, no-store, must-revalidate` and `content-type: application/xml; charset=utf-8`.
- ZIP paths inherit `content-type: application/zip` (the 404 for a missing file currently also carries this header — harmless, and resolves once the file exists).
- No auth redirects, no Cloudflare challenge page, no bot protection on these paths.

## Privacy policy

```text
https://abokadolabs.com/model-meter/privacy.html
```

Referenced from the landing page footer and the inline disclaimer block. Reflects the "local-first, no telemetry, Keychain-stored Claude creds" stance described in the app's README. Update there if the app's data behavior changes.

## Disclaimer block

The landing page footer includes:

> Not affiliated with OpenAI, Anthropic, Claude, ChatGPT, Codex, or Apple. Codex, Claude, and their respective marks belong to their owners.

Matches the wording requested in `SPARKLE_WEBSITE_HANDOFF.md`.

## Landing page download button

The landing page download button currently points at:

```text
/model-meter/releases/Model-Meter-1.0.0.zip
```

It will 404 until the actual 1.0.0 ZIP is dropped in place. Two options going forward:

1. **Static link (simplest).** Bump the `href` in `model-meter/index.html` whenever you cut a new version. Manual but explicit.
2. **Latest-version redirect.** If you want a stable `/model-meter/releases/latest.zip` that always points at the newest build, that's a separate small change to add — say the word and I'll wire it up via a `_redirects` rule.

Right now we're on option 1.

## Release workflow (end-to-end)

This is the path the website side expects. Steps marked **[app]** happen in the `gtpusage` repo / on Bob's Mac. Steps marked **[site]** happen in `abokadolabs-site`.

1. **[app]** Build, sign with Developer ID, notarize. Produces `Model-Meter-<version>.zip`. See `DISTRIBUTION.md`.

2. **[app]** Stage for Sparkle:

   ```text
   sparkle-release-staging/
     Model-Meter-<version>.zip
     release-notes/
       <version>.html
   ```

3. **[app]** Generate the appcast (reads the private EdDSA key from Keychain account `com.abokadolabs.ModelMeter`):

   ```bash
   /Users/bobkitchen/Library/Developer/Xcode/DerivedData/ModelMeter-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast \
     sparkle-release-staging
   ```

4. **[site]** Copy two files into the website repo:

   ```bash
   cp sparkle-release-staging/Model-Meter-<version>.zip \
      ~/Documents/GitHub/abokadolabs-site/model-meter/releases/

   cp sparkle-release-staging/appcast.xml \
      ~/Documents/GitHub/abokadolabs-site/model-meter/appcast.xml
   ```

5. **[site]** (Optional) Update the download-button `href` in `model-meter/index.html` to point at the new version.

6. **[site]** Deploy:

   ```bash
   cd ~/Documents/GitHub/abokadolabs-site
   wrangler pages deploy . --project-name=abokadolabs --branch=main
   ```

7. **[verify]**

   ```bash
   curl -I https://abokadolabs.com/model-meter/appcast.xml
   curl -I https://abokadolabs.com/model-meter/releases/Model-Meter-<version>.zip
   ```

   Both should return 200. Appcast body should contain a real `<item>` with `sparkle:edSignature`, `enclosure url`, `sparkle:version`, and `sparkle:shortVersionString`.

## Out of scope for the website

The website does not, and should not:

- Hold the EdDSA private key (stays in Bob's Keychain).
- Run `generate_appcast` (must be run on a machine with the key + a signed/notarized ZIP).
- Sign or modify ZIPs (signed and notarized in Xcode on the app side).
- Track downloads or count installs (no telemetry, by design).

## Contact

If anything on the website side needs to change — header behavior, route paths, additional MIME types, a redirect rule, page copy — say the word.

Site repo: `~/Documents/GitHub/abokadolabs-site` (not currently on GitHub; deploys are manual via `wrangler`).
