# Stabilization Report

Scope: this pass added **no new gameplay features**. The objective was to
review the whole project, remove dead weight, and make existing systems
(controls, networking, physics) reliable every time. Everything below was
verified against the actual running project — both interactively (Godot
4.7 editor) and via automated headless two-peer network sessions — not
just read from source.

---

## Bugs Found & Fixed

### 1. Sprint was bound to Ctrl, not Shift
**File:** `project.godot` (`[input]` → `sprint`)

The sprint action's physical keycode was `4194326`. Every doc in the repo
(and the in-game expectation) says "hold Shift to sprint" — but `4194326`
is `KEY_CTRL`. `KEY_SHIFT` is actually `4194325`. Verified directly
against Godot's own `KEY_SHIFT`/`KEY_CTRL` constants at runtime, not from
memory. Players pressing Shift, as documented, got no sprint at all.

**Fix:** rebound `sprint` to `4194325` (real `KEY_SHIFT`).

### 2. Capture never registered across a real network connection
**Files:** `Scripts/World/Main.gd`

*(Identified and fixed earlier in this project's life, re-verified as
part of this stabilization pass rather than re-broken/re-fixed now.)*
`MultiplayerSpawner`'s `spawned` signal only fires on peers that
**receive** a replicated node — not on the server that originates it via
`add_child()`. The server's own copy of the client's player node was
therefore stuck at the default multiplayer authority (`1`, itself), so
the server rejected the client's own position updates as
"non-authority," and the Hunter could stand on top of the Hider forever
without a capture ever firing.

**Fix:** `Main._spawn_player()` explicitly calls
`player.set_multiplayer_authority(peer_id)` immediately after
`add_child()`, in addition to the existing `spawned`-signal handler that
covers the *receiving* peers.

### 3. Game could get permanently stuck after any disconnect
**Files:** `Scripts/Autoload/NetworkManager.gd`,
`Scripts/Autoload/GameManager.gd`

`GameManager` (round state, timer, roles, score) is a singleton that
outlives scene changes. Nothing ever reset it when a connection was
lost. If a round was active when the host disappeared or a peer
dropped, `round_active` stayed `true` forever. Since
`Main._try_start_round()` refuses to start a new round while
`round_active` is already `true`, re-hosting or re-joining after any
disconnect would silently never start a round again — the only fix was
restarting the whole application.

**Fix:** added `GameManager.reset_state()` and call it from
`NetworkManager._on_server_disconnected()` and `_on_connection_failed()`.

### 4. Disconnected players left "ghost" bodies and stuck rounds for whoever remained
**File:** `Scripts/World/Main.gd`

If one peer disconnected mid-round while the other kept running (e.g.
the Hunter's PC lost power), the server never removed that peer's
`Player` node, and `round_active` stayed `true` with no way for it to
ever resolve (the vanished player can't be captured or replicate a
timeout).

**Fix:** `Main._on_peer_disconnected_server()` now despawns that peer's
`Player` node and calls `GameManager.reset_state()`, returning the
remaining player to a clean, restartable state.

### 5. Mouse capture could silently fail on Linux (X11/XWayland)
**File:** `Scripts/Player/PlayerController.gd`

Reproduced directly: `ERROR: NO GRAB at: mouse_set_mode
(display_server_x11.cpp:450)`. `Input.mouse_mode = MOUSE_MODE_CAPTURED`
was only ever called once, in `_ready()`. X11's pointer grab silently
fails if the window doesn't have OS input focus at that exact instant —
which is common for the second of two windows opened in quick
succession, exactly the local two-instance testing workflow this
project's own docs recommend. The result: camera look simply didn't
work, with no visible error to the player.

**Fix:** mouse capture is now also re-applied whenever the game window's
`focus_entered` signal fires (i.e. on window focus, and again on
alt-tabbing back in), so a failed initial grab self-heals instead of
leaving the player stuck.

---

## Dead Code Removed

All of the following were confirmed to have **zero references** anywhere
in the codebase before removal (checked with a full cross-file grep, not
just "doesn't look used"):

| Removed | From | Why |
|---|---|---|
| `NetworkManager.leave_game()` | `NetworkManager.gd` | No button/key ever called it. |
| `NetworkManager.connection_succeeded` signal | `NetworkManager.gd` | Emitted, never connected to anywhere; the scene change it used to "announce" already happens unconditionally right next to the emit. |
| `GameManager.HIDE_WARMUP` constant | `GameManager.gd` | Declared to document the ~10s echo delay but never actually read anywhere — the real delay is `EchoRecorder.BUFFER_SECONDS`. Actively misleading (two "sources of truth" for the same number, only one of which did anything). |
| `GameManager.timer_updated` signal | `GameManager.gd` | Emitted once per round start, never connected to anywhere; `HUD.gd` polls `GameManager.time_left` directly instead. |
| `GameManager.get_local_role()` | `GameManager.gd` | Public method, never called; `HUD.gd` derives role from the `role_assigned` signal instead. |
| Root `.rotation` replication property | `Scenes/Player/Player.tscn` | The `CharacterBody3D` root's own rotation is never modified by any script (only the child `BodyMesh`'s rotation is) — this property was being synced over the network every tick for a value that never changes. Removed from the `SceneReplicationConfig`; `BodyMesh:rotation` (the one that actually matters) is untouched. |

