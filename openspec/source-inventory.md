# Baseline source inventory

Inventory at `fff0092a8df42e4437b45892dae45ca2d4752943`. Links are discovery
aids, not claims of complete spec coverage or successful test execution.
Read [baseline.md](baseline.md) for conflicts and gaps. Wire contracts also
live in [docs/PROTOCOL.md](../docs/PROTOCOL.md).

Maintain this index when adding or moving relevant sources. Keep historical
plans distinguishable from implementation evidence.

## Product and agent guidance

- [README.md](../README.md)
- [AGENTS.md](../AGENTS.md)
- [CHANGELOG.md](../CHANGELOG.md)
- [TODO.md](../TODO.md) (open work only, not baseline requirements)
- [docs/ROADMAP.md](../docs/ROADMAP.md) (milestone context, not baseline requirements)

## Architecture and constraints

- [docs/DESIGN.md](../docs/DESIGN.md)
- [docs/MACOS-CONSTRAINTS.md](../docs/MACOS-CONSTRAINTS.md)
- [docs/PROTOCOL.md](../docs/PROTOCOL.md)
- [docs/releasing.md](../docs/releasing.md)
- [Package.swift](../Package.swift) (Sparkle pin)

## Application shell and settings

- [Sources/Pookie/main.swift](../Sources/Pookie/main.swift) (launch flags, headless modes)
- [Sources/Pookie/AppDelegate.swift](../Sources/Pookie/AppDelegate.swift)
- [Sources/Pookie/AppDelegate+Actions.swift](../Sources/Pookie/AppDelegate+Actions.swift)
- [Sources/Pookie/AppDelegate+Release.swift](../Sources/Pookie/AppDelegate+Release.swift)
- [Sources/Pookie/AppDelegate+Intents.swift](../Sources/Pookie/AppDelegate+Intents.swift)
- [Sources/Pookie/AppDelegate+Menu.swift](../Sources/Pookie/AppDelegate+Menu.swift)
- [Sources/Pookie/AppDelegate+PetMenu.swift](../Sources/Pookie/AppDelegate+PetMenu.swift)
- [Sources/Pookie/SettingsWindow.swift](../Sources/Pookie/SettingsWindow.swift)
- [Sources/Pookie/GlobalHotKey.swift](../Sources/Pookie/GlobalHotKey.swift)
- [Sources/Pookie/AppConfig.swift](../Sources/Pookie/AppConfig.swift)
- [Sources/Pookie/AppIdentity.swift](../Sources/Pookie/AppIdentity.swift)

Baseline spec: [app-shell/spec.md](specs/app-shell/spec.md), [settings-menu/spec.md](specs/settings-menu/spec.md)

## Window shell and rendering

- [Sources/Pookie/PetWindow.swift](../Sources/Pookie/PetWindow.swift)
- [Sources/Pookie/PetWindowController.swift](../Sources/Pookie/PetWindowController.swift)
- [Sources/Pookie/PetView.swift](../Sources/Pookie/PetView.swift)
- [Sources/Pookie/BubbleWindow.swift](../Sources/Pookie/BubbleWindow.swift)
- [Sources/Pookie/PetRenderer.swift](../Sources/Pookie/PetRenderer.swift)
- [Sources/Pookie/CatRenderer.swift](../Sources/Pookie/CatRenderer.swift)
- [Sources/Pookie/CatAnatomy.swift](../Sources/Pookie/CatAnatomy.swift)
- [Sources/Pookie/PetPose.swift](../Sources/Pookie/PetPose.swift)

Baseline spec: [window-shell/spec.md](specs/window-shell/spec.md), [pet-renderer/spec.md](specs/pet-renderer/spec.md)

## Species, cohort and appearance

- [Sources/Pookie/Species.swift](../Sources/Pookie/Species.swift)
- [Sources/Pookie/PetCohort.swift](../Sources/Pookie/PetCohort.swift)

Baseline spec: [species-roster/spec.md](specs/species-roster/spec.md), [pet-cohort/spec.md](specs/pet-cohort/spec.md)

## Motion, perching and speech

- [Sources/Pookie/PetMotion.swift](../Sources/Pookie/PetMotion.swift)
- [Sources/Pookie/ActionStack.swift](../Sources/Pookie/ActionStack.swift)
- [Sources/Pookie/WindowScanner.swift](../Sources/Pookie/WindowScanner.swift)
- [Sources/Pookie/Speech.swift](../Sources/Pookie/Speech.swift)

Baseline spec: [pet-motion/spec.md](specs/pet-motion/spec.md), [window-perching/spec.md](specs/window-perching/spec.md), [speech-bubbles/spec.md](specs/speech-bubbles/spec.md)

## Control plane and intents

- [Sources/Pookie/Protocol.swift](../Sources/Pookie/Protocol.swift)
- [Sources/Pookie/IntentMapping.swift](../Sources/Pookie/IntentMapping.swift)
- [Sources/Pookie/ControlServer.swift](../Sources/Pookie/ControlServer.swift)
- [Sources/Pookie/ControlConnection.swift](../Sources/Pookie/ControlConnection.swift)
- [Sources/Pookie/ControlClient.swift](../Sources/Pookie/ControlClient.swift)
- [Sources/Pookie/CLI.swift](../Sources/Pookie/CLI.swift)

Baseline spec: [intent-protocol/spec.md](specs/intent-protocol/spec.md), [control-plane/spec.md](specs/control-plane/spec.md)

## Updates and verification

- [Sources/Pookie/UpdateController.swift](../Sources/Pookie/UpdateController.swift)
- [Sources/Pookie/Diagnostics.swift](../Sources/Pookie/Diagnostics.swift) (`Pookie --selftest`)
- [Makefile](../Makefile) (`make selftest`, `make test`, `make poses`)
- [Tests/PookieTests/](../Tests/PookieTests/)
- [.github/workflows/ci.yml](../.github/workflows/ci.yml)

Baseline spec: [updates-diagnostics/spec.md](specs/updates-diagnostics/spec.md)

## Not indexed as baseline specs (unbuilt)

- MCP server (M4): no `Sources/` implementation
- LLM brain (M5): no out-of-process brain client
- Voice (M6): no whisper or TTS pipeline in tree
- Skill packs (M7): no loader in tree
