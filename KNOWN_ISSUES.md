# Known Issues

The honest list, collected from every subsystem's "known limitations"
section and the release audit. None of these block a game-jam release;
each entry says why it's acceptable for 1.0.0 and what the fix would
look like.

## Networking

1. **No host migration.** If the host quits, the other player is
   returned to the title screen with an explanation ("Host
   disconnected.") rather than seamlessly taking over. *Why acceptable:*
   at 2 players on LAN, restarting a session takes seconds; real
   migration would rebuild the entire authority model. (See
   NETWORKING_REPORT.md.)
2. **Reconnect forgets the score.** A client that drops and rejoins
   within the 20 s grace window recovers its role and the current
   round, but its score display reads 0–0 until the next round result
   corrects it. *Fix:* include both scores in
   `RoundManager._resync_after_reconnect`.
3. **Internet play requires port forwarding.** The game targets LAN;
   playing across the internet means forwarding UDP 7777 on the host's
   router. No NAT punch-through / relay.
4. **Cosmetic engine errors on host quit.** The surviving peer's log
   shows two internal `get_unique_id` errors during scene teardown
   (engine-side, after the peer is cleared). No player-visible effect.

## Gameplay

5. **Keyboard movement still works while paused.** The pause menu
   releases the mouse but doesn't block WASD (the match keeps running
   by design — it's a two-player network game). *Why acceptable:* the
   pause screen says so explicitly; blocking movement would just
   penalize the paused player.
6. **No mouse-look in the warm-up lobby.** The lobby panel needs the
   cursor, so you can walk (WASD) but not orbit the camera until the
   round starts.
7. **A stray teleport whoosh is possible** in one edge case (stepping
   onto a pad that's still on cooldown plays the sound on the
   observing peer without a teleport). Rate-limited to one; harmless.

## Presentation

8. **Placeholder characters.** Players are capsules with a face
   indicator and procedural squash/lean animation — stylized on
   purpose, but a rigged low-poly character (Kenney/Quaternius) is the
   obvious upgrade. (See ART_DIRECTION.md.)
9. **One music bed for menu and game**; no tension layer in the final
   seconds. (See AUDIO_SYSTEM.md future improvements.)
10. **Audio levels tuned by construction, not by ear** — synthesized
    envelopes/frequencies were designed numerically and verified
    headless. If something feels loud/quiet, per-bus sliders are in
    Settings, and mix baselines are one dictionary
    (`AudioManager.BUSES`).

## Platform / build

11. **No macOS build.** Exporting for macOS requires signing/
    notarization tooling not available in this environment. The
    project itself has no platform-specific code; a Mac owner can
    export from the editor. (See EXPORT_GUIDE.md.)
12. **No web build — deliberately.** Browser games can't use UDP/ENet,
    and Echo Hunt's multiplayer is ENet-based. A web build would be a
    single-player shell; not worth shipping. (See EXPORT_GUIDE.md.)
13. **Editor-version quirk:** the project was authored against Godot
    4.3 but has been opened with a 4.7 Mono editor (which stamped the
    `[dotnet]` section and "4.7" feature tag into `project.godot`).
    Both are inert — there is no C# in the project, 4.3 imports and
    exports it cleanly, and release builds are made with 4.3 Standard.

## Testing-environment notes (not product issues)

- Headless test runs log dummy-renderer mesh warnings
  (`mesh_get_surface_count: Parameter "m" is null`) and
  `ObjectDB instances leaked` on force-quit — artifacts of running a
  GPU-less renderer and killing live sessions, present in every
  headless Godot project.
