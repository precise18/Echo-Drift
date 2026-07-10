# Art Direction

This document covers the visual-quality pass on top of the systems
described in `MAP_SYSTEM.md`, `ECHO_SYSTEM.md`, and `GAMEPLAY_SYSTEMS.md`.
It replaces the "procedural placeholder only" framing in `Assets/README.md`
with a real (if still deliberately small) art pass: the project now mixes
a handful of curated free assets with the same procedural-geometry
approach used throughout the codebase, plus lighting, material, particle,
and animation tuning — all done in a way that keeps the "echoes and
reflection" theme (see the game's pitch) legible in the map itself, not
just in the mechanics.

## Visual goal

Stylized low-poly, high-readability, toy-like — the same target stated in
`Assets/README.md` from the MVP phase, now with actual assets and lighting
behind it: flat, saturated colors; simple silhouettes; glowing emissive
accents on anything "echo-related" (the mirror pool, teleport pads, the
echo ghost itself) so the game's central idea — your own past becomes a
visible, glowing trail — reads at a glance.

## Free assets used

Only one asset pack was added, kept deliberately small:

| Source | Pack | Used for | License |
|---|---|---|---|
| Kenney.nl, mirrored via OpenGameArt.org | Nature Kit (2.1) | Rocks, flowers, bushes dressing the Echo Chamber map | CC0 (`Assets/Environment/NatureKit/LICENSE.txt`) |

**Why OpenGameArt and not Kenney.nl/Poly Pizza directly:** Kenney.nl and
Poly Pizza are both JS-rendered single-page apps with no static download
links reachable from a non-browser environment. OpenGameArt.org mirrors
several Kenney packs as plain static files on a traditional
server-rendered site, including a direct CC0-licensed zip of the same
Nature Kit — same assets, same license, just a reachable download path.
Everything pulled is `.glb` (glTF binary, self-contained — no separate
texture files to track), and only 10 small props were kept (see
`Assets/Environment/NatureKit/`): a couple of rock variants, two flower
colors, and a bush, all a few KB each.

Characters, the mirror pool, teleport pads, walls, floor, and pillars
remain procedural `StandardMaterial3D` + primitive-mesh geometry, per
`Assets/README.md`'s original approach — that approach already matched
the visual goal, so it wasn't worth replacing wholesale. The Nature Kit
props exist purely to break up the arena's silhouette with organic shapes
procedural geometry doesn't cover well.

Everywhere a prop is placed, `MapKit.place_prop()` is used, which adds no
collision and isn't tagged into the navigation-source group — dressing
never becomes an accidental obstacle or nav-mesh hole. Props are placed in
mirrored pairs (`EchoChamber._add_mirrored_prop_pair`) like every other
piece of the map, so the "everything has a reflection" layout rule holds
for dressing too.

## Lighting and skybox

`EchoChamber._build_environment()` (`Scripts/Maps/EchoChamber.gd`) now
sets up:

- A `ProceduralSkyMaterial` sky (no texture, no download) tuned toward a
  cool blue-grey — matches the "echo chamber" mood better than Godot's
  default sky and costs nothing extra at runtime.
- A faint cyan fog (`fog_density = 0.004`) — reinforces the echo/reflection
  color language at a distance without hurting readability inside the
  arena, since the arena is small enough that fog barely applies at
  gameplay range.
- Glow/bloom (`glow_enabled`, softlight blend, modest intensity) tuned so
  every emissive surface already in the scene — the mirror pool, teleport
  pads, accent lights, the echo ghost's glow — actually blooms instead of
  just being a flat bright color. This is one Environment resource; it
  doesn't add draw calls or geometry.
- A small saturation/contrast lift (`adjustment_saturation = 1.15`,
  `adjustment_contrast = 1.05`) to keep flat material colors feeling
  stylized rather than washed out.

None of this adds textures, shaders, or extra scene nodes beyond one
`WorldEnvironment` and the pre-existing `DirectionalLight3D` — it's the
cheapest way to change the whole map's mood.

## Materials

`Materials/echo_chamber_floor_material.tres`, `wall_material.tres`, and
`rock_material.tres` each gained a procedural normal map: a `FastNoiseLite`
piped through a `NoiseTexture2D` (`as_normal_map = true`), no image files
involved. This breaks up what were previously flat, perfectly smooth
surfaces with subtle bump detail — cheap because the noise texture is
generated once at load (128×128, small) and reused as a tiling normal map
(`uv1_scale` tiles it across each surface), not computed per-frame.

Player and ghost materials (`player_hider_material.tres`,
`player_hunter_material.tres`, `ghost_material.tres`) gained:

- A low-energy `emission` matching each material's own albedo color, so
  players read clearly even in the map's cooler ambient light/fog without
  looking like a light source themselves.
- `rim_enabled` lighting — Godot's built-in fresnel-style rim term, not a
  custom shader — for a cheap "toon outline" edge glow that's standard
  in this kind of stylized low-poly game and directly helps silhouette
  readability (see **Player readability** below).

## Particles

All particle effects funnel through two new shared helpers in
`Scripts/Maps/MapKit.gd`, both deliberately capped (small `amount`, short
`lifetime`) so adding several of them per map stays cheap:

- **`make_sparkle_particles`** — a small looping ambient effect (one tiny
  unshaded emissive sphere as the draw mesh, gentle upward drift, no
  collision). Used for:
  - The mirror pool's surface glimmer (14 particles).
  - Each teleport pad's idle shimmer (6 particles) — reads as "active"
    before anyone steps on it.
