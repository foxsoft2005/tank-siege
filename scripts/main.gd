extends Node2D
## Main: the "game director". Builds the stage, spawns tanks, keeps score,
## handles power-ups, pause, stage clear (+ upgrade cards) and game over.
##
## Scene tree built at runtime:
##   Main (this, always processes so pause/restart work)
##   ├─ Camera2D            (screen shake)
##   ├─ World               (everything that pauses)
##   │   ├─ Level           (walls, bushes, border)
##   │   ├─ Base, Player, Enemies, Bullets, PowerUps, particles
##   ├─ HUD (CanvasLayer)   (UI, drawn on top, not affected by the camera)
##   ├─ CheatCodes          (listens for secret codes)
##   ├─ PauseMenu           (only while paused)
##   └─ UpgradeScreen       (only between stages)

enum State { PLAYING, STAGE_CLEAR, GAME_OVER }

const ENEMIES_PER_STAGE := 20
const BOSS_STAGE_ESCORTS := 8  # regular enemies on a boss stage
const MAX_ENEMIES_ON_SCREEN := 4
const SPAWN_INTERVAL := 2.5
const BONUS_ENEMY_NUMBERS := [4, 11, 18]  # these spawn as red bonus tanks

## Combo: kills less than COMBO_WINDOW seconds apart build a chain.
## Every kill in the chain is worth base points x the chain length (max x8).
const COMBO_WINDOW := 2.5
const MAX_MULTIPLIER := 8

var state := State.PLAYING
var world: Node2D
var level: Level
var base: Base
var players: Array = [null, null]  # Player 1 and (in co-op) Player 2
var player: Player:  # Player 1, for code that only cares about one player
	get: return players[0]
var camera: Camera2D

var enemies_quota := ENEMIES_PER_STAGE  # how many regular enemies this stage sends
var boss: Boss = null
var boss_stage := false
var boss_delay := 0.0  # countdown until the boss appears
var max_on_screen := MAX_ENEMIES_ON_SCREEN  # set from the difficulty
var enemies_spawned := 0
var enemies_alive := 0
var spawn_timer := 1.0
var spawn_index := 0
var freeze_time := 0.0
var fortify_time := 0.0
var shake := 0.0
var music_delay := 0.9  # start the music once the stage jingle has finished

var stage_time := 0.0   # seconds played this stage (for the stats screen)
var _stage_start_score := 0
var _stage_achievements: Array[String] = []  # unlocked during this stage

var combo := 0          # kills in the current chain
var combo_timer := 0.0  # seconds left before the chain breaks
var _hitstop_end := 0   # real-time msec when the hit-stop freeze ends

var _info_label: Label
var _upgrades_label: Label
var _combo_label: Label
var _combo_bar: ColorRect
var _status_label: Label
var _diff_label: Label
var _boss_bar: Control
var _boss_fill: ColorRect
var _message_label: Label
var _pause_menu: PauseMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()

	camera = Camera2D.new()
	camera.position = Vector2(256, 208)  # centre of the 512x416 screen
	add_child(camera)

	world = Node2D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel art (children inherit)
	add_child(world)

	level = Level.new()
	world.add_child(level)
	level.barrel_exploded.connect(func(_pos: Vector2) -> void:
		shake = maxf(shake, 9.0)
		GameState.track("barrels"))
	GameState.stage_stats = {}  # fresh numbers for this stage's stats screen
	_stage_start_score = GameState.score
	Achievements.unlocked.connect(func(id: String) -> void:
		_stage_achievements.append(id)
		GameState.run_achievements.append(id))
	_check_progress_achievements()
	# A custom level from the editor, or the next campaign stage.
	boss_stage = not GameState.is_custom() and LevelData.is_boss_stage(GameState.stage)
	level.build(GameState.current_map())
	if boss_stage:
		enemies_quota = BOSS_STAGE_ESCORTS
		boss_delay = 3.0
	max_on_screen = GameState.diff("max_on_screen") + (1 if GameState.coop else 0)

	base = Base.new()
	base.position = Level.BASE_POS
	base.shield_hits = GameState.stacks("core_shield")
	base.destroyed.connect(_on_base_destroyed)
	base.shield_broken.connect(func() -> void: shake = 6.0)
	world.add_child(base)

	_build_hud()
	var cheats := CheatCodes.new()
	cheats.code_entered.connect(_on_cheat)
	add_child(cheats)
	for i in GameState.player_count():
		_spawn_player(i)
	if boss_stage:
		var incoming: String = "FORTRESS APPROACHING" if _boss_kind() == 0 else "GUNSHIP INCOMING"
		_show_message("STAGE %d\n\nWARNING!\n%s" % [GameState.stage, incoming], 2.8)
		Sfx.play("boss_warning", -2.0, 0.0)
	else:
		_show_message(GameState.custom_name.to_upper() if GameState.is_custom() else "STAGE %d" % GameState.stage, 1.5)
		Sfx.play("stage_start", -2.0, 0.0)
	Music.set_muffled(false)


