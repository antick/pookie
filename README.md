# Pookie

A cat that lives on your screen. Transparent, always on top, rides every Space, and **never steals
focus**. She breathes, blinks, watches your cursor, wanders, sits, tucks her paws under into a loaf,
dozes off, and stretches when she wakes — and she can be picked up and thrown, lands on the top edges
of your windows, **jumps up onto them by herself**, climbs from one window to a higher one, rides them
when you drag them, and talks in a speech bubble. Ask for more and you get a **menagerie of up to
five** — a cat, a bunny, a puppy, a fox and a panda — running around, chasing each other, and having
the occasional undignified scuffle.

![Pookie pose sheet](shots/poses.png)

```
row 1: say (plain) | info card | success | warning
row 2: neutral | blink | curious + blush | facing left
row 3: sleepy  | walking | alarmed | talking
row 4: sitting | loafing | lying asleep | waking stretch
row 5: settling stand->sit | sit->loaf | loaf->lie | lie->stretch
row 6: blinking out 30% | 60% | 90% | and back in
```

Rows 4 and 5 are the posture work: four resting shapes and the mid-settle frames between them. They
are not sprites — every shape is a table of anchors, and the renderer draws the *blend*, which is why
she eases down into a loaf instead of cutting to one. See
[`CatAnatomy.swift`](Sources/Pookie/CatAnatomy.swift). Row 6 is the teleport blink, drawn from the
same one number the behaviour plays.

A species is a table too. Every animal shares that skeleton and those animations, and differs only in
its proportions and appendages — so all five perch, jump, loaf, stretch and blink identically:

![Five species](shots/species.png)

![Pookie talking on the desktop](shots/talking.png)

## Try it

```bash
make run          # build and launch with verbose logging
make selftest     # headless checks: bitmap layout, art envelope, physics, postures, perching, speech
make poses        # re-render shots/poses.png
make open         # assemble and launch Pookie.app
```

With Pookie running, from any shell:

```bash
./build/Pookie.app/Contents/MacOS/Pookie --say "hi"
```

Requires macOS 14+ and Xcode command line tools. No third-party dependencies.

> **Note:** `make` passes `--disable-sandbox` to SwiftPM. SwiftPM wraps manifest compilation in
> `sandbox-exec`, which is unavailable in some restricted shells. There are no external packages, so
> nothing untrusted is being compiled.

## Playing with her

| Action | Result |
|---|---|
| Drag the cat | She follows the cursor and tilts into the motion |
| Let go while moving | She is flung, falls, bounces, and squashes on landing |
| Move your cursor near her | She looks at it; her pupils track it |
| Leave her alone | She wanders, sits, blinks, flicks an ear, and eventually falls asleep |
| Leave her still on a window edge | She tucks her paws under and loafs |
| Leave her alone for a minute or two | She sits down, then lies down and sleeps |
| Move the cursor once she is asleep | She stretches and yawns, then goes back to standing |
| Move to another screen | She trots back to the screen you are working on |
| Leave her on a multi-monitor desk | She spins down into a poof of light and fur and reappears on the other display |
| Drop her above a window | She lands on its top edge and sits there |
| Leave her on the floor | She gathers, leaps, and lands on a reachable window top herself |
| Leave her on a perch | She hops up to a higher window if one is in reach |
| Drag that window | She rides it, rather than sliding off |
| Walk her off the window's end | She falls back to the desktop |
| Click her | She says something (rate-limited, and mutable) |
| Run `Pookie --say "..."` | She says it in a bubble |
| Add a cat from the menu | A new cat arrives, in her own coat, and starts exploring |

![Pookie perched on a window edge, talking](shots/perching.png)

Perching and jumping are geometry-only: she reads the top edges of normal windows with
`CGWindowListCopyWindowInfo`, which needs **no Screen Recording permission** and never reads window
titles. Only layer-0 windows count, so panels, HUDs, and other pets are not perches.

