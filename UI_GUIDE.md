# UI Guide

The complete player-facing experience: every screen, how they connect,
the visual theme that ties them together, and the flow of a full match
from title screen to game over. Builds on the systems documented in
`GAMEPLAY_SYSTEMS.md`, `NETWORKING_REPORT.md`, and `AUDIO_SYSTEM.md`.

## The one place the look is defined

`Scripts/UI/UIKit.gd` is to UI what `MapKit` is to maps and
`SoundFactory` is to audio: a static toolkit that builds the shared
`Theme` procedurally (no `.tres` to drift out of sync) plus factories
for every widget. All screens compose UIKit pieces, which is what makes
the theme *actually* consistent rather than consistent-by-discipline:

- **Palette** — deep blue-black backgrounds, panels with a faint cyan
  border. The cyan accent is the *same* echo-cyan as the ghost, mirror
  pool, and teleport pads, so menus feel like the world; gold is
  reserved for results and warnings (it's the capture-burst color);
  hider blue vs hunter red-orange match the in-world player materials.
- **Widgets** — one stylebox family (rounded, flat, cyan hover border)
  for buttons/option/check controls; every button from
  `UIKit.make_button()` plays the UI hover/click sounds automatically,
  so interaction feel can't be forgotten on a new screen.
- Change a color or radius in UIKit's constants and every screen in the
  game follows.

## Screen map

```
                 ┌─────────────────────────────────────────┐
                 │                TITLE                    │
                 │   Host Game / Join Game / Settings /    │
                 │           Credits / Quit                │
                 └──┬────────┬───────────┬─────────┬───────┘
             ┌──────┘        │           │         │  (ESC returns to Title
             ▼               ▼           ▼         ▼   from any screen)
        HOST A MATCH    JOIN A MATCH  SETTINGS  CREDITS
        map selection   IP field
             │               │
             │ Start Hosting │ Join ──────────► (loading cover)
             ▼               ▼
        ═══════════════ GAME SCENE ═══════════════
             │
             ▼
        WARM-UP LOBBY  ◄────────────────── Rematch resets here-ish
        walk around; host presses Start Match
             │
             ▼
        ROUND BANNER ("ROUND N — You are the HUNTER")
             │
             ▼                                   ESC at any time:
        ROUND (HUD top bar: role / timer / score)  PAUSE MENU
             │                                   Resume / Settings /
             ▼                                   Leave Match / Quit
        ROUND TRANSITION ("Next round in 5...")
             │  ...first to 3 round wins...
             ▼
        GAME OVER (VICTORY / DEFEAT + final score)
          Rematch  ──► round 1 again at 0–0
          Leave to Menu ──► (loading cover) ──► TITLE
```

## The screens

### Main menu (`Scripts/UI/MainMenu.gd`)
A router over five screens built in code; only one visible at a time,
ESC always returns to the title. The title screen shows the game's
pitch line and, when relevant, a gold notice explaining why you're back
here ("Host disconnected.") — the practical stand-in for host migration.

### Host menu + map selection
Radio-style map list generated from `MapManager`'s registry (a future
map shows up here with zero menu changes), the selected map's
description, and the port players need. Start Hosting applies the
selection and enters the game under the loading cover.

### Join menu
IP field (pre-filled with the last IP you joined — persisted in
settings), Join button that disables while connecting, and inline
status for failures. Enter in the field submits.

### Lobby (in-game warm-up)
After hosting/joining you land *in the arena*, not in another menu:
walk around and learn the space while the lobby panel shows the map
name, player count, and match rules. The host's Start Match button
enables when both players are present; the client sees "waiting for the
host". Placing the lobby inside the game scene is deliberate — the
scene-load timing that Godot's spawner replication depends on stays
exactly as the networking layer was built and tested
(see NETWORKING_REPORT.md), and a warm-up room suits the game.

### Loading screen (`Scripts/Autoload/TransitionScreen.gd`)
A full-screen cover with a status line ("Entering Echo Chamber...",
"Joining match...", "Returning to menu...") that snaps opaque when a
scene change begins and fades out on its own once the new scene is up.
It *paints over* loads rather than gating them — joining clients must
load the game scene immediately for spawn replication (see
NETWORKING_REPORT.md), and the cover never delays that. It also ignores
mouse input, so it can never trap the game.

