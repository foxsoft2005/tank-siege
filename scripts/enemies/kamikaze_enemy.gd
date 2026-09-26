class_name KamikazeEnemy
extends Enemy
## KAMIKAZE: very fast, never shoots. It hunts you (or the core) and, when it
## gets close, lights a short fuse and EXPLODES, damaging everything nearby:
## you, the core, bricks, and other enemies too! Shoot it early, ideally
## when it's next to its friends.
## If a brick wall blocks its way, it blows itself up to breach the wall.

const TRIGGER_RANGE := 40.0
const FUSE_TIME := 0.5
const BLAST_RADIUS := 46.0

var _fuse := -1.0  # < 0 = not lit
var _blocked_time := 0.0


func _configure() -> void:
	speed = 100.0
	points = 200
	sprite_name = "kamikaze"
	brain = Brain.HUNTER
	can_shoot = false
	holds_to_fire = false
	_warmup = randf_range(0.5, 1.5)  # gets going almost right away


func _think(delta: float, level: Level, player: Tank) -> Vector2:
	if _fuse >= 0.0:
		_fuse -= delta
		if _fuse < 0.0:
			explode()
		return facing  # stop and tremble
	var near_player := player != null and position.distance_to(player.position) < TRIGGER_RANGE
	# Stuck against bricks for a moment? Breach!
	if level and level.brick_ahead(position, facing) and velocity.length() < 1.0:
		_blocked_time += delta
	else:
		_blocked_time = 0.0
	if near_player or position.distance_to(target) < TRIGGER_RANGE + 12.0 or _blocked_time > 0.8:
		_fuse = FUSE_TIME
		Sfx.play("fuse")
		return facing
	return super(delta, level, player)


## Blow up when destroyed too, so shooting one next to its friends is a great move.
func explode() -> void:
	if _dead:
		return
	super()  # marks us dead, plays the normal explosion, tells Main
	_blast()


func _blast() -> void:
	Fx.explosion(get_parent(), position, true)
	var level := get_tree().get_first_node_in_group("level") as Level
	if level:
		level.damage_radius(position, BLAST_RADIUS, 1)
	for node in get_tree().get_nodes_in_group("tanks"):
		var t := node as Tank
		if t != self and t.position.distance_to(position) < BLAST_RADIUS + 10.0:
			t.hit()
	var base := get_tree().get_first_node_in_group("base") as Base
	if base and base.position.distance_to(position) < BLAST_RADIUS + 14.0:
		base.hit()


func _current_tint() -> Color:
	if _fuse >= 0.0 and int(Time.get_ticks_msec() / 60) % 2 == 0:
		return Color(3, 3, 3)  # frantic white flashing
	return super()


func _draw_extra() -> void:
	super()
	# A warning light on the turret that blinks faster when it's lit.
	var rate := 60 if _fuse >= 0.0 else 250
	if int(Time.get_ticks_msec() / rate) % 2 == 0:
		draw_circle(Vector2(0, 1), 2.5, Color("#ff3020"))
