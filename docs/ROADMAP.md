# Pookie — Roadmap

Milestones are ordered by **risk retired**, not by user-visible value. The parts that can invalidate
the design are built first, even when they are the least impressive.

Each milestone states a goal, acceptance criteria that can be checked without judgement calls, and
the risk it retires. A milestone is done when its acceptance criteria pass; there is no partial credit.

| Milestone | Theme | Risk retired |
|---|---|---|
| M0 | Transparent always-on-top window + placeholder pet | Can we even put a pet on a Mac desktop without ruining it? |
| M1 | Animation state machine + idle micro-behaviours | Does it feel alive? |
| M2 | Bubble + streaming `say` + preemption | Can it speak without being annoying? |
| M3 | Control plane (`pookie say "hi"`) | Can anything drive it? |
| M4 | MCP server | Can an agent drive it without custom glue? |
| M5 | LLM brain | Is it useful, not just charming? |
| M6 | Voice + global hotkey | Can it be used hands-free? |
| M7 | Reactive skill packs | Can other people extend it? |
| M8 | Multi-pet, settings, packaging | Can a stranger install it? |

---

## M0 — Walking skeleton: transparent, always-on-top, draggable

**Status: complete**, plus a fix pass after it. Three defects were found in use and closed with
tests: the art was being clipped at the window edge (tail and ears), a thrown cat fell at the idle
frame tier, and the hit-test mask cost 90 ms twice a second in a debug build. Two features also
landed ahead of their milestone because the shell was already there: **perching on other apps'
windows** (geometry-only, permission-free) and the **speech bubble** with `say` / `bubble.append` /
`bubble.hide`. Details and measurements: `M0-FINDINGS.md`.

### Goal

Prove the two things that can kill the product, with the least possible code around them: a
transparent, always-on-top window that **never steals focus**, and a window that behaves correctly
across Spaces, fullscreen apps, and multiple monitors. The cat itself is a procedural placeholder.

### Acceptance criteria

1. A borderless, transparent window shows a visible cat on the desktop with **no title bar and no
   chrome**.
2. The cat renders with `PetRenderer` as a protocol; the M0 implementation draws procedurally with
   Core Graphics. Swapping the implementation requires no change above the protocol.
3. **Typing is never interrupted.** With the pet visible and the cursor over it, typing in TextEdit
   or a terminal produces all characters in the right order, with no lost keystrokes and no window
   activation. Verified by hand, repeatedly, on a fresh boot.
4. The pet's window **can never become key or main**: `canBecomeKey` returns false and the Dock/Menu
   bar never reflects Pookie as the active app.
5. **Drag works**: press on the cat, the cat follows the cursor with visible lag, release, the cat
   stays where it was dropped. No fling physics required in M0.
6. **Spaces**: the pet is visible on every Space, including after switching with the keyboard. It does
   not disappear when a fullscreen app is focused.
7. **Click-through behaviour is measured and documented.** Both approaches — `ignoresMouseEvents` and
   per-pixel `hitTest` returning `nil` — are tested for whether a click actually reaches the app
   underneath. The result is written down in `MACOS-CONSTRAINTS.md`; if `hitTest` does not forward,
   the fallback design is chosen.
8. **Idle cost is under ~1% CPU** with the pet visible and idle, and drops to effectively zero when
   the window is fully occluded.
9. A global **hide/show hotkey** works with no Accessibility permission prompt.
10. The app builds and runs from `Package.swift` with no third-party runtime dependencies.

### Risk retired

That the platform refuses to cooperate: focus stealing, alpha compositing, window level, Spaces, and
occlusion are the failure modes that no amount of animation polish can fix. If M0 cannot make a
non-focus-stealing always-on-top window, the product does not exist and we should know now in days
rather than months.

### Explicitly not in M0

Animation state machine, walk cycle, physics, bubble, protocol server, CLI, MCP, brain, voice. The
cat blinks and breathes and that is all.

---

## M1 — Animation state machine and idle micro-behaviours

**Status: partially landed.** Criterion 2 (legal, documented animation states with an explicit
preemption order) is in for postures: four resting shapes she blends between rather than cuts to, and
a rest ladder — loaf after a long perch, sit before sleep, lie asleep, stretch and yawn on waking or
after a long idle — with `--selftest` proving the blend is continuous and that retargeting mid-settle
cannot pop. Criteria 4, 5 and 6 (spring locomotion, gravity and restitution, frame tiers with
hysteresis) landed in M0's fix pass. Outstanding: the SpriteKit renderer behind `PetRenderer`
(criterion 1), cached geometry, and the few micro-behaviours not yet on a jittered scheduler.