She only jumps at a ledge she can actually use: the whole cat has to fit on the ledge *and* on the
screen, so a window top tucked against the edge of a display — or narrower than she is — is ignored
rather than jumped at. Reach is capped at about 1050 pt (roughly six times her height, which is what
a real cat manages), so a window near the top of the screen is out of reach from the floor, and she
will climb up through lower windows to get there. She prefers the window of the app you are actually
using, which is permission-free too: `NSWorkspace.frontmostApplication`.

Global hotkeys, **no Accessibility or Input Monitoring permission required**:

| Shortcut | Action |
|---|---|
| `control-option-H` | Show / hide Pookie |
| `control-option-P` | Cycle mouse mode: click-through gaps → capture whole box → ignore mouse |
| `control-option-R` | Bring Pookie home |
| `control-option-D` | Print her state to stderr |
| `control-option-T` | Say hello (test the speech bubble) |
| `control-option-M` | Mute / unmute her reactions |

### Where your settings live

In `~/Library/Preferences/com.pookie.pet.plist` — the standard macOS preferences file for the app's
bundle identifier, written through `UserDefaults` (so `defaults read com.pookie.pet` shows you
everything, and `defaults delete com.pookie.pet` is a factory reset). It holds the roster — kind,
coat and name for each pookie — plus the pookie boss, the size, the teleport cadence and every
switch in the menu. Nothing else is stored anywhere: there is no database, no cache directory and no
file in `Application Support`. Positions, moods and everything else about the moment are deliberately
not saved; M8 owns the full preferences store.

**Right-click any pookie** for a menu about *that* one: bring it home, make it the one that answers for
Pookie, **hide it** (or show it again), or remove it from the desk. Hiding is per pet — the animal you
clicked, not the newest one — and a hidden pet costs nothing: its window is ordered out, its behaviour
stops, and the frame budget it was holding goes to the ones still on screen. Hidden pets stay in the
roster, so they come back with their species and coat when you show them.

The pawprint in the menu bar has the rest: **size** (small to extra large), **teleport between
displays** and **teleport every** (1–30 minutes), **add a pookie**, **Pookies** (each pet's kind,
coat, visibility, removal and who answers for Pookie), **hide all pookies** / **show all pookies**,
mouse mode, wander, cursor tracking,
sit-on-windows, jump-onto-windows, speech, hide-from-screen-sharing, float above fullscreen apps, and
quit. A pet you cannot easily quit is a pet you will resent.

Size is a real size change rather than a zoom: the window, the drawing and the behaviour geometry all
scale together, so a bigger Pookie still fits on the ledge she jumps to, still picks wander targets in
her own units, and still stands *on* the window top she is perched on. Teleporting is off with one
display and does nothing unless you leave it on: with two or more she waits a jittered minute, spins
down into a small poof of warm light and her own fur, and reappears somewhere on the other display —
arriving from above, so she lands on whatever window top is under her rather than in front of one. The
departure and the arrival are separate animations, with the hop itself happening while she is not on
screen to see it.

She stands on things, not above them. Her window's bottom edge is deliberately *below* the line her
feet are on, so a leaning paw or a wrapped tail is never clipped — which used to show up as a visible
gap above every window top she perched on. `--selftest` measures the real ink and fails if it drifts
off the floor line, at every size setting.

Click-through is a real toggle, and it matters: in the default mode she is transparent to the mouse
in the gaps around her body, so she never blocks a click on the window behind.

## More than one pookie

The menu bar has **Add a pookie ▸** (pick the animal) and **Remove a pookie**, and `Pookie --pets 5`
starts with five. Five is the cap — one of each animal — and there are five to choose from:

