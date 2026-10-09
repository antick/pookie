# M0 Findings

Empirical results from the walking skeleton. Everything here was measured or probed on the machine
below, not assumed. Where something was **not** verified, it says so.

**Environment:** macOS 26.6.2 (build 25G83), arm64, Xcode 27.0, Swift 6.4, two displays
(3840×1620 logical primary, 1440×2560 portrait secondary), development build (`swift build`,
ad-hoc signed, not notarized, not sandboxed).

---

## 1. Resolved

### 1.1 Carbon `RegisterEventHotKey` works with no permission prompt

**Resolved.** Four global hotkeys registered on first launch, no Accessibility or Input Monitoring
dialog, no permission grant:

```
[pookie] bound ctrl-opt-H -> hide/show
[pookie] bound ctrl-opt-P -> cycle mouse mode
[pookie] bound ctrl-opt-D -> describe state
[pookie] bound ctrl-opt-R -> bring home
```

This is why Pookie can offer an unhideable escape hatch on a fresh machine. **Still open:** does this
hold in a notarized, hardened-runtime, sandboxed build? That is an M6 question. Fallback remains
`CGEventTap` with an explicit Input Monitoring prompt.

### 1.2 `CADisplayLink` is available at the macOS 14 deployment target

**Resolved.** `NSView.displayLink(target:selector:)` compiles and runs with
`platforms: [.macOS(.v14)]` and no availability guard. Observed callback cadence ≈53–60 Hz.
`CVDisplayLink` is not needed. Uncertainty register item 6 is closed.

### 1.3 `CGBitmapContext` buffer row 0 maps to the **top** of the CG coordinate space

**Resolved by runtime probe, not assumption.** `CGBitmapContext` draws with a bottom-left origin but
stores row-major from the top, so a naive `buffer[y * width + x]` hit test is vertically mirrored
and silently wrong — the cat would respond to clicks above and below it but not on it.

Rather than hardcode the flip, `MaskRaster.probeRowZeroIsBottom()` fills the bottom half of a 4×4
alpha context at startup and observes where the pixels land. The selftest prints the answer:

```
row 0 of the CGBitmapContext buffer maps to the TOP of the CG coordinate space
  ok   mask reports bottom-half pixel as covered
  ok   mask reports top-half pixel as empty
```

A correctly-indexed mask is then validated against a known half-filled reference, so the indexing
is proven rather than restated.

### 1.4 Click-through: decision made, dependency removed

**Resolved as a design decision; the negative was not proven.**

`docs/MACOS-CONSTRAINTS.md` §3a flagged the open question: does returning `nil` from `hitTest`
forward a click to the app underneath, or does our window swallow it?

We could not prove it either way from this environment — `screencapture` fails
("could not create image from display") because the shell has no Screen Recording permission, so
there was no way to observe a click landing in a third-party app.

**So we removed the dependency instead of gambling on it.** `ignoresMouseEvents` is the mechanism
that provably works, and it is toggled by polling the cursor:

1. `ignoresMouseEvents = true` at rest — the pet is genuinely click-through.
2. Each frame, convert `NSEvent.mouseLocation` into window coordinates.
3. If the cursor is inside the silhouette (dilated, plus a 3 pt hysteresis ring), set it `false`.
4. On leaving, set it back to `true`. Edge-triggered, never set twice with the same value.
5. Never drop the mouse mid-drag, or the cat escapes your hand.

`hitTest` is retained only as a secondary guard, so a click landing in a gap on the frame the cursor
leaves cannot activate the window.

**Deviation from §3c:** the doc recommends polling at 10–15 Hz to save energy. We poll at display
rate instead, because it rides the frame pump that is already running and `NSEvent.mouseLocation` is
a cheap static read. The alternative — a separate 15 Hz timer — would add a second timer and a longer
race window for no benefit. If profiling later shows it matters, decimate to every fourth frame.

**Residual risk:** there is still a one-frame race on entering the silhouette. At ~15 fps idle that
is up to 66 ms. Expanding the hysteresis ring is the mitigation; a first-click-in-the-corner may
occasionally land on the app underneath.

### 1.5 A non-key window still receives mouse drags

