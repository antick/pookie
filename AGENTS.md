# Working on Pookie

A cat that lives on your screen: a transparent, always-on-top macOS window that never steals focus,
drawn procedurally. Swift + AppKit, **no third-party dependencies**, and **no permission prompts** —
Screen Recording, Accessibility and Input Monitoring are off the table by design, see
`docs/MACOS-CONSTRAINTS.md`.

`TODO.md` is what is left and what "done" means for it. `README.md` is the tour and the file map.
`docs/DESIGN.md` is the architecture.
`docs/ROADMAP.md` is what is done, what is next, and the risk each milestone retires. Read the
relevant one before changing behaviour in its area.

## The loop

1. **Green.** `make selftest` builds and runs the headless checks. It passes before and after your
   change, and a behaviour change lands with a check of its own — the test is the acceptance
   criterion, not a follow-up.
2. **Seen.** Art and geometry changes get looked at, not reasoned about: `make poses` writes the
   review sheet to `shots/poses.png`, and `Pookie --verbose` (or `make run`) logs mood, shape,
   frame tier, CPU and RSS every two seconds. `Pookie --help` is the source of truth for the launch
   flags, and they are how you set up a specific case by hand (`--at`, `--scale`, `--no-wander`).
3. **Documented.** The same change updates `README.md`, `docs/DESIGN.md` and `docs/ROADMAP.md`
   wherever behaviour or status moved — and **deletes** the finished item from `TODO.md`. That file
   is open work only: a ticked box is a list you stop reading. The history is `git log` and the
   milestone statuses.
4. **Committed.** One unit of work, one commit, as soon as it is green and documented — not batched
   to the end of the session. A unit is one thing the human asked for, or one coherent slice of it;
   when a slice is large, commit the slice that stands up on its own rather than the whole feature.

   ```
   area: what changed, imperative mood

   Why it changed, and what it cost: a measurement, a contract that moved, a bug that
   is now impossible. Anything a reader would otherwise have to reverse-engineer.
   ```

   `area` names the part of the pet you touched: `renderer`, `motion`, `menu`, `docs`, `tests`,
   `window`. Commit locally; pushing is the human's call.

## Invariants

- **The pet is a renderer.** Producers emit a small verb vocabulary and the pet draws it. New
  behaviour belongs in the behaviour layer, not in a new integration.
- **Behaviour is pure.** `PetMotion`, `PetPose`, `CatAnatomy` and `SpeechEngine` import no AppKit and
  need no window server, which is what lets `--selftest` drive all of them headlessly. AppKit lives
  in the shell: `PetView`, `PetWindowController`, the window classes, the menu, the status item.
- **The art envelope is a contract.** Every pose the renderer accepts — including every shape
  keyframe and every blend between shapes — rasterises inside `CatGeometry.stage`. Widen a limit and
  the selftest tells you to widen the stage.
- **The floor line is a contract.** `PetMotion.origin` is the line her feet stand on, and
  `CatGeometry.groundInset` is how far her window hangs below it so a leaning paw is not clipped.
  Everything that maps design space to the screen goes through `PetMotion.windowOrigin`, or her feet
  stop touching what she is standing on.
- **Screen space and design space are separate places.** The cat is drawn in design space and the
  facing flip mirrors it, so anything that reasons about the cursor converts first. Getting this
  wrong is a bug that looks like a rendering glitch: eyes aiming away from the pointer.
- **Silence by default, one bubble at a time.** Attention is rate-limited inside `SpeechEngine`; a
  pet never volunteers a line.
- **Pets share a budget.** `PetCohort` caps the *desk* (the collection is uncapped) and hands out
  per-pet frame rates; ten pets may not cost ten times one pet, and the cap is enforced in code rather
  than in prose.
- **A species is a table, not a renderer.** `PetSpecies` gives an animal proportions and appendages;
  the skeleton, the animations and the behaviour are shared. Adding an animal is a `SpeciesTraits`
  entry plus whatever new ear or tail shape it needs — never a parallel draw path or a second behaviour
  engine.
- **One of each animal.** `PetCohort` refuses a second pookie of a kind somebody already is, and a
  saved roster is repaired on load rather than trusted. Coats and names are the free axes.
- **`TODO.md` is open work only.** Finish an item and it comes out of the file, with the reason it
  is gone left to `git log` and the roadmap. Do not tick, do not strike through, do not keep a
  "recently closed" section: anything in there is something still to do.
- **A launch flag is not a settings edit.** `--no-wander` and friends are overrides for one run;
  `AppConfig.persistsChanges` is what keeps them out of the settings store.

## Conventions

- Comments say **why**: the decision, the bug it prevents, the measurement behind a number. A comment
  that restates the line beneath it is noise.
- Renderer numbers are **ratios of the standing cat**, so a new shape can be added without moving the
  one that already looks right.
- Behaviour is **jittered, never metronomic**, and every threshold is a `var` a test can pin.
- Tests read as claims about the pet: if a check cannot fail, it is not a test.
