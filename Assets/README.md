# Assets

The MVP uses **procedural placeholder geometry only** (Godot primitive
meshes — capsules, cylinders, boxes, spheres — with flat `StandardMaterial3D`
colors in `res://Materials/`). No external art files are required to run
the project, which keeps the repository small and license-clean while the
core loop is being validated. This also extends to audio (see
`Scripts/Echo/EchoAudio.gd`, which synthesizes its tone at runtime rather
than requiring a sound file) and maps (see `Scripts/Maps/MapKit.gd`,
which builds every map from shared procedural pieces — see
`MAP_SYSTEM.md`).

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
| `Assets/Environment/` | Kenney "Nature Kit" / "Prototype Kit" / "Dungeon Kit", Quaternius "Low Poly Nature" / "Dungeon" / "Castle" (replaces `MapKit`'s procedural meshes/materials theme-by-theme) |

Preferred sources, in priority order: **Kenney.nl**, **Quaternius**,
**Poly Pizza**, **OpenGameArt** (audio/SFX). Only use assets with licenses
that permit free redistribution in a game jam / itch.io release — do not
add copyrighted or unlicensed files.

## Multiple maps (post-MVP)

The map system (`MapManager` + `MapKit`, see `MAP_SYSTEM.md`) is already
built to take on more maps — adding one is a registry entry in
`MapManager.MAPS` plus a new `Scenes/Maps/<Name>.tscn` /
`Scripts/Maps/<Name>.gd` pair built from `MapKit` pieces, each exposing a
`hider_spawn` and `hunter_spawn` group `Marker3D`. The MVP intentionally
ships with only one map (`EchoChamber.tscn`) to keep scope small; Dungeon,
Laboratory, and Castle (per the original brief) are natural next additions
using the exact same pattern.
