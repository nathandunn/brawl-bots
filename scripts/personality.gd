class_name Personality
extends RefCounted
## What a gunman is like. Every man carries the same six-shooter and the same fists - the
## only thing that differs is how he thinks. Each trait is 0..1 and feeds the utility brain in
## gunman.gd and the role assignment in team_brain.gd.

const TRAITS: Array[String] = ["aggression", "caution", "patience", "discipline", "cunning", "nerve", "teamwork", "height", "brawl", "trigger"]

const TRAIT_HELP := {
	"aggression": "Closes distance, takes marginal shots, joins rushes",
	"caution": "Values cover, ducks when aimed at, falls back when hurt",
	"patience": "Waits for the enemy to show himself instead of peeking into a ready gun",
	"discipline": "Follows the team plan over instinct; counts shots; reloads before he must",
	"cunning": "Flanks, takes hidden routes, picks spots that beat the enemy's cover",
	"nerve": "Shrugs off suppression and wounds; stands in a duel",
	"teamwork": "Stays near mates, covers them, avenges them",
	"height": "Wants the balcony and the stairs",
	"brawl": "Goes for fists and point-blank work; rushes men who are reloading",
	"trigger": "Fans the hammer - fast, wild shots - instead of aiming each one",
}

const PRESETS := {
	"Balanced":    {"aggression": 0.5, "caution": 0.5, "patience": 0.5, "discipline": 0.5, "cunning": 0.5, "nerve": 0.5, "teamwork": 0.5, "height": 0.5, "brawl": 0.3, "trigger": 0.3},
	"Gunslinger":  {"aggression": 0.8, "caution": 0.25, "patience": 0.2, "discipline": 0.4, "cunning": 0.4, "nerve": 0.9, "teamwork": 0.3, "height": 0.2, "brawl": 0.3, "trigger": 0.65},
	"Sharpshooter": {"aggression": 0.3, "caution": 0.6, "patience": 0.9, "discipline": 0.8, "cunning": 0.5, "nerve": 0.6, "teamwork": 0.4, "height": 0.95, "brawl": 0.05, "trigger": 0.05},
	"Brawler":     {"aggression": 0.9, "caution": 0.2, "patience": 0.15, "discipline": 0.3, "cunning": 0.35, "nerve": 0.8, "teamwork": 0.4, "height": 0.1, "brawl": 0.95, "trigger": 0.5},
	"Snake":       {"aggression": 0.4, "caution": 0.6, "patience": 0.8, "discipline": 0.4, "cunning": 0.95, "nerve": 0.5, "teamwork": 0.2, "height": 0.5, "brawl": 0.3, "trigger": 0.2},
	"Lawman":      {"aggression": 0.5, "caution": 0.5, "patience": 0.6, "discipline": 0.95, "cunning": 0.4, "nerve": 0.8, "teamwork": 0.95, "height": 0.4, "brawl": 0.3, "trigger": 0.15},
	"Coward":      {"aggression": 0.1, "caution": 0.95, "patience": 0.7, "discipline": 0.3, "cunning": 0.6, "nerve": 0.1, "teamwork": 0.2, "height": 0.6, "brawl": 0.05, "trigger": 0.5},
	"Desperado":   {"aggression": 1.0, "caution": 0.05, "patience": 0.05, "discipline": 0.1, "cunning": 0.2, "nerve": 1.0, "teamwork": 0.1, "height": 0.2, "brawl": 0.7, "trigger": 0.9},
}

const PRESET_HELP := {
	"Balanced": "A bit of everything",
	"Gunslinger": "Nerve and speed: walks into the duel and fans the hammer",
	"Sharpshooter": "Takes the balcony, waits, aims every shot",
	"Brawler": "Charges men who are reloading and finishes it with his fists",
	"Snake": "Finds the angle that beats your cover and waits there",
	"Lawman": "Holds the team together, follows the plan, counts your shots",
	"Coward": "Hides, runs, and shoots you in the back if he gets the chance",
	"Desperado": "All in, all the time",
	"Random": "Every trait rolled fresh each match",
}

const ORDER: Array[String] = ["Balanced", "Gunslinger", "Sharpshooter", "Brawler", "Snake", "Lawman", "Coward", "Desperado", "Random"]

var t := {}


static func preset(name: String, rng: RandomNumberGenerator = null) -> Personality:
	var p := Personality.new()
	if name == "Random" or not PRESETS.has(name):
		var r := rng
		if r == null:
			r = RandomNumberGenerator.new()
			r.randomize()
		for k in TRAITS:
			p.t[k] = r.randf()
		return p
	var src: Dictionary = PRESETS[name]
	for k in TRAITS:
		p.t[k] = float(src.get(k, 0.5))
	return p


func g(k: String) -> float:
	return float(t.get(k, 0.5))


func duplicate_p() -> Personality:
	var p := Personality.new()
	p.t = t.duplicate()
	return p


## A copy with every trait nudged a little, so five men of one preset are not five clones.
func jittered(rng: RandomNumberGenerator, amount: float) -> Personality:
	var p := duplicate_p()
	for k in TRAITS:
		p.t[k] = clampf(g(k) + rng.randf_range(-amount, amount), 0.0, 1.0)
	return p
