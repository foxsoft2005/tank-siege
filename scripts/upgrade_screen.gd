class_name UpgradeScreen
extends CanvasLayer
## "Choose 1 of 3" upgrade cards, shown between stages while the game is paused.
## (1 of 4 with the Wide Choice perk, and a Reroll button with the Reroll perk.)
## Built from regular UI nodes (Controls). Each card is a Button, so
## mouse, keyboard (arrows + Enter/Space) and gamepad (D-pad + A) all
## work for free through Godot's built-in focus system.

signal picked(id: String)

const CARD_HEIGHT := 196.0

var _choices: Array[String]
var _stage: int
var _can_reroll := false
var _cards: Array[Button] = []
var _row: HBoxContainer
var _reroll_button: Button


func _init(choices: Array[String], stage: int, can_reroll := false) -> void:
	_choices = choices
	_stage = stage
	_can_reroll = can_reroll
	layer = 10  # draw above the HUD
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep working while the game is paused


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.82)
	dim.size = Vector2(512, 416)
	add_child(dim)

	var title := _label("STAGE %d CLEAR" % _stage, 24, Color("#f2c230"))
	title.position = Vector2(0, 30)
	title.size = Vector2(512, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var sub := _label("Choose an upgrade", 14, Color("#c9ccd4"))
	sub.position = Vector2(0, 64)
	sub.size = Vector2(512, 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.position = Vector2(0, 100)
	_row.size = Vector2(512, CARD_HEIGHT)
	add_child(_row)
	_build_cards()

	if _can_reroll:
		_reroll_button = Button.new()
		_reroll_button.text = "Reroll cards (once)"
		_reroll_button.theme = UITheme.make()
		_reroll_button.position = Vector2(186, 308)
		_reroll_button.size = Vector2(140, 26)
		_reroll_button.pressed.connect(_reroll)
		add_child(_reroll_button)

	var hint := _label("← →  choose     Enter / Space / click  pick", 11, Color("#7d8290"))
	hint.position = Vector2(0, 344)
	hint.size = Vector2(512, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)

	_lock_cards(0.6)


## Create one card per choice. Cards get narrower when there are 4.
func _build_cards() -> void:
	for card in _cards:
		card.queue_free()
	_cards.clear()
	var width := minf(148.0, (496.0 - 12.0 * (_choices.size() - 1)) / _choices.size())
	for i in _choices.size():
		var card := _make_card(_choices[i], Vector2(width, CARD_HEIGHT))
		_row.add_child(card)
		_cards.append(card)
		# Cards fade in one after another.
		card.modulate.a = 0.0
		create_tween().tween_property(card, "modulate:a", 1.0, 0.25).set_delay(0.1 * i)


## Short delay before cards can be picked, so a player still mashing
## the fire button doesn't grab the first card by accident.
func _lock_cards(seconds: float) -> void:
	for card in _cards:
		card.disabled = true
	await get_tree().create_timer(seconds).timeout
	for card in _cards:
		if is_instance_valid(card):
			card.disabled = false
	if not _cards.is_empty():
		_cards[0].grab_focus()


func _reroll() -> void:
	_reroll_button.queue_free()
	_choices = Upgrades.roll_choices(GameState.upgrades, _choices.size())
	Sfx.play("cheat", -4.0, 0.0)
	_build_cards()
	_lock_cards(0.3)


func _make_card(id: String, card_size: Vector2) -> Button:
	var data: Dictionary = Upgrades.ALL[id]
	var rarity_color := Upgrades.color(id)
	var level := GameState.stacks(id)

	var card := Button.new()
	card.custom_minimum_size = card_size
	card.focus_mode = Control.FOCUS_ALL
	card.add_theme_stylebox_override("normal", _style(rarity_color, Color("#1b1c24"), 2))
	card.add_theme_stylebox_override("hover", _style(rarity_color, Color("#262836"), 2))
	card.add_theme_stylebox_override("pressed", _style(rarity_color, Color("#30334a"), 2))
	card.add_theme_stylebox_override("disabled", _style(rarity_color.darkened(0.4), Color("#15161c"), 2))
	# "focus" is drawn ON TOP of the other styles, so it's just a bright outline.
	var focus := _style(Color.WHITE, Color.TRANSPARENT, 3)
	focus.draw_center = false
	card.add_theme_stylebox_override("focus", focus)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE  # let clicks reach the button
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var rarity_name: String = Upgrades.RARITY_NAMES[data["rarity"]]
	box.add_child(_label(rarity_name, 10, rarity_color))
	var name_label := _label(data["name"], 16, Color.WHITE)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)
	var level_text := "NEW" if level == 0 else "LV %d → %d" % [level, level + 1]
	if id == "field_repair":
		level_text = "INSTANT"
	box.add_child(_label(level_text, 11, Color("#f2c230")))
	var desc := _label(data["desc"], 12, Color("#c9ccd4"))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc)

	card.pressed.connect(_on_card_pressed.bind(id))
	# Grow the focused card a little. Mouse hover moves focus too.
	card.mouse_entered.connect(func() -> void:
		if not card.disabled:
			card.grab_focus())
	card.focus_entered.connect(_set_card_scale.bind(card, 1.06))
	card.focus_entered.connect(Sfx.play.bind("ui_move", -2.0, 0.0))
	card.focus_exited.connect(_set_card_scale.bind(card, 1.0))
	return card


func _set_card_scale(card: Button, s: float) -> void:
	card.pivot_offset = card.size / 2.0
	create_tween().tween_property(card, "scale", Vector2(s, s), 0.08)


func _on_card_pressed(id: String) -> void:
	for card in _cards:
		card.disabled = true
	Sfx.play("ui_pick")
	picked.emit(id)
	queue_free()


func _style(border: Color, bg: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	return s


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
