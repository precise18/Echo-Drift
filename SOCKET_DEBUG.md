# Socket Debug: WebSocket Lifecycle Audit

Audit of every WebSocket connection in the codebase, with temporary
debug logging added so the lifecycle is directly observable in the
Godot output/console during real play-testing. This complements
`NETWORK_FLOW.md` (which traces the whole Host→Game-start flow); this
document is scoped specifically to the WebSocket transport itself.

**Scope finding:** there is exactly **one** WebSocket in this codebase
— the signaling connection to the Render relay, owned entirely by
`Scripts/Autoload/WebRTCSignaler.gd` (`var ws: WebSocketPeer`). It is
not used for gameplay traffic; gameplay runs over the separate WebRTC
DataChannel / `WebRTCMultiplayerPeer` that this socket helps establish
(see `NETWORK_FLOW.md` steps 7-8). Nothing else in the project opens a
socket — `grep -rl "WebSocket" --include="*.gd"` returns only this one
file.

All logging added for this audit is tagged `[WS-DEBUG]` and marked
`# TEMP DEBUG` at each call site, so it can be found and stripped with
a single search:

```
grep -rn "WS-DEBUG\|TEMP DEBUG" Scripts/Autoload/WebRTCSignaler.gd
```

Verified: with the logging in place, `godot4 --headless --quit`
loads the project with no compile errors.

---

## The socket's full lifecycle

### 1. Connection created

- **File / function:** `WebRTCSignaler.gd`, one of `start_host()`
  (line 98), `start_client(room_code)` (line 115), or
  `start_quick_play()` (line 130).
- Each calls `stop()` first (tears down any prior socket/WebRTC state),
  then `ws = WebSocketPeer.new()` — the object is created but not yet
  connected.
- A `_pending_action` JSON string is queued at this point
  (`create_room` / `join_room` / `quick_play`) — it is **not** sent
  yet, only sent once the socket reaches `STATE_OPEN` (see step 5).

### 2. Connection opened

- `ws.connect_to_url(server_url)` is called
  (`server_url = "wss://echo-relay.onrender.com"`), and if it returns
  `OK`, `set_process(true)` starts the polling loop in `_process()`.
- **Debug log added:** `CONNECTING` — logged immediately after a
  successful `connect_to_url()` call, with the URL and which action
  triggered it. If `connect_to_url()` itself returns an error (bad URL,
  no network stack, etc.), `CONNECT_ERROR` is logged instead —
  distinguished from `TIMEOUT` (step 4) because this is a synchronous,
  immediate failure, not a hang.
- The actual open event is detected in `_process()` by watching for the
  ready-state transition into `WebSocketPeer.STATE_OPEN` — **debug log
  added:** `CONNECTED`.

### 3. Connection authenticated

**Finding: there is no authentication in this protocol.** No token,
API key, or credential is ever sent — `create_room` / `join_room` /
`quick_play` are accepted from any client with no identity check. This
was confirmed by testing the live relay directly (raw WebSocket
connections, no game client) during the prior `NETWORK_FLOW.md`
review — the server accepted `create_room` and returned a working room
code with no auth step of any kind.

Since the audit still needs *some* signal for "the server has accepted
this connection and is treating it as a real participant," the closest
equivalent is repurposed: **debug log added:** `AUTHENTICATED`, fired
in `_handle_message()` the moment `room_created` arrives — the first
message the server sends back in response to anything this client
does. The log message says explicitly that this is not a real auth
handshake, to avoid this being mistaken for one later.

**If real authentication is ever added** (e.g. a session token exchanged
before `create_room` is accepted), this is the exact spot to move the
`AUTHENTICATED` log to.

### 4. Connection remains alive

- A `Timer` (`wait_time = 30.0`, autostart) created in `_ready()` sends
  `{"type": "ping"}` over the socket every 30 seconds, but only if
  `ws.get_ready_state() == STATE_OPEN`.
- **Debug log added:** `PING`, logged every time this fires and
  actually sends.
