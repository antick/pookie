# Pookie Intent Protocol

Wire specification for the intent protocol described in `DESIGN.md` and ADR-0002.

Version: `0.1` (M0/M2 draft). Everything here is subject to change until M3 ships the control plane.

Status by milestone:

| Feature | Available |
|---|---|
| Verb vocabulary + envelope | M2 (in-process), M3 (on the wire) |
| Envelope decode, dedupe, TTL, error codes, acks | **Landed** — `Sources/Pookie/Protocol.swift`, headless-tested. The transport is what is left |
| `pookie` CLI client | M3 |
| MCP surface | M4 |
| LLM brain as a client | M5 |

---

## 1. Transport

- **Primary:** newline-delimited JSON (NDJSON) over a Unix domain socket, default path
  `~/Library/Application Support/Pookie/control.sock`.
- **Alternative:** NDJSON over `127.0.0.1` on a port written to
  `~/Library/Application Support/Pookie/port`, for clients that handle TCP better than Unix sockets.
- One JSON object per line, UTF-8, `\n` terminated. No embedded raw newlines inside strings.
- The connection is **producer → pet**. The same connection carries acks and events back.

Handshake (first line on connect, optional but recommended):

```json
{"verb":"hello","args":{"client":"pookie-cli/0.1","protocol":"0.1","events":["clicked","petted"]}}
```

The pet replies:

```json
{"verb":"hello.ok","args":{"protocol":"0.1","pets":["pookie"],"version":"0.1.0"}}
```

A client that does not send `hello` is assumed to want no events and no acks.

---

## 2. Intent envelope

Every intent is one JSON object with these fields:

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | yes | Unique per intent. UUID or ULID. Used for dedupe, acks, and log correlation |
| `ts` | integer | yes | Unix epoch milliseconds, UTC, when the producer created the intent |
| `verb` | string | yes | One of the verbs in section 4 |
| `args` | object | yes | Verb-specific. May be `{}`. Must not be `null` |
| `priority` | integer | no | Overrides the verb's default priority. Range 0–100 |
| `ttl` | integer | no | Milliseconds after `ts` at which the intent is discarded if not yet started |
| `pet` | string | no | Target pet id. Defaults to the primary pet. Ignored by `spawn` |

Minimal intent:

```json
{"id":"01J9Z6Q0V3","ts":1759773421000,"verb":"emote","args":{"name":"sparkle"},"priority":30,"ttl":5000}
```

Rules:

- **Dedupe is by `id`.** A repeated `id` is acknowledged and dropped. This makes retries safe.
- **Expiry is by `ttl`.** Checked twice: on arrival at the router, and again when the behaviour
  engine is about to start the action. An intent that waited behind a sentence and is now stale is
  dropped, not played late.
- **Unknown fields are ignored, unknown verbs are rejected** with `unknown_verb`.
- Field names are `lowerCamelCase`. Verb names are `lowerCamelCase` for the base verb plus a dotted
  namespace for bubble operations (`bubble.show`).

### Acks

If the client asked for acks in `hello`, the pet writes one line per intent:

```json
{"id":"01J9Z6Q0V3","ok":true,"accepted":"queued","eta_ms":0}
{"id":"01J9Z6Q0V4","ok":false,"error":"rate_limited","retry_after_ms":4000}
```

`accepted` is one of `started`, `queued` (deferred behind higher priority), or `dropped` (TTL
expired or rate-limited; see `error`).

### Error codes

| Code | Meaning |
|---|---|
| `malformed_json` | Line was not valid JSON |
| `missing_field` | Required envelope field absent |
| `unknown_verb` | Verb not in the vocabulary |
| `bad_args` | Args failed validation for this verb |
| `expired` | `ts + ttl` is already in the past |
| `duplicate_id` | Seen this `id` already |
| `rate_limited` | Attention budget exhausted; see `retry_after_ms` |
| `unknown_pet` | `pet` referred to a pet that does not exist |
| `capacity` | Too many pets (`spawn` beyond the limit) |
| `unsupported` | Verb understood but not implemented at this version |

---

## 3. Coordinates and anchors

Positions are expressed either as an **anchor** or as **absolute global display coordinates**.

