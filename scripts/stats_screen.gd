class_name StatsScreen
extends CanvasLayer
## The stats screen, shown after a stage is cleared and at game over.
##
##   Left:   a "DESTROYED" tally like the original game: one row per enemy
##           type, counting up with a blip per tank (two columns in co-op).
##   Right:  the numbers: time, shells, accuracy, best combo, walls, power-ups...
##   Bottom: stage AWARDS (small score bonuses for playing well) and any
##           achievements unlocked along the way.
##
## Everything animates in. Press Fire / Enter to skip the animation, then again
## to continue. At game over there are Retry / Main menu buttons instead.
##
## Main builds the `data` dictionary (see Main._stats_data) and waits for
## `closed`, which says what to do next: "continue", "retry" or "menu".

signal closed(choice: String)

## Enemy types in tally order: stats key, sprite, sprite frame size, base points.
const ROWS := [
	["basic", "tank_basic", 16, 100], ["fast", "tank_fast", 16, 200],
	["power", "tank_power", 16, 300], ["armor", "tank_armor", 16, 400],
	["kamikaze", "tank_kamikaze", 16, 200], ["sniper", "tank_sniper", 16, 300],
	["shielded", "tank_shielded", 16, 400], ["engineer", "tank_engineer", 16, 250],
	["fortress", "boss", 32, 5000], ["gunship", "gunship", 32, 6000],
]
const GOLD := Color("#f2c230")
const DIM := Color("#8a8f9e")

var _data: Dictionary
var _game_over: bool
var _coop: bool
var _skip := false         # the player pressed a button: finish instantly
var _done := false         # animation finished; the next press continues
var _opened_at := 0
var _hint: Label
var _buttons: HBoxContainer


## data keys: title, subtitle, stats (a stats Dictionary), time (seconds),
## score_line, medals [{name, desc, bonus, tier}], achievements [ids],
## extra [String], game_over (bool)
func _init(data: Dictionary) -> void:
	_data = data
	_game_over = data.get("game_over", false)
	_coop = GameState.coop
	layer = 20  # above the HUD and messages
	process_mode = Node.PROCESS_MODE_ALWAYS  # works while the game is paused


func _ready() -> void:
	_opened_at = Time.get_ticks_msec()
	Achievements.clear_toasts()  # they're all listed on this screen anyway
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.94)
	dim.size = Vector2(512, 416)
	add_child(dim)

	var title := _label(_data.get("title", ""), 26, Color("#ff6b4a") if _game_over else GOLD, Vector2(0, 10), 512)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label(_data.get("subtitle", ""), 12, Color("#c9ccd4"), Vector2(0, 44), 512)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Divider between the two columns
	var line := ColorRect.new()
	line.color = Color("#2c2e3a")
	line.position = Vector2(262, 70)
	line.size = Vector2(1, 222)
	add_child(line)

	_play()


# ---------------------------------------------------------------- animation

