extends Node2D
## Title screen: logo, main menu, custom levels list, options, high score,
## version number and the update banner.
##
## The background is a little "attract mode": tanks driving across a brick
## field, drawn with the same pixel art as the game.

const LEVELS_DIR := "user://levels/"

var _ui: CanvasLayer
var _panel: PanelContainer
var _pages: VBoxContainer
var _main_page: VBoxContainer
var _levels_page: VBoxContainer
var _options_page: VBoxContainer
var _difficulty_page: VBoxContainer
var _achievements_page: VBoxContainer
var _coop_chosen := false
var _coop_hint: Label
var _best_label: Label
var _diff_desc: Label
var _update_box: VBoxContainer
var _demo_tanks: Array[Dictionary] = []
var _time := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel art
	get_tree().paused = false
	Music.set_muffled(false)
	Music.play("upgrade")
	_spawn_demo_tanks()
	_build_ui()

	# Look for updates once per launch (if a server is configured and allowed).
	Updater.status_changed.connect(_refresh_update_banner)
	if Settings.check_updates and Updater.state == Updater.State.IDLE:
		Updater.check()
	_refresh_update_banner()


func _process(delta: float) -> void:
	_time += delta
	for t in _demo_tanks:
		t.pos += t.vel * delta
		if t.patrol:
			# Side patrols turn around at the ends of their beat.
			if (t.vel.y > 0.0 and t.pos.y > PATROL_BOTTOM) or (t.vel.y < 0.0 and t.pos.y < PATROL_TOP):
				t.vel.y = -t.vel.y
		elif t.pos.x > 512.0 + CONVOY_WRAP:
			t.pos.x -= 512.0 + 2.0 * CONVOY_WRAP  # off the right edge -> back in on the left
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _main_page.visible:
		_show_page(_main_page)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	var logo := Label.new()
	logo.text = "TANK SIEGE"
	logo.position = Vector2(0, 28)
	logo.size = Vector2(512, 60)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_font_size_override("font_size", 52)
	logo.add_theme_color_override("font_color", UITheme.ACCENT)
	logo.add_theme_color_override("font_outline_color", Color("#5a3a00"))
	logo.add_theme_constant_override("outline_size", 12)
	_ui.add_child(logo)

	var sub := Label.new()
	sub.text = "defend the core"
	sub.position = Vector2(0, 88)
	sub.size = Vector2(512, 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color("#9fd8ff"))
	_ui.add_child(sub)

	_pages = VBoxContainer.new()
	_main_page = _build_main_page()
	_levels_page = MenuKit.page("CUSTOM LEVELS", 240.0)  # filled in when opened
	_options_page = MenuKit.options_page(func() -> void: _show_page(_main_page))
	_difficulty_page = _build_difficulty_page()
	_achievements_page = MenuKit.page("ACHIEVEMENTS", 330.0)  # filled in when opened
	for p in [_main_page, _levels_page, _options_page, _difficulty_page, _achievements_page]:
		_pages.add_child(p)
	_panel = MenuKit.panel(_pages)
	_ui.add_child(_panel)

	# Your records, shown under the main menu (placed in _show_page).
	var best := Label.new()
	_best_label = best
	_refresh_best()
	best.size = Vector2(512, 30)
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best.add_theme_font_size_override("font_size", 11)
	best.add_theme_color_override("font_color", Color("#c9ccd4"))
	best.add_theme_color_override("font_outline_color", Color.BLACK)
	best.add_theme_constant_override("outline_size", 4)
	_ui.add_child(best)

	var version := Label.new()
	version.text = "v" + Updater.current_version
	version.position = Vector2(4, 398)
	version.add_theme_font_size_override("font_size", 10)
	version.add_theme_color_override("font_color", Color("#c9ccd4"))
	version.add_theme_color_override("font_outline_color", Color.BLACK)
	version.add_theme_constant_override("outline_size", 4)
	_ui.add_child(version)

	# Update messages appear at the bottom, under the records.
	_update_box = VBoxContainer.new()
	_update_box.theme = UITheme.make()
	_update_box.add_theme_constant_override("separation", 4)
	_update_box.position = Vector2(106, 346)
	_update_box.size = Vector2(300, 50)
	_ui.add_child(_update_box)

	_show_page(_main_page)