### Goal

Make it feel alive when nothing is happening. Replace the procedural placeholder with a SpriteKit
renderer behind the existing `PetRenderer` protocol, and put a real state machine and physics layer
under it.

### Acceptance criteria

1. `PetRenderer` has a second implementation (SpriteKit) and the shell can run either one without
   changes above the protocol.
2. An animation state machine with explicit states (`idle`, `walk`, `sit`, `sleep`, `drag`, `fall`)
   and documented legal transitions. Illegal transitions are rejected and logged, not silently
   allowed.
3. **Idle micro-behaviours** run on a jittered scheduler: blink (2–6 s), breathing, tail sway, look-at-cursor
   (only when idle and the cursor is near), and wander (every 20–60 s within the edge band).
   Pose-changing behaviours never overlap each other.
4. **Walking uses waypoint + spring**: the pet eases in at the target, facing flips on velocity sign,
   and the walk cycle is driven by distance travelled so it never moonwalks.
5. **Drag and fling use gravity + restitution**: a thrown pet falls, bounces, loses energy, settles,
   and returns to `idle`. It never leaves the visible screen area and never jitters indefinitely.
6. CPU while idle and visible stays under ~1%; frame tiers (idle vs active) are in place with
   hysteresis so there is no fps oscillation.
7. Behaviour state transitions are covered by unit tests with no AppKit dependency in the test path.

### Risk retired

That it is a static sticker. Aliveness is the product's core value, and it is entirely a behaviour
problem, not an art problem.

---

## M2 — Bubble window, streaming `say`, and preemption

**Status: criteria 1, 2 and half of 3 have landed** (bubble window, `say`, `bubble.append`,
`bubble.hide`, length-derived TTL, one bubble at a time, minimum gap, mute, plus the `Pookie --say`
bridge). Criteria 3 (wire streaming), 4 (preemption stack), 5 (TTL at dispatch), 6 (per-producer
attention budget) and 7 (log reasons) are outstanding — they need M3's transport to be meaningful.

### Goal

Let the pet talk — and more importantly, let it talk *politely*. This milestone builds the bubble
window and the priority/preemption machinery that keeps speech from being annoying.

### Acceptance criteria

1. A separate borderless, transparent, **non-key** bubble window renders text anchored to the pet,
   follows the pet, and repositions correctly near screen edges (flips side rather than clipping).
2. `say` produces a bubble that auto-dismisses on a length-derived timer.
3. **Streaming works**: `say` with `stream: true` opens a bubble, `bubble.append` adds deltas, and a
   `final` append closes the stream and starts the dismiss timer. Rendering a token-by-token stream
   does not visibly reflow or jitter the text already on screen.
4. **Preemption is implemented and tested**: drag(100) > say(60) > follow(40) > idle(0).
   - Dragging mid-sentence parks the queue; on drop, only unexpired intents resume.
   - A running `say` defers `moveTo`, and **idle wandering never interrupts a sentence** — this is
     an explicit automated test, not a manual check.
   - Equal priorities queue rather than preempt.
5. **TTL is enforced at dispatch**: an intent that waited too long is dropped, not played late.
6. **Attention budget is enforced**: `say` rate limits per producer, one concurrent bubble, and
   `rate_limited` acks with `retry_after_ms`.
7. Preempted and dropped intents are observable in the log with their reason.

### Risk retired

That the pet becomes a notification firehose. "Not annoying" stops being a slogan here and becomes
enforced behaviour with tests.

---

## M3 — Control plane: `pookie say "hi"` from the terminal

### Goal

Make the pet drivable from a shell. This is the milestone that unlocks everything: once a terminal
one-liner can move the cat, every integration, demo, and experiment becomes cheap.

### Acceptance criteria

1. The pet hosts the intent socket described in `PROTOCOL.md` (NDJSON over a Unix domain socket,
   loopback TCP fallback), speaking protocol version `0.1`.
2. A `pookie` CLI exists with at least: `pookie say "..."`, `pookie emote <name>`,
   `pookie move <anchor>`, `pookie state <name>`, `pookie hide`, `pookie show`.
