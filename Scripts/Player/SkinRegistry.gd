class_name SkinRegistry
## Registry of every selectable character skin — the same pattern as
## MapManager.MAPS: adding a skin later means one entry here plus one
## model file, and the lobby picker/replication/ghost all follow with no
## further changes. Models are CC0 from Quaternius's Ultimate Animated
## Character Pack (see Assets/Characters/Skins/LICENSE.txt, LICENSES.md,
## and ART_DIRECTION.md for sourcing).
##
## `color` is the player's identity tint — used for the lobby name tag
## and the picker button highlight. It's identity, not role: role colors
## (hider blue / hunter red) stay with the HUD chip and the own-feet
## role ring, never on the skin itself.

const SKINS := {
	"ninja": {
		"name": "Ninja",
		"scene": "res://Assets/Characters/Skins/Ninja_Male.fbx",
		"color": Color(0.35, 0.4, 0.5),
	},
	"knight": {
		"name": "Golden Knight",
		"scene": "res://Assets/Characters/Skins/Knight_Golden_Male.fbx",
		"color": Color(1.0, 0.8, 0.3),
	},
	"witch": {
		"name": "Witch",
		"scene": "res://Assets/Characters/Skins/Witch.fbx",
		"color": Color(0.6, 0.35, 0.8),
	},
	"viking": {
		"name": "Viking",
		"scene": "res://Assets/Characters/Skins/Viking_Female.fbx",
		"color": Color(0.85, 0.45, 0.25),
	},
	"zombie": {
		"name": "Zombie",
		"scene": "res://Assets/Characters/Skins/Zombie_Male.fbx",
		"color": Color(0.45, 0.75, 0.4),
	},
	"cowgirl": {
		"name": "Cowgirl",
		"scene": "res://Assets/Characters/Skins/Cowboy_Female.fbx",
		"color": Color(0.75, 0.55, 0.35),
	},
}
const DEFAULT_SKIN_ID := "ninja"


static func get_skin_ids() -> Array:
	return SKINS.keys()


## Only the skins whose model file actually exists in this build. The
## registry above is the full roster the team planned; models land in
## Assets/Characters/Skins/ one at a time, and everything downstream
## (picker, replication, valid_id fallback) keys off THIS list so a
## missing .fbx can never be selected, replicated, or instantiated.
## Adding a skin later means dropping in the file — no code changes.
static func available_ids() -> Array:
	var out := []
	for skin_id in SKINS:
		if _exists(skin_id):
			out.append(skin_id)
	return out


static func _exists(skin_id: String) -> bool:
	return SKINS.has(skin_id) and ResourceLoader.exists(String(SKINS[skin_id]["scene"]))


## Resolution order: the requested skin if its model exists, else the
## default if THAT exists, else the first available skin, else "" —
## which callers treat as "no skin system in this build; keep the stock
## capsule model" (see PlayerController._apply_skin).
static func valid_id(skin_id: String) -> String:
	if _exists(skin_id):
		return skin_id
	if _exists(DEFAULT_SKIN_ID):
		return DEFAULT_SKIN_ID
	var available := available_ids()
	return available[0] if not available.is_empty() else ""


static func get_skin_name(skin_id: String) -> String:
	var id := valid_id(skin_id)
	return SKINS[id]["name"] if id != "" else ""


static func get_skin_color(skin_id: String) -> Color:
	var id := valid_id(skin_id)
	return SKINS[id]["color"] if id != "" else Color.WHITE


static func get_skin_scene(skin_id: String) -> PackedScene:
	var id := valid_id(skin_id)
	if id == "":
		return null
	# load(), not preload: skins are the largest assets in the project
	# and only 1-2 of the six are ever on screen. Godot caches loads, so
	# flipping through the lobby picker re-uses already-loaded scenes.
	return load(SKINS[id]["scene"]) as PackedScene
