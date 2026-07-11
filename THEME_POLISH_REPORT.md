# Theme Polish Report

A game-jam-judge pass over Echo Hunt against its stated theme,
**Echoes and Reflection**. Every system was evaluated for how strongly
it reinforces the theme, three small, low-risk improvements were
implemented (all fit comfortably inside a one-hour budget — see
"What was implemented"), and everything larger is written up as a
recommendation, not attempted, per the "only implement what fits in an
hour" constraint. **No core gameplay changed** — every item here is
visual, audio, or UI presentation.

---

## Overall impression, as a judge

Echo Hunt doesn't just *reference* its theme, it's built the mechanic
*out of* it: the Hider's echo is a literal replay of the recent past
(Echoes), and the arena is bilaterally mirrored with a centerpiece pool
and linked teleport pads that are a literal mirror to walk through
(Reflection). That's a rare, strong fit — most jam entries bolt a theme
onto an unrelated mechanic after the fact; this one derives the
mechanic from the theme. The echo ghost itself (see
[`ECHO_VISUAL_GUIDE.md`](ECHO_VISUAL_GUIDE.md), a prior pass) is
already doing a lot of theme work: transparency, cyan glow, a
distortion shader, spawn/dissolve materialize-and-fade effects, a
footstep ripple, a replay-timeline label, and a reflection shimmer.
That system is the strongest theme touchpoint in the game and needed
no further work this pass.

The gap, evaluated area by area below, is that the *mechanic* fully
commits to the theme but the *presentation around it* — menus, HUD
chrome, transition screens — mostly doesn't reference "reflection" at
all yet. That's exactly the kind of gap a one-hour polish pass can
close a little of and should document the rest of.

---

## Evaluation by focus area

### Visual feedback — Strong
Role material swap (Hider/Hunter tint), capture burst, teleport
whoosh+burst, and the full echo VFX suite already give clear, instant
visual feedback for every state change that matters. No gap found.

### Audio feedback — Strong, now slightly stronger
Footsteps (including a distinct reverberant echo variant so a Hunter
can tell real steps from echo steps by ear), positional echo hum,
round/victory/defeat stings, and now (this pass) a literal audio echo
on every UI click — see "What was implemented" below.

### Lighting — Strong
`EchoChamber._build_environment()` already does real work here: cyan
fog tying the whole arena's atmosphere to the echo color, glow/bloom
tuned specifically so every emissive surface (pool, pads, ghost, accent
lights) reads as actually glowing, and a saturation/contrast lift for a
stylized rather than washed-out look. This is genuinely above the bar
for a jam entry's lighting pass. No changes made or needed.

### UI — Adequate, now touched
Clean, consistent, single-theme (`UIKit.theme()`), but before this pass
carried **zero** reflection/echo visual language of its own — every
menu screen, panel, and label used the same generic title/button/panel
look regardless of what game this UI belongs to. This was the clearest
gap in the whole review. Addressed for two high-visibility spots this
pass (see below); the rest is written up as a recommendation.

### Ghost readability — Strong (already addressed in a prior pass)
See `ECHO_VISUAL_GUIDE.md` in full — transparency, glow, distortion,
spawn pulse, dissolve, footstep ripple, timeline label, shimmer. A
player can tell "that's an echo" from across the arena. Nothing to add
here without re-opening work already done and verified.

### Reflection motif — Present in-world, absent in UI (until this pass)
The mirror pool, mirror panels, and the bilaterally-symmetric map
layout are a strong, literal "reflection" statement in the *world*.
The *UI* had none of this language anywhere. This pass adds a genuine
mirrored-reflection effect (not just a color reference) to two places —
see below.

### Mirror motif — Present in-world, strong
The map's X=0 mirror plane, matched spawn points, and linked teleport
pads ("stepping into one is like walking through a mirror to the
other" — `EchoChamber.gd`'s own doc comment) are a clean, legible
mirror motif already. No gap found worth spending the hour on; ideas
for going further are in "Recommended, not implemented."

### Color palette — Strong, consistent
Cyan (`ECHO_CYAN` / `UIKit.COLOR_ACCENT`) is used consistently for
every echo/reflection-adjacent element: the ghost, the mirror pool, the
teleport pads, accent lights, and the UI's own accent color. Gold is
reserved specifically for "a result just happened" (capture burst,
victory). This dual-color discipline is already well-executed and
didn't need touching.

### Menu presentation — Weakest area found, now improved
The title screen said "ECHO HUNT" in the theme's own accent color but
had no visual device that says "echo" or "reflection" beyond the
color. This was the single highest-impact, lowest-risk place to spend
polish time — see "What was implemented."

### Round transitions — Good pacing, now theme-touched at the biggest beat
`RoundManager`'s round-end → breather → next-round flow and
`TransitionScreen`'s cover/fade are already well-paced (see
`GAMEPLAY_SYSTEMS.md`, `UI_STATE_MACHINE.md`). The one moment that
reads as generic UI rather than "this game" is the Game Over headline
(VICTORY/DEFEAT) — the single biggest dramatic beat in a match, and
previously just a plain colored label. Addressed this pass.

---

## What was implemented (fits the one-hour budget)

All three items reuse the exact same technique (a faint, vertically
mirrored duplicate of an existing label, or a delayed quiet audio
repeat) so the actual new code is small and low-risk.

### 1. `UIKit.make_reflected_title()` / `UIKit.make_reflection_label()`