| Animal | What makes it read | Its coat |
|---|---|---|
| **Cat** | the original, unchanged | Tabby |
| **Bunny** | tall pink-lined ears on a small round body, cotton tail | Snow |
| **Puppy** | big floppy ears that hang, wide muzzle, curled tail | Chocolate |
| **Fox** | pale-lined ears, a white snout and cheek ruff, dark socks, and a *filled* brush tail with a pale tip — not a cat with pointy ears | Ginger |
| **Panda** | black ears, eye patches and paws on a white body | Panda |
| **Duckling** | no ears, an orange bill, webbed orange feet, and wings that **flutter as it walks and flap in the air** | Duckling |
| **Bear** | a big round body, button ears and a broad muzzle | Cocoa |
| **Hamster** | the smallest of them, with fat cheeks either side of the muzzle | Hazel |

**One of each animal at a time**, which is what makes the desk read as a gang rather than a
duplicate: adding a second bunny is not offered, and a saved roster with a duplicate is repaired on
load (the second bunny becomes the next animal nobody is, keeping its coat and name). A *coat* is
the free choice — any animal can wear any of the fourteen, so two pookies never have to look alike.

**Every pookie has a name**, and one of them is the **pookie boss** — the one that speaks when a
producer sends a line. **Pookies ▸ N ▸** renames one, changes its kind or coat, promotes it to boss,
hides it or takes it off the desk; right-clicking a pookie offers the same things.

**Pookies ▸** in the menu is where you decide what is on the desk: for each pet, pick its **kind** and
its **coat** (eleven of them, and any animal can wear any coat), and mark one as the one that
**answers for Pookie** — the pet a producer's line goes to. Those choices are saved, so the menagerie
you build is the menagerie that loads next time, along with the size, the switches and the teleport
cadence. Launch flags (`--no-wander`, `--scale`, …) are overrides for one run and never rewrite what
you saved.

They all have everything the first cat has — perching, jumping, teleporting, loafing, stretching — and
they know where each other are. Two who end up on the same spot step apart rather than stacking. When two of them **stay within a paw's length for three seconds**, they have a **brawl**: 1.6–3
seconds of flattened ears, wide eyes, a hop under each swing, and a **one-two of thrown paws** —
alternating, with a comic burst of lines where each lands and a bubble that says `POW!` or `*bap bap*`.
They lean into each other while it lasts (the rule that normally keeps them a body apart is relaxed, or
they could never touch), and they close the gap first if they are just out of reach. It takes three
seconds of company on purpose: two animals who happen to walk past each other are not fighting.

When they are further apart, one **chases** the other instead — a 2.5–5 second bout at a run, wearing
the happy face — and a chase that closes the distance turns into a brawl. No animal perches on another
animal.

Five pookies are real work. They share one frame budget — 120 drawn frames per second between them, so
one pet is unaffected and five get 24 fps each — and an occluded pet stops entirely. The honest numbers
on this renderer (software Core Graphics, a 3840x1620 display):

| Pookies | CPU, idle | RSS |
|---:|---:|---:|
| 1 | ~7% | 52 MB |
| 3 | ~13% | 56 MB |
| 5 | ~17% | 60 MB |

That is 2.4x the cost of one pet rather than 5x, and the remaining cost is the same M1 problem the
first cat already had: the fix is the SpriteKit renderer, not a smaller cap. Idle is the number that
matters for a desktop pet, but for the record: five of them awake, wandering and scrapping measure
around 25%.

Five is also a *default you can change*, not a floor. If the menagerie is more company than you want,
**Remove a pookie** takes it down to one, and the choice persists.

### Teleporting

Off with one display, and nothing happens unless you leave it on. With two or more, each pet waits a
jittered interval — **Teleport every** in the menu sets the cadence to 1, 2, 5, 10 or 30 minutes — then
spins down into a small poof of warm light and its own fur, and reappears somewhere on another display.
Leaving and arriving are separate animations, with the hop itself happening while the animal is not on
screen to see it. The jitter is what stops five of them blinking in unison.

## Talking to her