**Resolved.** `canBecomeKey = false` + `canBecomeMain = false` prevents focus theft, and mouse events
are still delivered. `acceptsFirstMouse(for:)` returning `true` is required, otherwise the first
click on an inactive window is swallowed to "activate" it and the pet feels dead.

Uncertainty register item 2 is closed. **Caveat:** the drag path is exercised by the headless
selftest (synthetic timestamped drag samples), not yet by a human clicking and throwing the cat.
Confirm by hand.

### 1.6 `NSEvent.mouseLocation` is permission-free

**Resolved.** Used for both look-at-cursor and the pass-through test. No prompt. Uncertainty
register item 3 is closed in favour of polling.

### 1.7 Window geometry is readable with no permission at all

**Resolved.** `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])` returns
owner, PID, layer and bounds for every on-screen window with no Screen Recording prompt, exactly as
`MACOS-CONSTRAINTS.md` §4.3 claimed. Verified on this machine with the new `Pookie --windows` mode:
55 windows listed, 7 of them large enough and at layer 0 to be perches.

Two things the implementation had to get right:

- **The y flip.** `CGWindowList` bounds are top-left-origin with y down; AppKit is bottom-left-origin.
  The conversion is `y = primaryScreen.frame.maxY - cgY - cgHeight`, done in one place
  (`WindowScanner`). A sanity check that it is right: every reported window top lands inside a
  screen's visible frame, and a 300 pt window sitting at AppKit y=62 reports `top=362`.
- **Layer 0 only.** Our own pet window is `.floating` (layer 3), and so is every other Pookie's, so a
  second instance is excluded by the layer filter rather than by the PID filter. That also means she
  only ever perches on *normal* application windows, never on panels, HUDs, or other pets.

Window **titles** (`kCGWindowName`) remain gated behind Screen Recording, and are not read. Perching
is a geometry-only feature, which is why it ships without a permission prompt.

---

## 2. The headline finding: energy

The design doc set a budget of **under ~1% CPU and ~40 MB RSS while idle and visible**. That target
is **not reachable in the M0 architecture.**

Measured with the in-process meter (`getrusage` + `task_info`, exposed under `--verbose`):

| Configuration | Drawn fps | CPU | RSS |
|---|---:|---:|---:|
| No frame tiers (every vsync) | 52 | **26–32%** | 49 MB |
| Idle tier | 15 | **~5%** | 44–49 MB |
| Walking tier | 30 | **~10%** | 49 MB |

Roughly **3 ms of CPU per frame** to rasterise the cat. That is the cost of ~35 separate
antialiased Core Graphics path operations per frame, in software, because `NSView.draw(_:)` is not
GPU-composited.

**Conclusions:**

1. Frame-rate tiers are not a nicety — they cut CPU by ~5× on their own and belong in the product.
2. The `<1%` idle target **cannot** be met by tuning tiers. Even at 8 fps (the sleepy tier) the
   per-frame cost puts it near 2%.
3. **SpriteKit (or Metal) in M1 is the actual fix, not an enhancement.** Moving the cat to a
   GPU-composited renderer is what removes this cost class. This is the single most important thing
   M0 learned, and it is the strongest argument for the M1 renderer swap that
   ADR-0001 already anticipated.
4. A useful interim lever, not yet done: cache the parts that do not change every frame (body, head,
   ears, paws) and redraw only the tail, eyes, whiskers, and mouth per frame. Estimated 40–60%
   saving, but it is real complexity that SpriteKit makes unnecessary. Recommended: measure
   SpriteKit first, optimise the vector path only if the swap slips.

Also confirmed: occlusion pausing fires correctly (`occlusion changed, visible=false/true`), and
`paused=true` frames stop the simulation.

### 2.1 Frame decimation needs slack

A subtle one worth recording. Decimating a ~60 Hz display link to a 30 fps target requires waiting
exactly two vsyncs. With a strict `accumulator >= target`, real timestamp jitter makes the sum fall a
hair short, the third vsync is silently consumed, and the pet draws at 20 fps while the code claims
30.

