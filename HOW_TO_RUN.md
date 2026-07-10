# How to Run

## Requirements

- [Godot 4.3 Stable](https://godotengine.org/download) (or newer 4.x —
  the project uses no 4.4-only features). Get the standard build, not
  .NET/C#, since this project is pure GDScript.

## Open the project

1. Launch Godot. On the Project Manager window, click **Import**.
2. Browse to this folder and select `project.godot`.
3. Click **Import & Edit**.

## Run it (single instance)

Press **F5**, or click the ▶ Play button top-right. The Main Menu
(`Scenes/UI/MainMenu.tscn`) should appear.

## Test multiplayer locally (two instances on one PC)

You need **two running copies** of the game talking over `localhost`.

**Option A — two editor instances:**
1. In Godot, open **Debug → Run Multiple Instances → 2**, then press F5.
   Two game windows will launch from the same editor.

**Option B — editor + exported build:**
1. Press F5 in the editor (instance #1).
2. Export a Windows/Linux build (see below) and run the `.exe`/binary
   directly (instance #2). Two separate processes avoid any editor
   quirks and is closer to how real testers will run it.

**Then, in either window:**
1. In window 1, click **Host Game**.
2. In window 2, type `127.0.0.1` in the IP field and click **Join Game**.
3. Both windows should drop into the arena with two characters.

See [`TESTING_GUIDE.md`](TESTING_GUIDE.md) for what to verify at each
step.

## Test multiplayer over a LAN (two PCs)

1. On PC A: click **Host Game**. Find PC A's local IP (`ipconfig` on
   Windows, look for something like `192.168.x.x`).
2. On PC B: enter PC A's IP in the Join field, click **Join Game**.
3. Both PCs must be on the same network, and PC A's firewall must allow
   inbound UDP on port `7777` (Godot will usually prompt for this the
   first time you host).

## Exporting a Windows build (for itch.io)

1. In the editor: **Project → Export…**.
2. Click **Add…** and choose **Windows Desktop**.
3. If prompted, install export templates via **Editor → Manage Export
   Templates → Download and Install** (must match your Godot version
   exactly).
4. Under the Windows preset, set an output path like
   `builds/windows/EchoHunt.exe`.
5. Click **Export Project**, choose the same path, and wait for it to
   finish. Godot will produce `EchoHunt.exe` plus a `.pck` data file —
   ship both together.
6. Test the exported `.exe` directly (don't just trust the editor run) —
   host in one copy, join from another, before uploading anywhere.

## Publishing to itch.io

1. Zip the export output folder (the `.exe` + `.pck`, and any other
   files Godot generated alongside them).
2. On itch.io, create/edit your project page, set **Kind of project** to
   "Executable", upload the zip, and check **"This file will be played in
   the browser"** OFF (this is a native download, not WebGL) — check
   **Windows** as the platform for that upload.
3. Because this is a peer-hosted (not dedicated-server) game, tell
   players in the page description that one player hosts and shares
   their IP, and that both players need the same build version.

## Common run problems

| Symptom | Likely cause |
|---|---|
| "Could not host game (error ...)" | Port `7777` already in use — close other instances, or another app is using it |
| Join hangs on "Connecting..." then fails | Wrong IP, host not actually running, or a firewall blocking UDP 7777 |
| Second window shows a blank/empty arena | Give it a second — the player spawns as soon as the connection completes; if it never appears, confirm both windows are running the *same* project version |
| Mouse doesn't look around | Click inside the game window first to give it input focus; press Esc to toggle mouse capture |
