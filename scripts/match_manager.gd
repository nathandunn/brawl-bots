class_name MatchManager
extends Node
## Spawns the two gangs, runs the two-minute clock and the team brains, resolves every bullet,
## keeps the stats and decides the winner.
##
## Winning: last team standing. At 2:00, the side with more men standing wins on decision; if
## the count is level it goes to sudden death - the next man down loses it for his side. If
## nobody falls in 45 s of sudden death, remaining health decides; dead level is a draw.

signal match_started(match_index: int)
signal match_ended(result: Dictionary)
signal celebration_finished(match_index: int)
signal announced(text: String, team: int)

const TEAM_SIZE := 5        # the default
const MAX_TEAM := 12
const MATCH_TIME := 120.0
const SUDDEN_DEATH_CAP := 45.0
const STANDOFF := 3.0      # the piano stops; nobody draws until the bottle breaks
const TEAM_NAMES := ["Outlaws", "Law"]           # (defaults; the live names are team_names)
const TEAM_WINS := ["The Outlaws win", "The Law wins"]
const TEAM_COLORS := [Color(0.72, 0.2, 0.16), Color(0.3, 0.42, 0.62)]
## A throwing star where it lands: it rarely kills outright, but it always bleeds.
const STAR_DMG := {"head": 999.0, "heart": 999.0, "gut": 18.0, "arm_r": 8.0, "arm_l": 8.0, "leg_l": 8.0, "leg_r": 8.0}
const STAR_SPEED := 24.0
const BOTTLE_SPEED := 13.0
const STANDOFF_LINES := {"saloon": "The piano stops. Nobody draws for %d seconds...", "dojo": "The fighters bow. %d breaths...",
	"bamboo": "The wind drops in the bamboo. %d seconds...", "temple": "The temple bell sounds. %d seconds..."}
## Where a slug lands decides everything. Head or heart: dead. Gut: badly hurt and bleeding.
## Arm or leg: not much blood, but he can't shoot, punch or walk right after (see Gunman).
const DMG := {"head": 999.0, "heart": 999.0, "gut": 38.0, "arm_r": 12.0, "arm_l": 12.0, "leg_l": 12.0, "leg_r": 12.0}
const PART_NAMES := {"head": "head", "heart": "heart", "gut": "gut", "arm_r": "gun arm", "arm_l": "left arm", "leg_l": "left leg", "leg_r": "right leg"}

var world: Node3D
var saloon: Saloon
var sfx: Sfx = null
var blood: Blood = null
var _corpses: Array = []    # [position, blood left to give]
var headless := false
var doctrines: Array[String] = ["Adaptive", "Adaptive"]
var team_presets: Array[String] = ["Balanced", "Balanced"]     # character (kind) for the whole side
var factions: Array[String] = ["outlaws", "law"]
var team_sizes: Array[int] = [TEAM_SIZE, TEAM_SIZE]
var team_grades: Array[String] = ["Regular", "Regular"]
var player_preset := [[], []]    # per man: "" = follow the team
var player_grade := [[], []]
var team_weapons: Array[String] = ["", ""]   # "" = the character's usual kit
var player_weapon := [[], []]
var scripts: Array = [null, null]          # AiScript per side (null = built-in brain only)
var script_text: Array[String] = ["", ""]
var team_names: Array[String] = ["Outlaws", "Law"]
var team_colors: Array[Color] = [TEAM_COLORS[0], TEAM_COLORS[1]]
var team_wins: Array[String] = ["The Outlaws win", "The Law wins"]
var _pending: Array = []      # [due time, callable] - stars in flight
var custom := [null, null]       # Personality edited with the sliders, used when preset is "Custom"
var gunmen: Array[Gunman] = []
var brains: Array[TeamBrain] = []
var running := false
var match_index := 0
var elapsed := 0.0
var time_left := MATCH_TIME
var sudden_death := false
var sudden_t := 0.0
var last_damage_t := 0.0
var dance_clock := 0.0
var rng := RandomNumberGenerator.new()
var show_intents := false
var result := {}
var _alive_cache: Array[Gunman] = []
var _cache_frame := -1
var _celeb_t := -1.0
var _fx: Array = []      # [node, ttl]
var _tracer_mat: StandardMaterial3D
var _dust_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _blood_mat: StandardMaterial3D = null
var _star_mat: StandardMaterial3D = null
var first_blood := -1.0


func can_fire() -> bool:
	return elapsed >= STANDOFF


func _ready() -> void:
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.92, 0.6, 0.85)
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_mat = StandardMaterial3D.new()
	_dust_mat.albedo_color = Color(0.75, 0.65, 0.5, 0.7)
	_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.6, 0.85, 0.7, 0.8)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _init() -> void:
	for t in 2:
		for i in MAX_TEAM:
			player_preset[t].append("")
			player_grade[t].append("")
			player_weapon[t].append("")


