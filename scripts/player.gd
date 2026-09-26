class_name Player
extends Tank
## The tank you drive. Reads input every physics frame.
## Its stats come from three places:
##   - the tank you picked in the Garage (GameState.tank_stat, see garage.gd)
##   - GameState.player_level: the P power-up (lost when you die)
##   - GameState.upgrades: roguelite cards (kept for the whole run)

const BASE_SPEED := 80.0

var index := 0          # 0 = Player 1, 1 = Player 2 (co-op)
var controls_enabled := true
var _actions := {}      # "up" -> the input action to read, e.g. "move_up" or "p2_up"
var max_hp := 1
var reload_time := 0.18  # seconds between shots while holding fire
var _fire_cooldown := 0.0


func _init(p_index := 0) -> void:
	team = Team.PLAYER
	index = p_index
	# Solo: the normal actions (WASD *and* arrows, any gamepad).
	# Co-op: "p1_..." / "p2_..." actions, one key set and one gamepad each.
	var prefix := ("p%d_" % (index + 1)) if GameState.coop else ""
	for a in ["up", "down", "left", "right"]:
		_actions[a] = prefix + a if GameState.coop else "move_" + a
	_actions["fire"] = prefix + "fire"
	# Player 2 drives a green Scout, like the original's second player.
	sprite_name = GameState.tank_stat("sprite") if index == 0 else "player2"


## Tank stats: Player 1 uses the tank picked in the Garage, Player 2 a Scout.
func _stat(key: String) -> Variant:
	return GameState.tank_stat(key) if index == 0 else Garage.stat("scout", key)


func stars() -> int:
	return GameState.stars_p[index]


func _ready() -> void:
	super()
	add_to_group("player")  # enemies find us with get_first_node_in_group("player")
	max_hp = _armor_total()
	hp = max_hp
	refresh_upgrades()


## Hit points = 1 + one armor plate per STAR (like the upgraded tanks of the
## original) + the Armor Plating card + the Garage armor unlock.
const ARMOR_PER_STAR := 1

func _armor_total() -> int:
	return 1 + stars() * ARMOR_PER_STAR + GameState.stacks("armor_plating") + int(_stat("armor"))


## Re-read upgrades and stars: stats, extra armor and drones. Safe to call any
## time. When max armor goes up, you get the new plates right away.
func refresh_upgrades() -> void:
	apply_stats()
	var new_max := _armor_total()
	hp = clampi(hp + new_max - max_hp, 1, new_max)
	max_hp = new_max
	for child in get_children():
		if child is Drone:
			child.queue_free()
	var drones := GameState.stacks("guard_drone")
	for i in drones:
		add_child(Drone.new(self, i, drones))


## Recalculate stats. Call this after picking up P or getting an upgrade.
## P level: 1 = faster shells, 2 = two shells at once, 3 = shells break steel.
func apply_stats() -> void:
	var level := stars()
	bullet_speed = (220.0 if level == 0 else 340.0) * float(_stat("shell_speed"))
	max_bullets = (2 if level >= 2 else 1) + GameState.stacks("rapid_loader") + int(_stat("extra_shells"))
	bullet_power = 2 if level >= 3 else 1
	speed = BASE_SPEED * float(_stat("speed")) * (1.0 + 0.15 * GameState.stacks("swift_treads"))
	reload_time = float(_stat("reload"))


func _physics_process(delta: float) -> void:
	super(delta)  # run Tank's _physics_process first (timers)
	_fire_cooldown -= delta
	if not controls_enabled:
		return

	var dir := Vector2.ZERO
	if Input.is_action_pressed(_actions["up"]):
		dir = Vector2.UP
	elif Input.is_action_pressed(_actions["down"]):
		dir = Vector2.DOWN
	elif Input.is_action_pressed(_actions["left"]):
		dir = Vector2.LEFT
	elif Input.is_action_pressed(_actions["right"]):
		dir = Vector2.RIGHT
	drive(dir)

	# Holding fire auto-fires; the bullet limit and a short cooldown keep it fair.
	if Input.is_action_pressed(_actions["fire"]) and _fire_cooldown <= 0.0:
		if shoot():
			_fire_cooldown = reload_time


func shoot() -> bool:
	if GameState.stacks("twin_cannon") == 0:
		return super()
	# Twin Cannon: two shells side by side. It counts as one "shot",
	# so the on-screen limit is doubled.
	if active_bullets >= max_bullets * 2 or _dead:
		return false
	var side := facing.orthogonal() * 6.0
	fire_shell(side)
	fire_shell(-side)
	return true


## Give our shells their upgrade powers.
func _configure_bullet(b: Bullet) -> void:
	b.player_index = index
	GameState.track("shots", 1, index)
	b.bounces_left = GameState.stacks("ricochet")
	b.pierce_left = GameState.stacks("piercing") + int(_stat("pierce"))
	b.blast = GameState.stacks("blast_shells") > 0 or bool(_stat("blast"))


func hit(from_dir := Vector2.ZERO, _damage := 1) -> void:
	if GameState.god_mode:  # secret code GODTIER
		Sfx.play("shield_block", -6.0)
		return
	var before := hp
	super(from_dir, 1)  # enemy shells always take exactly one hit point
	# Armor Plating soaked the hit: blink for a moment so you can escape.
	if hp < before:
		GameState.track("armor_lost", before - hp, index)  # includes the fatal hit
	if hp < before and hp > 0:
		invulnerable_time = 1.0
		Fx.debris(get_parent(), position, true)


## Like the original game, the tank's SHAPE shows its star level:
## assets/sprites/tank_<color>_L0..L3.png (drawn by tools/make_sprites.py).
func _current_sprite() -> String:
	return "%s_L%d" % [sprite_name, stars()]


func _draw_extra() -> void:
	if GameState.god_mode:  # golden halo
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 28, Color(1.0, 0.85, 0.2, 0.4 + 0.5 * pulse), 2.0)
	# An arrow on the back marks YOUR tank, whatever its color: gold for
	# Player 1, green for Player 2.
	var marker := Color("#ffd23f") if index == 0 else Color("#7dff8a")
	draw_colored_polygon(PackedVector2Array([Vector2(-3, 14), Vector2(3, 14), Vector2(0, 11)]), marker)
	# Grey plates on the treads show remaining armor (one per extra hit point,
	# up to 4 drawn). Knocked-off plates show as dark gaps.
	for i in mini(max_hp - 1, 4):
		var col := Color("#d6dbe3") if i < hp - 1 else Color(0.2, 0.2, 0.25, 0.7)
		draw_rect(Rect2(-16, -12 + i * 6, 2, 4), col)
		draw_rect(Rect2(14, -12 + i * 6, 2, 4), col)