func _process(delta: float) -> void:
	# End the hit-stop once enough REAL time has passed. (delta itself is slowed
	# down during the hit-stop, so we use the wall clock instead.)
	if _hitstop_end > 0 and Time.get_ticks_msec() >= _hitstop_end:
		_hitstop_end = 0
		Engine.time_scale = 1.0

	# Shake the camera, then ease it back to zero.
	var amount := shake if Settings.screen_shake else 0.0
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount
	shake = move_toward(shake, 0.0, delta * 25.0)
	_update_hud()

	if music_delay > 0.0:
		music_delay -= delta
		if music_delay <= 0.0 and state == State.PLAYING:
			# Odd and even stages get different songs; bosses get their own.
			if boss_stage:
				Music.play("boss")
			else:
				Music.play("battle_a" if GameState.stage % 2 == 1 else "battle_b")

	if get_tree().paused or state != State.PLAYING:
		return

	stage_time += delta
	# Secret achievement: a whole minute on the battlefield without firing.
	if stage_time >= 60.0 and GameState.stat(GameState.stage_stats, "shots") == 0 and _alive_players().size() > 0:
		Achievements.unlock("sunday_drive")

	if boss_delay > 0.0:
		boss_delay -= delta
		if boss_delay <= 0.0:
			_spawn_boss()

	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			_end_combo()

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = GameState.diff("spawn_interval")
		if enemies_spawned < enemies_quota and enemies_alive < max_on_screen:
			_try_spawn_enemy()

	if freeze_time > 0.0:
		freeze_time -= delta
		if freeze_time <= 0.0:
			_set_enemies_frozen(false)

	if fortify_time > 0.0:
		fortify_time -= delta
		if fortify_time <= 0.0:
			level.set_base_walls(Wall.Kind.BRICK)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and state == State.PLAYING:
		if _pause_menu:
			_pause_menu.back()  # Options page -> main page -> close
		else:
			_open_pause_menu()
	elif event.is_action_pressed("toggle_music"):
		Music.toggle()
		if state == State.PLAYING and not get_tree().paused:
			_show_message("MUSIC ON" if Music.enabled else "MUSIC OFF", 0.8)
	elif event.is_action_pressed("mute"):
		Sfx.toggle_mute()
		if state == State.PLAYING and not get_tree().paused:
			_show_message("SOUND OFF" if Sfx.muted else "SOUND ON", 0.8)
	# (At game over, Retry / Main menu are buttons on the stats screen. There
	# used to be Enter / Esc shortcuts here too, but Enter on the "Main menu"
	# button also triggered the Enter = retry shortcut and started a new game.)
	elif event.is_action_pressed("debug_clear_stage") and OS.is_debug_build() and state == State.PLAYING:
		_skip_stage()  # testing shortcut: F2
	elif event.is_action_pressed("debug_paths") and OS.is_debug_build():
		GameState.debug_paths = not GameState.debug_paths  # F3: show enemy AI paths


# ---------------------------------------------------------------- pause menu

func _open_pause_menu() -> void:
	get_tree().paused = true
	Music.set_muffled(true)
	Sfx.play("pause", 0.0, 0.0)
	_pause_menu = PauseMenu.new()
	_pause_menu.resumed.connect(_on_resumed)
	_pause_menu.restart_requested.connect(func() -> void:
		get_tree().paused = false
		GameState.end_run()
		GameState.reset()
		get_tree().reload_current_scene())
	_pause_menu.menu_requested.connect(func() -> void:
		get_tree().paused = false
		GameState.end_run()
		Music.stop(0.3)
		get_tree().change_scene_to_file(GameState.return_scene))
	add_child(_pause_menu)


func _on_resumed() -> void:
	_pause_menu = null
	get_tree().paused = false
	Music.set_muffled(false)


# ---------------------------------------------------------------- secret codes

func _on_cheat(id: String) -> void:
	if state != State.PLAYING:
		return
	GameState.cheats_used = true
	Sfx.play("cheat", 0.0, 0.0)
	Achievements.unlock("cheater")
	var text := ""
	match id:
		"god_mode":
			GameState.god_mode = not GameState.god_mode
			text = "GOD MODE " + ("ON" if GameState.god_mode else "OFF")
		"lives":
			for i in GameState.player_count():
				GameState.lives_p[i] += 30
			text = "+30 LIVES"
		"max_power":
			GameState.stars_p = [3, 3]
			for p in _alive_players():
				p.refresh_upgrades()  # new shape, perks AND the extra armor
			text = "MAX POWER"
		"kaboom":
			shake = 10.0
			_kill_all_enemies()
			text = "KABOOM!"
		"fortress":
			fortify_time = 0.0  # 0 = never turns back to brick this stage
			level.set_base_walls(Wall.Kind.STEEL)
			base.shield_hits += 3
			text = "FORTRESS"
		"skip":
			if _pause_menu:
				_pause_menu.back()
			text = "SHORTCUT"
			_skip_stage()
		"loot":
			var names: Array[String] = []
			for i in 3:
				var picks := Upgrades.roll_choices(GameState.upgrades, 1)
				if picks.is_empty():
					break
				GameState.add_upgrade(picks[0])
				if picks[0] == "core_shield":
					base.shield_hits += 1
				names.append(Upgrades.ALL[picks[0]]["name"])
			for p in _alive_players():
				p.refresh_upgrades()
			text = "LOOT!\n" + "\n".join(names)
		"disco":
			GameState.disco = not GameState.disco
			text = "DISCO " + ("ON" if GameState.disco else "OFF")
	if state == State.PLAYING:
		_show_message("CHEAT: " + text, 1.8)


