"""
Draws the game's pixel art from the text grids below and saves PNGs to
assets/sprites/.  OPTIONAL: the PNGs are already included.

Edit a grid, then run:   python tools/make_sprites.py   (needs Python 3 + Pillow)
Godot re-imports the images automatically.

Every character in a grid is one pixel; the PALETTE for that sprite says
which color each character means ("." is always transparent).
Sprites are drawn small (tanks are 16x16) and shown at 2x in the game,
which gives the chunky retro look.

Prefer drawing with a mouse? Open the PNGs in Aseprite / LibreSprite /
Piskel, edit, and save over them. (Then don't rerun this script, or it
will overwrite your work!)
"""

import os

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")


def img(grid, palette):
    h, w = len(grid), len(grid[0])
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y, row in enumerate(grid):
        assert len(row) == w, f"row {y} is {len(row)} wide, expected {w}: {row!r}"
        for x, ch in enumerate(row):
            if ch != ".":
                im.putpixel((x, y), hexcolor(palette[ch]))
    return im


def hexcolor(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def strip(images):
    """Put frames side by side (a sprite sheet)."""
    w = sum(i.width for i in images)
    sheet = Image.new("RGBA", (w, images[0].height), (0, 0, 0, 0))
    x = 0
    for i in images:
        sheet.paste(i, (x, 0))
        x += i.width
    return sheet


def save(name, im):
    im.save(os.path.join(OUT, name + ".png"))
    print("wrote", name + ".png", im.size)


# ------------------------------------------------------------------ tanks
# Drawn facing UP. o outline, d/m/l dark/mid/light body, b barrel,
# t/T tread dark/light (frame 2 swaps them, so treads look like they roll).

TANK = [
    "......obbo......",
    "......obbo......",
    "oooo..obbo..oooo",
    "oTTo..obbo..oTTo",
    "ottoooobbooootto",
    "oTToomobbomooTTo",
    "ottoomdbbdmootto",
    "oTToodmbbmdooTTo",
    "ottoodmllmdootto",
    "oTToodmllmdooTTo",
    "ottoodmmmmdootto",
    "oTToomddddmooTTo",
    "ottoommmmmmootto",
    "oTToomllllmooTTo",
    "ottooooooooootto",
    "oooo........oooo",
]

TANK_COLORS = {
    #          dark       mid        light      tread dk   tread lt   barrel
    "player": ("#b07d10", "#f2c230", "#ffe98a", "#4a3a10", "#8a7030", "#fff1b0"),
    "basic":  ("#6e7380", "#b8bcc6", "#e8ebf0", "#2e3038", "#5d616e", "#f4f4f4"),
    "fast":   ("#3f8f80", "#7fd6c2", "#c8fff2", "#1e3e38", "#3f6f66", "#e8fffa"),
    "power":  ("#7a4fb0", "#c98bff", "#ecd6ff", "#3a2650", "#6a4a90", "#f6ecff"),
    "armor":  ("#4a6333", "#6f8f4e", "#a9c98a", "#252f1a", "#4d5e3a", "#dfeecf"),
    "bonus":  ("#9e2622", "#e8413b", "#ff9a94", "#4a1210", "#7e2a26", "#ffe0de"),
    # newer enemies
    "sniper":   ("#2c3e66", "#4a6aa8", "#9fb8e8", "#161e30", "#2e3c5c", "#dfe8ff"),
    "kamikaze": ("#a3400f", "#f07a1a", "#ffc07a", "#40180a", "#7a3414", "#fff0d0"),
    "shielded": ("#3a6f7a", "#5aa8b8", "#b8eef5", "#1a3238", "#335d66", "#e8fcff"),
    "engineer": ("#6b5a2a", "#a89048", "#e0d08a", "#2e2610", "#5a4c24", "#fff6d0"),
    # garage tanks (the player can unlock these)
    "striker":    ("#a3245e", "#e8479a", "#ffb0d8", "#40102a", "#7a2450", "#ffe6f2"),
    "bulwark":    ("#6e4a1c", "#b0782c", "#e8b86a", "#2e1e0c", "#5a3c18", "#fff0d6"),
    "phantom":    ("#5a5a78", "#c8c8e8", "#ffffff", "#24243a", "#46466a", "#ffffff"),
    "demolisher": ("#7a1c14", "#c83a24", "#ff8a5a", "#300c08", "#5e1c14", "#ffe0c8"),
    # player 2 in co-op: green, like the original's second tank
    "player2":    ("#2e7d32", "#4caf50", "#a5e6a8", "#123814", "#2e5e30", "#e6ffe6"),
}


def tanks():
    frame2 = [row.replace("t", "_").replace("T", "t").replace("_", "T") for row in TANK]
    for name, (d, m, l, t, tt, b) in TANK_COLORS.items():
        pal = {"o": "#141418", "d": d, "m": m, "l": l, "t": t, "T": tt, "b": b}
        save("tank_" + name, strip([img(TANK, pal), img(frame2, pal)]))


# ------------------------------------------------------------------ player tanks: one shape per star level
# Like the original game, your tank changes shape as you collect stars:
#   level 0  light tank: short gun
#   level 1  longer gun with a muzzle brake (faster shells)
#   level 2  bigger turret, twin guns (two shells at once)
#   level 3  heavy tank: armor plates, twin heavy guns (breaks steel)
# These are built from rectangles so each level is a few numbers to tweak.

PLAYER_TANKS = ["player", "striker", "bulwark", "phantom", "demolisher", "player2"]

LEVEL_SHAPES = [
    # top: first row of the treads. turret: (x0, y0, x1, y1). barrels: list of
    # (x0, x1) columns. barrel_top: row where the gun ends. muzzle: wider tip.
    # plates: armor plates on the treads.
    dict(top=3, turret=(5, 7, 10, 12), barrels=[(7, 8)], barrel_top=2, muzzle=False, plates=False),
    dict(top=3, turret=(5, 7, 10, 12), barrels=[(7, 8)], barrel_top=0, muzzle=True, plates=False),
    dict(top=2, turret=(4, 6, 11, 12), barrels=[(5, 6), (9, 10)], barrel_top=1, muzzle=False, plates=False),
    dict(top=2, turret=(4, 5, 11, 12), barrels=[(5, 6), (9, 10)], barrel_top=0, muzzle=True, plates=True),
]


def player_tank_grid(level, frame):
    shape = LEVEL_SHAPES[level]
    g = [["." for _ in range(16)] for _ in range(16)]

    def rect(x0, y0, x1, y1, ch):
        for y in range(max(y0, 0), min(y1, 15) + 1):
            for x in range(max(x0, 0), min(x1, 15) + 1):
                g[y][x] = ch

    top = shape["top"]
    # treads, left and right (rolling stripes swap between the two frames)
    for x0 in (0, 12):
        rect(x0, top, x0 + 3, 15, "o")
        for y in range(top + 1, 15):
            rect(x0 + 1, y, x0 + 2, y, "T" if (y + frame) % 2 == 0 else "t")
        if shape["plates"]:  # extra armor bolted onto the treads
            rect(x0 + 1, top + 2, x0 + 2, top + 3, "S")
            rect(x0 + 1, 11, x0 + 2, 12, "S")
    # hull, between the treads
    rect(3, top + 1, 12, 14, "o")
    rect(4, top + 2, 11, 13, "m")
    rect(4, top + 2, 11, top + 2, "l")
    rect(4, 13, 11, 13, "d")
    # turret
    tx0, ty0, tx1, ty1 = shape["turret"]
    rect(tx0, ty0, tx1, ty1, "o")
    rect(tx0 + 1, ty0 + 1, tx1 - 1, ty1 - 1, "m")
    rect(tx0 + 1, ty0 + 1, tx1 - 1, ty0 + 1, "l")
    rect(tx0 + 1, ty1 - 1, tx1 - 1, ty1 - 1, "d")
    # gun barrel(s): from the tip down into the turret, with a dark outline
    for (bx0, bx1) in shape["barrels"]:
        rect(bx0 - 1, shape["barrel_top"], bx1 + 1, ty0, "o")
    for (bx0, bx1) in shape["barrels"]:
        rect(bx0, shape["barrel_top"], bx1, ty0 + 1, "b")
        if shape["muzzle"]:
            rect(bx0 - 1, shape["barrel_top"], bx1 + 1, shape["barrel_top"], "b")
    return ["".join(r) for r in g]


def player_tanks():
    for name in PLAYER_TANKS:
        d, m, l, t, tt, b = TANK_COLORS[name]
        pal = {"o": "#141418", "d": d, "m": m, "l": l, "t": t, "T": tt, "b": b, "S": "#d6dbe3"}
        for level in range(4):
            frames = [img(player_tank_grid(level, f), pal) for f in range(2)]
            save("tank_%s_L%d" % (name, level), strip(frames))


# ------------------------------------------------------------------ tiles (8x8, shown at 2x = one 16px wall piece)

BRICK = [
    "bbbgbbbb",
    "lllglllb",
    "dddgdddd",
    "gggggggg",
    "bbbbbbbg",
    "lllllllg",
    "dddddddg",
    "gggggggg",
]
STEEL = [
    "lllllllo",
    "lwwwwwmo",
    "lwmmmmdo",
    "lwmmmmdo",
    "lwmmmmdo",
    "lwmmmmdo",
    "lmddddoo",
    "oooooooo",
]
WATER_1 = [
    "bbbbbbbb",
    "bwwbbbbb",
    "wbbwbbbb",
    "bbbbbbbb",
    "bbbbbwwb",
    "bbbbwbbw",
    "bbbbbbbb",
    "bbbbbbbb",
]
WATER_2 = [
    "bbbbbbbb",
    "bbbwwbbb",
    "bbwbbwbb",
    "bbbbbbbb",
    "bwwbbbbb",
    "wbbwbbbb",
    "bbbbbbbb",
    "bbbbbbbb",
]
BUSH = [  # 16x16, covers a whole 32px block at 2x
    "..dd.....ddd....",
    ".dmmd...dmmmd.d.",
    "dmllmd.dmllmmdmd",
    "dmlmmdddmlmmmdmd",
    ".dmmmdmmdmmmd.d.",
    "..dddmllmddd.dd.",
    ".dd.dmlmmd..dmmd",
    "dmmddmmmmd.dmllm",
    "dmllmddddddmmlmd",
    "dmlmmmdmmdmmmmd.",
    ".dmmmdmllmdddd..",
    "..ddddmlmmd.dmd.",
    ".dmd.dmmmd.dmlmd",
    "dmlmd.ddd.dmmmmd",
    "dmmmmd...d.dmmd.",
    ".dddd.....d.dd..",
]


ICE = [
    "iiiiiiws",
    "iiiiiwsi",
    "iiiiwsii",
    "iiiiiiii",
    "iwsiiiii",
    "wsiiiiii",
    "siiiiiwi",
    "iiiiiiii",
]
MUD = [
    "mmdmmmmm",
    "mddmmlmm",
    "mmmmmmmm",
    "mlmmmddm",
    "mmmmmdmm",
    "mmdmmmml",
    "mddmmmmm",
    "mmmmlmmm",
]


def grid16():
    return [["." for _ in range(16)] for _ in range(16)]


def conveyor_frames():
    """Belt pointing UP, 4 frames: the yellow chevrons move up 2px per frame.
    The game rotates it for the other directions."""
    pal = {"k": "#2b2b35", "K": "#383844", "r": "#7d8290", "c": "#f2c230", "C": "#a07c10"}
    frames = []
    for f in range(4):
        g = grid16()
        for y in range(16):
            for x in range(16):
                g[y][x] = "r" if x in (0, 15) else ("K" if (y + f * 2) % 4 == 0 else "k")
        for base in range(-8, 24, 8):
            y0 = base - f * 2
            for i, (xa, xb) in enumerate([(7, 8), (6, 9), (5, 10)]):
                y = y0 + i
                if 0 <= y < 16:
                    g[y][xa] = "c"
                    g[y][xb] = "c"
                if 0 <= y + 1 < 16 and i == 2:
                    g[y + 1][xa] = "C"
                    g[y + 1][xb] = "C"
        frames.append(img(["".join(r) for r in g], pal))
    return frames


def teleporter_frames():
    """A glowing pad, 2 frames that pulse."""
    frames = []
    for f in range(2):
        pal = {"o": "#1a0f2a", "d": "#3a1f5c", "p": "#9a4ce8" if f == 0 else "#c27bff",
               "w": "#e6ccff" if f == 0 else "#ffffff", "g": "#5a2f8c"}
        g = grid16()
        for y in range(16):
            for x in range(16):
                r = ((x - 7.5) ** 2 + (y - 7.5) ** 2) ** 0.5
                if r < 2.2:
                    g[y][x] = "w"
                elif r < 3.6:
                    g[y][x] = "p" if (f == 1) else "g"
                elif r < 5.2:
                    g[y][x] = "d"
                elif r < 6.4:
                    g[y][x] = "p"
                elif r < 7.6:
                    g[y][x] = "o"
        # four little lights around the rim that swap each frame
        for (x, y) in ([(7, 1), (8, 14), (1, 8), (14, 7)] if f == 0 else [(2, 2), (13, 13), (2, 13), (13, 2)]):
            g[y][x] = "w"
        frames.append(img(["".join(r) for r in g], pal))
    return frames


BARREL = [
    "....oooooooo....",
    "...ollllllllo...",
    "..orrrrrrrrrro..",
    "..orrrrrrrrrro..",
    "..oyykkyykkyyo..",
    "..oyykkyykkyyo..",
    "..orrrrkkrrrro..",
    "..orrrrkkrrrro..",
    "..orrrrkkrrrro..",
    "..orrrrkkrrrro..",
    "..orrrrrrrrrro..",
    "..orrrrkkrrrro..",
    "..oyykkyykkyyo..",
    "..oyykkyykkyyo..",
    "...oddddddddo...",
    "....oooooooo....",
]


def tiles():
    save("ice", img(ICE, {"i": "#a8d8f0", "w": "#f0fbff", "s": "#78b0d0"}))
    save("mud", img(MUD, {"m": "#6b4a2a", "d": "#4a3218", "l": "#8a6440"}))
    save("conveyor", strip(conveyor_frames()))
    save("teleporter", strip(teleporter_frames()))
    save("barrel", img(BARREL, {"o": "#1a0a08", "l": "#f07a5a", "r": "#c8321e", "d": "#7a1a10",
                                "y": "#f2c230", "k": "#141418"}))
    save("brick", img(BRICK, {"b": "#b0552a", "l": "#d0733f", "d": "#7a3016", "g": "#9c8f7e"}))
    save("steel", img(STEEL, {"l": "#e0e4ea", "w": "#ffffff", "m": "#a8afbb", "d": "#7d8491", "o": "#4d535e"}))
    water_pal = {"b": "#1f4e9c", "w": "#6fa8ff"}
    save("water", strip([img(WATER_1, water_pal), img(WATER_2, water_pal)]))
    save("bush", img(BUSH, {"d": "#1d5c2a", "m": "#2f8a3c", "l": "#56c264"}))


# ------------------------------------------------------------------ base (16x16, 2 frames: alive, destroyed)

BASE_ALIVE = [
    "................",
    "......oooo......",
    "....oodddddo....",
    "...oddmmmmddo...",
    "..oddmmllmmddo..",
    "..odmmlwwlmmdo..",
    ".oddmlwwwwlmddo.",
    ".odmmlwwwwlmmdo.",
    ".odmmlwwwwlmmdo.",
    ".oddmlwwwwlmddo.",
    "..odmmlwwlmmdo..",
    "..oddmmllmmddo..",
    "...oddmmmmddo...",
    "....oodddddo....",
    "......oooo......",
    "................",
]
BASE_DEAD = [
    "................",
    "......oooo......",
    "....oodddddo....",
    "...oddd.mddddo..",
    "..oddm..lmddo...",
    "..odm.m..lmdo...",
    ".oddmlm.wlmddo..",
    ".odm..w..lmmdo..",
    ".odmml.w.lm.do..",
    "..ddml..w.mddo..",
    "..od.ml.w.mdo...",
    "..oddm.l.mddo...",
    "...od.mmm.ddo...",
    "....oo.dd.do....",
    "......oo.o......",
    "................",
]


def base():
    alive = {"o": "#0b2a33", "d": "#1b6f8a", "m": "#2fa3c0", "l": "#8ff0ff", "w": "#e8ffff"}
    dead = {"o": "#1a1a1a", "d": "#3a3a3a", "m": "#555555", "l": "#6a6a6a", "w": "#2a2a2a"}
    save("base", strip([img(BASE_ALIVE, alive), img(BASE_DEAD, dead)]))


# ------------------------------------------------------------------ power-up icons (12x12, in PowerUp.Kind order)

ICONS = {
    "star": [
        ".....yy.....",
        ".....yy.....",
        "....yyyy....",
        "yyyyywwyyyyy",
        ".yyyywwyyyy.",
        "..yyyyyyyy..",
        "...yyyyyy...",
        "...yyyyyy...",
        "..yyy..yyy..",
        "..yy....yy..",
        ".yy......yy.",
        "............",
    ],
    "shield": [
        ".cccccccccc.",
        "cwwccccccccc",
        "cwcccccccccc",
        "cwccccccccdc",
        "cccccccccddc",
        "ccccccccdddc",
        ".cccccccddc.",
        ".ccccccdddc.",
        "..cccccddc..",
        "...cccdcc...",
        "....cccc....",
        ".....cc.....",
    ],
    "freeze": [
        ".....cc.....",
        "..c..cc..c..",
        "...c.cc.c...",
        "....cwwc....",
        ".c..cwwc..c.",
        "ccccwwwwcccc",
        "ccccwwwwcccc",
        ".c..cwwc..c.",
        "....cwwc....",
        "...c.cc.c...",
        "..c..cc..c..",
        ".....cc.....",
    ],
    "bomb": [
        "........yr..",
        ".......y..r.",
        "......y.....",
        "....kkkk....",
        "..kkkkkkkk..",
        ".kkwkkkkkkk.",
        ".kwkkkkkkkk.",
        ".kkkkkkkkkk.",
        ".kkkkkkkkkk.",
        "..kkkkkkkk..",
        "...kkkkkk...",
        "............",
    ],
    "fortify": [
        "............",
        "gggggggggggg",
        "bbbbbgbbbbbg",
        "llllllgllllg",
        "gggggggggggg",
        "bbgbbbbbgbbb",
        "llgllllllgll",
        "gggggggggggg",
        "bbbbbgbbbbbg",
        "llllllgllllg",
        "gggggggggggg",
        "............",
    ],
    "life": [
        "............",
        "..rrr..rrr..",
        ".rwwrrrrrrr.",
        ".rwrrrrrrrr.",
        ".rrrrrrrrrr.",
        ".rrrrrrrrrr.",
        "..rrrrrrrr..",
        "...rrrrrr...",
        "....rrrr....",
        ".....rr.....",
        "............",
        "............",
    ],
}


def icons():
    pal = {"y": "#f2c230", "w": "#ffffff", "c": "#6fd0ff", "d": "#3c8fc0", "k": "#2b2b35",
           "r": "#ff6b4a", "g": "#9c8f7e", "b": "#b0552a", "l": "#d0733f"}
    order = ["star", "shield", "freeze", "bomb", "fortify", "life"]
    save("powerups", strip([img(ICONS[n], pal) for n in order]))


# ------------------------------------------------------------------ boss (32x32, facing DOWN, 2 tread frames)
# Big enough that drawing it by hand as text would be a pain, so this one is
# drawn with rectangles instead. Change the numbers to reshape it.

def boss():
    pal = {"o": "#141418", "d": "#4a1a24", "m": "#8a2a3a", "l": "#d0506a",
           "s": "#5a6070", "S": "#a8afbb", "w": "#e8ecf2", "y": "#f2c230", "k": "#2b2b35",
           "t": "#2a2a30", "T": "#555560"}
    frames = []
    for frame in range(2):
        g = [["." for _ in range(32)] for _ in range(32)]

        def rect(x0, y0, x1, y1, ch):
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    g[y][x] = ch

        # treads (left and right), with rolling stripes
        for x0 in (0, 26):
            rect(x0, 1, x0 + 5, 30, "o")
            rect(x0 + 1, 2, x0 + 4, 29, "t")
            for y in range(2 + frame * 2, 30, 4):
                rect(x0 + 1, y, x0 + 4, min(y + 1, 29), "T")
        # hull
        rect(6, 3, 25, 26, "o")
        rect(7, 4, 24, 25, "m")
        rect(7, 4, 24, 5, "l")
        rect(7, 22, 24, 25, "d")
        # hazard stripes at the back (top, since it faces down)
        for x in range(8, 24, 4):
            rect(x, 6, x + 1, 7, "y")
            rect(x + 2, 6, x + 3, 7, "k")
        # turret block
        rect(10, 10, 21, 21, "o")
        rect(11, 11, 20, 20, "s")
        rect(11, 11, 20, 12, "S")
        rect(14, 14, 17, 17, "w")  # glowing core
        # twin cannons pointing down
        for x0 in (11, 18):
            rect(x0, 21, x0 + 2, 31, "o")
            rect(x0 + 1, 21, x0 + 1, 30, "S")
        # rivets
        for (x, y) in [(8, 9), (23, 9), (8, 20), (23, 20)]:
            g[y][x] = "w"
        frames.append(img(["".join(r) for r in g], pal))
    save("boss", strip(frames))


# ------------------------------------------------------------------ gunship boss (32x32, nose pointing DOWN)
# The spinning rotor is drawn by the game (gunship.gd), not in the sprite.

def gunship():
    pal = {"o": "#10141c", "m": "#3b4a63", "l": "#6b7fa3", "d": "#26303f", "c": "#7fe0ff",
           "C": "#d8f8ff", "p": "#2b2b35", "r": "#ff5a3c", "y": "#f2c230", "b": "#a8afbb"}
    g = [["." for _ in range(32)] for _ in range(32)]

    def put(x, y, ch):
        if 0 <= x < 32 and 0 <= y < 32:
            g[y][x] = ch

    def ellipse(cx, cy, rx, ry, ch):
        for y in range(32):
            for x in range(32):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                    put(x, y, ch)

    # tail boom (towards the top) with a tail rotor bar and fin
    for y in range(1, 13):
        put(15, y, "m"); put(16, y, "d")
    for x in range(12, 20):
        put(x, 2, "b")
    put(15, 0, "y"); put(16, 0, "y")
    # stub wings with rocket pods
    for y in range(15, 19):
        for x in range(4, 28):
            put(x, y, "d" if y == 18 else "m")
    for x0 in (3, 25):
        for y in range(13, 21):
            for x in range(x0, x0 + 4):
                put(x, y, "p")
        put(x0 + 1, 20, "r"); put(x0 + 2, 20, "r")
    # fuselage, highlight, cockpit glass
    ellipse(16, 19, 6.5, 9.5, "m")
    ellipse(14.5, 16, 2.5, 5, "l")
    ellipse(16, 24.5, 3.5, 3.2, "c")
    ellipse(15.2, 23.8, 1.4, 1.3, "C")
    # hazard stripe and nose gun
    for x in range(11, 21):
        put(x, 12, "y" if x % 2 else "p")
    for y in range(28, 32):
        put(15, y, "b"); put(16, y, "b")
    # outline every empty pixel that touches the ship
    solid = [[g[y][x] != "." for x in range(32)] for y in range(32)]
    for y in range(32):
        for x in range(32):
            if not solid[y][x] and any(0 <= x + dx < 32 and 0 <= y + dy < 32 and solid[y + dy][x + dx]
                                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                g[y][x] = "o"
    save("gunship", img(["".join(r) for r in g], pal))


def app_icon():
    pal = {"o": "#141418", "d": "#b07d10", "m": "#f2c230", "l": "#ffe98a",
           "t": "#4a3a10", "T": "#8a7030", "b": "#fff1b0"}
    tank = img(TANK, pal).resize((48, 48), Image.NEAREST)
    icon = Image.new("RGBA", (64, 64), hexcolor("#141418"))
    icon.paste(tank, (8, 8), tank)
    save("icon", icon)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    tanks()
    player_tanks()
    tiles()
    base()
    icons()
    boss()
    gunship()
    app_icon()
