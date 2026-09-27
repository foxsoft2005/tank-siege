extends Node
## Autoload (a "singleton"): Godot creates this once at startup and keeps it
## alive while scenes are reloaded. Access it anywhere as `GameState`.
## Anything that must survive between stages or scenes lives here.

const TITLE_SCENE := "res://scenes/title.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const EDITOR_SCENE := "res://scenes/editor.tscn"
const GARAGE_SCENE := "res://scenes/garage.tscn"
const SAVE_PATH := "user://save.cfg"

var stage: int = 1
# Per player (index 0 = Player 1, 1 = Player 2 in co-op)
var lives_p: Array[int] = [3, 0]
var stars_p: Array[int] = [0, 0]   # star level 0..3 from the STAR power-up
var coop := false                   # 2-player game?

## Player 1's lives / star level. (Kept as simple names because lots of
## single-player code uses them.)
var lives: int:
	get: return lives_p[0]
	set(value): lives_p[0] = value
var score: int = 0
var player_level: int:
	get: return stars_p[0]
	set(value): stars_p[0] = value
var best_combo := 0  # longest kill chain this run
var bosses_killed := 0
var upgrades: Dictionary = {}  # upgrade id -> level, e.g. {"ricochet": 2}
var run_seed := 0  # procedural levels: new random maps every run, fixed within a run

# Cheats. god_mode and disco are toggles that survive a restart.
var god_mode := false
var disco := false
var cheats_used := false

var debug_paths := false  # F3: show enemy AI paths (debug runs only)

# Custom levels (from the level editor). Empty custom_map = normal campaign.
var custom_map := PackedStringArray()
var custom_name := ""
var return_scene := TITLE_SCENE  # where to go after a custom level / "Main menu"
var editor_map := PackedStringArray()  # the editor's unsaved work, kept between scenes

# Saved to disk
var difficulty: int = Difficulty.Level.NORMAL  # saved; picked on the title screen
var high_scores := {}  # difficulty -> {"score": int, "stage": int}

# Meta-progression (saved): scrap currency, unlocked tanks, bought perks.
var scrap := 0
var total_scrap := 0
var runs := 0
var unlocked_tanks: Array = ["scout"]
var selected_tank := "scout"
var perks := {}  # perk id -> level

var _run_over := false  # so a run's rewards are only paid out once

# Statistics (see track()). Three sets of the same counters:
#   stage_stats - this stage only (the stats screen after a stage)
#   run_stats   - the whole run (the stats screen at game over)
#   lifetime    - every run ever, saved to disk (counter achievements)
# Keys are plain strings: "shots", "kills", "kills.fast", "bricks"... and
# the per-player copies "p0.shots", "p1.kills.fast" (for co-op columns).
var stage_stats := {}
var run_stats := {}
var lifetime := {}
var achievements := {}  # achievement id -> unix time it was unlocked (saved)
var run_achievements: Array[String] = []  # unlocked during this run (game over screen)


func _ready() -> void:
	_setup_input()
	load_progress()


func player_count() -> int:
	return 2 if coop else 1


## Start a normal run (stage 1).
func start_campaign() -> void:
	reset()
	custom_map = PackedStringArray()
	custom_name = ""
	return_scene = TITLE_SCENE
	get_tree().change_scene_to_file(GAME_SCENE)


## Play one custom level. `from_scene` is where to go afterwards.
func start_custom(map: PackedStringArray, level_name: String, from_scene: String) -> void:
	coop = false  # custom levels are single-player
	reset()
	custom_map = map
	custom_name = level_name
	return_scene = from_scene
	get_tree().change_scene_to_file(GAME_SCENE)


func is_custom() -> bool:
	return not custom_map.is_empty()


## A run is over (game over, restart or quit): save the high score and pay out
## scrap. Returns {"record": bool, "scrap": int}. Safe to call more than once.
## Custom levels and runs with cheats don't count.
func end_run() -> Dictionary:
	var result := {"record": false, "scrap": 0}
	if _run_over or is_custom() or cheats_used:
		return result
	_run_over = true
	var best := record_for(difficulty)
	result["record"] = score > best["score"]
	high_scores[difficulty] = {"score": maxi(best["score"], score), "stage": maxi(best["stage"], stage)}
	var earned := int(Garage.scrap_for_run(score, stage, best_combo, bosses_killed, perk("scrap_magnet")) * diff("scrap"))
	scrap += earned
	total_scrap += earned
	runs += 1
	result["scrap"] = earned
	save_progress()
	return result