Fixed with a `* 0.92` tolerance on the threshold. Verified: idle now draws exactly 15.0 fps against a
15 fps tier. Without this the tier system lies about what it is doing, which would have made every
later battery comparison meaningless.

### 2.2 A 90 ms stall, twice a second, hidden in the hit-test mask

The silhouette mask was built with a dilation pass: grow the coverage by one pixel so the cat is
easier to grab. It was rebuilt twice a second while the cursor was near her.

Measured cost of one `MaskRaster.make`, same machine, same 177×160 window:

| Build | With dilation | Without |
|---|---:|---:|
| `swift build -c debug` | **89.8 ms** | 0.4 ms |
| `swift build -c release` | 1.6 ms | 0.4 ms |

A 90 ms stall is five dropped frames at 60 fps, twice a second — and it fires exactly when she is
walking around after being thrown, which is when smoothness is most obvious. `sample` put 20% of the
process CPU inside `MaskRaster.dilate`.

The dilation was also **redundant**: the pass-through test already probes a 3 pt ring around the
cursor, which gives the same tolerance with hysteresis and without a second pass over every pixel.
Deleted. Idle CPU went from 23–30% to 4–5% at the same frame tier, and the stall is gone.

The lesson is not "dilate is slow" — it is that an unoptimised Swift loop over a per-pixel buffer is
invisible in a release profile and fatal in the debug build everyone actually runs.

---

## 3. Bugs the headless selftest caught

Each of these was found by `--selftest` or by the live heartbeat, not by looking at the screen.

| Bug | How it showed | Fix |
|---|---|---|
| Wandering cancelled itself immediately | Travel range over 90 s was 110 pt instead of thousands. The "grounded" predicate tested `abs(vx) < 14`, which the wander's own velocity assignment violated on the very next frame, clearing the target | Groundedness is about altitude only |
| Open mouth rendered on the chest | `mouthOpen` pose drew at design y≈41, but the muzzle is at y≈56 and the head bottom at y=42 | Moved to y≈47.5, under the nose; added a tongue |
| Flung cats flew forever | Live heartbeat showed sustained 300–440 pt/s travel and `alarmed` mood for 20 s+ | Air drag, halving horizontal velocity in ~2 s |
| Cat stranded itself on the second display | `origin` reached x=4434 on the portrait monitor and stayed | Wandering now biases 65% toward the screen under the cursor |
| Tail visually detached from the body | Pose sheet render | Pivot moved inside the body; curve reshaped |
| Ears looked stuck on | Pose sheet render | Ears drawn before the head so the base tucks behind the skull |
| **Tail and ears cut off at the window edge** | Pose sheet and live window; measured ink reached x=0 and y=100 of a 100×100 box | Render stage larger than the art box, pose clamping, and a test that sweeps the whole envelope (§3.1) |
| **A thrown cat fell at 15 fps** | Reported by hand as "frame rates dropped when jumping"; the tier table keyed off mood, and an airborne cat with `|vy| < 700` resolved to `idle` | Tiers key off motion state; up-shifts are immediate (§3.2) |
| **She fell past the first window she spawned above** | The perch pump's first scan was up to a second late, by which time she had fallen past the window top | The pump starts overdue, and scans faster while airborne (§3.3) |
| **Her jumps landed short of the ledge** | Planned as a minimum-energy arc against constant horizontal speed; the discrete integrator peaked below the ledge and air drag ate a fifth of the distance | Aim 82% of the minimum-energy flight time, and integrate the drag term the physics actually applies (§3.4) |

The selftest now asserts fling behaviour on a two-display topology, so regressions in the physics are
caught without a human watching the screen.

### 3.1 The tail and the ears were being cut off

Reported from the pose sheet, and true: the art was drawn into a 100×100 design box that was fitted
to the window with no margin, and the art does not fit in it.

Measured with an offscreen probe that renders the design box at 1 pt = 1 design unit and reports the
ink bounding box:

- the swaying tail reached design **x = 0.0** — flush against the window edge, and past it once the
  landing squash scaled the body horizontally by 1.26 about x=50;
- the ear tips sat at **y = 98.25**, so a 3.2 pt walking hop or a 1.2× landing squash put them over
  the top edge;
