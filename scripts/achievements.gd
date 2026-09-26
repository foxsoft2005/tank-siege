extends Node
## Autoload "Achievements": the list of achievements, unlocking them, and the
## "ACHIEVEMENT UNLOCKED" popup that slides in (in any scene).
##
## Two kinds:
##   * Counter achievements have a "stat" and a "goal". GameState.track() calls
##     on_stat() whenever a lifetime counter grows, and they unlock by themselves
##     ("Destroy 100 enemy tanks" watches the "kills" counter).
##   * Event achievements are unlocked from game code with
##     Achievements.unlock("eagle_eye") at the moment they happen.
##
## Unlocked ones are saved in GameState.achievements (id -> unix time).
## Runs with cheats don't unlock anything, except the ones marked cheat_ok.
##
## ADD YOUR OWN: add a line to LIST, then either give it a "stat" + "goal", or
## call Achievements.unlock("your_id") where it happens. That's it: the title
## screen page and the popup pick it up automatically.

signal unlocked(id: String)

enum Tier { BRONZE, SILVER, GOLD }
const TIER_COLORS := [Color("#d08a4a"), Color("#c9d3e0"), Color("#ffd23f")]

const LIST: Array[Dictionary] = [
	# --- combat
	{"id": "first_blood", "name": "First Blood", "desc": "Destroy your first enemy tank.", "tier": Tier.BRONZE, "stat": "kills", "goal": 1},
	{"id": "tank_buster", "name": "Tank Buster", "desc": "Destroy 100 enemy tanks.", "tier": Tier.SILVER, "stat": "kills", "goal": 100},
	{"id": "scrapyard", "name": "Scrapyard Legend", "desc": "Destroy 1,000 enemy tanks.", "tier": Tier.GOLD, "stat": "kills", "goal": 1000},
	{"id": "chain_5", "name": "Chain Reaction", "desc": "Reach a x5 combo.", "tier": Tier.BRONZE},
	{"id": "chain_12", "name": "LEGENDARY!", "desc": "Chain 12 kills in one combo.", "tier": Tier.GOLD},
	{"id": "bomb_squad", "name": "Bomb Squad", "desc": "Destroy 4 tanks with a single Bomb.", "tier": Tier.SILVER},
	{"id": "eagle_eye", "name": "Eagle Eye", "desc": "Destroy a Sniper while its laser is on you.", "tier": Tier.SILVER},
	{"id": "hot_potato", "name": "Hot Potato", "desc": "Shoot a Kamikaze after its fuse is lit.", "tier": Tier.BRONZE},
	{"id": "interceptor", "name": "Interceptor", "desc": "Shoot 25 enemy shells out of the air.", "tier": Tier.BRONZE, "stat": "cancels", "goal": 25},
	{"id": "fortress_breaker", "name": "Fortress Breaker", "desc": "Destroy the Fortress.", "tier": Tier.SILVER},
	{"id": "clear_skies", "name": "Clear Skies", "desc": "Shoot down the Sky Raider.", "tier": Tier.SILVER},
	# --- stage feats (checked when a stage is cleared)
	{"id": "untouchable", "name": "Untouchable", "desc": "Clear a stage without losing any armor.", "tier": Tier.SILVER},
	{"id": "sharpshooter", "name": "Sharpshooter", "desc": "Clear a stage with 80% accuracy (20+ shells).", "tier": Tier.SILVER},
	{"id": "speed_demon", "name": "Speed Demon", "desc": "Clear a stage in under 75 seconds.", "tier": Tier.SILVER},
	{"id": "ammo_miser", "name": "Ammo Miser", "desc": "Clear a stage firing fewer than 40 shells.", "tier": Tier.GOLD},
	{"id": "tiptoe", "name": "Tiptoe", "desc": "Clear a stage without breaking a single wall.", "tier": Tier.GOLD},
	{"id": "last_stand", "name": "Last Stand", "desc": "Clear a stage on your very last life.", "tier": Tier.BRONZE},
	{"id": "buddies", "name": "Brothers in Arms", "desc": "Clear a stage in co-op.", "tier": Tier.BRONZE},
	# --- progress
	{"id": "stage_5", "name": "Warming Up", "desc": "Reach stage 5.", "tier": Tier.BRONZE},
	{"id": "stage_10", "name": "Veteran", "desc": "Reach stage 10.", "tier": Tier.SILVER},
	{"id": "stage_20", "name": "Iron Will", "desc": "Reach stage 20.", "tier": Tier.GOLD},
	{"id": "hard_5", "name": "Hard Boiled", "desc": "Reach stage 5 on Hard.", "tier": Tier.GOLD},
	{"id": "fully_loaded", "name": "Fully Loaded", "desc": "Reach star level 3.", "tier": Tier.BRONZE},
	{"id": "collector", "name": "Collector", "desc": "Own 3 tanks in the Garage.", "tier": Tier.SILVER},
	{"id": "architect", "name": "Architect", "desc": "Beat a custom level.", "tier": Tier.BRONZE},
	# --- lifetime counters
	{"id": "demolition", "name": "Demolition Crew", "desc": "Smash 1,000 wall pieces.", "tier": Tier.SILVER, "stat": "bricks", "goal": 1000},
	{"id": "shopaholic", "name": "Shopaholic", "desc": "Collect 50 power-ups.", "tier": Tier.SILVER, "stat": "powerups", "goal": 50},
	{"id": "frequent_flyer", "name": "Frequent Flyer", "desc": "Use teleporters 25 times.", "tier": Tier.BRONZE, "stat": "teleports", "goal": 25},
	{"id": "barrel_laughs", "name": "Barrel of Laughs", "desc": "Blow up 25 barrels.", "tier": Tier.BRONZE, "stat": "barrels", "goal": 25},
	{"id": "never_give_up", "name": "Never Give Up", "desc": "Lose 50 tanks. It happens!", "tier": Tier.BRONZE, "stat": "deaths", "goal": 50},
	# --- secrets (the description stays hidden until you get them)
	{"id": "sunday_drive", "name": "Sunday Drive", "desc": "Survive 60 seconds of a stage without firing.", "tier": Tier.BRONZE, "secret": true},
	{"id": "cheater", "name": "Cheater, Cheater", "desc": "Enter a secret code.", "tier": Tier.BRONZE, "secret": true, "cheat_ok": true},
	{"id": "night_fever", "name": "Night Fever", "desc": "Destroy a tank with DISCO mode on.", "tier": Tier.BRONZE, "secret": true, "cheat_ok": true},
]

