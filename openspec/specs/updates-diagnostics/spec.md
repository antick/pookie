# updates-diagnostics Specification

## Purpose

Define Sparkle update policy, development disable rules, headless selftest acceptance, PNG review exports, and CI-facing test entrypoints.

## Requirements

### Requirement: Sparkle dependency pin

Production updates SHALL use Sparkle 2.10.0 exactly as pinned in `Package.swift`, with feed URL and EdDSA policy enforced in `UpdatePolicy`.

#### Scenario: Development updates disabled

- **WHEN** the running identity is development or updates fail policy validation
- **THEN** `UpdateController` SHALL not offer unsigned or misconfigured update feeds

### Requirement: Selftest gate

`Pookie --selftest` SHALL run `Diagnostics.runSelfTest()` covering layout, envelope, motion, perching, speech, intents, control socket, and cohort cases, exiting non-zero on failure.

#### Scenario: Make selftest

- **WHEN** the developer runs `make selftest`
- **THEN** the Makefile SHALL build the binary and invoke `--selftest` as the acceptance gate for behaviour changes

### Requirement: Pose and review PNG exports

The binary SHALL support `--render-png`, `--render-species`, `--render-patterns`, and `--render-brawl` to regenerate art review sheets under `shots/`.

#### Scenario: Make poses target

- **WHEN** the developer runs `make poses`
- **THEN** all four render flags SHALL execute to refresh pose, species, pattern, and brawl sheets

### Requirement: Swift and script tests in CI

CI on macOS SHALL run `make test`, which includes selftest, `swift test`, and release script syntax tests, as defined in `.github/workflows/ci.yml`.

#### Scenario: Pull request checks workflow

- **WHEN** a pull request triggers the Checks workflow
- **THEN** the runner SHALL execute `make test` and `make verify-dev` on arm64 macOS
