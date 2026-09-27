extends Node2D
## Level editor. Paint a 13x13 map, test-play it, save it, share it.
##
## Mouse:     left-drag paints, right-drag erases, click a tile in the sidebar
## Keyboard:  arrows/WASD move the cursor, Space paints, X erases,
##            1-9 and 0 pick a tile, R rotates the conveyor belt,
##            Ctrl+Z undo, Ctrl+S save, T test, Esc menu
## Gamepad:   D-pad moves, A paints, B erases
##
## Levels are saved as plain text in user://levels/<name>.txt, in the same
## format as LevelData.MAPS (so "Copy as code" can paste one into the game).

const TOOLS := [
	{"char": ".", "name": "Erase"},
	{"char": "B", "name": "Brick"},
	{"char": "S", "name": "Steel"},
	{"char": "W", "name": "Water"},
	{"char": "G", "name": "Bush"},
	{"char": "I", "name": "Ice"},
	{"char": "M", "name": "Mud"},
	{"char": "belt", "name": "Belt"},  # the real character depends on the direction
	{"char": "T", "name": "Telep."},
	{"char": "X", "name": "Barrel"},
]
const BELT_CHARS := ["^", ">", "V", "<"]  # R cycles through these
const BLOCK := 32
const LEVELS_DIR := "user://levels/"

var map := PackedStringArray()
var level_name := "my_level"
var tool_index := 1
var belt_dir := 0  # index into BELT_CHARS
var cursor := Vector2i(6, 6)

var _painting := false
var _erasing := false
var _undo: Array[PackedStringArray] = []
var _tool_buttons: Array[Button] = []
var _dialog: CanvasLayer = null
var _toast: Label
var _name_label: Label


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_tree().paused = false
	Music.play("upgrade")
	# Come back to the map you were working on (e.g. after a test play).
	map = GameState.editor_map if not GameState.editor_map.is_empty() else _empty_map()
	if GameState.custom_name != "" and GameState.return_scene == GameState.EDITOR_SCENE:
		level_name = GameState.custom_name
	_build_sidebar()
	_select_tool(tool_index)


func _process(_delta: float) -> void:
	queue_redraw()  # conveyor belts animate


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if _dialog:
		return  # a Save/Load window is open

	# --- mouse
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_painting = mb.pressed
			if mb.pressed:
				_begin_stroke()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_erasing = mb.pressed
			if mb.pressed:
				_begin_stroke()
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		var m := get_global_mouse_position()
		if m.x < Level.SIZE and m.y < Level.SIZE and m.x >= 0 and m.y >= 0:
			cursor = Vector2i(int(m.x / BLOCK), int(m.y / BLOCK))
			if _painting:
				_paint(cursor, _tool_char())
			elif _erasing:
				_paint(cursor, ".")
			queue_redraw()
		return

	# --- keyboard / gamepad
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key >= KEY_1 and key <= KEY_9:
			_select_tool(key - KEY_1)
			return
		if key == KEY_0:
			_select_tool(9)
			return
		if key == KEY_R:
			_rotate_belt()
			return
		if (event as InputEventKey).ctrl_pressed and key == KEY_Z:
			_undo_last()
			return
		if (event as InputEventKey).ctrl_pressed and key == KEY_S:
			_open_save_dialog()
			return
		if key == KEY_T:
			_test_play()
			return
		if key == KEY_X or key == KEY_BACKSPACE or key == KEY_DELETE:
			_begin_stroke()
			_paint(cursor, ".")
			return
	for dir in [["move_up", Vector2i.UP], ["move_down", Vector2i.DOWN],
			["move_left", Vector2i.LEFT], ["move_right", Vector2i.RIGHT]]:
		if event.is_action_pressed(dir[0], true):  # true = also key repeat
			cursor = (cursor + dir[1]).clamp(Vector2i.ZERO, Vector2i(12, 12))
			queue_redraw()
			return
	if event.is_action_pressed("fire"):
		_begin_stroke()
		_paint(cursor, _tool_char())
	elif event.is_action_pressed("ui_cancel") and not event.is_action("pause"):
		_begin_stroke()
		_paint(cursor, ".")  # gamepad B erases
	elif event.is_action_pressed("pause"):
		_back_to_menu()


