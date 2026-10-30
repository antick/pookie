# control-plane Specification

## Purpose

Define NDJSON transport over Unix domain socket and loopback TCP, hello handshake, CLI client verbs, and environment overrides for development versus production channels.

## Requirements

### Requirement: Unix socket primary transport

The control server SHALL listen on a mode-0600 Unix domain socket under the active identity's Application Support directory, serving one JSON object per line.

#### Scenario: Development socket path

- **WHEN** Pookie Dev runs unbundled or with the development identity
- **THEN** the default socket path SHALL live under `~/Library/Application Support/Pookie Dev/control.sock`

### Requirement: TCP fallback and port file

The server SHALL also accept loopback TCP connections on a port recorded beside the socket path, and clients MAY override paths with `POOKIE_CONTROL_SOCKET` and `POOKIE_CONTROL_PORT`.

#### Scenario: Selftest real socket

- **WHEN** selftest opens a temporary Unix socket through `ControlServer`
- **THEN** hello, say, and pet.on flows SHALL succeed without starting the menu bar app

### Requirement: Hello handshake

Optional hello lines SHALL receive `hello.ok` with protocol version and pet names; clients omitting hello SHALL receive intents only without event streaming assumptions.

#### Scenario: CLI hello before say

- **WHEN** `ControlClient` connects for `pookie say`
- **THEN** it SHALL perform the hello exchange documented in `docs/PROTOCOL.md` before sending intents

### Requirement: pookie CLI verbs

The `pookie` front command SHALL parse say, emote, move, face, state, hide, show, and events locally, emitting NDJSON lines compatible with `CLI.swift`.

#### Scenario: Make cli symlink

- **WHEN** the developer runs `make cli`
- **THEN** `build/pookie` SHALL symlink to the development binary for PATH-based control

### Requirement: Legacy Pookie flags

The `Pookie` binary SHALL continue to support flag-style driving (`--say`, `--producer`, render/selftest flags) alongside the `pookie` subcommand surface.

#### Scenario: Help text source of truth

- **WHEN** the user runs `Pookie --help`
- **THEN** listed flags SHALL match the parser paths in `main.swift`
