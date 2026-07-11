# Echo Visual Guide

Every visual and audio effect that makes an echo ghost read as
**supernatural, not broken** — explained one by one, with the file/line
it lives in, why it exists, and what it costs. This is the companion to
[`ECHO_SYSTEM.md`](ECHO_SYSTEM.md) (the *mechanic*: recording, replay,
timing, networking) — this document is scoped to the *presentation*
only. Nothing here changes when an echo starts, stops, how far in the
past it replays, or any win/lose condition — see "What did not change"
at the end.

## The one-sentence goal

A player should be able to tell **"that's an echo"** in under a second,
from across the arena, without reading a UI element — silhouette,
color, motion, and sound all say it before the label confirms it.

---

## Design constraints this guide was built under

- **Do not change gameplay.** Every effect below is visual or audio
  only. Recording rate, replay delay, capture detection, and round
  timing are byte-for-byte unchanged (see "What did not change").
- **Avoid expensive shaders.** One shader, one draw call per ghost, no
  textures sampled, no screen-space effects (no refraction/distortion
  that reads `SCREEN_TEXTURE`), nothing per-pixel beyond a handful of
  `sin`/`cos`/`pow` calls. See "The distortion shader" for exactly what
  it does and doesn't do.
- **Keep performance suitable for Godot's GL Compatibility renderer.**
  This project ships `renderer/rendering_method = "gl_compatibility"`
  (`project.godot`) — every technique here was chosen to work on that
  renderer specifically (no compute shaders, no SSR, no MSDF-only
  features), not just on the more capable Forward+ renderer.
- **This MVP tracks one echo by default.** `EchoSystem.echo_delays`
  defaults to `[10.0]` (see `ECHO_SYSTEM.md` "Multiple echoes"), so
  "per-ghost cost" below is also "current total cost" in practice — but
  every effect was still built to duplicate cleanly per ghost (see
  "Why the material is duplicated per ghost") for when that changes.

---

## Effects

### 1. Ghost transparency

**File:** `Materials/echo_ghost_material.tres` (`shader_parameter/
base_color` alpha = `0.42`), applied via `Scripts/Echo/EchoGhost.gd`'s
`_material` (a per-ghost duplicate — see below).

A solid-looking capsule reads as "a player, rendered wrong." A
translucent one reads as "not physically there" instantly, before a
viewer even processes color or motion. `render_mode blend_mix` in the
shader is what makes alpha actually blend instead of being treated as
a cutout.

### 2. Blue/cyan emissive glow

**Files:** `echo_ghost.gdshader` (`EMISSION`), `EchoGhost.tscn`'s
`GlowLight` (`OmniLight3D`, `light_color = Color(0.55, 0.95, 1, 1)`).

Cyan is this game's one consistent "supernatural/echo" signal across
every system that touches the mechanic — the mirror pool, the teleport
pads, and the ghost all share the same hue (see `PROJECT_OVERVIEW.md`,
"The theme is load-bearing"). The shader's `EMISSION` output makes the
body glow even in `unshaded` mode (unshaded skips lighting *input*, not
emissive *output*), and `GlowLight` casts actual light into the scene
so the glow reads on nearby surfaces too, not just the ghost itself.

### 3. Fading opacity

**File:** `echo_ghost.gdshader`, `fragment()`: `float pulse = 1.0 +
sin(TIME * pulse_speed) * pulse_amount; ALPHA = base_color.a * pulse *
dissolve;`

A continuous, slow "breathing" alpha oscillation (±16% around the base
0.42, about once per second) on top of the base transparency — the
ghost is never perfectly static, which is a large part of why it reads
as alive/spectral rather than a translucent decal. This is separate
from the spawn/dissolve fades (effects 7–9 below); it's the ghost's
idle, always-on opacity behavior while active. Costs one `sin()` per
pixel — negligible.

### 4. Trailing particles

