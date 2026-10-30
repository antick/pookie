# OpenSpec in Pookie

OpenSpec is the default workflow for planning and implementing product changes.
The pinned CLI and generated agent skills are committed with the project.

## Start here

```bash
npm ci
OPENSPEC_TELEMETRY=0 npx openspec list --specs
npm run specs:check
```

Skills are generated for Codex (`.agents/skills`, also the shared location other
agents read), Claude Code (`.claude/skills`), DeepSeek Harness (`.dsh/skills`),
and Cursor (`.cursor/skills`). Codex invokes them as `$openspec-propose`; the
others use `/openspec-propose`.

Use `$openspec-explore` to investigate, `$openspec-propose` to create a
proposal, design, spec deltas and tasks, and `$openspec-apply-change` to implement an
authorized change. Use `$openspec-update-change` when the plan changes,
`$openspec-sync-specs` to reconcile accepted deltas into current specs, and
`$openspec-archive-change` when the work and verification are complete. Repo-local skills
are available on the next turn after the client discovers them; reopen the session
if the client has not refreshed its skill list.

The CLI is local. For an agent shell that expects the bare `openspec` command,
use `npm run specs:check` for strict validation or
`OPENSPEC_TELEMETRY=0 npx openspec <arguments>` for other subcommands.
Refresh every installed tool's skills after an intentional dependency upgrade with:

```bash
OPENSPEC_TELEMETRY=0 npx openspec update
```

Add another tool with the initializer, keeping the existing list:

```bash
OPENSPEC_TELEMETRY=0 npx openspec init --no-animation --no-copilot-cloud \
  --tools codex,claude,dsh,cursor,<new-tool>
```

Do not hand-edit generated skills to encode Pookie policy. Put project constraints
in `config.yaml` and `AGENTS.md`. The per-tool copies differ only in how they name
the next command, so regenerate them rather than editing one. No global CLI
installation is required.

## Existing behavior and future changes

- `specs/<capability>/spec.md` describes current behavioral contracts.
- `changes/<name>/` holds proposed changes and their implementation tasks.
- `changes/archive/` retains completed changes after accepted deltas are synced.
- [baseline.md](baseline.md) records provenance, coverage and known gaps.
- [source-inventory.md](source-inventory.md) preserves discoverability of existing
  docs, sources and behavior tests at the adoption commit.

The initial specs cover core invariants and representative workflows. They are
not an exhaustive translation of every implemented feature. The inventory retains
links to the detailed material so a future agent can find it before planning.

For each affected capability, read its spec and referenced source/tests first.
If behavior is missing, inspect the implementation and `Pookie --selftest`,
add a current-behavior requirement with scenarios and evidence, then describe the
requested delta separately. Do not implement old plans merely because they appear
in the inventory. Record contradictions and uncertainty instead of guessing.

For a deliberate full backfill, work through every inventory area: enumerate its
user-visible actions and wire contracts, map each to requirements and scenarios,
compare with code and selftest, and record unresolved gaps. An area is fully
audited only after that review. Keep inventory and evidence links current as
capabilities are added or removed.

Before finishing a change, run `npm run specs:check` and the applicable repository
checks (`make selftest`, `make test` on macOS), update the changelog, sync the
accepted specs and archive the change. Spec validation checks document structure;
selftest and Swift tests establish implementation coverage. Neither a valid spec
nor a checked task proves every GUI workflow works without the manual checks in TODO.md.
