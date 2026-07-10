# Licenses

Everything the shipped game contains, where it came from, and under
what terms. Verified as part of the 1.0.0 release audit.

## Project code and documentation

All GDScript, scenes, procedural resources (materials, animation
library), synthesized audio, and documentation in this repository were
written for this project. **Copyright © the Echo Hunt authors.**

No explicit open-source license file has been added — that choice
belongs to the repository owner. Recommendation for a game jam: MIT
for the code (add a `LICENSE` file at the repo root). Until one is
added, default copyright applies (all rights reserved) — which is fine
for distributing builds on itch.io, but means others can't legally
reuse the code yet.

## Third-party content in the shipped game

| Component | Source | License | Where |
|---|---|---|---|
| Godot Engine 4.3 | godotengine.org | MIT | The engine embedded in every export (includes its own third-party components — see below) |
| Nature Kit (2.1), 10 models | Kenney — kenney.nl (downloaded via the OpenGameArt.org mirror) | **CC0 1.0** (public domain) | `Assets/Environment/NatureKit/*.glb` |

- The verbatim Kenney license text ships in the repo at
  `Assets/Environment/NatureKit/LICENSE.txt` and is included in
  exports' packed resources. CC0 requires no attribution; we credit
  Kenney anyway on the in-game **Credits** screen and the itch.io page
  (their license asks politely, and it costs nothing).
- Godot's MIT license and the licenses of the engine's bundled
  third-party libraries (FreeType, ENet, mbedTLS, etc.) are viewable
  in-engine under **Editor → About → Third-party Licenses** and at
  https://godotengine.org/license/. When distributing builds, itch.io
  page or a bundled text file should mention "Made with Godot Engine,
  © Juan Linietsky, Ariel Manzur and contributors, MIT license" —
  ITCH_IO_DEPLOYMENT.md includes this in the page template.

## Explicitly *not* in the game

- **No fonts were added** — text renders with Godot's built-in default
  font (covered by the engine's licensing).
- **No audio files** — every sound is synthesized at runtime by
  project code (`Scripts/Audio/SoundFactory.gd`).
- **No textures** — materials use flat colors and runtime-generated
  noise normal maps.
- The unused Nature Kit models kept in the repo for future maps
  (`rock_tallB`, `flower_purpleB`, `plant_bushLarge`,
  `tree_pineSmallA/C`) are the same CC0 pack.

## Trademark-ish notes

"Echo Hunt" as a name was coined for this project; no trademark search
has been performed — worth a quick check before any commercial release.
