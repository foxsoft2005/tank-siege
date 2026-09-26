extends Node2D
## The Garage: spend SCRAP (earned at the end of every run) on new tanks and
## permanent perks. Everything is saved in user://save.cfg by GameState.
## Data (names, prices, stats) lives in garage.gd, this file is only the UI.

var _scrap_label: Label
var _tanks_page: Control
var _perks_page: Control
var _tabs: Array[Button] = []
var _preview: TextureRect
var _preview_atlas: AtlasTexture
var _info_name: Label
var _info_desc: Label
var _info_bars := {}
var _action: Button
var _shown_tank := "scout"
var _tank_buttons := {}
var _time := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Music.play("upgrade")
	_build_ui()
	_show_tab(0)


func _process(delta: float) -> void:
	_time += delta
	# Animate the preview tank's treads.
	if _preview_atlas:
		_preview_atlas.region = Rect2(16 * (int(_time * 6.0) % 2), 0, 16, 16)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_tree().change_scene_to_file(GameState.TITLE_SCENE)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 512, 416), Color("#0c0c10"))
	for x in range(0, 512, 16):
		Art.draw_frame(self, "brick", 0, Vector2(8, 8), Vector2(x + 8, 408), Color(0.5, 0.5, 0.55))


# ---------------------------------------------------------------- layout

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.theme = UITheme.make()
	root.size = Vector2(512, 416)
	ui.add_child(root)

	var title := MenuKit.label(root, "GARAGE", 28, UITheme.ACCENT)
	title.position = Vector2(16, 8)
	_scrap_label = MenuKit.label(root, "", 16, Color("#ffd23f"))
	_scrap_label.position = Vector2(300, 16)
	_scrap_label.size = Vector2(196, 24)
	_scrap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var tab_row := HBoxContainer.new()
	tab_row.position = Vector2(16, 52)
	root.add_child(tab_row)
	for i in 2:
		var b := MenuKit.button(tab_row, ["Tanks", "Perks"][i], _show_tab.bind(i))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(90, 0)
		_tabs.append(b)
	var back := MenuKit.button(root, "Back", func() -> void:
		get_tree().change_scene_to_file(GameState.TITLE_SCENE))
	back.position = Vector2(416, 52)
	back.custom_minimum_size = Vector2(80, 0)

	var stats := MenuKit.label(root, "runs played %d   ·   scrap earned in total %d" % [
		GameState.runs, GameState.total_scrap], 10, Color("#7d8290"))
	stats.position = Vector2(16, 378)

	_tanks_page = _build_tanks_page()
	_tanks_page.position = Vector2(16, 92)
	root.add_child(_tanks_page)
	_perks_page = _build_perks_page()
	_perks_page.position = Vector2(16, 92)
	root.add_child(_perks_page)
	_refresh()


func _show_tab(i: int) -> void:
	for t in _tabs.size():
		_tabs[t].button_pressed = t == i
	_tanks_page.visible = i == 0
	_perks_page.visible = i == 1
	var page := _tanks_page if i == 0 else _perks_page
	await get_tree().process_frame
	MenuKit.focus_first(page.get_child(0) if i == 0 else page)


# ---------------------------------------------------------------- tanks