- Absolute coordinates are in **points**, in the Core Graphics global display space: origin at the
  **top-left of the main display**, `y` increasing **downward**. This is the same space as
  `CGWindowListCopyWindowInfo` and `CGDisplayBounds`, which keeps producer code boring.
- `screen` is an optional display index or a display id string. If omitted and the coordinates are
  ambiguous, the pet picks the display with the largest intersection and then the main display.

Named anchors (preferred, because they survive monitor changes):

| Anchor | Meaning |
|---|---|
| `bottom-left` / `bottom-right` | Screen corner above the Dock band |
| `bottom-centre` | Bottom centre, clear of most window content |
| `top-right` / `top-left` | Just below the menu bar |
| `centre` | Screen centre. Use sparingly; this is "in the way" |
| `cursor` | Current cursor position (resolved by the pet, permission-free) |
| `front-window-edge` | Right edge of the frontmost window, if readable (may require Screen Recording; see `MACOS-CONSTRAINTS.md`) |

Anchors are resolved by the pet at action start, not at intent arrival.

---

## 4. Verbs

### 4.1 `say`

Speak a line. Opens (or reuses) a bubble and holds a locomotion lock for the duration.

| Arg | Type | Required | Default | Description |
|---|---|---|---|---|
| `text` | string | yes | — | The utterance. Plain text; markdown is a rendering concern |
| `mood` | enum | no | `neutral` | `neutral`, `happy`, `excited`, `worried`, `sleepy`, `alarmed` |
| `durationMs` | integer | no | auto | Minimum display time. `auto` = f(text length), floored at ~1200 ms |
| `stream` | boolean | no | `false` | If true, the bubble stays open and expects `bubble.append` |
| `bubbleId` | string | no | generated | Reuse an existing bubble, e.g. to stream into it |

Default priority 60. Default TTL 15000 ms (or the streaming window if `stream` is true).

```json
{"id":"a1","ts":1759773421000,"verb":"say","args":{"text":"Build passed. 42 tests.","mood":"happy"}}
{"id":"a2","ts":1759773430000,"verb":"say","args":{"text":"Thinking","stream":true,"bubbleId":"b7"},"priority":55}
{"id":"a3","ts":1759773431000,"verb":"bubble.append","args":{"bubbleId":"b7","delta":" about that"}}
```

### 4.2 `emote`

Play a named affect. Does not move the body root and does not need a bubble.

| Arg | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | enum | yes | — | `happy`, `sparkle`, `confused`, `sleepy`, `alarmed`, `love`, `sweat`, `question` |
| `loops` | integer | no | `1` | `0` means loop until superseded |
| `intensity` | number | no | `1.0` | 0.0–2.0, scales amplitude |

Default priority 30. Default TTL 4000 ms.

```json
{"id":"b1","ts":1759773421000,"verb":"emote","args":{"name":"sparkle","loops":2}}
```

### 4.3 `moveTo`

Walk to a point. Physics-driven; the body eases in rather than teleporting.

| Arg | Type | Required | Default | Description |
|---|---|---|---|---|
| `x` | number | one of `x`/`y` or `anchor` | — | Absolute X in global display points |
| `y` | number | one of `x`/`y` or `anchor` | — | Absolute Y in global display points |
| `anchor` | enum | one of the above | — | See section 3 |
| `screen` | string | no | auto | Display index or id |
| `speed` | number | no | `1.0` | 0.25–3.0 multiplier on walk speed |
| `arc` | boolean | no | `false` | Hop/arc instead of walking |
| `queue` | enum | no | `replace` | `replace` cancels a pending move; `append` chains waypoints |

Default priority 40. Default TTL 10000 ms.

```json
{"id":"c1","ts":1759773421000,"verb":"moveTo","args":{"anchor":"bottom-right","speed":0.8}}
{"id":"c2","ts":1759773425000,"verb":"moveTo","args":{"x":1200,"y":830,"screen":"1"}}
```

### 4.4 `lookAt`

Turn the eyes and head toward a point. The body does not move and the walk cycle is unaffected.

| Arg | Type | Required | Default | Description |
|---|---|---|---|---|
| `x` / `y` | number | yes (or `anchor`/`target`) | — | Point to look at |
| `anchor` | enum | no | — | Named anchor instead of coordinates |
| `target` | enum | no | — | `cursor`, `front-window`, `menubar`, `user` |
| `holdMs` | integer | no | 2000 | How long to hold before returning to idle gaze |

