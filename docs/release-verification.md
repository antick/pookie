# Public release verification

## Environment and baseline

- Development Mac: Apple Silicon, macOS 26.6.2, Xcode 27.1.
- Existing baseline: `make selftest` passed before implementation.
- Full Git history: gitleaks 8.30.1 found no secrets; working directory scan also passed.
- Existing Developer ID Application certificate matches team `2L85KT5GNL`.
- Existing Apple notarization API credentials validated and reused in `pookie-notary`.
- Sparkle uses the app-specific `pookie` signing account; public key is in Info.plist.
- Protected GitHub release secrets are configured; their values were not logged.
- Existing production preferences (including roster) were saved privately before acceptance.

## Verification summary

Public releases 0.1.0 and 0.1.1 passed complete hosted checks and release workflows.
The public installer is installed and its own native updater completed a real
0.1.0 → 0.1.1 upgrade, preserving every original production preference and roster.

A fresh physical Mac, older supported macOS versions, conferencing capture behavior,
and multi-monitor/full-screen acceptance cannot be inferred from headless tests.

## Implementation and artifact preflight

- Full bare `make test` passed after app isolation and bundled-defaults fixes.
- 23 Swift tests and 32 release-script tests pass after the final signed-feed policy fix.
- Regression checks observed failures before fixes for development storage/notification
  leakage, bare Sparkle dynamic linking, bundled preference initialization, termination
  cleanup, and feed-signature expiration. A temporary real `.app` is launched by tests.
- Real upstream Sparkle signature checks accept valid files and reject altered archives
  and signed feeds. Production requires signed metadata indefinitely and verifies archives
  before extraction; the 20-day fallback is disabled.
- Development bundle check passed identity, icon, license, framework symlinks, ad-hoc
  signature, six arm64-only binaries and bundled pet selftests.
- `make poses` completed; pose sheet and both procedural app icons were inspected.
- Independent whole-diff review identified the feed-expiration issue above; it was fixed
  with failing-then-passing runtime and packaging regressions. No other shipping finding.
- GitHub workflow audit (zizmor 1.30.1, offline) found no actionable issues.
- Real Developer ID preflight passed signing and Apple notarization submission
  `4a570bb4-856c-4d90-9d66-1b7d54758902`; stapling and Gatekeeper verification passed,
  with all six native binaries arm64 only. Final tagged artifacts are verified separately.
- Repository is public, GPL recognized by GitHub, private vulnerability reports enabled.
- GitHub Pages uses Actions and the `release` and `github-pages` environments allow `v*` tags.

## Development UI and isolation

- Launched Pookie Dev from its actual bundle with Settings.
- General/Behaviour/Pookies tabs rendered and were inspected. Development login
  registration is disabled; the checkbox was visibly disabled.
- Toggled development Quiet mode on and back off, read both UI states, and compared
  production preferences: every existing production key and the 12-entry roster
  stayed unchanged.
- User asked to keep working without foreground window control. Remaining acceptance
  runs in the background; browser clicks and foreground updater dialogs are not used.

## Public 0.1.0 and installation

- Main checks passed at `d04d54ee81a5ea6753b4a0c789ba6ee82e2dad76` (run 40097381098).
- Release run 40097640631 passed both publication and Pages deployment.
- https://github.com/antick/pookie/releases/tag/v0.1.0 is public and stable.
- All five downloaded assets matched SHA256SUMS; the source tarball matched its exact
  Git tag and contained license, manifest, lockfile, build scripts and build instructions.
- The unauthenticated DMG download matched the API download, and the live Pages appcast
  matched the archive/version. DMG and app passed stapling and Gatekeeper as Notarized Developer ID.
- Mounted the public DMG read-only without a Finder window, verified its Applications
  symlink, and installed `/Applications/Pookie.app` version 0.1.0/build 1.
- Installed signatures and all six arm64-only native binaries were verified again.
- Launched the installed app hidden/in the background beside Pookie Dev. Both control
  sockets responded independently, each mode 0600; production had four pets on the desk
  and development one. The original 12-entry production collection remained unchanged.
- Automatic checks were temporarily disabled during controlled acceptance to avoid
  foreground update dialogs while the user works; the original setting is restored after testing.

## Native 0.1.0 to 0.1.1 update: passed

- 0.1.1 main checks (40097967300) and release/Pages workflow (40098281292) passed at
  `dd7eb380e8a550b7de022e59809dc7075857bc42`. All five public assets, matching source,
  checksums and live appcast were downloaded and verified independently.
- The installed production app's own `SPUUpdater` checked the live feed and downloaded
  the public 0.1.1 archive. Temporary automatic download/install preferences enabled
  background acceptance without any window clicks or activation.
- Unified logs recorded `OK: EdDSA signature is correct for appcast` and
  `OK: EdDSA signature is correct for update` before extraction. Its staged app was
  0.1.1/build 2 with valid nested Developer ID signatures and six arm64-only binaries.
- Normal background termination of Pookie let Sparkle's registered installer replace
  `/Applications/Pookie.app`. No manual replacement or external updater was used.
- On-disk readback confirmed 0.1.1/build 2. Developer ID, nested signatures, notarization
  staple, Gatekeeper and all six arm64-only binaries passed again afterward.
- Every original production preference and the 12-entry collection matched the private
  pre-install snapshot. Temporary automatic-update preferences were restored to their
  original values; ordinary automatic checking follows the release's enabled default.
- Relaunched 0.1.1 hidden/in the background. Both production and Pookie Dev control
  sockets responded independently after the upgrade. Signed-app logs show all six
  global hotkey registrations succeeded.
- The temporary signing Keychain and exported CI material were removed; the exact
  prior user Keychain search list was restored. The permanent `pookie-notary` profile
  still validates, and the updater key remains in login Keychain with its protected backup.

## Limits retained for manual acceptance

No further foreground browser/menu/dialog clicks were used after the user asked to
keep working. The native automatic updater path was tested in the actual installed
app; its manual Check for Updates dialog, physical key presses, login reboot behavior,
fresh-machine Gatekeeper confirmation, supported older macOS, real screen sharing,
and multi-monitor/full-screen interaction remain manual checks. These are not inferred
from selftests. The original unrelated pet/renderer backlog stays open in TODO.md.

Sparkle logged a non-fatal stale-download-bookmark warning before continuing with valid
archive verification, and its background-app gentle-reminder advisory. Neither prevented
the verified native upgrade. Manual update notification presentation remains unverified.