## Names and colours from the factions; the same faction on both sides gets told apart.
func refresh_identity() -> void:
	for t in 2:
		var f: Dictionary = Roster.FACTIONS[factions[t]]
		team_names[t] = String(f["name"])
		team_colors[t] = f["color"]
		team_wins[t] = String(f["wins"])
	if factions[0] == factions[1]:
		team_names[1] += " II"
		team_wins[1] = team_wins[1].replace(String(Roster.FACTIONS[factions[1]]["name"]), team_names[1])
		team_colors[1] = team_colors[1].lightened(0.45)


## Set a side's faction; its characters reset to that faction's default if they don't fit.
func set_faction(t: int, f: String) -> void:
	factions[t] = f
	var ks: Array = Roster.kinds_for(f)
	if not ks.has(team_presets[t]) and team_presets[t] != "Custom" and team_presets[t] != "Random":
		team_presets[t] = Roster.default_kind(f)
	for i in MAX_TEAM:
		if player_preset[t][i] != "" and not ks.has(player_preset[t][i]):
			player_preset[t][i] = ""
	refresh_identity()


func personality_for(t: int, i: int) -> Array:
	var name: String = String(player_preset[t][i])
	if name == "":
		name = team_presets[t]
	if name == "Custom" and custom[t] != null:
		return [name, (custom[t] as Personality).jittered(rng, 0.03)]
	return [name, Personality.preset(name, rng).jittered(rng, 0.05)]


func start_match(seed_value: int = -1) -> void:
	clear()
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	match_index += 1
	elapsed = 0.0
	time_left = MATCH_TIME
	sudden_death = false
	sudden_t = 0.0
	last_damage_t = 0.0
	first_blood = -1.0
	result = {}
	_celeb_t = -1.0
	saloon.reset_props()
	_corpses.clear()
	if blood != null:
		blood.clear()
	brains.clear()
	for t in 2:
		var b := TeamBrain.new()
		b.rng.seed = rng.randi()
		b.setup(t, self, saloon, doctrines[t])
		brains.append(b)
	refresh_identity()
	for t in 2:
		var n: int = clampi(team_sizes[t], 1, MAX_TEAM)
		var slots: Array = []
		for k in n:
			slots.append(k)
		for k in range(n - 1, 0, -1):
			var j := rng.randi_range(0, k)
			var tmp = slots[k]
			slots[k] = slots[j]
			slots[j] = tmp
		for i in n:
			var g := Gunman.new()
			g.team = t
			g.idx = i
			g.gm_name = "%s%d" % [String(Roster.FACTIONS[factions[t]]["letter"]) + ("" if t == 0 or factions[0] != factions[1] else "'"), i + 1]
			var pp := personality_for(t, i)
			g.preset_name = pp[0]
			g.personality = pp[1]
			if scripts[t] != null:
				for k in (scripts[t] as AiScript).trait_set:
					g.personality.t[k] = float((scripts[t] as AiScript).trait_set[k])
			g.faction = factions[t]
			g.family = Roster.family(factions[t])
			g.kind = pp[0] if Roster.kinds_for(factions[t]).has(pp[0]) else Roster.default_kind(factions[t])
			g.grade = String(player_grade[t][i]) if String(player_grade[t][i]) != "" else team_grades[t]
			var ab := Roster.abilities(g.grade, g.kind)
			g.ab_speed = ab["speed"]
			g.ab_jump = ab["jump"]
			g.ab_smarts = ab["smarts"]
			g.ab_aim = float(ab.get("aim", 1.0))
			g.personality.t["nerve"] = clampf(g.personality.g("nerve") + float(ab.get("nerve", 0.0)), 0.0, 1.0)
			var lo := Roster.loadout(g.kind, factions[t])
			g.gun = String(lo["gun"])
			g.melee = String(lo["melee"])
			g.loadout_stars = int(lo["stars"])
			g.stealth = bool(lo.get("stealth", false))
			var wch := String(player_weapon[t][i]) if String(player_weapon[t][i]) != "" else team_weapons[t]
			if Roster.GUNS.has(wch) or wch == "lasso":
				g.gun = "colt" if wch == "lasso" else wch
				g.loadout_stars = 0
				g.has_lasso = wch == "lasso"
			elif wch == "knife" or wch == "bottle":
				g.gun = ""
				g.loadout_stars = 0
				g.carry_kind = wch
			g.script_rules = scripts[t]
			g.manager = self
			g.saloon = saloon
			g.brain = brains[t]
			g.team_color = team_colors[t]
			g.rng.seed = rng.randi()
			g.voice_id = (i + t) % 3
			g.voice_pitch = rng.randf_range(0.9, 1.1)
			g.show_intent = show_intents
			var sp := saloon.spawn_point(t, slots[i])
			g.position = sp + Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
			g.rotation.y = -PI * 0.5 if t == 0 else PI * 0.5
			g.died.connect(_on_died)
			world.add_child(g)
			gunmen.append(g)
			brains[t].members.append(g)
	running = true
	_pending.clear()
	announce(-1, String(STANDOFF_LINES.get(saloon.map_id, STANDOFF_LINES["saloon"])) % int(STANDOFF))
	match_started.emit(match_index)