# ---------------------------------------------------------------- editing

func _paint(block: Vector2i, ch: String) -> void:
	if block in LevelData.PROTECTED:
		return
	var row := map[block.y]
	if row[block.x] == ch:
		return
	map[block.y] = row.left(block.x) + ch + row.substr(block.x + 1)
	GameState.editor_map = map
	Sfx.play("ui_move", -10.0, 0.1)
	queue_redraw()


## Save a copy of the map before each stroke, so Ctrl+Z can undo it.
func _begin_stroke() -> void:
	_undo.append(map.duplicate())
	if _undo.size() > 50:
		_undo.pop_front()


func _undo_last() -> void:
	if _undo.is_empty():
		return
	map = _undo.pop_back()
	GameState.editor_map = map
	queue_redraw()
	_show_toast("Undo")


## The map character the current tool paints.
func _tool_char() -> String:
	var ch: String = TOOLS[tool_index]["char"]
	return BELT_CHARS[belt_dir] if ch == "belt" else ch


func _rotate_belt() -> void:
	belt_dir = (belt_dir + 1) % BELT_CHARS.size()
	_select_tool(7)
	# Rotating while the cursor is on a belt turns that belt too.
	if map[cursor.y][cursor.x] in BELT_CHARS:
		_begin_stroke()
		_paint(cursor, _tool_char())


func _select_tool(i: int) -> void:
	tool_index = i
	for b in _tool_buttons.size():
		_tool_buttons[b].button_pressed = b == i
	if _tool_buttons.size() > 7:
		_tool_buttons[7].text = "Belt " + ["^", ">", "v", "<"][belt_dir]


func _empty_map() -> PackedStringArray:
	var m := PackedStringArray()
	for y in LevelData.SIZE:
		m.append(".".repeat(LevelData.SIZE))
	return m


# ---------------------------------------------------------------- actions

func _test_play() -> void:
	GameState.editor_map = map
	GameState.start_custom(LevelData.sanitize(map), level_name, GameState.EDITOR_SCENE)


func _back_to_menu() -> void:
	GameState.editor_map = map
	get_tree().change_scene_to_file(GameState.TITLE_SCENE)


func _save(file_name: String) -> void:
	var clean := _clean_name(file_name)
	DirAccess.make_dir_recursive_absolute(LEVELS_DIR)
	var f := FileAccess.open(LEVELS_DIR + clean + ".txt", FileAccess.WRITE)
	if f == null:
		_show_toast("Could not save!")
		return
	f.store_string("\n".join(map) + "\n")
	f.close()
	level_name = clean
	_name_label.text = level_name
	_show_toast("Saved \"%s\"" % clean)


func _load(new_map: PackedStringArray, new_name: String) -> void:
	_begin_stroke()
	map = LevelData.sanitize(new_map)
	level_name = new_name
	_name_label.text = level_name
	GameState.editor_map = map
	queue_redraw()
	_show_toast("Loaded \"%s\"" % new_name)


func _copy_as_code() -> void:
	DisplayServer.clipboard_set(LevelData.to_gdscript(map, level_name))
	_show_toast("Copied! Paste it into MAPS in level_data.gd")


## Level names become file names: keep them simple.
static func _clean_name(text: String) -> String:
	var out := ""
	for ch in text.strip_edges().to_lower().replace(" ", "_"):
		if ch in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			out += ch
	return out.left(24) if out != "" else "level"


# ---------------------------------------------------------------- UI

