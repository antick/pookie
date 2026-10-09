# TODO

What is left, in the order I would do it. `docs/ROADMAP.md` has the milestone
detail and the acceptance criteria; this file is the working list — the things
that are *not* done, why they are not done, and what "done" means.

Last audited: against every place this repo records unfinished work — the roadmap's
"Outstanding" lines, `M0-FINDINGS.md` §5 "Not yet verified" and its "New unknowns",
`MACOS-CONSTRAINTS.md` §11 and `DESIGN.md` "New unknowns". The first version of this
file missed three items, the second missed three more (a sleep/lock feature that was
never implemented, and two things never seen on screen). Both times the miss was
found by sweeping the docs rather than by remembering, which is why the audit trail
is written down here. Anything not
listed here is either finished or not worth doing; `git log` is the history.

## 1. Asked for, or designed and never built

- [ ] **A kick in the brawl.** The ask was "punching their face, getting face
      punched **or kicked**". Punches landed (`CatPose.punch`, alternating
      forelegs, a flinch with a squint and a yelp); a hind-leg kick did not.
      *Done when:* `CatPose.kick` throws a hind leg at the rival, the brawl
      alternates punches and kicks rather than repeating one, and the receiving
      pookie reacts to both. It belongs in the transient sweep, like the punch.

- [ ] **Pause when the screen locks, and on sleep.** `M0-FINDINGS.md` §5 item 6:
      "`ProcessInfo` activity holds and screen-lock suspension are **designed but not
      implemented**". A pookie that keeps walking around behind a locked screen is
      burning battery for nobody, and `PetMotion.isPaused` is already the hook.
      *Done when:* locking the screen pauses every pet, unlocking resumes them, and
      a check drives the pause path without a window server.
      *Needs:* nothing.

## 2. The renderer swap (M1 criterion 1)

- [ ] **A layer-backed renderer behind `PetRenderer`.** This is the single
      highest-value piece of work left, and it is measured rather than assumed:
      drawing a pookie costs **1–2 ms**, the silhouette raster is ~2/s, and the
      frame pump runs within **1.2×** of its target — so a stutter is *not* the
      drawing. It is the window server moving a transparent, always-on-top window
      every frame, twice as often while airborne.
      *Done when:* the pet is drawn into a `CAMetalLayer`/`CALayer` on one
      surface, the window frame stops changing per frame, and `slip=` in
      `--verbose` is no worse than it is now under the same load.
      *Needs:* nothing. `worst=`, `masks=` and `slip=` are already in the
      heartbeat as the regression metric.

- [ ] **Interim lever, only if the swap slips:** cache the parts that do not
      change every frame (body, head, ears, paws) and redraw only the tail, eyes,
      whiskers and mouth. M0's findings estimate 40–60%, and recommend measuring
      the layer-backed path first — it is real complexity that the swap makes
      unnecessary.

## 3. The control plane, which unlocks three other milestones

- [ ] **M3 — a `pookie` CLI over a local socket.** `PROTOCOL.md` is written and
      the receiving end already exists (`Pookie --say` is the stand-in); what is
      missing is the transport (NDJSON over a Unix domain socket, loopback TCP
      fallback), the CLI verbs, and the envelope semantics: `id` dedupe, `ts` +
      `ttl` expiry, `priority` override, acks, and every error code in the
      protocol.
      *Done when:* `pookie say "hi"` from a fresh terminal makes the pet speak,
      with no setup beyond the CLI being on `PATH`.
      *Unlocks:* M4, M5 and M7. This is the roadmap's own "unlocks everything".

- [ ] **M4 — an MCP server**, one tool per verb, so Codex and Claude Code can
      animate the pet with no bespoke integration. The adapter must contain no
      behaviour logic beyond translation. *Needs:* M3.

- [ ] **M5 — an LLM brain** as a separate local process that starts, stops and
      restarts independently, streams tokens into a bubble, and never blocks the
      render loop. *Needs:* M3.

- [ ] **M7 — reactive skill packs**: declarative documents binding triggers to
      intents (`on git commit → emote(sparkle)`). *Needs:* M3/M4.

## 4. M2's remaining criteria

All four need M3's transport to be meaningful:

- [ ] Criterion 3 — wire streaming (`bubble.append` over the protocol).
- [ ] Criterion 4 — the preemption stack (priority override).
- [ ] Criterion 5 — TTL evaluated at dispatch, not at arrival.
- [ ] Criterion 7 — every rate-limit and preemption decision logged with a
      reason, so "why did my line not appear" has an answer.

## 5. Voice (M6)

- [ ] STT via `whisper.cpp`, locally, with no audio leaving the machine.
- [ ] TTS via `AVSpeechSynthesizer`, with a voice option and a mute.
- [ ] Push-to-talk on a global hotkey that works **without** prompting for
      Accessibility.
- [ ] Microphone captured only while the hotkey or a visible affordance is
      active; no always-on listening; the pet ducks its own idle behaviour while
      listening and does not talk over the user.

## 6. Release (M8 criterion 4)

- [ ] **A signed, notarized DMG.** `make bundle` produces an unsigned app;
      Gatekeeper warns on a clean machine until somebody with an Apple Developer
      certificate signs and notarizes it. This is a release process, not code.
      *Then re-check:* global hotkey registration, the `--say` distributed
      notification bridge, and permission behaviour. M0's findings call the
      bridge the most likely casualty of sandboxing.

## 6b. Open questions from the uncertainty register

`docs/MACOS-CONSTRAINTS.md` §11 is the register; these are its entries that are
still open, and they are here because a register nobody reads is a register nobody
closes.

- [ ] **Item 7 — the fullscreen-geometry heuristic.** Whether detecting "a
      full-screen app is in front" by window geometry gives acceptable false
      positives is unanswered, because the heuristic was never implemented. Keep it
      configurable and default off if it is.
- [ ] **Item 8 — MCP notifications.** Whether an MCP server can push notifications
      to Codex and Claude Code is untested; assume a `pookie_poll_events` tool is
      required until it is tested. Belongs with M4.
- [ ] **Item 4 — capture exclusion.** `sharingType = .none` has never met a real
      screen-share client. Listed under §7 as a check for a human.
- [ ] **Item 5 — the hotkey in a notarized, sandboxed build.** Carbon
      `RegisterEventHotKey` works with zero prompts in a dev build; re-check after
      notarization. Listed under §6.
- [x] **Item 11 — `Desktop.region(containing:)` near a display seam.** Closed: a
      point in the gap between two displays now prefers the region the pookie was
      already in, instead of nearest-by-centre, which could hand her back the
      display she just left and read as a bounce at the boundary.

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

## 7b. Not yet verified, from M0's findings

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

## 7c. Implemented, waiting for a caller

- [ ] **`PetWindowController.appendToBubble`** is the `bubble.append` verb, implemented
      in-process and reachable from `SpeechEngine.append` — and nothing calls the
      shell wrapper yet, because streaming from the wire is M2 criterion 3. It is
      not dead code: it is the seam the protocol will use. Listed so that a future
      dead-code pass does not delete it.

## 8. Small and cosmetic

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