func _skip_stage() -> void:
	enemies_spawned = enemies_quota
	boss_delay = 0.0
	_kill_all_enemies(true)
	_check_stage_clear()


# ---------------------------------------------------------------- spawning

func _spawn_player(index: int) -> void:
	var p := Player.new(index)
	p.position = Level.PLAYER_SPAWN if index == 0 else Level.PLAYER2_SPAWN
	p.invulnerable_time = 3.0  # spawn shield
	p.died.connect(_on_player_died)
	world.add_child(p)
	players[index] = p


func _alive_players() -> Array[Player]:
	var out: Array[Player] = []
	for p in players:
		if is_instance_valid(p) and not p._dead:
			out.append(p)
	return out


func _try_spawn_enemy(counts_toward_quota := true, forced_kind := -1) -> void:
	# Try the spawn points in rotation; skip any that are occupied.
	# (On boss stages the middle one is the boss's entrance.)
	var spawns: Array[Vector2] = Level.ENEMY_SPAWNS
	if boss_stage:
		spawns = [Level.ENEMY_SPAWNS[0], Level.ENEMY_SPAWNS[2]]
	for i in spawns.size():
		var p: Vector2 = spawns[(spawn_index + i) % spawns.size()]
		if _spot_is_free(p):
			spawn_index = (spawn_index + i + 1) % spawns.size()
			if counts_toward_quota:
				enemies_spawned += 1
			var kind: Enemy.Kind = _pick_enemy_kind() if forced_kind < 0 else forced_kind as Enemy.Kind
			var e := Enemy.create(kind)  # special kinds are their own subclass
			var bonus := counts_toward_quota and enemies_spawned in BONUS_ENEMY_NUMBERS
			e.setup(kind, bonus, _pick_brain(kind))
			e.position = p
			e.target = Level.BASE_POS
			e.frozen = freeze_time > 0.0
			e.died.connect(_on_enemy_died)
			world.add_child(e)
			enemies_alive += 1
			# Fade in, so enemies don't just pop into existence.
			e.modulate.a = 0.0
			create_tween().tween_property(e, "modulate:a", 1.0, 0.4)
			return


func _spot_is_free(p: Vector2) -> bool:
	for t in get_tree().get_nodes_in_group("tanks"):
		if (t as Node2D).position.distance_to(p) < 34.0:
			return false
	return true


## Later stages send tougher enemies, and new kinds join in over time:
## kamikazes from stage 2, snipers from stage 3, shielded tanks and
## engineers from stage 4. Each kind has a "weight": bigger = more common.
func _pick_enemy_kind() -> Enemy.Kind:
	var s := GameState.stage
	var weights := {
		Enemy.Kind.BASIC: 40.0,
		Enemy.Kind.FAST: 20.0,
		Enemy.Kind.POWER: 10.0 + 4.0 * s,
		Enemy.Kind.ARMOR: 5.0 + 5.0 * s,
	}
	if s >= 2:
		weights[Enemy.Kind.KAMIKAZE] = minf(6.0 + 2.0 * s, 16.0)
	if s >= 3:
		weights[Enemy.Kind.SNIPER] = 8.0
	if s >= 4:
		weights[Enemy.Kind.SHIELDED] = 10.0
		weights[Enemy.Kind.ENGINEER] = 6.0
	var total := 0.0
	for w: float in weights.values():
		total += w
	var roll := randf() * total
	for kind: Enemy.Kind in weights:
		roll -= weights[kind]
		if roll <= 0.0:
			return kind
	return Enemy.Kind.BASIC


## Which AI each enemy gets. Fast tanks hunt you, armored tanks go for the
## base, and basic tanks mostly wander (less and less on later stages).
## Only a few raiders are allowed at once, so the base isn't overrun instantly:
## 1 on stages 1-2, 2 on stages 3-5, 3 after that.
func _pick_brain(kind: Enemy.Kind) -> Enemy.Brain:
	var raiders := 0
	for t in get_tree().get_nodes_in_group("tanks"):
		if t is Enemy and (t as Enemy).brain == Enemy.Brain.RAIDER:
			raiders += 1
	var raid_ok := raiders < maxi(1 + GameState.stage / 3 + int(GameState.diff("raid_bonus")), 1)

	var wanted := Enemy.Brain.WANDER
	match kind:
		Enemy.Kind.FAST:
			wanted = Enemy.Brain.HUNTER
		Enemy.Kind.ARMOR, Enemy.Kind.SHIELDED:
			wanted = Enemy.Brain.RAIDER
		Enemy.Kind.POWER:
			wanted = Enemy.Brain.RAIDER if randf() < 0.5 else Enemy.Brain.HUNTER
		Enemy.Kind.BASIC:
			var smart_chance := minf(0.15 + 0.1 * GameState.stage, 0.6)
			if randf() < smart_chance:
				wanted = Enemy.Brain.RAIDER if randf() < 0.5 else Enemy.Brain.HUNTER
	if wanted == Enemy.Brain.RAIDER and not raid_ok:
		wanted = Enemy.Brain.WANDER
	return wanted


