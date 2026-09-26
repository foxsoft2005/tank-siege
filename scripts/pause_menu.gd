class_name PauseMenu
extends CanvasLayer
## The pause menu, with two "pages": the main page and the Options page.
## Everything is a normal Control node, so keyboard (arrows + Enter),
## gamepad (D-pad + A, B to go back) and mouse all work.
##
## Main creates this when you press P/Esc and calls back() when you press
## P/Esc again.

signal resumed
signal restart_requested
signal menu_requested

var _main_page: VBoxContainer
var _options_page: VBoxContainer
var _panel: PanelContainer
var _content: VBoxContainer


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.7)
	dim.size = Vector2(512, 416)
	add_child(dim)

	# Both pages live in the same container; only one is visible at a time.
	_content = VBoxContainer.new()
	_main_page = _build_main_page()
	_options_page = MenuKit.options_page(func() -> void: _show_page(_main_page))
	_content.add_child(_main_page)
	_content.add_child(_options_page)
	_panel = MenuKit.panel(_content)  # the panel also applies the menu Theme
	add_child(_panel)

	_show_page(_main_page)


## Called for P / Esc / gamepad B: go back one page, or close the menu.
func back() -> void:
	if _options_page.visible:
		Settings.save_settings()
		_show_page(_main_page)
		Sfx.play("ui_move", 0.0, 0.0)
	else:
		_resume()


func _unhandled_input(event: InputEvent) -> void:
	# Gamepad B / Backspace. (Esc is handled by Main through the "pause" action.)
	if event.is_action_pressed("ui_cancel") and not event.is_action("pause"):
		back()
		get_viewport().set_input_as_handled()


func _build_main_page() -> VBoxContainer:
	var page := MenuKit.page("PAUSED")
	MenuKit.button(page, "Resume", _resume)
	MenuKit.button(page, "Options", func() -> void: _show_page(_options_page))
	MenuKit.button(page, "Restart", func() -> void: restart_requested.emit())
	var testing := GameState.return_scene == GameState.EDITOR_SCENE
	MenuKit.button(page, "Back to editor" if testing else "Main menu", func() -> void:
		menu_requested.emit())
	return page


func _show_page(page: VBoxContainer) -> void:
	_main_page.visible = page == _main_page
	_options_page.visible = page == _options_page
	await MenuKit.center(_panel)
	MenuKit.focus_first(page)


func _resume() -> void:
	Sfx.play("pause", 0.0, 0.0)
	resumed.emit()
	queue_free()
