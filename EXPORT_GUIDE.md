# Export Guide

The export configuration itself: what the presets contain, why, and
platform-by-platform status. BUILD_GUIDE.md covers *running* the
exports; this explains the decisions inside them.

## Presets

`export_presets.cfg` is **gitignored** (Godot convention — the file can
hold signing credentials on some platforms). A clean, secrets-free
reference copy is committed as **`export_presets.example.cfg`**; copy
it into place to export:

```bash
cp export_presets.example.cfg export_presets.cfg
```

Two presets, verified for 1.0.0:

### Preset 0 — "Linux" (Linux/X11, x86_64)
### Preset 1 — "Windows" (Windows Desktop, x86_64)

Shared choices, and why:

| Setting | Value | Why |
|---|---|---|
| `binary_format/embed_pck` | `true` | One file to distribute — no `.pck` to lose. itch.io players just unzip and run |
| `export_filter` | `all_resources` | The project is small; excluding by hand risks missing a preload |
| `exclude_filter` | `*.md, __*__/*, export_presets.example.cfg` | Documentation and any test scaffolding stay out of shipped packs |
| `encrypt_pck` | `false` | A CC0-and-your-own-code jam game has nothing to hide; encryption complicates builds for zero benefit |
| `codesign/enable` (Windows) | `false` | No signing cert. Windows SmartScreen may warn on first run — normal for unsigned jam games; note it on the itch page |
| `texture_format` | bptc + s3tc | Desktop targets only |

Debug builds: use `--export-debug` instead of `--export-release` to get
console output and debug asserts in a build.

## Platform status

| Platform | Status | Notes |
|---|---|---|
| **Linux x86_64** | ✅ Shipped | Boot-verified headless (`--quit-after`, exit 0, clean log) |
| **Windows x86_64** | ✅ Shipped | Exported and structurally verified (valid PE32+). Run-verified only via the identical Linux pack — do one real Windows smoke test before the jam page goes public |
| **macOS** | ❌ Not shipped | Needs Apple signing/notarization not available here. No platform-specific code exists; a Mac owner can add the preset and export from the editor |
| **Web (HTML5)** | ❌ Deliberately skipped | Browsers cannot open UDP sockets; ENet-based multiplayer cannot work in a web build. Shipping a single-player shell would misrepresent the game |
| **Android/iOS** | ❌ Out of scope | No touch controls; desktop keyboard/mouse game |

## Export templates

Templates must match the exporting editor's version exactly
(`4.3.stable` for the shipped builds).

- Editor UI: **Editor → Manage Export Templates → Download and Install**.
- Manual: download `Godot_v4.3-stable_export_templates.tpz` from
  https://github.com/godotengine/godot/releases/tag/4.3-stable, then
  unzip the needed files into
  `~/.local/share/godot/export_templates/4.3.stable/`
  (only `linux_release.x86_64` and `windows_release_x86_64.exe` are
  needed for these two presets — ~150 MB instead of the full 1 GB).

## What's inside a shipped build

- The Godot 4.3 runtime for that platform (MIT — see LICENSES.md).
- The project pack: all scripts (compiled GDScript tokens), scenes,
  the ten CC0 `.glb` props + `LICENSE.txt`, materials, the animation
  library, and `project.binary` (compiled settings). Markdown docs are
  excluded by the preset filter.
- Nothing is downloaded at runtime; the game makes no network
  connections except the ENet session the player starts.

## Reproducibility

Anyone with Godot 4.3-stable and this repo produces functionally
identical builds: no private keys, no environment-specific paths, no
build-time codegen. The whole pipeline is the two commands in
BUILD_GUIDE.md.
