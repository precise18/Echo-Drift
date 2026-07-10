# itch.io Deployment

Publishing Echo Hunt 1.0.0 to itch.io, start to finish. The builds
themselves come from BUILD_GUIDE.md; this is everything after that.

## What you're uploading

| File | Platform | Channel name |
|---|---|---|
| `builds/echo-hunt-1.0.0-linux.zip` | Linux | `linux` |
| `builds/echo-hunt-1.0.0-windows.zip` | Windows | `windows` |

Each zip contains one self-contained executable (pack embedded) —
players unzip and run. **No web/HTML5 upload**: browser builds can't do
UDP, so the ENet multiplayer would not function (see EXPORT_GUIDE.md).

## One-time setup

1. Create the project: itch.io → **Upload new project**.
   - **Kind of project:** Downloadable.
   - **Pricing:** "No payments" or "Donate" — jam-friendly.
   - **Uploads:** add both zips; tick the matching OS box on each.
2. (Recommended) Install **butler**, itch's CLI, for repeatable
   uploads: https://itch.io/docs/butler/

## Uploading with butler (repeatable releases)

```bash
butler login
butler push builds/echo-hunt-1.0.0-linux.zip   YOUR_USER/echo-hunt:linux   --userversion 1.0.0
butler push builds/echo-hunt-1.0.0-windows.zip YOUR_USER/echo-hunt:windows --userversion 1.0.0
butler status YOUR_USER/echo-hunt
```

butler diffs uploads, so future patches transfer only what changed.
Keep channel names stable (`linux` / `windows`) — itch tracks version
history per channel.

## Page content template

**Tagline:** *Your past is hunting you. 2-player LAN hide-and-seek
where your movements become living echoes.*

**Description:** use the pitch + "Play it" section from README.md.
Must-include practical notes:

- **2 players, LAN.** One hosts, the other joins via the host's local
  IP (port 7777). Internet play needs the host to forward UDP 7777.
- **Windows note:** the build is unsigned — SmartScreen may show
  "Windows protected your PC"; *More info → Run anyway*. (Normal for
  jam games; saying it upfront prevents confused comments.)
- **Controls table** from README.md.

**Credits block** (also on the in-game Credits screen):

> Made with Godot Engine — © Juan Linietsky, Ariel Manzur and
> contributors (MIT). Environment props: "Nature Kit" by Kenney
> (kenney.nl), CC0. All audio synthesized at runtime — no recorded
> assets.

**Metadata suggestions:** Genre: Action; Tags: `multiplayer`,
`hide-and-seek`, `local-multiplayer` (itch has no plain "LAN" tag —
mention LAN in the description), `low-poly`, `godot`, `3d`;
Multiplayer: "Local multiplayer" + note; Player count: 2.

**Screenshots:** capture in-game (F5 → two instances → a round):
the mirror pool with sparkles, an echo ghost mid-trail, the Hunter
closing in, the Game Over screen. itch pages convert much better with
a short GIF of the echo ghost following a player's path — that one
image explains the whole game.

## For a jam submission specifically

- Submit the same project page through the jam's submission flow.
- Most jams require builds to stay unmodified during rating — upload
  before the deadline and don't push to those channels until rating
  ends (butler pushes create new versions; itch keeps the old ones,
  but don't cut it fine).
- Put the two-player requirement in the first line of the description
  — raters need to know they'll need a second person (or two instances
  on one machine: both builds run fine twice on one PC with
  `127.0.0.1`).

## Release checklist

- [ ] Both zips freshly exported from the tagged commit
- [ ] Linux build boot-tested (`--headless --quit-after 120`, exit 0)
- [ ] One real two-instance match played on the exported build
      (lobby → 3+ rounds → game over → rematch — TEST_PLAN.md §Release)
- [ ] Windows build smoke-tested on a real Windows machine once
- [ ] Page description includes LAN/port/SmartScreen notes
- [ ] Credits block present on page
- [ ] CHANGELOG.md entry matches `--userversion`
