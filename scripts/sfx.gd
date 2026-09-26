extends Node
## Autoload "Sfx": plays sound effects from anywhere with  Sfx.play("shoot").
##
## Why a pool of players? One AudioStreamPlayer plays one sound at a time.
## With a pool of them we can overlap sounds (4 tanks shooting at once) without
## creating and deleting nodes all the time.
##
## To replace a sound: drop your own .wav into assets/sfx/ with the same name.
## To add one: add the file, add its name to SOUND_NAMES, call Sfx.play("name").

## Every name here must match a file in assets/sfx/ (name.wav).
const SOUND_NAMES := [
	"shoot", "enemy_shoot", "drone_shoot",
	"hit_brick", "hit_steel", "bounce", "armor_hit",
	"explode_small", "explode_big", "shield_block",
	"powerup_appear", "powerup_pickup",
	"stage_start", "stage_clear", "game_over",
	"ui_move", "ui_pick", "pause", "cheat",
	"combo", "boss_warning", "boss_hit", "deflect", "repair", "fuse", "snipe", "scrap",
	"teleport",
]

const POOL_SIZE := 12
## The same sound can't start again within this many ms. Stops 4 explosions in
## one frame (Bomb power-up) from turning into one deafening blast.
const MIN_REPEAT_MS := 40

var muted := false
var _sounds := {}  # name -> AudioStream
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played := {}  # sound name -> time in ms


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # UI sounds must work while paused
	for sound_name in SOUND_NAMES:
		_sounds[sound_name] = load("res://assets/sfx/%s.wav" % sound_name)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"  # created by the Music autoload, which loads first
		add_child(p)
		_players.append(p)


## volume_db: 0 = normal, -6 = about half as loud.
## pitch_jitter: small random pitch change so repeated sounds don't feel robotic.
## pitch: 1 = normal, 2 = an octave higher (the combo sound rises with the combo).
func play(sound: String, volume_db := 0.0, pitch_jitter := 0.06, pitch := 1.0) -> void:
	if muted or not _sounds.has(sound):
		return
	var now := Time.get_ticks_msec()
	if now - _last_played.get(sound, -1000) < MIN_REPEAT_MS:
		return
	_last_played[sound] = now

	# Find a free player; if all are busy, reuse the oldest one.
	var player: AudioStreamPlayer = null
	for i in POOL_SIZE:
		var p := _players[(_next + i) % POOL_SIZE]
		if not p.playing:
			player = p
			break
	if player == null:
		player = _players[_next]
	_next = (_next + 1) % POOL_SIZE

	player.stream = _sounds[sound]
	player.volume_db = volume_db
	player.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	player.play()


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)  # bus 0 = Master (mutes everything)
