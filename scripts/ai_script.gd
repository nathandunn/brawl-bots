class_name AiScript
extends RefCounted
## The exposed AI: a side's rule script. Every man on the side reads it top to bottom each time
## he decides; the first rule whose conditions all hold, and whose action he can actually do,
## is what he does. Anything the script doesn't cover falls through to the built-in brain - so
## an empty script is the stock AI, and one line changes one habit.
##
##   # comments start with a hash
##   set caution 0.8                      overrides a personality trait for the whole side
##   aim 1.3                              takes 30% longer over every shot (truer, slower)
##   when bleeding and hp < 40 -> rush nearest for 3
##   when enemy_reloading and nearest < 12 -> rush reloading
##   when pinned -> hide for 2
##   when outnumbered and not high -> fall back
##   otherwise -> default
##
## Conditions join with "and"; "not" flips one. Numbers compare with < <= > >= == !=.

const BOOLS := {
	"bleeding": "losing blood from any wound",
	"reloading": "thumbing cartridges in",
	"jammed": "his Colt is jammed",
	"dry": "no rounds or stars left at all",
	"wounded": "hit anywhere at least once",
	"leg_hit": "shot or broken in a leg",
	"arm_hit": "shot or broken in an arm",
	"pinned": "rattled by fire (suppression high)",
	"alone": "no mate within 8 m",
	"aimed_at": "an enemy he can see is aiming at him",
	"enemy_seen": "he can see at least one enemy",
	"enemy_reloading": "a known enemy within 15 m is empty or reloading",
	"enemy_dry": "a known enemy is out of rounds for good",
	"enemy_high": "a known enemy holds high ground",
	"enemy_melee": "the nearest known enemy fights with a blade or staff",
	"high": "he is on high ground (balcony, rafter, roof)",
	"in_cover": "he is at a cover spot",
	"mate_down": "a mate fell within 6 m in the last 5 s",
	"stalemate": "nobody has drawn blood for 5 s",
	"outnumbered": "his side has fewer men standing",
	"ahead": "his side has more men standing",
	"even": "the sides are level",
	"sudden_death": "the clock has run out and it's next man down",
	"super": "he is a Super",
	"minion": "he is a Minion",
	"melee": "he fights with a blade or staff",
	"gunman": "he carries a Colt",
	"ninja": "he is a ninja",
	"has_stars": "he has throwing stars left",
	"in_reach": "an enemy is inside his weapon's reach",
	"has_bottle": "he has a bottle in his hand",
	"near_bottle": "a bottle (bar, shelf or table) within 7 m",
	"edge": "he is near the open edge of the balcony or a roof",
	"clinch": "an enemy is within 3 ft - close enough to wrestle",
	"close": "an enemy is within 3 m - nobody shoots that close",
	"holding": "he has a bottle or a chair in his hands",
	"near_chair": "a chair within 7 m",
	"wrestling": "he is locked in a wrestle",
}
const NUMS := {
	"hp": "health 0-100",
	"bleed_secs": "seconds until he bleeds out (999 if not bleeding)",
	"ammo": "rounds or stars left",
	"loaded": "rounds in the cylinder (stars in hand)",
	"mates": "men standing on his side, him included",
	"foes": "enemies standing",
	"diff": "mates - foes",
	"time": "seconds left on the clock (0 in sudden death)",
	"nearest": "metres to the nearest known enemy (99 if none)",
	"seen": "how many enemies he can see",
	"suppression": "how rattled he is, 0-1.5",
	"random": "a fresh number 0-100 every decision",
	"speed": "his speed ability (0.7-1.6)",
	"smarts": "his smarts ability (0-1)",
}
const ACTIONS := {
	"hold": "best cover spot near where he is, gun up",
	"advance": "best cover spot nearer the enemy",
	"hide": "out of every enemy's sight",
	"cower": "freeze, arms over his head (why would you)",
	"flank": "slip round out of sight to the angle that beats their cover",
	"rush": "rush nearest | weakest | reloading | high | aiming | melee",
	"fall back": "cover further from the enemy",
	"take high": "the nearest high ground",
	"hunt": "go looking toward the enemy's end",
	"flip table": "kick over the nearest table into cover",
	"grab bottle": "go and get the nearest bottle within 7 m (then throw it)",
	"grab chair": "go and pick up the nearest chair within 7 m (then throw it)",
	"default": "whatever the built-in brain would do",
}
const RUSH_TARGETS: Array[String] = ["nearest", "weakest", "reloading", "high", "aiming", "melee"]
const OPS: Array[String] = ["<=", ">=", "==", "!=", "<", ">"]