- the mirrored tail hit x = 100 for a left-facing cat.

Three changes, in order of how much they mattered:

1. **A stage, not a box.** `CatGeometry.stage` is the design-space rect the renderer fits into the
   view: `x[-18, 118] y[-2.5, 120.5]`, symmetric about x=50 so a left-facing cat has exactly the same
   room as a right-facing one. The window is derived from the stage (`stage × 1.3`), so the two
   cannot drift apart.
2. **A declared render envelope.** `CatPose.RenderLimits` is a contract: the renderer clamps every
   pose to it, motion code asks for no more than it, and the stage is sized for it. A producer
   sending a wild pose gets a slightly tamer cat rather than one with an ear sliced off.
3. **A test that cannot be fooled.** `--selftest` sweeps the envelope, rasterises 370 poses at the
   real window size, and fails if any ink lands in the window's outer ring. Alongside it, an analytic
   worst case transforms ~3000 ink boundary samples through every corner of the pose-transform box.
   Both must pass. The first version of the analytic check transformed the ink's *bounding box*
   instead of the ink, over-estimated the envelope by ~10 design units, and would have shrunk the cat
   for nothing.

The tilt pivot also moved from the feet to the body centre. Pivoting at the feet swings the long, low
tail sideways, which cost ~10 design units of stage width for an identical-looking lean.

### 3.2 The frame-rate drop when she was thrown

Also reported by hand, and also real. Frame tiers picked the interval from `mood`:

```
dragging → 60 fps | walking/alarmed/curious → 30 | sleepy → 8 | idle → 15
```

An airborne cat only resolves to `alarmed` while `|vy| > 700`; the rest of the flight it is `idle`,
so a tossed cat fell at **15 fps**. Two further problems compounded it: the 0.4 s debounce was
applied to up-shifts as well as down-shifts, so a drag spent its first 0.4 s at the idle tier, and
the landing squash animated at whatever tier she landed in.

Tiers now key off motion state, not mood:

```
dragging or airborne → display rate | landing squash or hovered → 30 | then mood
```

Up-shifts are immediate; only slowing down is debounced. `PetWindowController.desiredInterval` is
exposed so the selftest asserts the table directly, including "a thrown cat never falls at the idle
tier", and that a released cat actually reaches `isAirborne` rather than trusting the flag.

### 3.3 Perching: the first scan has to be early

Landing on a window top is one-way — a window only counts as a floor if she is already above it —
which is what stops her being launched onto the top of every window she walks in front of. The
consequence is that the platform list must be current *before* she falls past a window.

The first version scanned on a one-second idle interval, so she spawned above a window, fell for up
to a second with no platforms known, and dropped straight past it. The pump now starts overdue (so
the first frame scans) and re-scans every 0.2 s while she is airborne and every 0.1 s while perched,
which is also what makes riding a dragged window smooth. Verified end-to-end against a real moving
window: she landed on its top edge and tracked it across the screen at the same speed.

### 3.4 Jumping onto windows: two ways to land in the wrong place

She now plans her own leaps onto reachable window tops. The planner is a pure function
(`PetMotion.planJump`), which is what let the selftest ask what she *would* do without making her do
it. It picks a ballistic arc, and it took two corrections before the arc landed where it aimed.

**Correction 1: a minimum-energy arc never arrives.** The obvious plan is the flight time
`T = sqrt(2·rise/g)`, the one that arrives at the ledge with zero vertical velocity — the least
energy possible. On paper she touches down exactly on the ledge. In practice the simulation
integrates semi-implicitly, so she peaks a few points *short* of the analytic apex:

```
analytic apex = v²/2g = 362 pt     discrete apex ≈ 362 − v·dt/2 = 351.7 pt
```

She never reaches the ledge, falls back to the floor, and the whole feature looks broken. Aiming at
82% of that flight time puts the apex above the ledge and lands her on the way down, with about 10 pt
of clearance at the top of her range.

**Correction 2: air resistance eats a fifth of the horizontal distance.** The physics damps
horizontal velocity by `0.72^t` — that is what stops a flung cat ricocheting across every display.
The planner assumed constant horizontal speed, so every leap landed short:

