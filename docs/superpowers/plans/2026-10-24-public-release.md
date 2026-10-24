# Public Release Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans. Steps track independently verifiable deliverables; implementation is authorized by the user's explicit go-ahead.

**Goal:** Publish and install a GPL licensed, signed, notarized Apple Silicon Pookie with isolated development and verified in-app updates.

**Architecture:** AppIdentity centralizes channel identity. Sparkle manages native signed updates in production only. Shell/Python release tools package and verify bundles; trusted tag CI publishes assets before Pages.

**Tech Stack:** Swift/AppKit, Sparkle exactly 2.10.0, Bash/Python standard library, GitHub Actions.

**Spec:** docs/superpowers/specs/2026-10-24-public-release-design.md

## Global Constraints

Apple Silicon only; macOS 14+. Separate production/dev storage and runtime control. No new OS privacy permissions. Reuse existing Apple credentials. No secrets in git/logs. GPL-3.0-or-later. Touched code files under 500 lines. Approved Sparkle exception only.

## Review Focus

- Concurrent apps never share settings, ports, notifications or shortcuts.
- Unbundled/debug execution never starts the production updater or login item.
- Altered archives and mismatched tags/versions cannot be published or installed.
- All nested native binaries are arm64, signed and notarized.
- Installation and genuine version-to-version upgrade retain the roster/preferences.

## Tasks

1. App isolation and updater (Sources/Pookie, Package.swift, Resources/Info.plist, Tests). Write identity/update policy tests, observe red, implement AppIdentity and UpdateController, extract oversized touched files, run selftest and swift test.
2. Packaging and release tools (scripts, Makefile, .github/workflows). Tests first for source validation, architecture and feed validation. Implement development bundle, signed production bundle, DMG/ZIP, notarization, checksum/feed and trusted tag CI. Run script tests, development package and real signed artifacts.
3. Public readiness (LICENSE, notices, CONTRIBUTING, SECURITY, README, docs). Scan full history without printing secrets. Add GPL text and source notices. Document build, release and installer/update behavior. Verify license and repository state before making public.
4. Credential and hosted setup. Reuse local Developer ID and notary material, create app-specific Sparkle key, configure protected release environment/secrets and Pages. Never expose values. Push tested coherent commits, create immutable version tags and verify CI/public downloads/feed.
5. Acceptance. Install first public signed version and launch Pookie Dev concurrently. Verify identities/settings/control isolation. Publish next version and perform actual installed Sparkle upgrade. Record signing, notarization, architectures, test results and unresolved manual checks in docs/release-verification.md.

Execution ruling: work in this clean root checkout to preserve the user's app binding and existing build cache. Independent app and packaging tasks use shared checkout with disjoint owned paths. Root owns publication, credentials and final acceptance. No extra worktree or permission round is needed after the user's explicit end-to-end instruction.