## Ready-made lines for the editor's Examples list: [what it does, the line].
const EXAMPLES := [
	["Bleeding badly? Make it count", "when bleeding and bleed_secs < 15 -> rush nearest for 3"],
	["Punish a man who's reloading", "when enemy_reloading and nearest < 8 -> rush reloading"],
	["Duck a gun pointed at you", "when aimed_at and in_cover -> hide for 1.5"],
	["Pinned down: get out of sight", "when pinned -> hide for 2"],
	["Out of rounds: find a bottle", "when dry and not has_bottle and near_bottle -> grab bottle"],
	["Too close to shoot: grab a chair", "when close and not holding and near_chair -> grab chair"],
	["Get up top early", "when not high and time > 90 -> take high"],
	["Off the rail when they're close", "when edge and nearest < 4 -> fall back"],
	["Supers break a stalemate", "when super and stalemate -> flank"],
	["Minions stick together", "when minion and alone -> fall back"],
	["Blades: wait, then strike", "when melee and nearest < 6 -> rush nearest for 1.5"],
	["Outnumbered: dig in", "when outnumbered and enemy_seen -> hold"],
	["Losing on the clock: go", "when time < 25 and diff < 0 -> hunt"],
	["A coin toss (30%)", "when random < 30 and stalemate -> advance"],
	["Kick a table over under fire", "when pinned and not in_cover -> flip table"],
	["Steadier, slower shooting", "aim 1.3"],
	["A trait for the whole side", "set caution 0.8"],
	["Everything else: built-in brain", "otherwise -> default"],
]

const PRESETS := {
	"Built-in brain": "# Empty: every man uses the built-in brain.\n# Add a rule above 'otherwise' to change one habit.\notherwise -> default\n",
	"Careful hands": "# Stay in cover, make every shot count, never charge a loaded gun.\nset caution 0.85\nset patience 0.8\naim 1.25\nwhen pinned -> hide for 2\nwhen reloading and not in_cover -> hide\nwhen bleeding and bleed_secs < 15 -> rush nearest for 3\nwhen enemy_reloading and nearest < 8 -> rush reloading\nwhen enemy_seen -> hold\notherwise -> default\n",
	"Wild bunch": "# Close fast and keep moving. Make them reload, then go.\nset aggression 0.9\nset nerve 0.85\naim 0.8\nwhen enemy_reloading and nearest < 15 -> rush reloading for 3\nwhen aimed_at and nearest < 6 -> rush aiming\nwhen mate_down -> rush nearest for 2\nwhen stalemate -> advance\notherwise -> default\n",
	"High ground first": "# Get up top before anything else; come down for nothing.\nset height 0.95\nwhen not high and not enemy_seen -> take high\nwhen not high and stalemate -> take high\nwhen high and pinned -> hide for 1.5\nwhen high -> hold\notherwise -> default\n",
	"Ninja ambush": "# For blades: hide, wait for them to come close, then strike.\nset cunning 0.9\nwhen melee and in_reach -> rush nearest\nwhen melee and nearest < 6 -> rush nearest for 1.5\nwhen melee and aimed_at -> hide for 1.5\nwhen melee and stalemate -> flank\nwhen melee and enemy_seen -> hide\nwhen has_stars and enemy_seen and nearest > 6 -> hold\notherwise -> default\n",
	"Supers lead, minions swarm": "# Supers hunt; minions stay together and rush whoever the supers pin.\nwhen super and stalemate -> flank\nwhen super and enemy_seen -> advance\nwhen minion and alone -> fall back\nwhen minion and enemy_reloading -> rush reloading\nwhen minion and aimed_at -> hide for 1\nwhen minion -> hold\notherwise -> default\n",
	"Last stand": "# Bleeding men make it count; the healthy cover them.\nwhen bleeding and bleed_secs < 20 -> rush nearest for 4\nwhen bleeding -> hold\nwhen mate_down and outnumbered -> fall back\notherwise -> default\n",
}
const PRESET_ORDER: Array[String] = ["Built-in brain", "Careful hands", "Wild bunch", "High ground first", "Ninja ambush", "Supers lead, minions swarm", "Last stand"]