func clear() -> void:
	running = false
	for g in gunmen:
		g.cleanup()
		g.queue_free()
	gunmen.clear()
	for f in _fx:
		if is_instance_valid(f[0]):
			f[0].queue_free()
	_fx.clear()
	_cache_frame = -1


func alive_gunmen() -> Array[Gunman]:
	var f := Engine.get_physics_frames()
	if f != _cache_frame:
		_cache_frame = f
		_alive_cache = []
		for g in gunmen:
			if g.alive:
				_alive_cache.append(g)
	return _alive_cache


func alive_count(team: int) -> int:
	var n := 0
	for g in gunmen:
		if g.alive and g.team == team:
			n += 1
	return n


func team_hp(team: int) -> float:
	var s := 0.0
	for g in gunmen:
		if g.alive and g.team == team:
			s += g.hp
	return s


func set_show_intents(on: bool) -> void:
	show_intents = on
	for g in gunmen:
		g.show_intent = on
		g._update_label()


var stall_watch := false
var _lull_printed := false


## Seconds since anybody in the room was hurt by anything - the lull clock.
func quiet_time() -> float:
	return elapsed - maxf(last_damage_t, _last_hurt_any(alive_gunmen()))


func _last_hurt_any(men: Array) -> float:
	var t := 0.0
	for g in men:
		t = maxf(t, g.last_hurt_t)
	return t
var _stall := {}
var _stall_tick := 0.0


## Debug (--dumpmen): two enemies within 3 m for 5 s with nobody hurt is a stall - print both.
func _watch_stalls(delta: float) -> void:
	_stall_tick += delta
	if _stall_tick < 0.5 or not running:
		return
	_stall_tick = 0.0
	var men := alive_gunmen()
	var quiet := elapsed - maxf(last_damage_t, _last_hurt_any(men))
	if quiet > 12.0 and alive_count(0) > 0 and alive_count(1) > 0 and not _lull_printed:
		_lull_printed = true
		print("LULL t=%.1f quiet=%.1f" % [elapsed, quiet])
		for g in men:
			var ne: Gunman = null
			var nd := 99.0
			for e in men:
				if e.team != g.team and g.flat_dist(e.global_position) < nd:
					nd = g.flat_dist(e.global_position)
					ne = e
			print("   %s pos=%s st=%s mode=%s lock=%.1f hp=%d ammo=%d jam=%s rel=%s see=%d near=%.1f path=%d/%d goal=%d bottle=%s legs=%d arms=%d knocked=%.1f" % [g.gm_name, g.global_position, g.stance, g.mode, g.stance_lock, int(g.hp), g.total_ammo(), g.jammed, g.reloading, g.visible_enemies.size(), nd, g.path_i, g.path.size(), g.goal_id, g.has_bottle, g.legs_hit(), g.arms_hit(), g.knocked_t])
	elif quiet < 1.0:
		_lull_printed = false
	for a in men:
		for b in men:
			if a.team != 0 or b.team != 1:
				continue
			var key := "%s|%s" % [a.gm_name, b.gm_name]
			var d := Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()
			if d > 3.0 or absf(a.global_position.y - b.global_position.y) > 1.2 or elapsed - a.last_hurt_t < 1.0 or elapsed - b.last_hurt_t < 1.0:
				_stall.erase(key)
				continue
			_stall[key] = float(_stall.get(key, 0.0)) + 0.5
			if absf(float(_stall[key]) - 5.0) < 0.01:
				print("STALL t=%.1f d=%.2f clear=%s" % [elapsed, d, saloon.line_clear(a.global_position + Vector3(0, 0.45, 0), b.global_position + Vector3(0, 0.45, 0))])
				for g in [a, b]:
					print("   %s pos=%s st=%s mode=%s lock=%.1f knocked=%.1f pcd=%.2f wind=%.2f stag=%.2f face=%s canp=%s arms=%d legs=%d wr=%.1f grab=%.1f throw=%.1f bottle=%s path=%d/%d trav=%.1f fall=%s ammo=%d jam=%s rel=%s melee=%s reach=%.2f" % [g.gm_name, g.global_position, g.stance, g.mode, g.stance_lock, g.knocked_t, g.punch_cd, g.punch_wind, g.stagger_t, g.facing((b if g == a else a).global_position, 0.0), g.can_punch(), g.arms_hit(), g.legs_hit(), g.wrestle_t, g.grab_t, g.throw_wind, g.has_bottle, g.path_i, g.path.size(), g.trav_t, g.falling, g.total_ammo(), g.jammed, g.reloading, g.melee, g.reach()])


