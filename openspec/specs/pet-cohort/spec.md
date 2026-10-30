# pet-cohort Specification

## Purpose

Define multi-pet desk limits, shared draw budget, colony play and scuffle scheduling, spokespet targeting, and simplified spawn helpers on the wire.

## Requirements

### Requirement: Desk cap

At most ten pets SHALL be on the desk simultaneously, enforced by `PetCohort.maximumPets`.

#### Scenario: Launch pets flag

- **WHEN** the user passes `--pets N` at launch
- **THEN** N SHALL be clamped to the maximum desk cap and spawn that many configured pets

### Requirement: Shared frame budget

The cohort SHALL allocate a shared draw budget across pets so ten pets do not cost ten times the frame work of one pet.

#### Scenario: Frame rate distribution

- **WHEN** multiple pets are animating on desk
- **THEN** `PetCohort` SHALL assign per-pet frame rates from measured draw costs under the shared budget

### Requirement: Spokespet default target

Intents without an explicit `pet` field SHALL target the cohort spokespet (`boss` index) while named pets remain addressable when configured.

#### Scenario: Primary say intent

- **WHEN** a producer sends say without `pet`
- **THEN** the spokespet SHALL perform the utterance

### Requirement: Wire spawn and despawn stubs

Wire verbs spawn and despawn SHALL map to cohort add-last and remove-last helpers and SHALL NOT yet implement full protocol petId, kind, and at placement semantics.

#### Scenario: Spawn intent on socket

- **WHEN** a client sends a spawn intent over the control socket
- **THEN** the cohort SHALL add a pet using the simplified spawn helper rather than parsing full spawn args from section 4.10 of the draft protocol
