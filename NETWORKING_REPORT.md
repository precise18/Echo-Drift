# Networking Report

A review and improvement pass over Echo Hunt's multiplayer layer: ENet
via Godot's high-level multiplayer API, host-authoritative, exactly 2
peers. This document covers what changed, why, the architecture as it
stands now, its known limitations, and how to test every change.

---

## Architecture Diagram

```
┌─────────────────────────────┐        ┌─────────────────────────────┐
│   HOST (peer id 1, server)  │        │  CLIENT (peer id: random)   │
│                              │        │                              │
│  NetworkManager (authority) │◀──────▶│  NetworkManager              │
│   - session registry        │  ENet  │   - local_session_id         │
│   - reconnect grace windows │  :7777 │   - join_game() / reconnect  │
│                              │        │                              │
│  RoundManager (authority)   │        │  RoundManager (mirror)       │
│   - hider_id / hunter_id    │  RPCs  │   - receives round state     │
│   - RoundTimer              │──────▶ │     via reliable RPCs        │
│   - WinConditions checks    │        │                              │
│                              │        │                              │
│  MatchStateManager          │  RPCs  │  MatchStateManager           │
│   - score, match phase      │──────▶ │   - mirrors score/phase      │
│                              │        │                              │
│  Players/ (MultiplayerSpawner)        │  Players/ (replicated)       │
│   1/  <- host's own body    │  spawn │   1/  <- replicated          │
│   N/  <- client body(s)     │  +sync │   N/  <- owns & moves this   │
│                              │──────▶ │       one locally            │
└─────────────────────────────┘        └─────────────────────────────┘

Per-player MultiplayerSynchronizer (unreliable, ON_CHANGE):
  .:position            (Vector3, only sent when it actually changes)
  BodyMesh:rotation:y    (float, Y-axis facing only)

Round/match events (reliable RPCs, authority -> all or any_peer -> authority):
  RoundManager._apply_round_state    (round start)
  RoundManager._end_round            (capture or timeout)
  RoundManager._request_restart      (any peer -> server)
  RoundManager._resync_after_reconnect (server -> all, on reconnect)
  NetworkManager._register_session   (any peer -> server, on every connect)

Echo system: zero extra network traffic (each peer independently
buffers the already-replicated Hider position/rotation it receives
above — see ECHO_SYSTEM.md).
```

---

## What changed, and why

### Reliable synchronization

Already correctly split before this pass, confirmed and documented
here: **round/match *events*** (round start, round end, restart,
reconnect resync, session registration) are `@rpc(..., "reliable")` —
these are discrete facts that must never be dropped or arrive
out-of-order. **Continuous *state*** (player position/rotation) is
synced via `MultiplayerSynchronizer`, which uses an unreliable channel
by design — a dropped position packet is harmless because the next one
(arriving a fraction of a second later) supersedes it; making it
reliable would only add retransmission latency for no benefit. This
mix — reliable for events, unreliable for continuous state — is the
standard, correct pattern and was already in place; this pass didn't
need to change it, only confirm and document the reasoning.

### Spawn synchronization

Already solid from the stabilization pass (server explicitly sets
multiplayer authority right after `add_child()`, since
`MultiplayerSpawner`'s `spawned` signal only fires on *receiving* peers,
not the originating server — see `STABILIZATION_REPORT.md`). Re-verified
in this pass's regression tests; no changes needed.

### Player disconnect handling (improved)

Previously: any disconnect during a round immediately called
`RoundManager.reset_state()`, discarding the round and returning both
peers to square one. Now: a mid-round disconnect starts a
`RECONNECT_GRACE_PERIOD` (20s) hold instead of an immediate reset (see
Reconnect support below), and the surviving peer sees a clear "Opponent
disconnected — waiting Ns to reconnect..." message instead of the round
just silently stalling. A disconnect *between* rounds (no active round
to preserve) still resets immediately, unchanged.

### Reconnect support (new)

**Design:** each running client generates a random
`local_session_id` once at startup and sends it to the server on every
connection attempt (`NetworkManager._register_session`, reliable RPC).
When a peer disconnects mid-round, the server doesn't immediately clear
their role — it calls `NetworkManager.hold_reconnect_slot(session_id,
role)`, which remembers `{role, expires_at}` and starts a 20-second
countdown. If a *new* connection arrives within that window carrying the
*same* session id, the server recognizes it as the same player
returning (even though ENet gave them a brand-new peer id — ids are
never reused) and:

1. Re-spawns their `Player` body (`Main._on_player_reconnected_server`).
2. Restores their previous role under the new peer id
   (`RoundManager.reassign_role`).
3. Re-broadcasts the *current* authoritative state (roles, active flag,
   remaining time) to **every** connected peer — not just the
   reconnecting one, because the peer who stayed connected still has the
   departed player's *old* id cached in `hider_id`/`hunter_id` and needs
   correcting too.

