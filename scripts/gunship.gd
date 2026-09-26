class_name Gunship
extends Boss
## SKY RAIDER: the second boss (stages 10, 20, 30...). A helicopter gunship
## that FLIES: it ignores walls and water, so you can't hide behind them.
##
##   Hovers near the top, following you and firing aimed 3-shell bursts.
##   Every few seconds it flashes a red WARNING stripe across one row of the
##   map, then does a STRAFING RUN along that row, raining shells straight
##   down that chew through bricks. Get out of the stripe!
##   Phase 2: runs come more often, and it calls in escorts.
##   Phase 3: enraged (red), faster, and fires rings of 8 shells.
##
## It extends Boss (same health bar, phases, damage and death) and only
## replaces the movement, the attacks and the drawing.

enum Mode { HOVER, WARN, STRAFE }

const STRAFE_SPEED := 150.0
const WARN_TIME := 0.9
const DROP_EVERY := 0.09

var mode := Mode.HOVER
var _strafe_timer := 4.0
var _warn_timer := 0.0
var _strafe_y := 160.0
var _strafe_dir := 1.0
var _drop_timer := 0.0
var _burst_timer := 2.0
var _rotor := 0.0
var _bob := 0.0


func _init() -> void:
	super()
	body_size = Vector2(46, 46)
	speed = 70.0
	display_name = "SKY RAIDER"


func _ready() -> void:
	super()
	# It flies: other tanks and walls don't touch it, but shells still can
	# (Bullet's mask includes the AIR layer).
	collision_layer = Layers.AIR
	collision_mask = 0
	z_index = 15  # above bushes


func setup(stage: int) -> void:
	max_hp = int((36 + 12 * (stage / 10 - 1)) * GameState.diff("boss_hp"))
	hp = max_hp
	points = 6000


# ---------------------------------------------------------------- movement

func _move(delta: float) -> void:
	_rotor += delta * 28.0
	_bob += delta
	var player := nearest_player()
	match mode:
		Mode.HOVER:
			# Drift above the player's column, bobbing gently.
			var tx := clampf(player.position.x if player else 208.0, 60.0, 356.0)
			var target := Vector2(tx, 68.0 + sin(_bob * 1.6) * 10.0)
			position = position.move_toward(target, speed * (1.5 if phase == 3 else 1.0) * delta)
			_strafe_timer -= delta
			if _strafe_timer <= 0.0:
				# Pick a row near the player and warn everyone first.
				_strafe_y = clampf(player.position.y if player else 200.0, 60.0, 300.0)
				_strafe_dir = 1.0 if position.x < 208.0 else -1.0
				_warn_timer = WARN_TIME
				mode = Mode.WARN
				Sfx.play("boss_warning", -8.0, 0.0, 1.4)
		Mode.WARN:
			_warn_timer -= delta
			if _warn_timer <= 0.0:
				mode = Mode.STRAFE
		Mode.STRAFE:
			position.x += _strafe_dir * STRAFE_SPEED * (1.3 if phase == 3 else 1.0) * delta
			position.y = move_toward(position.y, _strafe_y, 260.0 * delta)
			if (_strafe_dir > 0.0 and position.x > 470.0) or (_strafe_dir < 0.0 and position.x < -54.0):
				mode = Mode.HOVER  # fly back in over the walls
				_strafe_timer = [6.5, 4.5, 3.2][phase - 1]
	_tread_phase = _rotor  # (unused by our drawing, but keeps Tank happy)


# ---------------------------------------------------------------- attacks

func _attack(delta: float) -> void:
	var player := nearest_player()
	if mode == Mode.STRAFE:
		# Carpet of shells straight down while it's over the map.
		_drop_timer -= delta
		if _drop_timer <= 0.0 and position.x > 0.0 and position.x < Level.SIZE:
			_drop_timer = DROP_EVERY
			_fire_from(position + Vector2(0, 22), Vector2.DOWN, 240.0)
		return
	if mode != Mode.HOVER:
		return
	# Aimed 3-shell bursts from the wing pods.
	_burst_timer -= delta
	if _burst_timer <= 0.0 and player:
		_burst_timer = [1.8, 1.3, 0.9][phase - 1]
		for side in [-22.0, 22.0]:
			var from := position + Vector2(side, 10)
			var aim := (player.position - from).normalized()
			for spread in [-0.18, 0.0, 0.18]:
				_fire_from(from, aim.rotated(spread), 230.0)
		Sfx.play("enemy_shoot", -2.0, 0.05, 1.3)
	# Escorts from phase 2, rings of shells in phase 3 (like the Fortress)
	if phase >= 2:
		_minion_timer -= delta
		if _minion_timer <= 0.0:
			_minion_timer = 9.0
			wants_minion.emit()
	if phase == 3:
		_ring_timer -= delta
		if _ring_timer <= 0.0:
			_ring_timer = 3.0
			for i in 8:
				var d := Vector2.RIGHT.rotated(TAU * i / 8.0)
				_fire_from(position + d * 26.0, d, 170.0)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	# The warning stripe across the row it's about to strafe (in map coordinates).
	if mode == Mode.WARN and int(Time.get_ticks_msec() / 100) % 2 == 0:
		var top := Vector2(-position.x, _strafe_y - position.y - 16.0)
		draw_rect(Rect2(top, Vector2(Level.SIZE, 32)), Color(1, 0.1, 0.1, 0.28))
		draw_rect(Rect2(top, Vector2(Level.SIZE, 32)), Color(1, 0.2, 0.2, 0.8), false, 1.0)

	var tint := Color.WHITE
	if phase == 3:
		tint = Color.WHITE.lerp(Color(1.8, 0.5, 0.5), 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0))
	if _flash_time > 0.0:
		tint = Color(6, 6, 6)
	# Shadow on the ground (it's flying!), then the ship itself.
	Art.draw_frame(self, "gunship", 0, Vector2(32, 32), Vector2(10, 16), Color(0, 0, 0, 0.35))
	Art.draw_frame(self, "gunship", 0, Vector2(32, 32), Vector2.ZERO, tint)
	# Main rotor: two long blades spinning over the cockpit.
	var hub := Vector2(0, 4)
	for i in 2:
		var d := Vector2.RIGHT.rotated(_rotor + PI / 2.0 * i) * 30.0
		draw_line(hub - d, hub + d, Color(0.85, 0.9, 1.0, 0.45), 3.0)
	draw_circle(hub, 3.0, Color("#26303f"))
