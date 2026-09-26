class_name EngineerEnemy
extends Enemy
## ENGINEER: drives to bricks that were shot away and REBUILDS them, undoing
## your shortcuts (and closing holes you blasted to reach the core).
## It rarely shoots. Take it out first!
##
## It reuses the normal pathfinding: _path_goal() is overridden so the A*
## route leads to the nearest rubble instead of the player or the base.

const REPAIR_RANGE := 90.0     # repairs bricks this close to it
const NOTICE_RANGE := 260.0    # drives toward rubble this close to it
const REPAIR_EVERY := 2.5
const BRICKS_PER_REPAIR := 2

var _repair_timer := 2.0


func _configure() -> void:
	speed = 50.0
	points = 250
	hp = 2
	sprite_name = "engineer"
	holds_to_fire = false
	shoots_bricks = false  # it'd only have to fix them again!
	shoot_delay = Vector2(2.5, 4.0)
	_warmup = randf_range(1.0, 2.0)


func _think(delta: float, level: Level, player: Tank) -> Vector2:
	if level == null:
		return super(delta, level, player)
	_repair_timer -= delta
	if _repair_timer <= 0.0:
		_repair_timer = REPAIR_EVERY
		_repair(level)
	# Close to rubble: stop and work (standing ON it would block the rebuild).
	var close := _nearest_rubble(level, 56.0)
	if close.x >= 0 and _cell_center(close).distance_to(position) > 22.0:
		return _axis_toward(_cell_center(close))
	# Head for rubble when there is some nearby; otherwise just wander.
	brain = Brain.HUNTER if _nearest_rubble(level, NOTICE_RANGE) != Vector2i(-1, -1) else Brain.WANDER
	return super(delta, level, player)


## Pathfinding target: a grid point on top of the nearest rubble.
func _path_goal(_player: Tank) -> Vector2i:
	var level := get_tree().get_first_node_in_group("level") as Level
	var c := _nearest_rubble(level, NOTICE_RANGE)
	return c + Vector2i(1, 1) if c.x >= 0 else Level.to_point(position)


func _nearest_rubble(level: Level, max_dist: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := max_dist
	for c: Vector2i in level.rubble:
		var d := _cell_center(c).distance_to(position)
		if d < best_d:
			best_d = d
			best = c
	return best


func _repair(level: Level) -> void:
	var nearby: Array[Vector2i] = []
	for c: Vector2i in level.rubble:
		if _cell_center(c).distance_to(position) < REPAIR_RANGE:
			nearby.append(c)
	nearby.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _cell_center(a).distance_to(position) < _cell_center(b).distance_to(position))
	var built := 0
	for c in nearby:
		if level.rebuild_brick(c):
			Fx.spark(level, _cell_center(c))
			built += 1
			if built >= BRICKS_PER_REPAIR:
				break
	if built > 0:
		Sfx.play("repair", -4.0)
		_flash_time = 0.05


static func _cell_center(c: Vector2i) -> Vector2:
	return Vector2(c * Level.CELL) + Vector2(8, 8)


func _draw_extra() -> void:
	# A little crane arm on the back.
	draw_rect(Rect2(3, 4, 2, 9), Color("#f2c230"))
	draw_rect(Rect2(3, 12, 6, 2), Color("#f2c230"))
	super()
