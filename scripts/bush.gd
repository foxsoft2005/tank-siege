class_name Bush
extends Node2D
## Decoration drawn ABOVE tanks and bullets (high z_index), so things hide in it.
## It has no physics body, so nothing collides with it.

func _init(block_pos: Vector2) -> void:
	position = block_pos
	z_index = 10


func _draw() -> void:
	Art.draw_frame(self, "bush", 0, Vector2(16, 16), Vector2.ZERO)

