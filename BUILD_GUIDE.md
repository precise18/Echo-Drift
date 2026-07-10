# Build Guide

How to go from a fresh clone to running the game, running its tests,
and producing the release binaries. For the export-preset details see
EXPORT_GUIDE.md; for publishing see ITCH_IO_DEPLOYMENT.md.

## Prerequisites

- **Godot 4.3 or newer, Standard build** (not .NET — the project is
  pure GDScript). https://godotengine.org/download
- ~200 MB disk for the project + import cache; ~1 GB more if you
  install export templates.
- No other dependencies: no addons, no packages, no asset downloads.

## Run from the editor

1. Open the Project Manager → **Import** → select `project.godot`.
2. First open triggers an asset import (a few seconds — ten small
   `.glb` files and the icon).
3. Press **F5**.

Two-instance local multiplayer: **Debug → Run Multiple Instances → 2**,
F5, host in one window, join `127.0.0.1` in the other, **Start Match**
from the host's lobby. Full flow in HOW_TO_RUN.md.

## Run from the command line

```bash
godot --path .            # run the game
godot --path . --editor   # open the editor
```

## Verify the project headlessly (CI-style)

The repo's convention after any change:

```bash
rm -rf .godot
godot --headless --path . --import    # catches parse/property errors
```

A clean run prints only the engine banner. For behavioral testing, the
project uses temporary two-process host/join sessions driven by a test
autoload — the pattern (and what it has caught) is documented in
TEST_PLAN.md.

## Production builds

Release builds are made headlessly with the presets in
`export_presets.cfg` (gitignored; copy `export_presets.example.cfg` to
`export_presets.cfg` if you don't have one):

```bash
# One-time: install export templates matching your Godot version
# (Editor → Manage Export Templates, or download the .tpz from
#  https://github.com/godotengine/godot/releases and unzip
#  templates/* into ~/.local/share/godot/export_templates/<version>/)

mkdir -p builds/linux builds/windows
godot --headless --path . --export-release "Linux"
godot --headless --path . --export-release "Windows"
```

Outputs (single-file, pack embedded):

- `builds/linux/echo-hunt-linux.x86_64` (~66 MB)
- `builds/windows/echo-hunt-windows.exe` (~84 MB)

Zip each for distribution:

```bash
zip -j builds/echo-hunt-1.0.0-linux.zip   builds/linux/echo-hunt-linux.x86_64
zip -j builds/echo-hunt-1.0.0-windows.zip builds/windows/echo-hunt-windows.exe
```

`builds/` is gitignored — binaries never enter the repo.

### Sanity-check a build

```bash
./builds/linux/echo-hunt-linux.x86_64 --headless --quit-after 120
```

Exit code 0 with no errors means the build boots, autoloads
initialize, and the menu constructs. Then do a real two-machine (or
two-instance) LAN smoke test per TEST_PLAN.md's release checklist.

### Version bumps

Update `config/version` in `project.godot`, add a CHANGELOG.md entry,
and use the version in the zip filenames.

## Gotchas seen in this environment (so you don't rediscover them)

- **Snap-confined shells** (e.g. a terminal inside a snap-packaged VS
  Code) remap `~/.local/share`, so Godot looks for export templates in
  the snap's private home and reports them missing. Fix:
  `env XDG_DATA_HOME=$HOME/.local/share godot --headless --export-release ...`
- **.NET/Mono Godot builds** crash headless if the `dotnet` runtime is
  absent. Use the Standard build for all headless work — this project
  has no C#.
