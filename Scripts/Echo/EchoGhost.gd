extends Node3D
class_name EchoGhost
## Single responsibility: render one target's position, animation, and a
## positional audio cue from `delay_seconds` in the past, by reading from
## an EchoRecorder it doesn't own. Purely visual/audio — no collision, no
## gameplay authority, no recording logic of its own, and nothing here
## changes *when* a round is won or lost (see WinConditions, which never
## looks at a ghost). Multiple EchoGhost instances can point at the same
## EchoRecorder with different `delay_seconds` values to show several
## simultaneous echoes of one recorded history — see EchoSystem.gd and
## ECHO_SYSTEM.md.
##
## Every visual/audio effect below exists for one reason: a player should
## be able to tell "that's an echo" at a glance, instantly, without
## reading a UI element. See ECHO_VISUAL_GUIDE.md for the full breakdown
## of each effect and why it reads as supernatural rather than a visual
## bug.

const GHOST_CYAN := Color(0.55, 0.95, 1.0) # matches GlowLight / echo_ghost_material.tres
const GLOW_ENERGY_BASE := 0.8

## How long the spawn-pulse "materializing" tween and the dissolve
## "fading out" tween each take. Short and snappy on purpose — this is a
## state-change flourish, not something the player should have to wait
## through mid-round.
const SPAWN_PULSE_TIME := 0.45
const DISSOLVE_TIME := 0.4

const SPAWN_BURST_AMOUNT := 22
const DISSOLVE_BURST_AMOUNT := 14
const RIPPLE_PARTICLE_AMOUNT := 9

## Radians/second the ground ring spins at — slow enough to read as
## "ticking through recorded time," not a spinning-loading-icon.
const TIMELINE_RING_SPIN := 0.6

## Reported to the timeline label as "ECHO · Ns AGO". A proper setter
## (not a plain @export var) because EchoSystem sets this *after*
## add_child() — i.e. after _ready() has already built the label — so
## the label needs to react whenever the real value actually arrives,
## not just once at construction with the default.
@export var delay_seconds := 10.0:
	set(value):
		delay_seconds = value
		if _timeline_label != null:
			_timeline_label.text = "ECHO · %ds AGO" % int(round(delay_seconds))

var recorder: EchoRecorder = null

@onready var _anim_player: AnimationPlayer = $AnimPlayer
@onready var _audio: EchoAudio = $EchoAudio
@onready var _body_mesh: MeshInstance3D = $BodyMesh
@onready var _glow_light: OmniLight3D = $GlowLight

var _current_anim := ""
var _trail: GPUParticles3D
var _footsteps: FootstepEmitter
var _timeline_label: Label3D
var _timeline_ring: MeshInstance3D

## The ghost's own private copy of echo_ghost_material.tres — duplicated
## in _ready() specifically so multiple simultaneous echoes (see
## EchoSystem.echo_delays) never fight over one shared resource's
## `dissolve` shader parameter. Without the duplicate, a spawn-pulse or
## dissolve tween on one ghost would visibly yank every other ghost's
## opacity around too, since ShaderMaterial resources are shared by
## reference unless explicitly copied.
var _material: ShaderMaterial

var _active := false
var _fade_tween: Tween


func _ready() -> void:
	_material = _body_mesh.get_surface_override_material(0).duplicate()
	_body_mesh.set_surface_override_material(0, _material)

	# Feet-height so the trail reads as footsteps left behind, not a halo
	# around the ghost's body. World-space (see MapKit.make_trail_particles)
	# so it stays behind as the ghost moves along its recorded path.
	_trail = MapKit.make_trail_particles(GHOST_CYAN, 10, "Trail")
	_trail.position = Vector3(0, 0.1, 0)
	add_child(_trail)

	# The ghost's replayed movement gets footsteps too — same emitter as a
	# live player but with the reverberant echo variant, so a Hunter can
	# tell "real steps" from "echo steps" by ear (see SoundFactory.
	# echo_footstep). Off until the ghost is actually visible/replaying.
	_footsteps = FootstepEmitter.new()
	_footsteps.name = "EchoFootsteps"
	_footsteps.stream = SoundFactory.echo_footstep()
	_footsteps.active = false
	_footsteps.stepped.connect(_on_footstep)
	add_child(_footsteps)

	_timeline_label = _build_timeline_label()
	add_child(_timeline_label)

	_timeline_ring = _build_timeline_ring()
	add_child(_timeline_ring)


func _process(delta: float) -> void:
	_timeline_ring.rotate_y(delta * TIMELINE_RING_SPIN)

	if recorder == null or not recorder.has_enough_data():
		_set_active(false)
		return

	_set_active(true)
	# One buffer lookup per frame answers both position and animation
	# (see EchoRecorder.sample_at).
	var sample := recorder.sample_at(delay_seconds)
	global_transform = sample["xform"]
	_update_animation(sample["anim"])


func _update_animation(anim_name: String) -> void:
	if anim_name == "" or anim_name == _current_anim:
		return
	# Track the *requested* name (not the resolved clip) so an
	# unresolvable name is only searched once, not every frame.
	_current_anim = anim_name
	var clip := anim_name
	if not _anim_player.has_animation(clip):
		clip = _resolve_clip(anim_name)
	if clip != "":
		_anim_player.play(clip)


