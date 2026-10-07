# Pookie — Design

Status: living document. Written alongside the M0 walking skeleton.
Stack: Swift + AppKit. SpriteKit arrives in M1. No Tauri, no Electron, no webview in the pet path.

---

## 1. Product thesis

A desktop pet dies from one of two causes: it is boring, or it is annoying. Boring is
recoverable. Annoying is not — the user uninstalls and never comes back.

So the product is judged on three axes, and the third one is not a tiebreaker:

| Axis | What it means | How it fails |
|---|---|---|
| Charm | It feels alive and it is pleasant to look at | Static PNG pasted on the desktop |
| Usefulness | It carries information the user actually wanted | Another notification firehose |
| Not annoying | It never takes something from the user to give them something | It steals focus, covers text, or talks too much |

**"Not annoying" is a first-class design constraint, enforced in code, not in taste.**

Concretely, that constraint compiles down to rules:

1. **Never steal focus.** The pet window can never become key. Typing in an editor must be
   impossible to interrupt. See `MACOS-CONSTRAINTS.md` — this is the single most common way
   desktop pets become unusable.
2. **Never block work.** The pet lives in screen edges and perches. It does not float over the
   centre of the screen unless explicitly told to.
3. **Silence by default.** With no producers connected, Pookie idles and says nothing. It has no
   opinions to volunteer.
4. **Attention is rate-limited.** Producers cannot exceed a budget of ambient interruptions.
   Excess intents are queued, coalesced, or dropped — never stacked into a pile of bubbles.
5. **Every behaviour is interruptible by the user.** Drag always wins. A hide hotkey always
   exists.

Usefulness without those five rules is just a noisier notification centre with a cat drawn on it.

---

## 2. Core insight: the pet is a renderer, not an app

Pookie does not know about Codex. It does not know about git. It does not know about your
calendar. It knows how to *say*, *emote*, *move*, *look*, and *be petted*.

Everything else is a producer emitting intents into a small verb vocabulary:

```
Codex finished a long task   ──►  say("Done. 3 files changed.")  +  emote("happy")
git commit hook fired        ──►  emote("sparkle")
Pomodoro timer expired       ──►  say("25 minutes. Stand up.")   +  moveTo(centre)
You clicked the cat          ──►  (pet emits "clicked")  ──►  producer decides what that means
```

This is the whole architecture in one sentence: **producers emit intents, the pet renders them.**

Why this matters more than it looks:

- **The pet ships before the integrations exist.** M0–M2 build a cat that responds to a protocol.
  Nothing in the pet target depends on an agent, a CLI, or an LLM.
- **Integrations are cheap and independent.** A new producer is a client of the protocol. It
  cannot destabilise the shell, cannot leak memory into the render loop, cannot crash the pet.
- **The vocabulary is the API.** A fixed, small verb set forces producers to express *what should
  happen*, not *how to draw it*. We never grow a "Codex mode".
- **It is testable.** Feed a scripted intent stream, assert the emitted event stream. No UI needed.

The failure mode we are explicitly avoiding is the feature-per-integration app: a `CodexWidget`,
a `GitWidget`, a `CalendarWidget`, each with its own window, each with its own idea of what a
desktop presence is. That app dies of combinatorial maintenance.

---

## 3. Architecture: four layers

```
┌───────────────────────────────────────────────────────────────────────────┐
│  L1  PRODUCERS                                                            │
│                                                                           │
│   Codex CLI      Claude Code     shell: pookie say "hi"     CI / build      │
│   git hooks      file watchers   calendar / timers         voice (M6)      │
│   LLM brain (M5, out-of-process: Node or Python)          MCP clients (M4) │
└──────────────────────────────────┬────────────────────────────────────────┘
                                   │  Intent envelope (JSON over localhost)
                                   │  { id, ts, verb, args, priority, ttl }
                                   ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  L2  INTENT ROUTER                                                        │
│                                                                           │
│   decode + validate  ·  dedupe by id  ·  TTL expiry  ·  rate limit        │
│   attention budget  ·  verb → Action mapping  ·  backpressure / drop       │
└──────────────────────────────────┬────────────────────────────────────────┘
                                   │  Action (typed, in-process)
                                   ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  L3  BEHAVIOUR ENGINE                                                     │
│                                                                           │
│   priority stack  ·  preemption  ·  animation state machine (M1)           │
│   idle micro-behaviour scheduler  ·  fake physics (waypoint spring,        │
│   gravity + restitution)  ·  emits pet.on(event): clicked/dragged/...      │
└──────────────────────────────────┬────────────────────────────────────────┘
                                   │  PetState (pose, mood, position)
                                   ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  L4  SHELL  (AppKit)                                                      │
│                                                                           │
│   borderless non-activating panel  ·  PetRenderer protocol (M0: Core      │
│   Graphics cat; M1: SpriteKit)  ·  bubble window (M2)  ·  hotkeys          │
│   occlusion + fps governor  ·  display reconfiguration                    │
└───────────────────────────────────────────────────────────────────────────┘
```

