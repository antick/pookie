# OpenSpec in Pookie

This directory holds the spec-driven workflow for Pookie: baseline product specs, active change folders, and archive history.

## Layout

- `config.yaml` project context and rules for proposals and specs
- `baseline.md` how the existing-product baseline was captured
- `source-inventory.md` maps each capability to Swift sources and docs
- `specs/<capability>/spec.md` normative behaviour for one product area
- `changes/` in-flight change proposals (empty until the next change)
- `changes/archive/` completed changes after archive

## Commands

From the repository root:

```bash
npm run specs        # validate all specs (strict, non-interactive)
npm run specs:check  # same as specs (CI-friendly alias)
```

Requires Node.js and `npm ci` so `@fission-ai/openspec` 1.14.1 is available.

## Workflow

1. Explore the area with the openspec-explore skill or `/opsx-explore` where configured.
2. Propose a change with openspec-propose; artifacts land under `openspec/changes/<id>/`.
3. Apply with openspec-apply-change; keep `make selftest` green.
4. Sync spec deltas with openspec-sync-specs, then archive with openspec-archive-change.

Skills live under `.agents/skills/`, `.claude/skills/`, `.cursor/skills/`, and `.dsh/skills/`.

## Baseline scope

Baseline specs describe **shipped** behaviour only. Items in `TODO.md` and future milestones in `docs/ROADMAP.md` are not requirements until they land in code.
