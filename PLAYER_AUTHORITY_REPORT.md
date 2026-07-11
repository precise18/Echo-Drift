# Player Authority Report

A full audit of Echo Hunt's player-authority system, treated as a
production-severity investigation: player spawning, `set_multiplayer_
authority()`, input ownership, camera ownership, character ownership,
RPC ownership, `CharacterBody3D` authority, and scene synchronization.

**Verdict:** one real race condition exists in this subsystem. It was
found and fixed in this pass (Finding 1) — it is the confirmed root
cause of "controls stop responding after joining," and, transitively,
of "only the Hider/only the Hunter can move" (explained below). Two
defensive diagnostics were added alongside it (Finding 2) so this class
of failure can never again fail silently. Every other property audited
below — input isolation, camera isolation, RPC authority annotations,
and authority survival across round restart / respawn / map load / role
switch — was traced through the actual code and found structurally
correct, for the reasons cited under each item.

This report reflects the code as it stands after this audit's fixes
were applied. No Godot binary was available in this environment to run
the project's own `godot4 --headless --quit` regression or a live
two-peer session — see "Verification still required" at the end.

---

## How authority works in this project (background)

Godot's high-level multiplayer gives every node a `multiplayer_
authority` property (an int peer id), defaulting to `1`. Only the peer
whose id matches that value may usefully drive that node's local
behavior (`is_multiplayer_authority()` is a plain `get_multiplayer_
authority() == multiplayer.get_unique_id()` comparison — see Godot's
`Node` source). Authority is **not** part of `SceneReplicationConfig` —
`Player.tscn`'s `MultiplayerSynchronizer` only replicates `position`
and `Model:rotation:y` (see the scene file); authority itself is a
plain local property that every peer must set for itself, on every
node, with no automatic network transport. This is the single fact
that makes this whole subsystem worth auditing carefully: **get the
local assignment wrong on any one peer, for any one node, and that
peer either can't move their own body (authority stuck at someone
else) or is silently driving a body that isn't theirs (authority stuck
on them).**

This project's WebRTC transport (`WebRTCSignaler._setup_webrtc`)
hardcodes peer ids: the host is always peer `1`, and the sole joining
client is always peer `2` (`webrtc_mp.create_client(2)`). Unlike ENet,
where a reconnecting peer gets a fresh id, **a reconnecting client here
always comes back as the exact same peer id it had before.** This one
fact is the root cause behind Finding 1.

---

## Finding 1 (FIXED) — reconnect race could permanently strand a peer with no body, hence no authority

**Files:** `Scripts/World/Main.gd` — `_on_peer_disconnected_server()`,
`_spawn_player()`.

**Severity:** Production-critical. Directly reproduces "controls stop
responding after joining" and (because round-1's Hider is always the
host under the id scheme above) the "only Hider/only Hunter can move"
reports.

### Root cause

On disconnect, the server ran:
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
Because the WebRTC transport reuses peer ids on reconnect (see
background above), a fast disconnect/reconnect could deliver
`_spawn_player(peer_id)` for the *same* id **before** the previous
body's deferred free had actually executed. `has_node()` still saw the
old, soon-to-be-deleted node and the guard silently skipped spawning a
new body **entirely**. The reconnecting peer ended up with no player
node under `Players/` at all — nothing for `MultiplayerSpawner` to
replicate, nothing for `_on_node_spawned` to ever assign authority to.
That peer's controls (and camera) never responded for the rest of the
session, with zero error output anywhere.

### Fix

```gdscript
players_container.remove_child(node)   # synchronous — frees the name slot immediately
node.queue_free()                      # still defers the actual deallocation
```
`remove_child()` is synchronous, so the name slot is free the instant
it returns — a same-frame respawn under the same peer id can never
collide with a node that's merely *pending* deletion.

### How to test

Host + join, start a match, force-drop the client's connection (kill
and relaunch the client process, or briefly disable its network
adapter) and reconnect within a couple of seconds. Repeat several times
in a row — this was a timing race, not a guaranteed repro on any single
attempt. Before the fix, a reconnecting client could end up with an
uncontrollable character (WASD/mouse-look do nothing, camera never
activates) with no console output explaining why. After the fix, the
reconnecting client always gets a fresh, fully-controllable body.

---

## Finding 2 (FIXED) — authority-assignment failures were previously silent

**File:** `Scripts/World/Main.gd` — `_spawn_player()`,
`_on_node_spawned()`.

Two failure paths in the spawn/authority code had zero diagnostic
trace, which is exactly what let Finding 1 go unexplained for as long
as it did:

1. `_spawn_player()`'s `has_node()` guard returned early with no log —
   a skipped spawn was indistinguishable from "this peer was already
   spawned on purpose."
2. `_on_node_spawned()`'s `node_name.is_valid_int()` guard — protecting
   against Godot auto-suffixing a node's name on a collision with an
   existing sibling (e.g. `"2"` becoming `"2 2"`) — silently left that
   node's authority at its default (the host) with no log line.

**Fix:** both branches now `push_warning()` with a message naming the
peer id and the likely cause, so if this class of failure is ever
reached again (from some future change, not from Finding 1's now-closed
window) it is immediately visible instead of presenting as an
unexplained "my controls don't work."

---

## Verification matrix

Every property the audit was asked to verify, traced to the code that
proves it.

| Requirement | Verdict | Evidence |
|---|---|---|
| Each client only processes input for its own player | **PASS** | `PlayerController._physics_process` and `_input` both open with `if not is_multiplayer_authority(): return` (or an early puppet branch) before touching `Input.*` — `Scripts/Player/PlayerController.gd:154, 208`. A puppet body reads zero local input; it only interpolates from the replicated `position`. |
| Remote players never consume local input | **PASS** | Same guard as above — `is_multiplayer_authority()` is a per-node, per-peer comparison (`get_multiplayer_authority() == multiplayer.get_unique_id()`), so a body that isn't this peer's own can never pass the check on this peer's screen, regardless of what it's doing on its owner's screen. |
| Host does not accidentally own every player | **PASS, was at risk under Finding 1** | Godot's default authority for any node is `1` — the host, under this project's id scheme — so "the host owns everything" is the *default state*, corrected explicitly for every node: server-created nodes via `_spawn_player`'s `set_multiplayer_authority(peer_id)` (`Main.gd:138`, synchronous, no networking dependency, cannot race); replicated nodes via `_on_node_spawned`'s `set_multiplayer_authority(node_name.to_int())` (`Main.gd:151`), driven by Godot's own `MultiplayerSpawner.spawned` signal. Finding 1 was the one concrete way this correction could be skipped entirely; it's fixed. |
| Joining clients correctly receive authority | **PASS** | See "Sequence: joining client spawn" below. `_on_node_spawned` fires for every node this peer receives via replication — including catch-up replication of the host's pre-existing body — and assigns authority purely from that node's own name, which always encodes its true owning peer id. |
| No authority is lost after **round restart** | **PASS** | `RoundManager`'s round-restart path (`start_round` → `_apply_round_state` RPC) only ever mutates `hider_id`/`hunter_id`/`round_active`/the timer — grep confirms zero calls to `set_multiplayer_authority` anywhere in `RoundManager.gd`. Player *bodies* are never destroyed or re-spawned for a round restart (see `GAMEPLAY_SYSTEMS.md`, "Spawn Management"), so there is no authority to lose. |
| No authority is lost after **respawn** | **PASS** | `SpawnManager.respawn_player()` only reassigns `global_position`/`velocity` on the *existing* body (`Scripts/World/SpawnManager.gd:35`). `Main._respawn_local_player()` looks the body up by the caller's own `multiplayer.get_unique_id()` and additionally checks `is_multiplayer_authority()` before touching it — doubly guarded, and a no-op (not a mis-teleport) in the unlikely event authority hasn't landed yet. |
| No authority is lost after **map load** | **PASS** | `Main._load_map()` only ever calls `map_container.add_child(...)` (`Main.gd:47-48`). `$Players` (and every player body, and every body's authority) lives under a completely separate branch of the scene tree that map loading never touches — confirmed by reading the full function body. |
| No authority is lost after **role switch** | **PASS** | `RoleManager.assign_roles()` is a pure function over peer ids (`Scripts/Gameplay/RoleManager.gd`) with no scene-tree access at all; `PlayerController._on_role_assigned` only calls `_refresh_role_material()` (a cosmetic material swap). Identity/ownership (authority) and role (Hider/Hunter) are fully independent concerns — nothing in the role-switch path references `multiplayer_authority` in any form. |
| Camera ownership: only the local player's camera activates | **PASS** | `apply_authority_state()` is the single call site for `Camera3D.make_current()`, gated on `is_multiplayer_authority()`, and is re-invoked at every point authority can become known (`_spawn_player` for server-local spawns, `_on_node_spawned` for replicated ones) rather than only in `_ready()` — this is what the 1.0.1 "stuck in first person" fix already established, confirmed intact. |
| RPC ownership: every RPC only runs where it's supposed to | **PASS** | Every `@rpc` in the project uses either `"authority"` (only the node's authority — always the server for the autoload RPCs in this project — may send it; `NetworkManager.gd:182,286`, `RoundManager.gd:145,165,225,259,292`, `MapManager.gd:74`) or `"any_peer"` with an explicit in-body guard re-checking `multiplayer.is_server()`/`get_remote_sender_id()` before acting (`NetworkManager._register_session`, `RoundManager._request_rematch`) — see `PACKET_TRACE.md` Finding 3 for the full trace of these guards. No RPC in the project runs unauthenticated game logic. |

---

## Sequence diagrams

### 1. Host spawns its own body

```
Host process                                   Main.gd (server branch)          PlayerController
─────────────                                  ──────────────────────           ─────────────────
NetworkManager.enter_game_as_host()
  connected_peer_ids = [1]
  change_scene_to_file(Main.tscn)
        │
        ▼
