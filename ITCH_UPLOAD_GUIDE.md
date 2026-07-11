# itch.io Upload Guide — 1.1.0

Step-by-step from a clean working tree to a live itch.io submission.
This supersedes `ITCH_IO_DEPLOYMENT.md`, which was written for the old
LAN/port-forwarding networking — the game now matchmakes over an online
relay with 4-letter room codes, which changes what the store page must
say.

## 0. Prerequisites (once)

- Godot **4.3-stable** (or the 4.x version you author in) with matching
  export templates installed (Editor → Manage Export Templates).
- An itch.io account, and [butler](https://itch.io/docs/butler/)
  installed if you want repeatable CLI uploads (recommended).

## 1. Pre-export verification (every release)

1. **Open the project in the Godot editor once** and let it import.
   This matters more than usual this release: `Ninja_Male.fbx` (the
   character skin) and the new Arena materials must have import
   artifacts in `.godot/` before an export can include them.
2. Check the Output panel: zero red errors on load.
3. Run two instances locally (F5 twice, or two exported copies):
   - Host → room code appears → join with the code from instance two.
   - Lobby shows both names; Start Match.
   - Play one round to a **capture** and one to a **timeout**; confirm
     roles swap, the echo appears after ~10s and animates, the minimap
     blip tracks it, and the score updates on both screens.
   - Win a match → Game Over → **Rematch** works → **Leave to Menu**
     works.
   - Repeat once with the **Forest Arena** map selected while hosting.
4. Confirm the version stamp: `project.godot` → `config/version`
   (currently `1.1.0`) matches CHANGELOG.md's top entry.

## 2. Export

From the editor (Project → Export) or headless:

```bash
godot4 --headless --export-release "Linux"   builds/linux/echo-hunt-linux.x86_64
godot4 --headless --export-release "Windows" builds/windows/echo-hunt-windows.exe
```

Both presets embed the pack — each output is one self-contained file.
Zip each with a short README (controls + "2 players, online, room
codes"):

```bash
cd builds/linux   && zip ../echo-hunt-1.1.0-linux.zip   echo-hunt-linux.x86_64 && cd ../..
cd builds/windows && zip ../echo-hunt-1.1.0-windows.zip echo-hunt-windows.exe  && cd ../..
```

Boot-test the Linux build before uploading:

```bash
./builds/linux/echo-hunt-linux.x86_64 --quit-after 300   # loads to menu, exits clean
```

## 3. Create the itch.io project page

itch.io → **Upload new project**:

| Field | Value |
|---|---|
| Title | Echo Hunt |
| Kind of project | Downloadable |
| Pricing | No payments (or Donate) |
| Genre | Action |
| Tags | `multiplayer`, `online-multiplayer`, `hide-and-seek`, `godot`, `3d`, `low-poly` |
| Multiplayer | Online multiplayer, 2 players |

**Description — must include, in this order:**

1. The pitch: *"2-player online hide-and-seek where your movements
   become living echoes — the Hunter tracks your past to find your
   present."*
2. **How to play together** (this is now room codes, not IPs/ports):
   one player clicks **Host Private Game** and shares the 4-letter room
   code (it's auto-copied to their clipboard); the other clicks
   **Join Private Game** and types it. Or both use **Quick Play** /
   the **Server Browser** for public matches. **No port forwarding, no
   IP addresses.**
3. **First-connection note:** the matchmaking server sleeps when idle
   (free hosting) — the first Host/Join of a session can take up to a
   minute to wake it. The game pings it at launch to warm it up.
4. **Windows SmartScreen note:** the build is unsigned; "Windows
   protected your PC" → *More info → Run anyway* is expected.
5. Controls: WASD move, mouse look, Space jump, Shift sprint, TAB
   toggles the lobby panel, ESC pause.
6. Credits block: *Made with Godot Engine (MIT). Environment props:
   Kenney Nature Kit (CC0). Character model: Quaternius Ultimate
   Animated Character Pack (CC0). All audio synthesized at runtime.*

**Screenshots:** the echo ghost mid-trail (your single best image), the
mirror pool, a capture moment, the Game Over screen, and one shot of
the Forest Arena. A short GIF of the ghost retracing a player's path
sells the whole game in two seconds.

## 4. Upload the builds

**Web UI:** add both zips under Uploads; tick the matching OS box on
each; set "Display name" to include the version.

**butler (recommended — diffs future patches):**

```bash
butler login
butler push builds/echo-hunt-1.1.0-linux.zip   YOUR_USER/echo-hunt:linux   --userversion 1.1.0
butler push builds/echo-hunt-1.1.0-windows.zip YOUR_USER/echo-hunt:windows --userversion 1.1.0
butler status YOUR_USER/echo-hunt
```

Keep the channel names (`linux`/`windows`) stable forever — itch tracks
version history per channel.

## 5. Submit to the jam

1. Set the project page to **Public** (Draft pages can't be rated).
2. Open the jam page → **Submit your project** → pick Echo Hunt.
3. In the submission form, restate the two-player requirement in the
   first line — raters need to know to grab a partner (or run two
   instances on one machine: host in one, join with the same room code
   in the other; both work fine on a single PC).
4. Don't push new builds to the rated channels between the deadline and
   the end of rating.

## 6. Post-upload smoke test (do not skip)

From the live itch page, on a machine that has never seen the project:
download the Windows zip → unzip → run → SmartScreen bypass → Host →
join it from a second machine/instance → play one full round. If that
works end-to-end, the submission is real.

## Release checklist

- [ ] Editor opened once; all imports clean; zero load errors
- [ ] `config/version` = CHANGELOG top entry = `--userversion`
- [ ] Both presets exported from the same commit
- [ ] Linux build boot-tested (`--quit-after`, exit 0)
- [ ] One full two-instance match on the *exported* build (both maps)
- [ ] Windows build smoke-tested on real Windows once
- [ ] Page: room-code instructions, relay cold-start note, SmartScreen
      note, controls, credits, 2-player warning in line one
- [ ] Jam submission form completed; page set to Public
