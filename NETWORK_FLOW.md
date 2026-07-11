# Network Flow: Host → Lobby → Game Start

Trace of the full multiplayer lifecycle as the code and the live relay
server actually behave today, from pressing **Host** in the Godot
client through to a match starting. Originally investigation-only;
the fixes identified below have since been applied to
`Scripts/Autoload/WebRTCSignaler.gd` and `Scripts/Autoload/NetworkManager.gd`
— this document is left largely as originally written (including the
"where it stops" analysis, since that reasoning is what motivated the
fix), with **`Status: FIXED`** notes added at each affected step.
Verified against the live server at `wss://echo-relay.onrender.com`
(see "Live verification" below).

**Bottom line up front (as originally found, now fixed):** the flow
did not fully break in the client code. It broke at the **WebRTC
ICE/NAT-traversal step**, because the project's only TURN relay
configuration was deliberately removed (commit `37853ca`) and never
replaced, and no timeout/error path existed to surface that failure to
the player. See [Where the flow stops](#where-the-flow-stops) — now
resolved: TURN is restored (re-verified empirically this time, not
just reverted-on-suspicion) and a 15s handshake timeout surfaces a
clear, actionable error instead of an infinite hang.

---

## Architecture at a glance

```
Godot Client A (Host)                Render (echo-relay.onrender.com)              Godot Client B (Joiner)
──────────────────────               ──────────────────────────────                ──────────────────────
MainMenu.gd (UI)                     WebSocket signaling relay                     MainMenu.gd (UI)
NetworkManager.gd (session/scene)    (source not in this repo — external           NetworkManager.gd
WebRTCSignaler.gd (signaling +       service, reachable and responding)            WebRTCSignaler.gd
  WebRTC peer connection)            Rooms: create / join / quick_play             
                                     Relays: SDP offer/answer, ICE candidates      
        │                                        │                                        │
        │──── WSS: create_room ─────────────────▶│                                        │
        │◀─── room_created {room, is_public} ────│                                        │
        │                                        │◀──── WSS: join_room {room} ────────────│
        │◀─── peer_connected {is_host:true} ──────│──── peer_connected {is_host:false} ───▶│
        │──── webrtc_signal {sdp offer} ─────────▶│──── webrtc_signal {sdp offer} ─────────▶│
        │◀─── webrtc_signal {sdp answer} ─────────│◀──── webrtc_signal {sdp answer} ────────│
        │◀──▶ webrtc_signal {ice candidates} ◀────│────▶ webrtc_signal {ice candidates} ◀───│
        │                                        │                                        │
        └──────────── Direct WebRTC DataChannel (ENet-style multiplayer_peer) ─────────────┘
                        STUN-only NAT traversal — no TURN fallback configured
```

Two things worth flagging before the step-by-step trace:

1. **`NETWORKING_REPORT.md` (already in the repo) describes an older
   architecture** — direct ENet on UDP port 7777, no relay server, no
   WebRTC. That document is accurate for the design *reasoning* around
   reconnects/roles/RPCs (still true today), but its architecture
   diagram is stale: the actual transport is now WebRTC via a signaling
   relay, introduced in commit `1f71d3a` ("Integrate WebRTC Room
   Codes... "), after `NETWORKING_REPORT.md` was written.
2. **There is no server source code in this repository.** `git log`
   shows a commit titled "...add Node relay server..." (`1f71d3a`), but
   no server files were actually committed alongside it — only the
   client-side `WebRTCSignaler.gd` referencing
   `wss://echo-relay.onrender.com`. The relay server is a live,
   externally-deployed service this repo has no source visibility
   into. Everything below about "the server" is inferred from its
   observed wire behavior, not from reading its code.

---

## Step-by-step lifecycle

### 1. Player presses "Host"

| | |
|---|---|
| **File** | `Scripts/UI/MainMenu.gd` |
| **Function** | `_on_start_hosting_pressed()` (line 313) |
| **Trigger** | `Button.pressed` signal from the "Start Hosting" button built in `_build_host_screen()` |
| **What happens** | `MapManager.set_selected_map(_selected_map_id)`, then `_show_screen("connecting")`, sets label to `"Generating code..."`, calls `NetworkManager.host_game()` |
| **UI state** | Host screen → **Connecting screen** (`_connecting_label = "Generating code..."`) |

### 2. Client networking code

**`Status: FIXED`** — `host_game()` no longer transitions scenes
eagerly. It now only calls `WebRTCSignaler.start_host()`; the scene
transition happens from the `room_created` handler (step 5) once the
server actually confirms the room exists, unifying the private-host
path with the already-correct public/quick-play-host path.

| | |
|---|---|
| **File** | `Scripts/Autoload/NetworkManager.gd` |
| **Function** | `host_game()` |
| **What happens (as originally found, now fixed)** | Called `WebRTCSignaler.start_host()`, then **immediately and synchronously** called `enter_game_as_host()` — did **not** wait for any server response. |
| **Signal fired** | None yet from the network layer |
| **UI state (original bug)** | `enter_game_as_host()` calls `TransitionScreen.cover(...)` and `get_tree().change_scene_to_file(GAME_SCENE)` — the scene tree switched to `Main.tscn` **before the WebSocket had even connected**. |

`Scripts/Autoload/WebRTCSignaler.gd::start_host()` runs in parallel:
- Creates `WebRTCMultiplayerPeer`, calls `webrtc_mp.create_server()`
  (host is always peer 1) — still eager, tracked now by a
  `_server_created` guard so the later `room_created` handler doesn't
  call it a second time.
- Queues `_pending_action = {"type": "create_room"}` (also cached into
  `_last_action_json` for the new WS retry logic — step 3).
- Opens `ws.connect_to_url(server_url)` and sets `set_process(true)` so
  `_process()` starts polling the socket.

**Original note (now resolved):** because `enter_game_as_host()` ran
before the room was even created server-side, the "Generating
code..." label in `MainMenu.gd` was effectively dead for the
private-host path. It now updates meaningfully, since the scene
transition and the `room_created` signal both fire from the same
handler in step 5.

### 3. HTTP/WebSocket request

| | |
|---|---|
| **File** | `Scripts/Autoload/WebRTCSignaler.gd` |
| **Function** | `_process()` (line 36), sends the queued action once `ws.get_ready_state() == STATE_OPEN` |
| **Packet sent** | `{"type": "create_room"}` over `wss://echo-relay.onrender.com` |
| **Also present** | An `HTTPRequest` fired in `_ready()` (line 22) hits the plain-HTTPS equivalent of `server_url` on launch, purely to wake a free-tier Render instance from cold sleep — unrelated to the room flow. `MainMenu.gd` separately polls `GET /api/stats` and `GET /api/rooms` for the title-screen server-stats label and the server browser. |

### 4. Render server

Not in this repo — external service. **Live-verified during this
review** (see [Live verification](#live-verification) below): the
service is up, the WebSocket upgrade succeeds, and `create_room` /
`join_room` / `peer_connected` all behave as the client code expects.

### 5. Lobby creation

**`Status: FIXED`** — both hosting paths (private and public/quick-play)
now transition scenes from exactly this handler, gated on the real
server ack.

| | |
|---|---|
| **Packet received (host)** | `{"type": "room_created", "room": "<CODE>", "is_public": false}` |
| **File/Function** | `WebRTCSignaler._handle_message()` |
| **What happens** | Sets `current_room_code = msg.room`. If `is_public` (quick-play winning the host coin-flip), sets `is_host = true`. Then, whenever `is_host` is true (private **or** public host): calls `webrtc_mp.create_server()` only `if not _server_created` (private hosting already did this eagerly in `start_host()`), assigns `multiplayer.multiplayer_peer`, and calls `NetworkManager.enter_game_as_host()` — this is now the single point *either* hosting path actually transitions scenes, no longer racing the WS round-trip. |
| **Signal fired** | `room_created(code)` — consumed by both `MainMenu.gd::_on_room_created()` (updates the connecting-screen label, no longer dead code for private hosts) and `HUD.gd::_on_room_created()` (updates the in-lobby room code label). |

### 6. Server acknowledgement (peer joins)

When a second client calls `join_game(room_code)` →
`WebRTCSignaler.start_client()` → sends `{"type":"join_room","room":code}`,
the server acknowledges both sides:

| | |
|---|---|
| **Packet received (both peers)** | `{"type": "peer_connected", "is_host": <bool>}` |
| **File/Function** | `WebRTCSignaler._handle_message()` → `_setup_webrtc()` (line 129) |
| **What happens** | Builds a `WebRTCPeerConnection`, initializes ICE with **STUN + TURN** (fixed — see step 8), wires `session_description_created` / `ice_candidate_created`, then: host side calls `webrtc_mp.add_peer(conn, 2)` + `create_offer()`; client side calls `webrtc_mp.create_client(2)` + `add_peer(conn, 1)`. Emits `match_ready`, then arms a `HANDSHAKE_TIMEOUT_SEC` (15s) watchdog (fixed — see step 8). |
| **Signal fired** | `match_ready()` — `NetworkManager._on_webrtc_match_ready()` (line 62) is connected to it but is currently a **no-op on both branches** (`if not is_host: pass` — the non-host branch is also just a comment, dead code). |

### 7. Client receives acknowledgement → WebRTC signaling relay

SDP and ICE exchange, fully relayed through the same WebSocket (not a
separate connection):

| Direction | Packet | Handler |
|---|---|---|
| Local → relay → remote | `{"type":"webrtc_signal","data":{"type":"sdp","sdp":...,"sdp_type":"offer"/"answer"}}` | `_on_sdo_created()` (line 154) sends; `_handle_signal()` (line 163) receives and calls `set_remote_description()` |
| Local → relay → remote | `{"type":"webrtc_signal","data":{"type":"ice","media":...,"index":...,"name":...}}` | `_on_ice_candidate()` (line 159) sends; `_handle_signal()` calls `add_ice_candidate()` |

Once `set_remote_description("offer", ...)` runs on the answering
peer, Godot's native WebRTC module auto-generates the answer (fixed by
commit `f1b4a36`, "Remove invalid create_answer() call; Godot
automatically generates answers" — no explicit `create_answer()` call
needed or present).

**This is the step verified live to actually work at the signaling
layer** (room + peer_connected exchange confirmed). The subsequent ICE
candidate exchange's ability to produce a usable pair for two
real, differently-NATed peers is what step 8 covers.

### 8. Where the flow used to stop — `Status: FIXED`

This was the actual gap, not a hypothetical one, and is now fixed in
`Scripts/Autoload/WebRTCSignaler.gd`:

- **Original bug:** `_setup_webrtc()` initialized ICE with **STUN
  only** (`stun:stun.l.google.com:19302`, no TURN). Git history showed
  a TURN server *was* configured once (`turn:openrelay.metered.ca`,
  commit `7b48cec`) and was then removed two commits later by
  `37853ca`, "Fix WebRTC initialize failure by reverting to simple
  STUN" — the TURN config was blamed for a failure and dropped rather
  than fixed.
- **Root cause, found empirically this pass:** `webrtc_conn.initialize()`
  never actually fails on any iceServers dict shape tested (it returns
  `OK` regardless — confirmed via a headless Godot script driving the
  real `addons/webrtc_native` GDExtension). The real, but non-fatal,
  problem is a *warning* — `strings` on the shipped
  `libwebrtc_native.linux.*.so` confirms this build's ICE agent is
  **libjuice**, which logs `"TURN transports TCP and TLS are not
  supported with libjuice"` for the old config's
  `turn:openrelay.metered.ca:443?transport=tcp` entry. It's a warning,
  not a rejection — `create_offer()` still succeeded in testing even
  with the old config present — but it was evidently misread as a hard
  failure at the time.
- **Fix applied:** `_setup_webrtc()` now initializes with STUN plus two
  clean TURN entries (`openrelay.metered.ca` on ports 80 and 443, UDP
  only, one URL per `iceServers` entry, no `?transport=tcp` suffix) —
  verified via the same empirical harness to produce zero warnings and
  a normal `add_peer()`/`create_offer()`/candidate-gathering cycle.
  (Note: the sandbox this was tested in blocks outbound UDP entirely —
  `errno=101`/`ENETUNREACH` on every candidate send — so an actual
  relayed connection across two real, differently-NATed machines
  should still be confirmed in the field; what's verified here is that
  the config no longer breaks anything locally, which is what the
  original revert was reacting to.)
- **Fix applied (defense in depth):** even with TURN restored, nothing
  previously detected a stalled handshake. `_setup_webrtc()` now arms a
  15-second (`HANDSHAKE_TIMEOUT_SEC`) watchdog right after `match_ready`
  fires, cancelled the instant `multiplayer.peer_connected` /
  `connected_to_server` confirms the transport is actually up. If it
  fires, `WebRTCSignaler` tears down the attempt and emits
  `connection_timed_out`, which `NetworkManager` forwards through the
  existing `connection_failed` → `MainMenu._on_connection_failed()`
  path — so a bad connection now surfaces "Connection failed or timed
  out... try again" and returns to the title screen, instead of an
  infinite hang broken only by the manual Cancel button.

This is the single highest-impact break in the reviewed flow: it's not
a crash or a code path that's missing, it's a NAT-traversal fallback
that was present, actively removed under time pressure, and never
reinstated with a matching working TURN config — combined with a total
absence of connection-timeout/error UX for this specific failure mode.

### 9. Client scene transition / UI transition

Once (if) the WebRTC transport actually connects, Godot's own
multiplayer API handshake completes and fires the standard signals
`NetworkManager` already listens for in `_ready()` (line 52-57):

| Peer | Signal | Handler | What happens |
|---|---|---|---|
| Host | `multiplayer.peer_connected(id)` | `_on_peer_connected()` (line 99) | Adds id to `connected_peer_ids`, calls `MapManager.sync_to_peer(id)` (server-authoritative map sync so the client's copy of `Main.gd` never races the load), emits `player_connected` |
| Joiner | `multiplayer.connected_to_server` | `_on_connected_to_server()` (line 116) | Sets `connected_peer_ids`, sends `_register_session.rpc_id(1, ...)` (reliable RPC, joins session registry for reconnect support), covers with `TransitionScreen`, calls `get_tree().change_scene_to_file(GAME_SCENE)` |

The host was already in `Main.tscn` since step 2; the joiner switches
into it here. Both are now in the same scene.

### 10. Lobby scene (in-game warm-up lobby)

| | |
|---|---|
| **File** | `Scripts/World/Main.gd`, `Scripts/UI/HUD.gd`, `Scripts/Autoload/MatchStateManager.gd` |
| **What happens** | `Main.gd::_ready()` registers the players container with `RoundManager`, and — server-side only — spawns a body per connected peer via `_spawn_player()` (line 100) the instant each one connects (`_on_peer_connected_server`, line 63). `HUD.gd` shows the `_lobby_panel` while `MatchStateManager.is_in_lobby()` is true, live-updating `_lobby_players_label` ("Players: 1 / 2" → "2 / 2") and the room code label (`_on_room_created`, populated from `WebRTCSignaler.current_room_code`). |
| **UI state** | Warm-up lobby panel visible, showing player count, room code, a **Start Match** button (host only, implicitly — see below), and a Kick Player button. |

Note: nothing in `HUD.gd`/`RoundManager.gd` visibly gates the "Start
Match" button to server-only in the UI layer itself — the safety net is
server-side, in `RoundManager.start_match()` (line 116):
`if not multiplayer.is_server() or round_active: return`. A
non-authoritative client pressing it is a harmless no-op, not a UI
bug, but worth knowing if a "disable button for non-host" pass is ever
done — it's not there today.

### 11. Game start

| | |
|---|---|
| **File** | `Scripts/UI/HUD.gd` → `Scripts/Autoload/RoundManager.gd` |
| **Function** | Button press → `RoundManager.start_match()` (line 116) → `start_round()` (line 126) |
| **What happens** | Server assigns roles via `RoleManager.assign_roles(...)`, then broadcasts `_apply_round_state.rpc(hider_id, hunter_id, ROUND_TIME)` — a reliable RPC to all peers. |
| **Signal fired** | `RoundManager.round_started` (consumed by `Main.gd::_on_round_started()`, line 150, which respawns the local player at a role-appropriate spawn point via `SpawnManager`) and `role_assigned` (consumed by `Main.gd::_on_role_assigned()`, line 142, wiring the echo system to the Hider). |
| **UI state** | Lobby panel hides, round timer/role HUD becomes active, players are placed in the arena. |

From here the match proper is already covered in depth by the existing
`NETWORKING_REPORT.md` (round RPCs, disconnect/reconnect handling,
bandwidth/sync behavior) — that document remains accurate for
everything *after* the transport connects; it's only the transport
section itself that predates the WebRTC rewrite.

---

## Live verification

Performed as read-only diagnostics against the live server, no game
client involved — confirms the signaling relay itself is up and
functioning as the client code expects:

```
$ curl https://echo-relay.onrender.com/api/stats   → HTTP 200
$ curl https://echo-relay.onrender.com/api/rooms   → HTTP 200, "[]"

$ node -e 'new WebSocket("wss://echo-relay.onrender.com")...'
  → OPEN
  → sent {"type":"create_room"}
  → received {"type":"room_created","room":"EF31","is_public":false}

$ (two-socket test: host creates room, second socket joins it)
  → host received  {"type":"room_created","room":"6332","is_public":false}
  → client received (after join_room)
  → host   received {"type":"peer_connected","is_host":true}
  → client received {"type":"peer_connected","is_host":false}
```

Everything through step 6 (`peer_connected` on both sides) is
confirmed working end-to-end against the real server. The WebRTC
DataChannel/ICE step (7-8) was not live-tested here (would require two
real Godot clients on genuinely different networks to reproduce the
NAT scenario) — the conclusion in step 8 is based on the STUN-only
config in the current code plus the git history of the TURN config
being added and then reverted for causing an initialization error.

---

## Summary table

| Step | File | Function | Signal | Sent | Received | UI state |
|---|---|---|---|---|---|---|
| Press Host | MainMenu.gd | `_on_start_hosting_pressed` | `Button.pressed` | — | — | Host screen → Connecting |
| Client net code | NetworkManager.gd, WebRTCSignaler.gd | `host_game`, `start_host` | — | — | — | Connecting (scene switch now deferred to `room_created` — **fixed**) |
| WS request | WebRTCSignaler.gd | `_process` | — | `create_room` | — | Connecting screen label (now meaningful for both host paths — **fixed**) |
| Render server | *(external, no source in repo)* | — | — | — | — | — |
| Lobby creation | WebRTCSignaler.gd | `_handle_message` | `room_created` | — | `room_created {room}` | Scene transitions here for both hosting paths + lobby room-code label set — **fixed** |
| Peer joins / ack | WebRTCSignaler.gd | `_handle_message` → `_setup_webrtc` | `match_ready` (no-op consumer) | offer/ICE (now STUN+TURN — **fixed**) | `peer_connected` | still Connecting/Lobby |
| **← previously stopped here without TURN — now fixed** | WebRTCSignaler.gd | `_setup_webrtc` (ICE init) | `connection_timed_out` after 15s if no real connect — **fixed** | ICE candidates (TURN relay now available for symmetric NAT) | — | error shown, returns to title screen instead of hanging |
| Client receives ack | NetworkManager.gd | `_on_peer_connected` / `_on_connected_to_server` | `player_connected` / `connected_to_server` | `_register_session` RPC | — | scene already in Main.tscn |
| UI/scene transition | Main.gd | `_ready`, `_spawn_player` | `spawned` | — | — | Player bodies appear |
| Lobby scene | HUD.gd, MatchStateManager.gd | `_refresh_lobby` | — | — | — | "Players: N / 2", Start Match enabled |
| Game start | HUD.gd → RoundManager.gd | `start_match` → `start_round` | `round_started`, `role_assigned` | `_apply_round_state` RPC | — | Lobby hides, round HUD active |
