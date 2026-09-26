class_name MedalIcon
extends Control
## A small medal drawn with code: a ribbon, a round medal in the tier's color
## (bronze / silver / gold) and a star. Locked achievements get a grey medal
## with a padlock. Used by the achievement popup, the title screen list and
## the stats screen.

var tier := 0
var got := true
var radius := 12.0


func _init(p_tier := 0, p_got := true, p_radius := 12.0) -> void:
	tier = p_tier
	got = p_got
	radius = p_radius
	custom_minimum_size = Vector2(radius * 2.0 + 4.0, radius * 2.0 + 10.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := Vector2(size.x / 2.0, size.y - radius - 2.0)
	var metal: Color = Achievements.TIER_COLORS[tier] if got else Color("#4a4d58")
	# Ribbon: two slanted strips above the medal.
	var ribbon := Color("#d6453d") if got else Color("#34363f")
	var top := c.y - radius - 8.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(-radius * 0.7, -radius * 0.4),
		Vector2(c.x - radius * 0.2, top), Vector2(c.x + radius * 0.15, top), c + Vector2(-radius * 0.15, -radius * 0.5)]), ribbon)
	draw_colored_polygon(PackedVector2Array([c + Vector2(radius * 0.7, -radius * 0.4),
		Vector2(c.x + radius * 0.2, top), Vector2(c.x - radius * 0.15, top), c + Vector2(radius * 0.15, -radius * 0.5)]), ribbon.darkened(0.2))
	# The medal: dark rim, metal, lighter inner disc.
	draw_circle(c, radius, metal.darkened(0.45))
	draw_circle(c, radius - 2.0, metal)
	draw_circle(c + Vector2(-1, -1), radius - 4.0, metal.lightened(0.18))
	if got:
		_draw_star(c, radius * 0.55, metal.darkened(0.35))
	else:
		# Padlock
		var s := radius * 0.4
		draw_arc(c + Vector2(0, -s * 0.3), s * 0.6, PI, TAU, 10, Color("#23252c"), 2.0)
		draw_rect(Rect2(c.x - s, c.y - s * 0.3, s * 2.0, s * 1.4), Color("#23252c"))


func _draw_star(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, color)
