# pet-motion Specification

## Purpose

Define unprompted and intent-driven motion: locomotion, drag and fling physics, rest ladder postures, transient pose channels, and social play between desk pets.

## Requirements

### Requirement: Pure behaviour layer

`PetMotion`, `PetPose`, and related schedulers SHALL NOT import AppKit and SHALL be drivable headlessly from selftest.

#### Scenario: Selftest motion section

- **WHEN** `Pookie --selftest` runs motion checks
- **THEN** physics, wander, and rest transitions SHALL be evaluated without creating an on-screen window

### Requirement: Transient pose channel clearing

Channels such as punch, kick, groom, spin, and impact SHALL be cleared at the top of each pose update so finished actions do not persist visually.

#### Scenario: After brawl ends

- **WHEN** a scuffle or play interaction completes
- **THEN** transient channels SHALL return to zero on subsequent idle frames

### Requirement: Drag preemption priority

User drag SHALL preempt lower-priority actions using the action stack priority 100 contract documented in `ActionStack.swift`.

#### Scenario: Drag during wander

- **WHEN** the user presses and drags the pet during an unprompted wander
- **THEN** drag handling SHALL take precedence until release

### Requirement: Rest ladder blending

Resting shapes (stand, sit, loaf, lie, curl, stretch) SHALL blend through continuous shape weights rather than hard cuts, including mid-settle retargeting without pops.

#### Scenario: Selftest settling continuity

- **WHEN** selftest retargets mid-settle between rest shapes
- **THEN** shape weights SHALL remain continuous across the transition samples

### Requirement: Launch motion overrides

Launch flags `--no-wander`, `--no-perch`, `--no-jump`, and `--no-teleport` SHALL override behaviour for one run without persisting to settings when combined with the persistsChanges guard in `main.swift`.

#### Scenario: No wander measurement run

- **WHEN** the user starts `Pookie --no-wander`
- **THEN** wandering SHALL be disabled for that process only unless settings persistence is explicitly enabled for that launch
