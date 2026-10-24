# Pookie public release

The user approved implementing, publishing and installing the proposed end-to-end release, including Sparkle, GPL licensing and development isolation. Apple Silicon only; macOS 14 or newer. Use the existing main Chrome profile if account access is required. Reuse credentials; never print secrets.

## Approach

Direct distribution through GitHub Releases and a GitHub Pages Sparkle appcast. A notarized drag-to-Applications DMG installs the app. Sparkle 2.10.0 is an exact-pinned, deliberately approved exception to the no-dependency rule. Its release is older than two days. Manual download-only updates do not meet the requested complete update flow; the Mac App Store adds an unrelated distribution process.

Production is Pookie.app / com.pookie.pet in /Applications. Development is Pookie Dev.app / com.pookie.pet.dev. Preferences, Application Support, sockets, notification bridges, shortcuts, login registration and updater state must be isolated. Bare executable launches default to development. Existing production preferences survive.

## Distribution contract

Resources/Info.plist owns CFBundleShortVersionString and CFBundleVersion. Production feed: https://antick.github.io/pookie/appcast.xml. Downloads: https://github.com/antick/pookie/releases/download/vVERSION/Pookie-VERSION-arm64.zip and .dmg. Artifacts: DMG, ZIP, SHA256SUMS, appcast.xml, corresponding source with build instructions. Sparkle account: pookie. Signing identity: Developer ID Application: Pankaj Sanam (2L85KT5GNL). Local notary profile: pookie-notary (reuse working Apple team credentials).

All Mach-O code shipped must be arm64 only, including Sparkle helpers. Production must fail closed without Developer ID signing and successful notarization; ad-hoc signatures are development-only. Staple notarization tickets and verify Gatekeeper. Publish assets before updating the feed. Only trusted version-tag releases access signing secrets; untrusted pull requests cannot.

## Acceptance

Baseline and final make selftest pass. Add tests for identity isolation and release validation. Verify malicious/inconsistent update metadata and altered archives are rejected. Install a publicly downloaded signed build, run development alongside it, test actual upgrade to a newer signed build, and compare preferences/roster. Check real menu, settings, shortcuts, login and pet behavior without granting prohibited permissions. Record anything requiring the user's participation honestly.

## Open source and maintenance

GPL-3.0-or-later, copyright Pankaj Sanam. Scan full tracked history for secrets before public visibility. Keep third-party notices and exact source/build information. Update README, DESIGN, ROADMAP and remove only completed TODO items. Keep each touched code file below 500 lines by coherent extraction. Pin all dependencies and Actions to immutable versions at least two days old. No HTTP endpoints are introduced; the existing local NDJSON protocol remains documented in docs/PROTOCOL.md.