func _build_sidebar() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var bg := ColorRect.new()
	bg.color = Color("#24242c")
	bg.position = Vector2(Level.SIZE, 0)
	bg.size = Vector2(512 - Level.SIZE, 416)
	ui.add_child(bg)

	var box := VBoxContainer.new()
	box.theme = UITheme.make()
	box.theme.default_font_size = 11
	box.position = Vector2(Level.SIZE + 6, 6)
	box.custom_minimum_size = Vector2(512 - Level.SIZE - 12, 0)
	box.add_theme_constant_override("separation", 3)
	ui.add_child(box)

	MenuKit.label(box, "EDITOR", 14, UITheme.ACCENT)
	_name_label = MenuKit.label(box, level_name, 10, Color("#9fd8ff"))
	_name_label.clip_text = true

	# Narrow buttons: two per row, with small padding.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := box.theme.get_stylebox(state, "Button") as StyleBoxFlat
		sb.content_margin_left = 2
		sb.content_margin_right = 2
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3

	MenuKit.label(box, "TILES  (1-9, 0)", 9, Color("#9aa0b0"))
	var tools := GridContainer.new()
	tools.columns = 2
	tools.add_theme_constant_override("h_separation", 3)
	tools.add_theme_constant_override("v_separation", 3)
	box.add_child(tools)
	var group := ButtonGroup.new()  # only one tool can be selected
	for i in TOOLS.size():
		var b := MenuKit.button(tools, TOOLS[i]["name"], _select_tool.bind(i))
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(40, 0)
		b.tooltip_text = "Key %d" % ((i + 1) % 10)
		_tool_buttons.append(b)
	MenuKit.label(box, "R: rotate belt", 9, Color("#9aa0b0"))
	box.add_child(HSeparator.new())
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 3)
	actions.add_theme_constant_override("v_separation", 3)
	box.add_child(actions)
	MenuKit.button(actions, "Test", _test_play)
	MenuKit.button(actions, "Save", _open_save_dialog)
	MenuKit.button(actions, "Load", _open_load_dialog)
	MenuKit.button(actions, "Undo", _undo_last)
	MenuKit.button(actions, "Copy", _copy_as_code).tooltip_text = "Copy the level as GDScript"
	MenuKit.button(actions, "Clear", func() -> void:
		_begin_stroke()
		map = _empty_map()
		GameState.editor_map = map
		queue_redraw())
	MenuKit.button(actions, "Random", func() -> void:
		_begin_stroke()  # (so Undo brings your map back)
		map = LevelGen.generate(maxi(GameState.stage, 6), randi())  # stage 6+: every tile type
		GameState.editor_map = map
		queue_redraw()).tooltip_text = "Make a random map to start from"
	MenuKit.button(actions, "Menu", _back_to_menu)
	for b in actions.get_children():
		(b as Control).custom_minimum_size = Vector2(40, 0)
	# Sidebar buttons are for the mouse; the keyboard drives the map cursor.
	for grid in [tools, actions]:
		for child in grid.get_children():
			(child as Button).focus_mode = Control.FOCUS_NONE

	_toast = Label.new()
	_toast.position = Vector2(0, 8)
	_toast.size = Vector2(Level.SIZE, 24)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 14)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.add_child(_toast)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


## A small popup window (Save / Load). Returns the page to fill.
func _open_dialog(title: String) -> VBoxContainer:
	_painting = false
	_erasing = false
	_dialog = CanvasLayer.new()
	_dialog.layer = 30
	add_child(_dialog)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(512, 416)
	_dialog.add_child(dim)
	var page := MenuKit.page(title, 240.0)
	var pc := MenuKit.panel(page)
	_dialog.add_child(pc)
	MenuKit.center(pc)
	return page


func _close_dialog() -> void:
	if _dialog:
		_dialog.queue_free()
		_dialog = null


func _open_save_dialog() -> void:
	var page := _open_dialog("SAVE LEVEL")
	MenuKit.label(page, "Name:", 12)
	var edit := LineEdit.new()
	edit.text = level_name
	edit.max_length = 24
	page.add_child(edit)
	var save := func() -> void:
		_save(edit.text)
		_close_dialog()
	edit.text_submitted.connect(func(_t: String) -> void: save.call())
	MenuKit.button(page, "Save", save)
	MenuKit.button(page, "Cancel", _close_dialog)
	edit.grab_focus.call_deferred()
	edit.select_all.call_deferred()


