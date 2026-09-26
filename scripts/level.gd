class_name Level
extends Node2D
## Builds the map from LevelData and handles walls being destroyed.

const CELL := 16          # size of one wall piece
const BLOCK := 32         # size of one map block (= one tank)
const BLOCKS := 13        # map is 13 x 13 blocks
const SIZE := BLOCK * BLOCKS  # 416 px

## Where the base sits (center of block 6,12) and the player spawns (block 4,12).
const BASE_POS := Vector2(6 * BLOCK + 16, 12 * BLOCK + 16)
const PLAYER_SPAWN := Vector2(4 * BLOCK + 16, 12 * BLOCK + 16)
const PLAYER2_SPAWN := Vector2(8 * BLOCK + 16, 12 * BLOCK + 16)  # co-op
const ENEMY_SPAWNS: Array[Vector2] = [
	Vector2(16, 16), Vector2(6 * BLOCK + 16, 16), Vector2(12 * BLOCK + 16, 16),
]

var walls: Dictionary = {}  # Vector2i cell -> Wall
var rubble: Dictionary = {}  # cells where a brick was shot away (engineers rebuild these)

## Floor tiles, per 16px cell: {"kind": "ice"/"mud"/"belt"/"tele", "dir": Vector2}
var floor: Dictionary = {}
var blocks_with_floor: Array[Vector2i] = []  # belt + teleporter blocks (drawn per block)
var teleporters: Array[Vector2i] = []        # teleporter blocks, in map order
var bush_blocks: Array[Vector2i] = []        # where the bushes are (power-ups avoid them)

signal barrel_exploded(pos: Vector2)

const BARREL_RADIUS := 46.0
const CONVEYOR_DIRS := {"^": Vector2.UP, "V": Vector2.DOWN, "<": Vector2.LEFT, ">": Vector2.RIGHT}

## Pathfinding grid for the enemy AI (see "Navigation" below).
var nav := AStarGrid2D.new()
var _nav_ready := false


func _ready() -> void:
	add_to_group("level")  # lets bullets find us with get_first_node_in_group()


func build(rows: PackedStringArray) -> void:
	var floor_layer := FloorLayer.new()  # added first = drawn under everything
	floor_layer.level = self
	add_child(floor_layer)
	for by in rows.size():
		var row: String = rows[by]
		for bx in row.length():
			var ch := row[bx]
			if ch == "G":
				add_child(Bush.new(Vector2(bx * BLOCK + 16, by * BLOCK + 16)))
				bush_blocks.append(Vector2i(bx, by))
				continue
			if _add_floor(Vector2i(bx, by), ch):
				continue
			var kind: int = {"B": Wall.Kind.BRICK, "S": Wall.Kind.STEEL, "W": Wall.Kind.WATER,
				"X": Wall.Kind.BARREL}.get(ch, -1)
			if kind == -1:
				continue
			for dy in 2:
				for dx in 2:
					_add_wall(Vector2i(bx * 2 + dx, by * 2 + dy), kind as Wall.Kind)
	set_base_walls(Wall.Kind.BRICK)
	_add_border()
	_setup_nav()


## The thin ring of wall pieces around the base.
## Floor tiles: ice (I), mud (M), conveyor belts (^ V < >) and teleporters (T).
## Returns true if `ch` was a floor tile.
func _add_floor(b: Vector2i, ch: String) -> bool:
	var info := {}
	match ch:
		"I": info = {"kind": "ice"}
		"M": info = {"kind": "mud"}
		"T": info = {"kind": "tele"}
		_:
			if CONVEYOR_DIRS.has(ch):
				info = {"kind": "belt", "dir": CONVEYOR_DIRS[ch]}
	if info.is_empty():
		return false
	for dy in 2:
		for dx in 2:
			floor[b * 2 + Vector2i(dx, dy)] = info
	if info["kind"] == "belt" or info["kind"] == "tele":
		blocks_with_floor.append(b)
	if info["kind"] == "tele":
		teleporters.append(b)
	return true


## What's under a tank centred at `pos`? Returns {ice, mud, push, tele}.
func floor_under(pos: Vector2) -> Dictionary:
	var result := {"ice": false, "mud": false, "push": Vector2.ZERO}
	var p := to_point(pos)
	for c in [p - Vector2i(1, 1), p - Vector2i(0, 1), p - Vector2i(1, 0), p]:
		var info: Dictionary = floor.get(c, {})
		match info.get("kind", ""):
			"ice": result["ice"] = true
			"mud": result["mud"] = true
			"belt": result["push"] = info["dir"]
	return result