The bubble is one borderless, transparent, non-key window anchored above her head. It flips below her
when there is no room, and clamps inside the screen rather than running off an edge. One bubble at a
time; a second line inside the minimum gap is refused rather than stacked.

Three ways to make her talk today, all of which end at the same call:

```bash
Pookie --say "build passed"          # from a shell (distributed notification)
```

```swift
controller.say("build passed", style: .success)   # in-process
controller.appendToBubble(" more text")           # streaming
controller.hideBubble()
```

```json
{"verb": "say", "args": {"text": "build passed"}}  // the M3 wire protocol, not built yet
```

`Pookie --say` uses `DistributedNotificationCenter`, which is permission-free and needs no server. It
is a stand-in for the M3 loopback protocol: the receiver already calls
`PetWindowController.say(_:)`, so wiring the real socket changes the transport, not the pet.

Styles: `plain`, `info`, `warning`, `success`, `code`. `SpeechEngine` owns the rules — silence by
default, one bubble, length-derived dismiss timer — and is pure logic, so the selftest drives it
without a window server.

## Layout

```
Sources/Pookie/
  main.swift               entry point, headless modes, --say bridge
  AppDelegate.swift        status item, hotkeys, menu
  PetWindow.swift          borderless window that can never become key
  PetWindowController.swift  window policy, frame clock + tiers, perching, bubble placement
  PetCohort.swift          the colony: population cap, shared frame budget, play, settings fan-out
  PetView.swift            drawing, mouse input, pass-through, hit testing, taps
  PetMotion.swift          physics and behaviour — no AppKit, fully testable
  CatAnatomy.swift         the five shape keyframes, and the blend between them
  CatRenderer.swift        the cat, drawn procedurally, and the stage it is fitted into
  PetRenderer.swift        renderer protocol + silhouette rasteriser
  PetPose.swift            the pose value type, palettes, and the render envelope
  BubbleWindow.swift       the speech bubble window + Core Text layout
  Speech.swift             say / bubble.show / bubble.append / bubble.hide, no AppKit
  WindowScanner.swift      other apps' window tops, and the pump that rides them
  GlobalHotKey.swift       Carbon hotkeys (permission-free)
  Support.swift            geometry, logging, in-process CPU/RSS meter
  Diagnostics.swift        --selftest, --render-png, --windows

docs/
  DESIGN.md                architecture, intent vocabulary, animation ladder
  PROTOCOL.md              the control-plane wire format (M3/M4)
  ROADMAP.md               M0 through M8, with acceptance criteria
  MACOS-CONSTRAINTS.md     window, permission, and platform rules
  M0-FINDINGS.md           what M0 measured, what it broke, what is unverified
  adr/                     why Swift, why a verb protocol, why the brain is out-of-process
```

## Architecture in one paragraph

**The pet is a renderer, not an app.** Pookie knows about twelve verbs — `say`, `emote`, `moveTo`,
`lookAt`, `face`, `state`, `bubble.show/append/hide`, `spawn`, `despawn`, and an event stream back —
and nothing else. Any producer (Codex, Claude Code, a shell script, CI, your calendar) emits those
intents; the pet renders them. Four of them (`say` and the three `bubble.*` verbs) are implemented
in-process today, behind `SpeechEngine`, and `spawn` / `despawn` exist as an in-process colony with no
wire protocol behind them yet; the rest are the M2/M3 work. A behaviour priority stack
decides who wins: `drag(100) > say(60) > follow(40) > idle(0)`, so idle wandering can never interrupt
a sentence. That is what turns a pet into a platform instead of a pile of one-off integrations. See
[DESIGN.md](docs/DESIGN.md).

## The M0 result worth knowing

The design set an energy budget of under ~1% CPU while idle. **M0 does not meet it, and the reason
is architectural.** Measured with the built-in `--verbose` meter:

| Configuration | Drawn fps | CPU | RSS |
|---|---:|---:|---:|
| No frame tiers | 52 | 26–32% | 49 MB |
| Idle tier | 15 | 4–5% | 44–51 MB |
| Walking tier | 30 | 10–15% | 49 MB |

