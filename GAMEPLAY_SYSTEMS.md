# Gameplay Systems

This document covers every gameplay system in Echo Hunt: what it owns,
how it talks to the rest of the game, and how to test it in isolation.
See [`PROJECT_STRUCTURE.md`](PROJECT_STRUCTURE.md) for where each file
lives in the folder tree, and [`STABILIZATION_REPORT.md`](STABILIZATION_REPORT.md)
for the reliability work this architecture grew out of.

## Design principle: one job per module

Every system below does exactly one thing and exposes a small, explicit
API to the rest of the game. Nothing reaches into another system's
internals — they only talk through public functions and signals. This
means you can read (and test) the entire win/lose ruleset by opening one
~20-line file, without wading through networking or rendering code.

```
NetworkManager  (connection lifecycle only)
      │
      ▼
RoundManager  ──uses──▶  RoleManager   (who hides / hunts next)
      │        ──uses──▶  RoundTimer    (the countdown)
      │        ──uses──▶  WinConditions (capture / timeout checks)
      │
      ▼ (on round end)
MatchStateManager  (cumulative score, match phase)
      │
      ▼
Scoreboard  (UI)          HUD  (timer / role / round-end UI)

Main.gd  ──uses──▶  SpawnManager  (spawn-point lookup, respawn)
```

---

## Round Manager

**File:** `Scripts/Autoload/RoundManager.gd` (autoload singleton)

Owns everything about the *current* round: who's Hider, who's Hunter,
whether a round is active, and the countdown. It's the only system
authorized to decide a round has started or ended — and only on the
server (`multiplayer.is_server()`); every other peer just receives that
decision via RPC and updates its own local copy.

**Public API:**
- `register_players_container(container: Node)` — called once by
  `Main.gd` so RoundManager can look up player nodes by peer id.
- `start_match()` — server-only; called when the host presses Start
  Match in the warm-up lobby (see UI_GUIDE.md). Kicks off round 1;
  every later round starts itself after `NEXT_ROUND_DELAY`, with roles
  swapped.
- `start_round()` — server-only. Picks roles via `RoleManager`, starts
  the timer, and replicates the new round state to every peer. Captures
  are suppressed for the first `CAPTURE_GRACE` seconds of each round
  (covers the respawn-replication window; see OPTIMIZATION_REPORT.md).
- `request_rematch()` — callable from **any** peer, but only once the
  match is over (Game Over screen); forwards to the server, which
  resets the score on every peer and starts round 1 again.
- `reset_state()` — clears all round state. Called on disconnect so a
  lost connection can never leave the game stuck mid-round.

**Public state:** `hider_id`, `hunter_id`, `round_active`, `time_left`.

**Signals:** `role_assigned(peer_id, role)`, `round_started`,
`round_ended(winner_role)`.

**Testing:**
1. Host + join, press Start Match in the lobby; confirm
   `RoundManager.round_active` becomes `true` on both peers.
2. Confirm `role_assigned` fires exactly twice per round start (once per
   player) and each peer's HIDER/HUNTER role chip matches what
   `hider_id`/`hunter_id` actually holds.
3. See "Round transitions" and "Win / Lose conditions" below for the
   rest of this system's behavior.

---

## Match State Manager

**File:** `Scripts/Autoload/MatchStateManager.gd` (autoload singleton)

Owns everything that spans *multiple* rounds: cumulative score and the
overall match phase. Deliberately separate from RoundManager — this
system doesn't know or care *how* a round was won, only that one was.

**Public API:**
- `begin_round()` — called by RoundManager when a round starts. Sets
  `phase = ROUND_ACTIVE`.
- `record_round_result(winner_role)` — called by RoundManager when a
  round ends. Increments the winner's score; sets `phase = MATCH_OVER`
  if that score reaches `ROUNDS_TO_WIN`, else `ROUND_ENDED`.
- `is_match_over()`, `match_winner_role()`, `round_number()`,
  `is_in_lobby()` — small queries used by the HUD, RoundManager, and
  PlayerController (warm-up movement).
- `reset()` — zeroes both scores and returns to `LOBBY`. Called
  alongside `RoundManager.reset_state()` on disconnect, and on rematch.

**Public state:** `hunter_score`, `hider_score`, `phase`
(`MatchPhase.LOBBY` / `ROUND_ACTIVE` / `ROUND_ENDED` / `MATCH_OVER`).

