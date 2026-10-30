# pet-renderer Specification

## Purpose

Define the procedural pet drawing contract: design-space geometry, facing flip, art envelope, and the single Core Graphics renderer behind `PetRenderer`.

## Requirements

### Requirement: PetRenderer protocol boundary

All drawing for a pet on screen SHALL go through the `PetRenderer` protocol so the shell does not depend on a specific graphics engine.

#### Scenario: CatRenderer implementation

- **WHEN** the app runs its default configuration
- **THEN** `CatRenderer` SHALL be the active `PetRenderer` implementation using Core Graphics

### Requirement: Art envelope inside stage

Every accepted pose and shape blend SHALL rasterize inside `CatGeometry.stage`; geometry outside the stage SHALL fail selftest rather than clip silently at the window edge.

#### Scenario: Selftest envelope sweep

- **WHEN** `Pookie --selftest` runs the art envelope section
- **THEN** all species and shape keyframes SHALL fit inside the stage bounds at every supported scale

### Requirement: Floor line and ground inset

The renderer SHALL align feet to `PetMotion.origin`, and window placement SHALL use `CatGeometry.groundInset` so leaning paws are not clipped below the floor line.

#### Scenario: Ground inset at multiple scales

- **WHEN** selftest checks floor line versus ink extents at small, medium, large, and huge scales
- **THEN** the lowest drawn ink SHALL remain above the clipped window bottom given the configured ground inset

### Requirement: Design-space facing

The cat SHALL be drawn in design space with a horizontal facing flip for left versus right, and gaze or cursor mapping SHALL convert screen coordinates into design space before aiming eyes.

#### Scenario: Cursor watch while facing left

- **WHEN** the pet faces left and watches the cursor
- **THEN** eye aim SHALL use the same design-space conversion as when facing right so the pet looks toward the pointer
