# Contributing to Pookie

Pookie is GPL-3.0-or-later. Contributions are accepted under that same license.
Keep the copyright and third-party notices intact.

You need an Apple Silicon Mac, macOS 14 or newer, and Xcode with Swift 6 support.
Clone the repository and run `make selftest` and `swift test`. Use `make dev` for
a development app with separate settings; it can run alongside an installed release.

Read AGENTS.md and docs/DESIGN.md before changing behavior. Add a meaningful check
for behavior changes. Keep touched code files under 500 lines; extract reusable
pieces instead of duplicating UI or release logic. Centralize constants and date
formatting. Dependencies must be pinned exactly and released at least two days ago.

For art or geometry changes, run `make poses` and inspect the generated sheets.
Update README.md, docs/DESIGN.md and docs/ROADMAP.md when behavior changes, and
remove completed work from TODO.md. Open a pull request explaining the problem,
the resulting behavior and how you verified it. Ordinary contributions never
need Apple signing credentials.

See docs/releasing.md for the maintainer release process. Never commit signing
keys, tokens, certificates containing private keys, or notarization credentials.
