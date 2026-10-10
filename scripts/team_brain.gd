class_name TeamBrain
extends RefCounted
## One per side. Three jobs:
##
## 1. The blackboard - every enemy any of us has seen or heard: where, when, how many shots
##    he has fired since he last reloaded (we count them), and whether he is reloading now.
## 2. The tactical map - for every tactical point in the saloon, against the enemies we know
##    about: can they see a man standing there, can they see him crouched, and can a man there
##    hit THEM even when they crouch (the flank / high-ground value). Swept a slice per tick.
## 3. The commander - runs the team's doctrine as a little phase machine and hands each man an
##    order: a role, a zone to pull toward, how far to push, and a fire policy. How hard a man
##    sticks to his order is his discipline; the rest is his own personality.

const DOCTRINES: Array[String] = ["Adaptive", "Dig In", "Rush", "Pincer", "High Ground", "Leapfrog", "Bait"]
const DOCTRINE_HELP := {
	"Adaptive": "A commander who reads the fight: presses a man advantage, digs in when behind, flanks a stalemate, rushes reloads",
	"Dig In": "Everyone in cover on our side; shoot only at men who show themselves. One man upstairs",
	"Rush": "Stack up, then all five charge together, fanning at close range",
	"Pincer": "Two take the balcony and work across it; three pin from the floor; when the high men are over, everyone springs",
	"High Ground": "Three hold the balcony and shoot down over the cover; two guard the foot of our stair",
	"Leapfrog": "Two groups: one bounds cover-to-cover while the other lays down suppressing fire, then swap",
	"Bait": "One man with nerve draws them out and runs back; the other four wait in ambush",
}
const CONTACT_TTL := 8.0
const SWEEP_TICKS := 50       # the whole map is re-scored about once a second
const MAX_THREATS := 4

var team := 0
var side := -1.0               # -1 west (Red), +1 east (Blue)
var manager: MatchManager
var saloon: Saloon
var members: Array[Gunman] = []
var doctrine := "Adaptive"
var plan := ""
var phase := ""
var plan_t := 0.0
var phase_t := 0.0
var orders := {}               # Gunman -> Dictionary
var contacts := {}             # Gunman -> {pos, t, seen_t, reloading, reload_end}
var shots_counted := {}        # Gunman -> shots fired since we last heard him reload
var claims := {}               # Gunman -> node id
var events: Array = []         # [time, text, important]
var plan_seconds := {}         # plan -> seconds active (for stats)
var rng := RandomNumberGenerator.new()
var _cmd_t := 0.0
var _punish := {}              # Gunman(member) -> [target, until]
var _avenge: Gunman = null
var _avenge_until := 0.0
var _last_damage_t := 0.0
var groups := [[], []]          # leapfrog / pincer split
var _bait_shots0 := 0
var _stormer: Gunman = null      # sent up the stairs to clear their men off the balcony
var _upstairs_t := 0.0

# tactical map
var _n := 0
var expo_s := PackedFloat32Array()
var expo_c := PackedFloat32Array()
var deny := PackedFloat32Array()
var _nx_s := PackedFloat32Array()
var _nx_c := PackedFloat32Array()
var _nx_d := PackedFloat32Array()
var _threats: Array[Vector3] = []      # used by the current map
var _sweep_threats: Array[Vector3] = []
var _sweep_i := 0
var _sweep_ids := PackedInt32Array()
var _tac_flag := PackedByteArray()


func setup(t: int, m: MatchManager, s: Saloon, doc: String) -> void:
	team = t
	side = -1.0 if t == 0 else 1.0
	manager = m
	saloon = s
	doctrine = doc
	_n = saloon.nodes.size()
	for arr in [expo_s, expo_c, deny, _nx_s, _nx_c, _nx_d]:
		arr.resize(_n)
		arr.fill(0.0)
	_tac_flag.resize(_n)
	_tac_flag.fill(0)
	for id in saloon.tac_ids:
		_tac_flag[id] = 1
	for i in _n:
		if not saloon.nodes[i].get("dead", false):
			_sweep_ids.append(i)
	for id in _sweep_ids:
		saloon.team_astar[team].set_point_weight_scale(id, 1.0)
	_start_sweep()


