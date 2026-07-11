# Final QA Report

## 1.1.0 addendum — teammate-integration QA

After the two QA passes documented below, the teammate systems were
integrated (character skins via `SkinRegistry`/`CharacterRig`, the
Forest Arena map, the echo minimap — see `FINAL_RELEASE_REPORT.md`).
Deltas against the findings below:

- **RESOLVED — "Arena.tscn dead prototype with broken references"
  (Low, "New in this pass"):** resolved by *integration*, not deletion
  — its four missing materials now exist
  (`Materials/{ground,tree_trunk,tree_leaves,cabin}_material.tres`) and
  the map is registered in `MapManager.MAPS` as "Forest Arena". The
  asset sweep was re-run after: zero missing `ext_resource`/`load`
  paths project-wide.
- **RESOLVED — "1 of 6 skin models present" (Low):** `SkinRegistry` is
  now availability-filtered (`available_ids()` /
  existence-aware `valid_id()`), so the picker, replication, and
  instantiation can only ever reference models that exist in the build.
  The five absent models are now a content roadmap, not a hazard.
- **RESOLVED — leftover `check_webrtc.gd`:** deleted (it would have
  shipped inside the pack; only `*.md` was export-filtered).
- **NEW WATCH ITEMS (need one live session):** skinned players' echo
  animation resolves recorded clip names by substring
  (`EchoGhost._resolve_clip`) — code-verified only; and puppet body
  *facing* may not visibly rotate on remote screens (pre-existing:
  the synchronizer replicates `Model:rotation:y` but facing is applied
  to a child of `Model`) — both documented in `KNOWN_LIMITATIONS.md`
  items 5–6.
- Authority/input/RPC surfaces were re-checked after integration: the
  skin swap happens entirely under `$Model` (a cosmetic subtree), never
  touches `set_multiplayer_authority`, the synchronizer's replicated
  properties, or any input path; skin sync reuses the existing
  registration RPC with server-side validation (`SkinRegistry.valid_id`)
  so a malicious/stale skin id cannot replicate.

---

A pre-submission release QA pass, treating this build as if it were
about to go live on itch.io. Every system in scope was reviewed against
its actual code (this pass, plus three prior dedicated audits earlier
in this project's history — `RELEASE_CANDIDATE_REPORT.md`,
`PLAYER_AUTHORITY_REPORT.md`, and the echo-visual work behind
`ECHO_VISUAL_GUIDE.md` — all re-verified still correct as part of this
pass rather than re-derived from scratch). One **High** severity issue
was found and fixed. No **Critical** issue was found outstanding.
Medium and Low findings are documented, not fixed, per this task's
scope.

**This is the second full pass over this codebase** (the request was
re-run). Rather than reissue the same document, this pass deliberately
went after ground the first one hadn't covered yet — every `preload`/
`load()` path in every script *and* every `ext_resource` path in every
`.tscn`/`.tres` file, cross-checked against what's actually on disk;
every `class_name` in the project, checked for collisions; every
`print()` call, checked against the documented debug-instrumentation
allowlist; and the autoload initialization order, checked for a
cross-autoload `get_node()` race. The mouse-sensitivity fix from the
first pass was re-confirmed still in place. One new finding came out of
the wider asset sweep — see "New in this pass" below; everything else
from the first pass was re-verified, not just copied forward.

**Method:** static code review — reading every system listed below
against the actual current source. **No Godot binary was available in
this sandbox** to run the project's own `godot4 --headless --quit`
regression or a live two-peer session — see "Verification still
required" at the end. Findings below are graded by how confidently
they can be asserted from code alone; anything that genuinely needs a
running engine to confirm is called out as such rather than guessed at.

---

## Fixed this pass

### [HIGH] Mouse sensitivity setting has no effect

**File:** `Scripts/Player/components/camera_component.gd`,
`handle_mouse()`.

**Finding:** `GameSettings.mouse_sensitivity` is a real, persisted,
user-facing setting — it has a slider in `SettingsPanel.gd` (in both
the main menu Settings screen and the in-game pause menu), it's saved
to `user://settings.cfg`, and its own doc comment in `GameSettings.gd`
says "multiplier on PlayerController's base sensitivity." It was never
actually read anywhere. `camera_component.gd::handle_mouse()` only used
its own local `@export var sensitivity` — dragging the Settings slider
from one extreme to the other produced **zero change** in actual mouse
look speed. This is a Settings/Input bug: a control that visibly exists,
saves its value, and does nothing.

