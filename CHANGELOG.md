# Changelog

All notable changes to Echo Hunt. Versions follow
[Semantic Versioning](https://semver.org/); development happened in
sequential feature passes, each verified with headless two-peer
regression tests before merging.

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
