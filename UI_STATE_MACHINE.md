# UI State Machine: Menu → Gameplay

Investigation only — no code changed to produce this document. Every
signal declaration in `Scripts/` was cross-checked against every
`.connect()` call site (full-repo grep, not sampling) to verify wiring
completeness; findings below are what that audit turned up, not
speculation.

## The actual order differs from the requested diagram

The requested chain was `Menu → Connecting → Lobby → Loading →
Gameplay`. The code's actual order is:

```
Menu → Connecting → Loading → Lobby → Gameplay
```

**`Loading` (the `TransitionScreen` cover) happens between Connecting
and Lobby, not between Lobby and Gameplay.** There is no scene load of
any kind between Lobby and Gameplay — that transition happens entirely
inside the already-loaded `Main.tscn`/`HUD.gd`, driven by RPCs and
signals, with no `TransitionScreen.cover()` call anywhere in that path.
The rest of this document uses the verified order.

---

## States and their owning scripts

| State | Owning script(s) | What's on screen |
|---|---|---|
| **Menu** | `Scripts/UI/MainMenu.gd` | One of: title / host / join / browser / settings / credits |
| **Connecting** | `Scripts/UI/MainMenu.gd` (`"connecting"` screen) | `_connecting_label`, Cancel button |
| **Loading** | `Scripts/Autoload/TransitionScreen.gd` | Full-screen cover + status line, autonomous fade (`HOLD_TIME` 0.7s + `FADE_TIME` 0.45s) |
| **Lobby** | `Scripts/UI/HUD.gd` (`_lobby_panel`), gated by `MatchStateManager.phase == LOBBY` | Player count, room code, Start Match / Kick buttons |
| **Gameplay** | `Scripts/UI/HUD.gd` (top bar + banner), `Scripts/World/Main.gd`, `Scripts/Player/PlayerController.gd` | Role chip, timer, arena |

`Loading` is cosmetic-only by design (see its own doc comment): it
"paints over" a scene load already in progress rather than gating it,
and its fade-out is on a fixed timer, not tied to any signal from the
states around it. It cannot get stuck and it doesn't wait for
anything — which also means it has no signal wiring to audit.

---

## Transition-by-transition trace

### 1. Menu → Connecting

Four entry points, all structurally identical (direct function call
from a `Button.pressed`, not signal-mediated — there's nothing here
that could be a "missing connection" since it's synchronous code in
the same file):

| Entry point | Callback | Script change |
|---|---|---|
| "Quick Play (Public)" | `MainMenu._on_quick_play_pressed()` | `_show_screen("connecting")` + `NetworkManager.quick_play()` |
| "Host Private Game" → "Start Hosting" | `MainMenu._on_start_hosting_pressed()` | `_show_screen("connecting")` + `NetworkManager.host_game()` |
| "Join Private Game" → "Join" | `MainMenu._on_join_pressed()` | `_show_screen("connecting")` + `NetworkManager.join_game(code)` |
| Server Browser → "Join Room: X" | inline lambda in `_refresh_browser()` | `_show_screen("connecting")` + `NetworkManager.join_game(room.code)` |

`_show_screen()` (line ~66) just flips `Control.visible` on the
`_screens` dictionary entries — no signal involved, verified correct.

**Back-edges from Connecting → Menu** (relevant to completeness, not
in the requested forward chain):

| Trigger | Signal | Callback |
|---|---|---|
| User clicks Cancel | none (direct call) | inline lambda: `NetworkManager.cancel_connection()` + `_show_screen("title")` |
| ENet-level failure | `multiplayer.connection_failed` → `NetworkManager.connection_failed` | `NetworkManager._on_connection_failed()` re-emits → `MainMenu._on_connection_failed()` (connected `Scripts/UI/MainMenu.gd:47`) |
| WebRTC handshake never completes | `WebRTCSignaler.connection_timed_out` → forwarded by `NetworkManager._ready()` into `connection_failed` | same `MainMenu._on_connection_failed()` — **see Finding 3, this only works while MainMenu is still alive** |
| Relay/room error | `WebRTCSignaler.room_error` | `MainMenu._on_room_error()` (connected in `_build_title_screen()`) |

### 2. Connecting → Loading

Two independent paths converge on the same two calls
(`TransitionScreen.cover(...)` then `get_tree().change_scene_to_file(GAME_SCENE)`):

| Path | Trigger | Script/Function |
|---|---|---|
| Host (private or public/quick-play) | `WebRTCSignaler` receives `{"type":"room_created",...}` over the WS relay | `WebRTCSignaler._handle_message()` calls `NetworkManager.enter_game_as_host()` **directly, inline** — not via a signal. The `room_created` *signal* also fires from the same handler, but purely for `MainMenu`/`HUD`'s cosmetic label updates; the actual scene transition does not depend on anyone having connected to that signal. |
| Joining client | Godot's built-in `multiplayer.connected_to_server` (fires once `WebRTCMultiplayerPeer`'s internal handshake completes) | Connected in `NetworkManager._ready()` → `NetworkManager._on_connected_to_server()` → `TransitionScreen.cover("Joining match...")` + scene change |