- **Debug log added:** `PONG` — an `elif msg.type == "pong":` branch
  was added to `_handle_message()` purely for observability. **No
  "pong" message was observed from the live server during this
  audit's testing window.** Whether the server implements a pong reply
  at all is unconfirmed; this branch exists so that if it ever does
  reply, it becomes immediately visible in the log instead of silently
  falling through (previously, an unrecognized message `type` was
  silently dropped with no branch matching it at all).
- **Debug log added:** `TIMEOUT` — a watchdog was added
  (`_ws_connect_started_at`, `_WS_CONNECT_TIMEOUT_MSEC = 10000`). If
  the socket is still in `STATE_CONNECTING` more than 10 seconds after
  `connect_to_url()` was called, this logs once. This is a **read-only
  observability addition** — it does not close the socket, retry, or
  change any behavior; see "Reconnect logic" below for why.

### 5. Messages sent

Every `ws.put_packet(...)` call site now logs `MESSAGE_SENT` with the
outgoing payload (SDP bodies are elided — logged as just the SDP kind,
`offer`/`answer` — to avoid dumping a multi-hundred-byte blob per ICE
negotiation):

| Call site | Payload |
|---|---|
| `_process()`, flushing `_pending_action` | `create_room` / `join_room` / `quick_play` |
| `_ready()` timer callback | `{"type":"ping"}` |
| `_on_sdo_created()` | `{"type":"webrtc_signal","data":{"type":"sdp",...}}` (SDP body elided in the log) |
| `_on_ice_candidate()` | `{"type":"webrtc_signal","data":{"type":"ice",...}}` |
| `stop()` | `{"type":"leave_room"}`, only if the socket was open |

### 6. Messages received

- **Debug log added:** `MESSAGE_RECEIVED` — logged for every raw
  packet pulled off the wire in `_process()`'s
  `while ws.get_available_packet_count() > 0` loop, **before** it's
  parsed or dispatched. This catches literally everything the server
  sends, including anything `_handle_message()` doesn't recognize —
  useful precisely because of the "no `pong` seen" finding above: if
  the server does send something unexpected, it now shows up here even
  if no specific handler exists for it yet.
- In addition to the raw log, `_handle_message()` now has **semantic**
  per-type logs so the lifecycle read is meaningful, not just a wall of
  JSON: `AUTHENTICATED` (`room_created`), `PEER_CONNECTED`
  (`peer_connected`), `ERROR` (`error`), `REMOTE_PEER_LEFT`
  (`peer_disconnected` — see note below), `PONG` (`pong`, if it ever
  arrives).

### 7. Heartbeat / ping

Covered in full under "Connection remains alive" above. Summary: this
is an **application-level** ping (a JSON message), not a WebSocket
protocol-level ping/pong control frame — `WebSocketPeer` in Godot
handles protocol-level pings internally and does not expose them to
this script. The 30-second timer is purely to keep the free-tier
Render instance from idling/sleeping and to detect a dead connection —
it is *not* currently used to detect a dead connection, because
nothing checks for a missing pong (see Known Gaps).

### 8. Reconnect logic — `Status: FIXED`

**Original finding: there was none, at the WebSocket layer.** Now
fixed: a bounded, backed-off auto-retry (`_WS_MAX_RETRIES = 3`,
delays `1s/2s/4s`) kicks in when the socket reaches `STATE_CLOSED`
*while still purely in room-setup* (`webrtc_conn == null` — i.e.
before `_setup_webrtc()` has run for this attempt). It re-sends
whichever action (`create_room` / `join_room {room}` / `quick_play`)
was in flight on a fresh `WebSocketPeer`. Each scheduled retry logs
`RECONNECTING attempt N/3 in Xs`. If a fresh `start_host()` /
`start_client()` / `start_quick_play()` / `stop()` happens in the
meantime (user cancelled, or started a different attempt), a
generation counter (`_ws_generation`) invalidates the pending retry so
it's a safe no-op instead of stomping on the new attempt.