## The main menu: 8 buttons in 2 columns, so it fits under the logo with
## room for your records below it. (Arrow keys move in both directions.)
func _build_main_page() -> VBoxContainer:
	var page := MenuKit.page("", 300.0)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	page.add_child(grid)
	var buttons := [
		["Play", func() -> void:
			_coop_chosen = false
			_show_page(_difficulty_page)],
		["Co-op  (2 players)", func() -> void:
			_coop_chosen = true
			_show_page(_difficulty_page)],
		["Garage", func() -> void: get_tree().change_scene_to_file(GameState.GARAGE_SCENE)],
		["Achievements", func() -> void:
			_fill_achievements_page()
			_show_page(_achievements_page)],
		["Custom levels", func() -> void:
			_fill_levels_page()
			_show_page(_levels_page)],
		["Level editor", func() -> void: get_tree().change_scene_to_file(GameState.EDITOR_SCENE)],
		["Options", func() -> void: _show_page(_options_page)],
		["Quit", func() -> void: get_tree().quit()],
	]
	for entry: Array in buttons:
		var b := MenuKit.button(grid, entry[0], entry[1])
		b.custom_minimum_size = Vector2(146, 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return page


## Pick Easy / Normal / Hard, then start. The last choice is remembered.
func _build_difficulty_page() -> VBoxContainer:
	var page := MenuKit.page("DIFFICULTY", 220.0)
	for level: int in [Difficulty.Level.EASY, Difficulty.Level.NORMAL, Difficulty.Level.HARD]:
		var b := MenuKit.button(page, Difficulty.NAMES[level], func() -> void:
			GameState.difficulty = level
			GameState.coop = _coop_chosen
			GameState.save_progress()
			GameState.start_campaign())
		b.add_theme_color_override("font_focus_color", Difficulty.COLORS[level])
		b.add_theme_color_override("font_hover_color", Difficulty.COLORS[level])
		b.focus_entered.connect(_on_difficulty_focus.bind(level))
		b.mouse_entered.connect(b.grab_focus)
		b.name = Difficulty.NAMES[level]
	_coop_hint = MenuKit.label(page, "P1: WASD + Space    P2: arrows + Enter", 10, Color("#7dff8a"))
	_coop_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diff_desc = MenuKit.label(page, "", 11, Color("#c9ccd4"))
	_diff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diff_desc.custom_minimum_size = Vector2(220, 30)
	_diff_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuKit.button(page, "Back", func() -> void: _show_page(_main_page))
	return page


func _on_difficulty_focus(level: int) -> void:
	_diff_desc.text = Difficulty.DESCRIPTIONS[level]
	_diff_desc.add_theme_color_override("font_color", Difficulty.COLORS[level])


## Under the main menu: your record on the last difficulty you played, then
## scrap and achievements.
func _refresh_best() -> void:
	_best_label.text = "%s\n%d scrap   ·   %d of %d achievements" % [_record_text(GameState.difficulty),
		GameState.scrap, Achievements.unlocked_count(), Achievements.LIST.size()]


func _record_text(level: int) -> String:
	var rec := GameState.record_for(level)
	var tag: String = Difficulty.NAMES[level]
	if rec["score"] <= 0:
		return "no %s high score yet" % tag.to_lower()
	return "%s HIGH SCORE  %d   ·   BEST STAGE  %d" % [tag, rec["score"], rec["stage"]]


func _fill_levels_page() -> void:
	for child in _levels_page.get_children().slice(1):  # keep the title label
		child.queue_free()
	var names := list_custom_levels()
	if names.is_empty():
		var l := MenuKit.label(_levels_page, "No levels yet.\nMake one in the Level editor!", 13)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, mini(names.size(), 5) * 34)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_levels_page.add_child(scroll)
	for level_name in names:
		MenuKit.button(list, level_name, func() -> void:
			var map := load_custom_level(level_name)
			GameState.start_custom(map, level_name, GameState.TITLE_SCENE))
	MenuKit.button(_levels_page, "Back", func() -> void: _show_page(_main_page))


