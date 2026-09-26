class_name SniperEnemy
extends Enemy
## SNIPER: slow and fragile, but deadly at range.
## It wanders until it lines up with you (same row or column, no steel in the
## way). Then it stops, shows a red laser sight for a moment (your warning!)
## and fires a very fast shell. Break the line of sight or dodge.

const LASER_TIME := 0.8
const RANGE := 420.0
const COOLDOWN := 2.5
const SNIPE_SPEED := 560.0

var _aim := 0.0       # > 0 while aiming
var _cooldown := 1.5


func _configure() -> void:
	speed = 35.0
	points = 300
	sprite_name = "sniper"
	brain = Brain.WANDER
	can_shoot = false  # it only ever fires its telegraphed snipe


func _think(delta: float, level: Level, player: Tank) -> Vector2:
	_cooldown -= delta
	var lined_up := player != null and level != null and _lined_up_with(player, RANGE) \
		and level.clear_shot(position, player.position)
	if _aim > 0.0:
		if not lined_up:
			_aim = 0.0  # you escaped the sight line
			return Vector2.ZERO
		var dir := _axis_toward(player.position)
		if facing == dir:
			_aim -= delta  # the laser countdown only runs once it has turned to you
		if _aim <= 0.0:
			_snipe(dir)
		return dir
	if lined_up and _cooldown <= 0.0:
		_aim = LASER_TIME
		return _axis_toward(player.position)
	return super(delta, level, player)


func _snipe(dir: Vector2) -> void:
	facing = dir
	var b := Bullet.new(team, dir, SNIPE_SPEED * GameState.diff("enemy_shell_speed"), 1, self)
	b.position = position + dir * 16.0
	get_parent().add_child(b)
	Sfx.play("snipe", -2.0)
	_cooldown = COOLDOWN


func _draw_extra() -> void:
	super()
	draw_rect(Rect2(-1, -24, 2, 9), Color("#dfe8ff"))  # extra-long barrel
	if _aim > 0.0 and not is_turning():
		# Laser sight: flickers faster just before the shot.
		var on := int(Time.get_ticks_msec() / (40 if _aim < 0.3 else 90)) % 2 == 0
		if on:
			draw_line(Vector2(0, -24), Vector2(0, -420), Color(1, 0.15, 0.15, 0.7), 1.0)
