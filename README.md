# Echo Hunt

**Your past is hunting you.**

Echo Hunt is a 3D multiplayer hide-and-seek game where every player's
past movements become living echoes. The Hider's movement is
continuously recorded and replayed 10 seconds later as a translucent,
glowing ghost — complete with animation, footsteps, and a positional
hum. Hunters track echoes through sound and ghost trails; Hiders
deliberately create misleading trails for their future echo to play
back. Your own history becomes your greatest advantage — or your
biggest mistake.

- **Players:** 2 over LAN (one Hider, one Hunter — roles swap every round)
- **Match:** first to 3 round wins; 90-second rounds
- **Engine:** Godot 4.3+, pure GDScript, no external dependencies
- **Version:** 1.0.0 — see [CHANGELOG.md](CHANGELOG.md)

## Play it

Grab a Linux or Windows build (built via [BUILD_GUIDE.md](BUILD_GUIDE.md),
published per [ITCH_IO_DEPLOYMENT.md](ITCH_IO_DEPLOYMENT.md)), then:

1. **Player 1** — *Host Game* → pick the arena → *Start Hosting*.
2. **Player 2** — *Join Game* → enter the host's LAN IP → *Join*.
   The host listens on port **7777**; find your IP with `ip addr`
   (Linux) or `ipconfig` (Windows).
3. Both players land in a **warm-up lobby** inside the arena — walk
   around, learn the space. The host presses **Start Match** when ready.
4. **Hider** — survive the 90-second clock. Your echo repeats
   everything you did 10 seconds ago: keep moving, double back, use the
   teleport pads, make your past lie for you.
5. **Hunter** — listen. Real footsteps are dry; echo footsteps are
   hollow and reverberant. Touch the Hider to win the round.

### Controls

| Input | Action |
|---|---|
| WASD | Move |
| Mouse | Look (third-person) |
| Shift | Sprint |
| Space | Jump |
| ESC | Pause menu |

## Run from source

1. Install [Godot 4.3 or newer (Standard build)](https://godotengine.org/download).
2. Open this folder as a project and press **F5** — or from a
   terminal: `godot --path .`
3. Two instances on one machine: **Debug → Run Multiple Instances → 2**,
   then F5; join with IP `127.0.0.1`.

Full details in [BUILD_GUIDE.md](BUILD_GUIDE.md) and
[HOW_TO_RUN.md](HOW_TO_RUN.md). Never used Godot? Start with
[BEGINNER_GODOT_GUIDE.md](BEGINNER_GODOT_GUIDE.md).

## The map

Echo Hunt ships one arena, **Echo Chamber** — bilaterally symmetric
around the game's own theme: a glowing reflective pool sits on the
mirror line, the Hider and Hunter spawn as literal reflections of each
other, and a linked pair of teleport pads lets you step "through the
mirror" to the other side. Maps are built from a shared procedural kit
and selected on the Host screen (registry-driven — adding a map needs
no menu changes). Full writeup: [MAP_SYSTEM.md](MAP_SYSTEM.md).

## Everything is generated

Apart from ten CC0 low-poly props (Kenney's Nature Kit — see
[LICENSES.md](LICENSES.md)), nothing in this game is a downloaded
asset: the map geometry is procedural (`MapKit`), every sound from
footsteps to the music bed is synthesized at runtime (`SoundFactory`),
and the entire UI theme is built in code (`UIKit`). The repository is
small, license-clean, and every visual/audio decision is readable as
code.

## Documentation index

| Document | What it covers |
|---|---|
| [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) | Architecture map — where to start reading |
| [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) | Every file and folder |
| [GAMEPLAY_SYSTEMS.md](GAMEPLAY_SYSTEMS.md) | Rounds, roles, win conditions, match flow |
| [ECHO_SYSTEM.md](ECHO_SYSTEM.md) | The recording/replay system |
| [NETWORKING_REPORT.md](NETWORKING_REPORT.md) | Multiplayer architecture, reconnect, bandwidth |
| [MAP_SYSTEM.md](MAP_SYSTEM.md) | Reusable map kit + the Echo Chamber |
| [AUDIO_SYSTEM.md](AUDIO_SYSTEM.md) | Synthesized audio + positional design |
| [UI_GUIDE.md](UI_GUIDE.md) | Every screen, the theme system, match UX |
| [ART_DIRECTION.md](ART_DIRECTION.md) | Visual style, lighting, assets |
| [OPTIMIZATION_REPORT.md](OPTIMIZATION_REPORT.md) | Performance work + measurements |
| [BUILD_GUIDE.md](BUILD_GUIDE.md) / [EXPORT_GUIDE.md](EXPORT_GUIDE.md) | Building and exporting |
| [ITCH_IO_DEPLOYMENT.md](ITCH_IO_DEPLOYMENT.md) | Publishing to itch.io |
| [TEST_PLAN.md](TEST_PLAN.md) | Manual + automated test coverage |
| [KNOWN_ISSUES.md](KNOWN_ISSUES.md) | Honest list of current limitations |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Code style + how to add things |
| [CHANGELOG.md](CHANGELOG.md) | Release history |

## License

Code and documentation © the Echo Hunt authors (see
[LICENSES.md](LICENSES.md) for the project licensing note and all
third-party licenses — engine MIT, assets CC0).