Default priority 20. Default TTL 5000 ms.

```json
{"id":"d1","ts":1759773421000,"verb":"lookAt","args":{"target":"cursor","holdMs":3000}}
```

### 4.5 `face`

Set facing direction without moving.

| Arg | Type | Required | Default | Description |
|---|---|---|---|---|
| `direction` | enum | yes | — | `left`, `right`, `cursor`, `front-window` |
| `holdMs` | integer | no | 0 (until changed) | Revert to idle facing after this |

Default priority 20. Default TTL 10000 ms.

```json
{"id":"e1","ts":1759773421000,"verb":"face","args":{"direction":"front-window"}}
```

### 4.6 `state`

Force a high-level mode. Structural: it changes the whole behaviour profile.

| Arg | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | enum | yes | — | `idle`, `sleep`, `work`, `alert`, `hidden`, `celebrate` |
| `params` | object | no | `{}` | Mode-specific knobs, e.g. `{"fpsTier":"low"}` |
| `sticky` | boolean | no | `true` | If true, holds until another `state` intent; if false, reverts to `idle` after `ttl` |

Default priority 50. Default TTL 30000 ms. `hidden` is priority 90 and cannot be preempted except
by an explicit `state: idle`.

```json
{"id":"f1","ts":1759773421000,"verb":"state","args":{"name":"work","sticky":true}}
```

### 4.7 `bubble.show`

Show a silent information card. Unlike `say`, this is not an utterance: no mood animation, no
locomotion lock, and it may persist.

| Arg | Type | Required | Default | Description |
|---|---|---|---|---|
| `text` | string | yes | — | Body text |
| `style` | enum | no | `plain` | `plain`, `info`, `warning`, `success`, `code` |
| `ttlMs` | integer | no | 8000, `0` = sticky | Auto-dismiss after this |
| `anchor` | enum | no | `above-pet` | `above-pet`, `beside-pet`, `screen-corner` |
| `bubbleId` | string | no | generated | Returned in the ack; needed for `bubble.append`/`bubble.hide` |

Default priority 35. Default TTL 20000 ms.

```json
{"id":"g1","ts":1759773421000,"verb":"bubble.show","args":{"text":"3 files changed","style":"success","ttlMs":6000}}
```

### 4.8 `bubble.append`

Stream a delta into an open bubble.

| Arg | Type | Required | Default | Description |
|---|---|---|---|---|
| `bubbleId` | string | yes | — | Target bubble |
| `delta` | string | yes | — | Text to append. Never replaces existing content |
| `final` | boolean | no | `false` | Marks the stream complete; starts the dismiss timer |
| `ttlMs` | integer | no | — | Refresh the bubble's TTL on this append |

Default priority 55 (slightly below `say`, so a new `say` can preempt a stale stream). Default TTL
15000 ms.

```json
{"id":"h1","ts":1759773421000,"verb":"bubble.append","args":{"bubbleId":"b7","delta":"Done."}}
{"id":"h2","ts":1759773421200,"verb":"bubble.append","args":{"bubbleId":"b7","delta":"","final":true}}
```

Note: appending to an unknown or already-hidden `bubbleId` fails with `bad_args` rather than
silently creating a bubble. Producers that want create-on-first-write should send `say` with
`stream: true` first.

### 4.9 `bubble.hide`

Dismiss a bubble or all bubbles.

| Arg | Type | Required | Default | Description |
|---|---|---|---|---|
| `bubbleId` | string | no | — | Omit to hide all bubbles for the target pet |
| `reason` | enum | no | `producer` | `producer`, `timeout`, `user`, `preempted` |

Default priority 65 (above `say`, so a hide always wins). Default TTL 5000 ms.

```json
{"id":"i1","ts":1759773421000,"verb":"bubble.hide","args":{"bubbleId":"b7","reason":"user"}}
```

### 4.10 `spawn`

Create a pet instance. Structural; bypasses the behaviour stack of any existing pet.

| Arg | Type | Required | Default | Description |
|---|---|---|---|---|
| `petId` | string | yes | — | Caller-chosen id, unique. Reuse returns `duplicate_id` |
| `kind` | string | no | `pookie` | Pet kind/theme |
| `at` | object | no | `bottom-right` | Same shape as `moveTo` args (`x`/`y`/`anchor`/`screen`) |
| `name` | string | no | `petId` | Display name |

