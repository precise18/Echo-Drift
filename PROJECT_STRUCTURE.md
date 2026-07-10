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
│
├── Scenes/
│   ├── Main.tscn               Game root: arena + players + echo system + HUD
│   ├── UI/
│   │   ├── MainMenu.tscn        Host / Join screen
│   │   └── HUD.tscn             In-round timer / role / score / restart
│   ├── Player/
│   │   ├── Player.tscn          Third-person character (CharacterBody3D)
│   │   └── EchoGhost.tscn       Transparent, collision-less echo replay
│   └── Maps/
│       └── Arena.tscn           MVP's single map (forest-styled arena)
│
├── Scripts/
│   ├── Autoload/
│   │   ├── NetworkManager.gd    Host / join / leave — connection lifecycle only
│   │   └── GameManager.gd       Roles, timer, score, win detection, restart
│   ├── Player/
│   │   └── PlayerController.gd  Input, movement, camera, placeholder animation
│   ├── Echo/
│   │   ├── EchoRecorder.gd      Rolling 10s transform buffer for one target
│   │   └── EchoGhost.gd         Renders the buffer at a 10s delay
│   ├── UI/
│   │   ├── MainMenu.gd          Wires menu buttons to NetworkManager
│   │   └── HUD.gd                Reflects GameManager state on screen
│   └── World/
│       └── Main.gd               Spawns players, wires echo target, resets spawns
│
├── Materials/                   StandardMaterial3D placeholders (flat colors)
├── Assets/                      Empty placeholder folders + README for future art
├── UI/Theme/                    Reserved for a shared Theme resource (post-MVP)
└── Audio/                       Reserved for SFX/music (post-MVP)
```

## Script responsibilities (one job each)

| Script | Owns | Does NOT own |
|---|---|---|
| `NetworkManager.gd` | ENet peer creation, connect/disconnect signals, scene transitions on connect | Round rules, scores |
| `GameManager.gd` | Hider/Hunter role assignment, round timer, win detection, score, restart RPC | Movement, rendering |
| `PlayerController.gd` | Reading input and moving *its own* body; ignores input for bodies it doesn't own | Networking, round rules |
| `EchoRecorder.gd` | Buffering one target's transform history | Deciding *who* the target is |
| `EchoGhost.gd` | Rendering a delayed transform | Recording history |
| `Main.gd` | Gluing the above together (spawning, wiring the echo target, spawn placement) | Any gameplay rule itself |
| `MainMenu.gd` / `HUD.gd` | Translating UI events ↔ autoload calls, displaying state | Any gameplay logic |

This split exists so each system can be tested/read in isolation — e.g. you
can understand the entire echo mechanic by reading two ~40-line files
without touching networking code at all.

## Multiplayer architecture (why it's built this way)

- **Host = server**, using Godot's high-level multiplayer API
  (`ENetMultiplayerPeer`) on port `7777`.
- Players are spawned via a `MultiplayerSpawner` watching the `Players`
  node in `Main.tscn`. Only the server calls `add_child()` under that
  node; the spawner automatically replicates the node to every client
  (including late joiners), which is why client code never manually
  instances `Player.tscn`.
- Each `Player.tscn` has a `MultiplayerSynchronizer` replicating its
  position/rotation from whichever peer owns it (`peer_id` = node name).
  `PlayerController.gd` only reads input and calls `move_and_slide()` on
  the body it has authority over — every other peer just receives the
  synced transform.
- `GameManager` state (roles, timer, score) is authoritative on the
  server and pushed to all peers via `@rpc("authority", "call_local",
  "reliable")` calls, so every peer's HUD reflects the same truth.
- The **echo system deliberately needs zero extra networking**: because
  every peer already receives the Hider's replicated transform each
  frame, every peer can independently buffer it locally and render its
  own echo ghost — no custom RPCs, no bandwidth cost beyond the player
  sync that would exist anyway.

## What's explicitly NOT in this MVP

Per the project brief, none of the following are built, and none should
be added until the MVP is validated as fun: AI/bots, checkpoints,
minimap, voice chat, inventory, crafting, multiple playable maps, skins,
cosmetics, settings menu, login, database, cloud saves, achievements,
progression systems, matchmaking, dedicated servers, advanced VFX.

`Scenes/Maps/` and `Assets/` are structured so a post-MVP pass can add
Forest/Dungeon/Laboratory/Castle maps and real art without refactoring
gameplay code — see [`Assets/README.md`](Assets/README.md) — but only one
arena ships in this MVP.