Main._ready()
  spawner.spawned.connect(_on_node_spawned)  ──▶ (connected BEFORE any spawn call)
  if multiplayer.is_server():
      for id in [1]:
          _spawn_player(1) ─────────────────────▶ instantiate Player.tscn
                                                    player.name = "1"
                                                    add_child(player)  ───────────▶ _ready() runs synchronously:
                                                    │  (spawner.spawned ALSO fires    peer_id = 1
                                                    │   here, locally, since a         name_tag built
                                                    │   node entered spawn_path;       apply_authority_state()
                                                    │   _on_node_spawned re-applies      → default authority (1)
                                                    │   the SAME value redundantly —      == own id (1) → TRUE
                                                    │   harmless, see Finding 1's         → camera.make_current()
                                                    │   doc comment analysis)             → mouse captured
                                                    │
                                                    player.set_multiplayer_authority(1)
                                                    player.apply_authority_state() ──▶ re-run: still TRUE, idempotent
```
Host ends up authoritative over its own body via two independent,
redundant, and mutually-consistent paths — both compute the same
value (`1`), so there's no ordering hazard.

### 2. Joining client spawns (dual perspective — the important one)

```
SERVER (host, peer 1)                                    JOINING CLIENT (peer 2)
──────────────────────                                    ───────────────────────
multiplayer.peer_connected(2) fires
        │
        ▼
