# macOS Constraints

Platform reference for Pookie. This is the document that stops us re-learning the same AppKit
lessons. It is deliberately opinionated about what is safe to build on and honest about what is not
verified.

Confidence markers used below:

- **[verified]** — API exists and behaves as described; safe to design against.
- **[verify in M0]** — API exists but the *behaviour we depend on* is not confirmed. Must be tested
  before anything is built on top of it.
- **[do not build on]** — unsupported, fragile, or sandboxed away. No architectural dependency.

---

## 1. The one rule: never steal focus

This is the number one killer of desktop pets. A pet that becomes the key window steals keystrokes:
you are typing in an editor, the cat animates, focus moves, and half your sentence lands in the
wrong place. Users do not debug that, they delete the app.

**Requirements:**

- The pet window **must never become key or main.**
- The application should not appear as the active app in the menu bar or Dock.
- Showing the pet must not deactivate whatever the user is working in.

**Implementation:**

1. **Subclass `NSWindow` (or `NSPanel`) and override the capabilities to `false`.** **[verified]**

   ```swift
   final class PetPanel: NSPanel {
       override var canBecomeKey: Bool { false }
       override var canBecomeMain: Bool { false }
   }
   ```

   Returning `false` from `canBecomeKey` is the load-bearing part. Without it, AppKit will happily
   make the window key when clicked.

2. **Use a non-activating panel.** `NSWindow.StyleMask.nonactivatingPanel` is valid on `NSPanel`.
   **[verified]** Combine with `.borderless`.

3. **Show without activating.** Use `orderFrontRegardless()` rather than `makeKeyAndOrderFront(_:)`.
   `makeKeyAndOrderFront` does exactly what it says and must never be called on the pet window.
   **[verified]**

4. **Run as an accessory app.** Set `LSUIElement` to `true` in `Info.plist`, or call
   `NSApp.setActivationPolicy(.accessory)`. No Dock icon, no menu bar takeover. **[verified]**

5. **Do not use `activate(ignoringOtherApps:)`.** Ever, for any reason.

**Bubble window caveat:** the bubble is a separate window and has the same constraint. Text in a
non-key window cannot be selected or copied through normal AppKit paths. If we want selectable
bubble text, that is a deliberate feature with its own focus design (an explicit opt-in "pin and
focus" action), not a default. This is one of the real costs accepted in ADR-0001.

**Implemented.** `BubbleWindow` is a `canBecomeKey = false` sibling of the pet window, one level
above it, `ignoresMouseEvents = true` always (an information card, not a control), with the same
`collectionBehavior` and `sharingType`. It is moved and redrawn by the frame pump, and its text is
drawn with Core Text so the same code path renders on screen and in the headless pose sheet.

---

## 2. Canonical window configuration

Starting point for the M0 pet window. Deviations must be deliberate and documented.

```swift
let panel = PetPanel(
    contentRect: NSRect(x: 0, y: 0, width: 160, height: 160),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)

panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.level = .floating

panel.collectionBehavior = [
    .canJoinAllSpaces,      // visible on every Space
    .fullScreenAuxiliary,   // allowed to appear alongside another app's fullscreen window
    .stationary,            // does not move with Exposé / Space switches
    .ignoresCycle           // excluded from Cmd-` window cycling
]

panel.isMovableByWindowBackground = false   // the cat is dragged by behaviour, not by titlebar rules
panel.hidesOnDeactivate = false
panel.isFloatingPanel = true
panel.becomesKeyOnlyIfNeeded = true
panel.animationBehavior = .none             // no fade-in on show
panel.contentView?.wantsLayer = true
panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

