class_name FloatingText
extends Node2D
## A little text that pops up, floats upward and fades out: "+200", "x3 COMBO!".
## Spawn one with FloatingText.spawn(parent, position, "text", color).

const LIFETIME := 0.9

var text: String
var color: Color
var size: int
var _age := 0.0


static func spawn(parent: Node, pos: Vector2, p_text: String, p_color := Color.WHITE, p_size := 12) -> void:
	var ft := FloatingText.new()
	ft.text = p_text
	ft.color = p_color
	ft.size = p_size
	ft.position = pos
	ft.z_index = 40  # above everything, even bushes
	parent.add_child(ft)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	position.y -= 28.0 * delta * (1.0 - _age / LIFETIME)  # rise, slowing down
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Pop in (grow quickly), then fade out.
	var t := _age / LIFETIME
	var s := minf(1.0, _age * 12.0) * (1.0 + 0.3 * (1.0 - minf(1.0, _age * 6.0)))
	var alpha := 1.0 - maxf(0.0, (t - 0.6) / 0.4)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(-w / 2.0, size / 3.0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, alpha))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, alpha))
