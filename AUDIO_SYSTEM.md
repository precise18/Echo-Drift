# Audio System

Complete audio for Echo Hunt: footsteps, echo footsteps, teleport sounds,
UI sounds, ambient music, environment ambience, and round
start/end/victory/defeat stings — with positional audio everywhere a
sound has a place in the world. Builds on the approach `EchoAudio.gd`
established in the MVP: **every sound is synthesized at runtime**, no
external audio files, so the repository stays small and license-clean
(see `Assets/README.md`), and every stream can be swapped for a real
recorded asset later without touching the code that plays it.

## Architecture

```
                       ┌────────────────────────────┐
                       │  SoundFactory (static)     │
                       │  Scripts/Audio/            │
                       │  synthesizes + caches every│
                       │  sound as AudioStreamWAV   │
                       └─────────────┬──────────────┘
                 streams built once, │ shared by all players of a sound
              ┌──────────────────────┼───────────────────────────┐
              │                      │                           │
┌─────────────┴─────────────┐ ┌──────┴───────────────┐ ┌─────────┴─────────┐
│ AudioManager (autoload)   │ │ FootstepEmitter      │ │ Positional one-offs│
│ non-positional audio:     │ │ (AudioStreamPlayer3D)│ │ TeleportPad.Whoosh │
│ buses, music bed, wind,   │ │ on every player and  │ │ EchoChamber.       │
│ UI click/hover, round     │ │ every echo ghost     │ │   MirrorPoolHum    │
│ start/end/victory/defeat  │ │                      │ │ EchoAudio (hum)    │
└───────────────────────────┘ └──────────────────────┘ └───────────────────┘
```

Three layers:

1. **`Scripts/Audio/SoundFactory.gd`** — a static class that generates
   every sound as 16-bit PCM in an `AudioStreamWAV`, built on first
   request and cached, so a sound used in ten places is synthesized once.
   All generators use fixed RNG seeds, so every player hears the same
   game. Measured cost of building *all twelve* sounds: **~390 ms, once**
   (loops are generated at 8–11 kHz since none of them contain content
   above ~1 kHz, which is most of why it's that cheap).
2. **`Scripts/Autoload/AudioManager.gd`** — owns everything that isn't
   tied to a 3D position: the audio bus layout, the looping music bed and
   wind ambience, UI sounds, and the round stings (wired to
   `RoundManager.round_started` / `round_ended`).
3. **Positional emitters on the nodes they belong to** — footsteps on
   players and ghosts, the whoosh on each teleport pad, the hum on the
   mirror pool, the existing `EchoAudio` tone on ghosts. All are
   `AudioStreamPlayer3D`, so distance attenuation and panning relative to
   the local camera are free.

## Bus layout

Created programmatically by `AudioManager._setup_buses()` at startup (no
`default_bus_layout.tres` to keep in sync):

| Bus | Volume | Carries |
|---|---|---|
| `SFX` | −8 dB | Footsteps, echo footsteps, teleport whoosh, echo hum, round stings |
| `UI` | −10 dB | Button click/hover |
| `Music` | −16 dB | The ambient pad loop |
| `Ambience` | −20 dB | Wind bed, mirror pool hum |

Music and ambience sit well under SFX **deliberately**: in a
hide-and-seek game, footsteps are information, not decoration — nothing
in the mix is allowed to mask them.

## The sounds

| Sound | Design | Where it plays |
|---|---|---|
| Footstep | Fast-decaying lowpassed noise scuff over an 85 Hz thump; ±8% pitch randomization per step | `FootstepEmitter` on every player body, on every peer |
| Echo footstep | The same impulse plus two decaying delay taps and a faint 660 Hz ping | `FootstepEmitter` on every echo ghost |
| Teleport | Exponential 280→980 Hz sweep with a detuned-octave shimmer | `TeleportPad`, at both ends of the jump |
| UI click / hover | Tiny sine blips (880 / 660 Hz) | `MainMenu` buttons + map selector, HUD restart button |
| Round start | Two quick ascending plucks (A4→E5) | `AudioManager`, on `round_started` |
| Round end | An inharmonic gong (220/277/331 Hz) — deliberately neutral | `AudioManager`, on `round_ended` |
| Victory | Ascending major arpeggio (C5–E5–G5–C6) | `AudioManager`, 0.8 s after the gong, if the local role won |
| Defeat | Slow descending minor line (A4–F4–D4) | Same, if the local role lost |
| Ambient music | 12 s two-chord pad (A minor ↔ F major) with sin²/cos² crossfade | `AudioManager`, looping always |
| Environment ambience | Filtered brown noise with a slow gust swell (6 s loop) | `AudioManager`, looping always |
| Mirror pool hum | Two barely-detuned 110 Hz sines (slow beat pulse) + quiet octave | Positional, at the pool |

The echo footstep is a gameplay decision, not just a variant: an echo's
steps are recognizably *the same sound, but hollow and reverberant*, so a
Hunter can distinguish real steps from echo steps by ear — which is
exactly the mind-game the game's pitch is about (echoes as information
*and* deception).

