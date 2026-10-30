# speech-bubbles Specification

## Purpose

Define rate-limited speech, producer budgets, bubble styles, streaming append, and silence-by-default behaviour.

## Requirements

### Requirement: Silence by default

With no connected producers and no explicit say intents, pets SHALL remain silent; unprompted lines SHALL respect quiet mode and chatty settings.

#### Scenario: Quiet mode enabled

- **WHEN** quiet mode is on in settings
- **THEN** unprompted speech lines SHALL be suppressed while explicit producer says may still flow within budgets

### Requirement: One bubble at a time

The speech engine SHALL allow at most one active bubble per pet path, coalescing or dropping excess producer traffic according to configured limits.

#### Scenario: Producer rate limit

- **WHEN** a producer exceeds the per-producer budget enforced in `SpeechEngine`
- **THEN** new say intents SHALL receive `rate_limited` or equivalent drop handling at the intent router

### Requirement: Bubble styles and TTL

Say intents SHALL support plain, info, warning, success, and code styles, with time-to-live derived from text length so bubbles dismiss without manual close.

#### Scenario: Selftest speech layout

- **WHEN** selftest validates bubble layout metrics
- **THEN** rendered bubble geometry SHALL fit within the envelope tested in `Diagnostics.swift`

### Requirement: Streaming bubble verbs

Wire verbs `bubble.show`, `bubble.append`, and `bubble.hide` SHALL map to shell bubble windows, using `text` in append args as implemented in the intent performer.

#### Scenario: Append with final flag

- **WHEN** a producer sends `bubble.append` with `final` true
- **THEN** the shell SHALL treat the append as completing the streaming utterance and apply TTL dismissal