Layer rules:

- Dependencies point downward only. L4 has no idea what an "intent" is; L2 has no idea what a
  window is.
- L1 is always out-of-process. Producers talk to the shell over the wire protocol, never by
  linking. See ADR-0003.
- The whole of L2 + L3 is pure logic with no AppKit imports. That is what makes it unit-testable
  in a headless test target.

The renderer is a seam, not a layer: `PetRenderer` is a protocol (`render(state:)` plus a
`measure`/`intrinsicSize` concept), so M0's procedural Core Graphics cat and M1's SpriteKit scene
are interchangeable behind it.

---

## 4. The intent vocabulary

Roughly twelve verbs. This is the contract; see `PROTOCOL.md` for argument tables and examples.

| Verb | Signature (abridged) | Meaning |
|---|---|---|
| `say` | `{text, mood?, duration?, stream?}` | Speak a line. Triggers the bubble. |
| `emote` | `{name, loops?}` | Play a named affect: happy, sparkle, confused, sleepy, alarmed. |
| `moveTo` | `{x, y, screen?, speed?, arc?}` | Walk to a point. Physics-driven, not a teleport. |
| `lookAt` | `{x, y, target?}` | Eyes/head track a point, body does not move. |
| `face` | `{direction: left\|right\|cursor, target?}` | Set facing, e.g. turn to the active window. |
| `state` | `{name, params?}` | Force a high-level state: `idle`, `sleep`, `work`, `alert`, `hidden`. |
| `bubble.show` | `{text, style?, ttl?, anchor?}` | Show a bubble without speaking (silent info card). |
| `bubble.append` | `{id, delta}` | Stream a token/delta into an open bubble. |
| `bubble.hide` | `{id?, reason?}` | Dismiss one bubble or all of them. |
| `spawn` | `{petId, kind?, at?}` | Create an additional pet instance. |
| `despawn` | `{petId, exit?: poof\|walkOff}` | Remove a pet instance. |
| `pet.on` | `{event, handler?}` | Subscribe to pet-emitted events. |

Events the pet emits back:

`clicked`, `dragged`, `dropped`, `petted`, `bubbleClicked`.

Design notes on the vocabulary:

- **`say` and `bubble.show` are different verbs on purpose.** `say` is an utterance: it has a mood,
  it ducks idle behaviour, it opens a bubble for you. `bubble.show` is a silent information card:
  it does not command attention the same way and may persist.
- **`moveTo` is a request, not a teleport.** The behaviour engine may refuse, defer, or shorten it
  if something more important is happening. It resolves with a completion event, not a promise
  that it happened instantly.
- **`pet.on` is the only verb that is a subscription.** It is how a producer learns that the user
  interacted, which is what makes two-way skills possible without the pet knowing any skill.
- **No verb draws.** There is no `setSprite`, no `playAnimation('wave')` by asset name, no colour
  argument. Animation choice is the pet's business; producers express intent.

---

## 5. Behaviour priority stack and preemption

Every incoming action carries a priority. The engine keeps a stack, not a queue: a higher-priority
action preempts the current one, and the preempted action is either resumed or dropped depending
on its `resumable` flag.

| Priority | Behaviour | Source | Interruptible by | Resumable |
|---:|---|---|---|---|
| 100 | `drag` | user, direct manipulation | nothing (user is holding it) | no |
| 60 | `say` + bubble | producer intent | `drag` only | no |
| 40 | `follow` / `moveTo` | producer intent, cursor follow | `drag`, `say` | yes |
| 0 | `idle` | engine itself | everything | yes |

Preemption rules:

1. **Higher priority wins immediately; ties do not preempt.** Two `say` intents at priority 60
   queue rather than interrupt each other.
2. **`drag` (100) hard-clears the stack.** While the user holds the pet, all producer intent is
   parked. On drop, the engine emits `dropped`, resets to `idle` at the drop position, and only
   then drains whatever is still unexpired.
3. **`say` (60) takes a locomotion lock.** While a sentence is being spoken, the body root does
   not move. `moveTo`/wander requests are deferred, not cancelled. `lookAt`, blink, breathing, and
   tail sway continue — they do not move the root.
4. **Idle wandering never interrupts a sentence.** This is the rule the whole priority scheme
   exists to protect. Idle has priority 0; anything above it suspends the wander scheduler. A cat
   that walks away mid-sentence reads as broken, not as a pet.
5. **TTL beats the stack.** Every intent carries a `ttl`. An intent that spent too long deferred
   behind a sentence is dropped rather than played late. Stale "build passed!" from four minutes
   ago is worse than silence.
6. **Preemption is observable.** The engine emits `preempted` / `resumed` internally so behaviour
   tests can assert the ordering rather than eyeball the pixels.

`spawn` / `despawn` are structural and bypass the stack: they create or destroy an engine instance
rather than scheduling work inside one. They are still rate-limited and still idempotent by `id`.

