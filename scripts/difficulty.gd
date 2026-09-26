class_name Difficulty
extends RefCounted
## Difficulty settings. Every number the game tweaks per difficulty lives in
## this one table, so balancing is easy: change a value, play, repeat.
##
## Read a value with GameState.diff("enemy_speed").

enum Level { EASY, NORMAL, HARD }

const NAMES := {Level.EASY: "EASY", Level.NORMAL: "NORMAL", Level.HARD: "HARD"}
const COLORS := {Level.EASY: Color("#6fe07a"), Level.NORMAL: Color("#f2c230"), Level.HARD: Color("#ff6b4a")}
const DESCRIPTIONS := {
	Level.EASY: "+2 lives, slower enemies, and you keep your star power when you die.",
	Level.NORMAL: "The intended experience.",
	Level.HARD: "1 life fewer, faster and more aggressive enemies. 1.5x scrap.",
}

const SETTINGS := {
	Level.EASY: {
		"lives": 2,               # extra lives at the start of a run
		"enemy_speed": 0.85,      # multiplier for enemy movement speed
		"enemy_shell_speed": 0.8, # multiplier for enemy shell speed
		"enemy_fire_delay": 1.5,  # multiplier for time between enemy shots (bigger = fewer shots)
		"max_on_screen": 3,       # enemies on the map at once
		"spawn_interval": 3.0,    # seconds between spawns
		"raid_bonus": -1,         # change to how many base raiders are allowed at once
		"ai_warmup": 4.0,         # extra seconds smart enemies wander before hunting
		"enemy_reaction": 1.5,    # multiplier for enemy reaction/turn/aim time (bigger = slower to shoot you)
		"boss_hp": 0.75,          # multiplier for boss health
		"keep_star_on_death": true,
		"scrap": 0.75,            # multiplier for scrap earned
	},
	Level.NORMAL: {
		"lives": 0,
		"enemy_speed": 1.0,
		"enemy_shell_speed": 1.0,
		"enemy_fire_delay": 1.0,
		"max_on_screen": 4,
		"spawn_interval": 2.5,
		"raid_bonus": 0,
		"ai_warmup": 0.0,
		"enemy_reaction": 1.0,
		"boss_hp": 1.0,
		"keep_star_on_death": false,
		"scrap": 1.0,
	},
	Level.HARD: {
		"lives": -1,
		"enemy_speed": 1.15,
		"enemy_shell_speed": 1.2,
		"enemy_fire_delay": 0.7,
		"max_on_screen": 5,
		"spawn_interval": 2.0,
		"raid_bonus": 1,
		"ai_warmup": -1.5,
		"enemy_reaction": 0.7,
		"boss_hp": 1.35,
		"keep_star_on_death": false,
		"scrap": 1.5,
	},
}