# ---------------------------------------------------------------- events

func _on_enemy_died(tank: Tank) -> void:
	var e := tank as Enemy
	enemies_alive -= 1
	_track_kill(e, "kills." + (Enemy.Kind.keys()[e.kind] as String).to_lower())
	_register_kill(e.position, e.points)
	shake = maxf(shake, 4.0)
	if e.is_bonus:
		_drop_powerup()
	_check_stage_clear()


## Stats: count a destroyed enemy (for the player whose shell got it, if any)
## and check the achievements that care HOW it was destroyed.
func _track_kill(t: Tank, kind_key: String) -> void:
	var who := t.last_hit_by
	GameState.track("kills", 1, who)
	GameState.track(kind_key, 1, who)
	if who < 0:
		return
	if t is SniperEnemy and (t as SniperEnemy)._aim > 0.0:
		Achievements.unlock("eagle_eye")
	if t is KamikazeEnemy and (t as KamikazeEnemy)._fuse >= 0.0:
		Achievements.unlock("hot_potato")
	if GameState.disco:
		Achievements.unlock("night_fever")


## "Reach stage N" achievements, checked as each stage starts.
func _check_progress_achievements() -> void:
	if GameState.is_custom():
		return
	var s := GameState.stage
	if s >= 5:
		Achievements.unlock("stage_5")
		if GameState.difficulty == Difficulty.Level.HARD:
			Achievements.unlock("hard_5")
	if s >= 10:
		Achievements.unlock("stage_10")
	if s >= 20:
		Achievements.unlock("stage_20")


## Stage-feat achievements, checked when a stage is cleared. (Custom levels
## only give "Architect": otherwise a tiny homemade map would make them easy.)
func _check_stage_achievements() -> void:
	if GameState.is_custom():
		Achievements.unlock("architect")
		return
	var st := GameState.stage_stats
	var shots := GameState.stat(st, "shots")
	var hits := GameState.stat(st, "hits")
	if GameState.stat(st, "armor_lost") == 0 and GameState.stat(st, "deaths") == 0:
		Achievements.unlock("untouchable")
	if shots >= 20 and hits * 100 >= shots * 80:
		Achievements.unlock("sharpshooter")
	if stage_time < 75.0:
		Achievements.unlock("speed_demon")
	if shots < 40:
		Achievements.unlock("ammo_miser")
	if GameState.stat(st, "bricks") == 0:
		Achievements.unlock("tiptoe")
	if _lives_left() == 1:
		Achievements.unlock("last_stand")
	if GameState.coop:
		Achievements.unlock("buddies")


## Stage awards for the stats screen: small score bonuses for playing well.
## Each is {name, desc, bonus, tier}. Add your own here!
func _stage_medals() -> Array:
	var st := GameState.stage_stats
	var shots := GameState.stat(st, "shots")
	var out := []
	if shots >= 10 and GameState.stat(st, "hits") * 100 >= shots * 75:
		out.append({"name": "SHARPSHOOTER", "desc": "75%+ of your shells hit", "bonus": 500, "tier": 1})
	if GameState.stat(st, "armor_lost") == 0:
		out.append({"name": "NO SCRATCH", "desc": "No damage taken", "bonus": 1000, "tier": 2})
	if stage_time < 90.0:
		out.append({"name": "BLITZ", "desc": "Cleared in under 1:30", "bonus": 500, "tier": 1})
	if GameState.stat(st, "best_combo") >= 5:
		out.append({"name": "COMBO KING", "desc": "A x5 combo or better", "bonus": 500, "tier": 1})
	if GameState.stat(st, "bricks") >= 40:
		out.append({"name": "WRECKING BALL", "desc": "40+ wall pieces smashed", "bonus": 300, "tier": 0})
	if GameState.stat(st, "powerups") >= 3:
		out.append({"name": "HOARDER", "desc": "3+ power-ups collected", "bonus": 300, "tier": 0})
	if GameState.coop:  # like the original: a bonus for whoever destroyed the most
		var k1 := GameState.stat(st, "kills", 0)
		var k2 := GameState.stat(st, "kills", 1)
		if k1 != k2:
			out.append({"name": "MVP P%d" % (1 if k1 > k2 else 2), "desc": "Most tanks destroyed", "bonus": 1000, "tier": 2})
	return out


func _check_stage_clear() -> void:
	var boss_alive := boss_delay > 0.0 or (is_instance_valid(boss) and not boss._dead)
	if enemies_spawned >= enemies_quota and enemies_alive <= 0 and not boss_alive and state == State.PLAYING:
		_stage_clear()


# ---------------------------------------------------------------- boss

