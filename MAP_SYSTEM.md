# Map System

A reusable map system: maps are self-contained scenes built from a
shared, reusable primitive kit, selectable before a match, and every map
carries the same required infrastructure (spawn points, navigation,
teleport locations, lighting, collision, gameplay boundaries). This MVP
ships one map, **Echo Chamber**, designed around the game's own
echo/reflection theme — but the system underneath is built to take on
more maps (Dungeon, Laboratory, Castle, per the original brief) without
touching anything described here.

---

## Architecture

```
MainMenu (map selector, host only)
      │  MapManager.set_selected_map(id)
      ▼
MapManager (autoload)
      │  authoritative on host; synced to a joining client via a
      │  reliable RPC sent the instant they connect (independent of
      │  scene-load timing — see "Selection & sync" below)
      ▼
Main.gd
      │  MapManager.instantiate_selected_map()
      ▼
Scenes/Maps/EchoChamber.tscn  (Node3D + EchoChamber.gd)
      │  built entirely from:
      ▼
MapKit (Scripts/Maps/MapKit.gd) — reusable static builders
      ground • wall • pillar • box obstacle • light • spawn point • navigation bake
      │
      └── TeleportPad (Scripts/Maps/TeleportPad.gd) — self-contained Area3D component
```

### MapManager — registry + network-synced selection

`Scripts/Autoload/MapManager.gd` (autoload) is the single source of
truth for "which map is this match using":

- `MAPS`: a `Dictionary` registry — one entry per shippable map (id →
  display name + scene path). **Adding a new map is one new entry here
  plus one new map scene** — nothing else in this file, or anywhere
  else in the selection/sync system, needs to change.
- `set_selected_map(id)` — called from `MainMenu.gd` before `Host Game`.
- `instantiate_selected_map()` — returns a ready-to-`add_child()` map
  root, used by `Main.gd`.
- `is_map_ready()` — true immediately on the server (its own choice is
  authoritative); true on a client only after the sync RPC below has
  actually arrived.
- `sync_to_peer(peer_id)` / `_receive_map_id` (RPC) — the moment a peer
  connects, the server sends them the active map id, independent of
  whatever pace that peer's own scene loading happens at.

**Selection & sync, and a real bug this design avoids:** the natural
first instinct is "don't load the game scene on a joining client until
they know which map to build." That was this project's first
implementation — and it broke `MultiplayerSpawner` replication, because
Godot starts replicating already-spawned nodes (e.g. the host's own
player) to a new peer as soon as the ENet connection completes, which
can arrive *before* a custom RPC does, and needs `Main.tscn`'s
`MultiplayerSpawner` to already exist to receive it. The fix: **the
game scene always loads immediately** (unchanged from before this
system existed), and only *map content* waits on the sync —
`Main.gd` checks `MapManager.is_map_ready()`, instantiating right away
if true or deferring to the `map_selected` signal if not. Nothing else
in `Main.tscn` (`Players`, `MultiplayerSpawner`, `EchoSystem`) is ever
blocked on map sync. See `NETWORKING_REPORT.md` for the broader pattern
this follows.

### MapKit — the reusable asset kit

`Scripts/Maps/MapKit.gd` (static functions only, no state) is what "maps
use reusable assets" means in a project with no external art files (see
`Assets/README.md`): the *pieces* are shared code, not copy-pasted
resource blocks duplicated into every map's `.tscn`. A map script calls
these to build itself in `_ready()` — the same pattern `EchoSystem.gd`
already uses for its ghosts, extended to whole maps:

| Function | Builds |
|---|---|
| `make_ground(size, material)` | A flat, collidable, walkable slab |
| `make_wall(size, center, material)` | A wall / room-divider box segment |
| `make_pillar(radius, height, base_position, material)` | A vertical cylinder — pillar, tower, trunk |
| `make_box_obstacle(size, center, material)` | A generic solid box — crate, pedestal, cell wall |
| `make_light(position, color, energy, range)` | A collision-less point light |
| `make_spawn_point(position, group)` | A `Marker3D` tagged into `hider_spawn`/`hunter_spawn` |
| `bake_navigation(region)` | Bakes a walkable `NavigationMesh` from every MapKit piece in the map |

Every `StaticBody3D` MapKit builds is auto-tagged into a shared
`nav_source` group, so `bake_navigation()` finds all of a map's
collision geometry regardless of where a map script puts it in its own
node hierarchy, and bakes from **collision shapes**, not visual meshes
(more correct, and avoids a GPU-readback performance warning Godot logs
if you bake from meshes at runtime).

### TeleportPad — reusable, self-contained component

`Scripts/Maps/TeleportPad.gd` (`extends Area3D`) builds its own
collision shape and glowing visual mesh in `_ready()` — like
`EchoAudio.gd`, a map script only does `add_child(TeleportPad.new())`
and wires `linked_pad` afterward; nothing else needs assembling.
Stepping into a pad teleports the entering body to its linked partner
(with a short cooldown so you don't instantly bounce back through the
pair) — each peer only teleports the body it actually has multiplayer
authority over, so this works correctly over the network with zero
custom RPCs, the same "each client already knows what it needs to know"
pattern the echo system uses.

---

## The Echo Chamber map

