class_name LevelData
extends RefCounted
## Stage layouts. Each map is 13 x 13 blocks, one character per block:
##   .  empty      B  brick (breakable)    S  steel (needs max power)
##   W  water      G  bushes (hide tanks)
##   I  ice (slippery)            M  mud (slow)
##   ^ V < >  conveyor belts (push tanks that way)
##   T  teleporter (drive onto the middle of one, come out of the next)
##   X  explosive barrel (shoot it: boom, and chain reactions)
## Keep the bottom two rows around columns 4-7 empty: that's where the
## player spawns and the base sits. Enemies spawn at top-left, top-middle
## and top-right, so keep those corners empty too.
## Add a new map to MAPS and it becomes the next stage. Stages loop.

const MAPS: Array[PackedStringArray] = [
	# Stage 1 - "Warm-up"
	[
		".............",
		".B.B.B.B.B.B.",
		".B.B.B.B.B.B.",
		".B.B.BSB.B.B.",
		".B.B.....B.B.",
		".....B.B.....",
		"S.BB.....BB.S",
		".....B.B.....",
		".B.B.BBB.B.B.",
		".B.B.B.B.B.B.",
		".B.B.....B.B.",
		"...B.....B...",
		"...B.....B...",
	],
	# Stage 2 - "Lakes"
	[
		".............",
		".GG.B.S.B.GG.",
		".GG.B...B.GG.",
		".....BBB.....",
		"WW.S.....S.WW",
		"...B.GGG.B...",
		".B.B.GSG.B.B.",
		"...B.GGG.B...",
		"WW.........WW",
		".B..BB.BB..B.",
		".B.S.....S.B.",
		"..B.......B..",
		"..B.......B..",
	],
	# Stage 3 - "Steel maze"
	[
		".............",
		".S.BBB.BBB.S.",
		".S.........S.",
		".SSS.B.B.SSS.",
		"...G.B.B.G...",
		"BBGG.....GGBB",
		"...S.WWW.S...",
		"BB.S.....S.BB",
		"...BB.S.BB...",
		".G.........G.",
		".GBB.B.B.BBG.",
		".............",
		"SS.........SS",
	],
	# Stage 4 - "Frozen Factory" (the new tiles)
	[
		".............",
		".T..IIIII..T.",
		"....IISII....",
		"BB..IIIII..BB",
		"...X.....X...",
		".>>>>...<<<<.",
		"..B..MMM..B..",
		"T.B.XMMMX.B.T",
		".....MMM.....",
		".SVS.....SVS.",
		"..V.B...B.V..",
		".............",
		"...M.....M...",
	],
]


## The boss arena (every 5th stage). Open at the top so the 64x64 boss can
## patrol, with a steel bunker above the core so its straight-down shots
## can't hit the core directly. Top rows, columns 5-7 must stay empty
## (that's where the boss appears).
const BOSS_MAP: PackedStringArray = [
	".............",
	".............",
	".S.........S.",
	".............",
	"..BB.....BB..",
	"..BB.....BB..",
	".............",
	"GG....B....GG",
	".B..BB.BB..B.",
	".B..SSSSS..B.",
	".............",
	"..B.......B..",
	"..B.......B..",
]


static func is_boss_stage(stage: int) -> bool:
	return stage % 5 == 0


static func get_map(stage: int) -> PackedStringArray:
	if is_boss_stage(stage):
		return BOSS_MAP
	return MAPS[(stage - 1) % MAPS.size()]


# ---------------------------------------------------------------- custom levels

const SIZE := 13
const TILES := ".BSWGIM^V<>TX"

## Blocks that must stay empty so the game works: the 3 enemy spawns, the
## player spawn and the base with its wall ring. The editor won't paint here.
const PROTECTED: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(6, 0), Vector2i(12, 0),  # enemy spawns
	Vector2i(4, 12), Vector2i(8, 12),                  # player 1 and 2 spawns
	Vector2i(5, 11), Vector2i(6, 11), Vector2i(7, 11), # base + wall ring
	Vector2i(5, 12), Vector2i(6, 12), Vector2i(7, 12),
]


## Make any list of text lines into a valid 13x13 map: pad/trim it, turn
## unknown characters into empty space, and clear the protected blocks.
static func sanitize(lines: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for y in SIZE:
		var src := lines[y].strip_edges().to_upper() if y < lines.size() else ""
		var row := ""
		for x in SIZE:
			var ch := src[x] if x < src.length() else "."
			if ch not in TILES or Vector2i(x, y) in PROTECTED:
				ch = "."
			row += ch
		out.append(row)
	return out


## The map as GDScript, ready to paste into MAPS above.
static func to_gdscript(map: PackedStringArray, title: String) -> String:
	var text := "\t# %s\n\t[\n" % title
	for row in map:
		text += "\t\t\"%s\",\n" % row
	return text + "\t],\n"
