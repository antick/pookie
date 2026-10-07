# ADR-0002: The pet is a renderer — a small intent protocol, not per-integration features

- Status: Accepted
- Date: 2026-10-06
- Deciders: Lead
- Supersedes: none

## Context

A desktop pet is only interesting when it reacts to something. The obvious way to build that is
feature-per-integration: a Codex feature, a git feature, a calendar feature, a build feature. Each
one knows about the pet's internals, each one decides its own visuals, each one arrives with its own
polling loop.

That approach fails predictably:

- **Combinatorial behaviour.** N integrations that each know the pet's animation names produce N
  ways to conflict, and the pet has no single place to arbitrate. Two integrations both want to
  speak. Nobody owns the decision.
- **The pet target becomes a hub.** Every new integration touches the shell, so every new
  integration can crash the pet, leak memory into the render loop, or block the main thread.
- **Nothing is testable.** Verifying "the pet behaves well when Codex and CI both fire" requires
  running Codex and CI.
- **The pet is coupled to whatever is fashionable.** Codex today, something else in six months. The
  integration is permanent code for a temporary thing.
- **No third party can build on it.** An external tool has no way in except a fork.

We also observed that every integration, whatever it is, actually wants the same tiny set of
things: say something, show a feeling, move over here, look over there, change mode, show/hide a
bubble. The integrations differ in *when* they do it, not in *what the pet does*.

## Decision

**Pookie exposes a small, fixed intent vocabulary. Producers emit intents; the pet renders them.**

The pet has no knowledge of Codex, git, CI, calendars, or LLMs. It knows roughly twelve verbs:

`say`, `emote`, `moveTo`, `lookAt`, `face`, `state`, `bubble.show`, `bubble.hide`, `bubble.append`,
`spawn`, `despawn`, and the `pet.on(event)` subscription.

Each intent is a JSON envelope — `{id, ts, verb, args, priority, ttl}` — delivered over a local
transport. The pet emits events back: `clicked`, `dragged`, `dropped`, `petted`, `bubbleClicked`.
See `PROTOCOL.md`.

Architecture consequence: the intent router and behaviour engine are pure logic with no AppKit
dependency, and producers are always out-of-process clients.

## Why a verb vocabulary beats feature-per-integration

1. **Fixed surface, unbounded producers.** The pet ships once; integrations are added forever
   without touching it. Adding an integration cannot destabilise the shell, because it cannot link
   against it.
2. **One arbiter.** Priorities and TTLs live in one place. When Codex and CI both want to speak, the
   behaviour engine decides, once, with rules we wrote down. There is no negotiation between
   features.
3. **Producers describe intent, not rendering.** No producer can name an animation, pick a colour, or
   position a bubble. That is what keeps the pet coherent instead of becoming a collage of other
   people's design decisions.
4. **It is testable without the OS.** Feed a scripted intent stream into the router and engine,
   assert the resulting action/event stream. Behaviour regressions become unit tests, not video
   review.
5. **The vocabulary is small enough to hold in your head.** Twelve verbs is an afternoon's
   documentation, not an SDK. That is what makes third-party adoption realistic.
6. **It is the same protocol for everything.** A shell command, an MCP client, a CI job, and the LLM
   brain are all just clients. There is no privileged integration path.
7. **It gives the pet a future as a platform.** A documented protocol plus `pet.on(event)` is what
   makes third-party skill packs (M7) possible without shipping our own features.

## Consequences

**Positive**

- Any agent or app can drive the pet: Codex, Claude Code, a shell one-liner, CI, a calendar, a
  custom script, eventually an MCP client.
- Producers can be written in any language, because the boundary is JSON over a local socket, not a
  Swift API.
- The behaviour engine is the single place that enforces "not annoying": rate limits, attention
  budget, and preemption are protocol-level concerns, not per-integration politeness.
- Producer crashes are survivable by construction.

**Negative / accepted costs**

- **An abstraction tax on trivial integrations.** "Emit a JSON envelope with an id and a ttl" is more
  work than calling `pet.wave()`. Accepted: it is the price of a stable boundary.
- **Expressive ceiling.** If someone wants something the verbs cannot express, the answer is "add a
  verb to the protocol" — a versioned, deliberate change — not "just call into the pet".
- **We own serialization, versioning, and backpressure.** The router must handle malformed input,
  duplicate ids, expired TTLs, and floods.
- **Two hops instead of one.** A shell command must reach a running pet rather than just running.
  This is the reason M3 (the CLI control plane) is called out as the milestone that unlocks
  everything: until it exists, nothing is easy to drive.
- **Debugging spans a process boundary.** Mitigated by structured logging on both sides and by the
  protocol being trivially reproducible with a text-based client.

## Rejected alternatives

- **Feature-per-integration with a shared pet API.** Fastest to demo, guaranteed to rot. Rejected:
  conflicts have no owner and the pet target becomes the integration hub.
- **A large plugin API (Swift frameworks, dynamic loading).** Powerful, but it means third-party code
  runs inside the pet process and can kill it. Rejected on stability and on sandboxing grounds.
- **One mega-verb (`perform(action:)` with a stringly-typed payload).** Looks flexible, is actually
  undocumented. The vocabulary is the documentation.

## Revisit trigger

If a genuine class of producer need repeatedly fails to fit the twelve verbs across two or more
independent integrations, add verbs deliberately and version the protocol. Do **not** widen an
existing verb into a grab bag, and do **not** introduce a per-integration escape hatch.
