class_name Wall
extends StaticBody2D
## One 16x16 piece of wall. A map "block" (32x32) is made of 4 of these,
## which is why a bullet can chew away half a brick block at a time.

enum Kind { BRICK, STEEL, WATER, BARREL }

const SIZE := 16

var kind: Kind
var cell: Vector2i  # grid coordinates, in 16px cells


func _init(p_kind: Kind, p_cell: Vector2i) -> void:
	kind = p_kind
	cell = p_cell
	position = Vector2(cell * SIZE) + Vector2(SIZE, SIZE) / 2.0
	collision_layer = Layers.WATER if kind == Kind.WATER else Layers.WALLS
	collision_mask = 0  # walls never move, so they don't need to detect anything

	var rect := RectangleShape2D.new()
	rect.size = Vector2(SIZE, SIZE)
	var shape := CollisionShape2D.new()
	shape.shape = rect
	add_child(shape)


var _water_frame := 0


func _ready() -> void:
	set_process(kind == Kind.WATER)  # only water animates


func _process(_delta: float) -> void:
	var f := int(Time.get_ticks_msec() / 600) % 2
	if f != _water_frame:
		_water_frame = f
		queue_redraw()


## Pixel art: each 8x8 tile is drawn at 2x to fill this 16x16 piece.
func _draw() -> void:
	match kind:
		Kind.BRICK:
			Art.draw_frame(self, "brick", 0, Vector2(8, 8), Vector2.ZERO)
		Kind.STEEL:
			Art.draw_frame(self, "steel", 0, Vector2(8, 8), Vector2.ZERO)
		Kind.WATER:
			Art.draw_frame(self, "water", _water_frame, Vector2(8, 8), Vector2.ZERO)
		Kind.BARREL:
			# A barrel covers a whole 32px block (4 wall pieces). Each piece
			# draws its own quarter of the 16x16 barrel sprite.
			var quarter := Rect2(Vector2((cell.x % 2) * 8, (cell.y % 2) * 8), Vector2(8, 8))
			draw_texture_rect_region(Art.tex("barrel"), Rect2(-8, -8, 16, 16), quarter)

