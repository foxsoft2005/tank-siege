class_name ShieldedEnemy
extends Enemy
## SHIELDED: a steel plate on its FRONT blocks your shells. Hit it from the
## side or from behind. Explosions (Blast Shells, Bomb, Kamikazes) ignore the
## shield, because they have no direction.

func _configure() -> void:
	speed = 45.0
	points = 400
	hp = 2
	sprite_name = "shielded"


func hit(from_dir := Vector2.ZERO, damage := 1) -> void:
	# A shell travelling AGAINST our facing direction is hitting the front.
	# dot() of two opposite directions is -1, of perpendicular ones 0.
	if from_dir != Vector2.ZERO and from_dir.dot(facing) < -0.5:
		Sfx.play("deflect", -2.0)
		Fx.spark(get_parent(), position + facing * 16.0)
		_flash_time = 0.04
		return
	super(from_dir, damage)


func _draw_extra() -> void:
	super()
	# The shield plate, drawn in front of the tank (drawing is rotated so
	# "up" is always the front).
	draw_rect(Rect2(-13, -19, 26, 4), Color("#dfe8ee"))
	draw_rect(Rect2(-13, -19, 26, 1), Color.WHITE)
	draw_rect(Rect2(-13, -16, 26, 1), Color("#5a6070"))
