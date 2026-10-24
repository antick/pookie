# Releasing Pookie

Pookie is distributed directly through GitHub Releases for Apple Silicon only,
macOS 14 or newer. Sparkle 2.10.0 is pinned exactly; its stable release was published
on 2026-09-13, more than two days before adoption. GPL-3.0-or-later covers Pookie;
Sparkle keeps its upstream notices. The application bundle includes both licenses.

## Development and installed use

`make dev` builds and opens Pookie Dev. `make run` runs the development binary.
Production is `/Applications/Pookie.app`, identifier `com.pookie.pet`. Development
is `Pookie Dev.app`, identifier `com.pookie.pet.dev`. Preferences, support directories,
control sockets/port discovery, speech bridge and shortcuts are separate. Development
adds Shift to the usual control-option shortcuts and disables login registration
and production updates. Unknown or unbundled executable launches use development.

The production `com.pookie.pet` preference domain stays intact, preserving existing
settings and pet collections. Neither channel rewrites the other's preferences.
Both may be running simultaneously; each has its own menu bar item and icon.

## Trust and hosting

- Developer ID Application certificate with its existing private key; team `2L85KT5GNL`.
- Existing Apple notarization API credentials, referenced locally as `pookie-notary`.
- Sparkle Ed25519 signing key, stored in login Keychain under account `pookie`.
  Keep a secure backup; only its public key is in Resources/Info.plist.
  Feed verification failures never expire (`SUSignedFeedFailureExpirationInterval=0`);
  retain the signing-key backup because update recovery depends on it.
- Public downloads: `https://github.com/antick/pookie/releases`.
- Stable appcast: `https://antick.github.io/pookie/appcast.xml`.
- The GitHub `release` environment permits `v*` tags. Its secrets hold certificate,
  notarization and updater signing material; ordinary pull requests cannot read them.
- Pages uses Actions deployment. The `github-pages` environment permits version tags.

A DMG uses a drag-to-Applications install and needs a Developer ID Application
certificate. It does not need a separate Developer ID Installer certificate.
The normal first-download confirmation is expected. Bypassing Gatekeeper or
removing quarantine is not an installation step.

## Release checklist

1. Update Resources/Info.plist: CFBundleShortVersionString is the public version;
   CFBundleVersion is a strictly increasing numeric build. Add CHANGELOG.md notes.
2. Run `make selftest`, `swift test` and the release script tests. Inspect `make poses`
   when art/geometry changed. Verify a development bundle and diff before committing.
3. Commit and push main, then confirm CI passes for that exact commit.
4. Create an immutable matching `vVERSION` tag and push it. The release workflow
   validates tag/version/build/main ancestry and release notes, then tests and builds.
5. The workflow thins every bundled Mach-O executable to arm64, signs nested helpers
   before their containers with hardened runtime and timestamps, notarizes/staples,
   verifies Gatekeeper, and builds the DMG, ZIP, checksum list and update appcast.
6. It uploads the complete asset set to a draft release, publishes it, verifies public
   downloads, then deploys the update feed. No unsigned fallback is permitted.
7. Download the public DMG in a browser, install it into Applications, verify the
   signature and notarization, launch it, and exercise the actual installed update.

Never move a published tag or replace assets underneath a published checksum/signature.
Fix a broken release with a higher version/build. If an update is bad, withdraw its
feed entry while preparing a corrected higher version; do not promise automatic downgrades.

## Acceptance evidence

A build passing does not prove installation or updates. Record artifact signatures,
notarization, architectures, public downloads/feed, installation path, and actual
old-to-new installed upgrade separately in `release-verification.md`. Check roster
and settings preservation, simultaneous development, hotkeys, login behavior, and
that no prohibited OS permission is requested. A fresh physical Mac is an additional
check when only this development machine is available.

## Maintainer commands

```sh
make test
make verify-dev
export POOKIE_SIGN_IDENTITY='Developer ID Application: Pankaj Sanam (2L85KT5GNL)'
export NOTARY_PROFILE=pookie-notary
make release
```

`make release` requires a clean checkout at a matching `vVERSION` tag whose commit
has been pushed to `origin/main`. It writes `build/release/Pookie.app` and
`build/release-artifacts`. `SPARKLE_KEY_FILE` may reference a private exported
Sparkle key; without it, signing uses the `pookie` Keychain account. An optional
`NOTARY_KEYCHAIN` selects the dedicated temporary release keychain.

CI imports `MAC_CERTIFICATE` (base64 PKCS#12), `MAC_CERTIFICATE_PASSWORD`,
`APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, and `SPARKLE_PRIVATE_KEY`
from the `release` environment. Its temporary keychain is added to the existing
search list, then removed with secrets deleted and the prior list restored on
success or failure. Secret-bearing command output is withheld on errors.

The pinned Actions are checkout v7.0.1, upload-pages-artifact v5.0.0 and
deploy-pages v5.0.1, all verified as latest stable and older than two days when
adopted. Workflows use their immutable commit hashes. No latest dependency was
skipped due to the age rule.

References: [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Sparkle setup](https://sparkle-project.org/documentation/), and
[Sparkle security settings](https://sparkle-project.org/documentation/customization/).