func _physics_process(delta: float) -> void:
	if stall_watch:
		_watch_stalls(delta)
	dance_clock += delta
	_tick_fx(delta)
	for i in range(_pending.size() - 1, -1, -1):
		if elapsed >= float(_pending[i][0]):
			var c: Callable = _pending[i][1]
			_pending.remove_at(i)
			c.call()
	# the dead go on bleeding into the boards for a while
	for c in _corpses:
		if c[1] > 0.0:
			var a := minf(c[1], 2.5 * delta)
			c[1] -= a
			if blood != null:
				blood.pool(c[0], a)
	if _celeb_t >= 0.0:
		_celeb_t += delta
		if _celeb_t > 6.0:
			_celeb_t = -1.0
			celebration_finished.emit(match_index)
	if not running:
		return
	var before := elapsed
	elapsed += delta
	if before < STANDOFF and elapsed >= STANDOFF:
		announce(-1, "DRAW!" if Roster.family(factions[0]) == "west" or Roster.family(factions[1]) == "west" else "HAJIME!")
		if sfx != null:
			sfx.voice("draw", 0, Vector3(0, 2.0, 0))
		sound("smash", Vector3(0, 1.4, 7.6))
	if sudden_death:
		sudden_t += delta
		if sudden_t > SUDDEN_DEATH_CAP:
			var h0 := team_hp(0)
			var h1 := team_hp(1)
			if absf(h0 - h1) < 0.5:
				_end(-1, "draw")
			else:
				_end(0 if h0 > h1 else 1, "health after sudden death")
			return
	else:
		time_left = MATCH_TIME - elapsed
		if time_left <= 0.0:
			time_left = 0.0
			var a := alive_count(0)
			var b := alive_count(1)
			if a != b:
				_end(0 if a > b else 1, "decision %d-%d at 2:00" % [a, b])
				return
			sudden_death = true
			announce(-1, "2:00 - level at %d a side. SUDDEN DEATH: next man down loses it" % a)
	for b in brains:
		b.tick(delta)


func _on_died(g: Gunman, killer: Gunman, how: String) -> void:
	last_damage_t = elapsed
	if how != "fists" and how != "blunt":
		_corpses.append([g.global_position, 14.0])
	if first_blood < 0.0:
		first_blood = elapsed
	brains[g.team].member_died(g, killer)
	var by := (" by %s" % killer.gm_name) if killer != null else ""
	if killer != null and killer.team == g.team:
		by = " by his own side (%s)" % killer.gm_name
	announce(g.team, "%s down%s (%s)" % [g.gm_name, by, how])
	if not running:
		return
	if sudden_death:
		_end(1 - g.team, "sudden death")
		return
	for t in 2:
		if alive_count(t) == 0:
			_end(1 - t if alive_count(1 - t) > 0 else -1, "last man standing" if alive_count(1 - t) == 1 else "wiped them out")
			return


func announce(team: int, text: String) -> void:
	announced.emit(text, team)


func sound(cue: String, at: Vector3, pitch := 1.0, vol := 0.0) -> void:
	if sfx != null:
		sfx.play(cue, at, pitch, vol)


# ---------------------------------------------------------------- bullets

## Fire one round from `shooter` at `aim` with angular spread `sigma`. The slug flies on a
## perturbed straight line until it meets wood, a wall, or a man (any man - friends included).
## Men it passes close to are suppressed. Everyone in the room hears it.
## One pull of a shotgun: one bang, eight pellets in a cone. Each pellet is a small slug: head
## or heart kills within 8 m, further out it only hurts; most body pellets don't make a wound.
func fire_shotgun(shooter: Gunman, aim: Vector3, sigma: float) -> Dictionary:
	shooter.stats["shots"] += 1
	sound("shot", shooter.muzzle(), rng.randf_range(0.62, 0.72), 3.0)
	brains[1 - shooter.team].enemy_fired(shooter)
	var first: Gunman = null
	var hit_any := false
	for k in 8:
		var r := fire_bullet(shooter, aim, sigma * 0.5 + 0.055, 1.0, true)
		var v = r.get("hit")
		if v != null and first == null:
			first = v
		if v != null and (v as Gunman).team != shooter.team:
			hit_any = true
	if hit_any:
		shooter.stats["hits"] += 1
	return {"hit": first}


