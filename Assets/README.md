# Assets

The MVP uses **procedural placeholder geometry only** (Godot primitive
meshes — capsules, cylinders, boxes, spheres — with flat `StandardMaterial3D`
colors in `res://Materials/`). No external art files are required to run
the project, which keeps the repository small and license-clean while the
core loop is being validated.

## Art direction target

Stylized low-poly, high-readability, toy-like — closer to *Among Us* /
*Human Fall Flat* / *Fall Guys* than anything realistic. Flat, saturated
colors; simple silhouettes; no textures needed to read the scene.

## Where post-MVP art should go

When the project moves from MVP into full jam production, replace the
placeholders with free/openly-licensed packs and drop them here:

| Folder | Contents |
|---|---|
| `Assets/Characters/` | Kenney "Toon Characters" / Quaternius character packs (replaces `Scenes/Player/Player.tscn`'s capsule mesh + adds a real skeleton/animations for `AnimPlayer`) |
| `Assets/Environment/` | Kenney "Nature Kit" / "Prototype Kit" / "Dungeon Kit", Quaternius "Low Poly Nature" / "Dungeon" / "Castle" (replaces `Scenes/Maps/Arena.tscn` primitives) |

Preferred sources, in priority order: **Kenney.nl**, **Quaternius**,
**Poly Pizza**, **OpenGameArt** (audio/SFX). Only use assets with licenses
that permit free redistribution in a game jam / itch.io release — do not
add copyrighted or unlicensed files.

## Multiple maps (post-MVP)

`Scenes/Maps/` is intentionally a folder, not a single hardcoded path, so
additional arenas (Forest / Dungeon / Laboratory / Castle) can be added as
sibling `.tscn` files later. They should each expose a `hider_spawn` and
`hunter_spawn` group `Marker3D`, exactly like `Arena.tscn`, so they drop
into `Main.tscn` without any script changes. The MVP intentionally ships
with only one arena (`Arena.tscn`, forest-themed) to keep scope small.
