class_name Base
extends StaticBody2D
## The thing you defend. If a shell hits it, the game is over.

signal destroyed
signal shield_broken

var alive := true
var shield_hits := 0  # Core Shield upgrade: hits it can still absorb this stage


func _ready() -> void:
	add_to_group("base")
	collision_layer = Layers.BASE
	collision_mask = 0
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30, 30)
	var shape := CollisionShape2D.new()
	shape.shape = rect
	add_child(shape)


func _process(_delta: float) -> void:
	queue_redraw()  # animate the glow


func hit() -> void:
	if not alive:
		return
	if shield_hits > 0:
		shield_hits -= 1
		Fx.spark(get_parent(), position)
		Sfx.play("shield_block")
		shield_broken.emit()
		return
	alive = false
	Fx.explosion(get_parent(), position, true)
	Sfx.play("explode_big", 0.0, 0.0)
	destroyed.emit()


func _draw() -> void:
	# Sprite sheet assets/sprites/base.png: frame 0 = intact, frame 1 = destroyed.
	if not alive:
		Art.draw_frame(self, "base", 1, Vector2(16, 16), Vector2.ZERO)
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 250.0)
	draw_circle(Vector2.ZERO, 15.0, Color(0.3, 0.9, 1.0, 0.1 + 0.15 * pulse))  # glow
	Art.draw_frame(self, "base", 0, Vector2(16, 16), Vector2.ZERO, Color(1, 1, 1).lerp(Color(1.3, 1.3, 1.3), pulse))
	for i in mini(shield_hits, 4):  # draw at most 4 rings
		draw_arc(Vector2.ZERO, 17.0 + i * 3.0, 0.0, TAU, 24, Color(0.6, 0.85, 1.0, 0.5 + 0.4 * pulse), 1.5)
