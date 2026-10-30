# settings-menu Specification

## Purpose

Define persisted user settings, the settings window, menu bar status item, pet context menus, global hotkeys, and launch-at-login for production builds.

## Requirements

### Requirement: Persisted settings store

User defaults SHALL persist roster entries, behaviour toggles, scale, opacity, teleport cadence, mouse mode, quiet and chatty flags, privacy screen-capture hide, and float-above-fullscreen preference via `AppConfig`.

#### Scenario: Launch flag non-persistence

- **WHEN** the user passes motion override flags such as `--no-wander` or `--scale`
- **THEN** `AppConfig.shared.persistsChanges` SHALL be false for that run so overrides do not rewrite saved settings

### Requirement: Settings window

The app SHALL provide a settings window with General, Behaviour, and Pookies tabs reachable from the menu and `--settings` launch flag.

#### Scenario: Open settings at launch

- **WHEN** `Pookie --settings` is passed
- **THEN** the settings window SHALL open during startup for automated review

### Requirement: Global hotkeys without Accessibility

Carbon global hotkeys SHALL toggle hide/show, cycle mouse mode, bring pets home, log state, test say, and mute reactions using the identity-specific shortcut prefix.

#### Scenario: Documented shortcut prefix

- **WHEN** the user reads `Pookie --help`
- **THEN** hotkey descriptions SHALL reflect `AppIdentity.current.shortcutPrefix` for production versus development

### Requirement: Launch at login production only

Login item registration via `SMAppService` SHALL be offered for the production bundle identity and SHALL be gated appropriately for development builds.

#### Scenario: Launch at login flag

- **WHEN** the user runs `Pookie --launch-at-login on` with the production bundle
- **THEN** the app SHALL register or unregister the login item according to the flag