func fire_bullet(shooter: Gunman, aim: Vector3, sigma: float, dmg_mult := 1.0, pellet := false) -> Dictionary:
	var from := shooter.muzzle()
	var dir := (aim - from).normalized()
	var right := dir.cross(Vector3.UP)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	dir = (dir + right * rng.randfn(0.0, sigma) + up * rng.randfn(0.0, sigma)).normalized()
	var end := from + dir * 45.0
	var hit := saloon.bullet_ray(from, end, rng)
	var stop: Vector3 = hit.get("position", end)
	var seg_len := from.distance_to(stop)
	if not pellet:
		shooter.stats["shots"] += 1
		sound("shot", from, rng.randf_range(0.92, 1.08) if dmg_mult <= 1.0 else rng.randf_range(0.78, 0.86), 2.0 if dmg_mult > 1.0 else 0.0)
		brains[1 - shooter.team].enemy_fired(shooter)
	# first man along the line
	var victim: Gunman = null
	var best_t := seg_len
	var hit_y := 0.0
	for g in alive_gunmen():
		if g == shooter:
			continue
		var r := _ray_capsule(from, dir, seg_len, g)
		if r.x >= 0.0 and r.x < best_t:
			best_t = r.x
			victim = g
			hit_y = r.y
	var res := {"hit": victim}
	if victim != null:
		stop = from + dir * best_t
		var part := hit_part(victim, stop, hit_y)
		var dmg: float = DMG[part] * rng.randf_range(0.85, 1.15) * (dmg_mult if part != "head" and part != "heart" else 1.0)
		if pellet:
			var far := best_t > 8.0
			if part == "head" or part == "heart":
				dmg = 30.0 if far else 999.0
			else:
				dmg = 13.0 if part == "gut" else 7.0
				if rng.randf() < 0.55:
					part = "pellet"   # a graze: it hurts, it doesn't open a wound
		if victim.team != shooter.team and not pellet:
			shooter.stats["hits"] += 1
			if part == "head" or part == "heart":
				shooter.stats["heads"] += 1
			if victim.crouched:
				shooter.stats["deny_hits"] += 1
			if shooter.level() == 1 and victim.level() != 1:
				shooter.stats["high_hits"] += 1
		last_damage_t = elapsed
		victim.take_damage(dmg, "gun", shooter, part, dir)
		res["part"] = part
	elif not hit.is_empty():
		var col = hit.get("collider")
		if saloon.bottle_hit(stop) != null:
			sound("smash", stop)
			_glass(stop)
		elif col is StaticBody3D and (col as Node).get_parent() is Table:
			sound("wood", stop)
		elif rng.randf() < 0.45:
			sound("ricochet", stop, rng.randf_range(0.8, 1.25), -2.0)
		else:
			sound("wood", stop, 0.8, -6.0)
		_dust(stop)
	# near misses rattle whoever the slug passed
	for g in alive_gunmen():
		if g == shooter or g == victim:
			continue
		var d := _seg_dist_to_body(from, stop, g)
		if d < 1.6:
			g.suppress(0.35 * (1.0 - d / 1.6), shooter)
			if d < 0.9:
				sound("whiz", g.global_position + Vector3(0, 1.6, 0), rng.randf_range(0.85, 1.2), -6.0)
	_tracer(from, stop)
	return res


## A throwing star: silent (nobody can count them), slower than a slug, stopped by most of
## what stops a slug and by a paper screen half the time, and turned aside by a blade or staff
## held up to meet it. Resolved along its line at the throw; lands when it gets there.
func throw_star(thrower: Gunman, aim: Vector3, sigma: float) -> Dictionary:
	var from := thrower.muzzle()
	var dir := (aim - from).normalized()
	var right := dir.cross(Vector3.UP)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	sigma *= 1.6
	dir = (dir + right * rng.randfn(0.0, sigma) + up * rng.randfn(0.0, sigma) + Vector3(0, -0.01, 0)).normalized()
	var end := from + dir * 20.0
	var hit := saloon.bullet_ray(from, end, rng, 0.5)
	var stop: Vector3 = hit.get("position", end)
	var seg_len := from.distance_to(stop)
	thrower.stats["shots"] += 1
	thrower.stats["stars"] += 1
	sound("swing", from, 1.6, -8.0)
	var victim: Gunman = null
	var best_t := seg_len
	var hit_y := 0.0
	for g in alive_gunmen():
		if g == thrower:
			continue
		var r := _ray_capsule(from, dir, seg_len, g)
		if r.x >= 0.0 and r.x < best_t:
			best_t = r.x
			victim = g
			hit_y = r.y
	if victim != null:
		stop = from + dir * best_t
	var flight := from.distance_to(stop) / STAR_SPEED
	_star_visual(from, stop, flight)
	var res := {"hit": victim}
	var v := victim
	var at := stop
	var hy := hit_y
	_pending.append([elapsed + flight, func():
		if v != null and is_instance_valid(v) and v.alive:
			# held up to meet it: a blade or staff turns a star he's watching
			var bl := float(v.weapon()["block"]) * 0.7 * (0.5 + 0.5 * v.ab_smarts)
			if v.facing(from, 0.5) and v.punch_wind < 0.0 and v.knocked_t <= 0.0 and rng.randf() < bl:
				v.stats["blocks"] += 1
				sound("clang", at, 1.4, -4.0)
				return
			var part := hit_part(v, at, hy)
			if v.team != thrower.team and is_instance_valid(thrower):
				thrower.stats["hits"] += 1
				thrower.stats["star_hits"] += 1
				if part == "head" or part == "heart":
					thrower.stats["heads"] += 1
			last_damage_t = elapsed
			sound("wood", at, 1.3, -4.0)
			v.take_damage(float(STAR_DMG[part]) * rng.randf_range(0.85, 1.15), "star", thrower if is_instance_valid(thrower) else null, part, dir)
		else:
			sound("wood", at, 1.5, -8.0)
	])
	# a star whispering past still makes a man flinch, though nobody hears where it came from
	for g in alive_gunmen():
		if g == thrower or g == victim:
			continue
		var d := _seg_dist_to_body(from, stop, g)
		if d < 0.8:
			g.suppression = minf(1.5, g.suppression + 0.15)
			sound("whiz", g.global_position + Vector3(0, 1.6, 0), 1.6, -8.0)
	return res