# ---------------------------------------------------------------- difficulty

## A setting for the current difficulty, e.g. diff("enemy_speed"). See difficulty.gd.
func diff(key: String) -> Variant:
	return Difficulty.SETTINGS[difficulty][key]


## Best score and stage reached on a difficulty.
func record_for(d: int) -> Dictionary:
	return high_scores.get(d, {"score": 0, "stage": 0})


# ---------------------------------------------------------------- garage

## Stats of the tank you picked in the Garage (see garage.gd).
func tank_stat(key: String) -> Variant:
	return Garage.stat(selected_tank, key)


func perk(id: String) -> int:
	return perks.get(id, 0)


## Spend scrap. Returns false if you can't afford it.
func try_spend(amount: int) -> bool:
	if amount < 0 or scrap < amount:
		return false
	scrap -= amount
	save_progress()
	return true


func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "high_scores", high_scores)
	cfg.set_value("progress", "difficulty", difficulty)
	cfg.set_value("meta", "scrap", scrap)
	cfg.set_value("meta", "total_scrap", total_scrap)
	cfg.set_value("meta", "runs", runs)
	cfg.set_value("meta", "unlocked_tanks", unlocked_tanks)
	cfg.set_value("meta", "selected_tank", selected_tank)
	cfg.set_value("meta", "perks", perks)
	cfg.set_value("stats", "lifetime", lifetime)
	cfg.set_value("stats", "achievements", achievements)
	cfg.save(SAVE_PATH)


func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	high_scores = cfg.get_value("progress", "high_scores", {})
	difficulty = cfg.get_value("progress", "difficulty", Difficulty.Level.NORMAL)
	if cfg.has_section_key("progress", "high_score"):  # save from an older version
		high_scores[Difficulty.Level.NORMAL] = {"score": cfg.get_value("progress", "high_score", 0),
			"stage": cfg.get_value("progress", "best_stage", 0)}
	scrap = cfg.get_value("meta", "scrap", 0)
	total_scrap = cfg.get_value("meta", "total_scrap", 0)
	runs = cfg.get_value("meta", "runs", 0)
	unlocked_tanks = cfg.get_value("meta", "unlocked_tanks", ["scout"])
	selected_tank = cfg.get_value("meta", "selected_tank", "scout")
	perks = cfg.get_value("meta", "perks", {})
	lifetime = cfg.get_value("stats", "lifetime", {})
	achievements = cfg.get_value("stats", "achievements", {})
	if not Garage.TANKS.has(selected_tank) or selected_tank not in unlocked_tanks:
		selected_tank = "scout"


## Start of a run: stats back to zero, plus your Garage bonuses.
func reset() -> void:
	stage = 1
	lives_p[0] = maxi(3 + perk("extra_life") + int(tank_stat("lives")) + int(diff("lives")), 1)
	lives_p[1] = maxi(3 + perk("extra_life") + int(diff("lives")), 1) if coop else 0  # P2 drives a Scout
	stars_p = [0, 0]
	score = 0
	best_combo = 0
	bosses_killed = 0
	upgrades.clear()
	cheats_used = god_mode or disco
	_run_over = false
	run_seed = randi()
	run_stats = {}
	stage_stats = {}
	run_achievements.clear()
	if perk("head_start") > 0:  # a free common card to start with
		var commons: Array[String] = []
		for id: String in Upgrades.ALL:
			if Upgrades.ALL[id]["rarity"] == Upgrades.Rarity.COMMON and id != "field_repair":
				commons.append(id)
		add_upgrade(commons.pick_random())


# ---------------------------------------------------------------- statistics

## Count something that happened: GameState.track("shots"), or
## GameState.track("kills.fast", 1, 0) for a kill by Player 1.
## `player` >= 0 also counts it in that player's own column ("p0.kills.fast").
## Lifetime totals (and the achievements that watch them) only count in
## runs without cheats, so KABOOM can't farm "destroy 1000 tanks".
func track(key: String, amount := 1, player := -1) -> void:
	_bump(key, amount, true)
	if player >= 0:
		_bump("p%d.%s" % [player, key], amount, false)


