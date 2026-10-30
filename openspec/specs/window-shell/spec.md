# window-shell Specification

## Purpose

Define transparent always-on-top pet and bubble windows, focus behaviour, mouse interaction modes, and frame-tier power management.

## Requirements

### Requirement: Non-key pet window

The pet window SHALL never become key or main; typing in other applications SHALL not be interrupted when the cursor is over the pet.

#### Scenario: Key window rejection

- **WHEN** the user clicks on the pet
- **THEN** `canBecomeKey` and `canBecomeMain` SHALL remain false for the pet window class

### Requirement: Click-through mouse modes

The shell SHALL support cycling mouse modes (silhouette capture, solid capture, passthrough) via the documented global hotkey without Accessibility permission.

#### Scenario: Silhouette mode

- **WHEN** silhouette click-through mode is active
- **THEN** hit testing SHALL use the rasterized alpha mask so transparent pixels pass clicks to applications beneath

### Requirement: Occlusion-aware frame tiers

The shell SHALL reduce animation work when the pet window is fully occluded and SHALL restore tier when visible again, using hysteresis to avoid flapping.

#### Scenario: Fully occluded idle pet

- **WHEN** the pet window is completely covered by other windows
- **THEN** the frame tier SHALL drop so idle CPU cost approaches zero until visibility returns

### Requirement: Bubble window separation

Speech bubbles SHALL render in a separate window from the pet body, positioned relative to the pet, and SHALL remain click-through so `bubbleClicked` is not emitted.

#### Scenario: Say with bubble visible

- **WHEN** an intent or menu action shows a speech bubble
- **THEN** the bubble window SHALL not steal keyboard focus from the user's active application
