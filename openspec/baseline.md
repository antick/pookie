# Existing-product baseline

## Provenance

Created from freshly fetched `origin/main` at
`fff0092a8df42e4437b45892dae45ca2d4752943` on 2026-10-30.
The adoption branch was created directly from that revision.
This is a source-inspected baseline of core contracts. References to tests mean
existing coverage was identified, not that every GUI workflow passed in this
adoption. See the pull request validation report for commands actually run.

## Coverage

| Existing area | Baseline spec | Remaining depth to audit |
| --- | --- | --- |
| Accessory app lifecycle, lock pause, legacy say bridge | app-shell | Distributed notification edge cases across channels |
| Non-key windows, mouse modes, occlusion, bubble window | window-shell | Screen-share hide and fullscreen float acceptance on notarized builds |
| PetRenderer contract, stage envelope, floor line, facing | pet-renderer | Second renderer implementation (SpriteKit or layer-backed) when it ships |
| Twenty-two species, coats, patterns, collection rules | species-roster | Every marking combination in art review exports |
| Motion, drag, rest ladder, transient channels, overrides | pet-motion | Every species gait nuance and brawl edge timing |
| Window scan, perch, ride, jump, teleport | window-perching | Fullscreen geometry heuristic in TODO.md |
| Speech rate limits, bubble styles, streaming verbs | speech-bubbles | Live producer flood under many concurrent clients |
| Envelope, dedupe, TTL, preemption, verbs and events | intent-protocol | Full wire spawn/despawn with petId, kind and at |
| Unix/TCP control, hello, CLI and legacy flags | control-plane | `pookie env` status subcommand (not implemented) |
| Desk cap, draw budget, spokespet, spawn stubs | pet-cohort | Wire-accurate spawn/despawn and skill-pack menu hooks |
| Settings, menu bar, hotkeys, login item | settings-menu | Manual hotkey verification on production bundle |
| Sparkle policy, selftest, PNG exports, CI entrypoints | updates-diagnostics | Hosted release acceptance beyond policy unit tests |
| MCP server | No dedicated baseline yet | Entire M4 surface |
| LLM brain | No dedicated baseline yet | Entire M5 surface |
| Voice and push-to-talk | No dedicated baseline yet | Entire M6 surface |
| Reactive skill packs | No dedicated baseline yet | Entire M7 surface |

Every shipped product area discovered at initial adoption has a baseline entry or
an explicit "no dedicated baseline yet" row. Detailed architecture and the wire
draft remain in place and are indexed in [source-inventory.md](source-inventory.md).
Being indexed is not equivalent to being fully specified or behaviorally verified.

## Known documentation conflicts

- `docs/ROADMAP.md` describes milestones M4 through M7 and partial M1/M3 criteria.
  Baseline specs intentionally omit those until code lands. Do not treat roadmap
  acceptance criteria as current requirements.
- `docs/PROTOCOL.md` documents full spawn/despawn semantics while the cohort
  implements simplified helpers. The intent-protocol and pet-cohort specs record
  the simplified behavior as current.
- `TODO.md` lists manual GUI checks (throw feel, screen share, physical hotkeys).
  Selftest and Swift tests do not replace those; do not infer they passed from specs.

The adoption does not rewrite historical documents wholesale. When changing an
affected area, reconcile live docs with verified code and update the spec and this
gap record together.

## Completing and maintaining the baseline

For each row above, expand the named depth into observable requirements and
WHEN/THEN scenarios. Attach implementation and test references in
source-inventory.md. Add missing selftest or Swift coverage before claiming an
area is fully audited. Keep proposed improvements in `changes/`, separate from
what the current system actually does.