## Bosses take turns: Fortress on stages 5, 15, 25..., Sky Raider gunship on 10, 20, 30...
func _boss_kind() -> int:
	return (GameState.stage / 5 - 1) % 2


func _boss_mark() -> int:
	return (GameState.stage / 5 + 1) / 2 if _boss_kind() == 0 else GameState.stage / 10


func _spawn_boss() -> void:
	if _boss_kind() == 0:
		boss = Boss.new()
		boss.position = Vector2(208, 48)
	else:
		boss = Gunship.new()
		boss.position = Vector2(208, -40)  # flies in from above the map
	boss.setup(GameState.stage)
	boss.health_changed.connect(_on_boss_health)
	boss.wants_minion.connect(func() -> void:
		if enemies_alive < max_on_screen + 1:
			_try_spawn_enemy(false, [Enemy.Kind.BASIC, Enemy.Kind.KAMIKAZE].pick_random()))
	boss.died.connect(_on_boss_died)
	world.add_child(boss)
	boss.modulate.a = 0.0
	create_tween().tween_property(boss, "modulate:a", 1.0, 0.8)
	shake = 8.0
	_boss_bar.visible = true
	_on_boss_health(boss.hp, boss.max_hp)


func _on_boss_health(hp: int, max_hp: int) -> void:
	_boss_fill.size.x = 296.0 * hp / max_hp
	_boss_fill.color = Color("#e8413b") if hp > max_hp * 0.33 else Color("#ff9a2e")


func _on_boss_died(tank: Tank) -> void:
	var pos := tank.position
	_boss_bar.visible = false
	GameState.bosses_killed += 1
	var is_gunship := tank is Gunship
	_track_kill(tank, "kills.gunship" if is_gunship else "kills.fortress")
	GameState.track("bosses")
	Achievements.unlock("clear_skies" if is_gunship else "fortress_breaker")
	_register_kill(pos, boss.points)
	FloatingText.spawn(world, pos + Vector2(0, -30), "%s DESTROYED!" % boss.display_name, Color("#ff7a3c"), 18)
	hit_stop(0.35)
	shake = 16.0
	# A chain of explosions all over the wreck.
	for i in 6:
		get_tree().create_timer(0.12 * i, false).timeout.connect(func() -> void:
			Fx.explosion(world, pos + Vector2(randf_range(-28, 28), randf_range(-28, 28)), true)
			Sfx.play("explode_big", -4.0, 0.2))
	_drop_powerup()
	_drop_powerup()
	# With the fortress gone, its escorts retreat: the stage is won.
	enemies_spawned = enemies_quota
	_kill_all_enemies()
	_check_stage_clear()


func _on_player_died(tank: Tank) -> void:
	var index := (tank as Player).index
	shake = 8.0
	GameState.track("deaths", 1, index)
	GameState.lives_p[index] -= 1
	if not GameState.diff("keep_star_on_death"):
		GameState.stars_p[index] = 0  # dying costs your star level (not your upgrade cards)
	if GameState.lives_p[index] > 0:
		await get_tree().create_timer(1.0, false).timeout
		if state == State.PLAYING:
			_spawn_player(index)
	elif _alive_players().is_empty() and _lives_left() == 0:
		_game_over()  # everyone is out of lives
	elif GameState.coop:
		FloatingText.spawn(world, tank.position, "P%d OUT!" % (index + 1), Color("#ff7a7a"), 14)


func _lives_left() -> int:
	var total := 0
	for i in GameState.player_count():
		total += GameState.lives_p[i]
	return total


func _on_base_destroyed() -> void:
	shake = 12.0
	_game_over()


func _stage_clear() -> void:
	if state != State.PLAYING:
		return
	state = State.STAGE_CLEAR
	_show_message("LEVEL COMPLETE!" if GameState.is_custom() else "STAGE CLEAR!")
	Sfx.play("stage_clear", 0.0, 0.0)
	Music.stop(0.3)
	GameState.track("time_ms", int(stage_time * 1000.0))
	GameState.track("stages_cleared")
	_check_stage_achievements()
	GameState.save_progress()  # lifetime stats + achievements
	await get_tree().create_timer(1.5).timeout
	_message_label.text = ""

	# The stats screen: tally, numbers, awards. Awards add a score bonus.
	get_tree().paused = true
	Music.play("upgrade", 1.0)
	var medals := _stage_medals()
	for m: Dictionary in medals:
		GameState.score += m["bonus"]
	var stats_screen := StatsScreen.new({
		"title": ("%s COMPLETE" % GameState.custom_name.to_upper()) if GameState.is_custom() else "STAGE %d CLEAR" % GameState.stage,
		"subtitle": Difficulty.NAMES[GameState.difficulty] + ("  ·  CO-OP" if GameState.coop else ""),
		"stats": GameState.stage_stats,
		"time": stage_time,
		"score_line": "+%d" % (GameState.score - _stage_start_score),
		"medals": medals,
		"achievements": _stage_achievements,
	})
	add_child(stats_screen)
	await stats_screen.closed
	if GameState.is_custom():
		# Custom levels are a single stage: back to where we came from.
		get_tree().paused = false
		Music.stop(0.3)
		get_tree().change_scene_to_file(GameState.return_scene)
		return

	# Pause the game and let the player pick 1 of 3 upgrade cards.
	# `await screen.picked` waits right here until the signal fires,
	# and gives us the value it was emitted with.
	# Garage perks: Wide Choice shows a 4th card, Reroll adds a reroll button.
	var count := 3 + GameState.perk("fourth_card")
	var screen := UpgradeScreen.new(Upgrades.roll_choices(GameState.upgrades, count), GameState.stage,
		GameState.perk("reroll") > 0)
	add_child(screen)
	var id: String = await screen.picked
	GameState.add_upgrade(id)
	Music.stop(0.5)
	get_tree().paused = false

	GameState.stage += 1
	get_tree().reload_current_scene()


