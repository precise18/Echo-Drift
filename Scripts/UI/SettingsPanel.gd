extends VBoxContainer
class_name SettingsPanel
## The settings controls themselves, with no window around them — so the
## exact same panel serves both the main menu's Settings screen and the
## in-game pause menu (see UI_GUIDE.md). Every control reads its starting
## value from GameSettings and writes back through its setters, which
## apply immediately (live audio preview while dragging) and persist.


func _ready() -> void:
	add_theme_constant_override("separation", 10)

	add_child(UIKit.make_label("AUDIO", 14, UIKit.COLOR_ACCENT))
	for bus_name: StringName in GameSettings.volumes:
		var row := UIKit.make_slider_row(String(bus_name), 0.0, 1.0, GameSettings.volumes[bus_name])
		var slider: HSlider = row["slider"]
		slider.value_changed.connect(func(value: float) -> void: GameSettings.set_volume(bus_name, value))
		# A click on release doubles as an instant "how loud is that" test
		# for the bus being adjusted (it plays through UI, close enough).
		slider.drag_ended.connect(func(changed: bool) -> void:
			if changed:
				AudioManager.play_click())
		add_child(row["row"])

	add_child(UIKit.make_label("CONTROLS", 14, UIKit.COLOR_ACCENT))
	var sensitivity := UIKit.make_slider_row("Mouse sensitivity", 0.2, 3.0, GameSettings.mouse_sensitivity)
	sensitivity["slider"].value_changed.connect(GameSettings.set_mouse_sensitivity)
	add_child(sensitivity["row"])

	add_child(UIKit.make_label("DISPLAY", 14, UIKit.COLOR_ACCENT))
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = GameSettings.fullscreen
	fullscreen.toggled.connect(GameSettings.set_fullscreen)
	fullscreen.pressed.connect(AudioManager.play_click)
	add_child(fullscreen)