```
aimed at dx = −304 pt, landed at −246 pt
```

The planner now integrates the same decay the physics applies, `∫₀ᵀ 0.72^t dt`, instead of assuming
`dx = vx·T`. Both constants are shared with the integrator, so they cannot drift apart. Verified: she
lands within 12 pt of her aim (usually exactly on it), and the selftest asserts it.

**The visibility rule.** A ledge is only a candidate if the whole cat fits on it *and* on the screen
that owns it: the usable landing x-range is the intersection of the ledge's span and the screen's
visible frame, and it has to be non-empty. A window top tucked against the edge of a display, or
narrower than the cat, is skipped rather than jumped at — which is the difference between a pet that
perches somewhere sensible and one that wedges half off the screen.

**Reach is sized to the real problem.** The first cap was 620 pt, which sounds generous (four times
her height) and reaches *nothing*: window tops on a 1620 pt display sit 700–1100 pt above the floor,
so she could not get onto a single window. The cap is now 1050 pt, roughly six times her height,
which is what a real cat manages. Windows higher than that are reached by climbing: she jumps to a
lower window, then to a higher one, which is what she was observed doing on a real desktop.

``` 
jumps=1  perch=WindowManager#196  origin=(25, 708)
jumps=2  perch=WindowManager#465  origin=(58, 1042)
```

Both of those windows were then moved by the user's window manager, and she rode them — the ride
path and the jump path composing without either knowing about the other.

---

## 4. Multi-display notes

`NSScreen.screens` correctly reported both displays with their visible frames
(`{0, 62, 3840, 1528}` and the portrait monitor). Geometry is tracked and re-read on
`didChangeScreenParametersNotification`.

**Known edge case:** a point that falls in the seam between two displays matches no screen's visible
frame, so `Desktop.region(containing:)` falls back to nearest-by-centre. Near a seam at high altitude
the chosen region can flip between displays with different floors and ceilings, and the wall clamp
can bounce the pet off the boundary. Low severity — it self-corrects — but the fallback should
prefer the *previous* region when the point is within a few points of it. **Fixed:** it now does.

---

## 5. Not yet verified

Stated plainly so they are not mistaken for done:

1. **Human interaction.** Drag, fling, tapping, and click-through-with-gaps have been exercised
   headlessly, by a synthetic timestamped drag, and by the author of the code — not by a person
   clicking the cat on screen. `screencapture` now works from this shell, so `shots/talking.png` and
   `shots/perching.png` are real screenshots of the live window (pet, bubble and all); the
   interaction itself is still unverified by hand. Perching, riding and autonomous jumping *were*
   observed live against real windows (log evidence in §3.3–3.4), including a window manager
   repositioning the windows she was standing on.
2. **The `hitTest` negative** (§1.4). We designed around it rather than proving it.
3. **`sharingType = .none`.** Implemented and toggleable, never tested against a real screen-share
   or conferencing client. Uncertainty register item 4 remains open, and the docs already warn never
   to promise capture-invisibility.
4. **Fullscreen behaviour.** `.canJoinAllSpaces` + `.fullScreenAuxiliary` + `.floating` is configured,
   but "does the pet appear over a fullscreen video, and does the `.statusBar` escape hatch work"
   has not been tested against a real fullscreen app.
5. **Notarized/sandboxed build.** Everything measured here is an unsigned development binary. Hotkey
   registration, the `--say` distributed-notification bridge, and permission behaviour must be
   re-checked after notarization (M6/M8). The bridge is the most likely casualty: a sandboxed app is
   restricted in which distributed notifications it may observe.
6. **Sleep/lock suspension.** `ProcessInfo` activity holds and screen-lock suspension are designed
   but not implemented.
7. **Bubble edge cases.** The flip-below-her-when-there-is-no-room-above path is unit-tested by
   geometry, not observed on screen; and no bubble has yet been seen on a display other than the
   primary.
8. **Perching while the window changes Space.** Riding is verified for a window being dragged across
   one display. What happens when the host window moves to another Space (and the pet follows it via
   `.canJoinAllSpaces`) is untested.
