# Optimization Report

A full-project performance pass: every subsystem reviewed, targeted
changes where they buy something real, and honest "already fine, left
alone" verdicts where they don't. All measurements below were taken
headless on a machine under external load (~3.5 loadavg) — worst-case
conditions, which is exactly when performance work matters.

## Headline changes

| Area | Change | Effect |
|---|---|---|
| Startup | Audio synthesis moved to a worker thread | Boot no longer blocks on synthesis: main-thread cost is now **5–9 ms** (two tiny UI blips); the remaining ~2–3.5 s of GDScript synthesis (measured under load) happens off-thread with zero frame stalls |
| Shadows | Directional shadows 4 cascades → 2 | Every shadow caster is drawn once per cascade; the arena is ~40 m corner to corner, so the extra cascades bought nothing. Shadow-map geometry halved |
| Shadow casters | Particles + teleport pad discs no longer cast | Scene census: **33 → 27 casters**. Combined with the cascade change, shadow-pass draws drop from ~132 to ~54 (≈ 60% less shadow geometry per frame) |
| Echo replay | Two linear scans per ghost-frame → one binary search | O(n) × 2 → O(log n) × 1 per ghost per frame over the ~100-sample buffer, plus no per-frame dictionary rebuilding |
| Round tick | Capture-check node lookup cached | Two by-name tree searches + string allocations per physics tick (server, whole round) → cached references, validated per use |
| HUD | Label text rebuilt only on value change | Timer/countdown/lobby/grace strings were re-formatted and re-assigned 60×/s; now only when the displayed second/count actually changes |

## Per-area review

### Physics
- `physics/common/physics_interpolation` was already on (movement
  smoothing pass); player capsules and static-box colliders are already
  minimal; 2 Area3D teleport pads are negligible. **No structural changes
  needed.**
- `RoundTimer` now disables `_physics_process` while idle instead of
  branching every tick forever (it's an autoload child — it previously
  ticked even on the main menu).
- The server's capture check (`RoundManager._check_for_capture`, twice
  per physics tick all round) no longer does by-name node lookups per
  tick — refs are cached and re-validated (`is_instance_valid` +
  parent check), falling back to a fresh lookup on any miss.

### Rendering / draw calls
Scene census in a live 2-player session (test harness, this build):
**31 MeshInstance3Ds, 4 particle systems, 7 lights, 27 shadow casters.**

- **Cascades**: `SHADOW_PARALLEL_2_SPLITS` on the sun (was the default
  4). Splits multiply shadow-pass geometry; two are visually identical
  at this arena size.
- **Casters**: all 4 particle systems (mirror-pool sparkles, both pad
  shimmers, ghost trail) and both teleport pad discs now have
  `cast_shadow = OFF` — tiny unshaded emissive quads/discs contribute no
  visible shadow but were being drawn into every cascade. The mirror
  pool and ghost body already had it off.
- **Lights**: the 7 lights are 1 shadowed directional + 6 shadowless
  omnis (pool glow, accents, pad glows, ghost glow) — already the cheap
  configuration; mobile renderer + MSAA 2× already chosen in
  `project.godot`.
- **Not done, deliberately**: mesh merging/MultiMesh for the ~31 static
  meshes (the color pass is small; merging would complicate MapKit for
  single-digit draw savings) and occlusion culling (an open arena with
  a mirror-line sightline occludes almost nothing).

### Networking
Reviewed, **no changes** — the networking pass already did the work:
`MultiplayerSynchronizer` replicates only position + body yaw with
ON_CHANGE mode; footsteps, teleport whooshes, round stings, capture
bursts, and the match-over decision all derive locally from
already-replicated state (zero dedicated messages — see
AUDIO_SYSTEM.md/UI_GUIDE.md). Idle bandwidth is near zero; active play
is a few KB/s on LAN. Lowering the sync rate further was considered and
rejected: the savings are irrelevant at LAN scale and remote movement
would visibly coarsen.

### Memory
- **SoundFactory cache**: all 12 synthesized sounds total ≈ **550 KB**
  of 16-bit PCM (music 188 KB, wind 130 KB, hum 63 KB, one-shots the
  rest) — a fixed, session-long budget; nothing regenerates.
- **Echo buffer**: ~100 samples × (Transform3D + small dict) ≈ tens of
  KB, rolling.
