# Project Structure

```
Echo Hunt/
├── project.godot              Engine config, autoloads, input map, layers
├── icon.svg                   Project icon
├── README.md
├── PROJECT_STRUCTURE.md       (this file)
├── HOW_TO_RUN.md
├── TESTING_GUIDE.md
├── BEGINNER_GODOT_GUIDE.md
├── STABILIZATION_REPORT.md
├── GAMEPLAY_SYSTEMS.md
├── ECHO_SYSTEM.md
├── NETWORKING_REPORT.md
├── MAP_SYSTEM.md
│
├── Scenes/
│   ├── Main.tscn               Game root: map container + players + echo system + HUD
│   ├── UI/
│   │   ├── MainMenu.tscn        Host / Join screen + map selector
│   │   └── HUD.tscn             In-round timer / role / round-end panel (Scoreboard lives here too)
│   ├── Player/
│   │   ├── Player.tscn          Third-person character (CharacterBody3D)
│   │   └── EchoGhost.tscn       Transparent, collision-less echo replay (animation + positional audio)
│   └── Maps/
│       └── EchoChamber.tscn     The MVP's map: symmetric, reflection-themed (see MAP_SYSTEM.md)
│
├── Scripts/
│   ├── Autoload/
│   │   ├── NetworkManager.gd     Host / join — ENet connection lifecycle only
│   │   ├── RoundManager.gd       Orchestrates one round: roles, timer, win checks, restart
│   │   ├── MatchStateManager.gd  Cumulative score + match phase across rounds
│   │   ├── MapManager.gd         Map registry + network-synced map selection
│   │   └── AudioManager.gd       Buses, music/ambience beds, UI sounds, round stings (see AUDIO_SYSTEM.md)
│   ├── Audio/
│   │   ├── SoundFactory.gd       Synthesizes + caches every sound as AudioStreamWAV (no audio files)
│   │   └── FootstepEmitter.gd    Positional footsteps derived from observed movement (players + ghosts)
│   ├── Gameplay/
│   │   ├── Role.gd               Shared HIDER/HUNTER/NONE identifier
│   │   ├── RoleManager.gd        Pure logic: who hides/hunts next (team assignment)
│   │   ├── RoundTimer.gd         Reusable countdown component
│   │   └── WinConditions.gd      Pure logic: capture / timeout checks
│   ├── Maps/
│   │   ├── MapKit.gd             Reusable static builders every map is made from
│   │   ├── TeleportPad.gd        Self-contained linked-pair teleport component
│   │   └── EchoChamber.gd        The MVP map, built entirely from MapKit
│   ├── Player/
│   │   └── PlayerController.gd  Input, movement, camera, placeholder animation
│   ├── Echo/
│   │   ├── EchoSystem.gd         Owns one recorder + N ghosts for one tracked target (public API)
│   │   ├── EchoRecorder.gd       Configurable rolling transform+animation buffer for one target
│   │   ├── EchoGhost.gd          Renders the buffer at a configurable delay, replays animation
│   │   └── EchoAudio.gd          Procedural positional audio cue for one ghost
│   ├── UI/
│   │   ├── MainMenu.gd          Wires menu buttons + map selector to NetworkManager/MapManager
│   │   ├── HUD.gd                Reflects RoundManager state on screen (timer/role/round-end)
│   │   └── Scoreboard.gd         Reflects MatchStateManager score on screen
│   └── World/
│       ├── Main.gd               Loads the selected map, spawns players, wires echo target
│       └── SpawnManager.gd       Pure logic: spawn-point lookup + player (re)placement
│
├── Materials/                   Shared StandardMaterial3Ds (flat colors + procedural normal maps, see ART_DIRECTION.md)
├── Assets/
│   ├── Characters/MovementAnimations.tres  Shared Idle/Walk/Run library (Player + EchoGhost)
│   └── Environment/NatureKit/    CC0 low-poly dressing props (Kenney — see ART_DIRECTION.md)
├── UI/Theme/                    Reserved for a shared Theme resource (post-MVP)
└── Audio/                       Reserved for recorded SFX/music files if synthesis is ever replaced (see AUDIO_SYSTEM.md)
```

See [`GAMEPLAY_SYSTEMS.md`](GAMEPLAY_SYSTEMS.md) for a full writeup of every
round/match system, [`ECHO_SYSTEM.md`](ECHO_SYSTEM.md) for the echo/ghost
mechanic, and [`MAP_SYSTEM.md`](MAP_SYSTEM.md) for the map kit and how to
add a new map. This file stays focused on overall project layout.