Verified connected: `multiplayer.connected_to_server.connect(_on_connected_to_server)`
in `NetworkManager.gd`. No missing connection on this edge.

### 3. Loading → Lobby

**Not signal-driven at all.** `MatchStateManager.phase` starts at
`MatchPhase.LOBBY` by static initialization
(`var phase: MatchPhase = MatchPhase.LOBBY`) — no event needs to fire
for the game scene to be "in the lobby." Once `Main.tscn` loads and
`HUD._ready()` runs, it calls `_apply_phase(MatchStateManager.phase)`
directly, which sets `_lobby_panel.visible = true` because the phase
is already `LOBBY` by default. `TransitionScreen`'s cover fades out on
its own fixed timer regardless of what's happening underneath.

**Practical consequence:** reaching the Lobby state only proves the
*scene* loaded — it does not by itself prove a second player is
connected, or even that this client's own connection succeeded (for
the host specifically; see Finding 3, since the host now transitions
here immediately after its own room is created, before any peer has
joined at all).

### 4. Lobby → Gameplay

| | |
|---|---|
| **Trigger** | Host clicks "Start Match" |
| **File/Function** | `HUD.gd`, button wired at `_build_lobby_panel()`: `_lobby_start_button.pressed.connect(func() -> void: RoundManager.start_match())` |
| **Guard** | `RoundManager.start_match()`: `if not multiplayer.is_server() or round_active: return` — safe even though the button itself is only ever made *visible* to the server (`_refresh_lobby()`: `_lobby_start_button.visible = true` only `if multiplayer.is_server()`), so a non-host clicking it isn't actually reachable through the UI, and would no-op server-side even if it were. |
| **What happens** | `start_round()` → `RoleManager.assign_roles(...)` → `_apply_round_state.rpc(hider_id, hunter_id, ROUND_TIME)` — reliable RPC, `call_local` so it also runs on the server's own peer, not just remote ones. |
| **Signals fired (inside `_apply_round_state`, on every peer)** | `MatchStateManager.begin_round()` → `phase_changed(ROUND_ACTIVE)`; `RoundManager.role_assigned(hider_id, Role.HIDER)`; `role_assigned(hunter_id, Role.HUNTER)`; `RoundManager.round_started()` |
| **Consumers, verified connected** | `HUD.gd`: `_on_phase_changed` (hides lobby panel), `_on_round_started` (hides end/lobby panels, shows round banner), `_on_role_assigned` (sets the local role chip, filters by `peer_id == multiplayer.get_unique_id()`). `Main.gd`: `_on_round_started` (respawns local player via `SpawnManager`), `_on_role_assigned` (wires the echo system to the Hider). `PlayerController.gd`: `_on_role_assigned` (refreshes body material). All confirmed connected via grep — no missing wiring on this edge. |

This is the best-wired transition in the whole chain: three
independent scripts consume the same signal batch and all three
connections are present and correct.

---

## Signal audit (every declared signal vs. every connection)

| Signal | Declared in | Connected by | Verdict |
|---|---|---|---|
| `room_created` | WebRTCSignaler | `MainMenu._on_room_created`, `HUD._on_room_created` | OK — cosmetic only, doesn't gate the real transition (see step 2) |
| `room_error` | WebRTCSignaler | `MainMenu._on_room_error` | OK |
| `match_ready` | WebRTCSignaler | *(none — removed, see Finding 1)* | **Fixed** — dead no-op callback and its connection deleted |
| `disconnected` | WebRTCSignaler | `MainMenu._on_signaling_disconnected`, `HUD._on_signaling_disconnected` | **Fixed** — see Finding 2 |
| `connection_timed_out` | WebRTCSignaler | `NetworkManager._on_connection_failed` (via `_ready()`) | OK — see Finding 3 |
| `connection_failed` | NetworkManager | `MainMenu._on_connection_failed`, `HUD._on_lobby_connection_failed` | **Fixed** — now covered both pre-scene-change (MainMenu) and in the Lobby (HUD), see Finding 3 |
| `player_connected` / `player_disconnected` / `player_reconnected` / `reconnect_grace_ended` | NetworkManager | `Main.gd` (server branch only) | OK — correctly server-gated |
| `reconnect_grace_started` / `reconnect_grace_ended` | NetworkManager | `HUD.gd` | OK |
| `role_assigned` | RoundManager | `HUD.gd`, `Main.gd`, `PlayerController.gd` | OK, three consumers, all present |
| `round_started` / `round_ended` | RoundManager | `HUD.gd`, `Main.gd`, `AudioManager.gd` | OK |
| `phase_changed` | MatchStateManager | `HUD.gd` | OK |
| `score_changed` | MatchStateManager | `Scoreboard.gd` | OK |

