# Release Candidate Report

Full bug audit of Echo Hunt performed as a release gate, covering player
spawning, ownership, multiplayer authority, input handling, character
movement, camera, round transitions, role switching, echo spawning/
playback, RPC synchronization, scene loading, lobby transitions, match
start, and match restart. No new gameplay systems were added — every
change below is a correctness fix to existing behavior.

Scope note: this audit was performed by static code review (reading
every script in the systems listed above, plus the project's own recent
debug docs — `NETWORK_FLOW.md`, `SOCKET_DEBUG.md`, `PACKET_TRACE.md`,
`UI_STATE_MACHINE.md` — which already contained live-verified findings
for the signaling/WebRTC layer). No Godot binary was available in this
environment to run the project's own `godot4 --headless --quit`
regression; **that verification step, and a real two-peer play session,
should be run before shipping** — see "Verification still required" at
the end of this report.

---

## Summary of the "can't move" family of bugs

The five reported symptoms —

- Sometimes only the Hider can move.
- Sometimes only the Hunter can move.
- Sometimes neither player can move.
- Controls stop responding after joining.
- Controls stop responding after role changes.

— all trace back to the same fact: `PlayerController._physics_process`
and `_input` gate every action on `is_multiplayer_authority()`, and
nothing in that gating logic ever looks at role (Hider/Hunter). So
"only the Hider can move" and "only the Hunter can move" are not two
different bugs — they're the **same** bug (a peer's own body silently
never receives multiplayer authority) observed at two different points
in a match. Round 1's Hider is always the host (`RoleManager.
assign_roles`, deterministic sort-by-peer-id), and this project's
WebRTC transport hardcodes peer ids to host=1/client=2
(`WebRTCSignaler._setup_webrtc`), so *which* role reads as "frozen"
just depends on whether the affected peer is currently Hider or
Hunter when the underlying authority assignment fails — which is
exactly why it presents as "sometimes Hider, sometimes Hunter, sometimes
both."

Root cause, found and fixed below (Finding 2): a same-frame race between
a departing player's body being torn down and a fast reconnect's new
body being spawned. Findings 3 and 6 harden the same code path so this
failure mode can never again fail *silently* if some other edge case
reaches it.

---

## Findings and fixes

### Finding 1 — Backward movement permanently dead (Character movement / Input handling)

**File:** `Scripts/Player/PlayerController.gd:117`

**Root cause:** `Input.get_vector("move_left", "move_right",
"move_forward", "move_backward")` references an action named
`"move_backward"`. The actual InputMap entry defined in `project.godot`
is named `"move_back"` (bound to the S key). `"move_backward"` does not
exist anywhere in the project.

Godot's `Input.get_vector()` resolves each named action against the
InputMap; an action that isn't registered contributes a strength of 0
and logs an engine error on every call. Concretely, this meant:
- The S key never produced backward movement, for either player, in
  every build — a 100%-reproducible, always-on bug, not a "sometimes."
- The error was logged on every single physics frame in every session
  (spammy enough to bury genuinely useful console output during a live
  debugging session).

**Fix:** changed the action name to `"move_back"`, matching
`project.godot`'s actual InputMap.

**How to test:** host or join a match, enter the lobby (free-roam is
allowed there), hold S. The character should now walk backward.
Previously it did nothing. Also confirm the console no longer logs an
InputMap error every frame.

---

### Finding 2 — Reconnect race can permanently strand a peer with no player body (Player spawning / Ownership / Multiplayer authority)

**Files:** `Scripts/World/Main.gd` (`_on_peer_disconnected_server`,
`_spawn_player`)

**Root cause:** on disconnect, the server did:
```gdscript
var node := players_container.get_node_or_null(str(id))
if node != null:
    node.queue_free()
```
`queue_free()` is **deferred** — the node stays a live child of
`players_container`, under its original name, until the end of the
current frame. `_spawn_player()`'s own re-entrancy guard is:
```gdscript
if players_container.has_node(str(peer_id)):
    return