var rules: Array = []          # {line, text, conds: [{name, op, num, neg}], action, arg, lock}
var errors: PackedStringArray = []
var trait_set := {}            # trait -> value
var aim_mult := 1.0
var source := ""


static func parse(src: String) -> AiScript:
	var sc := AiScript.new()
	sc.source = src
	var lines := src.split("\n")
	var otherwise_at := 0
	for li in lines.size():
		var n := li + 1
		var raw := String(lines[li])
		var hash := raw.find("#")
		var line := (raw.substr(0, hash) if hash >= 0 else raw).strip_edges().to_lower()
		if line == "":
			continue
		var words := line.split(" ", false)
		if words[0] == "set":
			if words.size() != 3 or not Personality.TRAITS.has(words[1]) or not words[2].is_valid_float():
				var hint := ""
				if words.size() >= 2 and not Personality.TRAITS.has(words[1]):
					hint = _did_you_mean(words[1], Personality.TRAITS)
				sc.errors.append("line %d: 'set' wants a trait and a number 0-1, e.g. set caution 0.8%s (traits: %s)" % [n, hint, ", ".join(Personality.TRAITS)])
				continue
			sc.trait_set[words[1]] = clampf(float(words[2]), 0.0, 1.0)
			continue
		if words[0] == "aim":
			if words.size() != 2 or not words[1].is_valid_float():
				sc.errors.append("line %d: 'aim' wants one number, e.g. aim 1.3" % n)
				continue
			sc.aim_mult = clampf(float(words[1]), 0.3, 3.0)
			continue
		var arrow := line.find("->")
		if arrow < 0:
			sc.errors.append("line %d: a rule needs '->' between the condition and the action" % n)
			continue
		var lhs := line.substr(0, arrow).strip_edges()
		var rhs := line.substr(arrow + 2).strip_edges()
		if otherwise_at > 0:
			sc.errors.append("line %d: comes after 'otherwise' on line %d, so it can never fire - move it above" % [n, otherwise_at])
			continue
		var rule := {"line": n, "text": raw.strip_edges(), "conds": [], "action": "", "arg": "", "lock": 0.0}
		if lhs == "otherwise" or lhs == "always":
			otherwise_at = n
		elif lhs.begins_with("when "):
			var ok := true
			for part in lhs.substr(5).split(" and ", false):
				var c := _parse_cond(String(part).strip_edges())
				if c.has("error"):
					sc.errors.append("line %d: %s" % [n, c["error"]])
					ok = false
					break
				rule["conds"].append(c)
			if not ok:
				continue
		else:
			sc.errors.append("line %d: start a rule with 'when ...' or 'otherwise'" % n)
			continue
		var act := _parse_action(rhs)
		if act.has("error"):
			sc.errors.append("line %d: %s" % [n, act["error"]])
			continue
		rule["action"] = act["action"]
		rule["arg"] = act["arg"]
		rule["lock"] = act["lock"]
		sc.rules.append(rule)
	return sc


static func _parse_cond(t: String) -> Dictionary:
	var neg := false
	if t.begins_with("not "):
		neg = true
		t = t.substr(4).strip_edges()
	for op in OPS:
		var i := t.find(op)
		if i > 0:
			var name := t.substr(0, i).strip_edges()
			var num := t.substr(i + op.length()).strip_edges()
			if not NUMS.has(name):
				return {"error": "'%s' isn't a number I know%s (numbers: %s)" % [name, _did_you_mean(name, NUMS.keys()), ", ".join(NUMS.keys())]}
			if not num.is_valid_float():
				return {"error": "'%s' should be a number" % num}
			return {"name": name, "op": op, "num": float(num), "neg": neg}
	if BOOLS.has(t):
		return {"name": t, "op": "", "num": 0.0, "neg": neg}
	if NUMS.has(t):
		return {"error": "'%s' is a number - compare it, e.g. %s < 40" % [t, t]}
	var dm := _did_you_mean(t, BOOLS.keys() + NUMS.keys())
	return {"error": "don't know '%s'%s - see the word list, or type a few letters for suggestions" % [t, dm if dm != "" else " (try: %s, ...)" % ", ".join(BOOLS.keys().slice(0, 8))]}


