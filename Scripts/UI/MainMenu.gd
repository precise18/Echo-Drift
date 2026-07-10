extends Control
## Single responsibility: translate menu button presses into
## NetworkManager calls and surface connection errors to the player.

@onready var ip_field: LineEdit = $CenterContainer/VBoxContainer/IPField
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var host_button: Button = $CenterContainer/VBoxContainer/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinButton
@onready var map_option_button: OptionButton = $CenterContainer/VBoxContainer/MapRow/MapOptionButton


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	_populate_map_options()

	for button in [host_button, join_button]:
		button.pressed.connect(AudioManager.play_click)
		button.mouse_entered.connect(AudioManager.play_hover)
	map_option_button.item_selected.connect(func(_index: int) -> void: AudioManager.play_click())

	# Explains why the player landed back here instead of silently
	# dumping them at the menu — e.g. after the host disconnected. This
	# is the practical stand-in for host migration: no seamless handoff,
	# but a clear reason plus an immediate one-click "Host Game" to start
	# a fresh session (see NETWORKING_REPORT.md).
	if NetworkManager.last_disconnect_reason != "":
		status_label.text = NetworkManager.last_disconnect_reason
		NetworkManager.last_disconnect_reason = ""


## Only the host's selection matters (a joining client learns the active
## map from the host automatically — see MapManager/NETWORKING_REPORT.md)
## but the list is built from MapManager.get_map_ids() either way, so
## adding a new map later only means updating MapManager's registry —
## this menu never needs to change.
func _populate_map_options() -> void:
	map_option_button.clear()
	for map_id in MapManager.get_map_ids():
		map_option_button.add_item(MapManager.get_map_name(map_id))
		map_option_button.set_item_metadata(map_option_button.item_count - 1, map_id)
	var default_index := 0
	for i in map_option_button.item_count:
		if map_option_button.get_item_metadata(i) == MapManager.DEFAULT_MAP_ID:
			default_index = i
			break
	map_option_button.select(default_index)


func _on_host_pressed() -> void:
	var selected_index := map_option_button.selected
	if selected_index >= 0:
		MapManager.set_selected_map(map_option_button.get_item_metadata(selected_index))

	status_label.text = "Starting host..."
	var err := NetworkManager.host_game()
	if err != OK:
		status_label.text = "Could not host game (error %d). Is the port already in use?" % err


func _on_join_pressed() -> void:
	status_label.text = "Connecting..."
	var err := NetworkManager.join_game(ip_field.text.strip_edges())
	if err != OK:
		status_label.text = "Could not join game (error %d)." % err


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the IP address and that the host is running."
