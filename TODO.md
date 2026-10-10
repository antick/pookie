# TODO

What is left, in the order I would do it. `docs/ROADMAP.md` has the milestone
detail and the acceptance criteria; this file is the working list — the things
that are *not* done, why they are not done, and what "done" means.

**A finished item is deleted from this file, not ticked off.** The history lives in
`git log`, in `docs/ROADMAP.md`'s milestone statuses and in `docs/DESIGN.md`, so
anything still in here is still open. An empty section is a good sign.

Last audited against every place this repo records unfinished work: the roadmap's
"Outstanding" lines, `M0-FINDINGS.md` §5 "Not yet verified" and its "New unknowns",
`MACOS-CONSTRAINTS.md` §11, `DESIGN.md`'s "New unknowns", and the code itself for
stubs and dead ends. Three sweeps have each found items the previous one missed, so
the method matters more than the memory: **sweep the docs, do not recall them.**

## 1. The renderer swap (M1 criterion 1)

- [ ] **A layer-backed renderer behind `PetRenderer`** (M1 criterion 1). Worth
      doing on its own merits — the software raster is 1–7 ms a frame and it is the
      last piece of M1 — but **not because of the stutter.** An experiment settled
      that: drawing is 1–2 ms in every configuration, the window is already
      configured as cheaply as AppKit allows (`isOpaque = false`, `hasShadow =
      false`, `animationBehavior = .none`), and the stage is already tight to the art
      envelope, so there is no margin to reclaim. See the next item for what the
      stutter actually is.
      *Done when:* the pet is drawn into a `CAMetalLayer`/`CALayer` on one surface,
      and `worst=` (slowest draw) is lower than it is now under the same load.
      *Needs:* nothing. `worst=`, `masks=` and `slip=` are already in the heartbeat.

## 2. The control plane, which unlocks three other milestones

- [ ] **`bubbleClicked`, and the click-to-event path end to end.** The event stream
      landed (`pet.on`, `clicked`, `dragged` coalesced to 10 Hz, `dropped`, `petted`,
      `["*"]`, per-connection filtering, the handler label) and is tested against a real
      socket. What is *not* done: the bubble is click-through by design, so
      `bubbleClicked` cannot fire, and the path from a **real** mouse click to a
      subscribed client has only been proven by construction and by the tests — nobody
      has clicked the pet with `pookie events` running. `pookie events` exists to make
      that a one-minute check.

- [ ] **M4 — an MCP server**, one tool per verb, so Codex and Claude Code can
      animate the pet with no bespoke integration. The adapter must contain no
      behaviour logic beyond translation. *Needs:* M3.

- [ ] **M5 — an LLM brain** as a separate local process that starts, stops and
      restarts independently, streams tokens into a bubble, and never blocks the
      render loop. *Needs:* M3.

- [ ] **M7 — reactive skill packs**: declarative documents binding triggers to
      intents (`on git commit → emote(sparkle)`). *Needs:* M3/M4.

## 3. M2's remaining criteria

All four need M3's transport to be meaningful:

- [ ] Criterion 3 — wire streaming (`bubble.append` over the protocol).
- [ ] Criterion 4 — the preemption stack (priority override).
- [ ] Criterion 5 — TTL evaluated at dispatch, not at arrival.
- [ ] Criterion 7 — every rate-limit and preemption decision logged with a
      reason, so "why did my line not appear" has an answer.

## 4. Voice (M6)

- [ ] STT via `whisper.cpp`, locally, with no audio leaving the machine.
- [ ] TTS via `AVSpeechSynthesizer`, with a voice option and a mute.
- [ ] Push-to-talk on a global hotkey that works **without** prompting for
      Accessibility.
- [ ] Microphone captured only while the hotkey or a visible affordance is
      active; no always-on listening; the pet ducks its own idle behaviour while
      listening and does not talk over the user.

## 5. Release (M8 criterion 4)

- [ ] **A signed, notarized DMG.** `make bundle` produces an unsigned app;
      Gatekeeper warns on a clean machine until somebody with an Apple Developer
      certificate signs and notarizes it. This is a release process, not code.
      *Then re-check:* global hotkey registration, the `--say` distributed
      notification bridge, and permission behaviour. M0's findings call the
      bridge the most likely casualty of sandboxing.

## 6. Open questions from the uncertainty register