# ---------------------------------------------------------------- blackboard

func now() -> float:
	return manager.elapsed


func saw(e: Gunman, _by: Gunman) -> void:
	var c: Dictionary = contacts.get(e, {})
	var first := c.is_empty()
	c["pos"] = e.global_position
	c["t"] = now()
	c["seen_t"] = now()
	if e.reloading:
		c["reloading"] = true
		c["reload_end"] = now() + float(Gunman.CYL - e.cylinder) * Gunman.ROUND_LOAD
	contacts[e] = c
	if first and contacts.size() == 1 and now() > 1.0:
		log_event("%s spots %s" % [_short(_by), e.gm_name], false)


func _heard(e: Gunman, noise: float) -> void:
	var c: Dictionary = contacts.get(e, {})
	if not c.is_empty() and now() - float(c.get("seen_t", -99.0)) < 0.6:
		c["t"] = now()
		return
	var off := Vector3(rng.randf_range(-noise, noise), 0, rng.randf_range(-noise, noise))
	c["pos"] = e.global_position + off
	c["t"] = now()
	if not c.has("seen_t"):
		c["seen_t"] = -99.0
	contacts[e] = c


## Every shot in the room is heard and counted - if the team has anyone disciplined enough to
## keep the count. A team of hotheads loses count.
func enemy_fired(e: Gunman) -> void:
	_heard(e, 1.5)
	if rng.randf() < 0.45 + 0.55 * _best("discipline"):
		shots_counted[e] = int(shots_counted.get(e, 0)) + 1


func enemy_reloading(e: Gunman) -> void:
	var d := _nearest_member_dist(e.global_position)
	if d > 16.0:
		return   # the click of a gate is a quiet sound
	_heard(e, 1.0)
	var c: Dictionary = contacts[e]
	c["reloading"] = true
	var spent := clampi(int(shots_counted.get(e, Gunman.CYL)), 1, Gunman.CYL)
	c["reload_end"] = now() + 0.25 + float(spent) * Gunman.ROUND_LOAD
	shots_counted[e] = 0


func enemy_reload_done(e: Gunman) -> void:
	if contacts.has(e):
		var c: Dictionary = contacts[e]
		# we only learn it ended when we see him, or when our estimate runs out
		if now() - float(c.get("seen_t", -99.0)) < 0.5:
			c["reloading"] = false


func heard_shot_near(by: Gunman, _victim: Gunman) -> void:
	_heard(by, 0.8)


func member_hit(_g: Gunman, by: Gunman) -> void:
	_last_damage_t = now()
	if by != null and by.team != team:
		_heard(by, 0.6)


## Our own man is reloading / has finished: tell the other side's ears.
func heard_reload(g: Gunman) -> void:
	manager.brains[1 - team].enemy_reloading(g)


func reload_done(g: Gunman) -> void:
	manager.brains[1 - team].enemy_reload_done(g)


func contact_pos(e: Gunman) -> Vector3:
	if contacts.has(e):
		return contacts[e]["pos"]
	return e.global_position


func is_empty_est(e: Gunman) -> bool:
	if not contacts.has(e):
		return false
	var c: Dictionary = contacts[e]
	if c.get("reloading", false) and now() < float(c.get("reload_end", 0.0)):
		return true
	return int(shots_counted.get(e, 0)) >= Gunman.CYL


func empty_contact_near(p: Vector3, r: float) -> Gunman:
	for e in contacts:
		if not is_instance_valid(e) or not e.alive:
			continue
		var c: Dictionary = contacts[e]
		if now() - float(c["t"]) > 4.0:
			continue
		var cp: Vector3 = c["pos"]
		if absf(cp.y - p.y) > 1.5:
			continue
		if Vector2(cp.x - p.x, cp.z - p.z).length() < r and is_empty_est(e):
			return e
	return null