**Fix:** `handle_mouse()` now multiplies the camera's base sensitivity
by `GameSettings.mouse_sensitivity` before applying it to both the yaw
and pitch rotation.

**Why High, not Critical:** it doesn't break the game or lose player
state — mouse look still works, just always at the hardcoded default
regardless of the slider. But it's a visible, easily-reproduced,
core-control-feel bug on a setting the game itself advertises as
functional, exactly the kind of thing a jam/itch.io player would notice
and report in the first five minutes.

**How to test:** open Settings (menu or pause), drag Mouse Sensitivity
to the minimum, enter/resume a match, confirm mouse look is now
noticeably slower. Drag to maximum, confirm it's now noticeably faster.

---

## New in this pass

### [LOW] `Scenes/Maps/Arena.tscn` is a dead prototype scene with four broken material references

**Found by:** cross-checking every `ext_resource path="res://..."` in
every `.tscn`/`.tres` file against what actually exists on disk (the
first pass only spot-checked `EchoChamber.gd`'s own preloads, which are
all fine — this widened the same check to every scene file in the
project).

**Finding:** `Scenes/Maps/Arena.tscn` — a hand-authored "forest arena"
scene predating this project's `MapKit`-based map system (see
`MAP_SYSTEM.md`; this looks like an early prototype, the ancestor of
what became `EchoChamber.tscn`) — references four materials that don't
exist anywhere in the repository:
`Materials/cabin_material.tres`, `Materials/ground_material.tres`,
`Materials/tree_leaves_material.tres`, `Materials/tree_trunk_material.tres`.
Confirmed by `grep`: nothing in `MapManager.MAPS` (the registry every
real map goes through — currently only `"echo_chamber"`), no `.gd`
script, and no other scene references `Arena.tscn` at all. It is
**completely unreachable from the actual game** — a player can never
encounter it, and it is not the cause of any in-game bug.

**Why Low, not Medium:** zero player-facing impact — nothing loads this
scene at runtime, so the broken references never surface as an error a
player (or even a host/server) would ever see. It's flagged because (a)
Godot's default export filter bundles all project resources, not just
reachable ones, so this dead file with broken links likely ships inside
the itch.io build anyway, and (b) opening this scene in the Godot editor
would show four broken-resource warnings, which looks unpolished during
any code review or a judge poking around the source.