static func _parse_action(t: String) -> Dictionary:
	var lock := 0.0
	var fi := t.find(" for ")
	if fi >= 0:
		var secs := t.substr(fi + 5).strip_edges()
		if not secs.is_valid_float():
			return {"error": "'for' wants seconds, e.g. hide for 2"}
		lock = clampf(float(secs), 0.0, 20.0)
		t = t.substr(0, fi).strip_edges()
	if t.begins_with("rush"):
		var arg := t.substr(4).strip_edges()
		if arg == "":
			arg = "nearest"
		if not RUSH_TARGETS.has(arg):
			return {"error": "rush whom?%s one of: %s" % [_did_you_mean(arg, RUSH_TARGETS), ", ".join(RUSH_TARGETS)]}
		return {"action": "rush", "arg": arg, "lock": lock}
	if ACTIONS.has(t):
		return {"action": t, "arg": "", "lock": lock}
	return {"error": "don't know the action '%s'%s (actions: %s)" % [t, _did_you_mean(t, ACTIONS.keys()), ", ".join(ACTIONS.keys())]}


## " - did you mean 'pinned'?" for the closest known word, or "" if nothing is close.
static func _did_you_mean(w: String, words: Array) -> String:
	var best := ""
	var bd := 99
	for k in words:
		var d := _edit_distance(w, String(k))
		if String(k).begins_with(w) and w.length() >= 3:
			d = mini(d, 1)
		if d < bd:
			bd = d
			best = String(k)
	if best != "" and bd <= maxi(2, w.length() / 3):
		return " - did you mean '%s'?" % best
	return ""


static func _edit_distance(a: String, b: String) -> int:
	var prev: Array[int] = []
	for j in b.length() + 1:
		prev.append(j)
	for i in range(1, a.length() + 1):
		var cur: Array[int] = [i]
		for j in range(1, b.length() + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			cur.append(mini(mini(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost))
		prev = cur
	return prev[b.length()]


## Everything the editor needs for suggestions and lookups, as plain data.
static func vocab() -> Dictionary:
	var traits := {}
	for k in Personality.TRAITS:
		traits[k] = String(Personality.TRAIT_HELP.get(k, ""))
	var rush := {}
	for k in RUSH_TARGETS:
		rush[k] = "rush the %s enemy" % k if k != "reloading" and k != "aiming" else ("rush a man who is reloading" if k == "reloading" else "rush the man aiming at him")
	return {"bools": BOOLS, "nums": NUMS, "actions": ACTIONS, "traits": traits, "rush": rush, "examples": EXAMPLES,
		"keywords": {"when": "starts a rule: when <condition> and ... -> <action>", "and": "both conditions must hold",
			"not": "flips a yes/no condition: not high", "otherwise": "the catch-all last rule: otherwise -> default",
			"set": "set <trait> <0-1> for the whole side", "aim": "aim <multiplier>: >1 aims longer and truer", "for": "keep doing it this many seconds: hide for 2"}}


## The first rule that holds for this man, or {} if none does.
func first_match(g: Gunman, skip: Array) -> Dictionary:
	for r in rules:
		if skip.has(r["line"]):
			continue
		var ok := true
		for c in r["conds"]:
			var v = g.rule_value(String(c["name"]))
			var hold: bool
			if String(c["op"]) == "":
				hold = bool(v)
			else:
				var x := float(v)
				var y := float(c["num"])
				match String(c["op"]):
					"<": hold = x < y
					"<=": hold = x <= y
					">": hold = x > y
					">=": hold = x >= y
					"==": hold = absf(x - y) < 0.001
					"!=": hold = absf(x - y) >= 0.001
			if bool(c["neg"]):
				hold = not hold
			if not hold:
				ok = false
				break
		if ok:
			return r
	return {}


static func help_text() -> String:
	var t := "RULES - one per line, read top to bottom; the first that holds (and can be done) wins.\n"
	t += "  when <condition> and <condition> -> <action> [for <seconds>]\n  otherwise -> <action>\n"
	t += "  set <trait> <0-1>     aim <multiplier>     # comment\n\n"
	t += "YES/NO CONDITIONS (put 'not' in front to flip):\n"
	for k in BOOLS:
		t += "  %-16s %s\n" % [k, BOOLS[k]]
	t += "\nNUMBERS (compare with < <= > >= == !=):\n"
	for k in NUMS:
		t += "  %-16s %s\n" % [k, NUMS[k]]
	t += "\nACTIONS:\n"
	for k in ACTIONS:
		t += "  %-16s %s\n" % [k, ACTIONS[k]]
	t += "\nTRAITS for 'set': " + ", ".join(Personality.TRAITS) + "\n"
	return t
