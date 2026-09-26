class_name MenuKit
extends RefCounted
## Small helpers for building menus in code: pages, buttons, sliders, toggles,
## and the shared Options page. Used by the title screen, the pause menu and the
## level editor, so they all look and behave the same.


## A vertical page with a big title at the top.
static func page(title: String, width := 240.0) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 8)
	p.custom_minimum_size = Vector2(width, 0)
	if title != "":
		var label := Label.new()
		label.text = title
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", UITheme.ACCENT)
		p.add_child(label)
	return p


static func button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(on_press)
	b.focus_entered.connect(Sfx.play.bind("ui_move", -4.0, 0.0))
	parent.add_child(b)
	return b


static func label(parent: Control, text: String, size := 12, color := UITheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


static func slider(parent: Control, text: String, value: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	# value_changed is a signal that passes the new value along.
	s.value_changed.connect(on_change)
	row.add_child(s)
	parent.add_child(row)
	return s


static func toggle(parent: Control, text: String, value: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_ALL
	c.toggled.connect(on_change)
	c.toggled.connect(func(_on: bool) -> void: Sfx.play("ui_pick", -4.0, 0.0))
	parent.add_child(c)
	return c


## The Options page, shared by the title screen and the pause menu.
static func options_page(on_back: Callable) -> VBoxContainer:
	var p := page("OPTIONS", 260.0)
	p.add_theme_constant_override("separation", 3)
	slider(p, "Master volume", Settings.master_volume, func(v: float) -> void:
		Settings.master_volume = v
		Settings.apply())
	slider(p, "Music", Settings.music_volume, func(v: float) -> void:
		Settings.music_volume = v
		Settings.apply())
	slider(p, "Sound effects", Settings.sfx_volume, func(v: float) -> void:
		Settings.sfx_volume = v
		Settings.apply()
		Sfx.play("shoot", 0.0, 0.0))  # instant feedback while dragging
	toggle(p, "Screen shake", Settings.screen_shake, func(on: bool) -> void:
		Settings.screen_shake = on)
	# Display: every window size that fits your screen, plus Fullscreen.
	var scales := Settings.available_scales()
	var labels: Array[String] = []
	for s in scales:
		var size := Settings.window_size(s)
		labels.append("%dx%d" % [size.x, size.y])
	labels.append("Fullscreen")
	var current := scales.size() if Settings.fullscreen else maxi(scales.find(Settings.window_scale), 0)
	choice(p, "Resolution", labels, current, func(index: int) -> void:
		Settings.fullscreen = index >= scales.size()
		if not Settings.fullscreen:
			Settings.window_scale = scales[index]
		Settings.apply())
	toggle(p, "Pixel-perfect scaling", Settings.pixel_perfect, func(on: bool) -> void:
		Settings.pixel_perfect = on
		Settings.apply())
	toggle(p, "Check for updates", Settings.check_updates, func(on: bool) -> void:
		Settings.check_updates = on)
	button(p, "Back", func() -> void:
		Settings.save_settings()
		on_back.call())
	return p


## A label and a drop-down list (OptionButton). on_change gets the chosen index.
static func choice(parent: Control, text: String, items: Array[String], selected: int, on_change: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	for item in items:
		ob.add_item(item)
	ob.selected = selected
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.focus_mode = Control.FOCUS_ALL
	ob.item_selected.connect(on_change)
	ob.item_selected.connect(func(_i: int) -> void: Sfx.play("ui_pick", -4.0, 0.0))
	row.add_child(ob)
	parent.add_child(row)
	return ob


## Give keyboard/gamepad focus to the first thing on a page you can interact with.
static func focus_first(p: Control) -> void:
	for child in p.get_children():
		if child is GridContainer and child.get_child_count() > 0:  # a grid of buttons
			(child.get_child(0) as Control).grab_focus()
			return
		if child is HBoxContainer and child.get_child_count() > 1:  # a slider row
			(child.get_child(1) as Control).grab_focus()
			return
		if child is Control and (child as Control).focus_mode == Control.FOCUS_ALL:
			(child as Control).grab_focus()
			return


## A centred panel with the shared theme, holding `content`.
static func panel(content: Control) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.theme = UITheme.make()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	pc.add_child(margin)
	margin.add_child(content)
	return pc


## Resize a panel to fit its content and centre it on the 512x416 screen.
static func center(pc: Control, y_offset := 0.0) -> void:
	pc.reset_size()
	await pc.get_tree().process_frame
	pc.reset_size()
	pc.position = (Vector2(512, 416) - pc.size) / 2.0 + Vector2(0, y_offset)
