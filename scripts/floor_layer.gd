class_name FloorLayer
extends Node2D
## Draws the floor tiles (ice, mud, conveyor belts, teleporter pads) in one go.
## Floor tiles have no collision: tanks drive over them, and Level/Tank decide
## what they do. This node is added to Level FIRST, so it's drawn under the
## walls and tanks.

var level: Level
var _frame := -1


func _process(_delta: float) -> void:
	# Belts and pads animate; only redraw when the frame changes.
	var f := int(Time.get_ticks_msec() / 90)
	if f != _frame:
		_frame = f
		queue_redraw()


func _draw() -> void:
	# Ice and mud: per 16px cell, like walls.
	for c: Vector2i in level.floor:
		var kind: String = level.floor[c]["kind"]
		if kind == "ice" or kind == "mud":
			Art.draw_frame(self, kind, 0, Vector2(8, 8), Vector2(c * Level.CELL) + Vector2(8, 8))
	# Belts and pads: one 16x16 sprite per 32px block (drawn at 2x).
	for b: Vector2i in level.blocks_with_floor:
		var info: Dictionary = level.floor[b * 2]
		var center := Vector2(b * Level.BLOCK) + Vector2(16, 16)
		if info["kind"] == "belt":
			# The sprite points up: rotate it to the belt's direction.
			var dir: Vector2 = info["dir"]
			draw_set_transform(center, dir.angle() + PI / 2.0)
			Art.draw_frame(self, "conveyor", _frame % 4, Vector2(16, 16), Vector2.ZERO)
			draw_set_transform(Vector2.ZERO)
		elif info["kind"] == "tele":
			Art.draw_frame(self, "teleporter", (_frame / 4) % 2, Vector2(16, 16), center)
