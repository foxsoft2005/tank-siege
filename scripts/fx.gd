class_name Fx
extends RefCounted
## Little "juice" helpers: particle bursts for explosions, sparks and debris.
## Game feel matters a lot. Try changing these numbers and see what happens!


static func explosion(parent: Node, pos: Vector2, big: bool) -> void:
	var g := Gradient.new()
	g.set_color(0, Color("#fff6b0"))
	g.add_point(0.35, Color("#ff9a2e"))
	g.set_color(g.get_point_count() - 1, Color(0.6, 0.1, 0.05, 0.0))
	_burst(parent, pos, 28 if big else 10, 0.55 if big else 0.25,
			160.0 if big else 70.0, 3.0 if big else 2.0, g)


static func spark(parent: Node, pos: Vector2) -> void:
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1, 0.8, 0.3, 0))
	_burst(parent, pos, 6, 0.15, 60.0, 1.5, g)


static func debris(parent: Node, pos: Vector2, steel: bool) -> void:
	var g := Gradient.new()
	g.set_color(0, Color("#d6dbe3") if steel else Color("#b0552a"))
	g.set_color(1, Color(0.3, 0.3, 0.3, 0))
	_burst(parent, pos, 5, 0.35, 50.0, 2.0, g)


static func _burst(parent: Node, pos: Vector2, amount: int, lifetime: float,
		speed: float, size: float, colors: Gradient) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 20
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.damping_min = speed
	p.damping_max = speed * 2.0
	p.scale_amount_min = size
	p.scale_amount_max = size * 1.8
	p.color_ramp = colors
	parent.add_child(p)
	p.emitting = true
	# Free the node once the particles are done (false = pauses with the game).
	parent.get_tree().create_timer(lifetime + 0.3, false).timeout.connect(p.queue_free)