## A bottle thrown at a man's head: slow enough to see coming, it rings a skull (a knockdown)
## and bruises anything else - and it smashes whatever it hits, including the bottles on the
## shelf.
func throw_bottle(thrower: Gunman, aim: Vector3, sigma: float, kind := "bottle") -> Dictionary:
	var chair := kind == "chair"
	var knife := kind == "knife"
	var from := thrower.muzzle() + Vector3(0, 0.2, 0)
	var dir := (aim - from).normalized()
	var right := dir.cross(Vector3.UP)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	dir = (dir + right * rng.randfn(0.0, sigma) + up * rng.randfn(0.0, sigma)).normalized()
	var end := from + dir * 16.0
	var hit := saloon.bullet_ray(from, end, rng, 1.0)
	var stop: Vector3 = hit.get("position", end)
	var seg_len := from.distance_to(stop)
	sound("swing", from, 0.7, -6.0)
	var victim: Gunman = null
	var best_t := seg_len
	var hit_y := 0.0
	for g in alive_gunmen():
		if g == thrower or g.falling:
			continue
		var r := _ray_capsule(from, dir, seg_len, g)
		if r.x >= 0.0 and r.x < best_t:
			best_t = r.x
			victim = g
			hit_y = r.y
	if victim != null:
		stop = from + dir * best_t
	var flight := from.distance_to(stop) / (9.0 if chair else (17.0 if knife else BOTTLE_SPEED))
	_bottle_visual(from, stop, flight, chair, knife)
	var v := victim
	var at := stop
	var hy := hit_y
	_pending.append([elapsed + flight, func():
		if knife:
			sound("wood", at, 1.5, -6.0)
		elif chair:
			sound("wood", at, 0.7, 3.0)
			_dust(at)
		else:
			sound("smash", at)
			_glass(at)
		saloon.bottle_hit(at)
		if v == null or not is_instance_valid(v) or not v.alive or v.falling:
			return
		# a blade or a staff can bat it away; a man who sees it coming may duck it
		var bl := float(v.weapon()["block"]) * 0.6 * (0.5 + 0.5 * v.ab_smarts)
		if v.facing(at, 0.5) and v.knocked_t <= 0.0 and rng.randf() < bl + 0.12 * v.ab_jump:
			v.stats["blocks"] += 1
			return
		var part := hit_part(v, at, hy)
		if v.team != thrower.team and is_instance_valid(thrower):
			thrower.stats["hits"] += 1
			thrower.stats["bottle_hits"] += 1
		last_damage_t = elapsed
		var by: Gunman = thrower if is_instance_valid(thrower) else null
		var how := "chair" if chair else "bottle"
		if knife:
			# the point goes in: head and heart kill, anything else cuts and bleeds
			if part == "head" or part == "heart":
				if is_instance_valid(thrower):
					thrower.stats["heads"] += 1
			v.take_damage({"head": 999.0, "heart": 999.0, "gut": 26.0}.get(part, 10.0) * rng.randf_range(0.85, 1.15), "knife", by, part, dir)
			if v.alive and not wounds_has(part):
				v.bleed += 0.6
				v.bleed_by = by
			return
		if part == "head":
			v.take_damage((22.0 if chair else 16.0) * rng.randf_range(0.85, 1.15), how, by, "head_blunt", dir)
			if v.alive and v.knocked_t <= 0.0 and not v.falling:
				v.knock_down(1.8 if chair else 1.6)
		else:
			v.take_damage((12.0 if chair else 7.0) * rng.randf_range(0.85, 1.15), how, by, "bruise", dir)
			if chair and v.alive and not v.falling and v.knocked_t <= 0.0 and rng.randf() < 0.55:
				v.knock_down(1.3)
			elif v.alive:
				v.stagger_t = maxf(v.stagger_t, 0.45)
				v.suppression = minf(1.5, v.suppression + 0.4)
	])
	thrower.stats["shots"] += 1
	return {"hit": victim}


