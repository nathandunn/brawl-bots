class_name Gunman
extends CharacterBody3D
## One man with a Colt and two fists. Every man is built the same; what differs is how he
## thinks (Personality) and what his team has told him to do (TeamBrain orders).
##
## The individual brain is a utility scorer over the team's tactical map: every cover spot and
## grid point carries how many known enemies can see it standing, see it crouched, and how
## many enemies it can hit even when they crouch (the flank/high-ground value). Personality
## turns those into weights; orders pull the choice toward a zone, forward or back.

signal died(g: Gunman, killer: Gunman, how: String)

const H_STAND := 1.8
const H_CROUCH := 1.15
const RADIUS := 0.3
const BODY_R := 0.27        # bullet capsule radius
const RUN := 3.9
const SPRINT := 5.0
const SNEAK := 1.9
const CYL := 6
const SPARE := 30
const ROUND_LOAD := 0.42    # one cartridge, thumbed into the gate
const COCK := 0.62          # hammer back between aimed shots
const FAN := 0.17           # palm on the hammer
const BASE_SIGMA := 0.036    # radians, standing still, settled aim
const PUNCH_RANGE := 1.45
const FOV_COS := -0.35      # can see ~140 degrees each side of dead ahead... no: 110 deg half-angle

var team := 0
var idx := 0
var gm_name := ""
var preset_name := ""
var personality: Personality
var manager: MatchManager
var saloon: Saloon
var brain: TeamBrain
var rng := RandomNumberGenerator.new()
var team_color := Color.RED

# condition
var hp := 100.0
var alive := true
var arm_wound := false
var leg_wound := false
var crouched := false
var knocked_t := 0.0
var stagger_t := 0.0
var suppression := 0.0
var last_hurt_t := -99.0
var grappled_by: Gunman = null
var grappled_t := -99.0

# the revolver
var cylinder := CYL
var spare := SPARE
var reloading := false
var reload_t := 0.0
var cock_t := 0.0
var aim_target: Gunman = null
var aim_t := 0.0
var aim_need := 0.5
var consec := 0
var fanning := false
var peek_hold := 0.0        # stay up this long after a shot (gunslingers stand in it)
var duck_t := 0.0           # forced crouch (ducking a gun aimed at him)
var punch_cd := 0.0
var punch_wind := -1.0
var punch_target: Gunman = null
var holster := false

# movement & intent
var path := PackedVector3Array()
var path_i := 0
var goal_id := -1
var goal_score := -INF
var move_mode := "run"
var mode := "spawn"
var focus: Gunman = null
var flip_table: Table = null
var decide_t := 0.0
var sense_t := 0.0
var stuck_t := 0.0
var still_t := 0.0          # how long he has been set (not moving) - a set man has his gun up
var rested := false
var last_target: Gunman = null   # who we were on before we ducked
var last_target_t := -99.0
var _last_pos := Vector3.ZERO
var visible_enemies: Array[Gunman] = []
var celebrating := false
var _celebrate_t := 0.0

# visuals
var body_root: Node3D
var torso_mi: MeshInstance3D
var arm_r: Node3D
var arm_l: Node3D
var leg_l: Node3D
var leg_r: Node3D
var gun_mi: MeshInstance3D
var flash_mi: MeshInstance3D
var label: Label3D
var mat_shirt: StandardMaterial3D
var mat_pants: StandardMaterial3D
var mat_skin: StandardMaterial3D
var mat_hat: StandardMaterial3D
var ragdoll: Ragdoll = null
var _walk_phase := 0.0
var _flash_t := 0.0
var show_intent := false

var stats := {}


func _ready() -> void:
	collision_layer = Saloon.LAYER_MEN
	collision_mask = Saloon.LAYER_WORLD | Saloon.LAYER_MEN | Saloon.LAYER_MOVE | Saloon.LAYER_SOFT
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.45
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = H_STAND
	cs.shape = cap
	cs.position = Vector3(0, H_STAND * 0.5, 0)
	add_child(cs)
	if not manager.headless:
		_build_body()
	stats = {"name": gm_name, "team": team, "preset": preset_name, "shots": 0, "hits": 0, "heads": 0, "dmg": 0.0, "kills": 0,
		"punches": 0, "punch_hits": 0, "knockdowns": 0, "fist_kills": 0, "reloads": 0, "flips": 0, "deny_hits": 0,
		"high_hits": 0, "taken": 0.0, "killed_by": "", "died_at": -1.0, "hp": 100.0, "alive": true, "ff": 0.0}
	_last_pos = global_position
	decide_t = rng.randf_range(0.05, 0.4)


# ---------------------------------------------------------------- body