func best_contact_for(g: Gunman, prefer_empty: bool) -> Gunman:
	var best: Gunman = null
	var bd := INF
	for e in contacts:
		if not is_instance_valid(e) or not e.alive:
			continue
		var cp: Vector3 = contacts[e]["pos"]
		var d := g.flat_dist(cp) + absf(cp.y - g.global_position.y) * 3.0
		if prefer_empty and is_empty_est(e):
			d *= 0.4
		if d < bd:
			bd = d
			best = e
	return best


func threat_count() -> int:
	return _threats.size()


func threat_centroid() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for e in contacts:
		if is_instance_valid(e) and e.alive:
			c += contacts[e]["pos"]
			n += 1
	if n == 0:
		return enemy_home()
	return c / n


func _ground_contacts_centroid() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for e in contacts:
		if is_instance_valid(e) and e.alive and float(contacts[e]["pos"].y) < 1.0:
			c += contacts[e]["pos"]
			n += 1
	return c / n if n > 0 else threat_centroid()


func team_centroid() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for g in members:
		if g.alive:
			c += g.global_position
			n += 1
	return c / n if n > 0 else home()


func home() -> Vector3:
	return Vector3(side * 10.0, 0, 3.0)


func enemy_home() -> Vector3:
	return Vector3(-side * 10.0, 0, 3.0)


func crouch_exposure(id: int) -> float:
	if id < 0 or _threats.is_empty():
		return 0.0
	return expo_c[id] / float(_threats.size())


func stand_sight(id: int) -> float:
	if _threats.is_empty():
		return 0.0
	return expo_s[id] / float(_threats.size())


func deny_value(id: int) -> float:
	if _threats.is_empty():
		return 0.0
	return deny[id] / float(_threats.size())


func claim(g: Gunman, id: int) -> void:
	claims[g] = id


func crowding(id: int, g: Gunman) -> float:
	var p := saloon.node_pos(id)
	var c := 0.0
	for o in claims:
		if o == g or not is_instance_valid(o) or not o.alive:
			continue
		var q := saloon.node_pos(int(claims[o]))
		var d := p.distance_to(q)
		if d < 1.8:
			c += 1.0 - d / 1.8 * 0.5
	return c


func _best(trait_name: String) -> float:
	var b := 0.0
	for g in members:
		if g.alive:
			b = maxf(b, g.p(trait_name))
	return b


func _mean(trait_name: String) -> float:
	var s := 0.0
	var n := 0
	for g in members:
		if g.alive:
			s += g.p(trait_name)
			n += 1
	return s / maxf(n, 1)


func _nearest_member_dist(p: Vector3) -> float:
	var bd := INF
	for g in members:
		if g.alive:
			bd = minf(bd, g.global_position.distance_to(p))
	return bd


func _short(g: Gunman) -> String:
	return g.gm_name if g != null else manager.TEAM_NAMES[team]


func log_event(text: String, important: bool) -> void:
	events.append([now(), text, important])
	if important:
		manager.announce(team, text)


# ---------------------------------------------------------------- per tick

func tick(delta: float) -> void:
	# forget the dead and the stale
	for e in contacts.keys():
		if not is_instance_valid(e) or not e.alive or now() - float(contacts[e]["t"]) > CONTACT_TTL:
			contacts.erase(e)
			continue
		var c: Dictionary = contacts[e]
		if c.get("reloading", false) and now() > float(c.get("reload_end", 0.0)):
			c["reloading"] = false
	_sweep()
	plan_seconds[plan] = float(plan_seconds.get(plan, 0.0)) + delta
	plan_t += delta
	phase_t += delta
	_cmd_t -= delta
	if _cmd_t <= 0.0:
		_cmd_t = 0.5
		_command()


# ---------------------------------------------------------------- tactical map