func _open_load_dialog() -> void:
	var page := _open_dialog("LOAD LEVEL")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	page.add_child(scroll)

	for n in _list_levels():
		MenuKit.button(list, n, func() -> void:
			var text := FileAccess.get_file_as_string(LEVELS_DIR + n + ".txt")
			_load(text.split("\n"), n)
			_close_dialog())
	# The built-in stages make good starting points.
	for i in LevelData.MAPS.size():
		MenuKit.button(list, "Stage %d (built-in)" % (i + 1), func() -> void:
			_load(LevelData.MAPS[i], "stage_%d_remix" % (i + 1))
			_close_dialog())
	MenuKit.button(page, "Cancel", _close_dialog)
	(list.get_child(0) as Control).grab_focus.call_deferred()


func _list_levels() -> Array[String]:
	var names: Array[String] = []
	for file in DirAccess.get_files_at(LEVELS_DIR):
		if file.ends_with(".txt"):
			names.append(file.get_basename())
	names.sort()
	return names


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(0, 0, Level.SIZE, Level.SIZE), Color.BLACK)
	for y in LevelData.SIZE:
		for x in LevelData.SIZE:
			_draw_block(Vector2i(x, y), map[y][x])

	# Grid lines
	for i in range(0, LevelData.SIZE + 1):
		var c := Color(1, 1, 1, 0.07)
		draw_line(Vector2(i * BLOCK, 0), Vector2(i * BLOCK, Level.SIZE), c)
		draw_line(Vector2(0, i * BLOCK), Vector2(Level.SIZE, i * BLOCK), c)

	# Fixed things you can't paint over
	for spawn in [Vector2i(0, 0), Vector2i(6, 0), Vector2i(12, 0)]:
		_draw_marker(spawn, "basic", Color(1, 0.3, 0.3, 0.25))
	_draw_marker(Vector2i(4, 12), "player", Color(1, 0.85, 0.2, 0.25))
	for c in Level.base_ring_cells():
		Art.draw_frame(self, "brick", 0, Vector2(8, 8), Vector2(c * 16) + Vector2(8, 8))
	Art.draw_frame(self, "base", 0, Vector2(16, 16), Level.BASE_POS)

	# Cursor
	var blocked := cursor in LevelData.PROTECTED
	var rect := Rect2(Vector2(cursor * BLOCK), Vector2(BLOCK, BLOCK))
	draw_rect(rect, Color("#ff5a4a") if blocked else UITheme.ACCENT, false, 2.0)


func _draw_block(b: Vector2i, ch: String) -> void:
	var top_left := Vector2(b * BLOCK)
	match ch:
		"B", "S", "W":
			var tile: String = {"B": "brick", "S": "steel", "W": "water"}[ch]
			for dy in 2:
				for dx in 2:
					Art.draw_frame(self, tile, 0, Vector2(8, 8), top_left + Vector2(dx * 16 + 8, dy * 16 + 8))
		"G":
			Art.draw_frame(self, "bush", 0, Vector2(16, 16), top_left + Vector2(16, 16))
		"I", "M":
			var floor_tile: String = "ice" if ch == "I" else "mud"
			for dy in 2:
				for dx in 2:
					Art.draw_frame(self, floor_tile, 0, Vector2(8, 8), top_left + Vector2(dx * 16 + 8, dy * 16 + 8))
		"T":
			Art.draw_frame(self, "teleporter", 0, Vector2(16, 16), top_left + Vector2(16, 16))
		"X":
			Art.draw_frame(self, "barrel", 0, Vector2(16, 16), top_left + Vector2(16, 16))
		_:
			if Level.CONVEYOR_DIRS.has(ch):
				var dir: Vector2 = Level.CONVEYOR_DIRS[ch]
				draw_set_transform(top_left + Vector2(16, 16), dir.angle() + PI / 2.0)
				Art.draw_frame(self, "conveyor", int(Time.get_ticks_msec() / 90) % 4, Vector2(16, 16), Vector2.ZERO)
				draw_set_transform(Vector2.ZERO)


func _draw_marker(b: Vector2i, sprite: String, tint: Color) -> void:
	var top_left := Vector2(b * BLOCK)
	draw_rect(Rect2(top_left, Vector2(BLOCK, BLOCK)), tint)
	Art.draw_frame(self, "tank_" + sprite, 0, Vector2(16, 16), top_left + Vector2(16, 16), Color(1, 1, 1, 0.5))
