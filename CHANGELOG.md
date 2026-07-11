# Changelog

All notable changes to Echo Hunt. Versions follow
[Semantic Versioning](https://semver.org/); development happened in
sequential feature passes, each verified with headless two-peer
regression tests before merging.

## [1.1.0] — 2026-07-11

Release Candidate: teammate feature integration + a full stabilization,
theming, and QA campaign (see FINAL_RELEASE_REPORT.md for the complete
account and FINAL_QA_REPORT.md for the issue-by-issue audit trail).

### Integrated (teammate systems)
- **Character skins** (`SkinRegistry`/`CharacterRig`): pick a character
  on the title screen; the choice replicates with the same
  server-validated registry sync as display names and replaces the
  stock capsule on every peer's screen. The registry is
  availability-filtered — only skins whose model file actually ships
  are offered/replicated, so the remaining five roster entries go live
  by simply dropping their `.fbx` into `Assets/Characters/Skins/`.
  Skins are identity, not role: the hider/hunter tint stays on the HUD,
  never painted over the skin.
- **Forest Arena map**: the second map, registered in `MapManager` and
  selectable when hosting. Its four missing materials (the reason it
  was previously orphaned) were created.
- **Echo minimap**: the bottom-left radar showing the visible echo's
  real relative direction/distance, promoted from preview to shipped.

### Added
- Player display names: entered on the title screen, synced via RPC,
  shown as billboarded 3D name tags (own tag hidden locally).
- Full echo VFX suite: distortion/dissolve shader, spawn pulse,
  dissolve effect, footstep ground ripples, replay-timeline label and
  ring, hum vibrato, UI click echo, title/game-over reflection titles.

### Fixed
- Reconnect race that could permanently strand a peer with no
  controllable body (the "only one player can move" family).
- Reconnect-grace-expiry state reset now broadcast to all peers.
- Reconnecting peer's scoreboard no longer stuck at 0–0.
- Dead `move_backward` input action (S key never worked).
- Echo ghost now finds the player's real AnimationPlayer (recursive
  search), and resolves recorded clip names by substring so skinned
  players' echoes still animate.
- Mouse sensitivity setting is now actually applied to the camera.
- Removed leftover debug script `check_webrtc.gd` from the pack.

## [1.0.1] — 2026-07-11

First-playtest fixes — two bugs found the moment real humans entered
the warm-up lobby together (both reproduced, fixed, and re-verified
with a two-peer headless probe plus the full match-flow regression):

- **Fixed: players launched skyward / unable to move in the lobby.**
  Both bodies spawned coincident at the origin; each peer's physics
  depenetrated its own body upward out of the other's replicated
  collider, ratcheting the pair into the sky (observed at y≈56 within
  seconds). Players now spawn at staggered lobby positions 4 m apart.
- **Fixed: wrong camera current ("stuck in first person").**
  `camera.current` and mouse-capture were decided once in `_ready`,
  which runs before multiplayer authority is assigned on both the
  server (for a late joiner's puppet — which stole the host's camera)
  and clients (whose own camera never became current). Authority-
  dependent state now lives in a re-runnable
  `PlayerController.apply_authority_state()`, called again right after
  authority is actually set on every spawn path.
- Committed editor-generated `.gd.uid` script identifiers (Godot 4.4+
  convention).

## [1.0.0] — 2026-07-11

First release build — the game-jam-ready version.

### Release preparation
- Full project audit (every scene, script, and asset reviewed; no
  debug prints, no TODOs, no orphaned files; licensing verified).
- Export presets for Linux and Windows (single-file binaries, embedded
  pack); production builds created and boot-tested.
- Complete documentation set (see README's index), including build,
  export, deployment, testing, and contribution guides.
- Version stamped in `project.godot`; stale doc sections updated to
  the current match flow.

### Optimization pass
- ~60% less shadow-pass geometry (2 shadow cascades instead of 4;
  particles and teleport pad discs no longer cast shadows).
- Echo replay: one binary search per ghost-frame instead of two linear
  buffer scans; cached animation-player lookups.
- Audio synthesis moved to a worker thread — startup no longer blocks
  (5–9 ms on the main thread, down from up to seconds under load).
- Round-loop and HUD per-frame allocations removed (cached node
  lookups, strings rebuilt only on change, idle timers stop ticking).
- **Fixed:** phantom capture at round start (respawn replication race)
  via a 1.5 s capture grace period.

### UX pass
- Full menu flow: Title / Host (map select) / Join / Settings /
  Credits, all themed by a single code-built UIKit theme.
- Match structure: warm-up lobby (host starts the match), automatic
  round transitions with countdown, **first-to-3** match rule, Game
  Over screen with rematch, pause menu (ESC), loading covers.
- Persistent settings (`user://settings.cfg`): per-bus volume, mouse
  sensitivity, fullscreen, last-joined IP.

### Audio pass
- Complete synthesized audio: footsteps (distinct echo variant),
  teleport whooshes, UI sounds, ambient music, wind, mirror-pool hum,
  round/victory/defeat stings — zero audio files, zero audio network
  messages (everything derives from replicated state).

### Visual quality pass
- Lighting/skybox (procedural sky, glow, fog, grading), procedural
  normal-mapped materials, particles (pool sparkles, teleport bursts,
  echo trail, capture burst), secondary character animation, CC0
  Kenney Nature Kit dressing, player/ghost rim-light readability.

### Map system
- Reusable MapKit + registry-driven map selection (host's choice
  synced to clients). Ships the **Echo Chamber**: a bilaterally
  symmetric arena with mirror pool and linked teleport pads.

### Echo system
- Rolling transform/animation recorder with interpolated replay,
  positional audio cue, support for multiple simultaneous echoes.

### Networking
- Host/join over ENet, spawn synchronization, disconnect handling,
  session-based reconnect with a 20 s grace window, movement smoothing
  via physics interpolation, minimal replication (position + yaw,
  on-change only).

### MVP (initial)
- Third-person 2-player LAN hide-and-seek core loop with the
  10-second echo ghost, procedural arena, HUD, and menus.

[1.0.0]: https://github.com/precise18/Echo-Drift/releases