## Teleporters: a tank that drives onto the middle of a pad comes out of the
## next pad (in map order), as long as that one isn't blocked by another tank.
func try_teleport(tank: Tank) -> void:
	if teleporters.size() < 2 or tank.teleport_cooldown > 0.0:
		return
	var here := Vector2i(floori(tank.position.x / BLOCK), floori(tank.position.y / BLOCK))
	var index := teleporters.find(here)
	if index < 0:
		return
	var center := Vector2(here * BLOCK) + Vector2(16, 16)
	if tank.position.distance_to(center) > 6.0:
		return  # not on the middle of the pad yet
	for step in range(1, teleporters.size()):
		var dest_block := teleporters[(index + step) % teleporters.size()]
		var dest := Vector2(dest_block * BLOCK) + Vector2(16, 16)
		if _spot_free(dest, tank):
			Fx.spark(self, tank.position)
			tank.position = dest
			tank.teleport_cooldown = 1.2  # so it doesn't bounce straight back
			Fx.spark(self, dest)
			Sfx.play("teleport", -2.0)
			if tank is Player:
				GameState.track("teleports", 1, (tank as Player).index)
			return


func _spot_free(pos: Vector2, ignore: Tank) -> bool:
	for t in get_tree().get_nodes_in_group("tanks"):
		if t != ignore and (t as Tank).position.distance_to(pos) < 30.0:
			return false
	return true


## Explosive barrels: blow up the whole 2x2 barrel, then (a moment later)
## damage everything around it. Nearby barrels go off too: chain reaction!
func explode_barrel(cell: Vector2i) -> void:
	var b := Vector2i(floori(cell.x / 2.0), floori(cell.y / 2.0))
	var any := false
	for dy in 2:
		for dx in 2:
			var c := b * 2 + Vector2i(dx, dy)
			var w: Wall = walls.get(c)
			if w and w.kind == Wall.Kind.BARREL:
				_remove_wall(c)
				any = true
	if not any:
		return
	var center := Vector2(b * BLOCK) + Vector2(16, 16)
	Fx.explosion(self, center, true)
	Sfx.play("explode_big", -2.0, 0.15)
	barrel_exploded.emit(center)
	get_tree().create_timer(0.12, false).timeout.connect(_barrel_blast.bind(center))


func _barrel_blast(center: Vector2) -> void:
	damage_radius(center, BARREL_RADIUS, 1)  # bricks, and other barrels (chain!)
	for t in get_tree().get_nodes_in_group("tanks"):
		var tank := t as Tank
		if tank.position.distance_to(center) < BARREL_RADIUS + 10.0:
			tank.hit()
	var base := get_tree().get_first_node_in_group("base") as Base
	if base and base.position.distance_to(center) < BARREL_RADIUS + 14.0:
		base.hit()


static func base_ring_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(11, 15):
		for y in range(23, 26):
			var is_base := x in [12, 13] and y in [24, 25]
			if not is_base:
				cells.append(Vector2i(x, y))
	return cells


## Used by the FORTIFY power-up: swap the ring to steel, and back to brick later.
func set_base_walls(kind: Wall.Kind) -> void:
	for c in base_ring_cells():
		_remove_wall(c)
		_add_wall(c, kind)


## A bullet hit wall piece `hit_cell`. Like the original game, it breaks a strip
## two pieces wide (the bullet's width), perpendicular to its travel direction.
func damage(hit_cell: Vector2i, dir: Vector2, bullet_pos: Vector2, power: int) -> void:
	var targets: Array[Vector2i] = []
	if dir.x != 0.0:  # moving sideways -> break a vertical strip
		for y in range(floori((bullet_pos.y - 8) / CELL), floori((bullet_pos.y + 7) / CELL) + 1):
			targets.append(Vector2i(hit_cell.x, y))
	else:             # moving up/down -> break a horizontal strip
		for x in range(floori((bullet_pos.x - 8) / CELL), floori((bullet_pos.x + 7) / CELL) + 1):
			targets.append(Vector2i(x, hit_cell.y))

	for c in targets:
		var w: Wall = walls.get(c)
		if w == null:
			continue
		if w.kind == Wall.Kind.BARREL:
			explode_barrel(c)
			continue
		if w.kind == Wall.Kind.BRICK or (w.kind == Wall.Kind.STEEL and power >= 2):
			Fx.debris(self, w.position, w.kind == Wall.Kind.STEEL)
			if w.kind == Wall.Kind.BRICK:
				rubble[c] = true
			_remove_wall(c)


