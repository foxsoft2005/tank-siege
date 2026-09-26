class_name Enemy
extends Tank
## Enemy tanks. Each one gets a "brain" (a behaviour) when it spawns:
##
##   WANDER  - the classic: drive around, turn at random, often drift toward the base.
##   RAIDER  - uses A* pathfinding (Level.find_path) to reach a spot next to your
##             base, blasting through bricks on the way, then shoots the base.
##   HUNTER  - pathfinds to YOU, re-planning as you move. When it lines up with
##             you in a row or column it stops, turns and fires.
##
## Every brain shoots sooner when the player or the base is right in front of it.
## Press F3 (while running from the editor) to see the planned paths.
##
## Special enemies are SUBCLASSES of Enemy that override a few "hook" functions:
##   SniperEnemy, KamikazeEnemy, ShieldedEnemy, EngineerEnemy (enemy_types.gd)
## Enemy.create(kind) builds the right one.

enum Kind { BASIC, FAST, POWER, ARMOR, SNIPER, KAMIKAZE, SHIELDED, ENGINEER }
enum Brain { WANDER, RAIDER, HUNTER }

## Spots a raider can attack the base from (grid points) and which way to face.
## Above the base, left of it and right of it.
const RAID_SPOTS := {
	Vector2i(13, 22): Vector2.DOWN,
	Vector2i(10, 25): Vector2.RIGHT,
	Vector2i(16, 25): Vector2.LEFT,
}

var kind: Kind = Kind.BASIC
var brain: Brain = Brain.WANDER
var is_bonus := false  # bonus tanks blink red and drop a power-up
var points := 100
var target := Vector2.ZERO  # the base position, set by Main

var _turn_timer := 1.0
var _shoot_timer := 1.0
var _since_shot := 0.0
var _wanted_dir := Vector2.DOWN

var _path: Array[Vector2i] = []
var _repath_timer := 0.0
var _stuck_time := 0.0
var _confused_time := 0.0  # stuck too long: wander for a moment, then plan again
var _raid_spot := Vector2i(-1, -1)
var _warmup := 0.0  # smart tanks wander for a few seconds first, so you get a chance

## Reaction times (seconds on NORMAL; scaled by the "enemy_reaction" difficulty
## setting). Without these, an enemy snaps round and fires the instant you
## line up with it, so you can never sneak up on one. Now there's a window:
##   spot you -> REACTION -> turn (TURN_90 / TURN_180) -> aim (AIM_TIME) -> fire
## and the barrel glows orange while it's getting ready. That's your cue!
const REACTION := 0.3   # how long before it reacts to seeing you
const TURN_90 := 0.25   # time to turn a quarter
const TURN_180 := 0.45  # time to turn right round
const AIM_TIME := 0.35  # after ANY turn, time to settle the gun before firing

var _turn_goal := Vector2.ZERO  # direction we're turning toward (ZERO = not turning)
var _turn_from := Vector2.DOWN
var _turn_left := 0.0           # reaction + turn time still to go
var _turn_total := 0.0          # the turning part only (for the smooth animation)
var _aim_timer := 0.0
var _seen_time := 0.0           # how long a player has been straight in front of us
var _last_facing := Vector2.DOWN
var _warning := false           # barrel glow: about to shoot at something

## Hooks subclasses can change:
var can_shoot := true        # kamikazes don't shoot
var holds_to_fire := true    # hunters stop when lined up with you (kamikazes charge instead)
var shoot_delay := Vector2(0.8, 1.8)  # random time between normal shots (min, max)
var shoots_bricks := true    # shoot bricks that block the way (engineers don't)


## Build the right kind of enemy (a subclass for the special ones).
static func create(p_kind: Kind) -> Enemy:
	match p_kind:
		Kind.SNIPER:
			return load("res://scripts/enemies/sniper_enemy.gd").new()
		Kind.KAMIKAZE:
			return load("res://scripts/enemies/kamikaze_enemy.gd").new()
		Kind.SHIELDED:
			return load("res://scripts/enemies/shielded_enemy.gd").new()
		Kind.ENGINEER:
			return load("res://scripts/enemies/engineer_enemy.gd").new()
	return Enemy.new()


