class_name PowerUp
extends Area2D
## A pick-up dropped by red "bonus" tanks. Only the player can collect it.

signal collected(kind: Kind, by: Player)

enum Kind { STAR, SHIELD, FREEZE, BOMB, FORTIFY, LIFE }

const COLORS := {
	Kind.STAR: Color("#f2c230"), Kind.SHIELD: Color("#6fd0ff"), Kind.FREEZE: Color("#b0e6ff"),
	Kind.BOMB: Color("#ff6b4a"), Kind.FORTIFY: Color("#c9ccd4"), Kind.LIFE: Color("#6fe07a"),
}
const LIFETIME := 15.0

var kind: Kind
var _age := 0.0


func _init(p_kind: Kind) -> void:
	kind = p_kind
	z_index = 15  # above bushes, so you can always see it


func _ready() -> void:
	collision_layer = Layers.POWERUPS
	collision_mask = Layers.TANKS
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 24)
	var shape := CollisionShape2D.new()
	shape.shape = rect
	add_child(shape)
	body_entered.connect(_on_body_entered)
	Sfx.play("powerup_appear")


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
	# Blink faster when about to disappear.
	var blink_speed := 8.0 if _age > LIFETIME - 4.0 else 2.0
	visible = fmod(_age * blink_speed, 1.0) < 0.75
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		collected.emit(kind, body)
		queue_free()


func _draw() -> void:
	var bob := sin(_age * 5.0) * 1.5
	var r := Rect2(-12, -12 + bob, 24, 24)
	draw_rect(r.grow(2), Color(0, 0, 0, 0.7))
	draw_rect(r.grow(2), COLORS[kind], false, 1.0)
	# assets/sprites/powerups.png holds one 12x12 icon per Kind, in enum order.
	Art.draw_frame(self, "powerups", kind, Vector2(12, 12), Vector2(0, bob))
