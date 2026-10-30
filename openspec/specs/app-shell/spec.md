# app-shell Specification

## Purpose

Define how the Pookie macOS application starts, runs as a non-activating accessory, and bridges external say requests without blocking the behaviour layer.

## Requirements

### Requirement: Accessory application lifecycle

The application SHALL run with activation policy `.accessory` so the pet never becomes the foreground app in the Dock or menu bar.

#### Scenario: Launch without arguments

- **WHEN** the user launches `Pookie` with no arguments on a graphical session
- **THEN** the app delegate SHALL start the pet cohort, status item, control server, and global hotkeys without requiring Screen Recording, Accessibility, or Input Monitoring permissions

#### Scenario: Headless modes before AppKit session

- **WHEN** the process is invoked with headless flags such as `--selftest`, render export flags, or `--help`
- **THEN** those modes SHALL run and exit without requiring a pet window on screen

### Requirement: Screen lock and sleep pause

The shell SHALL pause colony simulation when the session sleeps or the screen locks, and resume when the session is active again.

#### Scenario: Simulated lock for tests

- **WHEN** `Pookie --simulate-lock on` is passed
- **THEN** the app SHALL post the same distributed notification path used to verify pause behaviour

### Requirement: Distributed notification say bridge

When the Unix control socket is unavailable, the shell SHALL still accept a legacy say path via distributed notification so scripts can drive speech.

#### Scenario: Flag-style say from another process

- **WHEN** a running pet receives `Pookie --say "text"` from a separate process and the control client cannot connect
- **THEN** the shell SHALL fall back to the distributed notification bridge documented in `main.swift`
