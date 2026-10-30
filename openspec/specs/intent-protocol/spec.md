# intent-protocol Specification

## Purpose

Define the intent envelope, verb vocabulary, dedupe and TTL rules, priority preemption, mapping from args to actions, and acknowledgement error codes.

## Requirements

### Requirement: Envelope fields

Every intent SHALL include string `id`, integer epoch-millis `ts`, string `verb`, and object `args`; optional `priority`, `ttl`, and `pet` SHALL follow `docs/PROTOCOL.md`.

#### Scenario: Router malformed JSON

- **WHEN** a line is not valid JSON
- **THEN** the router SHALL respond with `malformed_json` and SHALL NOT mutate pet state

### Requirement: Dedupe and expiry

Duplicate `id` values SHALL be acknowledged and dropped; intents past `ttl` SHALL be dropped at receive and again before execution starts.

#### Scenario: Selftest intent router

- **WHEN** selftest feeds duplicate ids and expired ttl samples
- **THEN** outcomes SHALL match the headless expectations in `Diagnostics.swift`

### Requirement: Priority preemption stack

`ActionStack` SHALL implement strict higher-priority preemption, equal-priority queueing, locomotion lock during say, and drag clearing per protocol section 5.

#### Scenario: Selftest preemption section

- **WHEN** selftest runs the preemption stack cases
- **THEN** queued, started, and dropped actions SHALL match the configured priority table in `IntentVerb.defaults`

### Requirement: Implemented verb set

The router SHALL accept the verbs implemented in `Protocol.swift`, including say, emote, moveTo, lookAt, face, state, hide, show, bubble verbs, pet.on, spawn, and despawn, with spawn and despawn using simplified cohort helpers rather than full wire petId semantics.

#### Scenario: Unknown verb

- **WHEN** a producer sends an unrecognized verb string
- **THEN** the router SHALL return `unknown_verb` without changing pose state

### Requirement: Event vocabulary

Subscriptions via `pet.on` SHALL emit clicked, dragged, dropped, and petted events on the connection; bubbleClicked SHALL NOT be emitted because bubbles are click-through.

#### Scenario: Drag coalescing

- **WHEN** the user drags a pet while events are subscribed
- **THEN** dragged events SHALL coalesce near ten hertz as documented in `docs/PROTOCOL.md`
