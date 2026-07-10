# Echo System

The echo mechanic is Echo Hunt's core gimmick: the Hider's movement is
continuously recorded, and one or more translucent "echo ghosts" replay
that recorded movement — position, facing, and animation — some number
of seconds in the past, giving the Hunter a trail that's always slightly
out of date. This document covers how it's built, why it performs well
in multiplayer, and how to test and extend it.

See [`PROJECT_STRUCTURE.md`](PROJECT_STRUCTURE.md) for where these files
sit in the overall folder layout, and
[`GAMEPLAY_SYSTEMS.md`](GAMEPLAY_SYSTEMS.md) for how the echo system fits
into the round loop (when recording starts/stops, who it targets).

---

## Architecture

### Components

```
EchoSystem  (Scripts/Echo/EchoSystem.gd)
   │
   ├── owns exactly one ──▶  EchoRecorder  (Scripts/Echo/EchoRecorder.gd)
   │                              buffers one target's transform + animation
   │
   └── owns one-or-more ──▶  EchoGhost  (Scripts/Echo/EchoGhost.gd)  × N
                                    │
                                    ├── reads from the shared EchoRecorder
                                    ├── AnimPlayer (replays recorded animation)
                                    └── EchoAudio  (Scripts/Echo/EchoAudio.gd)
                                          procedural positional audio cue
```

Each piece has exactly one job:

| Component | Responsibility | Does NOT do |
|---|---|---|
| `EchoSystem` | Owns the recorder + ghost(s) for one tracked target; the only entry point the rest of the game talks to | Recording, rendering, or deciding *who* to track |
| `EchoRecorder` | Buffers a target's transform + current animation name on a timer; answers "what was it N seconds ago" | Rendering, deciding delay, audio |
| `EchoGhost` | Renders one delayed view of a recorder's buffer — position, animation, and an activation trigger for its audio | Recording, deciding *which* recorder to read |
| `EchoAudio` | Synthesizes and plays a positional tone while its ghost is active | Deciding when it should be active — `EchoGhost` calls `begin()`/`stop()` |

`Main.gd` only ever calls `EchoSystem.set_target()` (when a new Hider is
assigned) and `EchoSystem.clear()` (when a round ends) — it has no idea
`EchoRecorder`, `EchoGhost`, or `EchoAudio` exist. That's deliberate:
`EchoSystem` is the whole module's public API surface.

### Recording

`EchoRecorder` samples its `target`'s `global_transform` and current
animation name (read from a sibling node named `AnimPlayer`, matching
`Player.tscn`'s convention) every `sample_interval` seconds, appending
`{t, xform, anim}` to an array and trimming anything older than
`buffer_seconds`. Both are `@export` vars — see "Configurable recording
duration" and "Configurable replay interval" below.

### Replay

`EchoGhost.delay_seconds` says how far in the past to render. Every
frame it asks its recorder for the transform and animation at
`delay_seconds` ago:

- **Transform**: linearly interpolated (`Transform3D.interpolate_with`)
  between the two recorded samples that straddle the requested moment —
  smooth motion even though samples aren't taken every frame.
- **Animation**: animation names are categorical, not interpolatable, so
  the ghost just plays whichever of the two straddling samples' anim is
  closer in time. Repeated identical values are cheaply no-op'd (it only
  calls `AnimPlayer.play()` when the name actually changes) so a ghost
  holding "Idle" for a second doesn't restart the idle animation every
  frame.

A ghost stays invisible and silent until `EchoRecorder.has_enough_data()`
— i.e. until the buffer actually spans the requested delay — so it can
never flicker into existence mid-buffer or replay a mix of "no data yet"
garbage.

### Ghost material & collision

`EchoGhost.tscn`'s mesh uses `Materials/ghost_material.tres`
(`transparency = 1`, unshaded, emissive) so it always reads as "not a
real player" at a glance, and there is **no `CollisionShape3D`
anywhere in the scene** — the ghost cannot block movement, cannot be
walked into meaningfully, and never participates in physics queries.
Capture detection (`WinConditions.is_capture`) only ever compares real
player positions, never a ghost's.

### Positional audio

