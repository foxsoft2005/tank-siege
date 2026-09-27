class_name LevelGen
extends RefCounted
## Procedural levels: builds a random, VALID 13x13 map in the same text format
## as level_data.gd. Turned on with Options -> "Procedural levels".
##
## How a map is made:
##   1. Pick a "recipe" from the stage number: how many wall pieces, how much
##      steel, and which special tiles are unlocked (water from stage 2, ice/mud
##      from 3, barrels + belts from 4, teleporters from 6), like the handmade
##      stages introduce them.
##   2. Stamp random pieces (pillars, bars, blocks, L-shapes, bush patches...)
##      onto the LEFT half, then mirror it onto the right half. The original
##      game's maps are symmetric too, and it makes random maps look designed.
##   3. Check it (_is_valid). If it fails, try again with the next random
##      numbers. After MAX_TRIES it falls back to a handmade map.
##
## What "valid" means:
##   - the spawns, the base and its wall ring are empty (LevelData.PROTECTED);
##   - every enemy spawn can reach the base and the player spawns: steel,
##     water and barrels block, bricks don't (they can be shot away);
##   - no sealed-off pockets: every open block is reachable from the player
##     spawn (otherwise power-ups or tanks could end up somewhere pointless);
##   - enough walls to be interesting, enough open space to fight in;
##   - conveyor belts never push you into steel, water or a barrel;
##   - barrels are not next to the spawns or the base.
##
## The same seed always gives the same map, so a stage keeps its layout when
## you retry it (Main passes GameState.run_seed + the stage number).

const SIZE := 13
const HALF := 7  # columns 0..6; column 6 is the middle and mirrors onto itself
const MAX_TRIES := 80
const SOLID := "SWX"  # tanks can't drive through (or shoot through) these


## A valid map for `stage`, always the same for the same seed.
static func generate(stage: int, seed_value: int) -> PackedStringArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for attempt in MAX_TRIES:
		var map := _build(rng, stage)
		if _is_valid(map):
			return map
	push_warning("LevelGen: no valid map after %d tries, using a handmade one" % MAX_TRIES)
	return LevelData.MAPS[(stage - 1) % LevelData.MAPS.size()]


# ---------------------------------------------------------------- building

static func _build(rng: RandomNumberGenerator, stage: int) -> PackedStringArray:
	var g := []  # g[y][x] = one character
	for y in SIZE:
		var row := []
		row.resize(SIZE)
		row.fill(".")
		g.append(row)

	# The recipe gets tougher with the stage number.
	var steel_chance := minf(0.06 + 0.025 * stage, 0.3)
	var pieces := rng.randi_range(12, 16) + mini(stage / 3, 3)
	for i in pieces:
		var material := "B"
		var roll := rng.randf()
		if roll < steel_chance:
			material = "S"
		elif stage >= 2 and roll < steel_chance + 0.1:
			material = "W"
		elif roll < steel_chance + 0.22:
			material = "G"  # bushes
		_stamp(g, rng, material, rng.randi_range(0, 5))

	# Floor tiles: ice and mud patches, then belts.
	if stage >= 3:
		for i in rng.randi_range(1, 2):
			_patch(g, rng, "I" if rng.randf() < 0.5 else "M")
	if stage >= 4 and rng.randf() < 0.7:
		_belt(g, rng)
	if stage >= 4:
		for i in rng.randi_range(0, 2):
			_put_if_empty(g, rng.randi_range(1, 5), rng.randi_range(2, 8), "X")
	if stage >= 6 and rng.randf() < 0.6:
		# One teleporter per side: mirroring makes it a pair.
		_put_if_empty(g, rng.randi_range(0, 4), rng.randi_range(2, 9), "T")

	# A small brick nest for each player spawn, like the original.
	if rng.randf() < 0.6:
		_put_if_empty(g, 3, 11, "B")
		_put_if_empty(g, 3, 12, "B")

	_mirror(g)
	for p in LevelData.PROTECTED:
		g[p.y][p.x] = "."
	var out := PackedStringArray()
	for row in g:
		out.append("".join(row))
	return out