- **`make_burst_particles`** — a one-shot flourish (higher velocity,
  short 0.6s lifetime, frees itself when done via
  `particles.finished.connect(particles.queue_free)`, so it never lingers
  as dead weight). Used for:
  - Both ends of a teleport jump (`TeleportPad._spawn_activation_burst`),
    so stepping through a pad reads as a distinct event.
  - A capture flourish at the hider's position the instant a round ends
    in a capture (`Main._spawn_capture_burst`), in a warm gold color
    (`Color(1.0, 0.75, 0.3)`) deliberately distinct from the cyan
    echo/mirror color language, so "the round just ended" reads instantly
    even before the HUD catches up. Fires identically on every peer off
    the same replicated `round_ended` RPC, so no extra network message
    was needed for it.

A third helper, **`make_trail_particles`**, is world-space
(`local_coords = false`) rather than following its parent — so particles
already emitted stay behind as the parent moves, producing an actual
trail instead of a following cloud. `EchoGhost` uses this
(`Scripts/Echo/EchoGhost.gd`) to leave a faint cyan drip along its
recorded path, toggled on/off in step with the ghost's own
visibility (`_set_active`) so it never emits while hidden.

Total ambient particle `amount` across the whole Echo Chamber map (mirror
pool + both teleport pads' idle shimmer) is 26 — small enough that it
doesn't show up as a meaningful cost next to the map's geometry.

## Environment dressing

`EchoChamber._build_environment_dressing()` places 10 Nature Kit props in
5 mirrored pairs — small rocks and a large rock flanking the pillar rows,
purple and yellow flowers near the mirror pool, and a bush pair near one
wall. Kept intentionally sparse: the goal was breaking up flat ground
silhouette near landmarks players already navigate by (the pool, the
pillars), not filling the arena with clutter that would compete with
spotting an echo or another player.

## Player readability

Beyond the rim lighting and low emission covered under **Materials**:

- Hider (blue) and Hunter (red/orange) materials remain flat, highly
  saturated, and clearly distinct from both the map's cool blue-grey
  palette and each other — this was already true pre-pass and wasn't
  changed, just reinforced with rim/emission.
- The existing `FaceIndicator` box on the front of each capsule (unchanged
  this pass) still gives orientation at a glance — who's facing which
  way, useful for both the Hunter tracking a Hider's last-seen orientation
  and general spatial awareness.

## Animations

`Assets/Characters/MovementAnimations.tres` — the same procedurally-keyed
`AnimationLibrary` used by both live players (`PlayerController.gd`) and
every echo ghost (`EchoGhost.gd`, since ghosts replay animation names from
the recorded history) — gained secondary motion on top of the existing
vertical bob:

- **Idle**: a subtle scale "breathing" pulse (`BodyMesh:scale`, ±3% on Y).
- **Walk**: a gentle alternating lean (`BodyMesh:rotation:z`, ±0.06 rad)
  timed to the existing bob, so the capsule reads as shifting weight
  step-to-step instead of just bobbing in place.
- **Run**: a stronger lean (±0.12 rad) plus a squash-and-stretch scale
  keyed to the same beats — compress on the down-bob, stretch on the up-bob.

No new assets or a rigged skeleton were introduced — the capsule-based
placeholder character stays as documented in `Assets/README.md`, since
replacing it with a rigged model is a much larger scope (sourcing,
importing, retargeting) than "improve visual quality" calls for, and the
existing toy-like capsule silhouette already matches the stated art
target. This is purely more expressive keyframes on the same three
animation clips, so it's free at runtime (no extra tracks are evaluated
unless that clip is playing) and improves both live players and every
echo ghost at once, since both read from the same library.

## Echo visual effects

Summarizing what's new for the echo system specifically (see
`ECHO_SYSTEM.md` for the recording/playback architecture, unchanged this
pass):

- The ghost trail (`make_trail_particles`, above).
- `ghost_material.tres` gained rim lighting on top of its existing
  transparency + emission, so a ghost's translucent silhouette has a
  slightly stronger edge against busy backgrounds (the pillars, the
  Nature Kit props) than a flat transparent blob would.
- The mirror pool and teleport pad sparkle/burst effects use the same
  cyan (`Color(0.55, 0.95, 1.0)`) as the ghost's glow, so every
  "echo-related" visual element — the ghost, the pool, the pads — reads
  as one consistent color language, distinct from the warm gold used only
  for the capture-moment burst.

## Performance

Nothing in this pass adds a shader, a render pass, or per-frame CPU work
beyond what a handful of small `GPUParticles3D` nodes and one extra
`AnimationPlayer` track per clip already cost:

- **Assets**: 10 low-poly `.glb` props, a few KB each, no collision, not
  part of navigation baking.
- **Materials**: procedural normal maps are generated once at load
  (128×128 `NoiseTexture2D`) and reused every frame, not recomputed.
- **Particles**: capped `amount` on every emitter (6–28), short lifetimes,
  one-shot bursts free themselves immediately after finishing. Total
  ambient particle count across the whole map is 26.
- **Lighting**: one `WorldEnvironment` resource; glow is a single
  post-process pass already common in games at this scale.
- **Animations**: more keyframes on existing tracks, no new bones, no
  new meshes.

No new project settings, quality tiers, or minimum-spec changes were
needed — this pass is safe to run on the same hardware the MVP already
targeted.

## Testing

Verified with the project's established headless regression pattern
(`godot --headless --path . --import` after every change, plus scene
instantiation smoke tests that load `EchoChamber.tscn`, `EchoGhost.tscn`,
and `Player.tscn` headless and tick them for several frames) — no parse
errors, no missing-node errors, and every new particle/animation node
present and behaving as expected (ambient particles inactive until
triggered where relevant, ghost trail off by default, burst particles
free themselves). No regression to existing networking, round, or echo
behavior — none of those systems were touched this pass.
