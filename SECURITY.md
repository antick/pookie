# Security

Please report suspected vulnerabilities privately through GitHub's
[Report a vulnerability](https://github.com/antick/pookie/security/advisories/new)
feature. Include the version, macOS version, reproduction steps, and likely impact.
Do not post credentials or private information in a public issue.

The latest stable release is the supported version. Download installers from
https://github.com/antick/pookie/releases and use the in-app updater for updates.
Public binaries are Developer ID signed and notarized. Updates are authenticated
with Sparkle signatures; checksum files are an additional download-integrity check.

Pookie does not require Screen Recording, Accessibility, or Input Monitoring
permission. Its control socket is local to your account. Development and released
apps use separate control paths and settings. See docs/MACOS-CONSTRAINTS.md for
what the pet can and cannot observe.
