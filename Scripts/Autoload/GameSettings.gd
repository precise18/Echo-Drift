extends Node
## Autoload: the player's persistent preferences — audio levels, mouse
## sensitivity, fullscreen, and the last IP they joined — loaded from
## user://settings.cfg at startup, applied immediately, and saved on
## every change (SettingsPanel calls the setters). Kept separate from
## AudioManager on purpose: AudioManager defines what the buses *are*,
## this defines how much of each the player wants.
##
## Registered after AudioManager so the buses already exist when the
## saved volumes are applied.

const SAVE_PATH := "user://settings.cfg"

## User volume per bus as a linear 0..1 multiplier applied *on top of*
## AudioManager.BUSES' baseline mix levels — so "1.0" always means "the
## mix as designed", not "0 dB".
var volumes := {
	&"Master": 1.0,
	&"Music": 1.0,
	&"SFX": 1.0,
	&"Ambience": 1.0,
	&"UI": 1.0,
}

var mouse_sensitivity := 1.0 # multiplier on PlayerController's base sensitivity
var fullscreen := false
var last_join_code := ""
var preferred_role := 0 # 0: Any, 1: Hider, 2: Hunter
## Empty means "no preference" — NetworkManager assigns a deterministic
## "Player 1" / "Player 2" fallback in that case (see PLAYER_NAME_SYSTEM.md).
## Deliberately not trimmed here: trimming on every keystroke would eat a
## trailing space the moment it's typed, making a multi-word name
## impossible to enter. The meaningful trim (deciding whether the name is
## "blank") happens once, server-side, in NetworkManager._apply_display_name.
var display_name := ""
## The chosen character skin (a SkinRegistry id). Validated server-side
## against the skins actually present in the build (SkinRegistry.valid_id)
## on registration, same as display_name — a stale saved id from a build
## that shipped more skins can never break a peer.
var skin_id := SkinRegistry.DEFAULT_SKIN_ID


func _ready() -> void:
	_load()
	_apply_all()


func set_volume(bus_name: StringName, linear: float) -> void:
	volumes[bus_name] = clampf(linear, 0.0, 1.0)
	_apply_volume(bus_name)
	save()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.2, 3.0)
	save()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_fullscreen()
	save()


func set_last_join_code(ip: String) -> void:
	last_join_code = ip
	save()

func set_preferred_role(role: int) -> void:
	preferred_role = role
	save()

func set_display_name(value: String) -> void:
	display_name = value
	save()

func set_skin_id(value: String) -> void:
	skin_id = value
	save()


func save() -> void:
	var config := ConfigFile.new()
	for bus_name in volumes:
		config.set_value("audio", String(bus_name), volumes[bus_name])
	config.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("network", "last_join_code", last_join_code)
	config.set_value("game", "preferred_role", preferred_role)
	config.set_value("game", "display_name", display_name)
	config.set_value("game", "skin_id", skin_id)
	config.save(SAVE_PATH)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return # first run — defaults stand
	for bus_name in volumes:
		volumes[bus_name] = clampf(config.get_value("audio", String(bus_name), 1.0), 0.0, 1.0)
	mouse_sensitivity = clampf(config.get_value("input", "mouse_sensitivity", 1.0), 0.2, 3.0)
	fullscreen = config.get_value("display", "fullscreen", false)
	last_join_code = config.get_value("network", "last_join_code", "")
	preferred_role = config.get_value("game", "preferred_role", 0)
	display_name = config.get_value("game", "display_name", "")
	skin_id = config.get_value("game", "skin_id", SkinRegistry.DEFAULT_SKIN_ID)


func _apply_all() -> void:
	for bus_name in volumes:
		_apply_volume(bus_name)
	_apply_fullscreen()


func _apply_volume(bus_name: StringName) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	# Baseline mix level (0.0 for Master, AudioManager.BUSES for the rest)
	# plus the user's linear preference converted to dB. maxf keeps
	# linear_to_db away from -inf at slider zero — -60 dB is silent anyway.
	var base_db: float = 0.0 if bus_name == &"Master" else AudioManager.BUSES.get(bus_name, 0.0)
	AudioServer.set_bus_volume_db(idx, base_db + linear_to_db(maxf(volumes[bus_name], 0.001)))


func _apply_fullscreen() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
