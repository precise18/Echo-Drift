extends Area3D
class_name TeleportPad
## Single responsibility: teleport a player body to its linked pad when
## they step into this one. Two pads reference each other via
## `linked_pad` (wired by the map script right after both are created) —
## stepping into either sends you to the other, making this game's
## "echoes and reflection" theme a mechanic as well as a visual (see
## MAP_SYSTEM.md).
##
## Self-contained like EchoAudio: builds its own collision shape and
## glowing visual mesh in _ready() rather than requiring the map script
## to assemble them — a map just does `add_child(TeleportPad.new())` and
## sets `linked_pad` afterward.

const RADIUS := 1.1
const COOLDOWN_MSEC := 1000 # prevents instantly bouncing back through the pair

var linked_pad: TeleportPad = null
var pad_color := Color(0.55, 0.95, 1.0) # matches the echo ghost's cyan glow

var _cooldown_until: Dictionary = {} # CharacterBody3D -> ticks_msec they're clear to teleport again
var _sound_cooldown_until: Dictionary = {} # CharacterBody3D -> ticks_msec; rate-limits the whoosh only

var _whoosh: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # Players layer only
	body_entered.connect(_on_body_entered)
	_build_visuals()


func _build_visuals() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = 1.0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.5, 0)
	add_child(col)

	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS
	mesh.bottom_radius = RADIUS
	mesh.height = 0.1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(pad_color.r, pad_color.g, pad_color.b, 0.6)
	material.transparency = 1
	material.emission_enabled = true
	material.emission = pad_color
	material.emission_energy_multiplier = 1.2
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0, 0.05, 0)
	mesh_instance.material_override = material
	# A translucent glowing disc flat on the floor has no shadow worth
	# rendering — skip it in every shadow pass.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)

	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.6, 0)
	light.light_color = pad_color
	light.light_energy = 0.6
	light.omni_range = 3.0
	add_child(light)

	# Constant, cheap (small amount, capped lifetime) idle shimmer so the
	# pad reads as active/magical even before anyone steps on it.
	var idle_sparkles := MapKit.make_sparkle_particles(pad_color, 6, RADIUS * 0.7, "IdleSparkles")
	idle_sparkles.position = Vector3(0, 0.1, 0)
	add_child(idle_sparkles)

	_whoosh = AudioStreamPlayer3D.new()
	_whoosh.name = "Whoosh"
	_whoosh.stream = SoundFactory.teleport()
	_whoosh.bus = &"SFX"
	_whoosh.max_distance = 24.0
	_whoosh.position = Vector3(0, 0.5, 0)
	add_child(_whoosh)


func _on_body_entered(body: Node3D) -> void:
	if linked_pad == null or not (body is CharacterBody3D):
		return

	var now := Time.get_ticks_msec()

	# The whoosh plays on *every* peer, before the authority guard below:
	# body_entered fires everywhere (remote bodies' replicated positions
	# enter the area too), and a genuine teleport produces exactly one
	# entered event at each end — departure here, arrival at the linked
	# pad — so both players hear both ends positionally with no audio
	# networking. Rate-limited per body so an owner-side re-entry that's
	# still on teleport cooldown can at worst produce one stray whoosh.
	if _sound_cooldown_until.get(body, 0) <= now:
		_sound_cooldown_until[body] = now + COOLDOWN_MSEC
		_whoosh.play()

	if not body.is_multiplayer_authority():
		return # each peer only teleports the body it actually controls

	if _cooldown_until.get(body, 0) > now:
		return

	_spawn_activation_burst(global_position)
	body.global_position = linked_pad.global_position + Vector3(0, 0.1, 0)
	body.velocity = Vector3.ZERO
	linked_pad._cooldown_until[body] = now + COOLDOWN_MSEC
	linked_pad._spawn_activation_burst(linked_pad.global_position)


## A quick one-shot flourish at both ends of the jump — departure here,
## arrival at the linked pad — so the teleport reads as a distinct event
## rather than a silent teleport. Frees itself once finished (see
## MapKit.make_burst_particles).
func _spawn_activation_burst(at_position: Vector3) -> void:
	var burst := MapKit.make_burst_particles(pad_color, 16, "TeleportBurst")
	add_child(burst)
	burst.global_position = at_position + Vector3(0, 0.5, 0)
	burst.restart()