`docs/MACOS-CONSTRAINTS.md` §11 is the register; these are its entries that are
still open, and they are here because a register nobody reads is a register nobody
closes. Entries that were closed — the `hitTest` negative, the mouse-moved monitor,
`CADisplayLink` availability, the seam-gap fallback — are struck through in the
register itself, not here.

- [ ] **Item 7 — the fullscreen-geometry heuristic.** Whether detecting "a
      full-screen app is in front" by window geometry gives acceptable false
      positives is unanswered, because the heuristic was never implemented. Keep it
      configurable and default off if it is.
- [ ] **Item 8 — MCP notifications.** Whether an MCP server can push notifications
      to Codex and Claude Code is untested; assume a `pookie_poll_events` tool is
      required until it is tested. Belongs with M4.
- [ ] **Item 4 — capture exclusion.** `sharingType = .none` has never met a real
      screen-share client. Also listed in §7 as a check for a human.
- [ ] **Item 5 — the hotkey in a notarized, sandboxed build.** Carbon
      `RegisterEventHotKey` works with zero prompts in a dev build; re-check after
      notarization. Also listed in §5.

## 7. Verified by hand, not yet by a test

The suite is headless and this project takes no Accessibility permission, so
these are honestly "reviewed and reasoned" rather than proven. Each one is a
five-minute check for a human:

- [ ] **Throw a pookie for real.** The drag and fling path is exercised by the
      selftest with synthetic timestamped samples, never by a human picking one up
      and throwing it. M0's uncertainty register has been open on this since the
      beginning.
- [ ] **A real screen share.** `sharingType = .none` is implemented and toggleable
      and has never met a real conferencing client. Do not promise
      capture-invisibility until this is checked.
- [ ] **A real full-screen app.** `.canJoinAllSpaces` + `.fullScreenAuxiliary` +
      `.floating` is configured; whether the pet appears over a fullscreen video,
      and whether the `.statusBar` escape hatch works, is untested.
- [ ] **The settings window's controls.** Verified by unit tests on their data and
      by log lines (`settings: 5 in the collection, 3 on the desk`), not by
      clicking every control. Same for the menu-bar items and the right-click
      menu.

## 8. Not yet verified, from M0's findings

`docs/M0-FINDINGS.md` §5 is the list; these are its entries that are still open and
not already covered above.

- [ ] **Bubble edge cases.** The flip-below-her-when-there-is-no-room-above path is
      unit-tested by geometry and has never been *seen*; and no bubble has been
      observed on a display other than the primary.
- [ ] **Perching while the host window changes Space.** Riding is verified for a
      window dragged across one display. What happens when the window moves to
      another Space — the pet joins every Space, but the platform list is built from
      `optionOnScreenOnly`, so the window may vanish from the list and reappear —
      is untested. `DESIGN.md` "New unknowns" item 8.
- [ ] **The `hitTest` negative.** Register item 1: whether returning `nil` from
      `hitTest` forwards a click to the app underneath is unprovable here without
      Screen Recording permission, and the dependency was designed out
      (`ignoresMouseEvents` from a cursor poll). Not a task — recorded so the file is
      complete, and so nobody "fixes" the poll back into a `hitTest` assumption.

## 9. Implemented, waiting for a caller

- [ ] **`PetWindowController.appendToBubble`** is the `bubble.append` verb, implemented
      in-process and reachable from `SpeechEngine.append` — and nothing calls the
      shell wrapper yet, because streaming from the wire is M2 criterion 3. It is
      not dead code: it is the seam the protocol will use. Listed so that a future
      dead-code pass does not delete it.

## 10. Small and cosmetic

- [ ] **A true peek.** `CatShape.peek` is a lean forward — head low and forward,
      body high behind — because the renderer has no way to clip a pookie at the
      edge it is peering over. A real peek needs a clip region in the renderer.
      Documented as a lean rather than oversold.

## Conventions for anything picked up here

The loop in `AGENTS.md` applies: `make selftest` green (a behaviour change lands
with a check of its own), art looked at via `make poses`, docs updated, one commit
per unit. Two rules this list has already been bitten by, twice:

- **Every threshold is a `var` a test can pin.** A random behaviour with a
  hard-coded chance made the loaf test fail about one run in five.
- **A test that assumes frame timings will flake.** Advance until the condition
  holds, bounded, and assert the claim rather than a frame count.
