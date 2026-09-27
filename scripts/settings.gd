extends Node
## Autoload "Settings": player options, saved to disk between sessions.
##
## Godot's ConfigFile writes a simple INI-style text file. "user://" is a
## per-game folder Godot picks for you (on Windows it's in %APPDATA%\Godot\...).
## In the editor you can open it with Project > Open User Data Folder.

const PATH := "user://settings.cfg"

# Volumes are 0.0 .. 1.0 (what the sliders show). Audio buses use decibels,
# so we convert with linear_to_db() when applying.
var master_volume := 1.0
var music_volume := 0.8
var sfx_volume := 0.9
var screen_shake := true
var fullscreen := false
var window_scale := 2.0      # window size = game canvas (512x416) x this
var pixel_perfect := false   # only scale by whole numbers (sharpest pixels)
var check_updates := true
var procedural_levels := false  # off = the handmade stages; on = LevelGen makes new ones


func _ready() -> void:
	load_settings()
	apply()


## The game is always drawn on a 512x416 canvas (see project.godot); Godot
## then scales it up to fill the window ("stretch mode: canvas_items").
## These are the window sizes the Options page offers.
const BASE_SIZE := Vector2i(512, 416)
const WINDOW_SCALES := [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]


func apply() -> void:
	_set_bus("Master", master_volume, 0.0)
	_set_bus("Music", music_volume, Music.VOLUME_DB)
	_set_bus("SFX", sfx_volume, 0.0)
	_apply_display()


func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return  # tests / servers have no window
	var window := get_window()
	# Pixel-perfect: scale only by 2x, 3x... and add black borders if needed.
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if pixel_perfect \
		else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	if not fullscreen and not OS.has_feature("web"):
		var size := window_size(window_scale)
		if DisplayServer.window_get_size() != size:
			DisplayServer.window_set_size(size)
			# Keep the window centred on its screen.
			var screen := DisplayServer.window_get_current_screen()
			var area := DisplayServer.screen_get_usable_rect(screen)
			DisplayServer.window_set_position(area.position + (area.size - size) / 2)


static func window_size(scale: float) -> Vector2i:
	return Vector2i(roundi(BASE_SIZE.x * scale), roundi(BASE_SIZE.y * scale))


## Window sizes that fit on this screen (always at least 1x).
func available_scales() -> Array[float]:
	var out: Array[float] = [1.0]
	if DisplayServer.get_name() == "headless":
		out.assign(WINDOW_SCALES)
		return out
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	for s: float in WINDOW_SCALES:
		var size := window_size(s)
		if s > 1.0 and size.x <= area.x and size.y <= area.y - 40:  # leave room for the title bar
			out.append(s)
	return out


func _set_bus(bus_name: String, volume: float, offset_db: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i == -1:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(volume, 0.0001)) + offset_db)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("game", "screen_shake", screen_shake)
	cfg.set_value("game", "procedural_levels", procedural_levels)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "window_scale", window_scale)
	cfg.set_value("video", "pixel_perfect", pixel_perfect)
	cfg.set_value("updates", "check", check_updates)
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return  # first launch: keep the defaults
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	screen_shake = cfg.get_value("game", "screen_shake", screen_shake)
	procedural_levels = cfg.get_value("game", "procedural_levels", procedural_levels)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	window_scale = cfg.get_value("video", "window_scale", window_scale)
	pixel_perfect = cfg.get_value("video", "pixel_perfect", pixel_perfect)
	check_updates = cfg.get_value("updates", "check", check_updates)