## Stamp one wall piece on the left half. Shapes are block offsets.
static func _stamp(g: Array, rng: RandomNumberGenerator, material: String, shape: int) -> void:
	var cells: Array[Vector2i] = []
	match shape:
		0:  # pillar
			for i in rng.randi_range(2, 4):
				cells.append(Vector2i(0, i))
		1:  # bar
			for i in rng.randi_range(2, 3):
				cells.append(Vector2i(i, 0))
		2:  # block
			cells.assign([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)])
		3:  # L
			cells.assign([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)])
		4:  # T
			cells.assign([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)])
		_:  # dot
			cells.append(Vector2i(0, 0))
	# Water only makes sense as lakes, not thin lines everywhere.
	if material == "W" and cells.size() < 2:
		material = "B"
	var origin := Vector2i(rng.randi_range(0, HALF - 1), rng.randi_range(1, 10))
	for c in cells:
		var p := origin + c
		if p.x >= 0 and p.x < HALF and p.y >= 1 and p.y <= 11:
			g[p.y][p.x] = material


## A 2x2 or 3x2 patch of floor (ice or mud), only on empty blocks.
static func _patch(g: Array, rng: RandomNumberGenerator, ch: String) -> void:
	var o := Vector2i(rng.randi_range(0, HALF - 2), rng.randi_range(2, 9))
	for dy in 2:
		for dx in rng.randi_range(2, 3):
			_put_if_empty(g, o.x + dx, o.y + dy, ch)


## A short horizontal belt (2-3 blocks) pointing towards or away from the middle.
static func _belt(g: Array, rng: RandomNumberGenerator) -> void:
	var y := rng.randi_range(2, 9)
	var x := rng.randi_range(0, 3)
	var ch := ">" if rng.randf() < 0.5 else "<"
	for i in rng.randi_range(2, 3):
		_put_if_empty(g, x + i, y, ch)


static func _put_if_empty(g: Array, x: int, y: int, ch: String) -> void:
	if x >= 0 and x < HALF and y >= 0 and y < SIZE and g[y][x] == ".":
		g[y][x] = ch


## Copy the left half onto the right half, mirrored. Belts flip direction.
static func _mirror(g: Array) -> void:
	for y in SIZE:
		for x in range(HALF, SIZE):
			var ch: String = g[y][SIZE - 1 - x]
			g[y][x] = {"<": ">", ">": "<"}.get(ch, ch)


# ---------------------------------------------------------------- checking

static func _is_valid(map: PackedStringArray) -> bool:
	for p in LevelData.PROTECTED:
		if map[p.y][p.x] != ".":
			return false

	# Every enemy spawn must reach the base and the player spawns.
	var from_player := _reachable(map, Vector2i(4, 12))
	for spawn in [Vector2i(0, 0), Vector2i(6, 0), Vector2i(12, 0)]:
		if not from_player.has(spawn):
			return false
	if not from_player.has(Vector2i(6, 11)) or not from_player.has(Vector2i(8, 12)):
		return false

	# No sealed-off pockets, and a sensible amount of walls vs open space.
	var open := 0
	var bricks := 0
	var steel := 0
	for y in SIZE:
		for x in SIZE:
			var ch := map[y][x]
			if ch in SOLID:
				if ch == "S":
					steel += 1
				continue
			if not from_player.has(Vector2i(x, y)):
				return false  # a pocket nobody can get to
			if ch == "B":
				bricks += 1
			else:
				open += 1
	if bricks < 28 or bricks > 72 or steel > 26 or open < 64:
		return false

	# Belts must not push you into something solid (or off the map).
	for y in SIZE:
		for x in SIZE:
			var dir: Vector2i = {">": Vector2i.RIGHT, "<": Vector2i.LEFT, "^": Vector2i.UP, "V": Vector2i.DOWN}.get(map[y][x], Vector2i.ZERO)
			if dir == Vector2i.ZERO:
				continue
			var n := Vector2i(x, y) + dir
			if n.x < 0 or n.y < 0 or n.x >= SIZE or n.y >= SIZE or map[n.y][n.x] in SOLID:
				return false

	# Barrels: not right next to the spawns or the base (blowing up your own
	# core with one stray shell isn't fun).
	for y in SIZE:
		for x in SIZE:
			if map[y][x] != "X":
				continue
			for p in LevelData.PROTECTED:
				if absi(p.x - x) <= 1 and absi(p.y - y) <= 1:
					return false

	# Teleporters only work in pairs.
	var teleporters := 0
	for row in map:
		teleporters += row.count("T")
	return teleporters != 1


## Blocks a tank starting at `start` can drive to (bricks count as open,
## because they can be shot away). Flood fill, 4 directions, like tanks move.
static func _reachable(map: PackedStringArray, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var p: Vector2i = todo.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = p + d
			if n.x < 0 or n.y < 0 or n.x >= SIZE or n.y >= SIZE or seen.has(n):
				continue
			if map[n.y][n.x] in SOLID:
				continue
			seen[n] = true
			todo.append(n)
	return seen
