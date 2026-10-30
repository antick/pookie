# species-roster Specification

## Purpose

Define the menagerie table: species traits, coats and patterns, saved collection entries, and the one-of-each-kind rule on the desk.

## Requirements

### Requirement: Species as shared skeleton

Each animal SHALL share the same motion and posture skeleton; species differences SHALL be expressed only through `SpeciesTraits` proportions and appendage shapes.

#### Scenario: Species count

- **WHEN** the app enumerates `PetSpecies.allCases`
- **THEN** exactly twenty-two species SHALL be available for roster configuration

### Requirement: One of each kind on desk

The cohort SHALL refuse to place a second pet of the same species on the desk at the same time; saved rosters SHALL be repaired on load if duplicates appear.

#### Scenario: Add duplicate species from menu

- **WHEN** the user attempts to add a species already represented on the desk
- **THEN** the operation SHALL be rejected without corrupting the saved collection

### Requirement: Coat and pattern axes

Name, species, coat (`CatSkin`), and marking pattern SHALL be independent configuration fields persisted per `PookieConfig` entry.

#### Scenario: Pattern overlay

- **WHEN** a pet is drawn with a non-default pattern
- **THEN** the pattern SHALL overlay the chosen coat without changing species gait or skeleton logic

### Requirement: PNG species review export

The binary SHALL support `--render-species` to write a species comparison sheet for art review, exiting without starting the GUI.

#### Scenario: Make poses species sheet

- **WHEN** `make poses` runs
- **THEN** it SHALL invoke `--render-species` to refresh `shots/species.png`
