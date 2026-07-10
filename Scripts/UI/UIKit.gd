class_name UIKit
## The game's entire visual language for UI, in one place — the same role
## MapKit plays for map geometry and SoundFactory plays for audio: static
## builders that every screen composes, so all menus and HUD panels share
## one palette, one set of styleboxes, and one interaction feel (every
## button made here plays the UI hover/click sounds automatically).
## Change a color or corner radius here and the whole game follows.
## See UI_GUIDE.md.

# The palette. ACCENT is the echo-cyan used by the ghost, mirror pool and
# teleport pads — UI glow matches world glow, so menus feel like the same
# game. GOLD matches the capture burst: it always means "a result".
const COLOR_BACKGROUND := Color(0.055, 0.078, 0.102)
const COLOR_PANEL := Color(0.086, 0.114, 0.145, 0.96)
const COLOR_BUTTON := Color(0.13, 0.18, 0.235)
const COLOR_BUTTON_HOVER := Color(0.175, 0.245, 0.32)
const COLOR_BUTTON_PRESSED := Color(0.1, 0.14, 0.185)
const COLOR_ACCENT := Color(0.55, 0.95, 1.0)
const COLOR_TEXT := Color(0.87, 0.91, 0.94)
const COLOR_MUTED := Color(0.52, 0.6, 0.67)
const COLOR_GOLD := Color(1.0, 0.75, 0.3)
const COLOR_HIDER := Color(0.45, 0.7, 1.0)
const COLOR_HUNTER := Color(1.0, 0.5, 0.38)

## Set true by any HUD overlay that needs the OS cursor (pause, game
## over); PlayerController checks it before re-capturing the mouse on
## window focus, so alt-tabbing back never steals the cursor from a menu.
static var block_mouse_capture := false

static var _theme: Theme = null


## The one shared Theme. Built procedurally (no .tres to keep in sync
## with these constants) and cached; assign it to each UI root and every
## child Control inherits it.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()

	var button_normal := _flat_box(COLOR_BUTTON, Color(1, 1, 1, 0.06))
	var button_hover := _flat_box(COLOR_BUTTON_HOVER, Color(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.85))
	var button_pressed := _flat_box(COLOR_BUTTON_PRESSED, Color(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.5))
	for widget in ["Button", "OptionButton", "CheckButton"]:
		_theme.set_stylebox("normal", widget, button_normal)
		_theme.set_stylebox("hover", widget, button_hover)
		_theme.set_stylebox("pressed", widget, button_pressed)
		_theme.set_stylebox("focus", widget, button_hover)
		_theme.set_color("font_color", widget, COLOR_TEXT)
		_theme.set_color("font_hover_color", widget, Color.WHITE)
		_theme.set_color("font_pressed_color", widget, COLOR_ACCENT)
		_theme.set_color("font_focus_color", widget, Color.WHITE)
		_theme.set_color("font_disabled_color", widget, COLOR_MUTED)
		_theme.set_font_size("font_size", widget, 17)
	_theme.set_stylebox("disabled", "Button", _flat_box(Color(0.1, 0.13, 0.16), Color(1, 1, 1, 0.03)))

	var panel := _flat_box(COLOR_PANEL, Color(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.28))
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 22
	panel.content_margin_bottom = 22
	_theme.set_stylebox("panel", "PanelContainer", panel)

	var field := _flat_box(Color(0.06, 0.085, 0.11), Color(1, 1, 1, 0.1))
	field.content_margin_left = 12
	field.content_margin_right = 12
	_theme.set_stylebox("normal", "LineEdit", field)
	var field_focus := _flat_box(Color(0.06, 0.085, 0.11), Color(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.8))
	field_focus.content_margin_left = 12
	field_focus.content_margin_right = 12
	_theme.set_stylebox("focus", "LineEdit", field_focus)
	_theme.set_color("font_color", "LineEdit", COLOR_TEXT)
	_theme.set_font_size("font_size", "LineEdit", 17)

	_theme.set_color("font_color", "Label", COLOR_TEXT)
	_theme.set_font_size("font_size", "Label", 16)

	return _theme


static func _flat_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(7)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	return box


## Every interactive button in the game comes from here, which is what
## guarantees the interaction feel is uniform: same minimum size, same
## hover/click sounds, no per-screen audio wiring to forget.
static func make_button(text: String, min_width := 260.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width, 46)
	button.pressed.connect(AudioManager.play_click)
	button.mouse_entered.connect(AudioManager.play_hover)
	return button


static func make_title(text: String, font_size := 42, color := COLOR_ACCENT) -> Label:
	var label := make_label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func make_label(text: String, font_size := 16, color := COLOR_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Centered multi-line body text (credits, hints, descriptions).
static func make_paragraph(text: String, font_size := 15, color := COLOR_MUTED) -> Label:
	var label := make_label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(480, 0)
	return label


## A centered panel holding a VBox — the shape of every dialog in the
## game (lobby, pause, round end, game over, menu screens).
static func make_panel(separation := 14) -> Dictionary:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", separation)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	center.add_child(panel)
	return {"root": center, "panel": panel, "content": vbox}


## A labeled slider row for the settings panel. Returns the row plus the
## slider so callers can wire value_changed.
static func make_slider_row(label_text: String, min_value: float, max_value: float, value: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := make_label(label_text, 15, COLOR_MUTED)
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(220, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	return {"row": row, "slider": slider}