func _start_sweep() -> void:
	_sweep_i = 0
	_sweep_threats.clear()
	# the most recently confirmed enemies, nearest to us first
	var tc := team_centroid()
	var list: Array = []
	for e in contacts:
		if is_instance_valid(e) and e.alive:
			list.append(contacts[e]["pos"])
	list.sort_custom(func(a, b): return tc.distance_to(a) < tc.distance_to(b))
	for i in mini(list.size(), MAX_THREATS):
		_sweep_threats.append(list[i])
	_nx_s.fill(0.0)
	_nx_c.fill(0.0)
	_nx_d.fill(0.0)


func _sweep() -> void:
	var per := int(ceil(float(_sweep_ids.size()) / SWEEP_TICKS))
	var end := mini(_sweep_i + per, _sweep_ids.size())
	if not _sweep_threats.is_empty():
		for k in range(_sweep_i, end):
			var id := _sweep_ids[k]
			var np := saloon.node_pos(id)
			var tac := _tac_flag[id] == 1
			for tp in _sweep_threats:
				var t_eye := tp + Vector3(0, 1.65, 0)
				if saloon.line_clear(t_eye, np + Vector3(0, 1.45, 0)):
					_nx_s[id] += 1.0
					if tac and saloon.line_clear(t_eye, np + Vector3(0, 0.98, 0)):
						_nx_c[id] += 1.0
				if tac and saloon.line_clear(np + Vector3(0, 1.65, 0), tp + Vector3(0, 1.0, 0)):
					_nx_d[id] += 1.0
	_sweep_i = end
	if _sweep_i >= _sweep_ids.size():
		# publish
		var t := expo_s
		expo_s = _nx_s
		_nx_s = t
		t = expo_c
		expo_c = _nx_c
		_nx_c = t
		t = deny
		deny = _nx_d
		_nx_d = t
		_threats = _sweep_threats.duplicate()
		var n := float(maxi(_threats.size(), 1))
		var a: AStar3D = saloon.team_astar[team]
		for id in _sweep_ids:
			# a stealthy route treats every metre in an enemy's eye as four
			a.set_point_weight_scale(id, 1.0 + 4.0 * expo_s[id] / n)
		_start_sweep()


# ---------------------------------------------------------------- the commander

func order_for(g: Gunman) -> Dictionary:
	if _punish.has(g):
		var pv: Array = _punish[g]
		if now() < float(pv[1]) and is_instance_valid(pv[0]) and (pv[0] as Gunman).alive:
			return {"role": "punish", "focus": pv[0], "push": 1.0, "fire": "free", "move": "sprint"}
		_punish.erase(g)
	var o: Dictionary = orders.get(g, {"role": "free", "push": 0.0, "fire": "free", "move": "run"})
	if _avenge != null and is_instance_valid(_avenge) and _avenge.alive and now() < _avenge_until and g.p("teamwork") > 0.55:
		o = o.duplicate()
		o["focus"] = _avenge
	return o


func alive_members() -> Array[Gunman]:
	var a: Array[Gunman] = []
	for g in members:
		if g.alive:
			a.append(g)
	return a


func _set_plan(p: String, why: String) -> void:
	if p == plan:
		return
	plan = p
	plan_t = 0.0
	groups = [[], []]
	_enter_phase(_first_phase(p))
	log_event("%s: %s%s" % [manager.TEAM_NAMES[team], p, (" - " + why) if why != "" else ""], true)


func _first_phase(p: String) -> String:
	match p:
		"Rush": return "stack"
		"Pincer": return "set"
		"Leapfrog": return "A moves"
		"Bait": return "lure"
	return "hold"


func _enter_phase(ph: String) -> void:
	phase = ph
	phase_t = 0.0


