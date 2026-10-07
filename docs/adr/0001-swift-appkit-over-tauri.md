# ADR-0001: Swift + AppKit over Tauri (and over Electron)

- Status: Accepted
- Date: 2026-10-06
- Deciders: Lead
- Supersedes: none

## Context

Pookie is a desktop pet that must live on top of every application, never steal focus, cost
effectively zero battery while idle, and eventually read a small amount of system state (cursor
position, active window, fullscreen status) and accept global hotkeys. The pet is a window with a
transparent background, an animation loop, and a small always-on-top bubble.

The stack choice matters more here than in a normal app because almost all of the product risk
lives in the *window and platform layer*:

- A pet that can become key window breaks typing. Non-negotiable.
- A pet that costs 3% CPU gets uninstalled.
- A pet that needs heavy permissions to do trivial things gets denied.
- A pet whose transparent topmost window is unreliable (flickers, disappears over fullscreen apps,
  fails to join all Spaces) is simply broken.

Everything else — the cat, the protocol, the brain — is portable logic that could be written in any
language.

Four options were compared.

## Options

| | Electron | Tauri v2 | Swift + AppKit | Hybrid (native shell + web UI) |
|---|---|---|---|---|
| Binary size | ~150–250 MB | ~5–15 MB | ~2–10 MB | ~10–30 MB |
| Idle RAM | 150–400 MB | 60–150 MB | 30–60 MB | 60–150 MB |
| Transparent topmost window | Works, but a known source of platform bugs | Works via `tauri.conf.json` window flags; fewer escape hatches when the OS misbehaves | Full `NSWindow`/`NSPanel` control, including non-activating panels | Full, for the pet window |
| Never-steal-focus | Achievable but fiddly; historically leaky | Achievable; you are still one config layer away from the real API | Direct: override `canBecomeKey`, use `.nonactivatingPanel` | Direct |
| Animation runtime | Chromium compositor; heavy for a 200×200 cat | WKWebView compositor; heavy for a 200×200 cat | Core Animation / SpriteKit; purpose-built for this | Mixed |
| Battery while idle | Worst. A whole browser engine idles with you | Better, but still a webview + JS timer loop | Best. Stop the display link and the process is nearly free | Webview cost stays |
| Permissions | Standard macOS APIs via native modules | Rust-side plugins; some gaps need custom native code | Direct, no bridge | Direct |
| Pet art pipeline | Canvas/CSS/SVG | Canvas/CSS/SVG | Core Graphics now, SpriteKit sprite sheets in M1 | Canvas in a webview |
| Rich streaming chat UI | Free (it *is* a browser) | Free | **Hand-rolled.** Text layout, markdown, streaming, selection | Free |
| Time to first window | Hours | Hours | Days | Days |
| Long-term ceiling | Web stack forever, with a native escape hatch | Same, with a Rust escape hatch | Native all the way | Two languages forever |

Additional considerations that pushed the decision:

- **Tauri v2 on macOS is still a webview.** The pet is a small, continuously animated, alpha-blended
  window. That is the exact workload a webview compositor is worst at per pixel. We would be paying
  browser-engine costs to draw a cat.
- **The escape hatch problem.** Every time a webview-based pet hits an OS quirk (Spaces, fullscreen,
  occlusion, focus), the fix lands in native code anyway — but behind a config layer, an IPC bridge,
  and a plugin boundary. We would end up writing AppKit regardless, with more layers in the way.
- **The one thing native genuinely costs us is the bubble.** A chat bubble needs text layout,
  wrapping, markdown, code blocks, and token-by-token streaming. AppKit gives us `NSTextView` /
  TextKit 2, which is capable but not free. That is a real, bounded, weeks-not-months cost.
- **SpriteKit is deferred to M1**, so M0 does not need an animation engine at all — it needs a
  window and Core Graphics. That removes the last argument for a web renderer.

## Decision

**Build Pookie as a native Swift + AppKit macOS application.**

- The pet window is a borderless `NSPanel` with `.nonactivatingPanel`, `canBecomeKey == false`,
  transparent background, level `.floating`, and the full `collectionBehavior` set.
- **M0 renders the cat procedurally with Core Graphics**, behind a swappable `PetRenderer` protocol.
- **M1 swaps in a SpriteKit renderer** for sprite-sheet animation. The protocol is the seam; nothing
  above the renderer changes.
- No Tauri, no Electron, no webview in the pet path. The bubble is native too, for now.

## Consequences

**Positive**

- The focus, layering, and Spaces behaviour is directly controllable. This is the number one killer
  of desktop pets and we can fix it in our own code.
- Idle cost is bounded by our own render loop. We can stop it entirely when occluded.
- Permissions are requested through the standard APIs, one at a time, with honest justifications.
  Nothing is inherited from a framework's entitlement bundle.
- One language. The behaviour engine, protocol, and renderer are all Swift and all unit-testable.
- Distribution as a signed, notarized DMG with no runtime dependency beyond the OS.

**Negative / accepted costs**

- **We hand-roll the chat bubble and the streaming markdown renderer.** Text measurement, wrapping,
  incremental append without reflow jitter, code blocks, and copy/select-on-a-non-key-window are all
  ours. This is the single largest new cost the decision introduces.
- **No web UI conveniences anywhere.** No CSS, no layout engine, no component ecosystem, no instant
  iteration on visual design.
- **macOS only.** No Windows/Linux path without a rewrite. Accepted: the product is a macOS pet.
- **AppKit knowledge is a prerequisite.** Contributors cannot be web developers.
- Slower time-to-first-window than a Tauri spike would have been. We pay days now to avoid paying
  the webview tax for the life of the product.

**Neutral**

- SpriteKit is in the dependency graph from M1, but only behind `PetRenderer`.

## Tradeoff accepted, stated plainly

We are trading **UI ergonomics** for **window layering, battery, and native permissions**. We will
write our own bubble and our own streaming markdown renderer instead of getting one free, in
exchange for a pet that never steals focus, costs under ~1% CPU when idle, and asks for permissions
on its own terms.

That trade is correct for this product because the bubble is a bounded, well-understood text-rendering
problem, while window layering and focus are unbounded platform fights that never fully end.

## Revisit trigger

**If the rich streaming chat UI proves too costly** — specifically, if the bubble consumes more than
roughly one milestone of effort, or if we cannot get acceptable streaming markdown, code blocks, and
text selection without fighting TextKit — then **embed a `WKWebView` for the bubble only**.

That is a bounded escape hatch: the pet window and the renderer stay native, the bubble becomes a
web view rendering the streaming content, and the protocol and behaviour engine are untouched. It
does not reopen the Tauri or Electron decision.

Secondary trigger: if macOS-only becomes a product requirement, revisit the whole decision rather
than bolting on a second shell.