Roughly 3 ms of CPU per frame to rasterise ~35 antialiased Core Graphics paths in software (the
per-frame draw itself is now 0.4 ms; the rest is window movement and compositing). Frame tiers cut it
~5×, but no amount of tuning reaches 1%. **The fix is the M1 SpriteKit renderer**, which moves the
cat onto a GPU-composited path. That swap is not a nice-to-have; it is the thing M0 was built to
discover. Full write-up in [M0-FINDINGS.md](docs/M0-FINDINGS.md).

## Testing

There is no human in the loop for correctness:

```bash
make selftest
```

runs 288 headless checks, including:

- **five species on one stage**: every animal is swept through the whole art envelope — keyframes,
  mid-settle blends, the teleport twist — and checked against the stage, plus its own ground contact,
  its own proportions and a coat nobody else is wearing. This is what caught a panda whose body grew
  through the floor and a fox whose brush swung off the side of the world;
- **brawls**: that two seconds of company is not yet a fight and three is, that the paws alternate like
  a one-two with a comic hit on each swing, that they lean in rather than being pushed apart, that
  walking past somebody is not a fight, and that a sleeping or held animal is not drawn into one;
- **the settings**: the teleport cadence offers minutes and lands where it says, and the roster
  survives being written to the settings store and read back — including dropping a corrupt entry
  rather than guessing at it;
- **the right-click menu**: that it offers to hide *the pet you clicked* rather than the newest one,
  that a hidden pet's menu offers to show it again, that the last pet cannot be removed, and that
  hiding is free — a hidden pet stops moving and stops holding a share of the frame budget;

- the `CGBitmapContext` row order, probed at runtime rather than assumed;
- **the teleport blink**: it leaves before it moves — half way out she is part way gone and has not
  moved, the hop happens while she is off screen, and she spins back in with a landing squash. The
  twist is also swept through the art envelope at twenty-five steps, because it is the one pose the
  deformation limits do not cover;
- **a colony of cats**: ten different coats for the ten the cap allows, the cap itself, and the frame
  budget dividing down to a floor at the sleep tier. Two cats who start on the same spot step apart
  to exactly one personal space, a bout sends a cat running at her playmate with the happy face on,
  and play is refused while she is asleep or in your hand;
- **the art envelope**: every pose in the declared deformation range — and every shape keyframe and
  the blends between them — is rasterised and checked for ink touching the window edge, plus an
  analytic worst case over the pose transform. This is what caught the tail and ears being cut off,
  and what pins the lean limit the resting shapes are damped by;
- **the floor line**: at every size setting, the lowest ink in the window is measured and compared
  with the offset the window is drawn at. This is the "she hovers a few points above every window she
  perches on" bug, and it fails if the two ever drift apart;
- **the gaze**: with her walking away from the cursor, her pupils still point at it — the aim is
  smoothed in screen space and converted into the design space the flip mirrors. The renderer half is
  pinned too: the same offset has to land on opposite sides of her head depending on which way she
  faces;
- **the resting shapes**: every shape keeps a paw or a belly on the ground line, a half-settled loaf
  is the exact average of the two keyframes it blends, and a settle never moves an anchor more than
  half a design unit in a frame — so a posture change is a morph, not a hard cut. The awkward case
  is pinned too: she starts sitting down, dozes off before it finishes, and still does not pop;
- **the rest ladder**: still on a perch means a loaf, idle for a minute means a sit, minutes mean a
  lie, and the floor is not a perch. Waking up always stretches, and only once per idle period;
- the physics on a two-display topology — settling, wandering bounds, a 2500 pt/s fling;
- perching: landing on a window top, one-way platforms, falling off an edge, riding a moving window,
  and the pump cadence that makes the first scan happen before she falls past anything;