---

## 6. Idle micro-behaviours: what makes it feel alive

A static sprite with a walk cycle still reads as a toy. Aliveness comes from behaviour that
happens when nothing is being asked of the pet. In M1 these run as a weighted scheduler on top of
the `idle` state, each with its own cooldown and randomization:

| Micro-behaviour | Cadence | Notes |
|---|---|---|
| Blink | every 2–6 s, randomized, some double-blinks | Cheapest, highest impact per CPU cycle |
| Breathing | continuous, ~0.25 Hz | Sub-pixel scale/bob. Do not animate on a 60 fps timer if 12 fps will do |
| Tail sway | continuous, 0.3–0.6 Hz, phase-shifted | Amplitude rises with arousal state |
| Ear twitch | every 8–20 s | Triggered by sharp sounds later (M6) |
| Look-at-cursor | when idle, cursor within a radius | Reuses `lookAt`; includes a small head-lead bias |
| Wander | every 20–60 s | `moveTo` a waypoint inside the current screen's edge band. Suppressed while she is settled into a rest shape, so the sit before sleep is not interrupted by a stroll |
| Teleport to another display | a jittered 1–30 minutes (a setting), when there is more than one display and the setting is on | The only way a pet on a two-monitor desk ever uses the second monitor. **Staged in two halves**: she spins down into a poof of light and her own fur (0.5 s), the hop happens while she is off screen, and she spins back in with a landing squash (0.5 s). She arrives *from above*, so a window top under her becomes the ground she lands on rather than something she appears in front of. Suppressed while you are holding her, mid-air, mid-sentence, asleep or mid-chase — and grabbing her mid-blink cancels it, because the user's hand outranks an effect in progress |
| Zoomies | every 60–200 s, from a standstill | A dash at 2.1x trot for about a second. No new art: a speed multiplier and a far target, which is all a burst of energy is |
| Sneeze | every 2–5 minutes | A hop, a head shake, a squint and one line — the only thing she says without being asked, so it goes through the same rate limiter as everything else |
| Kneading | settled on a ledge and awake | The punch channel at a fifth of the swing, on a 4 Hz rhythm. Reusing a channel rather than adding one is the point: a knead *is* a small punch |
| Head-bump | the pointer within 90pt | A lean toward it, proportional to how close, and a hop within 46pt. Unprompted affection is what a desktop pet is for |
| Sleeping in a pile | two settled pookies | The separation rule shrinks by a third when both are resting, so they lean on each other instead of being pushed apart |
| Brawl | contact, or three seconds within a paw's length, every 6–16 s | The close-quarters version of playing: flattened ears, a hop under each swing, a **one-two of thrown paws** (`CatPose.punch`, alternating sign) with a comic burst where each lands (`CatPose.impact`), one bubble, 1.6–3 s. Two who *touch* start one on the spot; three seconds of nearness is for pookies who sit down near each other. The separation rule relaxes to half, so their bodies overlap — at the first distance they were close enough to look like dancing, which is exactly what the human reported. A landed swing is signalled (`takePendingHit`) and handed to the other pookie, who flinches: squint, open mouth, head snapping away, stagger, one bubble. A chase that closes the distance becomes one, so "they fight when they are close" falls out of the same rule as the chase rather than being a third scheduler |
| Company | continuous, when other pets are near | Two cats converging on one pixel read as one buggy cat, so each steps out of the other's way. The push is positional and decays to zero at one personal space, so they settle apart instead of springing at each other forever, and it only applies between cats on the same footing — one on a ledge and one on the floor are not stacked |
| Play | every 20–50 s, when two cats are awake on the same display | A jittered 2–5 s chase: aim at the playmate through the ordinary wander channel, re-aimed every 0.3 s, wearing the happy face. Refused while asleep, held, mid-air or mid-sentence, and behind the same "Wander around" switch as any other unprompted walking. One cat of the pair says a line, not both |
| Perch | on landing above a window top | One-way platform: a window top is a floor only if she is already above it. She rides a dragged window and falls off the end |
| Jump to a ledge | every 12–32 s, or 3–8 s if nothing was in reach | She gathers, leaps onto a reachable window top, and climbs from one window to a higher one. Suppressed during a sentence, while asleep, and by the menu toggle |
| Settle into a shape | loaf 8–16 s after she stops on a perch, and it lasts 20–45 s; sit after 45–80 s idle; lie when asleep | **Sit, loaf, lie, stretch** — four anatomy keyframes she blends into rather than cuts to. A posture is a weight vector across the shapes, not a state plus a progress bar, so retargeting mid-settle (sitting down, then dozing off before the sit finishes) cannot pop. The loaf is a bounded episode, so a cat that has settled still gets up and moves on. See §7 |
| Stretch / yawn | on waking, and once after ~35–70 s of idle | Signals "nothing is happening" instead of dead air — and it is what sells "she was asleep". One shape weight is the whole timeline: the bow, the open mouth and the squint are the same number |
| Sleep | after N minutes of no intent and no interaction | Drops to the lowest fps tier, lies down, shuts her eyes |