No unused scenes, unused assets, or duplicated logic blocks were found —
the project was already lean going into this pass (confirmed by
cross-referencing every `.tscn`'s `ext_resource` paths and every
`Materials/*.tres` against what's actually instanced).

---

## Remaining Issues (not fixed — see Recommendations)

- **No on-screen message when the other player disconnects.** After the
  fix in item 3/4 above, the remaining player's game returns to a valid,
  restartable state instead of freezing — but nothing tells them *why*
  the round stopped. Adding that message is a small UI feature, which is
  out of scope for a stabilization-only pass.
- **A rejected 3rd connection attempt** (the server already has
  `MAX_PLAYERS = 2`) does surface a generic "Connection failed" message
  via the existing `MainMenu` status label — functional, but the message
  doesn't distinguish "server full" from "wrong IP" or "host not
  running." Cosmetic, not a stability issue.
- **The `Ghosts` physics layer** (`layer_3` in `project.godot`) is
  declared but nothing is ever placed on it — `EchoGhost` has no
  collision at all, by design. Harmless unused metadata, not worth
  touching.

## Technical Debt

- **No automated test suite in the repo.** This session's verification
  used ad-hoc headless `SceneTree` scripts (host + join two full Godot
  processes talking real ENet, driving input, forcing a capture,
  checking state) written and discarded per-run rather than a permanent,
  checked-in test harness. If this project grows, formalizing that
  pattern (or adopting GUT) under a `tests/` folder would pay for itself
  quickly — the authority/spawning bug in particular would have been
  caught by CI on day one instead of manual testing.
- **`GameManager` and `NetworkManager` reference each other directly**
  (`GameManager` reads `NetworkManager.connected_peer_ids`;
  `NetworkManager` calls `GameManager.reset_state()`). This is a
  reasonable amount of coupling for two singletons at this project's
  size, but if the round-state model grows more complex, consider
  routing all cross-autoload calls through signals only, in one
  direction, to keep the dependency graph acyclic.
- **Player-vs-player physical collision** (`collision_mask = 3` on
  `Player.tscn`, i.e. World | Players) is effectively unreachable in
  normal play: the capture radius (1.3m) is larger than the two
  characters' combined collision radii (~0.8m), so a round always ends
  before the bodies can physically touch. Not a bug, just slightly more
  physics work than strictly needed — left as-is since removing it
  changes observable behavior (players would be able to overlap), which
  is a design call, not a stabilization fix.

## Recommendations

1. Add a "Player disconnected" state to the HUD (small, well-scoped
   follow-up feature building directly on the reset-state fix above).
2. Check the headless test scripts used in this session into a
   `tests/` folder (trimmed down and parameterized) so networking
   regressions get caught automatically instead of by manual replay.
3. If this project is ever built/tested in CI, use a **Standard
   (non-Mono)** Godot build for headless steps — the installed Godot 4.7
   **Mono** build crashes (`signal 11`) on `--headless --import` and
   `--headless --editor` specifically because it can't find a `dotnet`
   runtime on this machine. This is unrelated to the project itself
   (confirmed: the same project imports and runs cleanly under Godot
   4.3 Standard, and the actual game — not just `--import` — also runs
   fine interactively under the installed 4.7 Mono editor). Headless
   `--import`/`--editor` on that specific binary is the only thing that
   crashes; normal play does not.
4. Now that disconnect handling is reliable, a "Leave to Menu" button
   would be a natural, low-risk addition — the underlying
   `reset_state()`/cleanup path this report added already does the hard
   part.

---

## Testing Steps

Run these in order after pulling this change. All of them were also
verified via automated two-peer headless sessions during this pass;
these are the manual/interactive equivalents.

### 1. Sprint keybind
1. Host a game, spawn in.
2. Hold **Shift** and move — you should visibly speed up.
3. Hold **Ctrl** instead — you should move at normal walk speed (it's no
   longer bound to anything by default).

### 2. Capture detection over a network
1. Host in one window, join from a second (same PC or two PCs on one
   LAN).
2. As the Hunter, walk directly into the Hider.
3. **Expected:** the round ends immediately in *both* windows
   ("Hunter wins!"), and the score updates on both sides. (Before the
   fix, this would silently never trigger.)

### 3. Reconnect after disconnect doesn't get stuck
1. Host and join, start a round.
2. Close the **joining** window entirely (simulate a dropped
   connection).
3. In the host window: confirm the round ends/resets on its own (check
   the HUD isn't frozen mid-round) rather than hanging.
4. Have a new instance join the still-running host.
5. **Expected:** a new round starts normally. (Before the fix, step 5
   would never happen without restarting the host's app entirely.)

### 4. Mouse capture recovers after alt-tab
1. Host a game and get into the arena.
2. Alt-tab away to another application, then click back into the game
   window.
3. Move the mouse.
4. **Expected:** the camera responds to mouse movement immediately. If
   you instead have to click *inside* the game window first, that's
   expected too (window focus) — but the look input itself should work
   the moment focus returns, with no need to press Esc twice or restart.

### 5. General regression (nothing broken by the cleanup)
Follow the full checklist in `TESTING_GUIDE.md` end to end — host, join,
move, hide, echo ghost appears after ~10s, capture, round restart with
roles swapped, timeout win path. Everything there should behave exactly
as before; this pass changed reliability, not gameplay.