func _m(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _mesh_box(size: Vector3, pos: Vector3, m: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _limb(pos: Vector3, length: float, r: float, m: Material, parent: Node3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = length
	cm.radial_segments = 8
	cm.rings = 2
	mi.mesh = cm
	mi.material_override = m
	mi.position = Vector3(0, -length * 0.5, 0)
	pivot.add_child(mi)
	return pivot


func _build_body() -> void:
	mat_shirt = _m(team_color)
	mat_pants = _m(Color(0.22, 0.2, 0.25))
	mat_skin = _m(Color(0.86, 0.66, 0.5))
	mat_hat = _m(team_color.darkened(0.55) if team == 0 else Color(0.18, 0.14, 0.12))
	var vest := _m(Color(0.25, 0.17, 0.1))
	body_root = Node3D.new()
	add_child(body_root)
	leg_l = _limb(Vector3(-0.13, 0.85, 0), 0.82, 0.11, mat_pants, body_root)
	leg_r = _limb(Vector3(0.13, 0.85, 0), 0.82, 0.11, mat_pants, body_root)
	var upper := Node3D.new()
	upper.name = "upper"
	body_root.add_child(upper)
	torso_mi = _mesh_box(Vector3(0.5, 0.62, 0.3), Vector3(0, 1.17, 0), mat_shirt, upper)
	_mesh_box(Vector3(0.52, 0.5, 0.06), Vector3(0, 1.2, -0.15), vest, upper)
	_mesh_box(Vector3(0.52, 0.08, 0.32), Vector3(0, 0.9, 0), _m(Color(0.15, 0.1, 0.06)), upper)  # gun belt
	var head := _mesh_box(Vector3(0.28, 0.3, 0.28), Vector3(0, 1.64, 0), mat_skin, upper)
	_mesh_box(Vector3(0.3, 0.1, 0.06), Vector3(0, -0.1, -0.13), mat_shirt, head)  # bandana
	var brim := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.34
	bc.bottom_radius = 0.34
	bc.height = 0.03
	bc.radial_segments = 14
	brim.mesh = bc
	brim.material_override = mat_hat
	brim.position = Vector3(0, 0.17, 0)
	head.add_child(brim)
	var crown := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = 0.14
	cc.bottom_radius = 0.17
	cc.height = 0.18
	cc.radial_segments = 12
	crown.mesh = cc
	crown.material_override = mat_hat
	crown.position = Vector3(0, 0.27, 0)
	head.add_child(crown)
	arm_l = _limb(Vector3(-0.32, 1.44, 0), 0.6, 0.08, mat_shirt, upper)
	arm_r = _limb(Vector3(0.32, 1.44, 0), 0.6, 0.08, mat_shirt, upper)
	gun_mi = _mesh_box(Vector3(0.06, 0.12, 0.3), Vector3(0, -0.62, -0.1), _m(Color(0.15, 0.15, 0.17), 0.35), arm_r)
	flash_mi = MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.12
	fm.height = 0.24
	flash_mi.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.85, 0.4)
	flash_mi.material_override = fmat
	flash_mi.position = Vector3(0, -0.66, -0.32)
	flash_mi.visible = false
	arm_r.add_child(flash_mi)
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.pixel_size = 0.006
	label.outline_size = 8
	label.modulate = team_color.lightened(0.35)
	label.position = Vector3(0, 2.35, 0)
	add_child(label)
	_update_label()


func _update_label() -> void:
	if label == null:
		return
	var txt := "%s %d" % [gm_name, int(ceil(hp))]
	if show_intent and alive:
		txt += "\n" + mode
	if reloading:
		txt += " ⟳" if false else " (rel)"
	label.text = txt


# ---------------------------------------------------------------- helpers

func height() -> float:
	return H_CROUCH if crouched or knocked_t > 0.0 else H_STAND


func eye() -> Vector3:
	return global_position + Vector3(0, height() - 0.15, 0)


func chest() -> Vector3:
	return global_position + Vector3(0, height() * 0.68, 0)


func muzzle() -> Vector3:
	return global_position + Vector3(0, height() * 0.78, 0) + forward() * 0.35


func forward() -> Vector3:
	return -global_transform.basis.z


func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func flat_dist(p: Vector3) -> float:
	return Vector2(global_position.x - p.x, global_position.z - p.z).length()


func is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length() > 0.6


func level() -> int:
	return 1 if global_position.y > 2.6 else (2 if global_position.y > 0.4 else 0)


func face_toward(p: Vector3, delta: float, rate := 10.0) -> void:
	var d := flat(p - global_position)
	if d.length() < 0.01:
		return
	var want := atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(delta * rate, 0.0, 1.0))


func facing(p: Vector3, cos_lim: float) -> bool:
	var d := flat(p - global_position).normalized()
	return forward().dot(d) > cos_lim


func p(k: String) -> float:
	return personality.g(k)


func order() -> Dictionary:
	return brain.order_for(self)


func obey() -> float:
	return 0.3 + 0.7 * p("discipline")


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if celebrating:
		_celebrate(delta)
		return
	if not manager.running:
		velocity = Vector3.ZERO
		return
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.5
	suppression = maxf(0.0, suppression - delta * (0.3 + 0.45 * p("nerve")))
	cock_t -= delta
	punch_cd -= delta
	duck_t -= delta
	peek_hold -= delta
	stagger_t -= delta
	if knocked_t > 0.0:
		knocked_t -= delta
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		_pose(delta)
		if knocked_t <= 0.0 and body_root != null:
			body_root.rotation = Vector3.ZERO
		return

	sense_t -= delta
	if sense_t <= 0.0:
		sense_t = 0.18 + rng.randf() * 0.06
		_sense()
	decide_t -= delta
	if decide_t <= 0.0:
		decide_t = 0.45 + rng.randf() * 0.25
		_decide()

	_move(delta)
	_fight(delta)
	_pose(delta)


# ---------------------------------------------------------------- senses

func _sense() -> void:
	visible_enemies.clear()
	var my_eye := eye()
	for e in manager.alive_gunmen():
		if e.team == team:
			continue
		var d := flat_dist(e.global_position)
		var heard_close := d < 3.5 and absf(e.global_position.y - global_position.y) < 1.5
		if not heard_close:
			if d > 40.0:
				continue
			# a man on the balcony sees down; everybody else needs the man in his field of view
			var to := (e.chest() - my_eye)
			if forward().dot(flat(to).normalized()) < -0.3 and not _alerted():
				continue
		var seen := heard_close
		if not seen:
			# any part of him: head first (crouched men behind cover show only that)
			var head := e.global_position + Vector3(0, e.height() - 0.12, 0)
			seen = saloon.line_clear(my_eye, head) or saloon.line_clear(my_eye, e.chest())
		if seen:
			visible_enemies.append(e)
			brain.saw(e, self)


func _alerted() -> bool:
	return suppression > 0.2 or manager.elapsed - last_hurt_t < 2.0


# ---------------------------------------------------------------- the brain

func _decide() -> void:
	var o := order()
	var near := _nearest_enemy_alive(PUNCH_RANGE + 0.3)
	var contacts := brain.contacts
	_update_label()
	# --- a man in your face: fists, or back off if you can still shoot him
	if near != null:
		focus = near
		if p("caution") > 0.75 and hp < 45.0 and p("brawl") < 0.4:
			_set_mode("backing off")
			_go_fallback()
		else:
			_set_mode("brawling")
			_stop()
		return
	# --- out of bullets: fists or hide
	if cylinder == 0 and spare == 0 and not reloading:
		var c := brain.best_contact_for(self, true)
		if c != null and p("caution") < 0.7:
			focus = c
			_set_mode("fists up")
			move_mode = "sprint"
			_go_to(saloon.nearest_node(brain.contact_pos(c)), 99.0)
		else:
			_set_mode("hiding (dry)")
			_go_fallback()
		return
	# --- orders to punish a man the team has counted empty
	if String(o.get("role", "")) == "punish" and o.get("focus") != null and is_instance_valid(o["focus"]) and (o["focus"] as Gunman).alive:
		focus = o["focus"]
		_charge(focus, "punishing reload")
		return
	# --- own initiative: a counted-out man close by
	var empty := brain.empty_contact_near(global_position, 12.0)
	if empty != null and cylinder >= 2 and (p("aggression") + p("brawl")) * 0.5 + rng.randf() * 0.25 > 0.62:
		focus = empty
		_charge(empty, "rushing reload")
		return
	# --- hurt and losing nerve
	if hp < 45.0 and p("nerve") < 0.5 and rng.randf() < 0.8:
		_set_mode("falling back")
		_go_fallback()
		return
	# --- pinned
	if suppression > 0.75 and p("nerve") < 0.6:
		_set_mode("pinned")
		if goal_id < 0 or brain.crouch_exposure(goal_id) > 0.01:
			_go_fallback()
		return
	# --- nobody known: hunt
	if contacts.is_empty():
		_set_mode("hunting")
		move_mode = "sneak" if p("cunning") > 0.5 or p("caution") > 0.6 else "run"
		var z: Vector3 = o.get("zone", brain.enemy_home())
		if o.get("role", "") == "hold" or o.get("role", "") == "guard" or o.get("role", "") == "ambush":
			_choose_spot(o)
		else:
			_go_to(saloon.nearest_node(z.lerp(brain.enemy_home(), 0.5)), 0.0)
		return
	# --- a table to kick over when there is nothing better nearby
	if flip_table == null and brain.threat_count() > 0 and level() == 0:
		var here_prot := 1.0 - brain.crouch_exposure(saloon.nearest_node(global_position))
		if here_prot < 0.5 and rng.randf() < 0.25 + 0.5 * maxf(p("cunning"), p("caution")):
			var tb := saloon.table_near(global_position, 3.5)
			if tb != null:
				flip_table = tb
				tb.claimed_by = self
				_set_mode("flipping a table")
				move_mode = "sprint"
				var threat := brain.threat_centroid()
				var approach := tb.position - flat(threat - tb.position).normalized() * 0.95
				path = PackedVector3Array([approach])
				path_i = 0
				goal_id = -1
				return
	if flip_table != null:
		return
	_choose_spot(o)


func _set_mode(m: String) -> void:
	if m != mode:
		mode = m
		_update_label()


func _charge(target: Gunman, label_txt: String) -> void:
	_set_mode(label_txt)
	move_mode = "sprint"
	var tp := brain.contact_pos(target)
	_go_to(saloon.nearest_node(tp), 99.0)


func _stop() -> void:
	path = PackedVector3Array()
	path_i = 0


func _go_to(id: int, score: float) -> void:
	if id < 0:
		return
	goal_id = id
	goal_score = score
	var stealthy := (p("cunning") > 0.55 or p("caution") > 0.7) and move_mode != "sprint"
	path = saloon.path(team, global_position, id, stealthy)
	path_i = 0
	# drop waypoints already behind us
	while path_i < path.size() - 1 and flat_dist(path[path_i]) < 0.9:
		path_i += 1


## Score every known tactical point and walk to the best.
func _choose_spot(o: Dictionary) -> void:
	var role := String(o.get("role", "free"))
	var ob := obey()
	var push := float(o.get("push", 0.0))
	var zone: Vector3 = o.get("zone", Vector3.INF)
	var ec := brain.threat_centroid()
	var my_d_enemy := flat_dist(ec)
	var tc := brain.team_centroid()
	var nthreat := brain.threat_count()
	var wp := 0.5 + 1.2 * p("caution") + (0.35 if String(o.get("fire", "")) == "exposed_only" else 0.0)
	var ws := 0.4 + 0.5 * p("aggression") + (0.6 * ob if role == "overwatch" or role == "high" else 0.0)
	var wd := 0.25 + 1.3 * p("cunning") + (0.5 * ob if role == "flank" or role == "high" else 0.0)
	var wa := 0.9 * p("aggression") - 0.6 * p("caution") + ob * push * 1.4
	var wz := (1.3 * ob) if zone != Vector3.INF else 0.0
	var wh := 0.9 * p("height") + (1.6 * ob if role == "high" or role == "overwatch_high" else 0.0) - (1.2 * ob if role == "ground" else 0.0)
	var wdist := 0.6 + 0.4 * p("caution") - 0.3 * p("aggression")
	var best := -1
	var best_s := -INF
	var cur_s := -INF
	for id in saloon.tac_ids:
		var np: Vector3 = saloon.nodes[id]["pos"]
		var d := flat_dist(np) + absf(np.y - global_position.y) * 1.5
		if d > 22.0 and id != goal_id:
			continue
		var s := 0.0
		if nthreat > 0:
			var prot := 1.0 - brain.crouch_exposure(id)
			var sight := brain.stand_sight(id)
			var deny := brain.deny_value(id)
			s += wp * prot
			s += ws * sight * (1.0 if prot > 0.5 else 0.35)
			s += wd * deny
			var close := Vector2(np.x - ec.x, np.z - ec.z).length()
			s += wa * (my_d_enemy - close) / 10.0
			if close < 3.0:
				s -= 0.6 * (1.0 - p("brawl"))
		if zone != Vector3.INF:
			s -= wz * Vector2(np.x - zone.x, np.z - zone.z).length() / 10.0
		var lv := int(saloon.nodes[id]["level"])
		if lv == 1:
			s += wh
		elif lv == 2:
			s -= 0.4   # nobody wants to stand on the stairs
		s -= wdist * d / 10.0
		if saloon.nodes[id]["spot"]:
			s += 0.15
		s -= 0.08 * p("teamwork") * maxf(0.0, Vector2(np.x - tc.x, np.z - tc.z).length() - 6.0)
		s -= brain.crowding(id, self) * 0.7
		s += rng.randf() * 0.12
		if id == goal_id:
			cur_s = s + 0.25   # hysteresis: don't dither between two equal spots
			s = cur_s
		if s > best_s:
			best_s = s
			best = id
	if best < 0:
		return
	var label_txt := _role_label(role)
	_set_mode(label_txt)
	move_mode = String(o.get("move", "run"))
	if best != goal_id or path.is_empty() and flat_dist(saloon.node_pos(best)) > 0.6:
		_go_to(best, best_s)
	brain.claim(self, best)


func _role_label(role: String) -> String:
	match role:
		"hold": return "holding"
		"guard": return "guarding stairs"
		"ambush": return "lying in wait"
		"high", "overwatch_high": return "taking the balcony"
		"overwatch": return "overwatch"
		"flank": return "flanking"
		"bound": return "bounding forward"
		"pin": return "pinning them"
		"bait": return "baiting"
		"retreat": return "drawing them in"
		"push": return "pushing"
		"charge": return "charging"
	return "fighting"


func _go_fallback() -> void:
	# the most protected spot that is further from the enemy than we are
	var ec := brain.threat_centroid()
	var my_d := flat_dist(ec)
	var best := -1
	var best_s := -INF
	for id in saloon.tac_ids:
		var np: Vector3 = saloon.nodes[id]["pos"]
		var d := flat_dist(np)
		if d > 14.0:
			continue
		var s := (1.0 - brain.crouch_exposure(id)) * 2.0 + (Vector2(np.x - ec.x, np.z - ec.z).length() - my_d) / 8.0 - d / 12.0
		s -= brain.crowding(id, self)
		if s > best_s:
			best_s = s
			best = id
	move_mode = "sprint"
	_go_to(best, best_s)
	brain.claim(self, best)


func _nearest_enemy_alive(r: float) -> Gunman:
	var best: Gunman = null
	var bd := r
	for e in manager.alive_gunmen():
		if e.team == team:
			continue
		if absf(e.global_position.y - global_position.y) > 1.2:
			continue
		var d := flat_dist(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


# ---------------------------------------------------------------- moving

func _move(delta: float) -> void:
	var want := Vector3.ZERO
	var spd := RUN
	match move_mode:
		"sprint": spd = SPRINT
		"sneak": spd = SNEAK
	if leg_wound:
		spd *= 0.7
	if reloading:
		spd = minf(spd, RUN * 0.8)
	if stagger_t > 0.0:
		spd *= 0.3
	# a man brawling squares up to his opponent
	var near := focus if focus != null and is_instance_valid(focus) and focus.alive and flat_dist(focus.global_position) < PUNCH_RANGE + 0.6 else null
	if flip_table != null:
		if not is_instance_valid(flip_table) or flip_table.flipped and flip_table.claimed_by != self:
			flip_table = null
	if near == null and path_i < path.size():
		var wp := path[path_i]
		var to := flat(wp - global_position)
		var last := path_i == path.size() - 1
		if to.length() < (0.25 if last else 0.6) and absf(wp.y - global_position.y) < 1.4:
			path_i += 1
			if path_i >= path.size():
				_arrived()
		else:
			want = to.normalized() * spd
	elif flip_table != null and path_i >= path.size():
		_do_flip()
	# a steady man stops to take his shot instead of firing on the run
	if aim_target != null and move_mode != "sprint" and p("discipline") + 0.3 * p("patience") > 0.4 and want.length() > 0.0:
		want = Vector3.ZERO
	var accel := 14.0
	velocity.x = move_toward(velocity.x, want.x, accel * delta)
	velocity.z = move_toward(velocity.z, want.z, accel * delta)
	move_and_slide()
	# unstick: wanting to move but going nowhere
	if want.length() > 0.5:
		if global_position.distance_to(_last_pos) < spd * delta * 0.25:
			stuck_t += delta
		else:
			stuck_t = maxf(0.0, stuck_t - delta)
		if stuck_t > 0.7:
			stuck_t = 0.0
			var side := Vector3(-want.z, 0, want.x).normalized() * (1.0 if rng.randf() < 0.5 else -1.0)
			velocity += side * 3.0
			if goal_id >= 0:
				_go_to(goal_id, goal_score)
	_last_pos = global_position
	if Vector2(velocity.x, velocity.z).length() < 0.4:
		still_t += delta
	else:
		still_t = 0.0
	# crouch when settled in cover, sneaking, pinned or ducking
	var at_cover: bool = path_i >= path.size() and goal_id >= 0 and saloon.nodes[goal_id]["spot"] and flat_dist(saloon.node_pos(goal_id)) < 0.7
	var want_crouch: bool = (at_cover and not _peeking()) or move_mode == "sneak" and want.length() > 0.1 or duck_t > 0.0 or (suppression > 0.6 and not _peeking())
	if reloading and (at_cover or suppression > 0.3):
		want_crouch = true
	crouched = want_crouch
	# face: the man we're shooting, else where we're going, else the threat
	if aim_target != null and is_instance_valid(aim_target) and aim_target.alive:
		face_toward(aim_target.global_position, delta, 12.0)
	elif near != null:
		face_toward(near.global_position, delta, 12.0)
	elif want.length() > 0.3:
		face_toward(global_position + want, delta, 8.0)
	elif brain.threat_count() > 0:
		face_toward(brain.threat_centroid(), delta, 4.0)


func _arrived() -> void:
	if move_mode == "sprint" and mode != "fists up" and mode != "punishing reload" and mode != "rushing reload":
		move_mode = "run"


func _do_flip() -> void:
	var tb := flip_table
	flip_table = null
	if tb == null or tb.flipped or flat_dist(tb.position) > 1.6:
		if tb != null and tb.claimed_by == self:
			tb.claimed_by = null
		return
	var threat := brain.threat_centroid()
	tb.flip(flat(threat - tb.position))
	stats["flips"] += 1
	manager.sound("clatter", tb.position)
	brain.log_event("%s kicks over a table" % gm_name, false)
	# crouch behind it
	var spot := tb.crouch_spot()
	path = PackedVector3Array([Vector3(spot.x, 0, spot.z)])
	path_i = 0
	goal_id = saloon.nearest_node(spot)
	move_mode = "run"
	_set_mode("behind the table")
	decide_t = 1.5


func _peeking() -> bool:
	return aim_target != null or peek_hold > 0.0


# ---------------------------------------------------------------- fighting

func _fight(delta: float) -> void:
	# --- fists in close
	var near := _nearest_enemy_alive(PUNCH_RANGE)
	var grappled := grappled_by != null and is_instance_valid(grappled_by) and grappled_by.alive and manager.elapsed - grappled_t < 1.0 and flat_dist(grappled_by.global_position) < PUNCH_RANGE + 0.3
	if punch_wind >= 0.0:
		punch_wind -= delta
		if punch_wind < 0.0:
			_punch_land()
		return
	if near != null:
		var want_fists := grappled or cylinder == 0 or p("brawl") > 0.55 or stagger_t > 0.0
		if want_fists:
			aim_target = null
			if punch_cd <= 0.0 and facing(near.global_position, 0.3):
				punch_target = near
				punch_wind = 0.28
				punch_cd = 0.7 - 0.15 * p("brawl")
				stats["punches"] += 1
				manager.sound("swing", global_position + Vector3(0, 1.4, 0), 1.0, -6.0)
			return
	# --- reloading
	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			if spare > 0 and cylinder < CYL:
				cylinder += 1
				spare -= 1
				manager.sound("load", global_position + Vector3(0, 1.0, 0), 1.0, -10.0)
			if cylinder >= CYL or spare == 0:
				reloading = false
				brain.reload_done(self)
			else:
				reload_t = ROUND_LOAD
				# break off to shoot a man who has shown himself close
				if cylinder >= 2 and _best_target() != null and flat_dist(_best_target().global_position) < 8.0 and p("aggression") > 0.4:
					reloading = false
					brain.reload_done(self)
		_update_label()
		return
	if cylinder == 0:
		if spare > 0 and not grappled:
			_start_reload()
		return
	if grappled:
		aim_target = null
		return
	# a reload of choice: low and nobody in sight
	if cylinder <= int(1 + 2.0 * p("discipline")) and spare > 0 and visible_enemies.is_empty() and aim_target == null:
		_start_reload()
		return
	# --- duck a gun pointed at us (if we are not already about to fire)
	if aim_t < aim_need * 0.6:
		for e in visible_enemies:
			if e.aim_target == self and e.aim_t > 0.12 and not e.reloading:
				if rng.randf() < (0.08 + 0.25 * p("caution") - 0.15 * p("nerve")) and _in_cover():
					duck_t = 0.5 + 0.5 * p("caution")
					if aim_target != null:
						last_target = aim_target
						last_target_t = manager.elapsed
					aim_target = null
					aim_t = 0.0
					return
	if duck_t > 0.0:
		return
	if not manager.can_fire():
		return
	# --- pick a target, aim, fire
	var tgt := _best_target()
	if tgt == null:
		aim_target = null
		aim_t = 0.0
		if String(order().get("fire", "")) == "suppress" and cylinder > 2 and spare > 6 and cock_t <= 0.0:
			_suppress()
		return
	if tgt != aim_target:
		var reacquire := tgt == last_target and manager.elapsed - last_target_t < 2.5
		aim_target = tgt
		aim_t = 0.0
		if not reacquire:
			consec = 0
		var d := flat_dist(tgt.global_position)
		fanning = p("trigger") > 0.45 and d < 7.0 + 5.0 * p("trigger") or (p("trigger") > 0.8 and d < 14.0)
		aim_need = (0.14 if fanning else (0.7 - 0.2 * p("trigger")) * (1.0 + 0.2 * p("patience")))
		# a man who is set and already watching that way has his hammer back and his eye on the
		# lane: the defender's edge over a man who has to run into his sights
		rested = still_t > 0.8 and facing(tgt.global_position, 0.6)
		if rested:
			aim_need *= 0.65
		if reacquire:
			aim_need *= 0.5   # he ducked knowing exactly where to come back up
	if stagger_t > 0.0:
		return
	aim_t += delta * (1.0 - 0.4 * minf(suppression, 1.0))
	if aim_t >= aim_need and cock_t <= 0.0:
		_fire(tgt)


func _in_cover() -> bool:
	return goal_id >= 0 and saloon.nodes[goal_id]["spot"] and flat_dist(saloon.node_pos(goal_id)) < 0.9


func _start_reload() -> void:
	reloading = true
	reload_t = ROUND_LOAD + 0.25   # flip the gate, punch the empties
	aim_target = null
	stats["reloads"] += 1
	brain.heard_reload(self)
	manager.sound("click", global_position + Vector3(0, 1.0, 0))
	_update_label()


## Value of shooting each visible enemy now: the chance of a hit times what the hit is worth.
## Patience sets the bar - a patient man will not stand up for a poor shot.
func _best_target() -> Gunman:
	var o := order()
	var policy := String(o.get("fire", "free"))
	var moving := is_moving()
	var best: Gunman = null
	var best_v := 0.0
	var thr := 0.1 + 0.14 * p("patience") - 0.08 * p("aggression") + (0.15 if policy == "exposed_only" else 0.0) + (0.1 if moving and p("discipline") > 0.6 else 0.0)
	if policy == "hold_fire":
		thr = 0.95
	for e in visible_enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var d := flat_dist(e.global_position)
		var expo := _exposure_of(e)
		if expo <= 0.0:
			continue
		if _mate_in_lane(e):
			continue
		var pd := clampf(1.25 - d / 20.0, 0.15, 1.0) * expo
		if moving:
			pd *= 0.55 if move_mode != "sprint" else 0.35
		if e.is_moving():
			pd *= 0.85
		pd *= 1.0 - 0.45 * minf(suppression, 1.0)
		var v := pd
		if e.aim_target == self:
			v *= 1.35
		if e.hp < 50.0:
			v *= 1.25
		if e.reloading:
			v *= 1.2
		if e == focus or e == o.get("focus"):
			v *= 1.3
		if e == aim_target:
			v *= 1.25   # finish what we started
		if pd >= thr and v > best_v:
			best_v = v
			best = e
	return best


## Never fire through a friend: a mate within an arm's width of the line, short of the target.
func _mate_in_lane(e: Gunman) -> bool:
	return _mate_near_line(e.chest())


## A mate within a slug's likely spread of the line to `to` - or of where it carries on past
## it, since a miss does not stop at the man it was meant for.
func _mate_near_line(to: Vector3) -> bool:
	var from := muzzle()
	var dist := from.distance_to(to)
	var far := from + (to - from).normalized() * (dist + 6.0)
	for m in brain.members:
		if m == self or not m.alive:
			continue
		var base := m.global_position
		var r := manager._closest_seg_seg(from, far, base + Vector3(0, 0.3, 0), base + Vector3(0, m.height(), 0))
		var along: float = r.y * (dist + 6.0)
		var tol := 0.6 + along * BASE_SIGMA * 2.5
		if r.x < tol:
			return true
	return false


## How much of a man we could hit if we stood up now: 1 if his chest is clear, 0.45 if only
## his head shows over cover, 0 if he is fully behind it.
func _exposure_of(e: Gunman) -> float:
	var from := global_position + Vector3(0, H_STAND - 0.15, 0)
	if saloon.line_clear(from, e.chest()):
		return 1.0
	if saloon.line_clear(from, e.global_position + Vector3(0, e.height() - 0.12, 0)):
		return 0.45
	return 0.0


func _aim_point(e: Gunman) -> Vector3:
	var from := muzzle()
	var h := e.height()
	for f in [0.62, 0.82, 0.93, 0.4]:
		var pt: Vector3 = e.global_position + Vector3(0, h * float(f), 0)
		if saloon.line_clear(from, pt):
			return pt
	return e.chest()


func _fire(tgt: Gunman) -> void:
	crouched = false
	var sigma := BASE_SIGMA
	if is_moving():
		sigma *= {"sprint": 2.8, "run": 2.0, "sneak": 1.5}.get(move_mode, 2.0)
	if tgt.is_moving():
		sigma *= 1.25
	sigma *= 1.0 + suppression * 1.2
	if arm_wound:
		sigma *= 1.4
	if fanning:
		sigma *= 2.6
	else:
		sigma *= 1.0 - 0.4 * p("patience")   # the patient man's slower squeeze lands
	sigma *= 1.0 - 0.1 * mini(consec, 3)
	if rested and not is_moving():
		sigma *= 0.88
	var res := manager.fire_bullet(self, _aim_point(tgt), sigma)
	cylinder -= 1
	consec += 1
	cock_t = FAN if fanning else COCK + 0.1 * (1.0 - p("trigger"))
	aim_t = aim_need * (0.6 if fanning else 0.35)   # follow-up shots come quicker
	peek_hold = 0.3 + 1.2 * p("nerve") * (1.0 - p("caution"))
	if res.get("hit") == tgt:
		pass
	_flash()
	# a careful man ducks after every shot; a gunslinger stands in it
	if _in_cover() and rng.randf() < 0.25 + 0.6 * p("caution") - 0.3 * p("nerve"):
		last_target = aim_target
		last_target_t = manager.elapsed
		aim_target = null
		duck_t = 0.25 + 0.4 * p("caution")
	_update_label()


## Fire at where an enemy was last seen to keep his head down while a mate moves.
func _suppress() -> void:
	var c := brain.best_contact_for(self, false)
	if c == null:
		return
	var tp := brain.contact_pos(c) + Vector3(0, 1.0, 0)
	if flat_dist(tp) > 22.0 or _mate_near_line(tp):
		return
	crouched = false
	manager.fire_bullet(self, tp, BASE_SIGMA * 1.8)
	cylinder -= 1
	cock_t = COCK + 0.25
	peek_hold = 0.4
	_flash()


func _flash() -> void:
	if flash_mi != null:
		flash_mi.visible = true
		_flash_t = 0.06


func _punch_land() -> void:
	var e := punch_target
	punch_target = null
	if e == null or not is_instance_valid(e) or not e.alive:
		return
	if flat_dist(e.global_position) > PUNCH_RANGE + 0.25 or not facing(e.global_position, 0.2):
		return
	# a punch seen coming can be slipped
	if e.facing(global_position, 0.3) and e.rng.randf() < 0.15 + 0.15 * e.p("caution"):
		return
	stats["punch_hits"] += 1
	var dmg := 10.0 + 4.0 * p("brawl")
	manager.sound("thud", e.global_position + Vector3(0, 1.4, 0))
	e.grappled_by = self
	e.grappled_t = manager.elapsed
	e.stagger_t = 0.3
	var kd := rng.randf() < 0.14 + 0.18 * p("brawl")
	e.take_damage(dmg, "fists", self, "torso", flat(e.global_position - global_position).normalized())
	if kd and e.alive:
		stats["knockdowns"] += 1
		e.knock_down(1.3)


# ---------------------------------------------------------------- getting hurt

func take_damage(amount: float, how: String, by: Gunman, part: String, dir: Vector3) -> void:
	if not alive:
		return
	hp -= amount
	last_hurt_t = manager.elapsed
	stats["taken"] += amount
	if by != null:
		if by.team == team:
			by.stats["ff"] += amount
		else:
			by.stats["dmg"] += amount
	if part == "arm":
		arm_wound = true
	elif part == "leg":
		leg_wound = true
	suppression = minf(1.5, suppression + 0.5)
	_hurt_flash()
	if hp <= 0.0:
		hp = 0.0
		_die(by, how, dir)
	else:
		decide_t = minf(decide_t, 0.05)
		brain.member_hit(self, by)
	_update_label()


func knock_down(t: float) -> void:
	knocked_t = t
	aim_target = null
	reloading = false
	if body_root != null:
		body_root.rotation = Vector3(-1.3, 0, 0)


func suppress(amount: float, by: Gunman) -> void:
	suppression = minf(1.5, suppression + amount * (1.0 - 0.5 * p("nerve")))
	if by != null and by.team != team:
		brain.heard_shot_near(by, self)


func _hurt_flash() -> void:
	if torso_mi == null:
		return
	var m := mat_shirt
	m.albedo_color = Color(1, 0.9, 0.9)
	get_tree().create_timer(0.08).timeout.connect(func(): if is_instance_valid(self): m.albedo_color = team_color)


func _die(by: Gunman, how: String, dir: Vector3) -> void:
	alive = false
	stats["alive"] = false
	stats["hp"] = 0.0
	stats["died_at"] = manager.elapsed
	stats["killed_by"] = by.gm_name if by != null else "?"
	if by != null and by.team != team:
		by.stats["kills"] += 1
		if how == "fists":
			by.stats["fist_kills"] += 1
	collision_layer = 0
	collision_mask = Saloon.LAYER_WORLD
	if flip_table != null and flip_table.claimed_by == self:
		flip_table.claimed_by = null
	manager.sound("death", global_position + Vector3(0, 1.2, 0))
	if body_root != null:
		_spawn_ragdoll(dir * (5.0 if how == "gun" else 3.0))
	died.emit(self, by, how)


func _spawn_ragdoll(impulse: Vector3) -> void:
	ragdoll = Ragdoll.new()
	get_parent().add_child(ragdoll)
	ragdoll.build(global_transform, mat_shirt, mat_pants, mat_skin)
	if ragdoll.bodies.has("head"):
		var hat := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.3
		bc.bottom_radius = 0.3
		bc.height = 0.03
		hat.mesh = bc
		hat.material_override = mat_hat
		hat.position = Vector3(0, 0.2, 0)
		(ragdoll.bodies["head"] as Node3D).add_child(hat)
	ragdoll.shove(impulse + Vector3(0, 1.5, 0))
	body_root.visible = false
	if label != null:
		label.visible = false


func cleanup() -> void:
	if ragdoll != null and is_instance_valid(ragdoll):
		ragdoll.queue_free()
	ragdoll = null


# ---------------------------------------------------------------- pose & celebration

func _pose(delta: float) -> void:
	if body_root == null:
		return
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			flash_mi.visible = false
	if knocked_t > 0.0:
		return
	var crouch_amt := 1.0 if crouched else 0.0
	var upper: Node3D = body_root.get_node("upper")
	upper.position.y = lerpf(upper.position.y, -0.55 * crouch_amt, clampf(delta * 12.0, 0, 1))
	var spd := Vector2(velocity.x, velocity.z).length()
	_walk_phase += delta * spd * 2.6
	var swing := sin(_walk_phase) * clampf(spd / 4.0, 0.0, 1.0) * 0.7
	if crouched:
		leg_l.rotation.x = lerpf(leg_l.rotation.x, -1.2 + swing * 0.3, clampf(delta * 12.0, 0, 1))
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.3 - swing * 0.3, clampf(delta * 12.0, 0, 1))
		leg_l.position.y = 0.5
		leg_r.position.y = 0.5
	else:
		leg_l.rotation.x = swing
		leg_r.rotation.x = -swing
		leg_l.position.y = 0.85
		leg_r.position.y = 0.85
	# right arm: raised and pointing when aiming or peeking, else down at the side
	var aiming := aim_target != null or peek_hold > 0.0
	var target_rx := 1.57 if aiming else (0.35 if reloading else -swing * 0.6)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, target_rx, clampf(delta * 14.0, 0, 1))
	arm_l.rotation.x = lerpf(arm_l.rotation.x, (0.9 if reloading else swing * 0.6), clampf(delta * 10.0, 0, 1))
	if punch_wind >= 0.0:
		arm_l.rotation.x = 1.6


