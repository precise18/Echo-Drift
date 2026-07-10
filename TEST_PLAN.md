# Test Plan

What gets tested, how, and when — both the automated headless pattern
used throughout development and the manual pass required before a
release. Supersedes the MVP-era TESTING_GUIDE.md (kept as a pointer).

## 1. Automated: the headless two-process pattern

Every feature pass in this project was verified the same way, and
contributions should be too:

**Level 1 — parse/property check** (after every change):
```bash
rm -rf .godot && godot --headless --path . --import
```
Clean run = engine banner only.

**Level 2 — probe scripts** (for pure logic): `SceneTree`-extending
scripts run via `--script`, e.g. the EchoRecorder correctness probe
(hand-computed interpolation/clamp cases) in the optimization pass.
Note: scripts referencing autoload globals don't compile in `--script`
mode — probes work for kit/logic classes only.

**Level 3 — real two-process session** (for gameplay/network/UI flow):
a temporary autoload drives a genuine host + join pair:

```gdscript
# __test__/TestDriver.gd — register temporarily in [autoload], run:
#   godot --headless --path . -- --host-test   (process 1)
#   godot --headless --path . -- --join-test   (process 2)
extends Node
func _ready() -> void:
    var args := OS.get_cmdline_user_args()
    if "--host-test" in args:
        get_tree().create_timer(1.0).timeout.connect(NetworkManager.host_game)
    elif "--join-test" in args:
        get_tree().create_timer(2.0).timeout.connect(
            func() -> void: NetworkManager.join_game("127.0.0.1"))
# ...then assert on RoundManager/MatchStateManager state per frame,
# print PASS/FAIL, quit(0/1). Delete before committing.
```

This pattern has caught real bugs at every level of the stack: a
MultiplayerSpawner replication-ordering race, `is_server()` error spam
with a null peer, a phantom-capture race at round start, and a
freed-instance crash in a node cache. **Ignore two artifacts** of
headless runs: dummy-renderer `mesh_get_surface_count` warnings and
`ObjectDB instances leaked` on force-quit.

### What's already covered by past automated runs

- Full match flow on both peers: lobby → host `start_match()` → 3
  rounds with auto-transitions and role swaps → MATCH_OVER →
  client-requested rematch at 0–0.
- Worker-thread audio synthesis delivering playing music/wind on both
  peers; all buses present; footsteps firing from replicated movement.
- EchoRecorder lookup correctness (7 hand-computed cases).
- Production Linux build boot (`--headless --quit-after 120`, exit 0).

## 2. Manual test matrix (run before each release)

Two instances on one machine unless stated. ☐ = check.

### Menus & settings
- ☐ Title → each screen and back (buttons + ESC); hover/click sounds.
- ☐ Settings: drag each volume slider (audible change), toggle
  fullscreen, adjust sensitivity → quit the game entirely → relaunch →
  all values persisted.
- ☐ Join screen: wrong IP → "Connection failed" appears, Join button
  re-enables; last-used IP is pre-filled next launch.

### Session & lobby
- ☐ Host → warm-up lobby shows map name, "Players: 1 / 2", Start
  Match disabled.
- ☐ Second player joins → "2 / 2", Start Match enables; client sees
  "waiting for host".
- ☐ Both can walk (WASD) in the lobby; cursor is visible.
- ☐ Loading cover appears on host/join and fades out.

### Round flow
- ☐ Start Match → banner ("ROUND 1 — You are the HUNTER/HIDER"),
  role chip colored, mouse captured, round-start sting.
- ☐ Roles are host=Hider, joiner=Hunter in round 1; swap each round.
- ☐ Echo ghost appears ~10 s in, replays the Hider's path with trail
  particles, hollow footsteps, and hum; disappears at round end.
- ☐ Capture: Hunter touches Hider → gold burst at the Hider, gong then
  personal victory/defeat jingles (opposite on the two windows),
  transition panel with score and 5-second countdown → next round
  starts alone.
- ☐ Timeout: let the clock run out → Hider wins the round; clock turns
  gold under 15 s.
- ☐ No capture possible in the first ~1.5 s of a round (stand on
  spawn overlap — grace period).
- ☐ Teleport pads: whoosh + burst at both ends, on both windows;
  1-second cooldown (no ping-pong).

### Match end
- ☐ First to 3 wins → Game Over (VICTORY on winner's screen, DEFEAT on
  loser's), final score, ESC does *not* dismiss it.
- ☐ Rematch from the *losing* window → both reset to 0–0, round 1
  banner.
- ☐ Leave to Menu → menu, no error banner, mouse works.

### Pause & resilience
- ☐ ESC in-round → pause overlay; match keeps running (timer visibly
  ticks); Settings inside pause works; ESC in pause-settings backs out
  one level; Resume recaptures the mouse.
- ☐ Alt-tab out and back while paused → cursor still free (not stolen
  by recapture).
- ☐ Kill the client mid-round → host HUD shows the 20 s reconnect
  countdown; relaunch client and rejoin within it → same role,
  round continues (score display on the rejoiner lags — known issue
  #2). Let it expire instead → host returns to lobby cleanly.
- ☐ Kill the host mid-round → client lands on the title screen with
  "Host disconnected."

### Cross-machine (once per release, real LAN)
- ☐ Two PCs on one network: host on A, join from B via A's IP; play
  a full match. This is the release gate — `127.0.0.1` testing can't
  catch firewall/interface issues.

## 3. Release checklist

- ☐ Level-1 import check clean at the release commit.
- ☐ Full manual matrix above on the *exported* builds (not F5).
- ☐ ITCH_IO_DEPLOYMENT.md checklist (builds, page, credits).
- ☐ KNOWN_ISSUES.md re-read — anything new discovered goes in before
  tagging, not after.
