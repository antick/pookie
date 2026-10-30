# Source inventory

Traceability from baseline capabilities to repository sources. Counts are approximate; use paths to verify behaviour.

## Application and identity

| Capability | Primary sources | Supporting docs |
| --- | --- | --- |
| `app-shell` | `Sources/Pookie/main.swift`, `AppDelegate.swift`, `AppDelegate+Actions.swift`, `AppDelegate+Release.swift`, `AppDelegate+Intents.swift` | `docs/DESIGN.md`, `docs/MACOS-CONSTRAINTS.md` |
| `window-shell` | `PetWindow.swift`, `PetWindowController.swift`, `PetView.swift`, `BubbleWindow.swift`, `AppConfig.swift` | `docs/MACOS-CONSTRAINTS.md` |
| `settings-menu` | `SettingsWindow.swift`, `AppDelegate+Menu.swift`, `AppDelegate+PetMenu.swift`, `GlobalHotKey.swift` | `README.md` (hotkeys) |

## Rendering and appearance

| Capability | Primary sources | Supporting docs |
| --- | --- | --- |
| `pet-renderer` | `PetRenderer.swift`, `CatRenderer.swift`, `CatAnatomy.swift`, `PetPose.swift` | `README.md` (pose sheet) |
| `species-roster` | `Species.swift`, `AppConfig.swift` (`PookieConfig`, coats, patterns) | `README.md` (species sheet) |

## Behaviour

| Capability | Primary sources | Supporting docs |
| --- | --- | --- |
| `pet-motion` | `PetMotion.swift`, `PetPose.swift`, `ActionStack.swift` | `docs/DESIGN.md` § behaviour |
| `window-perching` | `WindowScanner.swift`, `PetMotion.swift` (platforms, jump, ride) | `docs/ROADMAP.md` M0 notes |
| `speech-bubbles` | `Speech.swift`, `BubbleWindow.swift`, `PetWindowController.swift` | `docs/PROTOCOL.md` § say / bubble |

## Control plane and cohort

| Capability | Primary sources | Supporting docs |
| --- | --- | --- |
| `intent-protocol` | `Protocol.swift`, `IntentMapping.swift`, `ActionStack.swift` | `docs/PROTOCOL.md` |
| `control-plane` | `ControlServer.swift`, `ControlConnection.swift`, `ControlClient.swift`, `CLI.swift`, `main.swift` | `docs/PROTOCOL.md` § transport |
| `pet-cohort` | `PetCohort.swift`, `AppDelegate+PetMenu.swift` | `AGENTS.md` (cohort cap, one-of-kind) |

## Updates and verification

| Capability | Primary sources | Supporting docs |
| --- | --- | --- |
| `updates-diagnostics` | `UpdateController.swift`, `Diagnostics.swift`, `Makefile`, `Tests/PookieTests/*` | `docs/releasing.md`, `Package.swift` (Sparkle pin) |

## Tests and headless checks

- `Diagnostics.runSelfTest()` in `Diagnostics.swift` drives `Pookie --selftest` (`Makefile` target `selftest`).
- Swift unit tests under `Tests/PookieTests/` cover identity, update policy, control socket lifecycle, and bundled defaults.
- Release script tests under `scripts/release/` are packaging policy, not pet behaviour; they are out of baseline specs except where Sparkle policy is cited in `updates-diagnostics`.
