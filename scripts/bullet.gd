class_name Bullet
extends Area2D
## A shell. It's an Area2D (a "sensor"), not a physics body: it doesn't push
## anything, it just gets told when it overlaps something via signals.

const BLAST_RADIUS := 30.0

var shooter: Tank  # can be null (drone shells don't count toward a tank's limit)
var team: Tank.Team
var dir: Vector2
var speed: float
var power: int

# Upgrade powers (set by Player._configure_bullet)
var bounces_left := 0   # Ricochet
var pierce_left := 0    # Piercing Rounds
var blast := false      # Blast Shells

var _done := false


func _init(p_team: Tank.Team, p_dir: Vector2, p_speed: float, p_power: int, p_shooter: Tank = null) -> void:
	team = p_team
	dir = p_dir
	speed = p_speed
	power = p_power
	shooter = p_shooter
	z_index = 5


func _ready() -> void:
	collision_layer = Layers.BULLETS
	collision_mask = Layers.WALLS | Layers.TANKS | Layers.BASE | Layers.BULLETS | Layers.AIR
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6, 6)
	var shape := CollisionShape2D.new()
	shape.shape = rect
	add_child(shape)

	# Signals: Godot calls these functions when something overlaps us.
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if shooter:
		shooter.active_bullets += 1


func _exit_tree() -> void:
	if is_instance_valid(shooter):
		shooter.active_bullets -= 1


func _physics_process(delta: float) -> void:
	position += dir * speed * delta


func _on_body_entered(body: Node2D) -> void:
	if _done:
		return
	if body is Tank:
		var tank := body as Tank
		if tank.team == team:
			return  # no friendly fire, fly through
		tank.hit(dir, power)
		if blast:
			_blast(tank)
		if pierce_left > 0:
			pierce_left -= 1  # keep flying
			return
		_finish()
	elif body is Wall:
		var wall := body as Wall
		var level := get_tree().get_first_node_in_group("level") as Level
		var steel_holds := wall.kind == Wall.Kind.STEEL and power < 2
		Sfx.play("hit_steel" if steel_holds else "hit_brick", -2.0)
		level.damage(wall.cell, dir, position, power)
		if blast:
			_blast(null)
		_bounce_or_finish()
	elif body is Base:
		(body as Base).hit()
		_finish()
	else:
		Sfx.play("hit_steel", -8.0)
		_bounce_or_finish()  # map border


func _on_area_entered(area: Area2D) -> void:
	# Two shells from opposite teams cancel each other out.
	if area is Bullet and (area as Bullet).team != team and not _done:
		Sfx.play("hit_steel", -6.0)
		(area as Bullet)._finish()
		_finish()


## Ricochet: turn 90 degrees to a random side instead of stopping.
func _bounce_or_finish() -> void:
	if bounces_left <= 0:
		_finish()
		return
	bounces_left -= 1
	position -= dir * 8.0  # step back out of the wall first
	dir = dir.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
	Sfx.play("bounce", -3.0)
	Fx.spark(get_parent(), position)


## Blast Shells: a small explosion that breaks bricks and hurts nearby enemies.
func _blast(already_hit: Tank) -> void:
	Fx.explosion(get_parent(), position, false)
	Sfx.play("explode_small", -4.0, 0.15)
	var level := get_tree().get_first_node_in_group("level") as Level
	level.damage_radius(position, BLAST_RADIUS, power)
	for node in get_tree().get_nodes_in_group("tanks"):
		var t := node as Tank
		if t != already_hit and t.team != team and t.position.distance_to(position) < BLAST_RADIUS + 13.0:
			t.hit()


func _finish() -> void:
	if _done:
		return
	_done = true
	Fx.spark(get_parent(), position)
	queue_free()


func _draw() -> void:
	var glow := Color("#ffb347") if blast else Color("#fff3c4")
	draw_rect(Rect2(-3, -3, 6, 6), glow)
	draw_rect(Rect2(-2, -2, 4, 4), Color.WHITE)
