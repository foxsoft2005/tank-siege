class_name Boss
extends Tank
## FORTRESS: the boss that guards every 5th stage. A 64x64 tank with three
## phases, based on how much health it has left:
##
##   Phase 1 (100-66%)  patrols the top, fires a 3-way spread
##   Phase 2 (66-33%)   + aimed shots at you, calls in escort tanks
##   Phase 3 (33-0%)    ENRAGED: glows red, moves lower and faster,
##                      + fires a ring of 8 shells
##
## It ignores Freeze, and a Bomb only hurts it instead of killing it.

signal health_changed(hp: int, max_hp: int)
signal wants_minion  # Main spawns an escort when this fires

const PATROL_LEFT := 80.0
const PATROL_RIGHT := 336.0

var max_hp := 40
var display_name := "FORTRESS"
var points := 5000
var is_bonus := false
var phase := 1

var _patrol_dir := 1.0
var _spread_timer := 2.0
var _aim_timer := 3.0
var _ring_timer := 4.0
var _minion_timer := 7.0
var _cannon := 1.0  # which cannon fires the aimed shot (-1 left, 1 right)


func _init() -> void:
	team = Team.ENEMY
	body_size = Vector2(58, 58)
	facing = Vector2.DOWN
	speed = 34.0


## Tougher every time you meet it: stage 5 = 40 HP, stage 10 = 55, ...
func setup(stage: int) -> void:
	max_hp = int((40 + 15 * (stage / 5 - 1)) * GameState.diff("boss_hp"))
	hp = max_hp


func _physics_process(delta: float) -> void:
	super(delta)
	if _dead:
		return
	var ratio := float(hp) / max_hp
	phase = 1 if ratio > 0.66 else (2 if ratio > 0.33 else 3)
	_move(delta)
	_attack(delta)


func _move(delta: float) -> void:
	var y_target := 72.0 if phase < 3 else 128.0
	var move_speed := speed * (1.6 if phase == 3 else 1.0)
	var dir := Vector2(_patrol_dir, 0.0)
	if absf(position.y - y_target) > 2.0:
		dir = Vector2(0.0, signf(y_target - position.y))
	var before := position
	velocity = dir * move_speed
	move_and_slide()
	_tread_phase = fmod(_tread_phase + position.distance_to(before), 8.0)
	# Turn around at the patrol edges, or when something blocks the way.
	var blocked := position.distance_to(before) < move_speed * delta * 0.3
	if dir.y == 0.0 and (blocked or position.x < PATROL_LEFT or position.x > PATROL_RIGHT):
		_patrol_dir = -signf(position.x - 208.0) if not blocked else -_patrol_dir


func _attack(delta: float) -> void:
	var player := nearest_player()
	# 3-way spread from both cannons
	_spread_timer -= delta
	if _spread_timer <= 0.0:
		_spread_timer = 2.2 if phase == 1 else 1.7
		for angle in [-0.45, 0.0, 0.45]:
			_fire(Vector2.DOWN.rotated(angle), 200.0)
	# Aimed shots at the player
	if phase >= 2 and player:
		_aim_timer -= delta
		if _aim_timer <= 0.0:
			_aim_timer = 1.4 if phase == 2 else 0.9
			_cannon = -_cannon
			var from := position + Vector2(7.0 * _cannon, 36.0)
			_fire((player.position - from).normalized(), 280.0, _cannon)
	# Call in escorts
	if phase >= 2:
		_minion_timer -= delta
		if _minion_timer <= 0.0:
			_minion_timer = 9.0
			wants_minion.emit()
	# Ring of 8 shells when enraged
	if phase == 3:
		_ring_timer -= delta
		if _ring_timer <= 0.0:
			_ring_timer = 2.8
			for i in 8:
				var d := Vector2.RIGHT.rotated(TAU * i / 8.0 + PI / 8.0)
				_fire_from(position + d * 34.0, d, 170.0)
			Sfx.play("explode_small", -6.0, 0.0, 1.6)


func _fire(dir: Vector2, shell_speed: float, cannon := 0.0) -> void:
	if cannon == 0.0:
		_fire_from(position + Vector2(-7, 36), dir, shell_speed)
		_fire_from(position + Vector2(7, 36), dir, shell_speed)
	else:
		_fire_from(position + Vector2(7.0 * cannon, 36), dir, shell_speed)
	Sfx.play("enemy_shoot", -2.0, 0.05, 0.7)


func _fire_from(pos: Vector2, dir: Vector2, shell_speed: float) -> void:
	var b := Bullet.new(team, dir, shell_speed * GameState.diff("enemy_shell_speed"), 1)  # no shooter: no limit
	b.position = pos
	get_parent().add_child(b)


func hit(_from_dir := Vector2.ZERO, damage := 1) -> void:
	if _dead:
		return
	hp -= damage
	_flash_time = 0.06
	Sfx.play("boss_hit", -3.0, 0.1)
	health_changed.emit(maxi(hp, 0), max_hp)
	if hp <= 0:
		explode()


func _draw() -> void:
	var tint := Color.WHITE
	if phase == 3:  # enraged: pulse red
		tint = Color.WHITE.lerp(Color(1.8, 0.5, 0.5), 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0))
	if _flash_time > 0.0:
		tint = Color(6, 6, 6)
	var frame := int(_tread_phase / 4.0) % 2
	Art.draw_frame(self, "boss", frame, Vector2(32, 32), Vector2.ZERO, tint)