func _command() -> void:
	var own := alive_members()
	if own.is_empty():
		return
	var foes := manager.alive_count(1 - team)
	var adv := own.size() - foes
	var tl := manager.time_left
	# --- pick the plan
	var want := doctrine
	var why := ""
	if doctrine == "Adaptive":
		want = plan if plan != "" else ""
		var reloading := 0
		var tcen := team_centroid()
		for e in contacts:
			if is_instance_valid(e) and e.alive and is_empty_est(e) and tcen.distance_to(contacts[e]["pos"]) < 15.0:
				reloading += 1
		var close := 0
		var tc0 := team_centroid()
		for e in contacts:
			if is_instance_valid(e) and e.alive and e.is_moving() and tc0.distance_to(contacts[e]["pos"]) < 11.0:
				close += 1
		if close >= 3 and adv <= 1 and plan != "Dig In":
			want = "Dig In"
			why = "they're charging - set and let them come"
		elif adv >= 2:
			want = "Rush"
			why = "two men up, press it"
		elif adv <= -2:
			want = "Dig In"
			why = "two men down, make them come"
		elif reloading >= 2 and plan != "Rush":
			want = "Rush"
			why = "counted %d of them empty" % reloading
		elif plan == "" or plan_t > 14.0 and now() - _last_damage_t > 10.0 and now() - manager.last_damage_t > 10.0:
			# opening, or a stalemate: pick by what this crew is good at
			var opts := ["Leapfrog", "Pincer", "High Ground"]
			if plan != "":
				opts.erase(plan)
			var hi := _mean("height")
			var cu := _mean("cunning")
			if hi > 0.6 and opts.has("High Ground"):
				want = "High Ground"
			elif cu > 0.55 and opts.has("Pincer"):
				want = "Pincer"
			else:
				want = opts[rng.randi_range(0, opts.size() - 1)]
			why = "opening" if plan == "" else "stalemate"
		elif plan == "Rush" and adv <= 0 and plan_t > 10.0:
			want = "Leapfrog"
			why = "the rush has stalled"
	# --- the clock: ahead sits on it, level or behind goes all in
	if not manager.sudden_death and tl < 25.0 and tl > 0.0:
		if adv > 0 and want != "Dig In":
			want = "Dig In"
			why = "ahead on the count with %ds left" % int(tl)
		elif adv <= 0 and want != "Rush":
			want = "Rush"
			why = "%s with %ds left" % ["level" if adv == 0 else "behind", int(tl)]
	if want != plan:
		_set_plan(want, why)
	_assign(own)
	_assign_storm(own)
	_assign_punish(own)


func _rank(own: Array[Gunman], f: Callable) -> Array[Gunman]:
	var a := own.duplicate()
	a.sort_custom(func(x, y): return f.call(x) > f.call(y))
	return a


func _order(role: String, zone, push: float, fire: String, move: String) -> Dictionary:
	var o := {"role": role, "push": push, "fire": fire, "move": move}
	if zone != null:
		o["zone"] = zone
	return o


func _balc(x: float) -> Vector3:
	return Vector3(x, Saloon.BALC_Y, -8.0)