func _bump(key: String, amount: int, count_lifetime: bool) -> void:
	stage_stats[key] = stage_stats.get(key, 0) + amount
	run_stats[key] = run_stats.get(key, 0) + amount
	if count_lifetime and not cheats_used:
		lifetime[key] = lifetime.get(key, 0) + amount
		Achievements.on_stat(key, lifetime[key])


## Remember the biggest value seen, e.g. the best combo of the stage.
func track_max(key: String, value: int) -> void:
	stage_stats[key] = maxi(stage_stats.get(key, 0), value)
	run_stats[key] = maxi(run_stats.get(key, 0), value)


## Read a counter. `which` is stage_stats, run_stats or lifetime.
static func stat(which: Dictionary, key: String, player := -1) -> int:
	return which.get(key if player < 0 else "p%d.%s" % [player, key], 0)


## The map for the current stage: a custom level, a procedural one (if that
## option is on), or the handmade stage. Boss stages always use their arena.
func current_map() -> PackedStringArray:
	if is_custom():
		return custom_map
	if Settings.procedural_levels and not LevelData.is_boss_stage(stage):
		return LevelGen.generate(stage, hash([run_seed, stage]))
	return LevelData.get_map(stage)


## Level of an upgrade you own (0 = don't have it). See upgrades.gd.
func stacks(id: String) -> int:
	return upgrades.get(id, 0)


func add_upgrade(id: String) -> void:
	upgrades[id] = stacks(id) + 1
	if id == "field_repair":
		lives += 1


## Input actions are usually made in Project > Project Settings > Input Map.
## We define them in code here so you can see everything in one place.
## physical_keycode = the key's position, so WASD works on any keyboard layout.
func _setup_input() -> void:
	_add_action("move_up", [KEY_W, KEY_UP], JOY_BUTTON_DPAD_UP)
	_add_action("move_down", [KEY_S, KEY_DOWN], JOY_BUTTON_DPAD_DOWN)
	_add_action("move_left", [KEY_A, KEY_LEFT], JOY_BUTTON_DPAD_LEFT)
	_add_action("move_right", [KEY_D, KEY_RIGHT], JOY_BUTTON_DPAD_RIGHT)
	_add_action("fire", [KEY_SPACE, KEY_J], JOY_BUTTON_A)
	_add_action("pause", [KEY_P, KEY_ESCAPE], JOY_BUTTON_START)
	_add_action("restart", [KEY_ENTER, KEY_KP_ENTER], JOY_BUTTON_START)
	_add_action("mute", [KEY_M])
	_add_action("toggle_music", [KEY_N])
	# Cheat for testing: F2 clears the stage instantly (only works in debug runs).
	_add_action("debug_clear_stage", [KEY_F2])
	_add_action("debug_paths", [KEY_F3])

	# Co-op: each player gets their own set of keys, and their own gamepad
	# (device 0 = first pad, device 1 = second pad).
	_add_action("p1_up", [KEY_W], JOY_BUTTON_DPAD_UP, 0)
	_add_action("p1_down", [KEY_S], JOY_BUTTON_DPAD_DOWN, 0)
	_add_action("p1_left", [KEY_A], JOY_BUTTON_DPAD_LEFT, 0)
	_add_action("p1_right", [KEY_D], JOY_BUTTON_DPAD_RIGHT, 0)
	_add_action("p1_fire", [KEY_SPACE, KEY_J], JOY_BUTTON_A, 0)
	_add_action("p2_up", [KEY_UP], JOY_BUTTON_DPAD_UP, 1)
	_add_action("p2_down", [KEY_DOWN], JOY_BUTTON_DPAD_DOWN, 1)
	_add_action("p2_left", [KEY_LEFT], JOY_BUTTON_DPAD_LEFT, 1)
	_add_action("p2_right", [KEY_RIGHT], JOY_BUTTON_DPAD_RIGHT, 1)
	_add_action("p2_fire", [KEY_ENTER, KEY_KP_0, KEY_CTRL], JOY_BUTTON_A, 1)


## device: which gamepad (-1 = any gamepad).
func _add_action(action: String, keys: Array, pad_button := JOY_BUTTON_INVALID, device := -1) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key: Key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	if pad_button == JOY_BUTTON_INVALID:
		return
	var pad := InputEventJoypadButton.new()
	pad.button_index = pad_button
	pad.device = device
	InputMap.action_add_event(action, pad)