func _game_over() -> void:
	if state == State.GAME_OVER:
		return
	state = State.GAME_OVER
	for p in _alive_players():
		p.controls_enabled = false
	_freeze_battlefield()
	Music.stop(1.0)
	# Wait for the explosion to ring out before the sad jingle.
	get_tree().create_timer(0.8).timeout.connect(Sfx.play.bind("game_over", 0.0, 0.0))
	GameState.track("time_ms", int(stage_time * 1000.0))
	var extra: Array[String] = []
	var result := GameState.end_run()  # (also saves the lifetime stats)
	if result["record"]:
		extra.append("NEW HIGH SCORE!")
	elif GameState.cheats_used:
		extra.append("(cheats used: no records)")
	if result["scrap"] > 0:
		extra.append("+%d scrap for the Garage" % result["scrap"])
	GameState.save_progress()
	_message_label.add_theme_font_size_override("font_size", 40)
	_show_message("GAME OVER")
	await get_tree().create_timer(2.2).timeout
	_message_label.text = ""

	# Stats with Retry / Main menu buttons, and two tabs: the stage you fell
	# on (shown first), and the whole run added up.
	var stats_screen := StatsScreen.new({
		"game_over": true,
		"title": "GAME OVER",
		"subtitle": "%s  ·  fell on stage %d" % [Difficulty.NAMES[GameState.difficulty], GameState.stage],
		"extra": extra,
		"views": {
			"stage": {
				"stats": GameState.stage_stats,
				"time": stage_time,
				"score_line": "+%d" % (GameState.score - _stage_start_score),
				"achievements": _stage_achievements,
			},
			"run": {
				"stats": GameState.run_stats,
				"time": GameState.stat(GameState.run_stats, "time_ms") / 1000.0,
				"stages_cleared": GameState.stat(GameState.run_stats, "stages_cleared"),
				"score_line": str(GameState.score),
				"achievements": GameState.run_achievements,
			},
		},
	})
	add_child(stats_screen)
	if result["scrap"] > 0:
		get_tree().create_timer(1.4).timeout.connect(Sfx.play.bind("scrap", 0.0, 0.0))
	var choice: String = await stats_screen.closed
	if choice == "retry":
		GameState.reset()
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(GameState.return_scene)


## The game is over: everything stops where it is, like in the original.
## Explosions and the score popups still finish playing.
func _freeze_battlefield() -> void:
	for t in get_tree().get_nodes_in_group("tanks"):
		# All movement, AI and shooting happens in _physics_process,
		# so switching it off freezes the tank completely.
		(t as Node).set_physics_process(false)
		(t as CharacterBody2D).velocity = Vector2.ZERO
	for child in world.get_children():
		if child is Bullet:
			(child as Bullet)._finish()  # shells in flight fizzle out
	combo_timer = 0.0


# ---------------------------------------------------------------- combo + hit-stop

## Score a kill: grow the combo chain, show a score popup, freeze for a moment.
func _register_kill(pos: Vector2, points: int) -> void:
	combo += 1
	combo_timer = COMBO_WINDOW
	GameState.best_combo = maxi(GameState.best_combo, combo)
	GameState.track_max("best_combo", combo)
	if combo >= 5:
		Achievements.unlock("chain_5")
	if combo >= 12:
		Achievements.unlock("chain_12")
	var mult := mini(combo, MAX_MULTIPLIER)
	var gained := points * mult
	GameState.score += gained

	if mult > 1:
		FloatingText.spawn(world, pos, "+%d  x%d" % [gained, mult], Color("#ffd23f"), 12 + mult)
		# The combo sound climbs a note with every kill in the chain.
		Sfx.play("combo", -2.0, 0.0, pow(2.0, (mini(combo, 12) - 2) / 12.0 * 2.0))
		if combo in [3, 5, 8, 12]:
			var word: String = {3: "NICE!", 5: "GREAT!", 8: "UNSTOPPABLE!", 12: "LEGENDARY!"}[combo]
			FloatingText.spawn(world, pos + Vector2(0, -18), word, Color("#ff7a3c"), 16)
	else:
		FloatingText.spawn(world, pos, "+%d" % gained, Color.WHITE, 11)
	# Bigger chains get a slightly longer freeze. It's tiny, but it makes
	# each kill feel heavier.
	hit_stop(0.05 + 0.01 * mini(combo, 5))