Rules that keep these from becoming noise:

- **Randomize, never synchronize.** Fixed periods read as a metronome. All cadences get jitter.
- **One at a time for pose-changing behaviours.** Blink + breathe + sway can overlap; wander,
  stretch, and sleep cannot. The rest ladder is a single priority list — dragging and being airborne
  beat sleep, sleep beats the sit, the sit beats the loaf — so exactly one shape is ever being eased
  into. The stretch is the one scripted animation, and it lays *over* the resting shape instead of
  replacing it, so waking out of a lie uncurls rather than cutting.
- **Suppressed during `say`.** Only the non-root-moving ones survive a sentence.
- **Suppressed while the user is in a call, presenting, or screen-sharing**, if we can tell —
  see the fullscreen/Do-Not-Disturb heuristics in `MACOS-CONSTRAINTS.md`.

---

## 7. Animation strategy ladder

Rendering technique escalates in cost. We start at the cheapest rung that can prove the product
and only climb when a rung provably fails.

| Rung | Technique | Cost to build | Buys | Costs |
|---:|---|---|---|---|
| 0 | **Procedural, code-driven** (M0) | Days. No asset pipeline | Total control, every parameter animatable, tiny binary, works before any artist exists | Ceiling on charm; hard to make genuinely expressive |
| 1 | **Sprite sheets** (SpriteKit, M1) | Art time + atlas tooling | Real charm; the standard for 2D pets; well-understood tooling | Fixed frame counts; state explosion; art is the bottleneck |
| 2 | **Rive** | Runtime dep + designer learning curve | State machine authored as data, blend trees, art and logic decoupled | Another runtime, another format, another way to ship a bug |
| 3 | **Live2D / VRM** | Heavy: rigging, runtime, mocap-ish | Near-continuous expressiveness, real physics on hair/tail | Heaviest runtime and art cost; 3D-ish style may not fit Pookie |

Why rung 0 first: the hard, risky parts of this product are **windows, permissions, the protocol,
and behaviour**, not pixels. A procedural cat forces us to build and debug exactly those, with no
art dependency blocking the critical path. It also gives us a fully parameterized test subject —
we can drive any pose from a test and screenshot it.

The ladder is a hedge, not a plan. We climb only if the current rung is the thing failing. And the
`PetRenderer` protocol exists so climbing is a swap, not a rewrite.

### Rung 0, taken seriously: shapes as data

The procedural cat is not a placeholder that animates by piling up branches in the drawing code. A
posture is a table of anchors (`CatAnatomy`), the renderer draws whatever anchors it is handed, and
the pose carries a *weight vector* across the five shapes. Three consequences, all pinned by
`--selftest`:

- **Settling is a morph.** Half a loaf is literally the average of the standing and loafing tables,
  so the test asserts that the halfway anatomy is the midpoint, and that no frame of a settle moves
  an anchor more than half a design unit. "Reads as a hard cut" is a test failure, not a taste call.
- **Retargeting cannot pop.** There is no from/to edge to re-anchor: weights move toward the target
  in proportion, so a cat that starts sitting down and dozes off half way through keeps moving at the
  same speed instead of snapping to the lie.
- **The envelope still holds.** The stage is the contract, and the resting shapes are lower and wider
  than the standing cat. Rather than grow the window — which would move a perch geometry test and,
  worse, make her hover above the floor the physics stands her on — each shape damps its own lean
  (`CatAnatomy.leanScale`). The envelope sweep then proves every keyframe *and* every mid-settle
  blend stays inside the stage.

The stretch is the same mechanism with a timeline: one shape weight rises and falls, and the open
mouth and the squint are the renderer's reading of that weight, so there is no second animation clock
to keep in sync with the body. This is also the piece of M1's "explicit animation state machine"
that the procedural cat can carry without SpriteKit: states, legal transitions, and a documented
preemption order, all in pure logic.

**A species is a table as well** (`PetSpecies`, `SpeciesTraits`). Seventeen animals share one skeleton:
each species supplies proportions (scaled about the ground line, so nobody floats) and appendages —
four ear shapes, three tail shapes, and flags for whiskers, markings, eye patches and dark limbs. The
whole behaviour layer, and every animation in this section, belongs to all five without a line of new
behaviour. A bird also needed a channel the others do not use: `CatPose.flap`, which the
behaviour drives from the same state machine as the walk — a flutter on the ground, a full flap in
the air — so a duckling's two gaits are one animation at two amplitudes. Two constraints the
envelope test enforced: a tall-eared animal is *smaller* rather than given a taller window (a taller window is a longer ledge it no longer fits on), and a thick tail has
to be *lifted*, because a stroked curve half a brush wider than a cat's hangs below the ground line it
is resting on.

