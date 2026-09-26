class_name Art
extends RefCounted
## Loads the pixel-art textures from assets/sprites/ (made by tools/make_sprites.py).
## Art.tex("brick") returns the texture, loading it only the first time.
##
## The art is drawn tiny (tanks are 16x16) and shown at 2x. For crisp pixels
## the game world uses "Nearest" texture filtering (see main.gd), otherwise
## Godot would blur the pixels when scaling them up.

const SCALE := 2.0

static var _cache := {}


static func tex(sprite_name: String) -> Texture2D:
	if not _cache.has(sprite_name):
		_cache[sprite_name] = load("res://assets/sprites/%s.png" % sprite_name)
	return _cache[sprite_name]


## Draw one frame of a horizontal sprite sheet, scaled up, centred on `center`.
static func draw_frame(ci: CanvasItem, sprite_name: String, frame: int, frame_size: Vector2,
		center: Vector2, modulate := Color.WHITE) -> void:
	var size := frame_size * SCALE
	var src := Rect2(Vector2(frame * frame_size.x, 0), frame_size)
	ci.draw_texture_rect_region(tex(sprite_name), Rect2(center - size / 2.0, size), src, modulate)
