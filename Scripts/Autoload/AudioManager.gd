extends Node
## Autoload owning everything audio that isn't tied to a specific 3D
## position: the bus layout, the ambient music bed, the global wind
## ambience, UI sounds, and the round start/end/victory/defeat stings
## (driven off RoundManager's signals, which are already replicated to
## every peer — so no audio ever needs its own network message).
## Positional audio lives on the nodes it belongs to instead:
## FootstepEmitter on players/ghosts, TeleportPad's whoosh, the mirror
## pool's hum, EchoAudio on ghosts. See AUDIO_SYSTEM.md.

## Bus name -> default volume. Created at startup if missing, so every
## other audio node in the project can just set `bus = &"SFX"` etc.
## Levels are relative: music and ambience sit well under gameplay SFX,
## because footsteps are information in this game, not decoration.
const BUSES := {
	&"Music": -16.0,
	&"Ambience": -20.0,
	&"SFX": -8.0,
	&"UI": -10.0,
}

## Delay between the neutral round-end gong and the personal
## victory/defeat jingle, so they read as two beats: "it's over" ... "and
## you won/lost".
const VERDICT_DELAY := 0.8

var _music_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _click_player: AudioStreamPlayer
var _hover_player: AudioStreamPlayer
var _sting_player: AudioStreamPlayer
var _verdict_player: AudioStreamPlayer


func _ready() -> void:
	_setup_buses()

	_music_player = _make_player(SoundFactory.music_loop(), &"Music")
	_music_player.play()
	_wind_player = _make_player(SoundFactory.wind_loop(), &"Ambience")
	_wind_player.play()

	_click_player = _make_player(SoundFactory.ui_click(), &"UI")
	_hover_player = _make_player(SoundFactory.ui_hover(), &"UI")
	# Stings and verdict jingles get separate players so the victory/defeat
	# jingle can start while the round-end gong is still ringing out.
	_sting_player = _make_player(null, &"SFX")
	_verdict_player = _make_player(null, &"SFX")

	RoundManager.round_started.connect(_on_round_started)
	RoundManager.round_ended.connect(_on_round_ended)


func play_click() -> void:
	_click_player.play()


func play_hover() -> void:
	_hover_player.play()


func _on_round_started() -> void:
	_sting_player.stream = SoundFactory.round_start()
	_sting_player.play()


func _on_round_ended(winner_role: int) -> void:
	_sting_player.stream = SoundFactory.round_end()
	_sting_player.play()

	# Whether that gong was good news depends on which side *this* peer
	# was playing — every peer resolves it locally from the same replicated
	# round state.
	if multiplayer.multiplayer_peer == null:
		return
	var local_role: int = Role.HIDER if multiplayer.get_unique_id() == RoundManager.hider_id else Role.HUNTER
	var verdict := SoundFactory.victory() if winner_role == local_role else SoundFactory.defeat()
	get_tree().create_timer(VERDICT_DELAY).timeout.connect(func() -> void:
		_verdict_player.stream = verdict
		_verdict_player.play())


func _setup_buses() -> void:
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
		AudioServer.set_bus_volume_db(idx, BUSES[bus_name])


func _make_player(stream: AudioStream, bus_name: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus_name
	add_child(player)
	return player