**The teleport blink is the same trick again**, and the reason it is a transform rather than a
sprite flip: `CatPose.vanish` is one number, the behaviour plays it 0 → 1, moves her, then 1 → 0, and
the renderer spins her down to nothing on the way. Two constraints shaped it, both discovered by the
art-envelope test rather than by taste. A full turn at full size sweeps her head through the ground
line, so the spin is a quarter turn and the shrink leads it — the further the turn has gone, the
smaller she must be, and a bigger turn reaches its dangerous angle sooner, which costs her
visibility. The poof (two rings and seven sparks) is bounded to the same stage: the first version
threw fur below the floor line and `--selftest` failed on the pixels, which is exactly what that
sweep is for.

---

## 8. Fake physics

We do not need a physics engine. We need two tricks that read as physical.

**Walking: waypoint + spring.**

- A `moveTo` sets a target waypoint.
- Each tick: `a = k * (target - pos) - c * v`, integrated with a fixed timestep, speed-capped.
- Near the waypoint, `k` drops and damping rises, so the pet eases in instead of snapping.
- Facing flips on the sign of `vx`; the walk cycle's phase is driven by distance travelled, not by
  wall-clock time, so it never moonwalks.
- Big traversals become a short path of waypoints, not one long straight line.

**Drag and fling: gravity + restitution.**

- While dragging, the body follows the cursor through a lag spring, so it trails slightly and
  tilts into the motion (`tilt = clamp(k * vx, ±maxTilt)`).
- On drop, the drag velocity becomes initial velocity. Gravity pulls down; the floor is the bottom
  of the current screen's visible frame (or the dock band).
- On floor/edge contact: reflect with `restitution ≈ 0.3–0.4`, apply tangential friction, and cut
  off when speed falls below a threshold. Then hand back to `idle`.
- Clamp hard: never leave the screen, never tunnel through the screen edge, never accumulate
  energy. A pet that jitters forever in a corner reads as a bug.

Both tricks are pure functions of `(position, velocity, dt)` — no AppKit — so they are unit
testable and deterministic under a fixed timestep.

---

## 9. Battery and energy discipline

A desktop pet that costs 5% CPU is a pet that gets killed. Budget: **under ~1% CPU and ~40 MB RSS
while idle and visible**, effectively 0% while occluded.

| Technique | Detail |
|---|---|
| Occlusion-based pausing | Read `NSWindow.occlusionState`. When the pet is not `.visible`, stop the display link outright and drop to a slow 1 Hz housekeeping timer. Nothing to draw means nothing to compute |
| FPS tiers | idle/sleep ≈ 8–12 fps, idle-visible ≈ 24 fps, walking/speaking ≈ 30 fps, dragging and airborne (thrown or jumping) ≈ display rate. Decimate a display link rather than running several timers |
| `CADisplayLink` | Preferred frame clock on macOS 14+. Note the availability caveat and the older fallback in `MACOS-CONSTRAINTS.md` |
| Cursor polling | Poll `NSEvent.mouseLocation` at 10–15 Hz for look-at-cursor, not 60 Hz, and only when idle and visible |
| Window-list scans | `CGWindowListCopyWindowInfo` runs on its own clock: 1 Hz idle, 5 Hz airborne (so she lands on a window rather than through it), 10 Hz while perched (so riding a dragged window is smooth). Never per-frame |
| App Nap | Hold a `ProcessInfo` activity only while actually animating; release it the moment we go idle-occluded, or the OS energy accounting punishes us |
| No hot loops | No global event taps, no per-frame window-list scans, no polling git. Producers push; the pet does not poll |
| Suspend on lock/sleep | Screen lock, display sleep, and fast user switching stop the render loop entirely |

Tier transitions are hysteresis-based. A pet at the boundary between "idle" and "active" must not
oscillate between 12 and 30 fps every frame.

**A stutter is measured, not felt.** `PetView` times each draw (`worst=`) and counts silhouette
rasterisations (`masks=`), and the controller reports how late the frame pump ran as a multiple of its
target interval (`slip=`). With five pookies that is 1–2 ms of drawing, ~2 rasterisations a second and a
worst lateness of 1.2x — so the renderer is not the cost. What remains is window-server work: a
transparent always-on-top window moving every frame, twice as often while airborne, which is exactly
what M1's layer-backed renderer replaces with one compositor-moved surface. Those three numbers are the
regression metric for that work.

**Many pets share one budget.** The population is capped at five (`PetCohort`) — one of each species,
which is the number that reads as a little gang rather than as a crowd — and the frame rates are
divided rather than multiplied: `totalFrameBudget` is 120 drawn frames per second for the whole
colony, so a single pet is unaffected by it and five get 24 fps each, the tier a walking cat already
uses. An occluded pet pauses outright, so a colony behind a fullscreen app costs nothing. Measured on
a 3840x1620 display while idle: one pet ≈ 7% CPU / 52 MB, three ≈ 13% / 56 MB, five ≈ 17% / 60 MB.
Five therefore cost about 2.4x one rather than 5x — and the remaining absolute cost is the software
rasterisation M1 exists to remove, multiplied by five. This is the honest reason the cap is a cap.

---

## 10. M0 scope vs deferred

M0 is the **walking skeleton**: the riskiest slice, built first, ugly on purpose. **It is built.**
Measured results and the bugs it caught are in `M0-FINDINGS.md`.

### In M0 — as actually shipped

- A borderless, transparent, always-on-top window that **can never become key**, riding every Space
  (`.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`, `.ignoresCycle`) at `.floating` level,
  with a `.statusBar` escape hatch for fullscreen apps.
- A **procedural cat** drawn with Core Graphics (~35 antialiased paths), behind a swappable
  `PetRenderer` protocol — breathing, blinking, tail sway, ear twitch, cursor-tracking pupils,
  squash-and-stretch, and an open mouth for M2's speech.
- **True click-through** in the gaps, implemented by toggling `ignoresMouseEvents` from a cursor poll
  rather than by `hitTest` (see §11 item 1 and `MACOS-CONSTRAINTS.md` §3).
- **Drag, fling, gravity and restitution** with air drag, wall/ceiling clamps, and a landing squash.
- **Waypoint wandering** with a walk/trot and cursor-biased target selection, so the cat returns to
  the screen you are working on.
- **Frame-rate tiers** (sleepy 8, idle 15, active 24–30, dragging 60) built on `CADisplayLink`,
  decimating rather than running extra timers, with 0.4 s debounce and occlusion pausing.
- **Sub-stepped simulation**: physics integrates at a fixed 60 Hz regardless of draw rate, so tiering
  never distorts gravity or the idle clock.
- Four **permission-free global hotkeys** (hide, cycle mouse mode, describe state, bring home), a
  built-in **menu-bar item**, a **screen-sharing privacy toggle**, and a `--verbose` in-process
  **CPU/RSS meter**.
- **`--selftest` and `--render-png`**: headless checks for bitmap layout, silhouette coverage, and
  physics on a two-display topology, plus an offscreen pose sheet for reviewing artwork without
  Screen Recording permission.

### Landed after M0 (the fix pass)

- **A render stage and a declared pose envelope.** The cat is fitted into `CatGeometry.stage`, a rect
  larger than the art box and symmetric about her centre line, and the renderer clamps every pose to
  `CatPose.RenderLimits`. Before this, the swaying tail and the ears of a hopping or squashing cat
  were genuinely cut off at the window edge; `--selftest` now sweeps the whole envelope and fails if
  any ink reaches the window border. See `M0-FINDINGS.md` §3.1.
- **A speech bubble** (`BubbleWindow`, `Speech.swift`): a second borderless, transparent, non-key
  window anchored above her head, flipping below when there is no room. `say`, `bubble.append` and
  `bubble.hide` are implemented in-process behind `SpeechEngine` — one bubble at a time, a minimum
  gap between utterances, a length-derived dismiss timer, and a master mute. `Pookie --say "text"`
  reaches a running pet over a distributed notification until M3's socket lands. This is the M2 shell
  and half of its behaviour; the preemption stack and attention budget are still to come.
- **Perching on other apps' windows** (`WindowScanner`, `PerchPump`): she lands on the top edges of
  normal-layer windows, rides one while it is dragged, and falls off the end. Geometry only —
  `CGWindowListCopyWindowInfo` needs no Screen Recording permission, and titles are never read. It is
  a one-way platform, so she is never launched onto the top of a window she walks in front of.
- **Jumping onto windows by herself** (`PetMotion.planJump`): a ballistic leap, planned as a pure
  function, onto the best ledge she can reach. A ledge is only a candidate if she would be **fully
  visible** on it — the whole cat has to fit on the ledge and on the screen — which is the rule that
  stops her wedging herself against a display edge. Reach is capped at ~1050 pt, so she climbs
  through lower windows to reach higher ones, and she prefers the frontmost app's window.
- **Frame tiers driven by motion, not mood.** A thrown cat used to fall at the idle tier; see
  `M0-FINDINGS.md` §3.2. Up-shifts are immediate, down-shifts are debounced.
- **Click is an event.** A press and release in the same spot is a tap, not a throw, which is what
  lets her be petted as well as dragged — and is where the `clicked` / `petted` event stream starts.
- **Resting shapes, blended** (`CatAnatomy`, `CatShapeWeights`). She no longer only ever stands. Sit,
  tucked-paw loaf, lie and the waking stretch are anatomy keyframes, and the pose carries a weight
  vector across them, so a settle is an interpolation and not a hard cut (§7). A small rest ladder
  decides which: a loaf after a long perch, a sit before sleep, a lie while asleep, and a stretch and
  yawn on waking or after a long idle. `--selftest` sweeps every keyframe and every mid-settle blend
  through the art envelope, checks that each shape keeps a paw or a belly on the ground line, and
  fails if a settle moves an anchor more than half a design unit in a frame. The frame-tier table
  gained one rule from it: a settle or a stretch is never drawn at the sleep tier.