**Not fixed** (Low severity, out of this pass's auto-fix scope) —
recommended action for a future cleanup pass: delete `Scenes/Maps/
Arena.tscn` outright (it's fully superseded by `EchoChamber.tscn` and
unreferenced), rather than trying to restore the four missing
materials for a scene nothing loads.

---

## No Critical issues found (this pass)

Two genuinely Critical issues **were** found and fixed in this
project's history before this pass — both re-verified still fixed as
part of this QA pass, not re-discovered:

1. A reconnect race (`queue_free()` vs. a same-frame respawn's
   `has_node()` check) that could permanently strand a reconnecting
   peer with no player body and therefore no multiplayer authority —
   fixed in `Main.gd` (`players_container.remove_child(node)` before
   `queue_free()`). Full root-cause and sequence-diagram writeup in
   `PLAYER_AUTHORITY_REPORT.md`.
2. A reconnect-grace-expiry round-state reset that only ran on the
   server, silently desyncing the surviving peer's HUD/round state
   forever — fixed via `RoundManager.broadcast_reset_state()`. Full
   writeup in `RELEASE_CANDIDATE_REPORT.md`.

Both were re-confirmed present and correct in the current code as part
of this pass (re-read the exact lines, not just trusted the prior
report).

---

## Medium — documented, not fixed

### [MEDIUM] Ledge-mantle state has a theoretical stuck-forever path

**File:** `Scripts/Player/PlayerController.gd`, `_execute_mantle()` /
`is_mantling`.

`is_mantling` is set `true` at the start of a mantle and only ever
cleared by a `Tween`'s final `tween_callback`. If that tween were ever
interrupted before completing (its node freed, or `create_tween()`
producing a tween that never resolves for some engine-level reason),
`is_mantling` would stay `true` forever — and `_physics_process` returns
immediately, before any input is read, whenever `is_mantling` is true,
so the affected player's controls would freeze exactly like the
already-fixed authority bugs did. **No concrete repro was found** — the
player body is never freed mid-round (only on disconnect, which tears
down the whole node, tween included), so the tween should always run to
completion in every normal-play path examined. Documented as a
watch-item, not fixed, because there's no evidence it's actually
reachable, and a defensive timeout added without a confirmed failure
mode risks adding complexity to fix a bug that may not exist.

### [MEDIUM] Two new-this-session visual assumptions are unverified in a running engine

**Files:** `Scripts/Echo/EchoGhost.gd` (`_build_timeline_ring` —
`TorusMesh` assumed to lie flat around the Y axis by default), `Scripts/
UI/EchoMinimap.gd` / `HUD._build_echo_minimap()` (bottom-left anchor
offset math). Both were implemented from documented/expected Godot 4
`Control`/`PrimitiveMesh` behavior, not confirmed by actually running
the scene (no Godot binary available this session — see "Verification
still required"). Worst case for either is a cosmetic misplacement
(a vertical ring instead of a flat one; a minimap positioned slightly
off from the intended corner), not a crash or gameplay effect. Flagged
here specifically so it gets a visual check before submission rather
than being assumed correct.

### [MEDIUM] `KNOWN_ISSUES.md` has drifted from the current code

Two of its entries are now stale:
- Item 2 ("Reconnect forgets the score") was fixed in this project's
  history (`RoundManager`/`MatchStateManager.sync_scores`, see
  `RELEASE_CANDIDATE_REPORT.md`) but the doc still lists it as an open
  limitation.
- Item 3 ("Internet play requires port forwarding... no NAT
  punch-through / relay") predates the WebRTC relay migration
  (`NETWORK_FLOW.md`) and is no longer accurate — the game now
  matchmakes over a public relay with STUN/TURN by default.

Not fixed here (documentation, not code, and explicitly Medium/Low
scope) — flagged so whoever does the next doc pass knows exactly which
two lines to revisit.

---

## Low — documented, not fixed

- **`Scenes/Maps/Arena.tscn` is dead, unreachable prototype content
  with four broken material references** — see "New in this pass"
  above for the full writeup. Recommended: delete the file.
- **`EchoGhost.tscn`'s `load_steps` header (`6`) no longer matches its
  actual resource count** after swapping `ghost_material.tres` for
  `echo_ghost_material.tres` in a prior pass. Purely cosmetic `.tscn`
  metadata — Godot tolerates the mismatch (it's a load-order hint, not
  a validated count) — but worth correcting on the next scene edit.
- **`EchoGhost._footsteps.active` stays `true` for the ~0.4s dissolve
  animation** instead of being cleared the instant a dissolve starts.
  Harmless in practice: the ghost's position is frozen the moment
  `recorder.has_enough_data()` goes false (see `_process()`), so
  `FootstepEmitter` never observes enough movement to fire a step
  during that window regardless of the flag's value — but the flag not
  reflecting the visual state precisely is a latent inconsistency worth
  tightening in a future pass.
- **`Assets/Characters/Skins/` ships 1 of the 6 models `SkinRegistry.gd`
  references** (`Ninja_Male.fbx` present; `Knight_Golden_Male.fbx`,
  `Witch.fbx`, `Viking_Female.fbx`, `Zombie_Male.fbx`,
  `Cowboy_Female.fbx` are not). **No runtime impact today** —
  `SkinRegistry`/`CharacterRig` are uncommitted, unreferenced files;
  grep confirms nothing in `PlayerController.gd`, `EchoGhost.gd`, or any
  UI script calls into either. This is a "missing assets" finding only
  in the sense that the files don't exist yet, not in the sense that
  anything currently loads and fails to find them.
- **Pre-existing, already-accepted limitations, unchanged by this
  pass** (see `KNOWN_ISSUES.md` for the full reasoning on each): no
  host migration on host-quit; a keyboard-movement-during-pause design
  choice; no macOS or web build; cosmetic `get_unique_id` engine errors
  logged on host quit.

---

## Additional checks this pass, no issues found

- **Autoload cross-reference at startup.** `NetworkManager._ready()`
  calls `get_node("/root/WebRTCSignaler")`, but `WebRTCSignaler` is
  declared *after* `NetworkManager` in `project.godot`'s `[autoload]`
  list — worth checking carefully, since a naive assumption about
  initialization order here could mean a null-instance crash on every
  single game launch. Traced through: Godot adds every autoload as a
  child of `/root` before dispatching `_ready()` to any of them, so the
  node exists by the time `NetworkManager._ready()` runs regardless of
  list order; and the signal being connected to
  (`connection_timed_out`) is registered at script-instantiation time,
  not inside `WebRTCSignaler._ready()`, so the connection is valid even
  before `WebRTCSignaler`'s own `_ready()` has executed. Consistent
  with this exact path being exercised successfully throughout this
  project's documented real-world playtesting. Not a bug.
- **Duplicate `class_name` declarations.** None — every `class_name` in
  `Scripts/` is unique (would otherwise be a hard compile error, not a
  runtime one, so this doubles as a basic compile-sanity check absent a
  Godot binary to actually invoke).
- **Stray debug output.** Grepped every `print(` call in `Scripts/`
  against the two documented, intentional debug systems
  (`PacketTrace.gd` / `[PACKET-TRACE]`, `WebRTCSignaler`'s
  `[WS-DEBUG]`) — zero prints exist outside those two, i.e. no
  accidental leftover debug output from other work.
- **`PacketTrace`/`[WS-DEBUG]` instrumentation itself is still present
  and would ship as-is.** Not a functional bug (every call site is
  correctly guarded and doesn't affect gameplay), but both were
  explicitly authored as `# TEMP DEBUG`, with their own doc comments
  giving the exact `grep` command to find and strip every call site
  before a real release (`PACKET_TRACE.md`, `SOCKET_DEBUG.md`). Worth
  a mention here even though it doesn't meet the bar for a numbered
  Low finding: every RPC and every WebSocket message currently prints
  to the console in a shipped build, which is fine for a jam submission
  but not something to carry into a longer-lived release without a
  deliberate decision to keep it.

---

## System-by-system checklist

| System | Verdict | Notes |
|---|---|---|
| **Menus** (Title/Host/Join/Browser/Settings/Credits) | Pass | Full signal-wiring audit already exists (`UI_STATE_MACHINE.md`); re-checked, still accurate. Title screen now carries a reflection effect (see `THEME_POLISH_REPORT.md`) — cosmetic only, no wiring changed. |
| **Lobby** | Pass | Player-count/room-code refresh, Start Match/Kick visibility gating, free-roam TAB toggle all read correctly from `RoundManager`/`MatchStateManager`/`NetworkManager` state. |
| **Host** | Pass | Room creation → scene transition ordering fixed in prior history (`NETWORK_FLOW.md`); re-verified `NetworkManager.enter_game_as_host()` still only transitions from the server-ack'd path. |
| **Join** | Pass | Same file; joining path transitions on `connected_to_server`, independent of map-sync timing (`MapManager.is_map_ready()`). |
| **Player movement** | Pass (after fix) | Input/authority gating verified correct in `PLAYER_AUTHORITY_REPORT.md`; mouse sensitivity fixed this pass (see above). `move_back` action name fixed in prior history. |
| **Round transitions** | Pass | `RoundManager` state machine (`_apply_round_state` → `_end_round` → delayed `_on_next_round_delay_elapsed`) re-read in full; no gaps found beyond the already-documented Medium items above. |
| **Scoring** | Pass | `MatchStateManager` increments/phase transitions correct; reconnect score-sync gap fixed in prior history, re-verified. |
| **Echo replay** | Pass | `EchoRecorder`/`EchoGhost` sampling, interpolation, and the full VFX suite re-read; animation-player lookup bug (flat vs. recursive search) fixed in prior history, re-verified still fixed. |
| **Networking** | Pass | RPC ownership matrix (every `@rpc` is `"authority"` or explicitly guarded) re-verified in full against current source — see `PLAYER_AUTHORITY_REPORT.md`'s verification matrix. |
| **UI** | Pass | No dangling signal connections found; `EchoMinimap` and reflection labels are new this session, both `MOUSE_FILTER_IGNORE` so they can't intercept clicks. |
| **Audio** | Pass | Bus setup, worker-thread synthesis, positional players all re-read; click-echo addition (`THEME_POLISH_REPORT.md`) uses an independent player so it can't block/replace the primary click sound. |
| **Particles** | Pass | Every `GPUParticles3D` this project creates (existing and new-this-session) is either continuous-and-toggled (`trail`) or one-shot-with-a-`finished`→`queue_free()` connection (`burst`, `ripple`) — confirmed no code path creates a one-shot particle node without ever calling `.restart()`/setting `emitting = true`, which is the specific pattern that would leak an un-freed node. |
| **Respawning** | Pass | `SpawnManager.respawn_player()` + `Main._respawn_local_player()`'s double authority/ownership guard re-verified. |
| **Map loading** | Pass | `MapManager`/`Main._load_map()` isolation from `Players`/authority re-verified; all map asset paths (`EchoChamber.gd`'s preloads, Kenney prop `.glb`s) confirmed present on disk. `MapManager.MAPS` registers exactly one map (`echo_chamber`) — the only other map-shaped scene in the project, `Arena.tscn`, is dead/unregistered (see New in this pass) and was never a map-loading candidate in the first place. |
| **Pause menu** | Pass | ESC handling, game-over override, mouse-capture policy (`HUD._update_mouse()`) re-read; no gaps found. |
| **Settings** | Pass (after fix) | Volume sliders, fullscreen toggle confirmed wired; mouse sensitivity was the one dead control, fixed this pass. |

### Look-for list — explicit results

| Looked for | Result |
|---|---|
| Null references | None found beyond already-guarded `get_node_or_null` patterns (all checked call sites null-check before use). |
| Race conditions | None new; the one known race (reconnect spawn/despawn) was fixed in prior history and re-verified fixed. |
| Missing assets | Two, both Low, both unreachable at runtime — see Low findings. Every `preload`/`load()` path in every script (14 unique) and every `ext_resource` path in every `.tscn`/`.tres` (22 unique) was cross-checked against disk this pass; both misses are dead/unwired content (unused skin models; the orphaned `Arena.tscn` prototype), not something an actual play session can reach. |
| Broken RPCs | None — every RPC re-checked against the authority/guard matrix in `PLAYER_AUTHORITY_REPORT.md`. |
| Physics glitches | One theoretical, unconfirmed path documented (Medium, ledge-mantle). |
| Camera bugs | One found and fixed (mouse sensitivity). Authority-gated activation re-verified correct. |
| Authority bugs | None new; fully covered by `PLAYER_AUTHORITY_REPORT.md`, re-verified. |
| Input bugs | One found and fixed (mouse sensitivity); `move_back` action name fixed in prior history, re-verified. |
| Memory leaks | None found — particle self-cleanup and Tween lifecycle both verified (see Particles row above). |

---

## Verification still required before submission

Everything above is a static-review result. Before an actual itch.io
upload:

1. `godot4 --headless --quit` — confirm the whole project still
   compiles with zero errors (no binary available in this sandbox).
2. A live two-peer session covering the full loop: host → join → lobby
   → Start Match → play a round to both a capture and a timeout →
   confirm the automatic round-2 restart with swapped roles → win a
   match → Rematch.
3. Visually confirm the two Medium-flagged unverified assumptions: the
   echo's ground ring lies flat (not vertical), and the bottom-left
   minimap renders in the correct corner at the intended size.
4. Confirm the mouse-sensitivity fix (this pass) actually changes feel
   in a live session, not just in the code path.
5. An actual exported build (per `BUILD_GUIDE.md`/`EXPORT_GUIDE.md`)
   boot-tested on the target platform(s), not just an editor run.
6. Decide on and act on the two new Low items from this pass before
   packaging: delete `Scenes/Maps/Arena.tscn` (dead, broken references,
   likely bundled into the export as-is), and decide whether to strip
   the `PacketTrace`/`[WS-DEBUG]` console instrumentation for this
   submission or deliberately keep it.
