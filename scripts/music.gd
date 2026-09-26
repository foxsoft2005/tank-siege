extends Node
## Autoload "Music": background music with fades, plus the audio bus setup.
##
##   Music.play("battle_a")      fade to a track (does nothing if already playing)
##   Music.stop()                fade out
##   Music.set_muffled(true)     "underwater" filter, used while paused
##
## Audio buses are like channels on a mixing desk. We make two, "Music" and
## "SFX", both feeding into "Master". That way music and effects can have
## separate volumes, and we can put a filter on the music only.
## (You can also build buses visually in the editor's Audio tab.)

const TRACKS := ["battle_a", "battle_b", "upgrade", "boss"]
const VOLUME_DB := -7.0  # music sits a bit below the sound effects

var enabled := true
var current := ""

var _player: AudioStreamPlayer
var _streams := {}
var _tween: Tween
var _bus := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep playing while the game is paused
	_setup_buses()

	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	add_child(_player)

	for track in TRACKS:
		var stream: AudioStream = load("res://assets/music/%s.ogg" % track)
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true  # loop forever
		_streams[track] = stream


func _setup_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	_bus = AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(_bus, VOLUME_DB)
	# Low-pass filter (cuts the high frequencies), switched on while paused.
	var muffle := AudioEffectLowPassFilter.new()
	muffle.cutoff_hz = 700.0
	AudioServer.add_bus_effect(_bus, muffle)
	AudioServer.set_bus_effect_enabled(_bus, 0, false)


func play(track: String, fade_time := 0.8) -> void:
	if track == current and _player.playing:
		return
	current = track
	_kill_tween()
	_tween = create_tween()
	if _player.playing:  # fade the old track out first
		_tween.tween_property(_player, "volume_db", -40.0, fade_time * 0.5)
	_tween.tween_callback(func() -> void:
		_player.stream = _streams[track]
		_player.volume_db = -40.0
		_player.play())
	_tween.tween_property(_player, "volume_db", 0.0, fade_time)


func stop(fade_time := 0.8) -> void:
	current = ""
	if not _player.playing:
		return
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", -40.0, fade_time)
	_tween.tween_callback(_player.stop)


func set_muffled(on: bool) -> void:
	AudioServer.set_bus_effect_enabled(_bus, 0, on)


func toggle() -> void:
	enabled = not enabled
	AudioServer.set_bus_mute(_bus, not enabled)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