func _build_tanks_page() -> Control:
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 16)

	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(190, 0)
	page.add_child(list)
	for id: String in Garage.TANKS:
		var b := MenuKit.button(list, "", _on_tank_pressed.bind(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_entered.connect(_show_tank.bind(id))
		b.mouse_entered.connect(_show_tank.bind(id))
		_tank_buttons[id] = b

	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(270, 0)
	info.add_theme_constant_override("separation", 4)
	page.add_child(info)
	_preview_atlas = AtlasTexture.new()
	_preview = TextureRect.new()
	_preview.texture = _preview_atlas
	_preview.custom_minimum_size = Vector2(64, 64)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	info.add_child(_preview)
	_info_name = MenuKit.label(info, "", 18, Color.WHITE)
	_info_desc = MenuKit.label(info, "", 11, Color("#c9ccd4"))
	_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_desc.custom_minimum_size = Vector2(270, 30)
	for stat_name in ["Speed", "Firepower", "Toughness"]:
		var row := HBoxContainer.new()
		var l := MenuKit.label(row, stat_name, 11)
		l.custom_minimum_size = Vector2(80, 0)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(170, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = 10
		row.add_child(bar)
		info.add_child(row)
		_info_bars[stat_name] = bar
	_action = MenuKit.button(info, "", func() -> void: _on_tank_pressed(_shown_tank))
	_show_tank(GameState.selected_tank)
	return page


func _show_tank(id: String) -> void:
	_shown_tank = id
	_preview_atlas.atlas = Art.tex("tank_%s_L0" % Garage.stat(id, "sprite"))
	_preview_atlas.region = Rect2(0, 0, 16, 16)
	_info_name.text = Garage.TANKS[id]["name"]
	_info_desc.text = Garage.TANKS[id]["desc"]
	# Rough 0-10 ratings, just to compare tanks at a glance.
	_info_bars["Speed"].value = 5.0 * float(Garage.stat(id, "speed")) * 1.3
	_info_bars["Firepower"].value = 3.0 + 2.0 * int(Garage.stat(id, "extra_shells")) \
		+ 3.0 * (float(Garage.stat(id, "shell_speed")) - 1.0) * 4.0 \
		+ 2.0 * int(Garage.stat(id, "pierce")) + (3.0 if Garage.stat(id, "blast") else 0.0) \
		+ (0.18 - float(Garage.stat(id, "reload"))) * 20.0
	_info_bars["Toughness"].value = 4.0 + 3.0 * int(Garage.stat(id, "armor")) + 2.0 * int(Garage.stat(id, "lives"))
	_refresh()


func _on_tank_pressed(id: String) -> void:
	if id in GameState.unlocked_tanks:
		GameState.selected_tank = id
		GameState.save_progress()
		Sfx.play("ui_pick", 0.0, 0.0)
	elif GameState.try_spend(Garage.TANKS[id]["cost"]):
		GameState.unlocked_tanks.append(id)
		GameState.selected_tank = id
		GameState.save_progress()
		Sfx.play("powerup_pickup", 0.0, 0.0)
	else:
		Sfx.play("deflect", -4.0, 0.0)  # can't afford it
	_show_tank(id)


# ---------------------------------------------------------------- perks

func _build_perks_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	for id: String in Garage.PERKS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var text := VBoxContainer.new()
		text.name = "Text"
		text.custom_minimum_size = Vector2(340, 0)
		text.add_theme_constant_override("separation", 0)
		var name_label := MenuKit.label(text, "", 13, Color.WHITE)
		name_label.name = "Name"
		MenuKit.label(text, Garage.PERKS[id]["desc"], 10, Color("#c9ccd4"))
		row.add_child(text)
		var buy := MenuKit.button(row, "", _buy_perk.bind(id))
		buy.name = "Buy"
		buy.custom_minimum_size = Vector2(120, 0)
		row.name = id
		page.add_child(row)
	return page


func _buy_perk(id: String) -> void:
	var cost := Garage.next_perk_cost(id, GameState.perk(id))
	if cost >= 0 and GameState.try_spend(cost):
		GameState.perks[id] = GameState.perk(id) + 1
		GameState.save_progress()
		Sfx.play("powerup_pickup", 0.0, 0.0)
	else:
		Sfx.play("deflect", -4.0, 0.0)
	_refresh()


# ---------------------------------------------------------------- refresh

func _refresh() -> void:
	_scrap_label.text = "SCRAP  %d" % GameState.scrap
	for id: String in _tank_buttons:
		var b: Button = _tank_buttons[id]
		var tank_name: String = Garage.TANKS[id]["name"]
		if id == GameState.selected_tank:
			b.text = "%s   ✓ selected" % tank_name
		elif id in GameState.unlocked_tanks:
			b.text = "%s   owned" % tank_name
		else:
			b.text = "%s   %d scrap" % [tank_name, Garage.TANKS[id]["cost"]]
	if _action:
		var id := _shown_tank
		if id == GameState.selected_tank:
			_action.text = "Selected"
			_action.disabled = true
		elif id in GameState.unlocked_tanks:
			_action.text = "Select"
			_action.disabled = false
		else:
			var cost: int = Garage.TANKS[id]["cost"]
			_action.text = "Buy for %d scrap" % cost
			_action.disabled = GameState.scrap < cost
	if _perks_page:
		for id: String in Garage.PERKS:
			var row := _perks_page.get_node(id)
			var level := GameState.perk(id)
			var max_level: int = Garage.PERKS[id]["costs"].size()
			(row.get_node("Text/Name") as Label).text = "%s   %d/%d" % [Garage.PERKS[id]["name"], level, max_level]
			var buy := row.get_node("Buy") as Button
			var cost := Garage.next_perk_cost(id, level)
			buy.text = "MAX" if cost < 0 else "Buy  %d" % cost
			buy.disabled = cost < 0 or GameState.scrap < cost