**File:** `Scripts/UI/UIKit.gd`.

A reusable helper that takes a title Label and produces a faded (22%
opacity), vertically-flipped copy positioned directly beneath it — the
same "reflection in still water" read the arena's mirror pool already
gives the world, now available to any UI screen. Implemented as two
functions: `make_reflected_title()` for static text (builds both labels
itself), and `make_reflection_label()` for text that changes at
runtime (wraps an existing label, caller keeps both in sync — see item
3). The flip is applied around the label's own center, set only once
its real size is known (`Control.resized`), which is what keeps the
mirrored copy sitting in the right place instead of flying off in the
wrong direction — Control rects are zero at construction time, before
the first layout pass.

### 2. Title screen reflection

**File:** `Scripts/UI/MainMenu.gd`, `_build_title_screen()`.

`"ECHO HUNT"` now renders with its own faint mirrored echo directly
beneath it, using item 1. One line changed
(`UIKit.make_title(...)` → `UIKit.make_reflected_title(...)`).

### 3. Game Over headline reflection

**Files:** `Scripts/UI/HUD.gd` — `_build_game_over_panel()`,
`_show_game_over()`.

VICTORY/DEFEAT — the biggest single dramatic beat in a match — now
gets the same mirrored-echo treatment. Because this label's text and
color change at runtime (gold for a win, muted for a loss, decided
per-peer), this uses `make_reflection_label()` directly rather than the
all-in-one static helper: a second `Label` (`_game_over_headline_
reflection`) is built alongside the real one and its text/color are
kept in lockstep inside `_show_game_over()`.

### 4. A literal audio echo on every UI click

**File:** `Scripts/Autoload/AudioManager.gd`, `play_click()`.

Every menu click now plays a second, quieter (-14dB) repeat of the same
click sound 90ms later — a literal echo, on the single most frequent
audio event in the entire menu flow (every button press, everywhere).
Implemented with one extra `AudioStreamPlayer` (`_click_echo_player`,
built the same way every other one-shot player in `AudioManager`
already is) and one `get_tree().create_timer(...)` call — no DSP, no
new bus, no risk to the existing click sound.

---

## Recommended, not implemented (exceeds the one-hour budget)

Written up for a future pass — none of these were started.

- **Menu background world-preview.** A blurred/darkened live shot of the
  mirror pool behind the title screen (instead of a flat
  `COLOR_BACKGROUND` rect) would sell "reflection" before a player even
  presses a button. Non-trivial: needs either a `SubViewport` rendering
  a small scene, or a pre-baked background image — either is real scope,
  not a one-line change.
- **Lobby room-code reflection.** The lobby panel's room code label
  (`HUD._lobby_room_code_label`) is a natural third spot for
  `make_reflected_title()` — skipped this pass only to keep the total
  change surface small; it's the same one-line change as item 2 and a
  safe pick for the next five-minute polish pass.
- **Round-end panel border tint.** `UIKit.make_panel()`'s styling is
  shared by every dialog in the game; a one-off cyan-glow border
  specifically on the round-end/game-over panels (rather than the
  generic panel style) would tie the "something happened" UI moments
  closer to the echo/mirror color language. Skipped because
  `make_panel()` is shared by seven+ call sites — a targeted change
  risks a wider blast radius than the other three items here.
- **HUD role chip mirrored bracket.** A small symmetric bracket/rune
  motif around the HIDER/HUNTER role chip (top bar) — cosmetic-only,
  but needs actual new iconography (even simple `draw_line` brackets),
  which is more design iteration than fits in the remaining budget once
  items 1–4 were done.
- **Minimap real art.** The bottom-left echo-direction radar added in a
  prior pass (`EchoMinimap.gd`) is explicitly a placeholder (see its own
  doc comment) — replacing the flat-drawn circle with a camera-relative
  rotating map and real iconography is a distinct, larger task.
- **Mirror-panel reflection parallax.** The arena's `MirrorPanel`
  obstacles (`mirror_panel_material.tres`) are flat-colored boxes today,
  not literal mirrors — a cheap fake-reflection shader (mirror the
  scene's sky color across the panel's normal, no real planar
  reflection probe) would sell "mirror" harder at zero real-time
  reflection cost, but writing and tuning a new shader safely is its
  own scoped task, not a one-hour add-on to this pass.

## What did not change

Gameplay, timing, physics, scoring, networking, and every RPC are
untouched — every change in this pass is a `Label`/audio-player
addition or a one-line swap of an existing UI call for a themed
equivalent. See `git diff` for the exact, small surface: `Scripts/UI/
UIKit.gd`, `Scripts/UI/MainMenu.gd`, `Scripts/UI/HUD.gd`, `Scripts/
Autoload/AudioManager.gd`.

## Testing

1. Title screen: confirm "ECHO HUNT" shows a fainter, upside-down copy
   of itself directly beneath, not overlapping and not misplaced.
2. Win a match: confirm "VICTORY" (gold) shows its mirrored echo in the
   same gold tint. Lose a match: confirm "DEFEAT" (muted) does the same
   in muted.
3. Click any menu button: confirm a quieter, distinct echo of the click
   sound follows shortly after the main click — audible but clearly
   secondary, never louder or simultaneous with the primary click.
4. Confirm none of the above affects click responsiveness, button
   layout, or any other UI screen's spacing (both reflection labels are
   `MOUSE_FILTER_IGNORE`, so they can't intercept input).