**Signals:** `score_changed(hunter_score, hider_score)`,
`phase_changed(new_phase)`.

**Match rule:** a match is **first to `ROUNDS_TO_WIN` (3) round wins**.
Every peer reaches the match-over conclusion independently from the
same replicated round results, so no extra synchronization exists for
it. (The original MVP had endless "Play Again" rounds; the UX pass —
see UI_GUIDE.md — replaced that with the lobby → rounds → game over →
rematch structure.)

**Testing:**
1. Play a round to completion. Confirm `score_changed` fires exactly
   once, with the correct score, on both peers.
2. Restart and play a second round with the other outcome (capture vs.
   timeout). Confirm both `hunter_score` and `hider_score` can each
   increment correctly and independently.
3. Disconnect one peer mid-match, reconnect a fresh pair, and confirm
   the score reads `0 — 0` again (see `reset()`).

---

## Win Conditions / Lose Conditions

**File:** `Scripts/Gameplay/WinConditions.gd` (static, no state)

There is exactly one way a round can end in this game, and it always
produces one winner and one loser — so "win conditions" and "lose
conditions" are two names for the same rule, checked from two
perspectives:

| Condition | Winner | Loser |
|---|---|---|
| `WinConditions.is_capture(hunter_pos, hider_pos)` — Hunter gets within `TOUCH_RADIUS` (1.3m) of the Hider | Hunter | Hider |
| `WinConditions.is_timeout(time_left)` — the round clock reaches zero first | Hider | Hunter |

Both are pure functions — no scene tree access, no signals, nothing to
mock to test them in isolation. `RoundManager` is the only caller: it
checks `is_capture()` every physics frame (server-only) and reacts to
`RoundTimer.expired` for the timeout case.

**Testing:**
1. As Hunter, walk directly into the Hider. Confirm the round ends
   immediately with "Hunter wins!" on both peers and
   `MatchStateManager.hunter_score` increments.
2. Let a round run out the clock without any contact. Confirm "Hider
   wins!" on both peers and `hider_score` increments instead.
3. Edge case: stand exactly `TOUCH_RADIUS` meters apart and slowly close
   the distance — the round should end the instant you cross 1.3m, not
   only on an exact/closer touch.

---

## Timer

**File:** `Scripts/Gameplay/RoundTimer.gd` (`class_name RoundTimer`,
instantiated by `RoundManager`, not an autoload itself)

A small, reusable countdown with no game rules baked in — it only knows
how to count down and say `expired`. `RoundManager` owns one instance
(created in `_ready()`) and decides what "expired" means (a timeout
loss).

**Public API:** `start(duration: float)`, `stop()`.
**Public state:** `time_left`, `running`.
**Signal:** `expired`.

Every peer runs its own local `RoundTimer` instance (all started
together via the same `_apply_round_state` RPC), so the HUD counts down
smoothly on every screen — but only the **server's** copy reaching zero
actually ends the round (`RoundManager._on_timer_expired()` checks
`multiplayer.is_server()` before acting).

**Testing:**
1. Start a round, watch the HUD timer count down from `01:30` (90s) on
   both peers in lockstep (small drift of a fraction of a second between
   two independent processes is normal; anything visibly desynced is
   not).
2. Let it reach `00:00` — confirm the round ends via timeout (see Win
   Conditions above) and the timer doesn't go negative or freeze before
   zero.

---

## Team Assignment / Hunter Selection / Hider Selection

**File:** `Scripts/Gameplay/RoleManager.gd` (static, no state)

In a 2-player game, "which team is this player on" and "is this player
the Hunter or the Hider" are the same question — so all three of these
concerns (team assignment, Hunter selection, Hider selection) live in
one pure function: `RoleManager.assign_roles(connected_peer_ids,
previous_hider_id) -> {hider_id, hunter_id}`.

**Rule:** if the previous Hider is still connected, they stay Hider
(used for the very first round, where there's no "previous" — it
defaults to the lowest peer id, i.e. the host). On every restart,
`RoundManager` explicitly flips `previous_hider_id` to the outgoing
Hunter before calling this again, so **roles always swap on restart** —
both players get a turn at both roles.

**Testing:**
1. First round after the host presses Start Match: confirm the host is
   always Hider and the joining player is always Hunter (deterministic,
   not random — makes this easy to test repeatably).