## Victory: a bottle flung up into the air, turning over, smashing where it comes down.
func toss_bottle(from: Vector3, r: RandomNumberGenerator) -> void:
	if headless or saloon == null:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.055
	cm.height = 0.3
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = saloon.mat("glass_g" if r.randf() < 0.5 else "glass_b")
	mi.position = from
	world.add_child(mi)
	var land := Vector3(from.x + r.randf_range(-1.6, 1.6), 0.05, from.z + r.randf_range(-1.6, 1.6))
	var peak := r.randf_range(2.0, 3.2)
	var tt := 1.0 + peak * 0.12
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(u: float):
		if is_instance_valid(mi):
			var p := from.lerp(land, u)
			p.y = lerpf(from.y, land.y, u) + 4.0 * u * (1.0 - u) * peak
			mi.position = p, 0.0, 1.0, tt)
	tw.tween_property(mi, "rotation:x", 14.0, tt)
	tw.chain().tween_callback(func():
		if is_instance_valid(mi):
			mi.visible = false
		sound("smash", land, r.randf_range(0.9, 1.15), -3.0)
		_glass(land))
	_fx.append([mi, tt + 1.0])


static func wounds_has(part: String) -> bool:
	return part in ["gut", "arm_r", "arm_l", "leg_l", "leg_r"]


func glass(at: Vector3) -> void:
	_glass(at)


func _bottle_visual(a: Vector3, b: Vector3, t: float, chair := false, knife := false) -> void:
	if headless:
		return
	var mi: Node3D
	if knife:
		mi = Saloon.knife_mesh(saloon.mat("dark"))
	elif chair:
		mi = Saloon.chair_mesh(saloon.mat("wood"), saloon.mat("dark"))
	else:
		var bmi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.055
		cm.height = 0.3
		cm.radial_segments = 8
		bmi.mesh = cm
		bmi.material_override = saloon.mat("glass_g")
		mi = bmi
	mi.position = a
	world.add_child(mi)
	var tt := maxf(t, 0.05)
	var lift := clampf(a.distance_to(b) * 0.06, 0.1, 0.7)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(u: float): if is_instance_valid(mi): mi.position = a.lerp(b, u) + Vector3(0, 4.0 * u * (1.0 - u) * lift, 0), 0.0, 1.0, tt)
	tw.tween_property(mi, "rotation:x", 18.0 * tt, tt)
	tw.chain().tween_callback(func(): if is_instance_valid(mi): mi.visible = false)
	_fx.append([mi, t + 1.5])


func _star_visual(a: Vector3, b: Vector3, t: float) -> void:
	if headless:
		return
	var mi := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 4:
		var ang := TAU * k / 4.0
		var tip := Vector3(cos(ang), 0, sin(ang)) * 0.09
		var l := Vector3(cos(ang + 0.6), 0, sin(ang + 0.6)) * 0.03
		var r := Vector3(cos(ang - 0.6), 0, sin(ang - 0.6)) * 0.03
		for v in [Vector3.ZERO, r, tip, Vector3.ZERO, tip, l]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	mi.mesh = st.commit()
	if _star_mat == null:
		_star_mat = StandardMaterial3D.new()
		_star_mat.albedo_color = Color(0.85, 0.87, 0.92)
		_star_mat.emission_enabled = true
		_star_mat.emission = Color(0.5, 0.5, 0.55)
		_star_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = _star_mat
	mi.position = a
	world.add_child(mi)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "position", b, maxf(t, 0.05))
	tw.tween_property(mi, "rotation:y", 40.0 * t, maxf(t, 0.05))
	_fx.append([mi, t + 1.5])


## Earliest distance along the ray at which it enters the man's capsule, and the height of
## the hit; x < 0 for a miss.
## Which part of the man a slug at `at` (height `hit_y`) struck. His own right is +x in his
## frame. The heart is a hand's width either side of the breastbone, upper chest.
func hit_part(v: Gunman, at: Vector3, hit_y: float) -> String:
	var rel := (hit_y - v.global_position.y) / v.height()
	var lx := (at - v.global_position).dot(v.global_transform.basis.x.normalized())
	if rel > 0.86 and absf(lx) < 0.14:
		return "head"
	if rel > 0.86:
		return "arm_r" if lx > 0.0 else "arm_l"   # a graze off the shoulder
	if rel > 0.45:
		if absf(lx) > 0.15:
			return "arm_r" if lx > 0.0 else "arm_l"
		if rel > 0.63 and rel < 0.78 and absf(lx) < 0.07:
			return "heart"
		return "gut"
	return "leg_r" if lx > 0.0 else "leg_l"


func _ray_capsule(o: Vector3, d: Vector3, max_t: float, g: Gunman) -> Vector2:
	var r := Gunman.BODY_R
	var base := g.global_position
	var a := base + Vector3(0, r, 0)
	var b := base + Vector3(0, g.height() - r, 0)
	var res := _closest_seg_seg(o, o + d * max_t, a, b)
	if res.x > r:
		return Vector2(-1, 0)
	var t: float = res.y * max_t
	# back off to the surface
	t = maxf(0.0, t - sqrt(maxf(r * r - res.x * res.x, 0.0)))
	return Vector2(t, a.lerp(b, res.z).y)