### Pause menu (ESC in game)
Resume / Settings / Leave Match / Quit Game over a dimmed backdrop,
with the honest caption that the match keeps running — in a two-player
network game there is no real pause. ESC toggles it; ESC inside its
settings page backs out one level first. Leaving cleanly disconnects
and returns to the title with no error banner (you chose to leave).

### Settings (`Scripts/UI/SettingsPanel.gd` + `GameSettings` autoload)
One panel used in *both* the main menu and the pause menu: volume
sliders for Master/Music/SFX/Ambience/UI (live preview while dragging,
applied on top of the mix baselines from `AudioManager.BUSES`), mouse
sensitivity, and fullscreen. Everything persists to
`user://settings.cfg` on change and is reapplied at startup.

### Credits
Kenney's Nature Kit (CC0, via OpenGameArt), the synthesized-audio note,
and Godot. Keeping the CC0 credit visible in-game is the polite half of
"crediting is not mandatory".

### Scoreboard
The persistent top bar during play: your role chip (colored hider-blue
or hunter-red), the round clock center (turns gold in the last 15
seconds — the hider is close to winning), and the running match score
(the same `Scoreboard` label class as before, now themed). The full
score also appears on every transition and the game-over screen.

### Round transition
Two beats, matching the audio's two beats (gong, then verdict jingle):
at round start, a banner fades in — "ROUND N", "You are the HUNTER",
and a one-line role hint — and fades itself out; at round end, a panel
names the round winner and how ("the echoes gave the hider away" /
"time ran out"), shows the score, and counts down "Next round in 5...".
The next round starts automatically — the server schedules it after
`RoundManager.NEXT_ROUND_DELAY`, and the HUD counts down the same
constant locally, so no countdown synchronization is needed. Roles swap
every round.

### Game over
A match is **first to 3 round wins** (`MatchStateManager.ROUNDS_TO_WIN`).
The final screen says VICTORY or DEFEAT *for you* (each peer resolves
it against its own role), shows the final score, and offers Rematch
(either player may request; scores reset to 0–0 and round 1 starts) or
Leave to Menu. ESC won't dismiss this screen — it asks for a decision.

## Mouse ownership — the one rule

`HUD._update_mouse()` is the single decision point: whenever any
interactive overlay is open (lobby, pause, game over) the cursor is
visible and `UIKit.block_mouse_capture` stops `PlayerController` from
re-grabbing it on window focus; when none is, the mouse is captured for
camera look. During the lobby the cursor is visible (the Start button
needs it) — you can still walk with WASD, you just can't mouse-look
until the round starts.

## What changed under the hood for this pass

- Rounds no longer auto-start when the second player connects; the
  host starts the match from the lobby
  (`RoundManager.start_match()`), and subsequent rounds start
  themselves after the transition delay.
- `request_restart` (manual "Play Again" after every round) became
  `request_rematch`, valid only from MATCH_OVER; between-round
  restarts are automatic now.
- The match-over decision needs no new networking: every peer already
  runs `record_round_result` from the same replicated `_end_round`
  RPC, so first-to-3 resolves identically everywhere.
- ESC moved from PlayerController (mouse toggle) to the pause menu.

## Known limitations

- **No pause in the physics sense** — by design; the pause screen says
  so rather than pretending.
- **Reconnect forgets the score** — a client that drops and rejoins
  mid-match recovers its role and the current round (see
  NETWORKING_REPORT.md) but rejoins with the score display at 0–0
  until the next round ends corrects it; a score resync on reconnect
  is a straightforward future addition.
- **Lobby has no chat or names** — players are "1 / 2"; identity
  barely matters at two players, but names would slot into the lobby
  panel naturally later.

## Testing

Verified with the established headless pattern: clean `--import`, then
a real two-process host/join session (temporary test autoload, removed
after) driving the complete flow — menu boot on both peers (all five
screens constructed), warm-up lobby confirmed, host `start_match()`,
three forced round ends with automatic between-round restarts and role
swaps, `MATCH_OVER` at 3–0 observed on **both** peers, rematch
requested **from the client**, and the rematch round confirmed active
at 0–0 on both sides — zero script errors end to end.
