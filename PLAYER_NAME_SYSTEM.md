# Player Name System

A floating, billboarded name tag above every player, with a
host/joiner-entered display name synchronized over multiplayer RPC. This
document explains exactly how that synchronization works, how the tag
itself stays readable and never clips into the player, and why the
whole system survives round restarts, role switches, respawns, and map
switches with no special-case code for any of them.

## The one-paragraph version

Each peer types a name into a `LineEdit` on the title screen (persisted
locally via `GameSettings`). The moment that peer connects — host or
joiner — it sends that name to the server as part of the *existing*
session-registration RPC (`NetworkManager._register_session`, which
already carried a session id and preferred role; display name is just a
third field on the same message). The server is the single source of
truth: it decides the final name (using a deterministic "Player N"
fallback if the field was left blank), stores it in one
`peer_id -> String` dictionary, and rebroadcasts that **whole
dictionary** to every connected peer over a second RPC
(`_sync_player_names`). From then on, every `PlayerController` — for
every player, on every peer's screen — reads its own body's name
straight out of that already-synced local dictionary. No further
networking happens for names after that broadcast; rendering a tag is a
pure local read.

---

## Architecture

```
Peer types a name (title screen)
        │
        ▼
GameSettings.display_name          (persisted, user://settings.cfg)
        │
        ▼  read at connect time
NetworkManager.enter_game_as_host() / _on_connected_to_server()
        │
        ▼
_register_session(session_id, preferred_role, display_name)   ◀── RPC ("any_peer", "call_local", "reliable")
        │  (server only acts on it)
        ▼
NetworkManager._apply_display_name(peer_id, display_name)
        │  blank? → deterministic "Player N" fallback
        │  else  → trimmed, capped to 20 chars
        ▼
peer_display_names[peer_id] = final_name        (server's authoritative dict)
        │
        ▼
_sync_player_names.rpc(peer_display_names)      ◀── RPC ("authority", "call_local", "reliable"), broadcast
        │  (every connected peer, including the server itself via call_local)
        ▼
NetworkManager.peer_display_names = names       (now identical on every peer)
player_names_changed.emit()
        │
        ▼
PlayerController._refresh_name_tag()            (every player body, every peer, local read only)
        │
        ▼
NetworkManager.get_display_name(peer_id)  →  name_tag.text
```

Two RPCs, both reusing patterns already established elsewhere in this
codebase (`_register_session`, `_apply_round_state`, `_reset_match`) —
no new networking pattern was introduced:

| RPC | Config | Direction | Purpose |
|---|---|---|---|
| `_register_session` | `any_peer, call_local, reliable` | peer → server (`rpc_id(1, ...)`) | Carries the requesting peer's chosen name to the server, alongside the session id and preferred role it already carried. |
| `_sync_player_names` | `authority, call_local, reliable` | server → all peers (broadcast) | Delivers the server's decided, final `peer_id -> name` map to every peer, including itself. |

### Why broadcast the whole dictionary instead of one changed entry

`_sync_player_names` always sends the **complete** `peer_display_names`
dictionary, not a diff. This means every peer's local copy is always a
full, self-consistent snapshot — there's no way for two peers to end up
with different partial views if messages happened to arrive in a
different order, and no accumulated-diff bugs to worry about as players
connect, disconnect, and reconnect over a session. This mirrors the
same "send the whole current state, not an incremental patch" principle
`RoundManager._resync_after_reconnect` already uses for round state.

### Why this doesn't need `MultiplayerSynchronizer` / scene replication

Player names are **session-scoped metadata about a peer**, not
per-frame gameplay state about a body — they never change after
registration (there's no in-match "rename" feature), and every peer
needs to know every *other* peer's name, not just the name of the body
whose position it's already receiving. Piggybacking this onto
`Player.tscn`'s `MultiplayerSynchronizer` (which only replicates
`position` and `Model:rotation:y` at gameplay tick rate) would tie a
one-time registration value to a system built for continuous physics
state, and would only reach peers *while that specific player's body
already exists* — the RPC approach delivers the name registry
independently of body spawn timing, and every `PlayerController`
subsequently reads it from a shared autoload rather than depending on
replicated per-node data.

---

## The tag itself

