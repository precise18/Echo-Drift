# Echo Hunt (MVP)

Echo Hunt is a 3D multiplayer hide-and-seek game where every player's
past movements become living echoes. Hunters track echoes through sound
and ghost trails, while Hiders can deliberately move to leave misleading
trails for their future self to play back. The result is a simple but
replayable game where your own history becomes your greatest advantage
— or your biggest mistake.

Mechanically: the Hider's movement is continuously recorded, and a
translucent "echo ghost" replays it 10 seconds later — complete with
animation and a positional audio cue — giving the Hunter a trail to
follow that is always slightly out of date.

This is a **minimum viable product**. Its only job is to prove the core
loop is fun: host, join, spawn, hide, leave a trail, follow the trail,
catch (or survive), and play again. Nothing beyond that list is in scope
yet — see [`PROJECT_STRUCTURE.md`](PROJECT_STRUCTURE.md) for what's
deliberately not here.

## Engine & Target

- Godot **4.3** (Stable), GDScript
- Windows desktop, built for itch.io distribution
- 2 players per match: one Hider, one Hunter (roles swap each round)

## Quick start

1. Install Godot 4.3 and open this folder as a project (`project.godot`).
2. Press **F5**. In the window that opens, click **Host Game**.
3. Run a second instance (see [`HOW_TO_RUN.md`](HOW_TO_RUN.md)) and click
   **Join Game** with IP `127.0.0.1`.
4. Move with WASD, look with the mouse, jump with Space, sprint with
   Shift. Survive as the Hider, or follow the cyan echo ghost as the
   Hunter.

Never used Godot before? Start with
[`BEGINNER_GODOT_GUIDE.md`](BEGINNER_GODOT_GUIDE.md) instead.

## Core game loop

```
Main Menu → Select Map → Host or Join → Players Spawn → Hider Hides
   → Echo System Records Movement → Echo Ghost Appears (after 10s)
   → Hunter Tracks Echo → Hunter Finds Hider → Round Ends
   → Score Updates → Play Again
```

## The map

Echo Hunt ships one map, **Echo Chamber** — a bilaterally symmetric
arena built around the game's own theme: a central reflective pool sits
on the mirror line, the Hider and Hunter spawn as literal reflections of
each other, and a linked pair of teleport pads let you step through the
mirror to the other side. Maps are built from a shared, reusable
primitive kit and are selectable before hosting (currently a
one-item menu, architected for more). Full writeup:
[`MAP_SYSTEM.md`](MAP_SYSTEM.md).

## How the echo mechanic works

Every peer keeps a rolling buffer of the Hider's transform and animation
state (`Scripts/Echo/EchoRecorder.gd`). The echo ghost
(`Scripts/Echo/EchoGhost.gd`) continuously renders the Hider's position
and animation from `now - 10s`, interpolated between recorded samples,
plus a soft positional audio cue. It has no collision and uses a
transparent, unshaded, emissive material so it always reads as "not
real." It only appears (and only makes sound) once the buffer holds a
full 10 seconds of data, so it never flickers into existence from
nothing. Full writeup, including how multiple simultaneous echoes work
and how it stays free in multiplayer bandwidth:
[`ECHO_SYSTEM.md`](ECHO_SYSTEM.md).

## Documentation index

- [`PROJECT_STRUCTURE.md`](PROJECT_STRUCTURE.md) — folder layout, what
  each script/scene owns, and what's explicitly out of scope
- [`HOW_TO_RUN.md`](HOW_TO_RUN.md) — running in-editor, local multiplayer
  testing, exporting a Windows build
- [`TESTING_GUIDE.md`](TESTING_GUIDE.md) — a manual verification checklist
  for every MVP feature
- [`GAMEPLAY_SYSTEMS.md`](GAMEPLAY_SYSTEMS.md) — how the round/match/
  scoring/spawn systems are designed, with per-system testing steps
- [`ECHO_SYSTEM.md`](ECHO_SYSTEM.md) — how recording/replay/multiple
  echoes/positional audio work, performance notes, and testing steps
- [`MAP_SYSTEM.md`](MAP_SYSTEM.md) — the reusable map kit, how Echo
  Chamber is built, map selection/sync, and how to add a new map
- [`STABILIZATION_REPORT.md`](STABILIZATION_REPORT.md) — bugs found and
  fixed in the reliability pass, remaining known issues, and recommendations
- [`NETWORKING_REPORT.md`](NETWORKING_REPORT.md) — architecture diagram,
  reconnect support, bandwidth/latency work, and known limitations
- [`BEGINNER_GODOT_GUIDE.md`](BEGINNER_GODOT_GUIDE.md) — a from-zero
  walkthrough for someone who has never opened Godot

## Status

This is a scoped MVP snapshot, hand-authored for a future game jam
expansion. Placeholder low-poly primitives stand in for real art (see
[`Assets/README.md`](Assets/README.md)) — the gameplay systems underneath
are the deliverable, not the visuals.