**Files:** `Scripts/Maps/MapKit.gd` (`make_trail_particles`, unchanged
from before this pass), wired in `EchoGhost._ready()`.

A `GPUParticles3D` in **world-space** (`local_coords = false`) parented
to the ghost, emitting small cyan dots that drift up and fade out —
because it's world-space, already-emitted particles stay behind at the
world position they were emitted at while the ghost keeps moving, which
is what makes it read as a *trail* rather than a cloud following the
ghost around. Toggled on/off with the ghost's active state (`_trail.
emitting`).

### 5. The distortion shader

**File:** `Materials/echo_ghost.gdshader`.

This is the one item on the requirements list that most needed an
explicit "why this counts as lightweight" answer, so here it is in
full:

```glsl
void vertex() {
    float wave = sin(TIME * wobble_speed + VERTEX.y * 3.0);
    VERTEX.x += wave * wobble_amount * dissolve;
    VERTEX.z += cos(TIME * wobble_speed * 0.8 + VERTEX.y * 3.0) * wobble_amount * dissolve;
}
```

A small sine/cosine-driven offset applied to each vertex's X/Z position,
varying by that vertex's height (`VERTEX.y`) — the body wavers gently
like a heat-shimmer or a reflection in disturbed water, rather than
holding a rigid mesh silhouette. What this is **not**: no `SCREEN_
TEXTURE` sampling (the classic "heat haze" technique that refracts
whatever's behind the object — expensive, and one of the GL
Compatibility renderer's weaker areas), no noise texture to load or
sample, no per-pixel raymarching. It's two trig calls per *vertex* (the
ghost capsule is a low-poly primitive, not a dense mesh) and a few more
per *pixel* for the fresnel/shimmer terms below — the entire shader
compiles to straightforward, cheap ALU work with zero texture fetches.

The same shader also drives the fresnel rim (`pow(1.0 - dot(NORMAL,
VIEW), rim_power)` — the edges glow brighter than the face-on surface,
a classic cheap "ghostly" cue with no extra geometry) and reads a
single `dissolve` uniform (0–1) that `EchoGhost.gd` tweens for the
spawn/dissolve effects — see 7 and 9.

### 6. Footstep ripple / ground ripple when the echo walks

**Files:** `Scripts/Audio/FootstepEmitter.gd` (new `stepped` signal),
`Scripts/Maps/MapKit.gd` (`make_ripple_particles`), `EchoGhost.gd`
(`_on_footstep`).

These are the same requirement (the list names it twice — "Footstep
ripple effect" and "Subtle ground ripple when echo walks") and are
implemented as one effect: `FootstepEmitter` already decides exactly
when a step "lands" (distance-based cadence — see its own doc comment);
it now also emits `stepped(ground_position)` at that exact instant,
purely additively (nothing about *when* or *how often* a footstep
sound plays changed). `EchoGhost` listens for that and spawns a
short-lived, one-shot burst of particles at that ground point via
`MapKit.make_ripple_particles()` — a new helper using the same
"cached tiny emissive dot mesh" idiom every other particle effect in
this project already uses (see `MapKit._get_particle_dot_mesh`), just
with `ParticleProcessMaterial.flatness = 1.0`, which collapses the
emission cone onto the ground plane instead of a hemisphere — particles
skate outward along the ground instead of puffing upward, which is what
reads as a ripple rather than a spark. `lifetime = 0.4s`, `one_shot =
true`, frees itself when finished — this is deliberately only ever a
few particles alive at once, timed to footstep cadence (roughly once
every 1.9m of movement, not every frame).

This effect is **only wired to the echo**, not real players, on
purpose — a footstep that visibly ripples the ground is itself a
"this isn't a normal footstep" cue, which would be diluted if real
players did it too.

### 7. Echo spawn pulse

**File:** `EchoGhost.gd`, `_activate()`.

The moment a ghost has enough recorded data to start replaying (or
re-appears after a round restart — see "Survives round restart" below),
it now visibly **materializes** instead of popping into existence:
- The shader's `dissolve` uniform tweens `0.0 → 1.0` over 0.45s
  (`SPAWN_PULSE_TIME`), so the body fades in rather than snapping to
  full opacity.
- The body mesh scales `0.5x → 1.0x` with a `TRANS_BACK`/`EASE_OUT`
  tween — a slight overshoot-then-settle, which reads as "arriving with
  some force" rather than a flat linear grow.
- `GlowLight.light_energy` flashes to 2.4× its resting value and eases
  back down over a slightly longer window — a bright "flash of arrival"
  that fades into the ghost's normal steady glow.
- A one-shot cyan particle burst (`MapKit.make_burst_particles`, same
  helper the capture-flourish and teleport-pad effects already use)
  fires at the spawn point.

### 8. Echo dissolve effect / 9. Echo disappearance effect

**File:** `EchoGhost.gd`, `_deactivate()` / `_finish_deactivate()`.

The list names these separately; they're the two halves of one
transition. When a ghost stops having enough data to replay (round
ends, or `EchoSystem.clear()`/`set_target()` retargets it), it no
longer just vanishes:
1. **Dissolve** (0.4s, `DISSOLVE_TIME`): the shader's `dissolve` uniform
   tweens `1.0 → 0.0` (fading the body out — the same uniform effect 5
   also drives, so "materializing" and "dissolving" are visually the
   same language played in reverse) while the body mesh shrinks to 35%
   scale, plus a smaller particle puff at the moment it starts.
2. **Disappearance**: only *after* both the fade and the shrink tween
   finish (`.chain()` — Godot `Tween` sequencing: everything before
   `.chain()` runs in parallel, everything after runs once all of it
   completes) does `_finish_deactivate()` actually set `visible = false`
   and silence the trail/footsteps/hum. This ordering is what prevents
   the old instant-hide behavior, where a ghost could disappear
   mid-frame while still fully opaque.

If a ghost is told to reactivate while a dissolve is still playing
(e.g. a fast round restart), `_activate()` kills the in-flight tween
first (`_fade_tween.kill()`) before starting its own — so an
interrupted dissolve can never sneak in and hide a ghost that's
actually supposed to be spawning back in.

### 10. Echo replay timeline indicator

**File:** `EchoGhost.gd`, `_build_timeline_label()` / `_build_timeline_
ring()`.

Two complementary pieces, both children of the ghost so they move and
show/hide with it automatically:
- **A floating label** reading `ECHO · 10s AGO` — a billboarded
  `Label3D` above the ghost's head, built the same way (and for the
  same "instantly legible, cheap, no extra draw calls beyond one more
  world-space label") as the player name tags added in a previous pass
  (see `PLAYER_NAME_SYSTEM.md`). This is the single most direct answer
  to "is this an echo" in the whole effect list — it says so, in text.
  `delay_seconds` is a property with a setter (not a plain `@export`)
  specifically because `EchoSystem` sets it *after* the ghost's
  `_ready()` has already run (see `EchoSystem._ready()`'s instantiate →
  `add_child` → *then* `ghost.delay_seconds = delay` order) — a plain
  export var would have shown the wrong number for any echo delay other
  than the default.
- **A slowly-spinning flat ring** at the ghost's feet (`TorusMesh`,
  unshaded, cyan) — a precise "this is where its feet actually are"
  ground marker, and its constant slow rotation (`TIMELINE_RING_SPIN`,
  about one turn per 10 seconds) reads as "time is passing/being
  replayed" at a glance, reinforcing the label without needing to be
  read.

### 11. Directional audio

**Files:** `Scripts/Echo/EchoAudio.gd`, `FootstepEmitter.gd` (echo
variant), `MapKit.make_ripple_particles` (silent — ripples have no
audio of their own).

Both `EchoAudio` and the echo's `FootstepEmitter` are `AudioStreamPlayer3D`
— being 3D-positional is a property of the node type itself, so stereo
panning and distance attenuation toward whichever direction the ghost
actually is (relative to the listener, the local camera) come from the
engine for free, with no extra script code. This was already true
before this pass; what's new here is a **slow pitch vibrato** on the
hum (`EchoAudio._process`: frequency wobbles ±3Hz at 0.35Hz) — a
perfectly steady tone reads as mechanical/electronic, while a tone that
drifts almost imperceptibly reads as unstable/otherworldly. One extra
`sin()` per audio sample — audio synthesis here already runs at 22050
samples/sec doing comparable work, so this is a rounding error on top
of existing cost.

### 12. Small reflection shimmer

**File:** `echo_ghost.gdshader`, `fragment()`:
```glsl
float shimmer = pow(max(sin(TIME * shimmer_speed + VERTEX.y * 9.0), 0.0), 10.0);
emission_color += rim_color.rgb * shimmer * 0.6;
```
A narrow, fast-moving bright band that sweeps up the body every couple
of seconds (`shimmer_speed = 5.5`, `pow(..., 10.0)` sharpens the sine
into a thin peak instead of a broad glow) — an intermittent glint
rather than a constant highlight, like light catching a moving water
surface. Ties back to the "Reflection" half of the game's own
"Echoes and Reflection" theme (the arena's mirror pool, mirror panels,
and now the ghost itself all carry the same "catches the light
unevenly" language). Costs one extra `pow`/`sin` per pixel.

### Minimap (preview)

**Files:** `Scripts/UI/EchoMinimap.gd`, wired into `HUD.gd`'s bottom-left
corner via `_build_echo_minimap()`.

Added mid-pass as an explicit **throwaway preview**, not a finished
feature — a small radar-style circle in the bottom-left HUD corner:
the local player as a fixed center marker, and a cyan blip showing the
real relative direction/distance to the *currently visible* echo,
clamped to the rim when it's farther than 24m away. Built entirely from
`CanvasItem` primitives (`draw_circle`/`draw_arc`/`draw_colored_
polygon`) — no art, so there's nothing to clean up if it's discarded.
Explicitly does **not** rotate with camera facing and only plots one
echo (matching this MVP's single-echo default) — both are exactly the
kind of shortcut a "just to see how it looks" pass is allowed to take,
and both are called out in the file's own doc comment so nobody mistakes
this for finished UX. It only ever plots a ghost that's already
`visible` (i.e. something already inferable by looking/listening in the
world), so it doesn't hand the Hunter information they couldn't already
have gotten in-world.

---

## Why the material is duplicated per ghost

`EchoGhost._ready()`:
```gdscript
_material = _body_mesh.get_surface_override_material(0).duplicate()
_body_mesh.set_surface_override_material(0, _material)
```
`ShaderMaterial` resources are shared by reference unless explicitly
copied. Without this duplicate, tweening one ghost's `dissolve` uniform
(spawn/dissolve — effects 7–9) would visibly yank *every* simultaneous
echo's opacity around too, since they'd all be pointing at the exact
same material resource loaded from `echo_ghost_material.tres`. This
MVP ships one echo by default so the bug wouldn't show today, but
`EchoSystem.echo_delays` supporting multiple simultaneous ghosts is an
existing, documented feature (see `ECHO_SYSTEM.md` "Multiple echoes") —
this fix was applied proactively rather than waiting for that setting
to change and the cross-talk to appear.

---

## Performance summary

| Effect | Per-frame cost | Notes |
|---|---|---|
| Shader (transparency, glow, fade, distortion, shimmer) | 1 draw call, a few `sin`/`cos`/`pow` per vertex/pixel | No textures sampled, no screen-space reads. GL Compatibility-safe. |
| Trail particles | Existing `GPUParticles3D`, unchanged | Already budgeted — see `ECHO_SYSTEM.md` Performance. |
| Footstep ripple | One short-lived `GPUParticles3D` (`lifetime = 0.4s`, one-shot) roughly every 1.9m of movement | Frees itself; never more than one or two alive at once. |
| Spawn/dissolve pulse | Two `Tween`s + one particle burst, only on activation/deactivation edges | Not continuous — fires on state *changes* only, which happen a handful of times per round. |
| Timeline label | One `Label3D`, static text (only updates when `delay_seconds` is set) | Same cost class as the player name tags already in the game. |
| Timeline ring | One low-poly `TorusMesh`, one `rotate_y()` call/frame | A single float add per frame; no shader. |
| Vibrato hum | One extra `sin()` per audio sample | Audio synthesis already does comparable per-sample work. |
| Minimap preview | `_draw()` once per frame, ~6 primitive draw calls | 2D `CanvasItem` drawing, not 3D — negligible; only active while HUD exists. |

Total added cost for this MVP's default single-echo configuration: one
extra shader (replacing a plain `StandardMaterial3D` the ghost already
had), one small always-on particle system reused from existing helpers,
occasional short-lived particle bursts, two lightweight always-present
3D nodes (label + ring), and a few 2D HUD draw calls. Nothing here adds
network traffic, physics queries, or per-frame heap allocation beyond
what particle bursts already did before this pass (see `ECHO_SYSTEM.md`
Performance for the zero-networking design this all builds on).

---

## What did not change

- **Recording/replay timing** — `EchoRecorder.sample_interval`,
  `buffer_seconds`, and `EchoGhost.delay_seconds`'s actual *value* are
  untouched (only how the value reaches the label changed — see
  effect 10).
- **Collision** — `EchoGhost.tscn` still has no `CollisionShape3D`;
  nothing added here gives the ghost any physical presence.
- **Win conditions** — `WinConditions.is_capture` still only ever
  compares real player positions (`RoundManager._check_for_capture`);
  no new code path reads anything from `EchoGhost`.
- **Footstep cadence** — `FootstepEmitter`'s distance-based step timing
  is unmodified; it now also *emits a signal* at the same moments it
  already decided to play a sound, nothing more.
- **Networking** — every effect here is computed independently, locally,
  on every peer from data that was already being replicated/recorded
  before this pass (see `ECHO_SYSTEM.md` "Zero extra network cost").
  No new RPCs, no new replicated properties.

## Testing

1. Play a round as Hider, move for ~10 seconds, then watch for the
   ghost's first appearance: confirm the spawn pulse (scale
   overshoot + light flash + particle burst + fade-in) instead of an
   instant pop.
2. Walk the Hider in a loop and watch the ghost's replayed footsteps:
   confirm a small ground ripple appears under the ghost at each step,
   in sync with the (reverberant) echo footstep sound.
3. Stand near the ghost for a few seconds: confirm the body visibly
   wavers (distortion), breathes in opacity (fading opacity), and
   occasionally catches a brighter glint traveling up it (shimmer) —
   all without the silhouette ever looking broken/glitchy.
4. Confirm the floating `ECHO · 10s AGO` label and the slowly-spinning
   ground ring are both present and legible from a normal play
   distance.
5. End a round (capture or timeout): confirm the ghost visibly
   dissolves (fade + shrink + particle puff) rather than vanishing
   instantly, and that its hum/footsteps/trail all stop at the same
   moment it finishes disappearing, not before.
6. Check the bottom-left minimap: confirm the echo blip's direction on
   the radar matches its actual direction from the player in the world,
   and that it disappears from the radar when the ghost itself isn't
   visible (buffer not full yet, or round ended).
7. If `EchoSystem.echo_delays` is temporarily changed to `[5.0, 10.0]`
   for testing multiple simultaneous echoes: confirm each ghost's spawn
   pulse/dissolve and label text are independent of the other's (see
   "Why the material is duplicated per ghost").
