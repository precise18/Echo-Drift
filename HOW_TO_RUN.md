# How to Run

## Requirements

- [Godot 4.3 Stable](https://godotengine.org/download) (or newer 4.x).
  Get the **Standard** build, not .NET/C# — this project is pure
  GDScript.
- Or skip the engine entirely and use a release build (see
  BUILD_GUIDE.md).

## Open the project

1. Launch Godot. On the Project Manager window, click **Import**.
2. Browse to this folder and select `project.godot`.
3. Click **Import & Edit**.

## Run it (single instance)

Press **F5**, or click the ▶ Play button top-right. The title screen
appears. (Hosting alone parks you in the warm-up lobby with **Start
Match** disabled — the game needs two players.)

## Test multiplayer locally (two instances on one PC)

You need **two running copies** of the game talking over `localhost`.

**Option A — two editor instances:**
1. In Godot: **Debug → Run Multiple Instances → 2**, then press F5.
   Two game windows launch from the same editor.

**Option B — editor + exported build:** run the editor (F5) as one
instance and a release build (BUILD_GUIDE.md) as the other — two
separate processes is closest to how real players run it.

**Then:**
1. Window 1: **Host Game** → pick the map → **Start Hosting**.
2. Window 2: **Join Game** → IP `127.0.0.1` → **Join**.
3. Both windows land in the **warm-up lobby** in the arena — walk
   around with WASD (the cursor stays free for the lobby UI).
4. Window 1 (the host): press **Start Match**. The round banner shows
   your roles; first to 3 round wins takes the match.

See [`TEST_PLAN.md`](TEST_PLAN.md) for the full verification checklist.

## Test multiplayer over a LAN (two PCs)

1. On PC A: **Host Game → Start Hosting**. Find PC A's local IP
   (`ipconfig` on Windows / `ip addr` on Linux — usually
   `192.168.x.x`).
2. On PC B: **Join Game**, enter PC A's IP, **Join**. (The last IP you
   joined is remembered.)
3. Both PCs must be on the same network, and PC A's firewall must
   allow inbound **UDP 7777** (the OS usually prompts the first time
   you host). Both players need the same build version.

## Exporting / publishing

- Building release binaries: [`BUILD_GUIDE.md`](BUILD_GUIDE.md)
- Export presets and platform notes: [`EXPORT_GUIDE.md`](EXPORT_GUIDE.md)
- Putting it on itch.io: [`ITCH_IO_DEPLOYMENT.md`](ITCH_IO_DEPLOYMENT.md)

## Common run problems

| Symptom | Likely cause |
|---|---|
| "Could not host (error ...)" | Port `7777` already in use — close other instances, or another app owns it |
| Join hangs on "Connecting..." then fails | Wrong IP, host not actually running, or a firewall blocking UDP 7777 |
| Start Match stays disabled | Only one player is connected — the lobby shows "Players: 1 / 2" until the second joins |
| Second window shows an empty arena | Give it a second — the player spawns when the connection completes; if never, confirm both run the *same* version |
| Mouse doesn't look around | During the lobby that's intentional (cursor is free for the UI); in a round, click the window to focus it — and ESC opens the pause menu, ESC again resumes |
| Settings didn't stick | They save to `user://settings.cfg` on change; if the file can't be written (odd permissions), defaults return |