Default priority 75. Not rate-limited by the attention budget but capped by a pet capacity limit
(`capacity` error). Available from M8.

```json
{"id":"j1","ts":1759773421000,"verb":"spawn","args":{"petId":"pookie-2","kind":"pookie","at":{"anchor":"bottom-left"}}}
```

### 4.11 `despawn`

Remove a pet instance.

| Arg | Type | Required | Default | Description |
|---|---|---|---|---|
| `petId` | string | yes | — | Pet to remove |
| `exit` | enum | no | `poof` | `poof`, `walkOff`, `fade` |

Default priority 75. Cannot despawn the last remaining pet unless `exit: "quit"` is also passed.
Available from M8.

```json
{"id":"k1","ts":1759773421000,"verb":"despawn","args":{"petId":"pookie-2","exit":"walkOff"}}
```

### 4.12 `pet.on`

Subscribe to pet-emitted events on this connection. The only subscription verb.

| Arg | Type | Required | Default | Description |
|---|---|---|---|---|
| `event` | enum or array | yes | — | One of the events in section 6, or `["*"]` for all |
| `handler` | string | no | — | Opaque label echoed back in the event, for clients multiplexing producers on one socket |
| `filter` | object | no | — | Event-specific filter, e.g. `{"pet":"pookie-2"}` |

Default priority 10. No TTL (subscriptions do not expire; they die with the connection). Sending
the same subscription twice is idempotent.

```json
{"id":"l1","ts":1759773421000,"verb":"pet.on","args":{"event":["clicked","petted"],"handler":"cli-main"}}
```

Unsubscribing is done by closing the connection, or by `pet.on` with `{"event":[],"handler":"..."}`
to clear a handler.

---

## 5. Priority and preemption

| Priority | Behaviour | Default source | Interruptible by | Resumable |
|---:|---|---|---|---|
| 100 | `drag` | user, direct manipulation | nothing | no |
| 90 | `state: hidden` | user hotkey / `state` | nothing except `state: idle` | no |
| 75 | `spawn` / `despawn` | producer | n/a (structural) | n/a |
| 65 | `bubble.hide` | producer | `drag` | no |
| 60 | `say` | producer | `drag` | no |
| 55 | `bubble.append` | producer | `say`, `drag` | yes |
| 50 | `state` (non-hidden) | producer | `say`, `drag` | yes |
| 40 | `moveTo` / `follow` | producer, cursor follow | `say`, `drag` | yes |
| 35 | `bubble.show` | producer | `say`, `moveTo`, `drag` | yes |
| 30 | `emote` | producer | anything ≥ 35 | yes |
| 20 | `lookAt` / `face` | producer | anything ≥ 30 | yes |
| 10 | `pet.on` | producer | n/a | n/a |
| 0 | `idle` micro-behaviours | the pet itself | everything | yes |

Preemption rules (normative):

1. A strictly higher priority preempts the running action. **Equal priority never preempts** — it
   queues.
2. `drag` (100) clears the stack. Parked producer intents resume on `dropped` only if their TTL has
   not expired.
3. A running `say` holds a **locomotion lock**: `moveTo` and idle wander are deferred, not dropped.
   `lookAt`, `face`, `emote`, blink, breathing, and tail sway still run, because they do not move
   the body root.
4. **Idle wandering must never interrupt a sentence.** Idle is priority 0 and the wander scheduler
   is suspended for the whole duration of any action with priority > 0.
5. TTL is evaluated at dispatch, not only at arrival. Expired intents are dropped and acked with
   `ok: false, error: "expired"`.
6. Preemption emits internal `preempted` / `resumed` records for behaviour tests.

### Attention budget

The router enforces a per-producer budget to keep the pet from becoming a notification firehose.
Defaults, all configurable:

| Rule | Default |
|---|---|
| Max `say` per producer per minute | 6 |
| Minimum gap between two `say` intents | 2000 ms |
| Global concurrent bubbles | 1 (a second `say` preempts or coalesces; it does not stack) |
| `emote`/`lookAt` coalescing | Newest wins; older pending duplicates are dropped |
| Behaviour during Do Not Disturb / presentation | Only priority ≥ 65 delivered |