func setup(p_kind: Kind, p_bonus: bool, p_brain: Brain) -> void:
	kind = p_kind
	is_bonus = p_bonus
	brain = p_brain
	facing = Vector2.DOWN
	# Raiders wait longer on early stages: 9-13 s on stage 1, down to 3-7 s later.
	var raid_wait := maxf(10.0 - GameState.stage, 4.0)
	_warmup = randf_range(raid_wait - 1.0, raid_wait + 3.0) if brain == Brain.RAIDER else randf_range(2.0, 4.0)
	match kind:
		Kind.BASIC:
			speed = 45.0; points = 100; sprite_name = "basic"
		Kind.FAST:
			speed = 95.0; points = 200; sprite_name = "fast"
		Kind.POWER:
			speed = 55.0; points = 300; bullet_speed = 340.0; sprite_name = "power"
		Kind.ARMOR:
			speed = 40.0; points = 400; hp = 4; sprite_name = "armor"
	_configure()  # subclasses set their own stats here
	# Difficulty (see difficulty.gd)
	speed *= GameState.diff("enemy_speed")
	bullet_speed *= GameState.diff("enemy_shell_speed")
	shoot_delay *= GameState.diff("enemy_fire_delay")
	_warmup = maxf(_warmup + GameState.diff("ai_warmup"), 0.5)
	_shoot_timer = randf_range(0.5, 1.5)


## Hook: special enemies set their speed, HP, points and sprite here.
func _configure() -> void:
	pass


func _physics_process(delta: float) -> void:
	super(delta)
	if frozen:
		velocity = Vector2.ZERO
		return

	var level := get_tree().get_first_node_in_group("level") as Level
	var player := nearest_player()  # co-op: go after whoever is closest
	var hold_fire_dir := _think(delta, level, player)

	if hold_fire_dir != Vector2.ZERO:
		velocity = Vector2.ZERO
		_turn_toward(hold_fire_dir, delta)
	else:
		_turn_goal = Vector2.ZERO
	_track_facing(delta)

	if can_shoot:
		_update_shooting(delta, level, player, hold_fire_dir != Vector2.ZERO)


## Decide how to move this frame. Returns a direction to stand still and aim
## in, or ZERO to keep moving. Subclasses override this for special behaviour
## and can call super() to fall back to the normal brains.
func _think(delta: float, level: Level, player: Tank) -> Vector2:
	var hold_fire_dir := Vector2.ZERO
	_warmup -= delta
	if _confused_time > 0.0 or _warmup > 0.0:
		_confused_time -= delta
		_wander(delta)
	elif brain == Brain.HUNTER and holds_to_fire and player and _lined_up_with(player, 180.0) \
			and level and level.clear_shot(position, player.position):
		hold_fire_dir = _axis_toward(player.position)
	elif brain == Brain.WANDER or level == null:
		_wander(delta)
	else:
		hold_fire_dir = _follow_path(delta, level, player)
	return hold_fire_dir


# ---------------------------------------------------------------- brains

func _wander(delta: float) -> void:
	var moved := drive(_wanted_dir)
	var blocked := moved < speed * delta * 0.5
	_turn_timer -= delta
	if _turn_timer <= 0.0 or blocked:
		_pick_random_direction(blocked)


func _pick_random_direction(blocked: bool) -> void:
	_turn_timer = randf_range(0.8, 2.5)
	var options: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	if blocked:
		options.erase(_wanted_dir)
	# About half the time, head toward the base.
	if randf() < 0.5:
		var to_base := target - position
		var dir := Vector2.DOWN
		if absf(to_base.x) > 16.0 and randf() < 0.5:
			dir = Vector2(signf(to_base.x), 0.0)
		if dir in options:
			_wanted_dir = dir
			return
	_wanted_dir = options.pick_random()


