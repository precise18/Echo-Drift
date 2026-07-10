extends Control
## Single responsibility: translate menu button presses into
## NetworkManager calls and surface connection errors to the player.

@onready var ip_field: LineEdit = $CenterContainer/VBoxContainer/IPField
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var host_button: Button = $CenterContainer/VBoxContainer/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinButton


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	NetworkManager.connection_failed.connect(_on_connection_failed)


func _on_host_pressed() -> void:
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