- **Size and displays are settings, not constants** (`CatScale`, `applyPetScale`,
  `PetMotion.teleportToRandomScreen`). The menu bar has a size — small to extra large — and a
  teleport toggle. Size is a real size change rather than a zoom: the window, the drawing and the
  behaviour geometry scale together, so a bigger Pookie still fits the ledge she jumps to and still
  reasons in her own units. The cost of that honesty is a bigger window to composite: extra large is
  3.6x the area of medium, which is a frame-tier problem long before it is a CPU problem. Teleporting
  is a jittered 45–120 s blink to another display, gated on there being one.
- **She stands on things, not above them.** The window used to be anchored with its bottom edge at
  the physics floor while the renderer kept a margin below her paws for a leaning pose, so the margin
  showed up as a ~7 pt gap above every window top she perched on. `CatGeometry.groundInset` is now
  the contract between the two: the floor is `PetMotion.origin`, and the window hangs that much lower
  on screen. `--selftest` rasterises the standing cat at every size setting, finds the lowest ink, and
  fails if it is not on the floor line — so the constant cannot quietly drift again.
- **A colony of cats** (`PetCohort`, `CatSkin`). `spawn` / `despawn` are real, in-process: up to ten
  pets, each with its own coat and size factor and the full behaviour set — perching, jumping,
  teleporting, resting, stretching. The cohort owns what only makes sense for a group: the cap, the
  shared frame budget (§9), the window exclusions that stop cats perching on each other, the companion
  positions each pet uses to step aside (§6), and the occasional play bout. Settings stay colony-wide,
  because "small" and "chatty" are properties of the desk rather than of one cat out of five.
  Everything that maps a design point to the screen is per-pet (`PetMotion.windowOrigin`), which is
  why ten windows can share one renderer without any of them disagreeing about where their cat is.
- **Markings over coats** (`PookiePattern`, `CatRenderer.drawPattern`). Nine patterns, independent of
  both the species and the coat, so the combinations multiply instead of the code: 8 animals x 17 coats x
  9 markings. Two rules make one drawing routine work across all of them — the marking colour is chosen
  for *contrast* against the fur rather than from a fixed palette slot, and every marking is outlined,
  which is what keeps a pale marking visible on a pale pookie. The two head markings are drawn in their
  own pass between the skull and the face, because drawn with the body they end up under the head.
  A punch and a marking are *transient* channels: they are swept against the stage on their own rather
  than through the deformation corners, because a brawl happens standing and grounded and multiplying a
  thrown paw by a full stretch would be testing a pose that cannot happen.
- **Names, a boss, and one of each animal** (`PookieConfig`, `PetSpecies`). Every pookie carries a
  name the human chose; the *pookie boss* is the one that answers producers, and any pookie can be
  promoted. The desk keeps one of each kind — a duplicate in a saved roster is repaired on load by
  becoming the next unused animal, keeping its coat and name — because two identical animals read as
  a bug rather than as company. A *coat* is the free axis: any animal wears any of them.
- **Per-pet control, including visibility** (`PetView.menu(for:)`, `PetCohort.setHidden(_:at:)`). Right
  clicking a pet offers a menu about *that* pet, built from a `PetMenuState` value so its shape is
  checkable without a window server. Hiding is per pet, not newest-first: a hidden pet's window is
  ordered out, its motion is paused, and it stops holding a share of the shared frame budget, which is
  what makes "hide the one I am pointing at" a better deal than removing it. The same items appear in
  the menu bar's **Pookies ▸**, because a pet you can only reach with the mouse is a pet you cannot
  reach when it is hidden.
- **Five species, and a roster you own** (`PetSpecies`, `PookieConfig`, `AppConfig.roster`). The desk
  can hold one of each animal — cat, bunny, puppy, fox, panda — and the menu decides which, in which
  coat, and which one answers producers. The roster, the size, the switches and the teleport cadence
  persist in `UserDefaults`; launch flags are one-run overrides and deliberately do *not* write to it,
  because a debugging flag that silently rewrites the saved settings is a bug the user cannot see.
- **Variety on the desk, and seams between displays** (`PetMotion.planJump`, `Desktop.neighbour`). The
  jump planner used to score purely on distance with a large bonus for the frontmost app, which put her
  on the same big window all day; it now penalises the window she is on and the last three she used,
  spreads the landing along the ledge, and takes the highest reachable ledge about a third of the time.
  And a display edge is a seam rather than a wall: `Desktop.neighbour` says whether anything is actually
  attached on that side, so she walks across instead of bouncing off nothing. The same wall code covers
  walking, jumping and being thrown, which is why the fix is one function.
  Fixing that exposed a real solver bug: the jump aimed with a *continuous* drag integral while the
  physics applies drag once per frame, so long jumps landed up to a fifth short. The integral now models
  the discrete integration, and a deterministic jump lands exactly on its target.