## Walk along the A* path. Returns a direction to hold and fire in when the
## raider has arrived at its spot next to the base (otherwise ZERO).
func _follow_path(delta: float, level: Level, player: Tank) -> Vector2:
	_repath_timer -= delta
	if _repath_timer <= 0.0 or _path.is_empty():
		_repath(level, player)

	if brain == Brain.RAIDER and Level.to_point(position) == _raid_spot \
			and position.distance_to(Level.to_pos(_raid_spot)) < 2.0:
		return RAID_SPOTS[_raid_spot]  # in position: aim at the base
	if _path.is_empty():
		_wander(delta)
		return Vector2.ZERO

	var next_pos := Level.to_pos(_path[0])
	var to_next := next_pos - position
	if to_next.length() < 1.5:  # reached this waypoint
		position = next_pos
		_path.pop_front()
		return Vector2.ZERO
	var dir := Vector2(signf(to_next.x), 0.0) if absf(to_next.x) > absf(to_next.y) else Vector2(0.0, signf(to_next.y))

	var moved := drive(dir)
	if moved < speed * delta * 0.3:
		_stuck_time += delta
		# Blocked by another tank (not a brick we can shoot)? Give up for a bit.
		if _stuck_time > 1.2 and not level.brick_ahead(position, facing):
			_stuck_time = 0.0
			_confused_time = randf_range(0.6, 1.4)
			_pick_random_direction(true)
	else:
		_stuck_time = 0.0
	return Vector2.ZERO


## Hook: where should the pathfinding take us? Subclasses can override this.
func _path_goal(player: Tank) -> Vector2i:
	if brain == Brain.HUNTER and player:
		return Level.to_point(player.position)
	if _raid_spot.x < 0:
		_raid_spot = _nearest_raid_spot()
	return _raid_spot


func _repath(level: Level, player: Tank) -> void:
	var goal := _path_goal(player)
	_repath_timer = randf_range(0.5, 0.9) if brain == Brain.HUNTER else randf_range(1.5, 2.5)
	_path = level.find_path(position, goal)
	# The first point is where we already are.
	if not _path.is_empty() and Level.to_pos(_path[0]).distance_to(position) < 8.0:
		_path.pop_front()


func _nearest_raid_spot() -> Vector2i:
	var best := Vector2i(13, 22)
	var best_d := INF
	for spot: Vector2i in RAID_SPOTS:
		var d := Level.to_pos(spot).distance_to(position) + randf_range(0, 60)
		if d < best_d:
			best_d = d
			best = spot
	return best


# ---------------------------------------------------------------- shooting

## Standing still and turning to `dir`: first a moment to react, then the
## turn itself (a U-turn takes longer than a quarter turn).
func _turn_toward(dir: Vector2, delta: float) -> void:
	if dir == facing:
		_turn_goal = Vector2.ZERO
		return
	if dir != _turn_goal:  # a new turn starts
		var r: float = GameState.diff("enemy_reaction")
		_turn_goal = dir
		_turn_from = facing
		_turn_total = (TURN_180 if dir.dot(facing) < -0.5 else TURN_90) * r
		_turn_left = REACTION * r + _turn_total
	_turn_left -= delta
	if _turn_left <= 0.0:
		facing = dir
		_turn_goal = Vector2.ZERO


## Every time we end up facing a new way (turning on the spot OR while
## driving), the gun needs a moment to settle before it can fire.
func _track_facing(delta: float) -> void:
	if facing != _last_facing:
		_last_facing = facing
		_aim_timer = AIM_TIME * GameState.diff("enemy_reaction")
	_aim_timer = maxf(_aim_timer - delta, 0.0)


func is_turning() -> bool:
	return _turn_goal != Vector2.ZERO


