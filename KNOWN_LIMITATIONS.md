# Known Limitations — 1.1.0

The honest list for the Release Candidate. Supersedes `KNOWN_ISSUES.md`
(written for 1.0.0, several of whose entries have since been fixed —
kept for history). None of these block submission; each entry says why
it's acceptable and what the fix would look like.

## Content

1. **One character skin ships (Ninja).** `SkinRegistry` rosters six;
   the other five models aren't in `Assets/Characters/Skins/` yet. The
   registry is availability-filtered, so nothing references a missing
   file — and each remaining skin goes live by just dropping its
   `.fbx` in (no code changes; the picker, replication, and validation
   all key off what exists).
2. **The echo ghost is a glowing capsule, not the Hider's skin.**
   Deliberate for readability (the ghost's job is to read as
   "supernatural echo," not as a second player) and cheap rendering.
   `CharacterRig.apply_ghost_material()` already exists for a future
   skinned-ghost upgrade.
3. **Forest Arena has no teleport pads and simpler lighting** than the
   Echo Chamber — by design of the map (denser cover instead of
   mobility), but worth knowing it plays differently.

## Presentation

4. **Minimap is fixed north-up** (doesn't rotate with the camera) and
   plots a single echo — matches this build's one-echo default.
5. **Remote players may not visibly turn their bodies.** The
   synchronizer replicates `Model:rotation:y`, but facing rotation is
   applied to a child of `Model` on the owning peer — so puppet facing
   may read as static (animation and position replicate fine). Cosmetic;
   needs a live two-peer session to confirm severity, and the fix
   (rotate `Model` itself, or re-target the replicated property) should
   only be made with that live test in hand.
6. **Skinned players' echo animation relies on substring clip matching**
   (`EchoGhost._resolve_clip`) between the skin's clip names and the
   ghost's library — verified by code review, needs one live look.
7. **One music bed for menu and game**; no tension layer in the final
   seconds of a round.

## Networking

8. **No host migration.** Host quits → the other player returns to the
   title screen with an explanation. At 2 players, re-hosting takes
   seconds; real migration would rebuild the authority model.
9. **Matchmaking depends on the public relay**
   (`wss://echo-relay.onrender.com`, a free-tier Render instance). Cold
   starts can add ~30–60s to the *first* connection of the day (the
   game pings it at launch to warm it); if the relay is down, hosting
   and joining are down. TURN fallback uses a public open relay
   (openrelay.metered.ca) — fine for a jam, not a production SLA.
10. **Reconnect window is 20 seconds** (same running client only).
    Score, role, name, and skin all survive a reconnect inside it.

## Platform / build

11. **No macOS or web build.** macOS needs signing not available here;
    web would need a different WebRTC path than the shipped
    `webrtc_native` GDExtension (see EXPORT_GUIDE.md).
12. **Windows build is unsigned** — SmartScreen will warn on first run;
    say so on the store page (see ITCH_UPLOAD_GUIDE.md).
13. **Debug telemetry prints in the console** (`[PACKET-TRACE]`,
    `[WS-DEBUG]`) — deliberately kept for the jam build so networking
    problems reported by players are diagnosable from a pasted log.
    Strip via the grep commands in PACKET_TRACE.md / SOCKET_DEBUG.md
    for a post-jam release.

## Gameplay (by design)

14. **The match keeps running while paused** (two-player network game;
    the pause screen says so). WASD still works while paused.
15. **No mouse-look in the warm-up lobby** while the lobby panel is
    open (press TAB to hide it and free-roam).
16. **Theoretical mantle stuck-state** if its tween were ever
    interrupted — no repro found in any normal play path; watch item
    only (see FINAL_QA_REPORT.md).