const TOAST_TIME := 3.2

var _by_id := {}
var _queue: Array[String] = []
var _layer: CanvasLayer
var _showing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # popups work while paused too
	for a in LIST:
		_by_id[a["id"]] = a
	_layer = CanvasLayer.new()
	_layer.layer = 100  # above everything, even the stats screen
	add_child(_layer)


func get_info(id: String) -> Dictionary:
	return _by_id.get(id, {})


func is_unlocked(id: String) -> bool:
	return GameState.achievements.has(id)


func unlocked_count() -> int:
	var n := 0
	for a in LIST:
		if is_unlocked(a["id"]):
			n += 1
	return n


## Unlock an achievement (does nothing if you already have it). Returns true
## if it was new.
func unlock(id: String) -> bool:
	if not _by_id.has(id):
		push_warning("Unknown achievement: " + id)
		return false
	if is_unlocked(id):
		return false
	if GameState.cheats_used and not _by_id[id].get("cheat_ok", false):
		return false
	GameState.achievements[id] = int(Time.get_unix_time_from_system())
	GameState.save_progress()
	unlocked.emit(id)
	_queue.append(id)
	if not _showing:
		_show_next()
	return true


## Called by GameState.track() when a lifetime counter changes.
func on_stat(key: String, total: int) -> void:
	for a in LIST:
		if a.get("stat", "") == key and total >= a["goal"]:
			unlock(a["id"])


## "37 / 100" style progress for counter achievements ("" for the others).
func progress_text(a: Dictionary) -> String:
	if not a.has("stat") or a["goal"] <= 1 or is_unlocked(a["id"]):
		return ""
	return "%d / %d" % [mini(GameState.lifetime.get(a["stat"], 0), a["goal"]), a["goal"]]


# ---------------------------------------------------------------- popup

## Drop waiting popups and quickly hide the one on screen (the stats screen
## lists new achievements itself, so the popups would just cover it).
func clear_toasts() -> void:
	_queue.clear()
	for toast in _layer.get_children():
		var tw := create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_property(toast, "modulate:a", 0.0, 0.15)

func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var a: Dictionary = _by_id[_queue.pop_front()]
	Sfx.play("achievement", 0.0, 0.0)

	var toast := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#15161ef0")
	style.border_color = TIER_COLORS[a["tier"]]
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	toast.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	toast.add_child(row)
	row.add_child(MedalIcon.new(a["tier"], true, 14.0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	col.add_child(_label("ACHIEVEMENT UNLOCKED", 10, TIER_COLORS[a["tier"]]))
	col.add_child(_label(a["name"], 16, Color.WHITE))
	col.add_child(_label(a["desc"], 10, Color("#c9ccd4")))
	_layer.add_child(toast)

	# Slide down from above the screen, wait, slide back up.
	toast.reset_size()
	await get_tree().process_frame
	toast.reset_size()
	var x := (512.0 - toast.size.x) / 2.0
	toast.position = Vector2(x, -toast.size.y - 4)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)  # hit-stop slow motion shouldn't freeze the popup
	tw.tween_property(toast, "position:y", 8.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(TOAST_TIME)
	tw.tween_property(toast, "position:y", -toast.size.y - 4, 0.25).set_ease(Tween.EASE_IN)
	await tw.finished
	toast.queue_free()
	_show_next()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