func _play() -> void:
	var stats: Dictionary = _data["stats"]
	await _wait(0.35)

	# --- left: the tally
	_label("DESTROYED", 13, Color("#9fd8ff"), Vector2(20, 68))
	if _coop:
		_label("P1", 11, Color("#ffd23f"), Vector2(92, 70), 40).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_label("P2", 11, Color("#7dff8a"), Vector2(140, 70), 40).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var rows: Array = []
	for r in ROWS:
		if GameState.stat(stats, "kills." + r[0]) > 0:
			rows.append(r)
	var row_h := minf(24.0, 196.0 / maxf(rows.size(), 1.0))
	var y := 90.0
	var total := 0
	for r in rows:
		var count := GameState.stat(stats, "kills." + r[0])
		_icon(r[1], r[2], Vector2(34, y + row_h / 2.0), row_h - 4.0)
		var counters: Array[Label] = []
		if _coop:
			counters.append(_label("0", 14, Color.WHITE, Vector2(92, y + row_h / 2.0 - 10.0), 40))
			counters.append(_label("0", 14, Color.WHITE, Vector2(140, y + row_h / 2.0 - 10.0), 40))
		else:
			counters.append(_label("x 0", 14, Color.WHITE, Vector2(60, y + row_h / 2.0 - 10.0), 80))
		for c in counters:
			if _coop:
				c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var pts := _label("", 12, DIM, Vector2(160, y + row_h / 2.0 - 9.0), 92)
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# Count up, one blip per tank (faster when there are lots).
		var p1 := GameState.stat(stats, "kills." + r[0], 0)
		var p2 := GameState.stat(stats, "kills." + r[0], 1)
		var step := minf(0.07, 0.7 / count)
		for i in range(1, count + 1):
			if _coop:  # count up Player 1's first, then Player 2's
				counters[0].text = str(mini(i, p1))
				counters[1].text = str(clampi(i - p1, 0, p2))
			else:
				counters[0].text = "x %d" % i
			pts.text = "%d PTS" % (i * r[3])
			if not _skip:
				Sfx.play("tally", -6.0, 0.0, 1.0 + 0.02 * mini(i, 20))
			await _wait(step)
		if _coop:  # final numbers (barrel and kamikaze blasts aren't anyone's kills)
			counters[0].text = str(p1)
			counters[1].text = str(p2)
		total += count
		y += row_h
		await _wait(0.1)
	if rows.is_empty():
		_label("nothing... yet!", 12, DIM, Vector2(20, 100))
	_label("TOTAL  %d" % total, 14, GOLD, Vector2(20, 294))

	# --- right: the numbers
	await _wait(0.15)
	y = 68.0
	for line: Array in _summary_lines(stats):
		_label(line[0], 12, DIM, Vector2(278, y + 2.0), 120)
		var v := _label(line[1], 13, line[2] if line.size() > 2 else Color.WHITE, Vector2(378, y), 118)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if not _skip:
			Sfx.play("tally", -8.0, 0.0, 0.8)
		y += 17.0 if _game_over else 19.0  # game over has an extra line + records
		await _wait(0.09)
	for extra: String in _data.get("extra", []):
		var e := _label(extra, 12, GOLD, Vector2(278, y + 2.0), 218)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		y += 17.0

	# --- bottom: awards and achievements
	var medals: Array = _data.get("medals", [])
	var achs: Array = _data.get("achievements", [])
	if not medals.is_empty():
		await _wait(0.25)
		await _chip_row("AWARDS", medals, 312.0, 8)  # up to 2 lines
	if not achs.is_empty():
		await _wait(0.2)
		var items: Array = []
		for id: String in achs:
			var a := Achievements.get_info(id)
			items.append({"name": a["name"], "tier": a["tier"], "bonus": 0})
		await _chip_row("ACHIEVEMENTS", items, 362.0 if not medals.is_empty() else 312.0, 3)

	_finish()


func _summary_lines(stats: Dictionary) -> Array:
	var lines := []
	var t := int(_data.get("time", 0.0))
	lines.append(["TIME", "%d:%02d" % [t / 60, t % 60]])
	if _game_over:
		lines.append(["STAGES CLEARED", str(_data.get("stages_cleared", 0))])
	lines.append(["SHELLS FIRED", str(GameState.stat(stats, "shots"))])
	lines.append(["ACCURACY", _accuracy_text(stats)])
	lines.append(["BEST COMBO", "x%d" % GameState.stat(stats, "best_combo")])
	lines.append(["WALLS SMASHED", str(GameState.stat(stats, "bricks"))])
	lines.append(["POWER-UPS", str(GameState.stat(stats, "powerups"))])
	lines.append(["SHELLS SHOT DOWN", str(GameState.stat(stats, "cancels"))])
	lines.append(["ARMOR LOST", str(GameState.stat(stats, "armor_lost"))])
	lines.append(["SCORE", _data.get("score_line", ""), GOLD])
	return lines


func _accuracy_text(stats: Dictionary) -> String:
	if _coop:
		return "%s / %s" % [_acc(stats, 0), _acc(stats, 1)]
	return _acc(stats, -1)


func _acc(stats: Dictionary, player: int) -> String:
	var shots := GameState.stat(stats, "shots", player)
	if shots == 0:
		return "-"
	return "%d%%" % roundi(100.0 * GameState.stat(stats, "hits", player) / shots)