func _seg_dist_to_body(p0: Vector3, p1: Vector3, g: Gunman) -> float:
	var base := g.global_position
	return _closest_seg_seg(p0, p1, base + Vector3(0, 0.3, 0), base + Vector3(0, g.height() - 0.2, 0)).x


## Closest approach of segments p0-p1 and q0-q1: (distance, s on first, t on second).
func _closest_seg_seg(p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3) -> Vector3:
	var d1 := p1 - p0
	var d2 := q1 - q0
	var r := p0 - q0
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-6 and e <= 1e-6:
		return Vector3(r.length(), 0, 0)
	if a <= 1e-6:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-6:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var bb := d1.dot(d2)
			var denom := a * e - bb * bb
			s = clampf((bb * f - c * e) / denom, 0.0, 1.0) if denom > 1e-6 else 0.0
			t = (bb * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((bb - c) / a, 0.0, 1.0)
	var c1 := p0 + d1 * s
	var c2 := q0 + d2 * t
	return Vector3(c1.distance_to(c2), s, t)


# ---------------------------------------------------------------- effects

## A puff of red where a slug goes in.
func spray(at: Vector3, dir: Vector3) -> void:
	if headless:
		return
	if _blood_mat == null:
		_blood_mat = StandardMaterial3D.new()
		_blood_mat.albedo_color = Color(0.55, 0.02, 0.02)
	for i in 7:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * rng.randf_range(0.03, 0.06)
		mi.mesh = bm
		mi.material_override = _blood_mat
		mi.position = at
		world.add_child(mi)
		var to := at + dir.normalized() * rng.randf_range(0.3, 0.9) + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.3), rng.randf_range(-0.3, 0.3))
		var floor_y := 3.25 if at.y > 3.4 else 0.0
		var tw := mi.create_tween()
		tw.tween_property(mi, "position", to, 0.12)
		tw.tween_property(mi, "position", Vector3(to.x, floor_y + 0.01, to.z), 0.25).set_ease(Tween.EASE_IN)
		_fx.append([mi, 0.6])


func _tracer(a: Vector3, b: Vector3) -> void:
	if headless:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _tracer_mat)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	world.add_child(mi)
	_fx.append([mi, 0.07])


func _dust(at: Vector3) -> void:
	if headless:
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 6
	sm.rings = 3
	mi.mesh = sm
	mi.material_override = _dust_mat
	mi.position = at
	world.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 2.5, 0.4)
	_fx.append([mi, 0.4])


func _glass(at: Vector3) -> void:
	if headless:
		return
	for i in 6:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.04, 0.02)
		mi.mesh = bm
		mi.material_override = _glass_mat
		mi.position = at
		world.add_child(mi)
		var tw := mi.create_tween()
		var to := at + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-1.2, 0.3), rng.randf_range(-0.6, 0.2))
		to.y = maxf(to.y, 0.02)
		tw.tween_property(mi, "position", to, 0.45)
		_fx.append([mi, 1.2])


func _tick_fx(delta: float) -> void:
	for i in range(_fx.size() - 1, -1, -1):
		_fx[i][1] -= delta
		if _fx[i][1] <= 0.0:
			if is_instance_valid(_fx[i][0]):
				_fx[i][0].queue_free()
			_fx.remove_at(i)


# ---------------------------------------------------------------- the end

func _end(winner: int, reason: String) -> void:
	running = false
	var men: Array = []
	for g in gunmen:
		g.stats["hp"] = g.hp
		g.stats["alive"] = g.alive
		men.append(g.stats.duplicate())
	var events: Array = []
	for b in brains:
		for e in b.events:
			events.append([e[0], b.team, e[1], e[2]])
	events.sort_custom(func(x, y): return x[0] < y[0])
	result = {
		"match": match_index,
		"winner": winner,
		"winner_name": team_names[winner] if winner >= 0 else "Draw",
		"team_names": team_names.duplicate(), "factions": factions.duplicate(), "map": saloon.map_id, "sizes": team_sizes.duplicate(), "grades": team_grades.duplicate(),
		"reason": reason,
		"duration": elapsed,
		"alive": [alive_count(0), alive_count(1)],
		"hp": [team_hp(0), team_hp(1)],
		"doctrines": doctrines.duplicate(),
		"presets": team_presets.duplicate(),
		"plans": [brains[0].plan_seconds.duplicate(), brains[1].plan_seconds.duplicate()],
		"men": men,
		"events": events,
		"first_blood": first_blood,
		"sudden_death": sudden_death,
	}
	announce(winner, "%s - %s" % [team_wins[winner], reason] if winner >= 0 else "Draw")
	if winner >= 0:
		for g in gunmen:
			if g.alive and g.team == winner:
				g.celebrate()
		if not headless:
			sound("cheer", Vector3(0, 2, 0))
	_celeb_t = 0.0
	match_ended.emit(result)