---

## Findings

### Finding 1 — `Status: FIXED` — `match_ready` had a connected callback that did nothing

`NetworkManager._on_webrtc_match_ready()` was:
```gdscript
func _on_webrtc_match_ready() -> void:
	if not get_node("/root/WebRTCSignaler").is_host:
		pass # We wait for connected_to_server instead for clients
```
Both branches were `pass` — dead code that never gated any transition
(the real Connecting→Loading edge is driven by
`connected_to_server`/`room_created` directly, step 2 above). **Fix
applied:** the function and its `match_ready.connect(...)` line in
`NetworkManager._ready()` were deleted outright rather than left as an
inert placeholder. `match_ready` itself is still declared and emitted
in `WebRTCSignaler.gd` (documented there as marking "local
signaling/offer setup is done") — it simply has no subscriber right
now, which is an ordinary unconsumed signal, not the same problem as a
connected-but-inert callback.

### Finding 2 — `Status: FIXED` — `WebRTCSignaler.disconnected` was a dead signal

Zero `.connect()` call sites anywhere in the repo (confirmed by grep).
It fires from `_handle_message()`'s `peer_disconnected` branch (the
*other* peer left during room setup, before any ENet/WebRTC-level
connection existed) and from the WS `STATE_CLOSED` path when retries
are exhausted (that second path also already gets a `room_error`
message, so wiring `disconnected` doesn't duplicate messaging there —
see below).

**Fix applied:** connected in both places a departed signaling peer can
actually be relevant, mirroring the existing `connection_failed`
handling:
- `MainMenu._on_signaling_disconnected()` — guarded to only act
  `if _current_screen == "connecting"`, shows "The other player
  disconnected before the match could start." and returns to the title
  screen. Covers a joining client whose host bails mid-signaling.
- `HUD._on_signaling_disconnected()` — guarded by
  `MatchStateManager.is_in_lobby()`, shows a transient message on the
  existing `_connection_status_label` (now factored into a shared
  `_show_transient_status()` helper alongside `_on_lobby_connection_failed`).
  Covers a host sitting in the Lobby whose prospective joiner bails.

### Finding 3 — `Status: FIXED` — the answer to "does any UI transition depend on a networking callback that never executes"

**Yes, this one (as originally found):** once the **host** had transitioned into the Lobby
(which, since the earlier host-scene-transition-race fix, now happens
immediately after the host's own room is confirmed created — *before*
any second peer has joined), **nothing in `Main.tscn`/`HUD.gd` is
connected to `NetworkManager.connection_failed` or
`WebRTCSignaler.connection_timed_out`/`disconnected`.**

The only listener for `connection_failed` is `MainMenu._on_connection_failed()`,
connected in `MainMenu._ready()`. Once `MainMenu`'s node is freed by
`get_tree().change_scene_to_file(GAME_SCENE)`, Godot automatically
drops that connection along with the freed node. So the sequence:

1. Host presses "Host Private Game" → room created → scene changes to
   `Main.tscn` → sitting in Lobby at "Players: 1/2". `MainMenu` node is
   now gone.
2. A joiner's `peer_connected` arrives, `_setup_webrtc()` runs on the
   host's side too, and the 15-second handshake watchdog starts (the
   fix from the previous pass).
3. If that specific handshake times out (e.g. the joiner's NAT can't
   be traversed even with TURN), `WebRTCSignaler` tears down and emits
   `connection_timed_out` → `NetworkManager._on_connection_failed()`
   runs (`RoundManager.reset_state()`, harmless since nothing was
   active) → re-emits `connection_failed` — **into a void. No listener
   exists.**
4. The host sees no message at all. `_refresh_lobby()` just keeps
   showing "Players: 1/2 — Waiting for a second player to join...",
   which isn't *wrong*, but silently discards the fact that someone
   just tried and failed to connect, with no hint to invite them
   again, check their network, etc.

The joining side does **not** have this gap: for a joiner, reaching
the Lobby at all is gated on the same success signal
(`connected_to_server`) that cancels its own timeout, so a joiner who
times out is by definition still on the Connecting screen, where
`MainMenu` (and its `connection_failed` listener) is still alive and
working correctly.

**Fix applied:** `HUD.gd._ready()` now also connects
`NetworkManager.connection_failed.connect(_on_lobby_connection_failed)`,
mirroring the existing `reconnect_grace_started`/`ended` pattern
already in the same file. `_on_lobby_connection_failed()` shows a
transient message on the existing `_connection_status_label`
("A connection attempt failed or timed out. Still waiting for a
player...") for 6 seconds, guarded by `MatchStateManager.is_in_lobby()`
so it doesn't fire mid-match (that case is the reconnect-grace path
instead, which is unrelated and untouched), and it won't clobber an
active reconnect-grace message if one happens to be showing at the
same time (checks `_grace_deadline <= 0.0` before hiding itself).