**File:** `Scripts/Player/PlayerController.gd` (`_build_name_tag()`,
`_refresh_name_tag()`), built as a `Label3D` child named `NameTag`,
constructed in code in `_ready()` — the same way this script already
builds its raycasts and footstep emitter, rather than hand-authored
into `Player.tscn`.

| Requirement | How it's satisfied |
|---|---|
| **Face the camera (billboard)** | `Label3D.billboard = BaseMaterial3D.BILLBOARD_ENABLED`. This is a built-in engine feature — the label's transform is re-oriented to face whichever camera is rendering it, on every viewer's screen independently, with no per-frame script code. |
| **Scale correctly with distance** | `Label3D` is a normal `Node3D` positioned in world space (not a `Control`/HUD element) — like any 3D object, perspective projection alone makes it appear smaller far away and larger up close. No manual distance/scale math was written or needed; `pixel_size` (kept at the engine default, `0.01`) just controls how many world-meters one text-texture pixel covers, i.e. the base sizing, while perspective handles the rest. |
| **Never clip into the player** | Anchored at a fixed local height, `NAME_TAG_HEIGHT = 2.2`, **above the `CharacterBody3D` root itself** — not above `$Model`. This matters because `$Model` gets rescaled and repositioned at runtime by `_autofit_model()` (so different-height meshes still fit the ~1.8m capsule); `NameTag` is a sibling of `$Model`, not a child of it, so it's completely unaffected by that scale/position adjustment and always sits a consistent ~0.4m above the top of the (fixed-size) collision capsule regardless of what model is loaded underneath. |
| **Remain readable** | `shaded = false` (unlit — full brightness regardless of local scene lighting, so it's never darkened standing in a shadow), a bold outline (`outline_size = 14`, near-black `outline_modulate`) for contrast against any background, `double_sided = true`, and a generous `font_size = 48`. `no_depth_test` is left `false` on purpose — the tag is still occluded by walls/geometry like a real object in the world, which reads as intentional/professional rather than an X-ray gimmick. |

### Own name never blocks the camera

`PlayerController.apply_authority_state()` — already the single place
this script decides "is this body mine?" for camera activation and
mouse capture (see `RELEASE_CANDIDATE_REPORT.md` for why that function
exists and is re-invoked on every spawn path) — now also sets:

```gdscript
if name_tag != null:
    name_tag.visible = not is_multiplayer_authority()
```

This is a **purely local, per-viewer decision** with no networking
involved: every peer independently hides the tag on the one body it has
authority over (its own) and shows every other body's tag. Since
`apply_authority_state()` already runs at every point authority can
become known or change (initial local spawn, replicated spawn on a
remote peer, reconnect), the tag's visibility is correct at exactly the
same moments the camera/mouse-capture state already is — no separate
timing to get right.

---

## Default names: "Player 1", "Player 2", ...

`NetworkManager._default_display_name(peer_id)` sorts
`connected_peer_ids` and returns `"Player %d"` for that peer's 1-based
position in the sorted list. This is applied:

- **Server-side**, in `_apply_display_name()`, whenever a peer's
  submitted name is empty or whitespace-only after trimming.
- **Client-side (defensively)**, in `get_display_name()`, as the
  fallback if a peer's id isn't in `peer_display_names` yet at all
  (e.g. a tag is drawn in the brief window before `_sync_player_names`
  has arrived) — so a tag is never blank, even transiently.

Because this project's WebRTC transport hardcodes peer ids (host is
always peer 1, the sole joining client is always peer 2 — see
`WebRTCSignaler._setup_webrtc`), this fallback is fully deterministic
in practice: an unnamed host is always "Player 1" and an unnamed joiner
is always "Player 2", matching the requirement exactly.

---

## Surviving round restart, role switching, respawn, and map switching

None of these four events receive any special-case handling in the name
system — they don't need it, because of *where* the two pieces of state
live:

