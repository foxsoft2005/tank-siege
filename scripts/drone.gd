class_name Drone
extends Node2D
## Guard Drone upgrade: orbits the player and shoots at nearby enemies.
## It's a child of the Player node, so it moves with it automatically
## (child positions are relative to the parent).

const ORBIT_RADIUS := 24.0
const RANGE := 170.0
const FIRE_INTERVAL := 1.4
const SHELL_SPEED := 260.0

var host: Tank
var _angle := 0.0
var _cooldown := 0.5


func _init(p_host: Tank, index: int, count: int) -> void:
	host = p_host
	_angle = TAU * index / count  # spread several drones evenly around the circle
	_cooldown = 0.5 + 0.35 * index
	z_index = 12


func _physics_process(delta: float) -> void:
	_angle += delta * 2.5
	position = Vector2.from_angle(_angle) * ORBIT_RADIUS
	queue_redraw()

	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var target := _nearest_enemy()
	if target == null:
		return
	_cooldown = FIRE_INTERVAL
	var aim := (target.global_position - global_position).normalized()
	var b := Bullet.new(host.team, aim, SHELL_SPEED, 1)
	if host is Player:
		b.player_index = (host as Player).index  # kills count for the drone's owner
	b.position = global_position
	host.get_parent().add_child(b)
	Sfx.play("drone_shoot", -3.0)


func _nearest_enemy() -> Tank:
	var best: Tank = null
	var best_dist := RANGE
	for node in get_tree().get_nodes_in_group("tanks"):
		var t := node as Tank
		var d := t.global_position.distance_to(global_position)
		if t.team != host.team and d < best_dist:
			best = t
			best_dist = d
	return best


func _draw() -> void:
	draw_circle(Vector2.ZERO, 6.0, Color(0.4, 1.0, 0.8, 0.25))
	var pts := PackedVector2Array([Vector2(0, -5), Vector2(4, 0), Vector2(0, 5), Vector2(-4, 0)])
	draw_colored_polygon(pts, Color("#5ff0c0"))
	draw_circle(Vector2.ZERO, 1.5, Color.WHITE)