## Blast Shells: break bricks (and steel, with max power) in a circle.
func damage_radius(center: Vector2, radius: float, power: int) -> void:
	var lo := Vector2i(floori((center.x - radius) / CELL), floori((center.y - radius) / CELL))
	var hi := Vector2i(floori((center.x + radius) / CELL), floori((center.y + radius) / CELL))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var w: Wall = walls.get(Vector2i(x, y))
			if w == null or w.position.distance_to(center) > radius:
				continue
			if w.kind == Wall.Kind.BARREL:
				explode_barrel(Vector2i(x, y))
				continue
			if w.kind == Wall.Kind.BRICK or (w.kind == Wall.Kind.STEEL and power >= 2):
				Fx.debris(self, w.position, w.kind == Wall.Kind.STEEL)
				if w.kind == Wall.Kind.BRICK:
					rubble[Vector2i(x, y)] = true
				_remove_wall(Vector2i(x, y))


func _add_wall(c: Vector2i, kind: Wall.Kind) -> void:
	var w := Wall.new(kind, c)
	walls[c] = w
	add_child(w)
	_refresh_nav_around(c)


func _remove_wall(c: Vector2i) -> void:
	var w: Wall = walls.get(c)
	if w:
		walls.erase(c)
		w.queue_free()
		_refresh_nav_around(c)


## Engineer enemies call this: put a brick back where one was shot away, as
## long as no tank is standing there. Returns true if it rebuilt something.
func rebuild_brick(c: Vector2i) -> bool:
	if walls.has(c) or not rubble.has(c) or c in base_ring_cells():
		return false
	var cell_rect := Rect2(Vector2(c * CELL), Vector2(CELL, CELL))
	for t in get_tree().get_nodes_in_group("tanks"):
		var tank := t as Tank
		if Rect2(tank.position - tank.body_size / 2.0, tank.body_size).intersects(cell_rect):
			return false
	rubble.erase(c)
	_add_wall(c, Wall.Kind.BRICK)
	return true


# ---------------------------------------------------------------- navigation
# Tanks are 2x2 wall-cells big and their centres sit on the 16px grid, so the
# pathfinding grid has one POINT per grid corner (27 x 27 of them). A tank
# centred on point P covers the 4 cells around it: P-(1,1), P-(0,1), P-(1,0), P.
#   - steel, water or the base in any of those cells -> point is solid
#   - bricks -> walkable but expensive (the AI will shoot its way through)
# AStarGrid2D then finds the cheapest route, like A* on any grid.

const NAV_SIZE := 27
const BRICK_COST := 3.0


func _setup_nav() -> void:
	nav.region = Rect2i(0, 0, NAV_SIZE, NAV_SIZE)
	nav.cell_size = Vector2(CELL, CELL)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER  # tanks only move in 4 directions
	nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	nav.update()
	_nav_ready = true
	for x in NAV_SIZE:
		for y in NAV_SIZE:
			_refresh_nav_point(Vector2i(x, y))


func _refresh_nav_around(c: Vector2i) -> void:
	if not _nav_ready:
		return
	for dx in 2:
		for dy in 2:
			var p := c + Vector2i(dx, dy)
			if nav.is_in_boundsv(p):
				_refresh_nav_point(p)


func _refresh_nav_point(p: Vector2i) -> void:
	var edge := p.x < 1 or p.y < 1 or p.x > NAV_SIZE - 2 or p.y > NAV_SIZE - 2
	var solid := edge
	var bricks := 0
	var mud := 0
	if not edge:
		for c in [p - Vector2i(1, 1), p - Vector2i(0, 1), p - Vector2i(1, 0), p]:
			if c.x in [12, 13] and c.y in [24, 25]:
				solid = true  # the base itself
			if floor.get(c, {}).get("kind", "") == "mud":
				mud += 1
			var w: Wall = walls.get(c)
			if w == null:
				continue
			if w.kind == Wall.Kind.BRICK:
				bricks += 1
			else:
				solid = true
	nav.set_point_solid(p, solid)
	nav.set_point_weight_scale(p, 1.0 + bricks * BRICK_COST + mud * 0.5)


