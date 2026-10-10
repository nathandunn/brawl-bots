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

const TEAM_SIZE := 5
const MATCH_TIME := 120.0
const SUDDEN_DEATH_CAP := 45.0
const STANDOFF := 3.0      # the piano stops; nobody draws until the bottle breaks
const TEAM_NAMES := ["Red", "Blue"]
const TEAM_COLORS := [Color(0.85, 0.25, 0.2), Color(0.25, 0.45, 0.9)]
## Where a slug lands decides everything. Head or heart: dead. Gut: badly hurt and bleeding.
## Arm or leg: not much blood, but he can't shoot, punch or walk right after (see Gunman).
const DMG := {"head": 999.0, "heart": 999.0, "gut": 38.0, "arm_r": 12.0, "arm_l": 12.0, "leg_l": 12.0, "leg_r": 12.0}
const PART_NAMES := {"head": "head", "heart": "heart", "gut": "gut", "arm_r": "gun arm", "arm_l": "left arm", "leg_l": "left leg", "leg_r": "right leg"}
const SPAWNS := [Vector2(13.2, 4.0), Vector2(12.9, 6.3), Vector2(10.2, 6.4), Vector2(9.8, 3.4), Vector2(13.8, 7.6)]

var world: Node3D
var saloon: Saloon
var sfx: Sfx = null
var headless := false
var doctrines: Array[String] = ["Adaptive", "Adaptive"]
var team_presets: Array[String] = ["Balanced", "Balanced"]
var player_preset := [["", "", "", "", ""], ["", "", "", "", ""]]   # "" = follow the team
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
	brains.clear()
	for t in 2:
		var b := TeamBrain.new()
		b.rng.seed = rng.randi()
		b.setup(t, self, saloon, doctrines[t])
		brains.append(b)
	for t in 2:
		var slots := [0, 1, 2, 3, 4]
		for k in range(4, 0, -1):
			var j := rng.randi_range(0, k)
			var tmp = slots[k]
			slots[k] = slots[j]
			slots[j] = tmp
		for i in TEAM_SIZE:
			var g := Gunman.new()
			g.team = t
			g.idx = i
			g.gm_name = "%s%d" % [TEAM_NAMES[t][0], i + 1]
			var pp := personality_for(t, i)
			g.preset_name = pp[0]
			g.personality = pp[1]
			g.manager = self
			g.saloon = saloon
			g.brain = brains[t]
			g.team_color = TEAM_COLORS[t]
			g.rng.seed = rng.randi()
			g.voice_id = (i + t) % 3
			g.voice_pitch = rng.randf_range(0.9, 1.1)
			g.show_intent = show_intents
			var sp: Vector2 = SPAWNS[slots[i]]
			var s := -1.0 if t == 0 else 1.0
			g.position = Vector3(sp.x * s + rng.randf_range(-0.3, 0.3), 0.05, sp.y + rng.randf_range(-0.3, 0.3))
			g.rotation.y = -PI * 0.5 if t == 0 else PI * 0.5
			g.died.connect(_on_died)
			world.add_child(g)
			gunmen.append(g)
			brains[t].members.append(g)
	running = true
	announce(-1, "The piano stops. Nobody draws for %d seconds..." % int(STANDOFF))
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


func _physics_process(delta: float) -> void:
	dance_clock += delta
	_tick_fx(delta)
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
		announce(-1, "DRAW!")
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
func fire_bullet(shooter: Gunman, aim: Vector3, sigma: float) -> Dictionary:
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
	shooter.stats["shots"] += 1
	sound("shot", from, rng.randf_range(0.92, 1.08))
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
		var dmg: float = DMG[part] * rng.randf_range(0.85, 1.15)
		if victim.team != shooter.team:
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
		"winner_name": TEAM_NAMES[winner] if winner >= 0 else "Draw",
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
	announce(winner, "%s wins - %s" % [TEAM_NAMES[winner], reason] if winner >= 0 else "Draw")
	if winner >= 0:
		for g in gunmen:
			if g.alive and g.team == winner:
				g.celebrate()
		if not headless:
			sound("cheer", Vector3(0, 2, 0))
	_celeb_t = 0.0
	match_ended.emit(result)