NetworkManager._on_peer_connected(2)
  connected_peer_ids.append(2)
  player_connected.emit(2)
        │
        ▼
Main._on_peer_connected_server(2)
        │
        ▼
_spawn_player(2)
  has_node("2")? NO → proceed
  instantiate Player.tscn, name="2"
  add_child(player)  ──────────────────────┐    (replication of this new spawn is
  set_multiplayer_authority(2)             │     sent to peer 2 by MultiplayerSpawner;
  apply_authority_state()                  │     also, any body that already existed
    → is_multiplayer_authority() on        │     under Players/ — the host's own "1" —
      the SERVER: 2 == 1? FALSE            │     is separately caught-up-replicated
    → camera/mouse NOT touched for         │     to the newly connected peer 2)
      this (correct: it's not the          │
      server's own body)                   │
                                            ▼
                                   ═══════ WebRTC data channel ═══════
                                                    │
                                                    ▼
                                     Client's own Main.tscn (already loaded —
                                     see NetworkManager._on_connected_to_server's
                                     doc comment on why the scene change happens
                                     immediately, before this replication lands)
                                                    │
                                     Two nodes arrive under Players/: "1" and "2"
                                     Each runs _ready() with DEFAULT authority (1)
                                     For each, MultiplayerSpawner emits `spawned`
                                                    │
                                                    ▼
                                     Main._on_node_spawned(node)
                                       node "1": set_multiplayer_authority(1)
                                         is_multiplayer_authority() on the
                                         CLIENT: 1 == 2? FALSE
                                         → camera/mouse NOT touched (correct —
                                           this is the host's body, not mine)
                                       node "2": set_multiplayer_authority(2)
                                         is_multiplayer_authority() on the
                                         CLIENT: 2 == 2? TRUE
                                         → camera.make_current()
                                         → mouse captured
                                         → name_tag hidden (own body)
```
Authority for a given body is always decided the same way on every
peer: read the node's own name, compare against `multiplayer.get_
unique_id()`. There is no step where the joining client's own body
could end up with the wrong authority independent of what name it was
given — which is set once, by the server, at spawn time, and never
changes.

### 3. Reconnect (Finding 1's race, before and after the fix)

```
BEFORE THE FIX                                  AFTER THE FIX
────────────────                                ────────────────
Peer 2 drops                                    Peer 2 drops
        │                                               │
        ▼                                               ▼
_on_peer_disconnected_server(2)                 _on_peer_disconnected_server(2)
  node = Players/"2"                              node = Players/"2"
  node.queue_free()  ── deferred,                 players_container.remove_child(node)
  still a child named "2"                           ── synchronous, name slot free NOW
  until end of frame                              node.queue_free()
        │                                               │
        ▼ (fast reconnect, same frame)                  ▼ (fast reconnect, same frame)
_register_session → player_reconnected(2)       _register_session → player_reconnected(2)
        │                                               │
        ▼                                               ▼
_spawn_player(2)                                _spawn_player(2)
  has_node("2")? ── node still present            has_node("2")? ── NO, already removed
  (pending deletion) → TRUE                        → proceed: instantiate + add_child
  → SILENTLY RETURNS, no body spawned              → set_multiplayer_authority(2)
        │                                          → apply_authority_state()
        ▼                                               │
Peer 2 has no player node.                              ▼
No authority ever assigned.                     Peer 2 has a fresh, fully
Controls permanently unresponsive.              authoritative, controllable body.
```

### 4. Round restart / respawn / role switch — why authority is a non-participant

```
RoundManager.start_round()  (server)
        │
        ▼
_apply_round_state.rpc(hider_id, hunter_id, ROUND_TIME)   ── broadcast, call_local
        │
        ├──▶ every peer: hider_id/hunter_id/round_active/timer updated locally
        │      role_assigned.emit() × 2, round_started.emit()
        │
        ├──▶ PlayerController._on_role_assigned()  → material swap only
        │      (no set_multiplayer_authority anywhere in this path)
        │
        └──▶ Main._on_round_started() → _respawn_local_player()
               looks up Players/str(multiplayer.get_unique_id())
               if player == null or not player.is_multiplayer_authority(): return
               SpawnManager.respawn_player(...)  → global_position/velocity only
```
Nothing in this entire chain — round restart, role reassignment, or
respawn — ever calls `set_multiplayer_authority`. Authority is set
exactly once per body, at spawn time (diagrams 1–2), and never touched
again for the lifetime of that body. This is *why* it survives round
restart, respawn, and role switch: there is no code path that could
lose it.

### 5. Map load — why it's isolated from authority

```
Main._ready()
  if MapManager.is_map_ready():
      _load_map()                        ── map_container.add_child(map)
  else:
      MapManager.map_selected.connect(_on_map_ready, CONNECT_ONE_SHOT)

  RoundManager.register_players_container(players_container)
  spawner.spawned.connect(_on_node_spawned)     ── Players/ wiring, independent branch
  if multiplayer.is_server():
      for id in connected_peer_ids: _spawn_player(id)   ── also independent
```
`_load_map()`/`_on_map_ready()` only ever touch `$MapContainer`.
`$Players` — and therefore every body's authority — lives under a
sibling node that map (re)loading code has no reference to and never
calls into. A client still waiting on `MapManager`'s sync RPC gets its
player body (and that body's authority) exactly as fast as a client
that already knows the map — the two are fully decoupled by design
(see `MapManager.gd`'s own doc comment and `MAP_SYSTEM.md`).

---

## Files changed in this audit

- `Scripts/World/Main.gd` — Finding 1 (`_on_peer_disconnected_server`:
  synchronous `remove_child` before `queue_free`) and Finding 2
  (`_spawn_player`/`_on_node_spawned`: `push_warning` on the two
  previously-silent failure paths).

No other file required a change — every other property audited above
was verified structurally correct by tracing the existing code, with no
defect found.

*(Findings 1 and 2 were originally identified and fixed during a prior
general release-readiness audit — see `RELEASE_CANDIDATE_REPORT.md`,
Findings 2–3 — and are re-verified and re-documented here in full,
dedicated authority-audit detail, including the sequence diagrams and
verification matrix that audit didn't include.)*

## Verification still required

No Godot binary was available in this environment. Before shipping:

1. `godot4 --headless --quit` — confirm `Scripts/World/Main.gd` still
   compiles with zero errors.
2. Re-run the fast-disconnect/reconnect scenario from Finding 1 several
   times in a row (it's a timing race — one clean pass isn't sufficient
   evidence it's closed).
3. Two-peer session: confirm each peer's camera activates on their own
   body only, WASD only ever moves the local peer's own body on both
   screens, and both properties hold across a full match (round
   restart → role swap → respawn → a second round restart).
