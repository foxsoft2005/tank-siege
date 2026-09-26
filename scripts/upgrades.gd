class_name Upgrades
extends RefCounted
## The roguelite upgrade list. After each stage you pick 1 of 3 random cards.
## Upgrades last for the whole run (until game over), and most can stack.
##
## To add your own upgrade:
##   1. add an entry to ALL below
##   2. read its level anywhere with GameState.stacks("your_id") and make it do something
## That's it: it will automatically show up as a card.

enum Rarity { COMMON, RARE, EPIC }

const RARITY_NAMES := {Rarity.COMMON: "COMMON", Rarity.RARE: "RARE", Rarity.EPIC: "EPIC"}
const RARITY_COLORS := {
	Rarity.COMMON: Color("#a7b0c2"),
	Rarity.RARE: Color("#4aa8ff"),
	Rarity.EPIC: Color("#c27bff"),
}
## Higher weight = shows up more often.
const RARITY_WEIGHTS := {Rarity.COMMON: 60, Rarity.RARE: 30, Rarity.EPIC: 12}

const ALL := {
	"swift_treads": {
		"name": "Swift Treads", "rarity": Rarity.COMMON, "max": 3,
		"desc": "+15% movement speed.",
	},
	"rapid_loader": {
		"name": "Rapid Loader", "rarity": Rarity.COMMON, "max": 2,
		"desc": "+1 shell on screen at once.",
	},
	"armor_plating": {
		"name": "Armor Plating", "rarity": Rarity.COMMON, "max": 2,
		"desc": "Survive one more hit per life.",
	},
	"field_repair": {
		"name": "Field Repair", "rarity": Rarity.COMMON, "max": 99,
		"desc": "+1 life. Always there when you need it.",
	},
	"ricochet": {
		"name": "Ricochet", "rarity": Rarity.RARE, "max": 2,
		"desc": "Shells bounce sideways off walls. +1 bounce per level.",
	},
	"piercing": {
		"name": "Piercing Rounds", "rarity": Rarity.RARE, "max": 2,
		"desc": "Shells punch through +1 enemy tank.",
	},
	"blast_shells": {
		"name": "Blast Shells", "rarity": Rarity.RARE, "max": 1,
		"desc": "Shells explode on impact, hurting nearby enemies and bricks.",
	},
	"core_shield": {
		"name": "Core Shield", "rarity": Rarity.RARE, "max": 2,
		"desc": "Your core survives +1 hit every stage.",
	},
	"twin_cannon": {
		"name": "Twin Cannon", "rarity": Rarity.EPIC, "max": 1,
		"desc": "Fire two shells side by side.",
	},
	"guard_drone": {
		"name": "Guard Drone", "rarity": Rarity.EPIC, "max": 2,
		"desc": "A drone orbits you and shoots nearby enemies.",
	},
}


## Pick `count` different upgrades, weighted by rarity, skipping maxed ones.
static func roll_choices(owned: Dictionary, count := 3) -> Array[String]:
	var pool: Array[String] = []
	for id: String in ALL:
		if owned.get(id, 0) < ALL[id]["max"]:
			pool.append(id)

	var picks: Array[String] = []
	while picks.size() < count and not pool.is_empty():
		var total := 0
		for id in pool:
			total += weight(id)
		var roll := randi() % total
		for id in pool:
			roll -= weight(id)
			if roll < 0:
				picks.append(id)
				pool.erase(id)
				break
	return picks


static func weight(id: String) -> int:
	return RARITY_WEIGHTS[ALL[id]["rarity"]]


static func color(id: String) -> Color:
	return RARITY_COLORS[ALL[id]["rarity"]]
