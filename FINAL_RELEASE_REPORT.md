# Final Release Report — Echo Hunt 1.1.0 Release Candidate

The end-to-end account of turning the feature-complete project into a
Release Candidate: what was integrated, what was audited, what was
fixed, and exactly what remains between this working tree and a live
itch.io submission. No new gameplay mechanics were added at any point —
every change is integration of already-built teammate systems,
stabilization, or polish.

**Honesty note up front:** no Godot binary exists in the environment
this campaign ran in, so every "verified" below means *statically
verified against the actual source* (every file read, every reference
cross-checked against disk, every RPC traced) — except where a prior
documented live playtest already covered it. The final gate is the
20-minute live protocol in ITCH_UPLOAD_GUIDE.md §1 — run it once and
this RC becomes a release.

---

## What this release is

**Echo Hunt 1.1.0** — 2-player online hide-and-seek. The Hider's
movement is recorded and replayed 10 seconds later as a glowing,
audible echo ghost; the Hunter tracks the past to find the present.
Room-code matchmaking over a WebRTC relay (no port forwarding), two
maps, six-slot character skin system, first-to-3 match structure.

### Teammate systems integrated this release

| System | What it was | What integration took |
|---|---|---|
| **Character skins** (`SkinRegistry.gd`, `CharacterRig.gd`, `Assets/Characters/Skins/`) | Complete but wired to nothing; registry listed 6 skins with 1 model on disk | Availability-filtered the registry (only skins whose model exists are offered/valid); persisted the choice (`GameSettings.skin_id`); title-screen picker; replicated via the existing name-registration RPC with server-side validation; `PlayerController` swaps the stock capsule for the `CharacterRig` on every peer (late-sync safe, one-shot), routes animation through the rig's abstract states, keeps facing/lean from `AnimationComponent`, and stops painting role colors over skins (per the registry's own identity-not-role rule) |
| **Forest Arena map** (`Scenes/Maps/Arena.tscn`) | Complete hand-built map, orphaned because its four materials were never committed (flagged as a QA finding) | Created the four materials (`ground`, `tree_trunk`, `tree_leaves`, `cabin`), registered it in `MapManager.MAPS` — the host-screen map picker and client sync are registry-driven, so it's selectable with no further changes. Its spawn markers were already in the correct `hider_spawn`/`hunter_spawn` groups |
| **Echo minimap** (`Scripts/UI/EchoMinimap.gd`) | Bottom-left radar, built earlier as an explicit preview | Promoted to shipped: docs/comments updated, limitations recorded (north-up, single echo — KNOWN_LIMITATIONS.md #4) |

Compatibility choices worth knowing: echoes record **abstract** states
for skinned rigs and `EchoGhost` resolves recorded clip names by
case-insensitive substring, so any skin's history replays on the
ghost's own animation library; a build with zero skin models present
falls back to the stock capsule everywhere automatically.

---

## The ten steps

### Step 1 — Project audit ✅
Every script (36), scene (8), autoload (9), material, and resource
reviewed across this campaign; full details in `FINAL_QA_REPORT.md`,
`RELEASE_CANDIDATE_REPORT.md`, `PLAYER_AUTHORITY_REPORT.md`. Final
sweep after integration: **34 unique resource paths referenced by
scripts and scenes, zero missing; no duplicate `class_name`s; no
broken scene paths; no stray debug prints outside the two documented
telemetry systems.** The one previously-broken scene (Arena) is now
integrated rather than orphaned.

### Step 2 — Build verification ⚠️ (one human step remains)
Static equivalent done: all cross-file references, signatures, and
signal wirings check out; no parser-level red flags found by review.
**Actually compiling requires the editor** — open the project once
(this also imports `Ninja_Male.fbx` and the new materials for export)
and confirm a clean Output panel. This is item 1 of the live protocol.

### Step 3 — End-to-end journey ✅ (code-traced) / ⚠️ (live run pending)
Menu → Host (room created, code copied) → Join (code) → Lobby (names,
count, Start gating) → map selection sync → `Main.tscn` → spawn +
authority (both paths) → movement → role assignment → echo record →
echo playback (+VFX, minimap) → teleport → capture → round end → score
→ next round (roles swapped) → match end → rematch → leave to menu:
every transition traced through the actual signal/RPC chain; every gap
found along the way was fixed (see Fixed list below).

### Step 4 — Multiplayer ✅
Authority matrix (who owns/input/camera/RPC per node per peer) verified
end-to-end in `PLAYER_AUTHORITY_REPORT.md`, including sequence diagrams;
re-checked after skin integration (skins never touch authority,
replication config, or input). Names, skins, score, roles, and round
state all survive reconnect inside the 20s grace window. Disconnect
paths (host quit, client quit, kick, grace expiry) each traced to a
clean state reset on every surviving peer.

### Step 5 — Performance ✅
Prior optimization pass retained (shadow splits, cached lookups,
worker-thread audio synthesis, zero-allocation HUD updates). New
systems audited for cost: skins are load-cached and swapped once per
session; all new particles are one-shot self-freeing or toggled; the
minimap is ~6 2D draw calls; the ghost shader is textureless ALU work
(see ECHO_VISUAL_GUIDE.md's cost table). No per-frame allocations
added.

### Step 6 — UI ✅
Every button, screen, popup, label, and transition enumerated and
wired-checked (`UI_STATE_MACHINE.md` + this campaign's passes). No
stuck states found: every overlay has an exit, connection failures
surface on whichever screen is alive (menu or lobby), the loading
cover fades on a timer and ignores input by design, and ESC behavior
is guarded on the game-over screen.

### Step 7 — Theme ✅
Judged and polished in `THEME_POLISH_REPORT.md`: the mechanic *derives*
from Echoes and Reflection (recorded past as gameplay; a bilaterally
mirrored arena). The echo reads as supernatural in under a second
(ECHO_VISUAL_GUIDE.md's twelve effects: transparency, cyan glow,
distortion, spawn pulse, dissolve, ripples, timeline label/ring,
shimmer, vibrato hum). UI carries the motif: mirrored title, mirrored
VICTORY/DEFEAT, echoed click sounds.

### Step 8 — Export ✅ (config) / ⚠️ (fresh export pending)
`export_presets.cfg`: Linux + Windows presets, embedded pack,
`product_name`/`file_description` set, docs excluded from the pack.
Icon (`icon.svg`) wired in `project.godot`; version stamped **1.1.0**
matching CHANGELOG. Removed `check_webrtc.gd` (leftover debug script
that would have shipped). Note for the exporter: Windows preset's
`application/icon` is empty — the executable uses the default Godot
icon unless an `.ico` is added; cosmetic, page icon matters more on
itch.

### Step 9 — Documentation ✅
Generated/updated this release: `FINAL_RELEASE_REPORT.md` (this file),
`FINAL_QA_REPORT.md` (updated with the 1.1.0 addendum),
`KNOWN_LIMITATIONS.md` (supersedes KNOWN_ISSUES.md),
`EXPORT_GUIDE.md` (web-build rationale corrected for WebRTC),
`ITCH_UPLOAD_GUIDE.md` (supersedes the LAN-era deployment doc),
`CHANGELOG.md` (1.1.0 entry).

### Step 10 — Release checklist

Legend: ✅ = verified in code this campaign (plus prior documented live
testing where noted) · 🔲 = requires the one live session
(ITCH_UPLOAD_GUIDE.md §1) to flip.

| Item | Static | Live |
|---|---|---|
| Main Menu | ✅ | 🔲 |
| Host (room code) | ✅ (+ prior live relay verification) | 🔲 |
| Join (room code) | ✅ (+ prior live relay verification) | 🔲 |
| Lobby (names, count, start gating) | ✅ | 🔲 |
| Spawn (+ authority, both peers) | ✅ | 🔲 |
| Movement (incl. S key, sensitivity) | ✅ | 🔲 |
| Camera (own-body only, sensitivity applied) | ✅ | 🔲 |
| Echoes (record, replay, VFX, minimap) | ✅ | 🔲 |
| Audio (buses, stings, positional, echo variants) | ✅ | 🔲 |
| Teleport (pads, both maps' layouts) | ✅ | 🔲 |
| Capture / Win / Lose | ✅ | 🔲 |
| Match end / Scoreboard | ✅ | 🔲 |
| Player names (tags, sync) | ✅ | 🔲 |
| Character skins (pick, sync, swap) | ✅ | 🔲 |
| Round restart (roles swap) | ✅ | 🔲 |
| Return to menu (leave/quit paths) | ✅ | 🔲 |
| Export presets + metadata | ✅ | 🔲 (fresh export) |
| No Critical bugs open | ✅ | — |

**Status: RELEASE CANDIDATE.** Every critical system is verified at
the source level and no Critical or High issue is open. The project is
one editor-import + one two-instance live protocol away from
**COMPLETE** — that protocol, and the upload that follows it, are fully
scripted in ITCH_UPLOAD_GUIDE.md so anyone on the team can execute it
in ~20 minutes.

---

## Everything fixed during this campaign

1. Reconnect spawn race → peer permanently unable to move (Critical).
2. Grace-expiry state reset not broadcast → surviving peer desynced
   forever (Critical).
3. Dead `move_backward` action → S key never worked (High).
4. Mouse sensitivity setting never applied (High).
5. Reconnect scoreboard stuck at 0–0 (High).
6. Echo recorder never found the real AnimationPlayer → ghosts never
   animated (High).
7. Camera stolen / stuck first-person on join (fixed pre-campaign,
   re-verified; authority re-application on every spawn path).
8. Arena map orphaned by four missing materials (integrated).
9. Silent authority-assignment failure modes → now loudly warned.
10. Leftover debug script shipping in the pack (removed).

## Open items (all documented, none blocking)

See `KNOWN_LIMITATIONS.md` — 16 entries, the notable ones: one skin
model shipped (five more are drop-in), relay cold-start latency,
puppet facing rotation needs a live look, debug telemetry deliberately
kept for the jam, no macOS/web.