func _assign(own: Array[Gunman]) -> void:
	var s := side
	var ec := threat_centroid()
	if plan == "Bait" and phase == "lure" and phase_t < 0.6:
		var rb := _rank(own, func(g): return g.p("nerve") + 0.5 * g.p("aggression"))
		_bait_shots0 = rb[0].stats["shots"]
	match plan:
		"Dig In":
			var hi := _rank(own, func(g): return g.p("height"))
			for g in own:
				orders[g] = _order("hold", Vector3(s * 9.0, 0, 2.0), -0.5, "exposed_only", "run")
			if own.size() >= 3:
				orders[hi[0]] = _order("high", _balc(s * 9.0), -0.3, "exposed_only", "run")
		"Rush":
			if phase == "stack":
				for g in own:
					orders[g] = _order("hold", Vector3(s * 6.0, 0, 1.5), 0.0, "free", "run")
				var ready := 0
				for g in own:
					if g.flat_dist(Vector3(s * 6.0, 0, 1.5)) < 5.0:
						ready += 1
				if phase_t > 4.0 or ready >= own.size() - 1:
					_enter_phase("charge")
					log_event("%s: CHARGE!" % manager.TEAM_NAMES[team], true)
			else:
				# concentration of force: all five onto their floor group, the men upstairs can wait
				var gc := _ground_contacts_centroid()
				for g in own:
					orders[g] = _order("push", gc, 1.0, "free", "sprint")
		"Pincer":
			if groups[0].is_empty():
				var r := _rank(own, func(g): return g.p("height") + g.p("cunning"))
				var nh := 2 if own.size() >= 3 else 1
				groups = [r.slice(0, nh), r.slice(nh)]
			if phase == "set":
				for g in groups[0]:
					orders[g] = _order("high", _balc(-s * 3.0), 0.3, "exposed_only", "run")
				for g in groups[1]:
					orders[g] = _order("pin", Vector3(s * 4.0, 0, 1.0), 0.0, "suppress", "run")
				var over := false
				for g in groups[0]:
					if g.alive and g.level() == 1 and g.global_position.x * -s > -1.0:
						over = true
				if over or phase_t > 22.0:
					_enter_phase("spring")
					log_event("%s: pincer closes" % manager.TEAM_NAMES[team], true)
			else:
				for g in groups[0]:
					orders[g] = _order("overwatch_high", _balc(-s * 6.0), 0.4, "free", "run")
				for g in groups[1]:
					orders[g] = _order("push", ec, 0.8, "free", "run")
		"High Ground":
			if groups[0].is_empty():
				var r := _rank(own, func(g): return g.p("height") + 0.3 * g.p("patience"))
				var nh := mini(3, own.size())
				groups = [r.slice(0, nh), r.slice(nh)]
			for g in groups[0]:
				orders[g] = _order("high", _balc(s * 3.0), 0.15, "free", "run")
			for g in groups[1]:
				orders[g] = _order("guard", Vector3(s * 12.5, 0, 4.0), -0.5, "exposed_only", "run")
		"Leapfrog":
			if groups[0].is_empty():
				var a: Array[Gunman] = []
				var b: Array[Gunman] = []
				for i in own.size():
					(a if i % 2 == 0 else b).append(own[i])
				groups = [a, b]
			var movers: Array = groups[0] if phase == "A moves" else groups[1]
			var cover: Array = groups[1] if phase == "A moves" else groups[0]
			for g in movers:
				orders[g] = _order("bound", null, 0.9, "free", "run")
			for g in cover:
				orders[g] = _order("overwatch", null, -0.3, "suppress", "run")
			var settled := true
			for g in movers:
				if g.alive and g.path_i < g.path.size():
					settled = false
			if phase_t > 7.0 or (settled and phase_t > 3.0):
				_enter_phase("B moves" if phase == "A moves" else "A moves")
		"Bait":
			var r := _rank(own, func(g): return g.p("nerve") + 0.5 * g.p("aggression"))
			var bait: Gunman = r[0]
			for g in own:
				if g != bait:
					orders[g] = _order("ambush", Vector3(s * 8.0, 0, 1.5), -0.6, "exposed_only", "sneak")
			if phase == "lure":
				orders[bait] = _order("bait", Vector3(-s * 1.0, 0, 1.0), 0.9, "free", "run")
				# show yourself, fire once, then run - before they can settle on you
				if phase_t > 6.0 or bait.hp < 90.0 or bait.suppression > 0.3 or bait.stats["shots"] > int(_bait_shots0) and phase_t > 1.0:
					_enter_phase("draw")
			elif phase == "draw":
				orders[bait] = _order("retreat", Vector3(s * 11.0, 0, 4.0), -1.0, "hold_fire", "sprint")
				var near := 0
				for e in contacts:
					if is_instance_valid(e) and e.alive and Vector2(contacts[e]["pos"].x - s * 7.0, contacts[e]["pos"].z - 1.5).length() < 9.0:
						near += 1
				if near > 0:
					_enter_phase("spring")
					log_event("%s: they took the bait" % manager.TEAM_NAMES[team], true)
				elif phase_t > 8.0:
					_enter_phase("lure")
			else:
				for g in own:
					orders[g] = _order("hold", Vector3(s * 6.0, 0, 1.5), 0.3, "free", "run")
				if phase_t > 10.0:
					_enter_phase("lure")
		_:
			for g in own:
				orders[g] = _order("free", null, 0.0, "free", "run")