If the window expires with no matching reconnect, `RoundManager.
reset_state()` runs — exactly the old immediate-reset behavior, just
delayed by up to 20 seconds to give a real reconnect a chance first.

**Scope, deliberately:** this supports the same running game process
reconnecting (e.g. a brief WiFi drop, then `NetworkManager.join_game()`
called again) — not restarting the app and somehow resuming. See Known
Limitations for exactly where this stops.

### Host migration — practical equivalent, not literal migration

See Known Limitations for why true seamless host migration isn't
practical here. What *is* implemented: when the host disappears, the
client is returned to the menu immediately with a clear reason
("Host disconnected.") via `NetworkManager.last_disconnect_reason`,
displayed by `MainMenu.gd`, and can click **Host Game** immediately to
start a fresh session — no restarting the application, no silent
failure.

### Round synchronization (extended)

Already RPC-driven and correct for the normal flow (see Reliable
synchronization above). Extended in this pass to also handle the
previously-nonexistent case of a peer joining *mid-round* — which can
now happen via reconnect — through `_resync_after_reconnect`, which
dumps current round state to a rejoining session instead of leaving
them at default `(-1, -1, false)` values.

### Latency

Local input is already zero-latency by design: each peer has full
authority over its own body and moves it immediately on input, with no
round-trip to the server before responding (see `PlayerController.gd` —
`is_multiplayer_authority()`-gated movement). The only latency-sensitive
things are (a) seeing the *other* player/echo move, which is cosmetic
and forgiving for this game's pace, and (b) round-event RPCs (start/end/
restart), which are small, infrequent, and reliable — their delivery
time is dominated by actual network RTT, not anything this codebase
controls. The bandwidth reduction and movement smoothing below are the
concrete levers that exist for a project at this scope; see Known
Limitations for what's deliberately not chased further.

### Movement smoothing / network interpolation

Enabled Godot's built-in physics interpolation
(`physics/common/physics_interpolation=true` in `project.godot`, plus
`physics_interpolation_mode = 1` (ON) on `Player.tscn`'s root). This
interpolates the *rendered* transform between the last two committed
physics-tick transforms, regardless of what caused the change — so it
smooths both ordinary local movement (nicer on high-refresh-rate
displays) and, more importantly, the visual "snap" that would otherwise
be visible on a remote player's body each time
`MultiplayerSynchronizer` writes a newly-received position. This is the
standard, engine-supported way to solve this in Godot 4.1+, used instead
of a hand-rolled lerp system: less code, no custom per-frame
interpolation logic to maintain, and it's exactly what the feature is
documented and designed for.

### Network prediction — deliberately not implemented

"Where appropriate" is the operative phrase, and it isn't, here.
Client-side prediction with server reconciliation exists to solve one
problem: hiding round-trip latency on actions a *server* must validate
before they're real (e.g. "did that shot land"). This game has no such
action — each peer already has full local authority over its own
movement (no server validation, no rollback needed, zero added latency
by construction), and the two things that *are* server-authoritative
(capture detection, round timer) are simple binary checks whose result
is immediately confirmed via a reliable RPC — there's nothing for a
client to usefully "predict" about whether it got caught; guessing
either matches the server's answer trivially or doesn't matter for a
few hundred milliseconds in a game with a 90-second round timer.
Building prediction/reconciliation here would add real complexity for
no perceptible benefit.

### Bandwidth reduction

Two changes to `Player.tscn`'s `SceneReplicationConfig`:

1. **`replication_mode` changed from `ALWAYS` to `ON_CHANGE`** for both
   synced properties. `ALWAYS` sends a value every sync tick regardless
   of whether it changed; `ON_CHANGE` only sends when it actually
   differs from what was last sent. A player standing still (which,
   for a Hider trying not to be found, is a lot of the game) now sends
   **zero** position/rotation traffic instead of continuous updates.
2. **Rotation sync narrowed from a full `Vector3` to just its Y
   component** (`BodyMesh:rotation:y` instead of `BodyMesh:rotation`) —
   the character only ever rotates around the vertical axis, so the X
   and Z components were always zero and always being sent anyway.
   12 bytes → 4 bytes for that property, a 66% cut on every update that
   *does* fire.

Combined with the echo system's already-zero added network cost (see
`ECHO_SYSTEM.md`), the entire game's steady-state bandwidth is now
dominated purely by *actual movement* of up to 2 characters, each
capped at 16 bytes (12-byte position + 4-byte rotation) per change,
sent only on change rather than continuously.

---

## Known Limitations

