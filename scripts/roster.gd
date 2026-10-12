class_name Roster
extends RefCounted
## Who can fight: factions (what a side looks like and which characters it fields), characters
## (a personality and a loadout), grades (how good a man is - speed, jump, smarts), and the
## weapons. Any faction can face any other on any map. Damage is the same for everyone: a
## Super dies to one good slug or one clean cut like anybody else - he is just faster, jumps
## further and thinks better.

const FACTIONS := {
	"outlaws": {"name": "Outlaws", "family": "west", "color": Color(0.72, 0.2, 0.16), "wins": "The Outlaws win", "letter": "O",
		"blurb": "Bandana masks and black hats; Colts and fists"},
	"law": {"name": "Law", "family": "west", "color": Color(0.3, 0.42, 0.62), "wins": "The Law wins", "letter": "L",
		"blurb": "Tin stars and pale hats; Colts and fists"},
	"lotus": {"name": "Black Lotus", "family": "ninja", "color": Color(0.52, 0.36, 0.74), "wins": "The Black Lotus wins", "letter": "K",
		"blurb": "Ninja clan in black with violet sashes"},
	"dragon": {"name": "Red Dragon", "family": "ninja", "color": Color(0.92, 0.55, 0.14), "wins": "The Red Dragon wins", "letter": "D",
		"blurb": "Ninja clan in crimson with gold sashes"},
}
const FACTION_ORDER: Array[String] = ["outlaws", "law", "lotus", "dragon"]

## Characters each family can field. A western character is a temperament with a Colt; a ninja
## character also decides the weapon.
const KINDS := {
	"west": ["Balanced", "Gunslinger", "Sharpshooter", "Brawler", "Snake", "Lawman", "Coward", "Desperado"],
	"ninja": ["Shinobi", "Kunoichi", "Monk", "Ronin", "Shadow"],
}
const LOADOUTS := {
	"west": {"gun": "colt", "melee": "fists", "stars": 0},
	"Shinobi": {"gun": "", "melee": "katana", "stars": 6},
	"Kunoichi": {"gun": "", "melee": "nunchaku", "stars": 10},
	"Monk": {"gun": "", "melee": "staff", "stars": 0},
	"Ronin": {"gun": "", "melee": "katana", "stars": 3},
	"Shadow": {"gun": "", "melee": "katana", "stars": 12, "stealth": true},
}
## A character's nudge to the grade's abilities (the Kunoichi is lighter on her feet, etc.)
const KIND_BIAS := {
	"Kunoichi": {"speed": 0.05, "jump": 0.2},
	"Monk": {"smarts": 0.1},
	"Ronin": {"speed": -0.03},
	"Shadow": {"jump": 0.1},
}
const KIND_HELP := {
	"Shinobi": "Katana and six throwing stars; the all-rounder",
	"Kunoichi": "Nunchaku and ten stars; quick, and the best jumper",
	"Monk": "Bo staff - longest reach, blocks well, sweeps legs; no stars",
	"Ronin": "Masterless swordsman: katana, three stars, will not back down",
	"Shadow": "Katana and a dozen stars; hard to spot while still",
}

## Skill, not armour.
## speed: moves, draws, cocks, reloads, swings faster. jump: vaults, drops, leaps (class 0/1/2).
## smarts: decides faster and better. aim: steadiness of hand (divides the spread). nerve: added
## to his temperament - minions panic, supers don't.
const GRADES := {
	"Minion": {"speed": 0.85, "jump": 0.0, "smarts": 0.2, "aim": 0.7, "nerve": -0.25},
	"Regular": {"speed": 1.0, "jump": 0.3, "smarts": 0.5, "aim": 1.0, "nerve": 0.0},
	"Veteran": {"speed": 1.15, "jump": 0.6, "smarts": 0.72, "aim": 1.2, "nerve": 0.1},
	"Super": {"speed": 1.4, "jump": 1.0, "smarts": 0.95, "aim": 1.6, "nerve": 0.25},
}
const GRADE_ORDER: Array[String] = ["Minion", "Regular", "Veteran", "Super"]
const GRADE_NAMES := {
	"west": {"Minion": "Greenhorn", "Regular": "Regular", "Veteran": "Veteran", "Super": "Super Gunslinger"},
	"ninja": {"Minion": "Genin", "Regular": "Chunin", "Veteran": "Jonin", "Super": "Grandmaster"},
}

## Melee weapons. reach (m), wind (s to land), cd (s between blows), block (chance to turn a
## blow or a star when facing it), kd (knockdown), cut (bleeds) or blunt (bruises, breaks, stuns).
const WEAPONS := {
	"fists": {"reach": 1.45, "wind": 0.28, "cd": 0.7, "block": 0.0, "kd": 0.2, "cut": false, "dmg": 12.0},
	"katana": {"reach": 1.95, "wind": 0.3, "cd": 0.75, "block": 0.6, "kd": 0.05, "cut": true, "dmg": 34.0},
	"nunchaku": {"reach": 1.6, "wind": 0.17, "cd": 0.38, "block": 0.3, "kd": 0.3, "cut": false, "dmg": 11.0},
	"staff": {"reach": 2.4, "wind": 0.3, "cd": 0.7, "block": 0.65, "kd": 0.45, "cut": false, "dmg": 15.0},
}


static func family(faction: String) -> String:
	return String(FACTIONS.get(faction, FACTIONS["outlaws"])["family"])


static func kinds_for(faction: String) -> Array:
	return KINDS[family(faction)]


static func default_kind(faction: String) -> String:
	return "Balanced" if family(faction) == "west" else "Shinobi"


static func loadout(kind: String, faction: String) -> Dictionary:
	if family(faction) == "west":
		return LOADOUTS["west"].duplicate()
	return LOADOUTS.get(kind, LOADOUTS["Shinobi"]).duplicate()


static func grade_name(grade: String, faction: String) -> String:
	return String(GRADE_NAMES[family(faction)].get(grade, grade))


static func abilities(grade: String, kind: String) -> Dictionary:
	var a: Dictionary = GRADES.get(grade, GRADES["Regular"]).duplicate()
	var b: Dictionary = KIND_BIAS.get(kind, {})
	for k in b:
		a[k] = float(a[k]) + float(b[k])
	a["speed"] = clampf(a["speed"], 0.7, 1.6)
	a["jump"] = clampf(a["jump"], 0.0, 1.0)
	a["smarts"] = clampf(a["smarts"], 0.0, 1.0)
	a["aim"] = float(a.get("aim", 1.0))
	return a