## One row per achievement: medal, name, description (or ??? for secrets you
## haven't found), and progress for the counting ones ("37 / 100").
func _fill_achievements_page() -> void:
	for child in _achievements_page.get_children().slice(1):  # keep the title label
		child.queue_free()
	var got := Achievements.unlocked_count()
	var summary := MenuKit.label(_achievements_page, "%d of %d unlocked" % [got, Achievements.LIST.size()], 11, Color("#c9ccd4"))
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bar := ProgressBar.new()
	bar.max_value = Achievements.LIST.size()
	bar.value = got
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	_achievements_page.add_child(bar)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 136)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true  # arrow keys / D-pad scroll the list
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	_achievements_page.add_child(scroll)
	# Unlocked first, then the rest in list order.
	var order: Array[Dictionary] = []
	for a in Achievements.LIST:
		if Achievements.is_unlocked(a["id"]):
			order.append(a)
	for a in Achievements.LIST:
		if not Achievements.is_unlocked(a["id"]):
			order.append(a)
	for a in order:
		list.add_child(_achievement_row(a))
	MenuKit.button(_achievements_page, "Back", func() -> void: _show_page(_main_page))


func _achievement_row(a: Dictionary) -> Control:
	var got := Achievements.is_unlocked(a["id"])
	var hidden: bool = a.get("secret", false) and not got
	# A flat Button, so it can take keyboard focus (and the list scrolls to it).
	var row := Button.new()
	row.focus_mode = Control.FOCUS_ALL
	row.custom_minimum_size = Vector2(0, 38)
	row.flat = true
	var focus := StyleBoxFlat.new()  # a thin gold outline on the row you're on
	focus.draw_center = false
	focus.border_color = UITheme.ACCENT
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(4)
	row.add_theme_stylebox_override("focus", focus)
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_right = -14.0  # keep clear of the scrollbar
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)
	box.add_child(MedalIcon.new(a["tier"], got, 10.0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)
	var title := MenuKit.label(col, "SECRET" if hidden else a["name"], 13,
		Achievements.TIER_COLORS[a["tier"]] if got else Color("#9aa0b0"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var desc := MenuKit.label(col, "Keep playing to find this one." if hidden else a["desc"], 10,
		Color("#c9ccd4") if got else Color("#6f7482"))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var progress := Achievements.progress_text(a)
	if progress != "":
		var p := MenuKit.label(box, progress, 10, Color("#9fd8ff"))
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


func _show_page(page: VBoxContainer) -> void:
	for p in _pages.get_children():
		p.visible = p == page
	# Records and update messages belong to the main menu only; other pages
	# are taller and would cover them.
	_best_label.visible = page == _main_page
	_update_box.visible = page == _main_page
	if _coop_hint:
		_coop_hint.visible = _coop_chosen
	await MenuKit.center(_panel, 38.0)
	_panel.position.y = maxf(_panel.position.y, 116.0)  # stay below the logo...
	_panel.position.y = minf(_panel.position.y, 412.0 - _panel.size.y)  # ...but on screen
	if page == _main_page:
		_panel.position.y = 118.0  # right under the logo, records below it
		_best_label.position = Vector2(0, _panel.position.y + _panel.size.y + 8.0)
		_update_box.position.y = _best_label.position.y + 36.0
	MenuKit.focus_first(page)
	if page == _difficulty_page:  # start on the difficulty you played last
		(page.get_node(Difficulty.NAMES[GameState.difficulty]) as Control).grab_focus()
	if page == _achievements_page:  # start on the first row, so arrows scroll the list
		for child in page.get_children():
			if child is ScrollContainer and child.get_child(0).get_child_count() > 0:
				(child.get_child(0).get_child(0) as Control).grab_focus()
	if page == _levels_page and page.get_child_count() > 1:
		var scroll := page.get_child(page.get_child_count() - 2)
		if scroll is ScrollContainer and scroll.get_child(0).get_child_count() > 0:
			(scroll.get_child(0).get_child(0) as Control).grab_focus()


# ---------------------------------------------------------------- updates

func _refresh_update_banner() -> void:
	for child in _update_box.get_children():
		child.queue_free()
	var info := Updater.latest
	match Updater.state:
		Updater.State.CHECKING:
			_banner_text("Checking for updates…")
		Updater.State.UP_TO_DATE:
			_banner_text("You have the latest version.")
		Updater.State.AVAILABLE:
			_banner_text("Update v%s available!" % info.get("version", "?"), UITheme.ACCENT)
			var row := _button_row()
			if Updater.can_auto_install():
				MenuKit.button(row, "Download & install", Updater.download_and_install)
			if info.get("page_url", "") != "":
				MenuKit.button(row, "Open download page", func() -> void:
					OS.shell_open(info["page_url"]))
		Updater.State.DOWNLOADING:
			_banner_text("Downloading… %d%%" % int(Updater.progress * 100.0))
			var bar := ProgressBar.new()
			bar.value = Updater.progress * 100.0
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 8)
			_update_box.add_child(bar)
		Updater.State.READY:
			_banner_text("Update installed. Restart to play v%s." % info.get("version", "?"), Color("#6fe07a"))
			MenuKit.button(_button_row(), "Restart now", Updater.restart_game)
		Updater.State.FAILED:
			_banner_text("Update check failed:\n" + Updater.error_text, Color("#ff8a7a"))


func _button_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	_update_box.add_child(row)
	return row


func _banner_text(text: String, color := Color("#9aa0b0")) -> void:
	var l := MenuKit.label(_update_box, text, 11, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# ---------------------------------------------------------------- custom level files

static func list_custom_levels() -> Array[String]:
	var names: Array[String] = []
	for file in DirAccess.get_files_at(LEVELS_DIR):
		if file.ends_with(".txt"):
			names.append(file.get_basename())
	names.sort()
	return names


static func load_custom_level(level_name: String) -> PackedStringArray:
	var text := FileAccess.get_file_as_string(LEVELS_DIR + level_name + ".txt")
	return LevelData.sanitize(text.split("\n"))


# ---------------------------------------------------------------- attract mode

## The background "attract mode":
##   * a convoy of 3 tanks along the bottom, all at the same speed and evenly
##     spaced, so they never drive into each other, and clear of the brick wall;
##   * one tank patrolling up and down each side of the menu.
const CONVOY_Y := 372.0      # tanks are 32px tall: 356..388, above the bricks at 400
const CONVOY_SPEED := 36.0
const CONVOY_WRAP := 40.0    # how far off-screen a tank goes before coming back
const PATROL_TOP := 58.0     # below the top bricks (0..32)
const PATROL_BOTTOM := 326.0 # above the convoy lane


func _spawn_demo_tanks() -> void:
	var convoy := ["player_L2", "basic", "fast"]
	var loop := 512.0 + 2.0 * CONVOY_WRAP
	for i in convoy.size():
		_demo_tanks.append({
			"sprite": convoy[i],
			"pos": Vector2(-CONVOY_WRAP + loop * i / convoy.size(), CONVOY_Y),
			"vel": Vector2(CONVOY_SPEED, 0.0),
			"patrol": false,
		})
	_demo_tanks.append({"sprite": "armor", "pos": Vector2(40.0, 120.0), "vel": Vector2(0.0, 28.0), "patrol": true})
	_demo_tanks.append({"sprite": "power", "pos": Vector2(472.0, 260.0), "vel": Vector2(0.0, -28.0), "patrol": true})


func _draw() -> void:
	draw_rect(Rect2(0, 0, 512, 416), Color("#0c0c10"))
	# Tanks (sprites face up, so rotate them to face the way they drive)
	for t in _demo_tanks:
		var frame := int(_time * 8.0) % 2
		draw_set_transform(t.pos, (t.vel as Vector2).angle() + PI / 2.0)
		Art.draw_frame(self, "tank_" + t.sprite, frame, Vector2(16, 16), Vector2.ZERO, Color(0.55, 0.55, 0.6))
	draw_set_transform(Vector2.ZERO)
	# Brick strips at top and bottom, drawn last so nothing ever covers them
	for x in range(0, 512, 16):
		for y in [0, 16, 400]:
			Art.draw_frame(self, "brick", 0, Vector2(8, 8), Vector2(x + 8, y + 8), Color(0.55, 0.55, 0.6))