## Script responsibilities (one job each)

| Script | Owns | Does NOT own |
|---|---|---|
| `NetworkManager.gd` | ENet peer creation, connect/disconnect signals, scene transitions on connect | Round rules, scores |
| `RoundManager.gd` | Hider/Hunter role assignment (via RoleManager), round timer (via RoundTimer), win detection (via WinConditions), restart RPC | Movement, rendering, cumulative score |
| `MatchStateManager.gd` | Cumulative score, match phase (Lobby / RoundActive / RoundEnded) | Anything round-specific (timer, roles) |
| `RoleManager.gd` | Pure function: connected peer ids + previous hider → next hider/hunter | Networking, state |
| `RoundTimer.gd` | Counting down and announcing expiry | Deciding what expiry *means* |
| `WinConditions.gd` | Pure functions: is this a capture? is this a timeout? | Acting on the answer |
| `SpawnManager.gd` | Pure functions: where is this role's spawn point; move a body there | Deciding *when* to respawn |
| `MapManager.gd` | Map registry, active selection, syncing that selection to a joining client | Building map content itself |
| `MapKit.gd` | Pure functions: build a ground/wall/pillar/obstacle/light/spawn point, bake navigation | Deciding a map's *layout* |
| `TeleportPad.gd` | Teleporting a body to its linked pad on entry | Deciding *where* pads go |
| `PlayerController.gd` | Reading input and moving *its own* body; ignores input for bodies it doesn't own | Networking, round rules |
| `EchoSystem.gd` | Owning one recorder + N ghosts for one target; the only echo API `Main.gd` talks to | Recording/rendering details |
| `EchoRecorder.gd` | Buffering one target's transform + animation history | Deciding *who* the target is, rendering |
| `EchoGhost.gd` | Rendering a delayed transform + animation, driving its audio's on/off | Recording history |
| `EchoAudio.gd` | Synthesizing/playing one ghost's positional tone | Deciding *when* it should play |
| `Main.gd` | Gluing the above together (spawning, wiring the echo target, triggering respawns) | Any gameplay rule itself |
| `MainMenu.gd` / `HUD.gd` | Translating UI events ↔ autoload calls, displaying round state | Score display (that's Scoreboard.gd), any gameplay logic |
| `Scoreboard.gd` | Displaying cumulative score from MatchStateManager | Round state, timer, roles |

This split exists so each system can be tested/read in isolation — e.g. you
can understand the entire echo mechanic by reading two ~40-line files
without touching networking code at all, or understand exactly how a
winner is decided by reading the ~20-line `WinConditions.gd` without
wading through RPC/networking code at all.

## Multiplayer architecture (why it's built this way)

- **Host = server**, using Godot's high-level multiplayer API
  (`ENetMultiplayerPeer`) on port `7777`.
- Players are spawned via a `MultiplayerSpawner` watching the `Players`
  node in `Main.tscn`. Only the server calls `add_child()` under that
  node; the spawner automatically replicates the node to every client
  (including late joiners), which is why client code never manually
  instances `Player.tscn`.
- Each `Player.tscn` has a `MultiplayerSynchronizer` replicating its
  position from whichever peer owns it (`peer_id` = node name).
  `PlayerController.gd` only reads input and calls `move_and_slide()` on
  the body it has authority over — every other peer just receives the
  synced transform.
- `RoundManager` state (roles, timer) and `MatchStateManager` state
  (score) are authoritative on the server and pushed to all peers via
  `@rpc("authority", "call_local", "reliable")` calls, so every peer's
  HUD/Scoreboard reflects the same truth.
- The **echo system deliberately needs zero extra networking**: because
  every peer already receives the Hider's replicated transform each
  frame, every peer can independently buffer it locally and render its
  own echo ghost — no custom RPCs, no bandwidth cost beyond the player
  sync that would exist anyway.

## What's explicitly NOT in this MVP

Per the project brief, none of the following are built, and none should
be added until the MVP is validated as fun: AI/bots, checkpoints,
minimap, voice chat, inventory, crafting, skins, cosmetics, settings
menu, login, database, cloud saves, achievements, progression systems,
matchmaking, dedicated servers, advanced VFX.

The map system (see [`MAP_SYSTEM.md`](MAP_SYSTEM.md)) is built to take
on more maps (Dungeon, Laboratory, Castle) without touching its
architecture — adding one is a registry entry plus a new `MapKit`-built
scene — but only one map, Echo Chamber, ships now.