`EchoAudio` (`extends AudioStreamPlayer3D`) synthesizes a soft,
low-volume hum in real time via `AudioStreamGenerator` rather than
requiring a licensed sound file — this MVP ships with no external audio
assets (see [`Assets/README.md`](Assets/README.md)). Being an
`AudioStreamPlayer3D`, volume and stereo panning automatically follow
the node's position relative to the active listener (the local player's
camera) — "positional" comes for free from the engine, no extra code.
Swapping in a real recorded sound later only means changing what
`stream` is set to in `EchoAudio._ready()`; `EchoGhost` only ever calls
the inherited `play()`/`stop()` plus one custom `begin()` (see the
component's own doc comment for why `begin()` exists), so nothing else
needs to change.

### Multiple echoes

`EchoSystem.echo_delays` is an `Array[float]`, one entry per
simultaneous echo. `EchoSystem` instances one `EchoGhost` per entry, all
pointing at the **same** `EchoRecorder` — multiple echoes are multiple
*views* of one recorded history, not multiple independent recordings, so
adding another echo costs one more cheap read-and-render per frame, not
another full recording pipeline. Ships with a single default delay
(`[10.0]`) to match this MVP's tuned difficulty; set it to e.g.
`[5.0, 10.0]` to show two simultaneous echoes. See Testing below for how
this was verified.

### Configurable recording duration

`EchoRecorder.buffer_seconds` (`@export`, default `10.0`) controls how
far back the buffer reaches, set via `EchoSystem.buffer_seconds` at the
call site (`Main.tscn`'s `EchoSystem` node, or any inspector/script that
configures one). `EchoGhost.delay_seconds` should not exceed whatever
`buffer_seconds` the ghost's recorder is using, or it will simply clamp
to the oldest available sample instead of the requested delay.

### Configurable replay interval

`EchoRecorder.sample_interval` (`@export`, default `0.1`s = 10 samples/
second) controls how often a new sample is recorded. This is the main
performance/precision lever — see Performance below — set via
`EchoSystem.sample_interval`.

---

## Performance

### Zero extra network cost

This is the load-bearing design decision: **the echo system adds no
networking of its own.** Every peer already receives the Hider's
replicated `position` and `BodyMesh:rotation` every tick (that's how the
Hider is rendered as a normal player in the first place —
`MultiplayerSynchronizer` in `Player.tscn`). `EchoRecorder` just reads
that already-arriving data locally and buffers it. Every peer
independently builds its own echo history and renders its own ghost(s)
— no RPCs, no extra replicated properties, no bandwidth cost beyond
player movement sync that would exist regardless of whether the echo
system existed at all.

### Bounded, configurable memory

The buffer is a simple array, trimmed every time a new sample is added
(`while _samples.size() > 2 and now - _samples[0]["t"] > buffer_seconds:
pop_front()`), so memory never grows unbounded across a long session.
Sample count is `buffer_seconds / sample_interval` — at the defaults,
10s / 0.1s = **100 samples**, each a small `Dictionary` (a `Transform3D`
= 12 floats, a timestamp, and a short interned string). Raising
`sample_interval` trades recording precision for a smaller buffer: e.g.
`0.2` halves memory and CPU for a barely-perceptible smoothness cost,
since `get_transform_at()` still interpolates between whatever samples
exist.

### One recording, N renders

Before this pass, "one ghost" meant "one recorder." Now `EchoSystem`
shares a single `EchoRecorder` across every `EchoGhost` it owns, so
enabling multiple simultaneous echoes doesn't multiply recording cost —
only the (cheap) per-ghost read-and-interpolate work scales with echo
count, not the sampling work.

### Audio cost

`EchoAudio` only pushes samples to its `AudioStreamGeneratorPlayback`
while its ghost is active (`EchoGhost` calls `begin()`/`stop()` exactly
on visibility transitions, not every frame) — an inactive/invisible
ghost's audio player does no work at all, not even generate silence.

### Where the cost actually scales

The one thing that *does* scale directly with player count is how many
`EchoRecorder`s exist — one per tracked target. This MVP only ever
tracks the single Hider (a 2-player game has exactly one), so this is
moot today, but is the thing to watch if a future mode ever echoes more
than one player at once.

---

## Testing

### Recording + replay accuracy (deterministic, no networking needed)

The most reliable way to test this system is to drive a fake target on
a controlled timer and check recall — no multiplayer, no waiting on real
wall-clock 10-second buffers. This is exactly what was used to verify
this implementation:

1. Create a `CharacterBody3D` with a child `Node3D` named `BodyMesh` and
   a child `AnimationPlayer` named `AnimPlayer` (loaded with
   `Assets/Characters/MovementAnimations.tres`).
2. Create an `EchoSystem`, configure a short `buffer_seconds` (e.g.
   `2.0`) and `sample_interval` (e.g. `0.05`) for a fast test, and call
   `set_target()` on the fake body.
3. Move the fake body and call `anim_player.play(...)` at known times.
4. After `buffer_seconds` has elapsed, call
   `recorder.get_transform_at(seconds_ago)` /
   `get_animation_at(seconds_ago)` for known past moments and assert the
   position/animation match what was set at that time.

This exact test was run during development: recalling position 0.1s ago
correctly returned the most recent position, recalling 1.9s ago (near
the edge of a 2.0s buffer) correctly returned the oldest recorded
position, and animation recall correctly distinguished "Run" (recent)
from "Idle" (old) at those same two points.

### Multiple echoes

Using the same fake-target harness, set `echo_delays = [0.3, 0.8, 1.5]`
instead of the default single-element array, then after the buffer
fills:
- Confirm `echo_system.get_children()` contains one `EchoGhost` per
  delay (3, in this example).
- Confirm every ghost reports `visible = true`.
- Confirm ghosts at different delays report different `global_position`
  values when the fake target moved during the buffered window (ghosts
  whose delays land in the same movement segment will correctly report
  the *same* position — that's not a bug, it means both delays are
  looking at a moment where the target hadn't moved yet).

This was verified directly: with delays `[0.3, 0.8, 1.5]` against a
target that moved twice during the buffer window, the two closer delays
(0.3s, 0.8s) correctly matched the most recent position while the
farthest delay (1.5s) correctly matched an earlier position — all three
simultaneously visible.

### In-game / manual testing

1. Host + join, play as Hider and move in a distinctive pattern (e.g. a
   loop around a tree) for the first ~10 seconds.
2. Confirm no ghost is visible yet (buffer still filling).
3. After ~10 seconds, confirm a translucent ghost appears and starts
   retracing your movement from about 10 seconds earlier.
4. Confirm the ghost's pose changes between an idle stance and a
   walking/running bob matching whatever you were actually doing 10
   seconds ago (sprint past a spot, then watch the ghost visibly "run"
   through that same spot ~10s later).
5. Get close to the (Hunter's) ghost and confirm you can hear a soft,
   directional hum that gets louder/pans as you approach — and that it
   stops the instant the ghost disappears (round end, or before the
   buffer first fills).
6. Walk straight through the ghost — confirm no collision response at
   all (no push, no blocking, `move_and_slide` behaves as if it isn't
   there).
7. End a round (capture or timeout) and confirm the ghost disappears
   (and its hum stops) immediately, rather than continuing to trail over
   the round-end screen.

### Full regression coverage

This system was also exercised as part of a full two-peer headless ENet
session (host + join, real movement input, real round start) with zero
script errors and zero "ignoring sync data" warnings — confirming the
echo system's zero-extra-networking design holds up under an actual
multiplayer connection, not just in isolation.

---

## Future Improvements

- **Multiple *targets*, not just multiple delays.** `EchoSystem` is
  scoped to one target today (this MVP only ever has one Hider to
  track). If a future mode has more than one player to echo
  simultaneously, `Main.gd` would own multiple `EchoSystem` instances
  (one per target) rather than needing `EchoSystem` itself to change —
  the module boundary already supports this without modification.
- **Real audio asset.** `EchoAudio`'s synthesized hum is a placeholder
  by design (see [`Assets/README.md`](Assets/README.md)); swapping in a
  licensed "echo"/"whisper" sound effect is a one-line change
  (`stream = preload(...)` instead of an `AudioStreamGenerator`) with no
  other code affected.
- **Visual distinction per echo.** With multiple simultaneous echoes
  enabled, all ghosts currently share the same material/color. A subtle
  opacity or hue falloff by delay (closer-in-time echoes slightly
  brighter) would help a Hunter parse multiple echoes at a glance.
  Deliberately not built now since this MVP ships with a single echo by
  default (see "Multiple echoes" above) and this would be pure polish
  for a mode not yet turned on.
- **Adaptive sample rate.** `sample_interval` is fixed per `EchoSystem`
  today. A recorder could lower its own sample rate automatically when
  the target is barely moving (position delta below some threshold) to
  save memory during idle stretches, at the cost of a little more
  complexity.
- **Ghost-to-ghost audio mixing.** With several simultaneous echoes each
  running their own `EchoAudio`, a busy scene could stack multiple hums.
  Not an issue at today's default of one echo; worth revisiting if a
  future balance pass ships more.