## Every gang knows a balcony full of guns has to be cleared: when two or more of them have
## held it for a while and none of us is up there, the boldest climber goes up the nearest
## stair after them. A team that is digging in leaves them be.
func _assign_storm(own: Array[Gunman]) -> void:
	var up := 0
	for e in contacts:
		if is_instance_valid(e) and e.alive and float(contacts[e]["pos"].y) > 2.6:
			up += 1
	var ours := 0
	for g in own:
		if g.level() == 1:
			ours += 1
	if up >= 2 and ours == 0 and plan != "Dig In":
		_upstairs_t += 0.5
	else:
		_upstairs_t = 0.0
	if _stormer != null and (not is_instance_valid(_stormer) or not _stormer.alive or up == 0):
		_stormer = null
	if _stormer == null and _upstairs_t > 6.0 and own.size() >= 2:
		var r := _rank(own, func(g): return g.p("aggression") + g.p("cunning") + g.p("height") - (2.0 if _punish.has(g) else 0.0))
		_stormer = r[0]
		log_event("%s: %s goes up the stairs to clear the balcony" % [manager.TEAM_NAMES[team], _stormer.gm_name], true)
	if _stormer != null:
		# up our own stair and along the balcony toward them
		var ex := 0.0
		var n := 0
		for e in contacts:
			if is_instance_valid(e) and e.alive and float(contacts[e]["pos"].y) > 2.6:
				ex += float(contacts[e]["pos"].x)
				n += 1
		var tx := ex / maxf(n, 1)
		orders[_stormer] = _order("high", _balc(tx + side * 3.0), 0.8, "free", "run")


## The payoff for counting: a man the team has counted empty gets rushed by whoever is best
## placed and most willing.
func _assign_punish(own: Array[Gunman]) -> void:
	for e in contacts:
		if not is_instance_valid(e) or not e.alive or not is_empty_est(e):
			continue
		var taken := false
		for g in _punish:
			if _punish[g][0] == e:
				taken = true
		if taken:
			continue
		var cp: Vector3 = contacts[e]["pos"]
		var best: Gunman = null
		var bs := -INF
		for g in own:
			if _punish.has(g) or g.cylinder < 2 or g.reloading:
				continue
			var d := g.flat_dist(cp) + absf(cp.y - g.global_position.y) * 4.0
			if d > 15.0:
				continue
			var c: Dictionary = contacts[e]
			var window := float(c.get("reload_end", 0.0)) - now() if c.get("reloading", false) else 1.5
			if d / Gunman.SPRINT > window + 1.0:
				continue   # he'll be loaded before we get there
			var sc := g.p("aggression") + g.p("brawl") + 0.5 * g.p("discipline") - d / 10.0
			if sc > bs:
				bs = sc
				best = g
		if best != null and rng.randf() < 0.3 + 0.6 * _mean("discipline"):
			_punish[best] = [e, now() + 3.5]
			log_event("%s counted %s empty - %s goes for him" % [manager.TEAM_NAMES[team], e.gm_name, best.gm_name], true)


func member_died(g: Gunman, killer: Gunman) -> void:
	_last_damage_t = now()
	claims.erase(g)
	_punish.erase(g)
	if killer != null and killer.team != team:
		_avenge = killer
		_avenge_until = now() + 6.0
	# a man going down next to you rattles you
	for m in members:
		if m.alive and m.global_position.distance_to(g.global_position) < 6.0:
			m.suppression = minf(1.5, m.suppression + 0.35 * (1.0 - m.p("nerve")))
	for k in groups.size():
		groups[k].erase(g)