- **Flyweight particle resources**: every emitter with the same
  color/dot-size now shares one cached draw mesh + material
  (`MapKit._particle_mesh_cache`) instead of each allocating its own —
  previously every burst, pad, pool, and trail carried duplicates.
- Burst particles free themselves on finish (unchanged); noise
  textures are three 128×128 single-channel generates.

### Scene loading
- **The real cost was audio, and it's gone from the critical path**:
  `AudioManager` now synthesizes only the two UI blips on the main
  thread (measured 5–9 ms) and builds everything else on a `Thread`,
  handing streams back via `call_deferred`. Under load, music alone
  measured ~2 s to synthesize — previously that was part of a blocking
  boot, and an intermediate per-frame-chunk design would have hitched
  frames instead; the thread removes both. `SoundFactory`'s cache is
  now mutex-guarded; a mid-build request from gameplay at worst
  redundantly builds the same deterministic sound (safe, last write
  wins) rather than blocking.
- Scene changes themselves are subsecond (small scenes, GLB props a few
  KB each) and painted over by TransitionScreen — which by design never
  delays the load (see UI_GUIDE.md).

### Script performance
- **EchoRecorder** (hottest per-frame path): `sample_at()` answers
  position *and* animation in one binary search — previously
  `get_transform_at` + `get_animation_at` each linearly scanned the
  buffer every frame per ghost, building throwaway dictionaries. The
  old getters remain as thin wrappers. The recorder also caches its
  target's `AnimationPlayer` instead of `get_node_or_null` per sample.
  Verified against hand-computed expectations (interpolation midpoints,
  boundary clamps, animation nearest-pick) by a dedicated probe.
- **HUD**: all per-frame strings now rebuild only on change, with cache
  invalidation when panels are re-shown.
- **FootstepEmitter / particles / Scoreboard**: reviewed — already
  cheap (a vector subtract per character per frame; signal-driven).

### Object pooling
Reviewed and **deliberately not introduced**: the only transient
objects are one-shot burst particles (≤ ~1/second worst case — teleport
or capture) which already free themselves, and every other emitter
(footsteps, whoosh, hums, stings) is a persistent node reused across
plays — effectively pre-pooled. A pool would add lifecycle complexity
for unmeasurable gain. The allocation cost per burst *was* reduced the
non-pooling way: the flyweight mesh/material cache above means a burst
now allocates only the emitter + process material, not its render
resources.

### Resource management
Materials were already shared `.tres` files (one per surface type,
preloaded); the additions are the mutex-guarded sound cache, the
particle mesh flyweight, and persisted settings. No per-instance
duplicate resources remain.

## Bugs found by this pass (both fixed)

1. **Phantom capture on role swap** (pre-existing): respawning is
   client-authoritative, so at each round start the server could
   briefly see both bodies at the *previous* round's positions —
   occasionally within capture radius, instantly ending the new round.
   Fixed with `RoundManager.CAPTURE_GRACE` (1.5 s, no captures right
   after round start — also a fairness improvement). Caught because the
   optimization regression run lost the timing lottery that earlier
   runs had won.
2. **Freed-instance in the new node cache** (introduced, then caught by
   the same regression): a disconnected player's freed body in the
   cache dictionary errored when assigned to a typed variable; the
   cache now validates before typing.

## Verification

- Clean headless import after every change.
- `EchoRecorder` correctness probe: 7 hand-computed cases, all pass.
- Full two-process host/join regression: lobby → start → three rounds
  with automatic transitions and role swaps → MATCH_OVER 3–0 on both
  peers → client-requested rematch active at 0–0 on both — zero script
  errors, worker-thread music confirmed playing on both peers.
- Audio timing probe (three runs under load): main-thread startup
  synthesis 5–9 ms; off-thread work ~2–3.5 s total that previously sat
  on the boot path.

**On FPS claims**: this environment is headless (no GPU), so no
frames-per-second number here would be honest. What's measurable is
structural: ~60% less geometry in the shadow pass, six fewer shadow
casters, one echo-buffer search instead of two per ghost-frame, per-tick
allocations removed from the round loop and HUD, and synthesis hitches
eliminated. On the target hardware (integrated GPUs at 1280×720) the
shadow-pass reduction is the change most likely to show up directly in
frame time; everything else buys headroom and consistency.
