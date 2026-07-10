# Contributing

How to work on Echo Hunt without fighting it. The codebase has strong
conventions — following them is most of what a good contribution needs.

## The one architectural idea

Everything generated, one owner per concern. Before adding a file, ask
which existing "kit" or manager owns your concern:

| You want to change... | Go to |
|---|---|
| Map geometry / a new map | `Scripts/Maps/MapKit.gd` + a new map script/scene, registered in `MapManager.MAPS` |
| A sound | `Scripts/Audio/SoundFactory.gd` (one function per sound) |
| UI look & feel | `Scripts/UI/UIKit.gd` (theme constants + widget factories) |
| Round/match rules | `RoundManager` / `MatchStateManager` / `WinConditions` |
| Connection lifecycle | `NetworkManager` (and nothing else touches ENet) |
| Echo behavior | `Scripts/Echo/` (recorder / ghost / system) |

Autoloads hold session state; `class_name` static kits hold pure
logic/builders. Don't add an autoload for something a static class can
do.

## Code style

- **GDScript, tabs, typed** (`:=` inference where the type is obvious,
  explicit types on parameters/returns).
- Every file starts with a `##` doc comment stating its **single
  responsibility** — read a few existing files first; match their
  voice.
- Comments explain **constraints and why**, not what the next line
  does. If a decision looks odd (e.g. "deliberately untyped",
  "call_local on purpose"), the comment says why — keep that standard.
- No `print()` in committed code. The release audit greps for it.
- Signals for cross-system communication; direct calls within a
  system.

## Multiplayer rules (the ones that bite)

1. **Only the server decides outcomes**; everyone else receives
   reliable RPCs. Look at `RoundManager._end_round` for the pattern.
2. **Derive, don't replicate.** Footsteps, bursts, stings, match-over
   are all computed locally from already-replicated state. If your
   feature "needs a new RPC", check whether every peer could compute
   it from what it already knows.
3. **Never gate scene loading on your own sync message** — spawn
   replication needs `Main.tscn`'s `MultiplayerSpawner` to exist
   early. See NETWORKING_REPORT.md before touching the join flow.
4. Peer ids are random 32-bit ints (never assume 1 and 2 — the
   *server* is always 1).

## Testing (non-negotiable)

After any change:

```bash
rm -rf .godot && godot --headless --path . --import
```

must print only the engine banner. For anything touching gameplay,
networking, or UI flow, run a two-process regression: a temporary test
autoload that hosts/joins and drives the flow (the pattern is in
TEST_PLAN.md, including a reusable skeleton). This pattern has caught
a phantom-capture race, a freed-instance crash, and a replication
ordering bug — it earns its keep. Delete the harness (and its
`project.godot` autoload line) before committing.

Manual test checklists live in TEST_PLAN.md; run the relevant section
for what you changed.

## Commits & PRs

- One coherent change per commit; message explains **why**, present
  tense ("Add X because Y" — read `git log` for the house style).
- Don't commit: `.godot/`, `builds/`, `export_presets.cfg` (the
  example copy is the committed one), test harnesses.
- If your change alters player-facing behavior, update the matching
  doc (UI_GUIDE, GAMEPLAY_SYSTEMS, etc.) in the same commit — stale
  docs are treated as bugs here.
- Update CHANGELOG.md under an "Unreleased" heading.

## Good first contributions

Ranked by value-to-effort, from KNOWN_ISSUES.md:

1. Score resync on reconnect (one RPC field — issue #2).
2. A second map (the whole point of MapKit/MapManager — registry
   entry + one script/scene; MAP_SYSTEM.md walks through it).
3. Rigged low-poly characters replacing the capsules
   (ART_DIRECTION.md lists sources; keep CC0/CC-BY only, update
   LICENSES.md).
4. A tension music layer for the last 20 seconds
   (`SoundFactory` + a crossfade in `AudioManager`).