func celebrate() -> void:
	celebrating = true
	_celebrate_t = rng.randf() * 0.3
	aim_target = null
	crouched = false
	velocity = Vector3.ZERO
	_set_mode("victory")


func _celebrate(delta: float) -> void:
	_celebrate_t += delta
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	velocity.x = 0
	velocity.z = 0
	move_and_slide()
	if body_root == null:
		return
	var t := _celebrate_t
	# fire twice into the ceiling, then a jig, hat in the air on the beat
	if t < 2.0:
		arm_r.rotation.x = lerpf(arm_r.rotation.x, 3.0, clampf(delta * 8.0, 0, 1))
		if (t > 0.5 and t - delta <= 0.5) or (t > 1.3 and t - delta <= 1.3):
			_flash()
			manager.sound("shot", global_position + Vector3(0, 2.2, 0), 1.0, -4.0)
	else:
		var beat := manager.dance_clock
		var hop := absf(sin(beat * 5.0)) * 0.25
		body_root.position.y = hop
		leg_l.rotation.x = sin(beat * 10.0) * 0.6
		leg_r.rotation.x = -sin(beat * 10.0) * 0.6
		arm_l.rotation.z = 2.4 + sin(beat * 5.0) * 0.4
		arm_r.rotation.x = 2.6
		rotation.y += delta * 2.5
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			flash_mi.visible = false