func _end_combo() -> void:
	if combo >= 3:
		FloatingText.spawn(world, Vector2(208, 200), "COMBO x%d ENDED" % combo, Color("#9fd8ff"), 12)
	combo = 0
	combo_timer = 0.0


## "Hit-stop": slow time almost to a halt for a split second.
## Fighting games use this so hits feel powerful.
func hit_stop(seconds: float) -> void:
	Engine.time_scale = 0.05
	_hitstop_end = maxi(_hitstop_end, Time.get_ticks_msec() + int(seconds * 1000.0))


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # never leave the game in slow motion


# ---------------------------------------------------------------- power-ups

func _drop_powerup() -> void:
	var pu := PowerUp.new(PowerUp.Kind.values().pick_random())
	pu.position = _powerup_spot()
	pu.collected.connect(_on_powerup_collected, CONNECT_DEFERRED)
	# We're usually inside a physics callback here (a bullet just hit a tank).
	# Physics objects can't be added mid-callback, so add it at the end of the frame.
	world.add_child.call_deferred(pu)


## Somewhere a player can actually reach (see Level.powerup_spots), and not on
## top of another power-up. Two can drop in the same frame (a boss drops two),
## so we also remember the spots we just used.
var _recent_drops: Array[Vector2] = []

func _powerup_spot() -> Vector2:
	var alive := _alive_players()
	var from: Vector2 = alive[0].position if not alive.is_empty() else Level.PLAYER_SPAWN
	var spots := level.powerup_spots(from)
	var taken: Array[Vector2] = _recent_drops.duplicate()
	for child in world.get_children():
		if child is PowerUp:
			taken.append((child as PowerUp).position)
	var free := spots.filter(func(p: Vector2) -> bool: return p not in taken)
	if free.is_empty():
		free = spots
	var spot: Vector2 = free.pick_random() if not free.is_empty() else Level.PLAYER_SPAWN + Vector2(0, -64)
	_recent_drops.append(spot)
	if _recent_drops.size() > 4:
		_recent_drops.pop_front()
	return spot


## `by` is the player who drove over it: stars, shields and lives are theirs.
func _on_powerup_collected(kind: PowerUp.Kind, by: Player) -> void:
	if not is_instance_valid(by):
		return
	GameState.score += 500
	Sfx.play("powerup_pickup", 0.0, 0.0)
	GameState.track("powerups", 1, by.index)
	match kind:
		PowerUp.Kind.STAR:
			var text := ""
			if by.stars() < 3:
				GameState.stars_p[by.index] = by.stars() + 1
				by.refresh_upgrades()  # new perks + one more armor plate
				# The tank changes shape (see Player._current_sprite): make it noticeable.
				var perk_text: String = ["", "FASTER SHELLS", "DOUBLE SHOT", "STEEL BREAKER"][by.stars()]
				text = "STAR %d: %s\n+1 ARMOR" % [by.stars(), perk_text]
				if by.stars() == 3:
					Achievements.unlock("fully_loaded")
			else:
				# Already maxed out: a star repairs one lost armor plate instead.
				by.hp = mini(by.hp + 1, by.max_hp)
				text = "ARMOR REPAIRED"
			FloatingText.spawn(world, by.position + Vector2(0, -24), text, Color("#ffd23f"), 12)
			by._flash_time = 0.15
			Fx.spark(world, by.position)
		PowerUp.Kind.SHIELD:
			by.invulnerable_time = 10.0
		PowerUp.Kind.FREEZE:
			freeze_time = 8.0
			_set_enemies_frozen(true)
		PowerUp.Kind.BOMB:
			shake = 10.0
			var caught := 0
			for t in get_tree().get_nodes_in_group("tanks"):
				if t is Enemy and not (t as Enemy)._dead:
					(t as Enemy).last_hit_by = by.index  # the bomb's kills are yours
					caught += 1
			if caught >= 4:
				Achievements.unlock("bomb_squad")
			_kill_all_enemies()  # (only damages a boss)
		PowerUp.Kind.FORTIFY:
			fortify_time = 15.0
			level.set_base_walls(Wall.Kind.STEEL)
		PowerUp.Kind.LIFE:
			GameState.lives_p[by.index] += 1


## Destroy every regular enemy. A boss only takes heavy damage, unless
## include_boss is true (used by the stage-skip shortcuts).
func _kill_all_enemies(include_boss := false) -> void:
	for t in get_tree().get_nodes_in_group("tanks"):
		if t is Enemy:
			(t as Enemy).explode()
	if is_instance_valid(boss) and not boss._dead:
		if include_boss:
			boss.explode()
		else:
			boss.hit(Vector2.ZERO, 8)


func _set_enemies_frozen(value: bool) -> void:
	for t in get_tree().get_nodes_in_group("tanks"):
		if t is Enemy:
			(t as Enemy).frozen = value


