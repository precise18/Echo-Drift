# Packet Trace: Networking Layer Instrumentation

Every outgoing and incoming packet in the networking layer is now
logged. This covers two genuinely different transports that make up
"the networking layer" in this project, and is explicit about a third
that isn't covered:

1. **WebSocket signaling** (`Scripts/Autoload/WebRTCSignaler.gd`) — JSON
   messages between this client and the external Render relay.
2. **RPCs** (`NetworkManager.gd`, `RoundManager.gd`, `MapManager.gd`) —
   Godot's high-level multiplayer RPCs, sent peer-to-peer over the
   WebRTC data channel once it's established.
3. **`MultiplayerSynchronizer` replication** (`Player.tscn`'s
   position/rotation sync) — **not instrumented**. This is Godot engine
   internals with no per-packet script hook available; per-packet
   logging here would also be extremely high-frequency noise for what
   is, by design, continuous state rather than discrete events (see
   `NETWORKING_REPORT.md`'s bandwidth-reduction section). Use Godot's
   built-in Network Profiler (Debugger panel, already referenced in
   `NETWORKING_REPORT.md`) to inspect this traffic instead.

All instrumentation added for this pass is tagged `[PACKET-TRACE]` and
routed through one shared helper, `Scripts/Autoload/PacketTrace.gd`
(registered as an autoload in `project.godot`). Grep `PacketTrace` or
`[PACKET-TRACE]` to find or strip every call site.

```
grep -rn "PacketTrace\|\[PACKET-TRACE\]" Scripts/ project.godot
```

Verified: `godot4 --headless --quit` still loads the whole project
with zero compile errors after this instrumentation.

## Log format

```
[PACKET-TRACE][<timestamp_ms>] SENT     type=<type> sender=<who> receiver=<who> payload=<payload> expected_handler=<fn>
[PACKET-TRACE][<timestamp_ms>] RECEIVED type=<type> sender=<who> receiver=<who> payload=<payload> expected_handler=<fn> actual_handler=<fn or reason it wasn't handled>
```

`SENT` never has an `actual_handler` — whether a sent packet was
actually handled is only knowable from the *other* side's own log,
which for a real two-machine connection is a different console
entirely. The `RECEIVED` line is always where "was this actually
acted on, or silently ignored" gets answered, which is the direct
answer to this task's four "identify" questions below.

---

## Packet catalog

### WebSocket signaling (client ↔ Render relay)

| Type | Direction | Sender → Receiver | Sent from | Received/handled by |
|---|---|---|---|---|
| `create_room` | out | CLIENT → RELAY | `WebRTCSignaler.start_host()` (queues `_pending_action`, flushed in `_process()`) | *(external — no source in repo)* |
| `join_room` | out | CLIENT → RELAY | `WebRTCSignaler.start_client()` | *(external)* |
| `quick_play` | out | CLIENT → RELAY | `WebRTCSignaler.start_quick_play()` | *(external)* |
| `ping` | out | CLIENT → RELAY | `WebRTCSignaler`'s 30s heartbeat timer (`_ready()`) | *(external)* |
| `leave_room` | out | CLIENT → RELAY | `WebRTCSignaler.stop()` | *(external)* |
| `webrtc_signal` (sdp) | out | CLIENT → RELAY → remote peer | `WebRTCSignaler._on_sdo_created()` | remote peer's `_handle_signal()` |
| `webrtc_signal` (ice) | out | CLIENT → RELAY → remote peer | `WebRTCSignaler._on_ice_candidate()` | remote peer's `_handle_signal()` |
| `room_created` | in | RELAY → CLIENT | *(external)* | `_handle_message()` → `NetworkManager.enter_game_as_host()` (if host) |
| `error` | in | RELAY → CLIENT | *(external)* | `_handle_message()` → `room_error` signal |
| `peer_connected` | in | RELAY → CLIENT | *(external)* | `_handle_message()` → `_setup_webrtc()` |
| `webrtc_signal` (sdp/ice) | in | remote peer → RELAY → CLIENT | remote peer's `_on_sdo_created`/`_on_ice_candidate` | `_handle_message()` → `_handle_signal()` |
| `peer_disconnected` | in | RELAY → CLIENT | *(external)* | `_handle_message()` → `disconnected` signal |
| `pong` | in | RELAY → CLIENT | *(external, never observed — see Finding 2)* | `_handle_message()` (handler exists, never exercised) |

### RPCs (peer ↔ peer, over the WebRTC data channel once established)

| RPC | Config | Sent from | Target |
|---|---|---|---|
| `_register_session` | `any_peer, call_local, reliable` | `NetworkManager.enter_game_as_host()` (host — **direct call, not a network packet**, see Finding 1) / `_on_connected_to_server()` (client, `rpc_id(1,...)`) | server (peer 1) |
| `_receive_kick` | `authority, call_remote, reliable` | `NetworkManager.kick_peer()` | one specific peer |
| `_receive_map_id` | `authority, call_remote, reliable` | `MapManager.sync_to_peer()` | one specific peer |
| `_apply_round_state` | `authority, call_local, reliable` | `RoundManager.start_round()` | all peers (broadcast) |
| `_end_round` | `authority, call_local, reliable` | `RoundManager._on_timer_expired()` / `_check_for_capture()` | all peers (broadcast) |
| `_request_rematch` | `any_peer, call_local, reliable` | `RoundManager.request_rematch()` | server (peer 1) |
| `_reset_match` | `authority, call_local, reliable` | inside `_request_rematch()`, server-side only | all peers (broadcast) |
| `_resync_after_reconnect` | `authority, call_local, reliable` | `RoundManager.reassign_role()` | all peers (broadcast) |

---

## Findings

### Finding 1 — a "packet" that's never actually sent over the network at all

`NetworkManager.enter_game_as_host()` calls `_register_session(...)` as
a **plain direct GDScript function call**, not `.rpc()`/`.rpc_id()`.
The host registering its own session never touches the wire — there's
no one else to send it to at that point. Only the *joining* client's
path (`_on_connected_to_server()` → `_register_session.rpc_id(1, ...)`)
is a real network packet. Both are logged, but the host's is tagged
`(direct call, not RPC -- no packet actually sent)` so it isn't
mistaken for wire traffic when reading the trace.

### Finding 2 — packets never received: `pong`

Confirmed already in `SOCKET_DEBUG.md`'s live testing: the client sends
`ping` every 30 seconds, and a `pong` handler exists in
`_handle_message()`, but no `pong` has ever actually arrived from the
live relay in any testing session. The handler is real and would log
`RECEIVED ... type=pong ... actual_handler=_handle_message/pong
(handled)` the instant one ever showed up — it just never has.

### Finding 3 — packets received but ignored (by design, confirmed via the new guard-clause logging)

Two RPCs use `call_local`, which means the *sender's own machine* also
runs the handler locally — even when the RPC's actual network target
was someone else entirely (`rpc_id(1, ...)`, i.e. "send to the server
only"). On that local echo, `multiplayer.get_remote_sender_id()`
returns `0` (it wasn't really a received network packet), and the
handler's own authority guard then bails immediately:

- **`NetworkManager._register_session`**: a joining client's own local
  echo hits `if not multiplayer.is_server(): return` every time. Now
  logs `RECEIVED ... sender=LOCAL_CALL ... actual_handler=IGNORED (not
  server) -- expected for call_local's own-machine echo on a non-host
  peer`.
- **`RoundManager._request_rematch`**: same shape — a non-host clicking
  "Rematch" runs this locally too, hits the same guard (or the
  `MatchStateManager.is_match_over()` half of it), and now logs which
  specific reason it was ignored for (`not server` vs `match not
  over`).

Both are intentional, harmless behavior (this is exactly what
`call_local` is supposed to do), but previously had **zero visibility**
— there was no way to tell, from the logs alone, that these functions
were even being invoked locally and silently bailing rather than
simply never being called. Now every invocation is visible whether it
proceeds or not.

### Finding 4 — packets with invalid format (previously silent, now caught and logged)

Four distinct cases, all previously dropped with **zero trace of any
kind** — this is the direct reason `_process()`'s WS receive loop and
`_handle_message()`/`_handle_signal()` needed actual validation added,
not just a print statement wrapped around existing behavior:

1. **A WS packet that isn't valid JSON, isn't a Dictionary, or has no
   `"type"` key.** Previously: `JSON.parse_string()` returns `null`,
   `if msg:` is false, the packet is silently discarded — indistinguishable
   from a packet that was simply never sent. Now: explicitly checked in
   `_process()` before ever reaching `_handle_message()`, logged as
   `type=UNKNOWN ... actual_handler=INVALID_FORMAT -- dropped (not a
   dict, or missing "type")`.
2. **A WS message with a well-formed `"type"` this client has no case
   for.** Previously: fell through the entire `if/elif` chain in
   `_handle_message()` with no `else`, silently doing nothing. Now: an
   `else` branch logs `actual_handler=UNHANDLED -- no case matches this
   type`.
3. **A `webrtc_signal` envelope whose inner `data.type` is neither
   `"sdp"` nor `"ice"`.** Same shape of gap, same fix, in
   `_handle_signal()`.
4. **An unrecognized `map_id` in `_receive_map_id`.** This one is a
   valid *packet* with an invalid *payload value* — `MapManager` already
   guarded against it (`if MAPS.has(map_id): ...`), but silently kept
   the old `selected_map_id` and still marked itself synced with zero
   indication anything was wrong. Now logs
   `actual_handler=INVALID_PAYLOAD -- unrecognized map_id, silently
   kept old selected_map_id=...`. (Low real-world risk today — `map_id`
   is only ever set by this same codebase's own `MapManager.MAPS`
   registry, not user input — but the silent-tolerance pattern is
   exactly what this task asked to surface.)

None of these four cases have ever actually been observed firing
in testing (the relay behaves correctly, and this client only ever
sends map ids it knows about) — they're latent gaps in error handling
that are now instrumented and would immediately show up in the trace
the moment any of them ever did occur, rather than vanishing silently
the way they did before this pass.

---

## What this instrumentation deliberately does not attempt

- **Cross-machine correlation.** A `SENT` log on the host's console and
  the corresponding `RECEIVED` log on the joining client's console are
  two different processes' stdout — this instrumentation does not (and
  cannot, without a shared external sink) automatically match them up.
  Verifying "packet X sent by A was actually received by B" requires
  comparing two consoles by hand, or piping both to a shared log file
  during a manual two-client test session.
- **`MultiplayerSynchronizer` traffic** — see the intro above.
- **Removing any of the WS-level `[WS-DEBUG]` logging from the prior
  `SOCKET_DEBUG.md` pass** — that instrumentation and this one now
  coexist (different tags, different granularity: lifecycle events vs.
  full packet fields). Both can be stripped independently by their own
  grep tag.