3. `pookie say "hi"` from a fresh terminal makes the pet speak, with no additional setup beyond the
   CLI being on `PATH`.
4. **Envelope semantics are complete**: `id` dedupe, `ts` + `ttl` expiry, `priority` override, acks,
   and every error code in `PROTOCOL.md` behaving as documented.
5. Malformed input, unknown verbs, and duplicate ids are rejected with the correct error and do not
   affect the running pet.
6. A `pookie env` / status subcommand reports the socket path, protocol version, running pets, and
   whether a brain is connected.
7. Fuzzing the socket with garbage for 30 seconds does not crash or leak the pet.

### Risk retired

That nothing can drive the pet without custom code. Also retires protocol-shape risk: real shell use
will find the argument that is wrong long before the MCP adapter does.

---

## M4 — MCP server so Codex and Claude Code can drive it

### Goal

Expose the verb vocabulary as MCP tools (`PROTOCOL.md` section 7) so coding agents can animate the
pet with no bespoke integration.

### Acceptance criteria

1. An MCP server exposes one tool per verb, with names and args matching the sketch in
   `PROTOCOL.md`. The adapter contains no behaviour logic beyond translation.
2. **Codex** and **Claude Code** can both list and call the tools, and a call like
   `pookie_say("tests passed")` visibly drives the pet on both.
3. Event subscription works through the negotiated mechanism. If push notifications are not
   supported by a target client, `pookie_poll_events` is the documented path — this must be resolved
   empirically, not assumed.
4. Tool descriptions state the attention budget, and an agent that calls `pookie_say` in a tight loop
   is rate-limited with a visible error rather than flooding the desktop.
5. A documented end-to-end example ships: an agent finishes a task and the pet reports it.
6. The pet behaves identically whether driven by the CLI or by MCP — same priorities, same TTLs,
   same events.

### Risk retired

That driving the pet from an agent requires custom glue per agent. Also retires the "is the
vocabulary actually expressive enough" question against a real, opinionated consumer.

---

## M5 — LLM brain: streaming chat and memory

### Goal

Give Pookie a conversation. The brain runs **out-of-process** per ADR-0003, speaks the same protocol
as any producer, and can be killed and restarted mid-sentence without taking the pet down.

### Acceptance criteria

1. The brain is a separate local process (Node or Python) that starts, stops, and restarts
   independently of the shell.
2. **Streaming conversation**: a message to the brain produces a streamed response rendered through
   `say(stream: true)` + `bubble.append`, with the pet's mouth/expression following the stream.
3. **Memory persists across brain restarts.** Killing the brain mid-conversation and restarting it
   preserves history; the conversation continues rather than resetting.
4. **Shell resilience is proven by test**: kill the brain mid-stream. The pet does not freeze, does
   not hang on the render thread, does not leave a permanently half-typed bubble, and returns to idle.
   Reconnection uses backoff, and a persistently absent brain produces a quiet, visible degraded state.
5. Latency from brain token to pixel is measured and documented; the render loop never blocks on the
   brain.
6. The user can stop the brain from the shell without quitting the pet.
7. Conversation state is stored on disk in a documented location and format.

### Risk retired

That the usefulness axis is real. Also retires process-lifecycle risk: supervised restart, correlated
ids across a process boundary, and graceful degradation.

---

## M6 — Voice and global hotkey

### Goal

Hands-free interaction: speech in, speech out, and a global hotkey that does not require Accessibility
permission.

### Acceptance criteria

1. **STT** via `whisper.cpp` runs locally. No audio leaves the machine.
2. **TTS** via `AVSpeechSynthesizer` speaks responses, with at least one voice option and a mute
   toggle. The cat animates in sync with speech.
3. **Push-to-talk via a global hotkey** registered so that it works **without** prompting for
   Accessibility or Input Monitoring. (Carbon `RegisterEventHotKey` is the current candidate; see
   `MACOS-CONSTRAINTS.md`.)
4. Microphone is captured **only** while the hotkey or a visible push-to-talk affordance is active.
   A persistent, honest indicator exists whenever audio is being captured.
5. The pet ducks or pauses idle micro-behaviours while listening, and does not talk over the user.
6. Wake-word-free by default: there is no always-on listening mode.
7. Voice round trip (hotkey release → first audio out) is measured and documented.

### Risk retired

