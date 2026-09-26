class_name Tank
extends CharacterBody2D
## Shared code for every tank. Player and Enemy "extend" (inherit from) this,
## just like a C# subclass. They add the brain: keyboard input or AI.

signal died(tank: Tank)

enum Team { PLAYER, ENEMY }

const GRID := 16.0  # tanks line up on a 16px grid when they turn

var team: Team = Team.ENEMY
var speed := 60.0
var hp := 1
var facing := Vector2.UP
var sprite_name := "basic"  # which assets/sprites/tank_*.png to use
var bullet_speed := 220.0
var max_bullets := 1
var bullet_power := 1        # 2 = can break steel
var active_bullets := 0      # Bullet updates this itself
var invulnerable_time := 0.0 # > 0 means shielded
var frozen := false
var body_size := Vector2(26, 26)  # collision box (the boss is much bigger)
var teleport_cooldown := 0.0
var last_hit_by := -1  # which player's shell hit us last (for the stats), -1 = nobody

## Floor tiles (see Level.floor_under)
const MUD_SPEED := 0.5       # speed multiplier on mud
const ICE_GRIP := 1.4        # how fast you can change speed on ice (lower = slipperier)
const CONVEYOR_SPEED := 45.0 # how hard belts push

var _level: Level
var _drive_velocity := Vector2.ZERO  # our own movement, without belt pushes

var _flash_time := 0.0
var _tread_phase := 0.0
var _dead := false


func _ready() -> void:
	add_to_group("tanks")
	collision_layer = Layers.TANKS
	collision_mask = Layers.WALLS | Layers.WATER | Layers.TANKS | Layers.BASE
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING  # top-down: no floor/gravity
	_level = get_tree().get_first_node_in_group("level") as Level

	var rect := RectangleShape2D.new()
	rect.size = body_size  # a bit smaller than a 32px block, so tanks fit in corridors
	var shape := CollisionShape2D.new()
	shape.shape = rect
	add_child(shape)


func _physics_process(delta: float) -> void:
	invulnerable_time = maxf(invulnerable_time - delta, 0.0)
	teleport_cooldown = maxf(teleport_cooldown - delta, 0.0)
	_flash_time = maxf(_flash_time - delta, 0.0)
	queue_redraw()  # redraw every frame (cheap for simple shapes)


## Move in one of 4 directions (or ZERO to stop). Returns how far we moved.
## The floor changes things: mud slows you, ice makes you slide, belts push.
func drive(dir: Vector2) -> float:
	var ground := _level.floor_under(position) if _level else {"ice": false, "mud": false, "push": Vector2.ZERO}
	var delta := get_physics_process_delta_time()
	var target := dir * speed * (MUD_SPEED if ground["mud"] else 1.0)
	if ground["ice"]:
		# Low grip: speed changes slowly, so you keep sliding after letting go.
		_drive_velocity = _drive_velocity.move_toward(target, speed * ICE_GRIP * delta)
	else:
		_drive_velocity = target
	var push: Vector2 = ground["push"] * CONVEYOR_SPEED
	if _drive_velocity.length() < 0.5 and push == Vector2.ZERO:
		velocity = Vector2.ZERO
		_drive_velocity = Vector2.ZERO
		return 0.0
	if dir != Vector2.ZERO and dir != facing:
		# Turning 90 degrees: snap to the grid so we slide neatly into corridors.
		# This is THE trick that makes grid-based tank games feel right.
		if absf(dir.dot(facing)) < 0.5:
			if dir.x != 0.0:
				position.y = roundf(position.y / GRID) * GRID
			else:
				position.x = roundf(position.x / GRID) * GRID
		facing = dir
		if ground["ice"]:
			# Turning on ice keeps some of the old speed in the new direction.
			_drive_velocity = dir * _drive_velocity.length() * 0.6
	var before := position
	velocity = _drive_velocity + push
	move_and_slide()
	if get_slide_collision_count() > 0 and ground["ice"]:
		_drive_velocity = velocity - push  # hitting a wall kills the slide
	var moved := position.distance_to(before)
	_tread_phase = fmod(_tread_phase + moved, 4.0)
	if _level:
		_level.try_teleport(self)
	return moved


## The closest living player tank (co-op has two), or null.
func nearest_player() -> Tank:
	var best: Tank = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as Tank
		var d := p.position.distance_to(position)
		if d < best_d and not p._dead:
			best = p
			best_d = d
	return best


## Returns true if a bullet was actually fired.
func shoot() -> bool:
	if active_bullets >= max_bullets or _dead:
		return false
	fire_shell(Vector2.ZERO)
	return true


## Spawn one shell. `offset` shifts it sideways (used by Twin Cannon).
func fire_shell(offset: Vector2) -> Bullet:
	var b := Bullet.new(team, facing, bullet_speed, bullet_power, self)
	b.position = position + facing * 16.0 + offset
	_configure_bullet(b)
	get_parent().add_child(b)
	if team == Team.PLAYER:
		Sfx.play("shoot")
	else:
		Sfx.play("enemy_shoot", -4.0)
	return b


## Subclasses override this to give shells special powers.
func _configure_bullet(_b: Bullet) -> void:
	pass


## from_dir: the direction the shell was travelling (ZERO for explosions).
## damage: how much HP to take (max-power shells deal 2).
func hit(from_dir := Vector2.ZERO, damage := 1) -> void:
	if invulnerable_time > 0.0 or _dead:
		return
	hp -= damage
	_flash_time = 0.08
	if hp <= 0:
		explode()
	else:
		Sfx.play("armor_hit")  # survived: armored enemy or Armor Plating


func explode() -> void:
	if _dead:  # two bullets can hit in the same frame, only die once
		return
	_dead = true
	Fx.explosion(get_parent(), position, true)
	Sfx.play("explode_big" if team == Team.PLAYER else "explode_small")
	died.emit(self)
	queue_free()


## Draws the pixel-art sprite (assets/sprites/tank_*.png, 2 frames), rotated
## to face the way we're going. The sprite is drawn facing UP.
func _draw() -> void:
	draw_set_transform(Vector2.ZERO, _draw_angle())
	var tint := _current_tint()
	if GameState.disco:  # secret code DISCO: every tank cycles through the rainbow
		tint = Color.from_hsv(fmod(Time.get_ticks_msec() / 1500.0 + get_instance_id() * 0.13, 1.0), 0.6, 1.0)
	if _flash_time > 0.0:
		tint = Color(6, 6, 6)  # values above 1 brighten: a white "hit flash"
	var frame := int(_tread_phase / 2.0) % 2  # swap frames as we roll: treads move
	Art.draw_frame(self, "tank_" + _current_sprite(), frame, Vector2(16, 16), Vector2.ZERO, tint)
	_draw_extra()

	draw_set_transform(Vector2.ZERO)
	if invulnerable_time > 0.0 and int(Time.get_ticks_msec() / 60) % 2 == 0:
		draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 24, Color(0.5, 0.9, 1.0, 0.9), 2.0)


## Which way the sprite is drawn (the sprite points UP, hence the +90 degrees).
## Enemies override this to show a smooth turn while they rotate toward you.
func _draw_angle() -> float:
	return facing.angle() + PI / 2.0


## Subclasses override these to change the look (e.g. red bonus tanks).
func _current_sprite() -> String:
	return sprite_name


func _current_tint() -> Color:
	return Color.WHITE


## Subclasses can override this to draw extra details.
func _draw_extra() -> void:
	pass
