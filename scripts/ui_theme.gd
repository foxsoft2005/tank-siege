class_name UITheme
extends RefCounted
## Builds a Theme in code. A Theme is a style sheet for UI: set it on one
## Control and every child inherits it (like CSS). You can also create a
## Theme resource in the editor and edit it visually.

const ACCENT := Color("#f2c230")
const TEXT := Color("#e6e8ee")
const PANEL := Color("#1b1c24")


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14

	# Buttons
	t.set_stylebox("normal", "Button", _box(Color("#262836"), Color("#3a3d52")))
	t.set_stylebox("hover", "Button", _box(Color("#30334a"), Color("#5a5f80")))
	t.set_stylebox("pressed", "Button", _box(Color("#3a3d5a"), ACCENT))
	t.set_stylebox("focus", "Button", _box(Color.TRANSPARENT, ACCENT, 2, false))
	t.set_stylebox("disabled", "Button", _box(Color("#1d1e26"), Color("#2a2c38")))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)

	# CheckButton (on/off switch) reuses the Button look, but with no border box
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var box := _box(Color.TRANSPARENT, ACCENT if state == "focus" else Color.TRANSPARENT, 1, false)
		box.content_margin_left = 0  # line the text up with the slider labels
		t.set_stylebox(state, "CheckButton", box)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_focus_color", "CheckButton", ACCENT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)

	# Drop-down lists (OptionButton) look like buttons; their pop-up menu is a dark panel.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(state, "OptionButton", t.get_stylebox(state, "Button"))
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_focus_color", "OptionButton", ACCENT)
	t.set_color("font_hover_color", "OptionButton", Color.WHITE)
	t.set_stylebox("panel", "PopupMenu", _box(PANEL, ACCENT, 1))
	t.set_stylebox("hover", "PopupMenu", _box(Color("#30334a"), Color.TRANSPARENT, 0))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", ACCENT)

	# Sliders
	var track := _box(Color("#30334a"), Color.TRANSPARENT, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := _box(ACCENT.darkened(0.2), Color.TRANSPARENT, 0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_stylebox("focus", "HSlider", _box(Color.TRANSPARENT, ACCENT, 1, false))

	# Panels and labels
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, Color("#3a3d52"), 2))
	t.set_color("font_color", "Label", TEXT)
	return t


static func _box(bg: Color, border: Color, width := 1, fill := true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.draw_center = fill
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(4)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s