That the permission model blocks the feature. If a global hotkey genuinely requires Accessibility or
Input Monitoring, that is discovered here — with a documented fallback rather than a surprise at
launch.

---

## M7 — Reactive skill packs

### Goal

Let behaviour be authored as data. A skill pack maps producer events and user interactions to intents,
so new behaviour ships without a new build of the pet.

### Acceptance criteria

1. A skill pack is a declarative document (file or folder) that binds triggers to intents — for
   example "on git commit → `emote(sparkle)`", "on `petted` → `say` from a random list".
2. Skills are loaded and unloaded at runtime without restarting the pet.
3. **Skill packs cannot execute arbitrary code in the pet process.** They emit intents only, and go
   through the same router, priorities, TTLs, and rate limits as any other producer.
4. A malformed or hostile skill pack is rejected with a clear error and cannot destabilise the pet.
5. Trigger sources include at least: protocol events (`clicked`, `dragged`, `dropped`, `petted`,
   `bubbleClicked`), timers, git hooks, and build/file watchers.
6. A skill that exceeds the attention budget is throttled; there is a per-skill budget and a global
   one.
7. At least three example skill packs ship and are documented.

### Risk retired

That every new behaviour requires us. Also retires the safety question of letting third parties drive
the pet.

---

## M8 — Multi-pet, menu-bar settings, packaging

**Status: partially landed.** Criterion 1 is in for the in-process case — and then some: up to ten
pets coexist, one of each species (cat, bunny, puppy, fox, panda), each with its own coat, size and
behaviour engine, spawned and removed from the menu-bar item or `Pookie --pets N`, under one shared
frame budget, with a persisted roster. The menu-bar item already carries show/hide, **pet size**,
**add / remove a pookie**, per-pet kind and coat, the spokespet, mouse mode, wander, cursor tracking,
perching, jumping, speech, **teleport between displays and its cadence**, per-pet visibility and
removal from a right-click on the pet itself, screen-sharing privacy and quit — so criterion 2 is
largely there ahead of its milestone. The settings window and the persisted
collection landed ahead of the milestone: a real window (General / Behaviour / Pookies), a roster that
holds every animal with a desk flag, and the frame budget. Outstanding: opacity, quiet mode,
per-producer rate limits, skill toggles, launch at login, and the per-pet CPU budget is still a shared
frame-rate ceiling rather than an accounting of who spent what.

### Goal

Make it installable by a stranger and configurable without editing files. This is the
"someone else can use this" milestone.

### Acceptance criteria

1. `spawn` and `despawn` work with the documented semantics; multiple pets coexist, each with its own
   behaviour engine, and the per-pet CPU budget scales honestly (N pets must not mean N× the idle
   cost of one, or the limit must be documented).
2. A **menu-bar item** provides settings: show/hide, pet scale, opacity, quiet mode, per-producer
   rate limits, skill pack toggles, launch at login, and quit.
3. Settings persist and are editable without touching a JSON file by hand (a plain-text config file
   may still exist for power users).
4. **Distribution is a signed, notarized DMG.** Gatekeeper opens it without a warning on a clean
   machine.
5. No Accessibility, Screen Recording, or Input Monitoring permission is requested for any core
   feature. Optional features that need one ask at the moment of use, with an explanation, and
   degrade gracefully when denied.
6. First-run experience: the pet appears, a short onboarding bubble explains the hide hotkey, and
   nothing else is required to use it.
7. Uninstall is documented and complete: app, settings, sockets, and any brain process.
8. The app is not distributed via the Mac App Store, and the docs say why. See
   `MACOS-CONSTRAINTS.md`.

### Risk retired

That only the author can run it. The pet's adoption ceiling is set here: install friction and
permission prompts, not features.

---

## Sequencing notes

- **M0 and M1 are separated on purpose.** M0 proves the window; M1 proves the feel. Mixing them means
  a window bug looks like an animation bug.
- **M3 is the hinge.** Everything before it is a demo; everything after it is a platform. If schedule
  pressure forces a cut, cut features, not M3.
- **M2 before M3** because speech is the pet's primary output channel; a control plane that can only
  move the cat is not yet worth building a client ecosystem for.
- **Voice is deliberately late.** It multiplies permission and privacy risk, and the product must be
  useful silently first.
- **Docs track milestones.** Behavioural changes land in `DESIGN.md` / `PROTOCOL.md` in the same change
  as the code, and architecture decisions that would surprise a reader get an ADR.
