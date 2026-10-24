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

## Acceptance in progress

The source includes identity/update tests and packaging/signature tests. Final
results, artifact trust checks, public URLs, installed versions, development
coexistence and a real signed upgrade will be recorded here as each completes.

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
