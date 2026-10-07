# ADR-0003: The conversation brain runs out-of-process

- Status: Accepted
- Date: 2026-10-06
- Deciders: Lead
- Supersedes: none

## Context

From M5, Pookie has an LLM-backed conversation brain: it holds a chat history, calls a model,
streams tokens, and maintains memory. That brain is the least stable component in the system by a
wide margin:

- It depends on network calls that fail, hang, and rate-limit.
- It depends on SDKs and runtimes (Node or Python) that update constantly and break constantly.
- It holds large context buffers that grow, leak, and get compacted.
- It is the part we will iterate on most aggressively, and therefore restart most often.
- It may need heavyweight local dependencies (tokenizers, embedding models, vector stores).

The pet shell is the opposite: it is a small, long-lived, always-on-top UI process. If the shell
dies, the user's pet vanishes from the desktop and they notice immediately. If the shell restarts,
the pet disappears and reappears, which is jarring.

Putting an LLM client inside the shell means every brain crash, dependency upgrade, or memory leak
takes the pet with it. It also means every brain iteration requires rebuilding and relaunching the
whole app.

## Decision

**The LLM/conversation brain runs out-of-process**, as a separate local service — Node or Python —
listening on localhost, talking to the pet over the same intent protocol any other producer uses.

- The shell contains no model client, no SDK, no API keys, and no conversation state.
- The brain connects to the pet as an ordinary producer and drives it with `say`, `emote`,
  `bubble.append`, and friends.
- The brain can be written in Node or Python, whichever has the better library story at the time.
  The shell does not care.
- Restarting the brain is a normal operation. It must be possible to kill the brain mid-sentence and
  have the pet survive and recover.

This is a direct consequence of ADR-0002: because the pet is a renderer with a small verb
vocabulary, the brain was never going to be privileged code. ADR-0003 just makes that explicit and
adds the resilience requirement.

## Consequences

**Positive**

- **Restart the brain mid-conversation without killing the pet.** Upgrade a dependency, change a
  prompt, swap models, reload the vector store — the cat keeps sitting on the desktop.
- **Crash isolation.** A brain segfault or an unhandled promise rejection is a disconnected client,
  not a dead pet.
- **Language freedom.** Node today, Python later (or vice versa) with no shell changes. This matters
  for whisper.cpp bindings and embedding/ML tooling particularly.
- **Independent iteration.** The brain's build, test, and debug loop is a normal server loop with hot
  reload. No Xcode rebuild for a prompt change.
- **Resource isolation.** Tokenization and embedding spikes do not run on the shell's main thread and
  cannot cause frame drops in the pet.
- **The interface is already documented.** The brain speaks the same protocol as Codex and CI, so
  there is nothing new to specify.

**Negative / accepted costs**

- **Two processes to install, launch, and supervise.** The shell must manage the brain's lifecycle:
  start it, detect its death, restart it with backoff, and not spawn a storm of zombies.
- **IPC latency and complexity.** Token streaming now crosses a process and socket boundary. For text
  this is negligible; it is still a new failure surface.
- **No shared types.** The protocol is JSON, so version skew between shell and brain is possible and
  must be handled explicitly, with a protocol version in the handshake.
- **Debugging spans two logs.** Requires correlated request ids (the envelope `id`) end-to-end.
- **Secrets live in the brain process**, which is good for the shell's attack surface but means the
  brain needs its own key storage discipline.

## Required shell behaviour: resilience to brain disconnection

This is a hard requirement, not a nice-to-have. The shell must:

1. **Treat the brain as one producer among many.** Losing it must not affect the pet's ability to
   render, idle, or accept intents from anyone else.
2. **Detect disconnection promptly** (socket close, missed heartbeats) and mark the brain as absent.
3. **Degrade gracefully and visibly, but quietly.** An open streaming bubble should be completed with
   what arrived, or marked as interrupted — never left permanently half-typed, never silently
   discarded mid-word with no explanation.
4. **Never block on the brain.** No synchronous request/response call from the render thread. No
   "waiting for brain" UI state that freezes the pet.
5. **Apply TTLs and backpressure to the brain exactly as to any producer.** A reconnecting brain that
   replays its buffer must not produce a burst of stale speech.
6. **Reconnect with backoff, cap the retries, and surface a state.** After repeated failures the pet
   enters a plainly-noticed state (for example `state: sleepy` with a short bubble) rather than
   pretending everything is fine.
7. **Preserve conversation continuity across a brain restart.** Conversation state belongs to the
   brain, so it must persist to disk (or be rehydrated from the shell's event log) and survive a
   restart. A restarted brain resuming with an empty history is a product bug.
8. **Own the kill switch.** The user can stop the brain from the shell without quitting the pet.

## Revisit trigger

Only if the out-of-process boundary becomes the dominant source of bugs or perceptible latency, and
only after the resilience requirements above have been implemented and measured. Dropping the
boundary is a last resort, because it trades a supervised failure for an unsupervised one.