**Seamless loops without files:** a synthesized loop clicks at the wrap
point unless it's designed not to. The music and hum quantize every note
frequency to a whole number of cycles per loop (`_quantize_freqs`, error
< 1/24 Hz — inaudible) and use crossfade windows that are themselves
periodic in the loop length; the wind loop crossfades its tail into its
head. All three loop byte-perfectly.

## How audio stays in sync across the network — without networking

No audio event sends a network message. Everything derives from state
that is already replicated:

- **Footsteps** — `FootstepEmitter` watches its parent's *observed
  position* each frame and plays a step every `stride` (1.9 m) of
  horizontal travel. Since remote players' positions arrive via
  `MultiplayerSynchronizer` and ghost positions come from `EchoRecorder`
  playback, the same emitter works for local players, remote players, and
  ghosts identically — each peer derives every character's footsteps from
  positions it already has. (A single-frame jump > 3 m is treated as a
  teleport/spawn and resets the stride accumulator instead of firing a
  burst of steps.)
- **Teleport whoosh** — `Area3D.body_entered` fires on *every* peer,
  because remote bodies' replicated positions enter and leave the pad
  areas too. A genuine teleport produces exactly one entered event at
  each end (departure pad, then arrival pad), so both players hear both
  ends positionally. The whoosh plays *before* the authority guard in
  `TeleportPad._on_body_entered`, rate-limited per body.
- **Round stings, victory/defeat** — driven by `RoundManager`'s
  `round_started`/`round_ended` signals, which are emitted on every peer
  by the same reliable `call_local` RPCs that drive the HUD. Whether the
  gong is good news is resolved locally: each peer compares the winner
  role against its own role from the same replicated round state.

## Performance

- One-time synthesis cost at startup: **~390 ms** for all sounds
  combined, measured headless. Nothing is synthesized per-frame except
  the pre-existing `EchoAudio` generator hum (unchanged).
- Steady-state cost is just normal mixing of a handful of short mono
  16-bit streams: 2 loops + 1 positional hum playing continuously, plus
  transient one-shots. No reverb/effect buses were added.
- `FootstepEmitter._process` is a vector subtraction and a couple of
  comparisons per character per frame (3 characters in a round).

## Known limitations

- **No footsteps distinguish surfaces** — one step sound everywhere; the
  arena is one material, so surface variants weren't worth their cost yet.
- **Menu and game share one music bed** — there's no separate menu track;
  the pad is quiet and ambient enough to serve both.
- **A stray whoosh is possible** at a pad in one edge case (walking onto
  a pad while still on its teleport cooldown plays the sound without a
  teleport on the observing peer). Rate-limited to at most one; harmless
  in practice.
- **Engine noise on host quit** (pre-existing, not audio): when the host
  process exits, the other peer's `MultiplayerSynchronizer` teardown logs
  two internal `get_unique_id` errors. Cosmetic; predates this system.

## Testing

Verified with the project's established headless pattern:

1. `godot --headless --path . --import` after every change — no parse or
   property errors.
2. A **real two-process host/join session** (temporary test autoload
   driving `NetworkManager.host_game()`/`join_game()`, with the host
   simulating movement via `Input.action_press`): round started with both
   players, all four buses present, music playing, footstep emitter
   *observed firing* on real replicated movement, ghost echo-footstep
   emitter present, zero script errors. Test harness deleted after use.
3. Sound generation timed in the same harness (~390 ms total).

Headless runs use Godot's dummy audio driver — playback is logically
exercised (streams start, `playing` flips true, no errors) even though
nothing reaches a speaker; the audible result was designed by
construction (envelopes, frequencies) rather than by ear, so listen and
tune bus volumes in `AudioManager.BUSES` to taste.

## Future improvements

- Replace synthesized streams with recorded CC0 assets (Kenney's audio
  packs, OpenGameArt SFX) — one function per sound in `SoundFactory` is
  the only place to touch.
- Distance-based lowpass on far footsteps (occlusion feel) via a per-bus
  effect once mixing matters more.
- A separate, tenser music layer that crossfades in during the round's
  final 20 seconds.
