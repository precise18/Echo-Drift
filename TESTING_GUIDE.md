# Testing Guide

Manual verification checklist for every MVP feature. Godot has no
automated test runner configured for this MVP (out of scope — see
`PROJECT_STRUCTURE.md`), so testing means running the game and checking
each item below by hand. Run two instances for anything multiplayer (see
`HOW_TO_RUN.md`).

---

## 1. Host a game

**Steps**
1. Press F5. Click **Host Game** on the main menu.

**Verify**
- [ ] Status text briefly shows "Starting host...".
- [ ] The screen transitions into the 3D arena within ~1 second.
- [ ] No errors appear in the Godot debugger Output panel.

## 2. Join a game

**Steps**
1. With a host already running (test 1), launch a second instance.
2. Enter `127.0.0.1` in the IP field, click **Join Game**.

**Verify**
- [ ] Status text shows "Connecting...".
- [ ] The joining window transitions into the same arena.
- [ ] Both windows now show two characters in the arena (one per window's
      own view).
- [ ] If you enter a wrong/unreachable IP, the status label shows a
      connection-failed message instead of hanging forever.

## 3. Spawn into the arena

**Verify**
- [ ] Both players appear standing on the ground, not falling through it
      or spawning inside a wall/obstacle.
- [ ] Each window's camera starts behind its *own* character (not the
      other player's).
- [ ] The two spawn points are on opposite sides of the arena.

## 4. Move around (third-person movement, jump, sprint, camera)

**Steps**
1. In either window, move the mouse and press WASD.

**Verify**
- [ ] Mouse movement rotates the camera/look direction smoothly.
- [ ] W/A/S/D moves the character relative to the camera, not fixed
      world axes.
- [ ] The character visibly turns to face its movement direction.
- [ ] Holding **Shift** noticeably increases movement speed (sprint).
- [ ] Pressing **Space** makes the character jump; it comes back down
      and doesn't get stuck floating or clip through the ground.
- [ ] Walking/running plays a subtle bob animation; standing still plays
      idle (placeholder animation, not a full rig — just confirm the
      three states are visually distinct).
- [ ] Moving in window 1 shows that character moving in window 2's view
      too (and vice versa), without major stutter on localhost.

## 5. Hide (obstacles block sightlines)

**Verify**
- [ ] The Hider can stand behind a tree, rock, bush, or the cabin such
      that the Hunter's camera can no longer see their character model.
- [ ] The Hider cannot walk through walls or obstacles (collision
      works).
- [ ] The Hider cannot leave the arena through the perimeter walls.

## 6. Echo system records movement / ghost appears / replays it

**Steps**
1. Start a round. Immediately note the time and start moving the Hider
   in a distinctive path (e.g. a loop around one tree).
2. Watch both windows for ~10-12 seconds.

**Verify**
- [ ] No echo ghost is visible for the first ~10 seconds of the round
      (buffer still filling — this is intentional, not a bug).
- [ ] After ~10 seconds, a translucent cyan capsule ("echo ghost")
      appears and starts moving.
- [ ] The ghost's path matches the Hider's path from about 10 seconds
      earlier (compare the loop you walked to what the ghost repeats).
- [ ] The ghost has no collision — walking into it does nothing, and it
      passes through walls/obstacles the same way a recorded path would.
- [ ] The ghost is visibly transparent/glowing, clearly not a real
      player.
- [ ] The ghost keeps updating continuously for the rest of the round
      (it's a rolling 10-second delay, not a one-shot replay).

## 7. Hunter tracks the echo and finds the hider

**Steps**
1. As the Hunter, follow the echo ghost's trail rather than looking
   directly for the Hider.

**Verify**
- [ ] Following the ghost's recent path leads generally toward where the
      Hider actually is (accounting for the 10s delay, the Hider may have
      moved on).
- [ ] Walking the Hunter's character within about a body-length of the
      Hider triggers a round end in **both** windows within a frame or
      two of each other.

## 8. Round timer

**Verify**
- [ ] The HUD timer counts down from the round start value (90s) once
      the round begins.
- [ ] If the Hunter never catches the Hider, the timer reaches `00:00`
      and the round ends automatically with the Hider declared the
      winner.

## 9. One hunter, one hider, round restart, score

**Steps**
1. Let a round end (either by catch or timeout).
2. Click **Play Again** in either window.

**Verify**
- [ ] A "Round Over" panel appears in both windows with a winner message
      and a **Play Again** button.
- [ ] The score line (`Hunter X — Y Hider`) updates correctly after the
      round and matches in both windows.
- [ ] Clicking **Play Again** in *either* window restarts the round for
      *both* windows (only one click needed, from any player).
- [ ] After restart, both players are teleported back to spawn points,
      the timer resets to 90s, and the echo ghost disappears until a new
      10-second buffer builds up.
- [ ] Roles swap on restart — whoever was Hunter is now Hider and vice
      versa (check the "You are: HIDER/HUNTER" label in each window).

## 10. Full loop, end to end

**Steps**
1. From a cold start: host, join, play a full round to completion,
   restart, and play a second round.

**Verify**
- [ ] Every step above works back-to-back with no crashes, no stuck
      states, and no need to restart the application between rounds.
