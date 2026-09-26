class_name Garage
extends RefCounted
## Meta-progression data: the tanks you can unlock and the permanent perks you
## can buy with SCRAP. Scrap is earned at the end of every run (see
## GameState.end_run), so even a bad run makes you a little stronger.
##
## To add a tank: add an entry to TANKS (and a color to tools/make_sprites.py,
## or reuse an existing sprite). Every stat is optional; missing ones use the
## defaults in stat().
## To add a perk: add an entry to PERKS, then read GameState.perk("your_id")
## wherever it should matter.

## speed / shell_speed are multipliers (1.0 = normal). reload is seconds
## between shots. extra_shells / armor / pierce / lives are added on top.
const TANKS := {
	"scout": {
		"name": "Scout", "cost": 0, "sprite": "player",
		"desc": "Balanced and reliable. The classic.",
	},
	"striker": {
		"name": "Striker", "cost": 60, "sprite": "striker",
		"desc": "Rapid fire: +1 shell on screen, faster shells and reload.",
		"extra_shells": 1, "shell_speed": 1.25, "reload": 0.12, "speed": 0.95,
	},
	"bulwark": {
		"name": "Bulwark", "cost": 80, "sprite": "bulwark",
		"desc": "Heavy armor: survives one extra hit every life. Slow.",
		"armor": 1, "speed": 0.82,
	},
	"phantom": {
		"name": "Phantom", "cost": 120, "sprite": "phantom",
		"desc": "Very fast, shells pierce one tank. Starts with one fewer life.",
		"speed": 1.3, "pierce": 1, "lives": -1,
	},
	"demolisher": {
		"name": "Demolisher", "cost": 150, "sprite": "demolisher",
		"desc": "Every shell explodes. Slow to reload.",
		"blast": true, "reload": 0.4, "speed": 0.95,
	},
}

## costs: price of each level, so the list length is the max level.
const PERKS := {
	"extra_life": {
		"name": "Spare Parts", "costs": [40, 90],
		"desc": "+1 life at the start of every run.",
	},
	"head_start": {
		"name": "Head Start", "costs": [50],
		"desc": "Begin every run with a free common upgrade card.",
	},
	"reroll": {
		"name": "Reroll", "costs": [60],
		"desc": "Once per stage, reroll the upgrade cards.",
	},
	"fourth_card": {
		"name": "Wide Choice", "costs": [100],
		"desc": "Choose from 4 upgrade cards instead of 3.",
	},
	"scrap_magnet": {
		"name": "Scrap Magnet", "costs": [50, 110],
		"desc": "+25% scrap from every run.",
	},
}

const DEFAULTS := {
	"speed": 1.0, "shell_speed": 1.0, "reload": 0.18,
	"extra_shells": 0, "armor": 0, "pierce": 0, "lives": 0, "blast": false,
}


## Read a stat for a tank, falling back to the default.
static func stat(tank_id: String, key: String) -> Variant:
	return TANKS[tank_id].get(key, DEFAULTS.get(key))


## Price of the next level of a perk, or -1 if it's maxed out.
static func next_perk_cost(perk_id: String, current_level: int) -> int:
	var costs: Array = PERKS[perk_id]["costs"]
	return costs[current_level] if current_level < costs.size() else -1


## How much scrap a finished run is worth.
static func scrap_for_run(score: int, stage: int, best_combo: int, bosses: int, magnet: int) -> int:
	var base := score / 100 + (stage - 1) * 10 + best_combo * 2 + bosses * 25
	return int(base * (1.0 + 0.25 * magnet))