## Recorded animation names follow the recorded rig's own clip naming —
## with CharacterRig skins that's e.g. "CharacterArmature|Run", which
## doesn't literally exist in this ghost's own library (idle/walk/run
## from MovementAnimations.tres). Resolve by case-insensitive substring
## in either direction, the same trick CharacterRig itself uses to adopt
## inconsistently-named imported clips.
func _resolve_clip(anim_name: String) -> String:
	var lower := anim_name.to_lower()
	for clip in _anim_player.get_animation_list():
		if clip == "RESET":
			continue
		var clip_lower := String(clip).to_lower()
		if lower.contains(clip_lower) or clip_lower.contains(lower):
			return clip
	return ""


## Edge-triggered: only reacts on an actual HIDDEN<->ACTIVE transition,
## same as the original boolean check this replaced, but now dispatches
## to a tweened spawn/dissolve sequence instead of an instant
## visible = active pop.
func _set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	if active:
		_activate()
	else:
		_deactivate()


## The "materializing" moment: visible immediately (so the mesh, trail,
## and audio are all live from frame one) but faded in over
## SPAWN_PULSE_TIME via the shader's `dissolve` uniform, with a quick
## overshoot scale-up and a one-shot particle burst — see
## ECHO_VISUAL_GUIDE.md "Echo spawn pulse".
func _activate() -> void:
	visible = true
	_trail.emitting = true
	_footsteps.active = true
	_audio.begin()

	if _fade_tween != null:
		_fade_tween.kill()
	_material.set_shader_parameter("dissolve", 0.0)
	_body_mesh.scale = Vector3.ONE * 0.5
	_glow_light.light_energy = GLOW_ENERGY_BASE * 2.4

	var burst := MapKit.make_burst_particles(GHOST_CYAN, SPAWN_BURST_AMOUNT, "SpawnPulse")
	add_child(burst)
	burst.restart()

	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_method(_set_dissolve, 0.0, 1.0, SPAWN_PULSE_TIME).set_trans(Tween.TRANS_SINE)
	_fade_tween.tween_property(_body_mesh, "scale", Vector3.ONE, SPAWN_PULSE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(_glow_light, "light_energy", GLOW_ENERGY_BASE, SPAWN_PULSE_TIME * 1.4)


## The "dissolving" moment: fades the shader's `dissolve` uniform back to
## 0 and shrinks the mesh over DISSOLVE_TIME, with its own particle
## puff, THEN (only once both finish — see .chain() below) actually
## hides the node and silences its audio/trail/footsteps. This is what
## keeps a round-end or buffer-empty transition from looking like the
## ghost was switched off rather than fading away — see
## ECHO_VISUAL_GUIDE.md "Echo disappearance effect".
func _deactivate() -> void:
	if _fade_tween != null:
		_fade_tween.kill()

	var burst := MapKit.make_burst_particles(GHOST_CYAN, DISSOLVE_BURST_AMOUNT, "DissolvePulse")
	add_child(burst)
	burst.global_position = global_position + Vector3(0, 0.9, 0)
	burst.restart()

	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_method(_set_dissolve, 1.0, 0.0, DISSOLVE_TIME).set_trans(Tween.TRANS_SINE)
	_fade_tween.tween_property(_body_mesh, "scale", Vector3.ONE * 0.35, DISSOLVE_TIME).set_trans(Tween.TRANS_SINE)
	_fade_tween.chain().tween_callback(_finish_deactivate)


func _finish_deactivate() -> void:
	visible = false
	_trail.emitting = false
	_footsteps.active = false
	_audio.stop()
	_current_anim = ""


func _set_dissolve(value: float) -> void:
	_material.set_shader_parameter("dissolve", value)


## Spawns a ground ripple at the exact position/instant a footstep
## sound plays — see FootstepEmitter.stepped and
## MapKit.make_ripple_particles. Guarded on `visible` even though
## _footsteps.active already tracks _active, because a step that was
## already in flight when a dissolve starts should not spawn a ripple
## for a ghost that's mid-vanish.
func _on_footstep(ground_position: Vector3) -> void:
	if not visible:
		return
	var ripple := MapKit.make_ripple_particles(GHOST_CYAN, RIPPLE_PARTICLE_AMOUNT, "FootstepRipple")
	add_child(ripple)
	ripple.global_position = Vector3(ground_position.x, 0.05, ground_position.z)
	ripple.restart()


## The floating "ECHO · Ns AGO" tag — the single most direct answer to
## "is this an echo": it's a small billboarded readout, not a guess from
## body language. See ECHO_VISUAL_GUIDE.md "Echo replay timeline
## indicator".
func _build_timeline_label() -> Label3D:
	var label := Label3D.new()
	label.name = "TimelineLabel"
	label.position = Vector3(0, 2.15, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.no_depth_test = false
	label.double_sided = true
	label.font_size = 34
	label.outline_size = 10
	label.modulate = Color(0.65, 0.97, 1.0, 0.88)
	label.outline_modulate = Color(0.0, 0.05, 0.08, 0.85)
	label.pixel_size = 0.01
	label.text = "ECHO · %ds AGO" % int(round(delay_seconds))
	return label


## A slowly-spinning, flat cyan ring at the ghost's feet — reinforces
## "this is a moment in time being replayed" (it visually "ticks"),
## and doubles as a precise ground-contact marker that a plain
## translucent capsule alone doesn't give you. Plain unshaded
## StandardMaterial3D (not the distortion shader) so it stays a crisp,
## legible reference shape even while the body mesh is wobbling/pulsing.
func _build_timeline_ring() -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.5
	mesh.outer_radius = 0.62
	mesh.rings = 4
	mesh.ring_segments = 20

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = GHOST_CYAN
	material.emission_energy_multiplier = 1.6
	material.albedo_color = Color(GHOST_CYAN.r, GHOST_CYAN.g, GHOST_CYAN.b, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TimelineRing"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = Vector3(0, 0.04, 0)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance
