# Echo Hunt (MVP)

A 3D multiplayer hide-and-seek prototype built around an **echo /
reflection** mechanic: the Hider's movement is continuously recorded, and
a translucent "echo ghost" replays it 10 seconds later — giving the Hunter
a trail to follow that is always slightly out of date.

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
Main Menu → Host or Join → Players Spawn → Hider Hides
   → Echo System Records Movement → Echo Ghost Appears (after 10s)
   → Hunter Tracks Echo → Hunter Finds Hider → Round Ends
   → Score Updates → Play Again
```

## How the echo mechanic works

Every peer keeps a 10-second rolling buffer of the Hider's transform
(`Scripts/Echo/EchoRecorder.gd`). The echo ghost
(`Scripts/Echo/EchoGhost.gd`) continuously renders the Hider's position
from exactly `now - 10s`, interpolated between recorded samples. It has no
collision and uses a transparent, unshaded, emissive material so it always
reads as "not real." It only appears once the buffer holds a full 10
seconds of data, so it never flickers into existence from nothing.

## Documentation index

- [`PROJECT_STRUCTURE.md`](PROJECT_STRUCTURE.md) — folder layout, what
  each script/scene owns, and what's explicitly out of scope
- [`HOW_TO_RUN.md`](HOW_TO_RUN.md) — running in-editor, local multiplayer
  testing, exporting a Windows build
- [`TESTING_GUIDE.md`](TESTING_GUIDE.md) — a manual verification checklist
  for every MVP feature
- [`BEGINNER_GODOT_GUIDE.md`](BEGINNER_GODOT_GUIDE.md) — a from-zero
  walkthrough for someone who has never opened Godot

## Status

This is a scoped MVP snapshot, hand-authored for a future game jam
expansion. Placeholder low-poly primitives stand in for real art (see
[`Assets/README.md`](Assets/README.md)) — the gameplay systems underneath
are the deliverable, not the visuals.