- **Brawls** (`PetMotion.startScuffle`, `CatPose.punch`/`impact`). Two pookies within a paw's length *for three
  seconds* brawl for 1.6–3 s: alternating thrown paws with a comic hit on each swing, leaning into each
  other. The three-second rule is what makes it provoked rather than random — the first version fired on
  the frame two animals happened to be close, which is why it was almost never seen.
- **The teleport has an effect** (`CatPose.vanish`, `CatGeometry.vanishTransform`). Leaving and
  arriving are separate animations rather than one teleport mark on the position: she spins down to
  nothing in a poof of light and fur, the hop happens off screen, and she spins back in. The whole
  effect is one pose number, and the art-envelope check sweeps it at twenty-five steps because it is
  the only pose the deformation limits do not cover (§7).

### Deferred, with the milestone that owns it

| Deferred | Milestone |
|---|---|
| SpriteKit renderer + sprite sheets — **now the top priority**, see §9 and `M0-FINDINGS.md` §2 | M1 |
| Cached static geometry / draw-call reduction | M1, only if the SpriteKit swap slips |
| Animation state machine with explicit preemption | M1 |
| Waypoint/spring easing for `moveTo` (M0 has linear waypoints + trot) | M1 |
| The rest of M2: preemption stack (`drag > say > follow > idle`), per-producer attention budget, streaming `say` from the wire | M2 |
| Wire protocol server + `pookie` CLI | M3 |
| MCP server | M4 |
| LLM brain, conversation, memory | M5 |
| Voice, push-to-talk, further hotkeys | M6 |
| Reactive skill packs | M7 |
| Multi-pet, preferences UI, notarization, DMG | M8 |

### Non-goals (explicitly)

- Pookie is not an always-listening assistant. Nothing captures the microphone unless a hotkey or a
  visible push-to-talk affordance triggers it.
- Pookie does not replace the Dock, the menu bar, or Spotlight.
- Pookie does not read other apps' notifications. That path is sandboxed, fragile, and unsupported.
- Pookie does not run its LLM in-process. See ADR-0003.

---

## 11. Known unknowns

Tracked here so they are not rediscovered as bugs. Full detail in `MACOS-CONSTRAINTS.md` and
`M0-FINDINGS.md`.

1. ~~Whether `hitTest` returning `nil` actually forwards a click to the application underneath.~~
   **Resolved by removal.** We could not prove the negative (no Screen Recording permission to
   observe a click in a third-party app), so we stopped depending on it: pass-through is done with
   `ignoresMouseEvents` toggled from a cursor poll. `hitTest` is a secondary guard only.
2. ~~Whether global mouse-moved monitoring is available without Accessibility/Input Monitoring
   permission.~~ **Resolved — do not use it.** Poll `NSEvent.mouseLocation`, which is permission-free
   and already runs on the frame pump.
3. Whether `NSWindow.sharingType = .none` still reliably excludes the window on modern screen-sharing
   and conferencing stacks. **Still open** — implemented but untested against a real client.
4. ~~Whether Carbon `RegisterEventHotKey` remains the right global-hotkey mechanism long term.~~
   **Partially resolved.** It registers four hotkeys with zero permission prompts on macOS 26.6.2.
   Still to confirm in a notarized/sandboxed build (M6).
5. ~~Whether `CADisplayLink` availability (macOS 14+) is an acceptable floor.~~ **Resolved.** It
   compiles and runs unguarded at a macOS 14 deployment target.

### New unknowns surfaced by M0

6. Whether a SpriteKit renderer actually removes the ~3 ms/frame software rasterisation cost, and by
   how much. This is the M1 bet; measure it with `--verbose` before and after. See `M0-FINDINGS.md` §2.
7. Whether the seam-gap fallback in `Desktop.region(containing:)` needs to prefer the previous region
   for points near a display boundary. Low severity, deferred to M1.
8. Whether perching behaves when the host window moves to another Space. The pet joins every Space
   and so does the window, but the platform list is built from `optionOnScreenOnly`, so the window
   may vanish from the list and reappear. Untested.
9. Whether the `--say` distributed-notification bridge survives a notarized, sandboxed build. It is
   explicitly a stand-in for the M3 loopback socket, which is the transport we actually intend to
   ship, so the answer only has to hold until M3.

---

## See also

- `M0-FINDINGS.md` — what M0 measured, what it broke, and what is still unverified.
- `adr/0001-swift-appkit-over-tauri.md` — why native, and what we hand-rolled.
- `adr/0002-pet-as-renderer-intent-protocol.md` — why a verb vocabulary beats per-integration features.
- `adr/0003-out-of-process-brain.md` — why the LLM brain is not in the shell.
- `PROTOCOL.md` — the wire format.
- `ROADMAP.md` — M0 through M8.
- `MACOS-CONSTRAINTS.md` — platform rules and permission reference.
