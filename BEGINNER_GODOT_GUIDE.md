# Beginner's Guide to Godot (for this project)

This guide assumes you have **never opened Godot before**. It walks
through everything you need to open, run, understand, and modify Echo
Hunt.

## 1. Installing Godot

1. Go to the official download page: https://godotengine.org/download
2. Choose your OS (Windows/Mac/Linux) and download the **Standard**
   build labeled **Godot 4.3** (avoid the ".NET" version — this project
   uses GDScript, not C#).
3. Godot doesn't need a traditional installer — it's a single
   executable. Unzip it somewhere convenient (e.g. `Desktop\Godot`) and
   double-click `Godot_v4.3-stable_win64.exe` (or equivalent) to launch
   it.

## 2. Opening the project

1. Launch Godot — you'll see the **Project Manager**, a list of known
   projects (empty the first time).
2. Click **Import**.
3. Click **Browse**, navigate to this project's folder, and select the
   file named `project.godot`.
4. Click **Import & Edit**. The main editor window opens.

## 3. Running the project

- Press **F5**, or click the ▶ (Play) button in the top-right corner.
- The first time, Godot may ask "Select Main Scene" — this shouldn't
  happen here since `MainMenu.tscn` is already set as the main scene,
  but if it does, pick `Scenes/UI/MainMenu.tscn`.
- Press **F8** (or the stop button) to stop running.

## 4. Understanding Scenes

A **Scene** in Godot is a reusable chunk of the game — a menu screen, a
character, a level. Every `.tscn` file you see (`Player.tscn`,
`EchoChamber.tscn`, `MainMenu.tscn`, etc.) is one scene. Scenes are built
as a **tree of Nodes**, and scenes can contain other scenes (e.g.
`Main.tscn` loads the currently selected map scene into its
`MapContainer` node at runtime — see `MAP_SYSTEM.md`).

Double-click any `.tscn` file in the **FileSystem** panel (bottom-left)
to open it in the **Scene** panel (top-left), where you'll see its node
tree.

## 5. Understanding Nodes

A **Node** is the basic building block — everything in the scene tree is
a node. Different node *types* do different things:
- `Node3D` — a plain 3D object with just a position (used as a folder /
  grouping point, e.g. `CameraPivot`).
- `CharacterBody3D` — a physics body meant for player-controlled
  characters (used by `Player.tscn`).
- `MeshInstance3D` — renders a visible 3D shape.
- `CollisionShape3D` — defines the invisible physical shape for
  collision.
- `Camera3D` — what the player sees through.
- `Control` / `Label` / `Button` — 2D UI elements (used in the menu and
  HUD).

Click any node in the Scene panel to see its properties in the
**Inspector** (right side) — that's how position, color, size, etc. are
set without code.

## 6. Editing scripts

A **Script** (`.gd` file) attaches behavior to a node. In the Scene
panel, a node with a script has a small scroll icon next to it.
Double-click that icon (or the script file in FileSystem) to open it in
the built-in **Script** editor tab at the top of the window.

Scripts in this project are plain GDScript (Python-like syntax). For
example, `Scripts/Player/PlayerController.gd` reads WASD input and moves
the character — open it and read the comments at the top of each
function to see what it does.

You don't need to reopen Godot after editing a script — just save
(Ctrl+S) and press F5 again to see the change.

## 7. Testing multiplayer locally

See [`HOW_TO_RUN.md`](HOW_TO_RUN.md) for full steps. Short version:
**Debug → Run Multiple Instances → 2**, then F5. Two windows open; host
in one, join `127.0.0.1` in the other.

## 8. Exporting a Windows build

See the "Exporting a Windows build" section in
[`HOW_TO_RUN.md`](HOW_TO_RUN.md). In short: **Project → Export**, add a
Windows Desktop preset (installing export templates if prompted), then
**Export Project**.

## 9. Exporting for itch.io

Also covered in `HOW_TO_RUN.md` under "Publishing to itch.io" — zip the
exported `.exe` + `.pck`, upload to an itch.io project page, mark the
platform as Windows.

## 10. Common mistakes (and how to avoid them)

- **"Failed to load script" errors on open** — usually means a script
  file was moved/renamed without updating the scene that references it.
  Check the exact path in the error message against the `Scripts/`
  folder.
- **Editing a scene's node tree instead of its script** — remember,
  *what a node looks like/where it sits* is set in the Inspector;
  *what it does* is set in its script. Beginners often hunt for
  behavior in the Inspector when it's actually in code, or vice versa.
- **Testing multiplayer with only one window open** — hosting alone
  will not spawn a second player and the round won't start (this MVP
  needs exactly two connected peers). Always test with two instances.
- **Forgetting to click into the game window before using the mouse** —
  the OS won't send mouse-look input to an unfocused window.
- **Editing `.tscn` files by hand outside Godot** — possible (they're
  plain text), but risky for beginners; a single misplaced value can
  make the scene fail to parse. Prefer the editor UI until you're
  comfortable with the format.
- **Committing the `.godot/` folder to git** — this is Godot's local
  cache, not source content. It's already excluded via `.gitignore`;
  don't remove that entry.
- **Assuming Play (F5) tests the exported build** — always test the
  actual exported `.exe` before publishing; editor behavior and exported
  behavior can differ slightly (see `HOW_TO_RUN.md`).
