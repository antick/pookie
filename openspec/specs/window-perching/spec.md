# window-perching Specification

## Purpose

Define permission-free window-edge detection, perching, riding dragged windows, and self-jump onto eligible platform windows.

## Requirements

### Requirement: Geometry-only window scan

Window discovery SHALL use `CGWindowListCopyWindowInfo` metadata without Screen Recording or Accessibility, filtering to on-screen layer-zero windows suitable as platforms.

#### Scenario: Windows listing mode

- **WHEN** the user runs `Pookie --windows`
- **THEN** the process SHALL print candidate platform windows and exit without starting the pet GUI

### Requirement: Perch and ride behaviour

When perching is enabled, pets SHALL align to detected top edges, remain attached while the platform window moves, and respect `--no-perch` for a single run.

#### Scenario: Perch disabled flag

- **WHEN** `Pookie --no-perch` is passed at launch
- **THEN** the pet SHALL not attach to foreign window edges during that session

### Requirement: Self-jump onto platforms

When jump is enabled, pets SHALL attempt reachable jumps onto eligible windows using fit and reach rules in `PetMotion`, and SHALL honour `--no-jump` for a single run.

#### Scenario: Selftest jump section

- **WHEN** selftest exercises self-jump logic headlessly
- **THEN** jump success and failure cases SHALL match the geometry rules without manual window server interaction

### Requirement: Multi-display seams

Pets SHALL handle movement and teleport across displays using configured teleport cadence, honouring `--no-teleport` for a single run.

#### Scenario: Teleport disabled flag

- **WHEN** `Pookie --no-teleport` is passed at launch
- **THEN** display poof teleport SHALL not occur during that session