- jumping: that she plans a leap, crouches, lands on the ledge *where she aimed*, climbs, and that a
  ledge she could not stand on fully visible — or could not reach — is never a jump target;
- teleporting: that it is off when the setting is off, that one display has nowhere to go, that she
  arrives inside the other display *and on a window top there*, and that she never blinks out of your
  hand;
- resizing: that growing or shrinking her keeps her feet on the same line and her middle where it
  was, rather than sliding sideways;
- the frame-tier table, including the regression where a thrown cat fell at the idle tier;
- the speech engine: rate limiting, TTL expiry, streaming appends, muting;
- bubble layout: text measured, wrapped, and rasterised headlessly;
- taps: a click in place is a pet, a drag is a throw.

`make poses` renders the pose sheet offscreen, so the artwork can be reviewed without Screen
Recording permission. `Pookie --windows` prints the perches she can currently see, in screen
coordinates — useful when a window does not behave the way you expect.

## Status

M0 complete. On top of it: the **clipping bug** (tail and ears cut off by an over-tight render box)
is fixed and now enforced by a test; the **frame-rate drop** when she is thrown is fixed (a thrown
cat used to fall at the 15 fps idle tier, and a 90 ms mask rasterisation stall hit every half
second while she walked); she **perches on and rides other apps' windows**, **jumps up onto them by
herself**, and **talks** in a speech bubble.

She also **stops standing**. Four resting shapes — sit, tucked-paw loaf, lie, and the waking stretch
— are blendable anatomy tables rather than sprites, so she eases into them and out of them, and a
small rest ladder decides when: a loaf after a long perch, a sit before sleep, a lie while asleep,
and a stretch and yawn on waking or after a long idle. Because a posture is drawn as a weighted
average, changing her mind half way through a settle cannot pop. That "she only ever stands" line is
closed; what remains of **M1** is the SpriteKit renderer, cached geometry, and the rest of the idle
micro-behaviour scheduler.

She is also now **yours to place**: a size setting in the menu (small to extra large, a real size
change rather than a zoom), an optional blink to another display on a multi-monitor desk, and — the
bug worth naming — her feet are finally **on** the things she stands on. The window used to be
anchored with its bottom edge at the physics floor while the art kept a margin below her paws for a
leaning pose, so she hovered about seven points above every window top she perched on. The window now
hangs below the floor line by exactly that margin, and the selftest measures the ink to prove it, at
every size.

![Pookie's feet on the window ledge, before and after the floor fix](shots/feet-on-the-floor.png)

Her eyes no longer look the wrong way. The gaze was aimed in screen space and stored in the design
space that the facing flip mirrors, so a cat facing left — walking away from the pointer, being
carried, or with the cursor close enough that she had not turned — tracked it backwards. The aim is
now smoothed in screen space and converted once on the way into the pose, which also keeps her pupils
on the pointer *through* a turn instead of sweeping across it. The selftest drives both halves: the
behaviour, and the renderer's mirror.

And there is **more than one of her** — in fact more than one *animal*. Up to five pookies live
under one shared budget: a cat, a bunny, a puppy, a fox and a panda, each with its own coat and size,
each with every capability the first cat has, stepping out of each other's way, chasing each other
across a display and having the occasional scrap when they get close. What is on the desk, what each
one is, and how often they blink between displays are all settings, and they are saved between
launches. That is the in-process half of M8's `spawn` / `despawn`; the wire protocol will be able to
drive it for free once M3 lands, because the verbs already exist on paper.

Next is **M1**: SpriteKit renderer, cached geometry, and the remaining animation states. Then
the rest of M2 (preemption stack, attention budget, streaming from the wire), M3 (the CLI control
plane — the hinge that unlocks everything), M4 (MCP, so coding agents can drive her), and beyond.
See [ROADMAP.md](docs/ROADMAP.md).

Deliberately not done: she does not listen to your microphone, read other apps' notifications, or run
an LLM in-process. Those are decisions, not omissions.