func _update_shooting(delta: float, level: Level, player: Tank, holding: bool) -> void:
	_shoot_timer -= delta
	_since_shot += delta
	var ready := _aim_timer <= 0.0 and not is_turning()

	# Has a player been straight in front of us long enough to notice?
	var player_ahead := player != null and _in_front(player.position, 300.0)
	_seen_time = _seen_time + delta if player_ahead else 0.0
	var noticed: bool = _seen_time >= REACTION * float(GameState.diff("enemy_reaction"))

	var wants := holding or player_ahead or _in_front(target, 400.0)
	var has_reason := holding or (player_ahead and noticed) or _in_front(target, 400.0)
	if shoots_bricks and level and level.brick_ahead(position, facing) and velocity.length() < 1.0:
		has_reason = true  # a brick is in the way: shoot through it
	# Orange barrel glow = "I'm about to shoot at you". Only while getting ready.
	_warning = wants and (not ready or (player_ahead and not noticed)) and active_bullets < max_bullets

	if not ready:
		return  # still turning or steadying the gun
	if has_reason and _since_shot > 0.5 * GameState.diff("enemy_fire_delay"):
		_fire()
	elif _shoot_timer <= 0.0 and not (player_ahead and not noticed):
		_fire()  # a random "potshot" (but never a surprise shot in your face)


func _fire() -> void:
	if shoot():
		_since_shot = 0.0
	_shoot_timer = randf_range(shoot_delay.x, shoot_delay.y)


## Is `pos` straight ahead of us (same row/column, in the direction we face)?
func _in_front(pos: Vector2, max_dist: float) -> bool:
	var d := pos - position
	if d.length() > max_dist:
		return false
	if facing.x != 0.0:
		return absf(d.y) < 10.0 and signf(d.x) == facing.x
	return absf(d.x) < 10.0 and signf(d.y) == facing.y


## Are we in the same row or column as `t`, close enough to take a shot?
func _lined_up_with(t: Node2D, max_dist: float) -> bool:
	var d := t.position - position
	return d.length() < max_dist and (absf(d.x) < 8.0 or absf(d.y) < 8.0)


func _axis_toward(pos: Vector2) -> Vector2:
	var d := pos - position
	if absf(d.x) > absf(d.y):
		return Vector2(signf(d.x), 0.0)
	return Vector2(0.0, signf(d.y))


# ---------------------------------------------------------------- looks

func _current_sprite() -> String:
	if is_bonus and int(Time.get_ticks_msec() / 150) % 2 == 0:
		return "bonus"  # blink red
	return sprite_name


func _current_tint() -> Color:
	if frozen:
		return Color("#9fd8ff")
	if kind == Kind.ARMOR:  # armor tanks glow hotter as they get damaged
		return Color.WHITE.lerp(Color(1.6, 1.1, 0.4), (4 - hp) / 3.0)
	return Color.WHITE


## While turning on the spot, rotate the sprite smoothly (after the reaction pause).
func _draw_angle() -> float:
	if is_turning() and _turn_total > 0.0 and _turn_left < _turn_total:
		var t := 1.0 - _turn_left / _turn_total
		return lerp_angle(_turn_from.angle(), _turn_goal.angle(), t) + PI / 2.0
	return super()


func _draw_extra() -> void:
	if _warning and not frozen:
		# Barrel glow: pulses at the tip of the gun (tank-space: gun points UP).
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 45.0)
		draw_circle(Vector2(0, -16), 3.0 + pulse * 1.5, Color(1.0, 0.55, 0.1, 0.45 + 0.4 * pulse))
		draw_circle(Vector2(0, -16), 1.5, Color(1.0, 0.95, 0.6))
	if not GameState.debug_paths or _path.is_empty():
		return
	# Debug view (F3): draw the planned route. We're inside Tank._draw's rotated
	# transform, so undo it first.
	draw_set_transform(Vector2.ZERO)
	var pts := PackedVector2Array([Vector2.ZERO])
	for p in _path:
		pts.append(Level.to_pos(p) - position)
	var col := Color(1, 0.3, 0.3, 0.8) if brain == Brain.HUNTER else Color(1, 0.8, 0.2, 0.8)
	draw_polyline(pts, col, 1.5)
	draw_set_transform(Vector2.ZERO, _draw_angle())  # back to tank-space for subclasses