# ---------------------------------------------------------------- UI

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)

	var sidebar := ColorRect.new()
	sidebar.color = Color("#24242c")
	sidebar.position = Vector2(Level.SIZE, 0)
	sidebar.size = Vector2(512 - Level.SIZE, 416)
	hud.add_child(sidebar)

	_diff_label = Label.new()
	_diff_label.position = Vector2(Level.SIZE + 10, 396)
	_diff_label.add_theme_font_size_override("font_size", 10)
	_diff_label.add_theme_color_override("font_color", Difficulty.COLORS[GameState.difficulty])
	hud.add_child(_diff_label)

	_info_label = Label.new()
	_info_label.position = Vector2(Level.SIZE + 10, 12)
	_info_label.add_theme_font_size_override("font_size", 13)
	hud.add_child(_info_label)

	_combo_label = Label.new()
	_combo_label.position = Vector2(Level.SIZE + 10, 160)
	_combo_label.add_theme_font_size_override("font_size", 14)
	_combo_label.add_theme_color_override("font_color", Color("#ffd23f"))
	hud.add_child(_combo_label)
	_combo_bar = ColorRect.new()
	_combo_bar.position = Vector2(Level.SIZE + 10, 181)
	_combo_bar.color = Color("#ffd23f")
	hud.add_child(_combo_bar)

	_upgrades_label = Label.new()
	_upgrades_label.position = Vector2(Level.SIZE + 8, 262)

	# Boss health bar across the top of the map (only on boss stages).
	_boss_bar = Control.new()
	_boss_bar.position = Vector2(58, 6)
	_boss_bar.visible = false
	hud.add_child(_boss_bar)
	var bar_bg := ColorRect.new()
	bar_bg.size = Vector2(300, 10)
	bar_bg.color = Color(0, 0, 0, 0.75)
	_boss_bar.add_child(bar_bg)
	_boss_fill = ColorRect.new()
	_boss_fill.position = Vector2(2, 2)
	_boss_fill.size = Vector2(296, 6)
	_boss_bar.add_child(_boss_fill)
	var boss_name := Label.new()
	boss_name.text = "%s MK-%d" % ["FORTRESS" if _boss_kind() == 0 else "SKY RAIDER", maxi(_boss_mark(), 1)]
	boss_name.position = Vector2(0, 10)
	boss_name.add_theme_font_size_override("font_size", 10)
	boss_name.add_theme_constant_override("outline_size", 4)
	boss_name.add_theme_color_override("font_outline_color", Color.BLACK)
	_boss_bar.add_child(boss_name)

	_status_label = Label.new()
	_status_label.position = Vector2(Level.SIZE + 10, 190)
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color("#9fe8a0"))
	hud.add_child(_status_label)
	_upgrades_label.add_theme_font_size_override("font_size", 9)
	_upgrades_label.add_theme_color_override("font_color", Color("#9fd8ff"))
	hud.add_child(_upgrades_label)

	_message_label = Label.new()
	_message_label.position = Vector2(0, 100)
	_message_label.size = Vector2(Level.SIZE, 216)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 28)
	_message_label.add_theme_constant_override("outline_size", 8)
	_message_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_child(_message_label)


func _update_hud() -> void:
	var left := enemies_quota - enemies_spawned + enemies_alive
	var text := "STAGE %d\nLIVES %d\nENEMIES %d\nPOWER %d\n\nSCORE\n%d" % [
		GameState.stage, GameState.lives, left, GameState.player_level, GameState.score]
	if GameState.coop:  # one line per player: lives and stars
		text = "STAGE %d\nP1 LIVES %d\nP2 LIVES %d\nENEMIES %d\n\nSCORE\n%d" % [
			GameState.stage, GameState.lives_p[0], GameState.lives_p[1], left, GameState.score]
	_diff_label.text = Difficulty.NAMES[GameState.difficulty]
	_info_label.text = text

	var status := PackedStringArray()
	if base.shield_hits > 0:
		status.append("SHIELD %d" % base.shield_hits)
	if GameState.god_mode:
		status.append("GOD MODE")
	if freeze_time > 0.0:
		status.append("FREEZE %d" % ceili(freeze_time))
	if fortify_time > 0.0:
		status.append("WALLS %d" % ceili(fortify_time))
	_status_label.text = "\n".join(status)

	# Combo meter: multiplier + a bar showing how long until the chain breaks.
	var mult := mini(combo, MAX_MULTIPLIER)
	_combo_label.text = "COMBO x%d" % mult if combo >= 2 else ""
	_combo_bar.size = Vector2(76.0 * combo_timer / COMBO_WINDOW if combo >= 2 else 0.0, 3)

	var up := ""
	for id: String in GameState.upgrades:
		if id != "field_repair":
			up += "%s %d\n" % [Upgrades.ALL[id]["name"], GameState.upgrades[id]]
	_upgrades_label.text = ("UPGRADES\n" + up) if up != "" else ""


func _show_message(text: String, duration := 0.0) -> void:
	_message_label.text = text
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout
		if _message_label.text == text:
			_message_label.text = ""


func _draw() -> void:
	draw_rect(Rect2(0, 0, Level.SIZE, Level.SIZE), Color.BLACK)