| Event | What actually happens | Why the name tag is unaffected |
|---|---|---|
| **Round restart** | `RoundManager` resets `round_active`/timer and re-runs role assignment (`_apply_round_state`). Player *bodies* are never destroyed or re-spawned for this — see `GAMEPLAY_SYSTEMS.md`, "Spawn Management". | `NameTag` is a permanent child of the (unchanged) `CharacterBody3D`; `NetworkManager.peer_display_names` is an autoload-level dictionary untouched by round state. Nothing here ever runs code that could clear either. |
| **Role switching** | `RoleManager.assign_roles` flips who's Hider/Hunter each round; `PlayerController._on_role_assigned` only updates the body's material color. | Identity (the name) and role (Hider/Hunter) are deliberately separate concerns — the same separation `SkinRegistry`'s own doc comment already establishes for skin color ("identity, not role"). Role switching has no code path that touches `name_tag` at all. |
| **Respawn** | `SpawnManager.respawn_player()` only reassigns `global_position` and zeroes `velocity` on the existing body. | `NameTag` is a child node with a fixed *local* offset (`Vector3(0, 2.2, 0)`) — it moves with the body automatically as part of the normal scene tree transform hierarchy, the same way the camera and collision shape do. No respawn-specific code exists for it because none is needed. |
| **Map switching** | `Main._load_map()` only ever adds/replaces content under `$MapContainer`. | `$Players` (and everything under it, including every `NameTag`) is a completely separate branch of the scene tree that `MapManager`/`Main._load_map()` never touches. |

The only way a name tag's *text* ever changes after spawn is the
`NetworkManager.player_names_changed` signal, which every
`PlayerController` subscribes to in `_ready()` — so even if the
registry RPC happens to land after a body has already spawned (a
reconnecting peer registering again, for instance), every tag already
in the world corrects itself the moment that broadcast arrives, with no
polling and no per-frame cost.

---

## Testing

1. **Basic entry:** on the title screen, type a name (e.g. "Nova") into
   the new Display Name field, host a match. Confirm the field's value
   persisted (`user://settings.cfg`, `[game] display_name`) by
   restarting the game and checking the field is pre-filled.
2. **Default fallback:** leave the field blank, host as one instance and
   join as another (both blank). Confirm the host's tag reads "Player 1"
   and the joiner's reads "Player 2" on **both** screens.
3. **Mixed:** host with a custom name, join with the field left blank
   (or vice versa). Confirm each screen shows the correct name for both
   players — the custom one and the "Player 2" fallback.
4. **Billboard/scale/readability:** walk around a remote player's tag
   from multiple angles — it should always face the camera. Back away
   to the far side of the arena — it should shrink but remain legible
   (outline keeps it readable against any background); walk close — it
   should never overlap/clip into the character model's head or body.
5. **Own tag hidden:** confirm you never see your own name tag from
   your own camera, but the other player's tag is always visible on
   your screen (and vice versa on theirs).
6. **Survives round restart / role switch:** play a full round to
   completion, let the automatic round-2 restart happen with roles
   swapped. Confirm both tags still show the correct names throughout —
   during the round-end screen, the countdown, and the new round.
7. **Survives respawn:** each round start repositions both bodies (see
   `SpawnManager`) — confirm the tag stays correctly positioned above
   the head immediately after the teleport, with no lag or misplacement.
8. **Survives reconnect:** drop and reconnect a client mid-match (within
   the grace window). Confirm the reconnected peer's tag still shows
   its name (re-registration re-sends the name as part of the same
   `_register_session` call used for the original join).

## Files touched

- `Scripts/Autoload/GameSettings.gd` — persisted `display_name` +
  `set_display_name()`.
- `Scripts/UI/MainMenu.gd` — Display Name field on the title screen.
- `Scripts/Autoload/NetworkManager.gd` — `peer_display_names` registry,
  `_apply_display_name()`, `_default_display_name()`,
  `get_display_name()`, `_sync_player_names` RPC, extended
  `_register_session` RPC signature.
- `Scripts/Player/PlayerController.gd` — `NameTag` (`Label3D`)
  construction, `_refresh_name_tag()`, own-tag visibility in
  `apply_authority_state()`.

## Deliberate scope boundary: echoes don't get name tags

`EchoGhost` (the 10-second-delayed replay of the Hider's movement, see
`ECHO_SYSTEM.md`) intentionally has no name tag. Labeling the echo would
directly undercut the game's own core mechanic — the Hunter is supposed
to have to judge by sound and movement whether a ghost is the real
Hider's trail, not read a name tag that would remove all ambiguity.