Every map must contain spawn points, navigation, teleport locations,
lighting, collision, and gameplay boundaries. Echo Chamber's design
doesn't just check those boxes — it uses them to *literalize the game's
own theme*:

- **Bilateral symmetry.** The whole layout mirrors across the plane
  X = 0 — every pillar, panel, and light exists as a `(x, z)` /
  `(-x, z)` pair (`EchoChamber._build_mirrored_obstacles`). The two
  spawn points sit at `(-10, 1, 0)` and `(10, 1, 0)`: literal mirror
  images of each other, so the Hider and Hunter start the round as
  reflections of one another.
- **The mirror pool.** A flat, highly reflective disc
  (`mirror_pool_material.tres` — metallic, near-zero roughness, a faint
  cyan emission) sits exactly on the mirror plane at the map's center —
  the thing everything else is reflected *across*, and a landmark both
  players navigate by. Deliberately non-collidable (a `MeshInstance3D`
  with no `StaticBody3D`) so it's a visual centerpiece, not a
  gameplay obstruction.
- **Mirrored teleport pads as a mechanic, not just a visual.** A linked
  `TeleportPad` pair sits at `(-13, 0, 10)` / `(13, 0, 10)` — stepping
  into one is, thematically, stepping through the mirror to reach its
  reflection on the other side. This is "teleport locations" turned into
  the same idea the Echo System already explores: your reflection is
  real enough to use.
- **Lighting matches the echo ghost's glow.** Accent lights and the
  pool's emission all use `Color(0.55, 0.95, 1.0)` — the exact cyan
  `ghost_material.tres` uses — so the map's atmosphere and the echo
  ghost's presence read as the same visual language rather than two
  unrelated art choices.
- **Gameplay boundaries & collision.** A full perimeter wall ring
  (`MapKit.make_wall` ×4) plus every pillar/panel using proper collision
  shapes — standard MapKit pieces, nothing map-specific.
- **Navigation.** Baked after everything else is built
  (`EchoChamber._build_navigation`), covering the ground and correctly
  routing around every obstacle (see Testing below for how this was
  verified). Not currently consumed by any AI (this MVP has none, by
  design — see `PROJECT_STRUCTURE.md`), but the infrastructure is real
  and ready for whenever it is.

Reused, not recreated: Echo Chamber's walls use the **same**
`wall_material.tres` and pillars the same `rock_material.tres` that the
project's original arena used — proof the "reusable assets" requirement
means what it says, not just a label.

---

## Adding a new map (Dungeon / Laboratory / Castle, or anything else)

1. Add an entry to `MapManager.MAPS` (id, display name, scene path).
2. Create `Scenes/Maps/<Name>.tscn` — a bare `Node3D` root with a new
   `Scripts/Maps/<Name>.gd` script attached (copy `EchoChamber.tscn`'s
   two-line structure).
3. In `<Name>.gd`'s `_ready()`, call `MapKit` functions to build the
   map's ground, walls, obstacles, lights, and two spawn points
   (`hider_spawn` / `hunter_spawn` groups — required), optionally
   `TeleportPad` pairs, and finish with `MapKit.bake_navigation()`.
4. That's it — `MainMenu`'s map selector is built from
   `MapManager.get_map_ids()` automatically, so a new registry entry
   shows up in the UI with no scene/script changes there.

---

## Testing

### Map loads and contains everything required
1. Host a game (Echo Chamber is the only choice right now, so this is
   automatic). Confirm the arena appears with a central reflective pool,
   symmetric pillars/panels on both sides, and a full perimeter wall.
2. Confirm both players spawn at opposite ends (`hider_spawn` /
   `hunter_spawn`), not overlapping, not inside geometry.
3. Walk into a teleport pad; confirm you're moved to its linked pad
   instantly, and that walking into pads repeatedly doesn't
   instant-bounce you back and forth (the cooldown).
4. Try to leave the arena in any direction — confirm the perimeter walls
   stop you (gameplay boundaries).

### Map selection UI
1. On the main menu, confirm a "Map" dropdown is visible and defaults to
   "Echo Chamber".
2. Host a game — confirm the selection you made is the map that loads.
   (With only one map registered right now, this mostly confirms the
   dropdown is wired up correctly for when a second map exists.)
3. Join from a second window — confirm that window loads the **same**
   map the host is running, with no map-selection control needed on the
   joining side (only the host's choice matters — see Architecture).

### Reusable asset verification
Confirm `wall_material.tres` and `rock_material.tres` (already used
elsewhere in the project before this map existed) render identically in
Echo Chamber — same color/finish — proving they were genuinely reused,
not reauthored under a new name.

### Full regression (nothing broken by this pass)
This system was verified against a live two-peer headless ENet session:
map instantiated identically on both host and client, `NavigationMesh`
baked successfully (non-empty, collision-derived), both spawn groups
present, the mirror pool and both teleport pads found and correctly
cross-linked, and the teleport mechanic itself tested by moving a real
player body onto a pad and confirming it landed within centimeters of
the linked pad — all with zero engine errors during actual gameplay.
Run the full checklist in `TESTING_GUIDE.md` end to end afterward — this
pass changed where the arena comes from, not the round/echo/scoring
rules, so everything there should behave exactly as before.