static func to_point(pos: Vector2) -> Vector2i:
	return Vector2i(roundi(pos.x / CELL), roundi(pos.y / CELL))


static func to_pos(p: Vector2i) -> Vector2:
	return Vector2(p * CELL)


## Path of grid points from `from` towards `to`. If `to` can't be reached,
## returns the path to the closest reachable point instead.
func find_path(from: Vector2, to: Vector2i) -> Array[Vector2i]:
	var start := to_point(from)
	if not nav.is_in_boundsv(start) or not nav.is_in_boundsv(to):
		return []
	return nav.get_id_path(start, to, true)


## Every grid point a tank at `from` can drive to (a "flood fill" over the
## navigation grid). Steel, water, barrels and the core block the way; bricks
## don't, because you can shoot through them.
func reachable_points(from: Vector2) -> Dictionary:
	var start := to_point(from)
	var seen := {}
	if not nav.is_in_boundsv(start):
		return seen
	var todo: Array[Vector2i] = [start]
	seen[start] = true
	while not todo.is_empty():
		var p: Vector2i = todo.pop_back()
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = p + step
			if nav.is_in_boundsv(n) and not seen.has(n) and not nav.is_point_solid(n):
				seen[n] = true
				todo.append(n)
	return seen


## Good places to drop a power-up: map blocks that are completely empty (no
## brick, steel, water or barrel in any of their 4 pieces), not hidden under a
## bush, not on a belt or teleporter, not next to the core, and that a tank
## at `from` can actually drive to. Returns block centres.
func powerup_spots(from: Vector2) -> Array[Vector2]:
	var reachable := reachable_points(from)
	var spots: Array[Vector2] = []
	for by in range(0, BLOCKS - 1):  # (the bottom row is the core and your spawn)
		for bx in BLOCKS:
			var b := Vector2i(bx, by)
			if b in bush_blocks or b in blocks_with_floor:
				continue
			if bx >= 5 and bx <= 7 and by >= 11:
				continue  # the core's wall
			var empty := true
			for dy in 2:
				for dx in 2:
					if walls.has(Vector2i(bx * 2 + dx, by * 2 + dy)):
						empty = false
			var centre := Vector2(bx * BLOCK + 16, by * BLOCK + 16)
			if empty and reachable.has(to_point(centre)):
				spots.append(centre)
	return spots


## Could a shell fly from `from` to `to` in a straight line without hitting
## steel? (Bricks are fine: they can be shot through.) Both points should share
## a row or a column.
func clear_shot(from: Vector2, to: Vector2) -> bool:
	var steps := int(from.distance_to(to) / 8.0)
	for i in range(1, steps):
		var p := from.lerp(to, float(i) / steps)
		var w: Wall = walls.get(Vector2i(floori(p.x / CELL), floori(p.y / CELL)))
		if w and w.kind == Wall.Kind.STEEL:
			return false
	return true


## Is there a brick right in front of a tank at `pos` facing `dir`?
func brick_ahead(pos: Vector2, dir: Vector2) -> bool:
	var p := to_point(pos)
	var cells: Array[Vector2i] = []
	if dir == Vector2.UP:
		cells = [Vector2i(p.x - 1, p.y - 2), Vector2i(p.x, p.y - 2)]
	elif dir == Vector2.DOWN:
		cells = [Vector2i(p.x - 1, p.y + 1), Vector2i(p.x, p.y + 1)]
	elif dir == Vector2.LEFT:
		cells = [Vector2i(p.x - 2, p.y - 1), Vector2i(p.x - 2, p.y)]
	else:
		cells = [Vector2i(p.x + 1, p.y - 1), Vector2i(p.x + 1, p.y)]
	for c in cells:
		var w: Wall = walls.get(c)
		if w and w.kind == Wall.Kind.BRICK:
			return true
	return false


## Invisible walls just outside the map so nothing can leave it.
func _add_border() -> void:
	var t := 32.0
	var rects := [
		Rect2(-t, -t, SIZE + 2 * t, t),   # top
		Rect2(-t, SIZE, SIZE + 2 * t, t), # bottom
		Rect2(-t, 0, t, SIZE),            # left
		Rect2(SIZE, 0, t, SIZE),          # right
	]
	for r: Rect2 in rects:
		var body := StaticBody2D.new()
		body.collision_layer = Layers.WALLS
		body.collision_mask = 0
		body.position = r.get_center()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = r.size
		shape.shape = rect
		body.add_child(shape)
		add_child(body)