- **True host migration isn't practical for this architecture**, and
  isn't attempted. Migration (promoting a client to become the new
  authoritative server mid-session) requires either (a) a rendezvous/
  matchmaking service so the other peer(s) can discover the new host's
  address, or (b) both peers already knowing each other's direct address
  ahead of time. This project is explicitly peer-hosted with no
  dedicated server (per the original project brief: "NO dedicated
  servers"), and with exactly 2 players, if the host leaves there is by
  definition only one player left — there's no one to migrate *to* that
  isn't already the sole survivor. The practical equivalent implemented
  (clear messaging + instant re-host) is the honest answer for a 2-peer
  topology without a rendezvous server, not a limitation of the
  implementation effort.
- **Reconnect only covers the same running process.** It relies on
  `local_session_id`, which is generated fresh every time the game
  starts and never persisted to disk. Closing and reopening the
  application before reconnecting will not be recognized as the same
  session — this is a deliberate scope boundary (a persisted identity
  system is a meaningfully bigger feature, and unnecessary for the
  target use case of "brief network hiccup, not a full restart").
- **Reconnecting after the round already ended via timeout while you
  were away is a minor rough edge.** `_resync_after_reconnect` correctly
  reports `round_active = false` in this case (it never forces a round
  back open that legitimately ended), but the reconnecting peer's HUD
  won't retroactively show the round-end panel/winner message they
  missed — they'll just see no active timer until the next restart.
  Rare (requires disconnecting in roughly the round's final 20 seconds)
  and cosmetic, not fixed in this pass.
- **The reconnect grace period (20s) is a fixed constant**
  (`NetworkManager.RECONNECT_GRACE_PERIOD`), not currently
  configurable from a settings UI. Easy to change in code; not exposed
  as a player-facing option since this MVP has no settings menu at all
  (explicitly out of scope per the project brief).
- **No network prediction**, by design — see above.
- **Bandwidth reduction is about *waste*, not a hard cap.** There's no
  rate-limiting/throttling of sync frequency (e.g. capping to a fixed
  Hz) — updates still send as fast as they change, which is correct for
  this game's low player count and slow pace, but wouldn't scale to
  many more simultaneous players without revisiting.

---

## Testing Guide

### 1. Reliable synchronization / round events
1. Host + join, play a round to a capture.
2. Confirm the "Hunter wins!" panel and score appear on **both** screens
   within the same frame or two of each other (reliable RPC delivery).

### 2. Spawn synchronization
1. Host + join. Confirm both players see two distinct characters spawn
   at opposite corners, each window showing its own camera behind its
   own character.

### 3. Disconnect handling + reconnect (the main new behavior)
1. Host + join, let a round start.
2. Close the **joining** window (or otherwise drop its connection)
   without quitting the whole test harness / app process.
3. On the host's screen, confirm the "Opponent disconnected — waiting
   Ns to reconnect..." message appears and the round timer keeps
   counting down underneath it (it does **not** freeze or reset).
4. Within 20 seconds, reconnect using the **same running client**
   (same app instance) via **Join Game** again with the host's IP.
5. Confirm: the reconnecting player is placed back in the arena, their
   role (Hider or Hunter) matches what it was before they dropped, the
   round timer continues from roughly where it left off (not reset to
   90s), and the host's "waiting to reconnect" message disappears.
6. Repeat, but this time **do not** reconnect within 20 seconds. Confirm
   the round cleanly resets (host returns to a restartable state,
   message disappears) instead of hanging forever.

### 4. Host migration (practical equivalent)
1. Host + join, get into a round.
2. Close the **host's** window.
3. On the **joining** player's screen, confirm they're returned to the
   main menu with a "Host disconnected." message visible (not a silent
   or confusing blank menu).
4. Confirm they can immediately click **Host Game** and start hosting
   their own new session without restarting the application.

### 5. Round synchronization after reconnect
Covered by test 3, step 5 — the key thing to verify is that **both**
peers (not just the reconnecting one) show the same `hider`/`hunter`
assignment after a reconnect, since the surviving peer's old cached ids
need correcting too, not just the rejoining peer's.

### 6. Movement smoothing / interpolation
1. Host + join on two separate windows (ideally two physical machines
   or at least visibly separate windows, not overlapping).
2. Move one character around continuously (walk, sprint, turn).
3. Watch that character from the **other** window. Motion should look
   continuous, not like a series of discrete teleports/snaps between
   positions — most noticeable when comparing before/after this pass on
   a deliberately throttled/high-latency connection, but should look
   smooth even locally.

### 7. Bandwidth reduction
1. Host + join, then have one player stand **completely still** for 10+
   seconds while the other watches Godot's Network Profiler (Debugger
   panel → Network Profiler, available when running from the editor).
2. Confirm no `.position`/`rotation` sync traffic is shown for the
   stationary player during that window (`ON_CHANGE` correctly sending
   nothing when nothing changed) — traffic should resume the instant
   they move again.

### 8. Full regression (nothing broken by this pass)
Run the complete checklist in `TESTING_GUIDE.md` end to end — this pass
changed networking robustness and traffic patterns, not gameplay rules,
so every existing behavior (capture, timeout, restart, role swap, echo
system) should work exactly as before.