panel.orderFrontRegardless()
```

Field notes:

| Property | Value | Why |
|---|---|---|
| `isOpaque` | `false` | Required for alpha compositing. Without it the transparent regions render black |
| `backgroundColor` | `.clear` | Pairs with `isOpaque`. Both are needed |
| `hasShadow` | `false` | A rectangular window shadow around a non-rectangular cat looks broken. Shadows, if wanted, are drawn by the renderer |
| `level` | `.floating` | Above normal windows, below system UI. `NSWindow.Level` also has `.statusBar`, `.popUpMenu`, `.screenSaver`. **Do not** use `.screenSaver` or higher to float over fullscreen apps — it is an App Store rejection and a user-hostile behaviour |
| `collectionBehavior` | see above | `.canJoinAllSpaces` + `.fullScreenAuxiliary` is what makes the pet survive Space switches and fullscreen apps |
| `animationBehavior` | `.none` | The default fade on show reads as a flicker for a small pet window |

**[verify in M0]** The exact combination of `.borderless` + `.nonactivatingPanel` + `isFloatingPanel`
+ `becomesKeyOnlyIfNeeded` has several plausible variants. M0 should test them explicitly against
criterion 3 (typing is never interrupted) rather than assuming this exact set is minimal or correct.
In particular, confirm that the window still receives mouse events for dragging while
`canBecomeKey` is `false`.

---

## 3. Click-through and hit testing

Two different goals get confused here:

- **Shape-accurate input:** clicks on transparent pixels around the cat should not hit the cat.
- **True click-through:** clicks on transparent pixels should reach the app *underneath* the pet.

They are not the same problem, and only the first one is solved by `hitTest`.

### 3a. Shape-accurate hit testing (`hitTest`) **[verified API, verify behaviour]**

Override `hitTest(_:)` in the content view and return `nil` outside the cat's silhouette:

```swift
override func hitTest(_ point: NSPoint) -> NSView? {
    guard silhouetteContains(point) else { return nil }   // alpha threshold on the rendered bitmap
    return super.hitTest(point)
}
```

**The honest caveat.** By the time `hitTest` runs, the window server has **already delivered the
event to this window**. Returning `nil` means "no view in this window wants it" — it does **not**
mean "give this click to the application behind me". In the common case the click is consumed by
our borderless window and the app underneath never sees it. Whether AppKit re-routes it in any
configuration is exactly the kind of thing that is documented ambiguously and behaves differently
across releases.

**M0 outcome: not proven, and not depended upon.** We could not verify it either way — `screencapture`
fails in the development shell (no Screen Recording permission), so there was no way to observe a
click landing in a third-party app. Rather than gamble on undefined behaviour, pass-through is
implemented entirely with `ignoresMouseEvents` (§3c). `hitTest` is retained **only** as a secondary
guard, so a click landing in a gap on the frame the cursor leaves cannot activate the window. See
`M0-FINDINGS.md` §1.4.

### 3b. True pass-through (`ignoresMouseEvents`) **[verified]**

`NSWindow.ignoresMouseEvents = true` excludes the window from the window server's hit testing
entirely, so clicks genuinely land on whatever is underneath. **[verified]** This is the reliable
mechanism, and it is binary: the whole window is transparent to input.

### 3c. The recommended hybrid — **implemented in M0**

Because `ignoresMouseEvents` is all-or-nothing and `hitTest` is unreliable for pass-through, combine
them with a cursor poll. This is what `PetView.updateMousePassthrough()` does:

1. Keep `ignoresMouseEvents = true` by default — the pet is click-through at rest.
2. Read `NSEvent.mouseLocation` (permission-free; see section 4) and convert to window coordinates.
3. When the cursor enters the pet's opaque silhouette, set `ignoresMouseEvents = false`.
4. When it leaves, set it back to `true`. **Edge-triggered**, never written twice with the same value.
5. Never drop the mouse while `motion.isDragging`, or the cat escapes your hand mid-throw.

Costs and caveats, stated plainly:

- There is a **race**: a click can arrive in the interval between the cursor entering the silhouette
  and the toggle taking effect. Mitigated with a 3 pt hysteresis ring on the silhouette test, and
  accepted.
- **Deviation from the original recommendation:** the poll runs at display rate (15–60 Hz depending on
  the frame tier) rather than 10–15 Hz, because it rides the frame pump that is already running and
  `NSEvent.mouseLocation` is a cheap static read. A second timer would add a longer race window for
  no benefit. If profiling shows it matters, decimate to every fourth frame.
- At the idle tier the race window is up to ~66 ms. That is the price of the 15 fps energy budget.

**Rejected alternative:** capture the click and re-post it with `CGEvent.post`. That requires
Accessibility permission, is fragile across apps, and can double-deliver. Not worth it for a pet.

---

## 4. Permissions

### 4.1 Permission-free — build freely on these

| Capability | API | Notes |
|---|---|---|
| Cursor position | `NSEvent.mouseLocation` | Class property, screen coordinates, no permission. **This is the pet's primary sensor** |
| Global hotkeys | Carbon `RegisterEventHotKey` / `InstallEventHandler` | Still functional and permission-free at time of writing. See caveat below |
| Own window/screen geometry | `NSScreen`, `NSWindow` | Always available |
| Loopback sockets, file system (user-selected paths) | — | Standard sandbox rules apply |
| Distributed notifications (post/observe) | `DistributedNotificationCenter` | Works, but see the sandbox caveat in 4.4 |

**Carbon hotkey caveat [verify in M0].** `RegisterEventHotKey` in `Carbon.HIToolbox` is a legacy API.
It requires no Accessibility or Input Monitoring permission, which is exactly why it is attractive
for a global show/hide hotkey, and it is still used widely for this purpose. It is legacy, so confirm
it works on our target macOS versions and in a sandboxed/notarized build before depending on it in
M6. The alternative — a `CGEventTap` — does require permission, so there is a real tradeoff here.

### 4.2 Accessibility (`AXUIElement`) — required for app introspection

| Need | API |
|---|---|
| Check trust | `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions(_:)` |
| Prompt | `kAXTrustedCheckOptionPrompt` in the options dictionary |
| Read window list / focused window of another app | `AXUIElementCreateApplication(_:)` + `AXUIElementCopyAttributeValue` with attributes such as `kAXFocusedWindowAttribute`, `kAXWindowsAttribute` |

Use it for: "what is the user looking at?", "is the front window a browser?", positioning next to a
window. Cost: a scary, sticky, all-or-nothing system prompt. Users who deny it must still get a fully
functional pet.

**Rule:** Accessibility is an enhancement, never a requirement. Everything in M0–M3 works without it.

### 4.3 Screen Recording — required for window titles and frames

| Need | API | Permission |
|---|---|---|
| On-screen window list — owner, PID, bounds, layer | `CGWindowListCopyWindowInfo(_:_:)` with `kCGWindowListOptionOnScreenOnly` | **Not required** for these fields |
| Window **titles** (`kCGWindowName`) | same call | **Required.** Without Screen Recording, the `kCGWindowName` entry is simply absent from the dictionary |
| Preflight / request | `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` | — |
| Window pixels | `CGWindowListCreateImage` | Deprecated as of macOS 14 in favour of ScreenCaptureKit. Do not build new code on it |

Practical consequence: we can learn that *a* window occupies a rectangle without permission, but not
which window it is. Design any "react to the active window" feature to degrade to geometry-only, or
require Accessibility instead (the smaller ask for introspection).

**Implemented — perching.** `WindowScanner` reads owner, PID, layer and bounds with this call to find
window top edges for the cat to stand on; `Pookie --windows` prints what it sees. Titles are never
read. Verified permission-free on macOS 26.6.2: 55 windows listed, no prompt. Only layer-0 windows
count, which excludes panels, HUDs, and Pookie's own `.floating` windows — including those of a
second Pookie instance. The bounds are top-left-origin, so `WindowScanner` flips them once
(§6) before anything else sees them.

### 4.4 Input Monitoring — required for global keyboard/event taps

- A `CGEventTap` for keyboard events requires either Accessibility or Input Monitoring trust.
- Check with the IOHID access APIs (`IOHIDCheckAccess`, `IOHIDRequestAccess` with the appropriate
  request type) before installing a tap. **[verify in M0]** Confirm the exact API and constants
  against the SDK before coding against them; the naming here has churned across releases.

**Rule:** do not install a global event tap for anything the pet does by default. Hotkeys come from
Carbon (permission-free) and cursor tracking comes from `NSEvent.mouseLocation` (permission-free).
Taps are a last resort with an explicit, explained prompt.

### 4.5 Global mouse-moved monitors — unclear, do not depend on it

`NSEvent.addGlobalMonitorForEvents(matching:handler:)` exists **[verified API]**. The documented
permission story is clearest for **key** events, where the process must be trusted for Accessibility.
Whether mouse-moved events monitored globally require any trust is **not clearly documented and is
known to vary**. **[verify in M0]**

**Do not architect around it.** Use polling of `NSEvent.mouseLocation` on a 10–15 Hz timer for
look-at-cursor, and reserve global monitors for a feature that has been proven to need them.

### 4.6 Permissions: summary

| Capability | Permission | Use in Pookie |
|---|---|---|
| Cursor position | none | Look-at-cursor, hit-test toggle |
| Global hotkey (Carbon) | none | Show/hide, push-to-talk |
| Own windows/screens | none | Everything core |
| Read window titles | Screen Recording | Degradable enhancement only |
| Read other apps' UI structure | Accessibility | Degradable enhancement only |
| Global keyboard tap | Accessibility or Input Monitoring | Avoided |
| Read other apps' notifications | — | **Do not build on** (section 5) |

---

## 5. Other apps' notifications: do not build on this

The Notification Center store lives in a protected location under `~/Library/Group Containers/...`
and reading it requires Full Disk Access, is unsandboxable for distribution, and its schema is
private and changes without notice. There is **no supported public API** for observing another
application's notifications.

**[do not build on]** Any design that says "the pet reacts when Slack pings you" via notification
scraping is dead on arrival.

**Preferred substitutes, in order:**

1. **Producer-side webhooks and hooks.** Git hooks, build watchers, CI callbacks, a CLI invocation.
   This is the whole point of the intent protocol — the producer tells the pet directly.
2. **`DistributedNotificationCenter`** for system-level events that are genuinely distributed
   notifications. Note the sandbox caveat: a sandboxed app is restricted in which distributed
   notifications it may observe, and some require a temporary-exception entitlement. Use it for
   well-known system events, not as a general app-event bus.
3. **File and directory watching** (`DispatchSource` / FSEvents) on paths the user grants.
4. **Accessibility** as a last-resort fallback for apps that expose nothing else, and only as an
   explicitly optional enhancement.

---

## 6. Multi-monitor and display reconfiguration

- **Enumerate displays with `NSScreen.screens`**, not with hard-coded Core Graphics display ids.
  `NSScreen.main` is the screen with the key window, which for us is often not the screen the user
  is looking at — prefer `NSScreen.screens.first` (the primary display) or explicit selection.
- **Use `visibleFrame`, not `frame`.** `visibleFrame` excludes the menu bar and the Dock, so it is
  the correct floor for a walking pet. **[verified]** Note that the menu bar and Dock appear on only
  one display, so `visibleFrame` differs per screen; a pet that walks to a specific `y` will look
  wrong if that `y` was computed on another display.
- **Notch and safe areas:** `NSScreen.safeAreaInsets` (macOS 12+) is real and should be respected for
  anything that sits near the top edge. **[verified]**
- **Handle reconfiguration.** Displays get plugged, unplugged, rearranged, and resolution-changed.
  Observe `NSApplication.didChangeScreenParametersNotification` and `NSWindow.didChangeScreenNotification`.
  **[verified]** For lower-level display changes, Core Graphics offers
  `CGDisplayRegisterReconfigurationCallback`; prefer the AppKit notifications unless they prove
  insufficient.
- **After any reconfiguration, clamp every pet's position into a valid `visibleFrame`.** The classic
  bug is a pet that lived on a now-disconnected display and is invisible forever, with no way for the
  user to find it. There must be a "gather all pets to the main display" recovery action.
  `PetMotion.keepOnScreen()` is that clamp, and it runs on a size change as well as on a display
  change. **[implemented]**
- **Teleporting between displays is a placement, not a window move.** `PetMotion` only assigns an
  `origin` inside another `visibleFrame`; the window follows through the ordinary frame sync, so there
  is no second code path that can disagree about coordinates. Landing *from above* (`surface(at:from:)`
  with `region.maxY`) is what makes her arrive on a window top instead of in front of one, and it
  needs no new geometry. Note that `NSScreen.screens` order and a two-display alternation are not the
  same thing: "somewhere else" is implemented as "any other index in `visibleFrames`".
- **A bigger pet is a bigger window.** The size setting scales the window, so extra large is 3.6x the
  composited area of medium at the same frame rate — worth remembering before blaming a CPU
  measurement on the renderer.
- **Coordinate space discipline.** Window positions are AppKit bottom-left-origin; `CGWindowList`
  bounds and `CGDisplayBounds` are top-left-origin with y down. The protocol uses the Core Graphics
  convention (see `PROTOCOL.md`). Pick one at each boundary and convert explicitly; mixing them is the
  most common source of "the cat is one screen-height off". Pookie's only such boundary is
  `WindowScanner`, which converts once: `y = primaryScreen.frame.maxY - cgY - cgHeight`.

---

## 7. Screen-sharing privacy

`NSWindow.sharingType = .none` asks the system to exclude the window from screen capture and sharing.
The property exists (`NSWindow.SharingType` with `.none`, `.readOnly`, `.readWrite`). **[verified]**

**Caveat [verify in M0].** There are reports that on recent macOS releases (macOS 15.4+ is the
version cited), windows marked `kCGWindowSharingStateSharingNone` are **still captured by
ScreenCaptureKit**. See the Apple Developer Forums thread [On macOS 15.4+, NSWindow with
kCGWindowSharingStateSharingNone still captured by
ScreenCaptureKit](https://developer.apple.com/forums/thread/792152).

**Conclusion:** treat `sharingType = .none` as best-effort, not a guarantee. Do not promise users
that the pet is invisible in screen shares. Any genuinely private content must not be rendered by the
pet at all. Document the real behaviour after testing it, and note that the window-sharing state may
also affect screenshots taken through other paths.

---

## 8. Fullscreen apps, hiding, and the hide hotkey

### 8.1 Surviving fullscreen

`.fullScreenAuxiliary` in `collectionBehavior` is what allows the pet to appear alongside another
application's fullscreen window. **[verified]** Combined with `.canJoinAllSpaces`, this covers Space
switches and fullscreen reliably.

### 8.2 Detecting fullscreen video

**There is no public API for "a video is playing".** Anything here is a heuristic.

Plausible heuristic: a layer-0 window whose bounds cover an entire display's frame, on the frontmost
application, is a fullscreen window. Use `CGWindowListCopyWindowInfo` with the bounds/owner/layer
fields, which do **not** require Screen Recording permission. Add a user-facing rule ("hide during
fullscreen") and let the user disable it.

**[verify in M0/M2]** Confirm that the geometry heuristic behaves acceptably for fullscreen video in a
browser, in a native player, and in presentation apps. It will produce false positives; the design
must tolerate them.

### 8.3 Useful workspace and session notifications

Available on `NSWorkspace.shared.notificationCenter`: **[verified]**

- `NSWorkspace.didActivateApplicationNotification` — frontmost app changed
- `NSWorkspace.activeSpaceDidChangeNotification` — Space switched
- `NSWorkspace.screensDidSleepNotification` / `NSWorkspace.screensDidWakeNotification` — display sleep
- `NSWorkspace.sessionDidResignActiveNotification` / `NSWorkspace.sessionDidBecomeActiveNotification` —
  fast user switching

Use these to suspend the render loop. Display sleep and session resignation are the cheapest possible
battery wins because the pet provably cannot be seen.

**[verify in M0]** Screen lock (`com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`) is
available only as an undocumented distributed notification, widely used in the community but **not**
an Apple-documented API. Do not make it load-bearing; treat lock detection as a bonus on top of the
documented session and screen-sleep notifications.

### 8.4 The global hide hotkey

A global hide/show hotkey is **mandatory**, not a nicety. It is the user's guaranteed escape hatch
from any misbehaviour, and it is what makes the "not annoying" constraint credible.

- Register it with Carbon `RegisterEventHotKey` so it requires no permission prompt.
- Make it work even when the pet is occluded, mispositioned, or in a degraded state.
- Ship a sensible default, expose it in settings (M8), and detect and report a failed registration
  (another app may already own the combination — do not assume success).
- Add a recovery action that gathers pets back onto the visible screen (section 6).

---

## 9. Distribution: DMG, not the Mac App Store

**The Mac App Store is not a viable channel for Pookie.** Reasons:

- A transparent, always-on-top window with unusual `NSWindow.Level` behaviour and non-activating
  panels is exactly the class of thing App Review rejects as "not behaving like a Mac app".
- Floating above other apps' fullscreen windows reliably often tempts implementations toward
  higher window levels and `NSApplication.presentationOptions` overrides, which read as private-API
  or system-UI-spoofing territory.
- The sandbox restricts the distributed-notification and file-watching surfaces that make the pet
  useful, and blocks supervising an out-of-process brain (ADR-0003) cleanly.
- Notarization plus a Developer ID is sufficient for Gatekeeper on a DMG, without review.

**Decision:** ship a signed, notarized **DMG** with Developer ID. Notarize with `notarytool`. State
the App Store incompatibility in the docs and in the README, so it is never re-litigated as a
"growth" idea.

**Consequence:** no App Store auto-update. An update mechanism is an M8 packaging concern; a
third-party updater framework is an option, but it introduces its own signing and permission
surface, so evaluate it then rather than assuming it.

---

## 10. Energy discipline (cross-reference)

The platform rules that matter for battery are covered in `DESIGN.md` section 9. The AppKit-specific
facts:

- **Occlusion:** read `NSWindow.occlusionState` and observe `NSWindow.didChangeOcclusionStateNotification`.
  When the pet is not in the `.visible` set, stop the frame clock entirely. **[verified]**
- **Frame clock:** `NSView.displayLink(target:selector:)` and `NSWindow.displayLink(target:selector:)`
  exist on recent macOS, making `CADisplayLink` the preferred frame clock. **[verified API,
  verify in M0]** Confirm the exact availability annotation against our deployment target. As of the
  M0 walking skeleton, `Package.swift` declares `platforms: [.macOS(.v14)]`, which is the release that
  introduced these `displayLink` methods — so `CADisplayLink` should be available unconditionally and
  no `CVDisplayLink` fallback should be needed. Confirm this by compiling, not by assuming. If the
  deployment target is ever lowered, the older `CVDisplayLink` is a fallback only, and it is
  **deprecated as of macOS 15**.
- **App Nap:** hold a `ProcessInfo` activity only while genuinely animating, and release it when idle
  or occluded. A pet that keeps an activity open while invisible is burning the user's battery for
  nothing.

---

## 11. Uncertainty register

Everything the M0 walking skeleton must answer empirically, with the fallback if the answer is bad.
**Status column added after M0.** Detail and evidence in `M0-FINDINGS.md`.

| # | Question | Status | Outcome / fallback |
|---:|---|---|---|
| 1 | Does returning `nil` from `hitTest` forward a click to the app underneath? | **Designed around** | Unprovable here (no Screen Recording permission). Removed the dependency: `ignoresMouseEvents` toggled by a cursor poll (§3c) |
| 2 | Does the exact style-mask/panel configuration keep the pet non-key while still receiving drags? | **Resolved** | `canBecomeKey = false` + `canBecomeMain = false` + `acceptsFirstMouse = true`. Drags delivered. Confirm by hand |
| 3 | Do global mouse-moved monitors need Accessibility/Input Monitoring? | **Resolved — don't use them** | Poll `NSEvent.mouseLocation`; permission-free and already on the frame pump |
| 4 | Does `sharingType = .none` still exclude the window from capture on current macOS? | **Open** | Implemented and toggleable, untested against a real screen-share client. Never promise invisibility |
| 5 | Does Carbon `RegisterEventHotKey` work in a notarized, sandboxed build? | **Partial** | Works with zero prompts on macOS 26.6.2 in a dev build. Re-check after notarization (M6) |
| 6 | Is `CADisplayLink` actually available at our deployment target? | **Resolved** | Compiles and runs unguarded at macOS 14. ~53–60 Hz observed. `CVDisplayLink` not needed |
| 7 | Does the fullscreen-geometry heuristic give acceptable false positives? | **Open** | Not implemented. Keep it configurable and default off |
| 8 | Are MCP server-initiated notifications usable in our target clients? | **Open** | Assume `pookie_poll_events` is required until tested in M4 |

### New from M0

| # | Question | Status | Outcome |
|---:|---|---|---|
| 9 | Does a SpriteKit renderer remove the measured ~3 ms/frame software rasterisation cost? | **Open — the M1 bet** | M0 measured 5% CPU at 15 fps, 10% at 30 fps, 30% undecimated. Measure with `--verbose` before and after the swap |
| 10 | Does frame decimation faithfully hit its tier? | **Resolved** | Not without slack. A strict `accumulator >= target` silently gave 20 fps for a 30 fps tier. A `* 0.92` tolerance fixes it |
| 11 | Does `Desktop.region(containing:)` behave near a display seam? | **Open** | A point in the seam gap matches no screen and falls back to nearest-by-centre; can cause a boundary bounce. Prefer the previous region. Deferred to M1 |

Results go here, not into tribal memory. Items 1 and 2 gated the rest of the product, and both are
now closed.
