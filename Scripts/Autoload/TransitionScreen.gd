extends CanvasLayer
## Autoload: the loading screen. A full-screen cover with a status line
## that snaps opaque the instant a scene change begins and fades out
## shortly after the new scene is up — so transitions read as a deliberate
## beat instead of a hard cut.
##
## Deliberately *never delays* the underlying scene change: joining
## clients must load Main.tscn immediately so its MultiplayerSpawner
## exists before spawn replication arrives (see NETWORKING_REPORT.md), so
## cover() just paints over that load rather than gating it. The cover
## also ignores mouse input, so it can never trap the game if something
## goes wrong underneath it.

const HOLD_TIME := 0.7 # scene loads are subsecond; hold just long enough to read
const FADE_TIME := 0.45

var _rect: ColorRect
var _label: Label
var _tween: Tween


func _ready() -> void:
	layer = 100
	_rect = ColorRect.new()
	_rect.color = UIKit.COLOR_BACKGROUND
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	add_child(_rect)

	_label = UIKit.make_title("", 24, UIKit.COLOR_ACCENT)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.add_child(_label)


## Call immediately before a scene change. Shows the cover at full
## opacity right now, then fades it out on its own once the new scene has
## had a moment to appear underneath.
func cover(message: String) -> void:
	if _tween != null:
		_tween.kill()
	_label.text = message
	_rect.modulate.a = 1.0
	_rect.visible = true
	_tween = create_tween()
	_tween.tween_interval(HOLD_TIME)
	_tween.tween_property(_rect, "modulate:a", 0.0, FADE_TIME)
	_tween.tween_callback(func() -> void: _rect.visible = false)