```
This project's WebRTC transport hardcodes peer ids
(`WebRTCSignaler._setup_webrtc`: host is always peer 1, the client is
always `webrtc_mp.create_client(2)` / peer 2) — unlike ENet, where a
reconnecting peer gets a fresh id, **a reconnecting client here always
comes back as the exact same peer id it had before.** If that
reconnect's `_spawn_player(peer_id)` call landed before the previous
body's deferred free actually ran (a real possibility for a fast
drop/reconnect — a network blip, or the existing bounded WebSocket
retry in `WebRTCSignaler` firing quickly), `has_node()` still saw the
old, soon-to-be-deleted node and the guard **silently skipped spawning
a new body entirely**. The reconnecting peer would then have no player
node under `Players/` at all — nothing for a `MultiplayerSpawner` to
replicate, nothing for `_on_node_spawned` to assign authority to. That
peer's controls (and camera) would never respond for the rest of the
session, with no error anywhere.

This is the concrete mechanism behind "controls stop responding after
joining" and, transitively (since round 1's Hider is always the host
and roles alternate), the "only Hider" / "only Hunter" reports.

**Fix:** `players_container.remove_child(node)` before `queue_free()`.
`remove_child()` is synchronous, so the name slot is free immediately —
a same-frame respawn under the same peer id can never collide with a
node that's merely *pending* deletion.

**How to test:** host + join, start a match, force-drop the client's
connection (e.g. kill and relaunch the client process, or briefly
disable its network adapter) and reconnect within a couple of seconds
— fast enough to land inside the old ~1-frame window. Before the fix
this could leave the reconnecting client's character un-controllable
(WASD/mouse-look do nothing, camera doesn't activate) with no console
output explaining why. After the fix the reconnecting client always
gets a fresh, controllable body. Repeat several times in a row (rapid
disconnect/reconnect) since this was a timing race, not a guaranteed
repro on any single attempt.

---

### Finding 3 — Silent authority-assignment failures now surfaced (defensive hardening)

**File:** `Scripts/World/Main.gd` (`_spawn_player`, `_on_node_spawned`)

**Root cause:** two failure modes in the spawn/authority path had zero
diagnostic trace:
1. `_spawn_player()`'s `has_node()` guard (see Finding 2) returned early
   with no log line — a skipped spawn was indistinguishable from "this
   peer was already spawned on purpose."
2. `_on_node_spawned()`'s `node_name.is_valid_int()` guard — protecting
   against Godot auto-suffixing a node's name on a collision with an
   existing sibling (e.g. `"2"` becoming `"2 2"`) — silently left that
   node's multiplayer authority at its default (the server) with no log
   line. A node in that state can never be moved by its actual owning
   peer, and there was previously no way to tell this had happened from
   the logs.

**Fix:** both branches now `push_warning()` with a message that
explains the likely cause and the player-facing symptom ("this peer
won't be able to move"), consistent with this project's existing
practice of surfacing previously-silent failure modes rather than
tolerating them quietly (see `PACKET_TRACE.md` Finding 4, same pattern
applied to RPC/WS payload handling).

**How to test:** no behavior change in the success path. To exercise
the warning paths deliberately, reproduce Finding 2's race (fast
reconnect) — if the timing ever lands such that a collision still
occurs for some other reason in the future, the Godot console/log will
now show exactly which peer and node name failed, instead of a silent,
undiagnosable frozen player.

---

### Finding 4 — Reconnect-grace-expiry reset was never broadcast to the surviving peer (Round transitions / RPC synchronization)

**File:** `Scripts/Autoload/RoundManager.gd`,
`Scripts/World/Main.gd` (`_on_reconnect_grace_ended_server`)

**Root cause:** when a disconnected peer's reconnect grace window
(`NetworkManager.RECONNECT_GRACE_PERIOD`, 20s) expires without them
coming back, `Main.gd` called:
```gdscript
func _on_reconnect_grace_ended_server(_role: int, reconnected: bool) -> void:
    if not reconnected:
        RoundManager.reset_state()