## A labelled row of medal "chips" that pop in one by one. It wraps onto a
## second line when it's full (HFlowContainer); after `max_chips` it just
## says "+N more".
func _chip_row(caption: String, items: Array, y: float, max_chips: int) -> void:
	_label(caption, 10, Color("#9fd8ff"), Vector2(20, y - 2.0))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 0)
	row.position = Vector2(100, y - 8.0)
	row.size = Vector2(400, 20)
	add_child(row)
	for n in items.size():
		var item: Dictionary = items[n]
		if n == max_chips:
			var more := Label.new()
			more.text = "+%d more" % (items.size() - max_chips)
			more.add_theme_font_size_override("font_size", 10)
			more.add_theme_color_override("font_color", DIM)
			row.add_child(more)
			break
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 2)
		chip.add_child(MedalIcon.new(item.get("tier", 1), true, 7.0))
		var text: String = item["name"]
		if item.get("bonus", 0) > 0:
			text += "  +%d" % item["bonus"]
		var l := Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", Achievements.TIER_COLORS[item.get("tier", 1)])
		l.tooltip_text = item.get("desc", "")
		chip.add_child(l)
		row.add_child(chip)
		chip.pivot_offset = Vector2(10, 10)
		if not _skip:
			chip.scale = Vector2(1.6, 1.6)
			var tw := create_tween()
			tw.set_ignore_time_scale(true)
			tw.tween_property(chip, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
			Sfx.play("medal", -3.0, 0.0)
		await _wait(0.28)


func _finish() -> void:
	_done = true
	if _game_over:
		_buttons = HBoxContainer.new()
		_buttons.theme = UITheme.make()
		_buttons.add_theme_constant_override("separation", 16)
		_buttons.position = Vector2(146, 382)
		_buttons.size = Vector2(220, 26)
		_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(_buttons)
		var retry := MenuKit.button(_buttons, "Retry", _close.bind("retry"))
		retry.custom_minimum_size = Vector2(100, 0)
		var menu := MenuKit.button(_buttons, "Main menu", _close.bind("menu"))
		menu.custom_minimum_size = Vector2(100, 0)
		retry.grab_focus()
	else:
		_hint = _label("Press FIRE or ENTER to continue", 12, Color("#c9ccd4"), Vector2(0, 390), 512)
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var tw := create_tween().set_loops()
		tw.tween_property(_hint, "modulate:a", 0.3, 0.5)
		tw.tween_property(_hint, "modulate:a", 1.0, 0.5)


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not _pressed_continue(event):
		return
	if Time.get_ticks_msec() - _opened_at < 400:
		get_viewport().set_input_as_handled()  # still mashing fire from the battle
		return
	if not _done:
		_skip = true  # first press: show everything at once
		get_viewport().set_input_as_handled()
	elif not _game_over:
		get_viewport().set_input_as_handled()
		Sfx.play("ui_pick", 0.0, 0.0)
		_close("continue")
	# (at game over, the Retry / Main menu buttons handle the press themselves)


func _pressed_continue(event: InputEvent) -> bool:
	for action in ["ui_accept", "fire", "p1_fire", "p2_fire", "restart"]:
		if event.is_action_pressed(action):
			return true
	return event is InputEventMouseButton and event.pressed and not _game_over


func _close(choice: String) -> void:
	closed.emit(choice)
	queue_free()


# ---------------------------------------------------------------- helpers

## Wait in real time (works while paused and during hit-stop), unless skipping.
func _wait(seconds: float) -> void:
	if _skip:
		return
	await get_tree().create_timer(seconds, true, false, true).timeout


func _label(text: String, size: int, color: Color, pos: Vector2, width := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	if width > 0.0:
		l.size = Vector2(width, 20)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(l)
	return l


## Frame 0 of a sprite sheet, drawn `px` pixels tall, centred on `center`.
func _icon(sprite: String, frame_px: int, center: Vector2, px: float) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = Art.tex(sprite)
	atlas.region = Rect2(0, 0, frame_px, frame_px)
	var tr := TextureRect.new()
	tr.texture = atlas
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.size = Vector2(px, px)
	tr.position = center - Vector2(px, px) / 2.0
	add_child(tr)
