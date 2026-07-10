# Assets

Most of the game is still **procedural geometry** (Godot primitive meshes
— capsules, cylinders, boxes, spheres — with `StandardMaterial3D`s in
`res://Materials/`, several now with a procedural noise-based normal map
rather than a flat color — see `ART_DIRECTION.md`). This also extends to
audio (see `AUDIO_SYSTEM.md` — every sound in the game, from footsteps to
the music bed, is synthesized at runtime by `Scripts/Audio/SoundFactory.gd`
rather than requiring sound files) and maps (see
`Scripts/Maps/MapKit.gd`, which builds every map from shared procedural
pieces — see `MAP_SYSTEM.md`).

`Assets/Environment/NatureKit/` is the one place real downloaded assets
now live — 10 small CC0 low-poly props (rocks, flowers, a bush) used as
environment dressing on the Echo Chamber map. See `ART_DIRECTION.md` for
what was added, where it came from, and why. Everything else (characters,
the mirror pool, teleport pads, walls, floor, pillars) is still
procedural — that approach already matched the art direction target
below, so it wasn't replaced.

## Art direction target

Stylized low-poly, high-readability, toy-like — closer to *Among Us* /
*Human Fall Flat* / *Fall Guys* than anything realistic. Flat, saturated
colors; simple silhouettes; no textures needed to read the scene.

## Where more post-MVP art should go

Further replacing placeholders with free/openly-licensed packs:

| Folder | Contents |
|---|---|
| `Assets/Characters/` | Kenney "Toon Characters" / Quaternius character packs (replaces `Scenes/Player/Player.tscn`'s capsule mesh + adds a real skeleton/animations for `AnimPlayer` — not done yet; the capsule's animations were improved procedurally instead, see `ART_DIRECTION.md`) |
| `Assets/Environment/NatureKit/` | Kenney "Nature Kit" (done — see `ART_DIRECTION.md`) |
| `Assets/Environment/` (other) | Kenney "Prototype Kit" / "Dungeon Kit", Quaternius "Dungeon" / "Castle" if more maps are added |

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
