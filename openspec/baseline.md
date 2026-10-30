# Existing-product baseline

This baseline records how Pookie behaves today, as implemented in the Swift tree and documented in `docs/PROTOCOL.md`. It is not a roadmap.

## Method

1. Read `AGENTS.md`, `README.md`, `docs/DESIGN.md`, and `docs/PROTOCOL.md` for vocabulary and invariants.
2. Walk `Sources/Pookie/` and `Tests/PookieTests/` to confirm each requirement against code.
3. Split behaviour into capability specs under `openspec/specs/` (one folder per product area).
4. Record traceability in `source-inventory.md`.
5. Validate with `npm run specs` (`openspec validate --all --strict --no-interactive`).

## Out of scope for this baseline

- MCP server (M4), LLM brain (M5), voice and push-to-talk (M6), reactive skill packs (M7)
- Layer-backed or SpriteKit second renderer (M1 criterion still open)
- Full wire semantics for `spawn` / `despawn` with `petId`, `kind`, and `at` (partial stubs only)
- `pookie env` status subcommand (not implemented)
- `bubbleClicked` events (bubble is click-through by design)

## Maintenance

When a change ships, archive its OpenSpec change so deltas merge into the matching `specs/<capability>/spec.md`. Keep baseline prose aligned with code; do not copy roadmap language into specs.