2. Let the next round auto-start after the transition countdown:
   confirm roles swap (host becomes Hunter, the other player becomes
   Hider).
3. Next round: confirm they swap back. Roles alternate every round,
   never repeating the same assignment twice in a row.

---

## Round Transitions & Rematch

**File:** `Scripts/Autoload/RoundManager.gd` (`_end_round()` /
`_on_next_round_delay_elapsed()` / `request_rematch()`)

Rounds chain themselves: when a round ends and the match *isn't* over,
the server schedules the next round `NEXT_ROUND_DELAY` (5 s) later —
the HUD counts down the same constant locally, so nothing extra is
synchronized. The scheduler re-checks the world before firing (peer
still connected, phase still `ROUND_ENDED`), so a disconnect during the
breather can't start a broken round.

Once a player reaches `ROUNDS_TO_WIN`, nothing is scheduled — the Game
Over screen's **Rematch** is the only way forward. Either peer may
request it (`request_rematch()` → `rpc_id(1, ...)`); the server ignores
it unless the match is actually over, then resets the score on every
peer and starts round 1 via the same `start_round()` path as always.

**Testing:**
1. End a round either way (capture or timeout) with the score below
   match point: confirm the transition panel counts down and the next
   round starts by itself on *both* windows, roles swapped.
2. Win a match (3 round wins): confirm Game Over appears on both peers
   with opposite VICTORY/DEFEAT headlines and no auto-restart.
3. Click **Rematch** from the **losing** window. Confirm both windows
   reset to 0–0 and round 1 starts (rematch isn't gated by who won).

---

## Spawn Management / Respawning

**File:** `Scripts/World/SpawnManager.gd` (static, no state)

Looks up the current map's spawn points (`Marker3D` nodes in the
`hider_spawn` / `hunter_spawn` groups — see `MAP_SYSTEM.md`) and places a
player body there. `Main.gd` calls `SpawnManager.respawn_player()` for
the *local* player only, whenever `RoundManager.round_started` fires —
each peer only ever moves the body it has multiplayer authority over;
the `MultiplayerSynchronizer` replicates that new position to everyone
else.

**Why "spawn management" and "respawning" are the same system here:**
this MVP's hide-and-seek design ends the round the instant the Hider is
caught (see Win Conditions) — there's no "lose a life, respawn, keep
playing" mid-round loop for this game type. So the only time a player
needs placing is at the start of a round or a restart, which is exactly
what `SpawnManager` does. This is a deliberate design fit, not a missing
feature — see Recommendations in `STABILIZATION_REPORT.md` if a future
mode ever wants mid-round respawns.

**Testing:**
1. Start a round — confirm the Hider spawns at one corner of the arena
   and the Hunter at the opposite corner (not overlapping, not inside
   geometry).
2. Restart several times — confirm spawn points swap along with roles
   (whoever is Hider always spawns at the Hider marker, regardless of
   who that peer was last round).
3. Temporarily rename a map's spawn group (e.g. typo `hider_spawn` in
   the editor) and confirm `SpawnManager` logs a `push_warning` instead
   of crashing — this is what protects against a future map missing a
   spawn marker.

---

## Scoreboard

**File:** `Scripts/UI/Scoreboard.gd` (attached to `HUD.tscn`'s
`ScoreLabel` node)

Purely a rendering layer over `MatchStateManager` — it owns no state of
its own, just listens for `score_changed` and updates its label text.
Deliberately independent of `HUD.gd`'s other responsibilities (timer,
role label, round-end panel), so it could be reused in a different
screen (e.g. a future spectator view) without dragging any of that along.

**Testing:**
1. Confirm the scoreboard reads `Hunter 0 — 0 Hider` before any round
   ends.
2. After a Hunter win, confirm it updates to `Hunter 1 — 0 Hider` on
   **both** peers' screens.
3. Confirm it persists correctly across a restart (score is cumulative,
   not reset per round — only `MatchStateManager.reset()` on disconnect
   clears it).

---

## Full end-to-end test

Once every system above checks out individually, run the complete loop
end to end (this is also covered in `TESTING_GUIDE.md`): host, join,
play a round to a capture, restart, play a second round to a timeout,
restart again, and confirm score, roles, and spawn points are all
correct throughout — with no application restart required at any point.