When the budget is exhausted, the intent is rejected with `rate_limited` and a `retry_after_ms`,
**not** queued without bound. Producers that care should back off; producers that do not should drop
the message, which is the correct outcome for a stale notification.

---

## 6. Event stream

Events are emitted by the pet on any connection subscribed via `pet.on`. Event lines have a distinct
shape from intents:

```json
{"event":"clicked","ts":1759773421000,"pet":"pookie","handler":"cli-main","data":{"button":"left","x":1420,"y":901}}
```

| Event | Fired when | `data` fields |
|---|---|---|
| `clicked` | User clicks the pet body | `button` (`left`/`right`), `x`, `y`, `clickCount` |
| `dragged` | Pet is being dragged. Coalesced to ~10 Hz, not per frame | `x`, `y`, `vx`, `vy` |
| `dropped` | Drag released and physics settled | `x`, `y`, `vx`, `vy`, `screen` |
| `petted` | Cursor strokes over the pet for ≥ ~300 ms without pressing | `x`, `y`, `durationMs` |
| `bubbleClicked` | User clicks a bubble | `bubbleId`, `x`, `y`, `link?` |

Event semantics:

- Events are **at-most-once per connection** and are not replayed. A reconnecting client loses what
  it missed; it should not rely on events for state.
- `dragged` is rate-limited and coalesced because the consumer is usually a producer that will do
  something expensive. Full-resolution motion is available in `dropped`'s final velocity.
- Events carry the `handler` label from the subscribing `pet.on` so a multiplexed client can route.
- Events are **not** sent to clients that did not subscribe, and are not sent on the control socket
  unless requested.

---

## 7. MCP surface sketch (M4)

The MCP server is a thin adapter: one tool per verb, same args, same priority defaults, same TTLs.
The value of the protocol design is that this adapter has no logic in it.

| MCP tool | Maps to verb | Notes |
|---|---|---|
| `pookie_say` | `say` | `text` required; returns `bubbleId` when `stream: true` |
| `pookie_emote` | `emote` | |
| `pookie_move_to` | `moveTo` | Accepts `anchor` or `x`/`y` |
| `pookie_look_at` | `lookAt` | |
| `pookie_face` | `face` | |
| `pookie_set_state` | `state` | Named `set_state` so it does not shadow generic "state" tooling |
| `pookie_bubble_show` | `bubble.show` | Returns `bubbleId` |
| `pookie_bubble_append` | `bubble.append` | For streaming markdown into an open bubble |
| `pookie_bubble_hide` | `bubble.hide` | |
| `pookie_spawn` | `spawn` | M8; registered but returns `unsupported` before then |
| `pookie_despawn` | `despawn` | M8 |
| `pookie_subscribe_events` | `pet.on` | See below |
| `pookie_poll_events` | — | Fallback for `pet.on`; see below |

`pet.on` does not map cleanly onto MCP, because the protocol's event stream is a push model while
most MCP clients are request/response.

- **Preferred:** `pookie_subscribe_events` registers the subscription server-side, and events are
  delivered as MCP notifications (server → client push, for example
  `notifications/pookie.event` with the payload from section 6).
- **Fallback:** `pookie_poll_events({since})` returns buffered events and is drained by the client on
  its own schedule.

**Flagged uncertainty:** whether server-initiated notifications are usable across the specific MCP
clients we target (Codex CLI, Claude Code) is not verified here. Assume `pookie_poll_events` is
required until it is tested in M4. Do not design a skill that depends on push events.

MCP-specific conventions:

- Tool descriptions must state the attention-budget behaviour, so an LLM does not spam `pookie_say`.
- The MCP server should default to slightly conservative priorities and longer TTLs than a human
  script would, because models over-call.
- Tools return the pet's ack (`ok`, `accepted`, `error`) rather than an empty success, so a model can
  see when it was rate-limited.

---

## 8. Versioning

- The protocol version is exchanged in `hello` / `hello.ok`.
- Additive changes (new optional args, new verbs, new events) do not bump the major version.
  Clients must ignore unknown fields and unknown events.
- Removing a verb, changing an arg's type, or changing default priority is a major bump.
- The pet rejects a client whose major version it does not support, with `unsupported`.