- **Deliberately still not retried:** a drop *after* `_setup_webrtc()`
  has run (i.e. mid WebRTC/ICE signaling). Re-sending
  `create_room`/`join_room` against a fresh socket at that point isn't
  well-defined against a relay server we don't control the source of
  (risk of "already in a room" errors or an orphaned duplicate room) —
  this case still falls straight through to `disconnected.emit()`,
  unchanged from before.
- After all 3 retries are exhausted, `room_error.emit("Lost connection
  to the matchmaking server. Please try again.")` fires — `MainMenu`
  already renders `room_error` with zero new UI wiring needed.
- Do not confuse this with `NetworkManager.gd`'s `RECONNECT_GRACE_PERIOD`
  (20s) — that is a **different layer entirely**: it's the
  application/game-session reconnect (same running client rejoining
  mid-round after a drop, tracked via `local_session_id`), documented
  in `NETWORKING_REPORT.md`. It's untouched and has no relationship to
  this fix.

### 9. Socket closed

Three distinct paths, all now logged:

- **Local, deliberate:** `stop()` is called (leaving a room, starting
  a new connection, app-level cleanup). Logs `MESSAGE_SENT` for the
  `leave_room` packet (if the socket was open) immediately followed by
  `DISCONNECTED` — logged here explicitly rather than relying on the
  state-transition watcher, since `ws.close()` on an already-open
  socket may not resolve to `STATE_CLOSED` on the very next `poll()`.
- **Remote/network, detected via state:** the state-transition watcher
  in `_process()` catches the socket organically reaching
  `STATE_CLOSING` (logs `CLOSING`) and then `STATE_CLOSED` (logs
  `DISCONNECTED`, including `ws.get_close_code()` /
  `ws.get_close_reason()` — genuinely new information this audit
  surfaces that wasn't visible before).
- **Remote peer left, socket itself unaffected:** a `peer_disconnected`
  *message* over the still-open socket (the other player left the
  room/match) is a different event from the socket closing. Logged as
  `REMOTE_PEER_LEFT`, deliberately **not** reusing the `DISCONNECTED`
  label, to avoid conflating "the other player left" with "our own
  transport died" — these were easy to confuse at a glance in the
  original code, since both ultimately emit the same
  `WebRTCSignaler.disconnected` signal.

---

## Known gaps this audit surfaced, and what's since changed

1. **No real authentication** on this socket or its message protocol —
   `AUTHENTICATED` above is still a repurposed label, not a genuine
   credential check. **Not fixed** — would require changing the relay
   server's own protocol, and its source isn't in this repo. Anyone who
   can reach the relay can still create/join rooms.
2. **No dead-connection detection via the heartbeat.** The 30s ping is
   sent but nothing checks for a missing reply, and no `pong` has ever
   been observed. **Not fixed** — superseded in practice by the
   handshake-level timeout below, which catches the failure mode that
   actually mattered (a stalled connection never completing) without
   needing the heartbeat itself to detect it.
3. **No reconnect logic at the WebSocket layer.** **`Status: FIXED`** —
   see "Reconnect logic" (step 8) above: bounded, backed-off retry now
   covers a dropped signaling socket during room setup.
4. **The `TIMEOUT` watchdog (WS connect) was passive**, and
   `NETWORK_FLOW.md` separately found the downstream WebRTC ICE/TURN
   gap had no automatic recovery either. **`Status: FIXED`** — TURN is
   restored (see `NETWORK_FLOW.md` step 8) and a new *handshake* timeout
   (`WebRTCSignaler.HANDSHAKE_TIMEOUT_SEC`, 15s, distinct from this
   file's WS-connect `TIMEOUT`) now tears down a stalled WebRTC attempt
   and surfaces a real error to the player instead of hanging silently.

Item 1 remains a genuine, out-of-scope limitation (needs a server
change this repo doesn't own); items 3 and 4 are fixed in
`Scripts/Autoload/WebRTCSignaler.gd` / `NetworkManager.gd`.