```
`RoundManager.reset_state()` is a **plain local function call** — it
mutates that peer's own `hider_id`/`hunter_id`/`round_active`/timer and
calls `MatchStateManager.reset()`, all locally. This handler only runs
on the server (`NetworkManager.reconnect_grace_ended` is a server-only
signal, connected only inside Main.gd's `if multiplayer.is_server()`
block). The result: the server resets to the lobby, but the **surviving
client is never told** — its `RoundManager` keeps believing a round is
active, with `hider_id`/`hunter_id` pointing at a peer that no longer
exists, its HUD keeps counting down a timer for a round the server has
already abandoned, and nothing will ever correct it because
`reset_state()`'s only caller for this path never sent anything over
the wire. This is a genuine host/client state divergence — squarely in
"Round transitions" and "RPC synchronization" — surfaced by this audit,
independent of the "can't move" family above.

**Fix:** added `RoundManager.broadcast_reset_state()` (server-only) plus
a `_reset_state` RPC (`@rpc("authority", "call_local", "reliable")`,
matching the exact pattern already used by `_apply_round_state`,
`_end_round`, and `_reset_match` in the same file), and pointed
`Main.gd`'s handler at it instead of the local-only call.

**How to test:** host + join, start a match, then force-drop the
client's connection **without reconnecting** and wait out the full 20s
grace window. Before the fix: the host's HUD correctly returns to the
lobby, but if you reconnect a fresh client process afterward it should
show a fresh 0-0 lobby too — the bug is specifically observable via
added logging/state inspection (`RoundManager.round_active` on a
peer that stayed connected through someone else's grace-window
expiry, in a 3+-peer-over-time test session, would show `true` when it
should be `false`). After the fix, `_reset_state` fires on every
connected peer, so state never diverges from the server's.

---

### Finding 5 — Reconnecting peer's scoreboard stuck at 0-0 (Match restart / RPC synchronization)

**Files:** `Scripts/Autoload/MatchStateManager.gd`,
`Scripts/Autoload/RoundManager.gd`

This was already a documented, diagnosed gap
(`KNOWN_ISSUES.md` #2: "Reconnect forgets the score... Fix: include
both scores in `RoundManager._resync_after_reconnect`") with an exact
prescribed fix. Fixed here since it's the same reconnect-resync RPC
already touched by Finding 4 and squarely within the audited scope
(Match restart / RPC synchronization).

**Root cause:** `RoundManager.reassign_role()` → `_resync_after_reconnect.rpc(...)`
only ever sent `hider_id`, `hunter_id`, `round_active`, and `time_left`.
Ordinary score increments travel exclusively through `_end_round`'s
`call_local` RPC — a peer that wasn't connected yet when an earlier
round ended in the same match never received that RPC at all, so its
own `MatchStateManager.hunter_score` / `hider_score` stay at their
initial `0`/`0` for the rest of the session, regardless of the real
score, until the next round happens to end and correct it by accident.

**Fix:** `_resync_after_reconnect` now also carries
`hunter_score`/`hider_score`, and a new `MatchStateManager.sync_scores()`
applies them (and emits `score_changed`, so the Scoreboard UI updates
immediately rather than waiting for the next round).

**How to test:** host + join, play to a 1-0 or 2-1 score, then
force-drop and reconnect the client mid-match (inside the grace
window). Before the fix, the reconnecting client's scoreboard read
`0 — 0` until the next round ended. After the fix, it should show the
correct live score immediately on reconnect.

---

### Finding 6 — Echo ghosts never replay real animation (Echo spawning / Echo playback)

**File:** `Scripts/Echo/EchoRecorder.gd`

**Root cause:** `EchoRecorder.set_target()` looked up the Hider's
animation player with:
```gdscript
_target_anim_player = target.get_node_or_null("AnimPlayer") as AnimationPlayer
```
i.e. a direct child of the player body literally named `"AnimPlayer"`.
This matched an earlier version of `Player.tscn`. The current
`Player.tscn` (since "Replace proto pill with custom player model and
logic") nests its real `AnimationPlayer` inside the imported model —
`Model/ModelInstance/...` — at a depth that isn't fixed (it depends on
the glTF/FBX import). `Scripts/Player/components/animation_component.gd`
already handles this correctly with a recursive search
(`_find_anim_player`); `EchoRecorder` was never updated to match and
regressed silently.

**Effect:** `target.get_node_or_null("AnimPlayer")` always returned
`null`, so `_current_animation_name()` always returned `""`, so every
recorded sample's `"anim"` field was empty, so
`EchoGhost._update_animation("")` always no-op'd (`if anim_name == "":
return`). The echo ghost still replayed **position** correctly (that
comes from the transform, unaffected by this bug) but never played any
recorded animation — a visually static/idle-posed ghost gliding along
the correct path instead of visibly walking/running/jumping, directly
undermining the core echo-reading mechanic ("track the echoes... sound
and ghost trails betray the hider" — GAMEPLAY_SYSTEMS.md /
ECHO_SYSTEM.md).

**Fix:** replaced the flat lookup with a recursive `_find_anim_player()`
helper (same approach as `AnimationComponent`), so `EchoRecorder`
correctly finds the AnimationPlayer regardless of how deep the imported
model nests it.

**How to test:** start a round, have the Hider run/jump around for at
least 10 seconds (the buffer window), then observe the echo ghost once
it appears. Before the fix, the ghost slides along its path in a fixed
idle pose. After the fix, it should visibly walk/run/jump matching what
the Hider actually did 10 seconds earlier.

---

## Verified clean (no fix needed)

Walked through explicitly per the requested checklist; no defects
found beyond what's listed above:

- **Ownership model:** every `CharacterBody3D` is named by its owning
  peer id (`player.name = str(peer_id)`) and looked up the same way
  everywhere (`RoundManager._get_player_node`, `Main._respawn_local_player`,
  `Main._on_role_assigned`) — one body per peer, no cross-ownership found.
- **Input isolation:** both `_input()` and `_physics_process()` in
  `PlayerController.gd` gate on `is_multiplayer_authority()` before
  reading `Input`/`Input.get_vector` — a puppet body never reads local
  input, it only interpolates from replicated position (see the
  `not is_multiplayer_authority()` branch).
- **Camera isolation:** `apply_authority_state()` is the single place
  `Camera3D.make_current()` is called, gated the same way; re-invoked on
  every spawn path (`_spawn_player` server-side, `_on_node_spawned`
  client-side) rather than only in `_ready()`, which is what the
  1.0.1 changelog's "stuck in first person" fix already established —
  confirmed intact and consistent across both spawn paths.
- **Round transitions / role switching:** `RoundManager` role
  assignment (`RoleManager.assign_roles`) is a pure, deterministic
  function of connected peer ids and preferences; movement gating
  (`RoundManager.round_active or MatchStateManager.is_in_lobby()`) does
  not reference role at all, confirming the "only Hider/only Hunter"
  reports are an authority bug, not a role-logic bug (see Finding 2).
- **Win conditions:** `WinConditions.is_capture`/`is_timeout` are pure,
  stateless, and only ever evaluated server-side
  (`RoundManager._check_for_capture`, gated on `multiplayer.is_server()`).
- **Scene loading order:** `Main.gd` correctly decouples "the scene/
  MultiplayerSpawner exists" from "map content has loaded" (`MapManager.
  is_map_ready()` / `map_selected` signal), so a client's own
  `MultiplayerSpawner` is always ready to receive replicated spawns
  regardless of map-sync timing — matches the documented intent in both
  `Main.gd` and `NetworkManager._on_connected_to_server`'s comments.
- **Lobby transitions / match start:** cross-checked against
  `UI_STATE_MACHINE.md`'s full signal audit (every declared signal vs.
  every `.connect()` call site) — no missing wiring found on the Menu →
  Connecting → Loading → Lobby → Gameplay chain beyond what that
  document's own findings already fixed.

---

## Verification still required before shipping

This audit was performed by static reading of every file in scope, not
by running the engine (no Godot binary was available in this sandbox).
Before release:

1. Run `godot4 --headless --quit` to confirm all six edited files still
   compile with zero errors (this project's own standard check, per
   `PACKET_TRACE.md`/`SOCKET_DEBUG.md`).
2. Run the two-peer regression described in `TEST_PLAN.md` /
   `TESTING_GUIDE.md` end to end.
3. Specifically re-run the fast-disconnect/reconnect scenario from
   Finding 2 several times in a row — it was a timing race, so a single
   pass is not sufficient evidence it's closed.
4. Visually confirm Finding 6 (echo now animates) and Finding 1
   (backward movement) in a live session — both are trivially
   observable but were not previously covered by the automated
   two-process regression described in `TEST_PLAN.md`.

## Files changed

- `Scripts/Player/PlayerController.gd` — Finding 1
- `Scripts/World/Main.gd` — Findings 2, 3, 4
- `Scripts/Autoload/RoundManager.gd` — Findings 4, 5
- `Scripts/Autoload/MatchStateManager.gd` — Finding 5
- `Scripts/Echo/EchoRecorder.gd` — Finding 6
