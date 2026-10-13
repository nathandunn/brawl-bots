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
const SPARE := 12           # 18 rounds in all; after that it's fists
const TOTAL := CYL + SPARE
const ROUND_LOAD := 0.42    # one cartridge, thumbed into the gate
const COCK := 0.62          # hammer back between aimed shots
const FAN := 0.17           # palm on the hammer
const BASE_SIGMA := 0.03    # radians: standing still, aim fully settled
const AIM_TAU := 0.42       # how fast the aim settles: spread x(1 + 2.2 e^(-t/tau))
const AIM_BUCKETS := [0.3, 0.7, 1.2]   # stats: snap / quick / steady / careful
const PUNCH_RANGE := 1.45
## Every wound bleeds; one is about a minute from killing a man, two about half that.
const BLEED := {"gut": 1.1, "arm_r": 1.4, "arm_l": 1.4, "leg_l": 1.4, "leg_r": 1.4}
const MISFIRE := 0.015      # a bad cap, a cylinder out of line
const JAM_SCUFFLE := 0.22   # ... much likelier with a man hanging on your gun hand
const JAM_CLEAR := 1.6      # seconds to work it free, two hands
const CLINCH := 0.95        # 3 ft: close enough to grab hold and wrestle
const NO_SHOOT := 3.0       # nobody fires a gun inside 3 m: close in and fight, back off, or throw something
const PUNCH_JAM := 0.32     # a punch to a man with his gun up can knock the cylinder out of line

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
## who he is: faction (outlaws, law, lotus, dragon), family (west, ninja), character, grade
var faction := "outlaws"
var family := "west"
var kind := "Balanced"
var grade := "Regular"
var gun := "colt"            # "colt" or "" (no gun)
var melee := "fists"         # fists, katana, nunchaku, staff
var loadout_stars := 0
var stealth := false
## abilities from his grade: skill, not armour
var ab_speed := 1.0
var ab_jump := 0.3
var ab_smarts := 0.5
var ab_aim := 1.0
var jump_cls := 1
## the rule script his side is running (null = the built-in brain only)
var script_rules: AiScript = null
var last_rule := ""

# condition
var hp := 100.0
var alive := true
## Wounds, by part: arm_r (the gun arm), arm_l, leg_l, leg_r, gut. Counted, not just flagged.
var wounds := {"arm_r": 0, "arm_l": 0, "leg_l": 0, "leg_r": 0, "gut": 0}
var bleed := 0.0
var bleed_by: Gunman = null
var voice_id := 0
var voice_pitch := 1.0
var _voice_t := -99.0
var jammed := false
var jam_t := 0.0
var _drip_t := 0.0
var _last_cell := Vector3i(9999, 0, 0)
var _close_choice_t := 0.0
var _close_fists := false     # at arm's length: decided to fight with fists rather than shoot
var _riposte := false         # just turned a blow: the next one comes quicker
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
# a bottle off the bar or a table: grab it, throw it, or break it over a head
var has_bottle := false      # something in his hand to throw: see held_kind
var held_kind := ""          # "bottle" or "chair"
var grab_t := -1.0
var throw_wind := -1.0
var throw_target: Gunman = null
var _bottle_cd := 0.0
var bottle_mi: MeshInstance3D = null
# inside 3 ft: the blow being thrown, and a wrestling clinch
var blow := ""                # "kick" while a kick is coming; "" for a punch or weapon blow
var wrestle_t := -1.0
var wrestle_with: Gunman = null
var wrestle_lead := false     # he started it; he resolves it
var _clinch_t := 0.0
var _band_t := 0.0
var _stall_t := 0.0           # an enemy within 3 m and nobody hurt: never let it sit            # how long he's been stuck inside 3 m without landing a blow
# going over the rail (or off a roof)
var falling := false
var fall_dead := false        # the hit killed him; the fall is only where he lands
var fall_by: Gunman = null
var fall_how := ""

# movement & intent
var path := PackedVector3Array()
var path_i := 0
var path_ids := PackedInt64Array()
# a jump / climb / drop in progress along a nav link
var trav_t := -1.0
var trav_dur := 0.0
var trav_from := Vector3.ZERO
var trav_to := Vector3.ZERO
var trav_type := ""
var trav_h := 0.0
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
## The mode he is in. Each has its own movement, firing and pose:
##   hold, advance, duck, hide, cower, flank, rush, fall back, brawl, hunt, dry
var stance := "hold"
var stance_t := 0.0          # time in this stance
var stance_lock := 0.0       # can't be talked out of it before this runs down
var cower_cd := 0.0
var flank_goal := -1
var ambush_ready := false    # hiding with an enemy walking into him: comes up already aimed
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
var weapon_root: Node3D
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
	# what he carries and how good he is
	if gun == "colt":
		cylinder = CYL
		spare = SPARE
	else:
		cylinder = loadout_stars
		spare = 0
	jump_cls = 0 if ab_jump < 0.25 else (1 if ab_jump < 0.8 else 2)
	if not manager.headless:
		_build_body()
	stats = {"name": gm_name, "team": team, "preset": preset_name, "shots": 0, "hits": 0, "heads": 0, "dmg": 0.0, "kills": 0,
		"punches": 0, "punch_hits": 0, "knockdowns": 0, "fist_kills": 0, "reloads": 0, "flips": 0, "deny_hits": 0,
		"high_hits": 0, "taken": 0.0, "killed_by": "", "died_at": -1.0, "hp": 100.0, "alive": true, "ff": 0.0,
		"modes": {}, "cowers": 0, "flanks": 0, "hides": 0, "rushes": 0, "aim_sum": 0.0, "aimb": [[0, 0], [0, 0], [0, 0], [0, 0]], "aimr": [], "dry_at": -1.0, "wounds": [], "death_part": "", "jams": 0, "slips": 0, "gun_knocks": 0, "bled": 0.0,
		"kind": kind, "grade": grade, "faction": faction, "jumps": 0, "blocks": 0, "parries": 0, "dodges": 0, "melee_hits": 0, "melee_kills": 0, "stars": 0, "star_hits": 0, "rules": {},
		"bottles": 0, "bottle_hits": 0, "falls": 0, "fall_kills": 0, "kicks": 0, "kick_hits": 0, "wrestles": 0, "throws": 0}
	for i in 12:
		stats["aimr"].append([0, 0])
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
	var ninja := family == "ninja"
	mat_shirt = _m(team_color if not ninja else (Color(0.1, 0.09, 0.11) if faction == "lotus" else Color(0.5, 0.06, 0.06)))
	mat_pants = _m(Color(0.22, 0.2, 0.25) if not ninja else mat_shirt.albedo_color.darkened(0.2))
	mat_skin = _m(Color(0.86, 0.66, 0.5))
	mat_hat = _m(Color(0.1, 0.09, 0.09) if faction == "outlaws" else Color(0.72, 0.62, 0.45))
	var vest := _m(Color(0.25, 0.17, 0.1))
	body_root = Node3D.new()
	add_child(body_root)
	leg_l = _limb(Vector3(-0.13, 0.85, 0), 0.82, 0.11, mat_pants, body_root)
	leg_r = _limb(Vector3(0.13, 0.85, 0), 0.82, 0.11, mat_pants, body_root)
	var upper := Node3D.new()
	upper.name = "upper"
	body_root.add_child(upper)
	torso_mi = _mesh_box(Vector3(0.5, 0.62, 0.3), Vector3(0, 1.17, 0), mat_shirt, upper)
	var head := _mesh_box(Vector3(0.28, 0.3, 0.28), Vector3(0, 1.64, 0), mat_skin, upper)
	var eye_m := _m(Color(0.08, 0.06, 0.05))
	for ex in [-0.065, 0.065]:
		_mesh_box(Vector3(0.045, 0.03, 0.01), Vector3(ex, 0.045, -0.142), eye_m, head)
	if ninja:
		# the hood: garb-coloured all over the head, a slit of skin for the eyes
		var hood := mat_shirt
		_mesh_box(Vector3(0.31, 0.17, 0.31), Vector3(0, 0.08 + 0.06, 0), hood, head)      # crown
		_mesh_box(Vector3(0.31, 0.15, 0.31), Vector3(0, -0.085, 0), hood, head)           # mask
		var sash := _m(Color(0.55, 0.35, 0.8) if faction == "lotus" else Color(0.95, 0.72, 0.15))
		_mesh_box(Vector3(0.53, 0.09, 0.33), Vector3(0, 0.92, 0), sash, upper)
		var tail := _mesh_box(Vector3(0.07, 0.3, 0.03), Vector3(0.18, 0.78, 0.17), sash, upper)
		tail.rotation.z = 0.25
		_mesh_box(Vector3(0.33, 0.06, 0.06), Vector3(0, 0.055, 0.17), sash, head)          # hood knot band
		if loadout_stars > 0:
			for k in 3:
				var st := _shuriken_mesh(0.05)
				st.position = Vector3(-0.12 + k * 0.08, 0.92, -0.17)
				upper.add_child(st)
	else:
		_mesh_box(Vector3(0.52, 0.5, 0.06), Vector3(0, 1.2, -0.15), vest, upper)
		_mesh_box(Vector3(0.52, 0.08, 0.32), Vector3(0, 0.9, 0), _m(Color(0.15, 0.1, 0.06)), upper)  # gun belt
		if faction == "outlaws":
			_bandana(head)
		else:
			_tin_star(upper, Vector3(-0.13, 1.33, -0.19))
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
	if grade == "Super":
		# a super gets a thin gold line at the collar so you can pick him out of the crowd
		_mesh_box(Vector3(0.52, 0.04, 0.32), Vector3(0, 1.47, 0), _m(Color(1.0, 0.82, 0.3), 0.3), upper)
	arm_l = _limb(Vector3(-0.32, 1.44, 0), 0.6, 0.08, mat_shirt, upper)
	arm_r = _limb(Vector3(0.32, 1.44, 0), 0.6, 0.08, mat_shirt, upper)
	_build_weapon()
	flash_mi = MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.12
	fm.height = 0.24
	flash_mi.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.85, 0.4)
	flash_mi.material_override = fmat
	flash_mi.position = Vector3(0, -0.94, -0.05)
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


## What he carries in his right hand: a Colt, a katana, nunchaku or a bo staff.
func _build_weapon() -> void:
	var steel := _m(Color(0.82, 0.84, 0.88), 0.25)
	var wood := _m(Color(0.45, 0.3, 0.16))
	var dark := _m(Color(0.12, 0.1, 0.1))
	weapon_root = Node3D.new()
	weapon_root.position = Vector3(0, -0.6, 0)
	arm_r.add_child(weapon_root)
	if gun == "colt":
		_build_revolver()
		return
	match melee:
		"katana":
			gun_mi = _mesh_box(Vector3(0.035, 0.012, 0.85), Vector3(0, 0, -0.55), steel, weapon_root)
			_mesh_box(Vector3(0.1, 0.03, 0.03), Vector3(0, 0, -0.12), dark, weapon_root)
			_mesh_box(Vector3(0.04, 0.04, 0.24), Vector3(0, 0, 0.0), dark, weapon_root)
		"nunchaku":
			gun_mi = _mesh_box(Vector3(0.045, 0.045, 0.32), Vector3(0, 0, -0.05), wood, weapon_root)
			var swing := _mesh_box(Vector3(0.045, 0.045, 0.32), Vector3(0, -0.2, -0.3), wood, weapon_root)
			swing.rotation.x = 0.9
			_mesh_box(Vector3(0.01, 0.01, 0.1), Vector3(0, -0.06, -0.24), steel, weapon_root)
		"staff":
			gun_mi = _mesh_box(Vector3(0.05, 0.05, 1.9), Vector3(0, 0, -0.3), wood, weapon_root)
		_:
			gun_mi = _mesh_box(Vector3(0.01, 0.01, 0.01), Vector3.ZERO, dark, weapon_root)


## A Colt single-action six-shooter, in the hand: barrel on along the arm, the fluted cylinder,
## the hammer, the trigger guard and a walnut grip dropping below the hand. Everything hangs off
## gun_mi so it hides and changes hands as one.
func _build_revolver() -> void:
	var blued := _m(Color(0.16, 0.16, 0.19), 0.3)
	var steel := _m(Color(0.42, 0.43, 0.47), 0.25)
	var walnut := _m(Color(0.36, 0.2, 0.1), 0.7)
	# frame: the hand's at the origin; "forward" when aimed is -Y here, "down" is +Z
	gun_mi = _mesh_box(Vector3(0.034, 0.1, 0.05), Vector3(0, -0.66, -0.02), blued, arm_r)
	gun_mi.scale = Vector3.ONE * 1.5   # a touch larger than life, so it reads at fighting distance
	# barrel
	var bm := CylinderMesh.new()
	bm.top_radius = 0.013
	bm.bottom_radius = 0.013
	bm.height = 0.13
	bm.radial_segments = 10
	var barrel := MeshInstance3D.new()
	barrel.mesh = bm
	barrel.material_override = blued
	barrel.position = Vector3(0, -0.105, -0.022)
	gun_mi.add_child(barrel)
	# ejector rod housing under the barrel
	var rod := _mesh_box(Vector3(0.012, 0.085, 0.012), Vector3(0, -0.085, 0.0), blued, gun_mi)
	rod.name = "rod"
	# the cylinder, six chambers round it
	var cm := CylinderMesh.new()
	cm.top_radius = 0.036
	cm.bottom_radius = 0.036
	cm.height = 0.055
	cm.radial_segments = 12
	var cyl := MeshInstance3D.new()
	cyl.mesh = cm
	cyl.material_override = steel
	cyl.position = Vector3(0, -0.01, -0.012)
	gun_mi.add_child(cyl)
	for k in 6:
		var a := TAU * k / 6.0
		var ch := _mesh_box(Vector3(0.008, 0.058, 0.008), Vector3(cos(a) * 0.024, -0.01, -0.012 + sin(a) * 0.024), blued, gun_mi)
		ch.name = "flute%d" % k
	# hammer spur, trigger and guard
	_mesh_box(Vector3(0.012, 0.03, 0.025), Vector3(0, 0.045, -0.04), blued, gun_mi)
	_mesh_box(Vector3(0.006, 0.012, 0.03), Vector3(0, 0.0, 0.035), steel, gun_mi)
	var guard := _mesh_box(Vector3(0.008, 0.05, 0.008), Vector3(0, -0.005, 0.055), steel, gun_mi)
	guard.name = "guard"
	# walnut grip, raked back below the hand
	var grip := _mesh_box(Vector3(0.03, 0.045, 0.12), Vector3(0, 0.05, 0.065), walnut, gun_mi)
	grip.rotation.x = 0.35


static var _star_mat: StandardMaterial3D


func _shuriken_mesh(r: float) -> MeshInstance3D:
	if _star_mat == null:
		_star_mat = StandardMaterial3D.new()
		_star_mat.albedo_color = Color(0.75, 0.77, 0.82)
		_star_mat.metallic = 0.3
		_star_mat.roughness = 0.3
		_star_mat.emission_enabled = true
		_star_mat.emission = Color(0.3, 0.3, 0.33)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 4:
		var a := TAU * k / 4.0
		var tip := Vector3(cos(a), 0, sin(a)) * r
		var l := Vector3(cos(a + 0.5), 0, sin(a + 0.5)) * r * 0.3
		var rr := Vector3(cos(a - 0.5), 0, sin(a - 0.5)) * r * 0.3
		for f in [[Vector3.ZERO, rr, tip], [Vector3.ZERO, tip, l]]:
			for v in f:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
			for v in [f[0], f[2], f[1]]:
				st.set_normal(Vector3.DOWN)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _star_mat
	mi.rotation.x = PI * 0.5
	return mi


## An outlaw's mask: a kerchief over nose, mouth and chin, knotted behind, its point hanging
## below the jaw. Only the eyes show between it and the hat brim.
static var _bandana_mat: StandardMaterial3D
static var _tin_mat: StandardMaterial3D


func _bandana(head: Node3D, k := 1.0) -> void:
	if _bandana_mat == null:
		_bandana_mat = StandardMaterial3D.new()
		_bandana_mat.albedo_color = Color(0.5, 0.06, 0.06)
		_bandana_mat.roughness = 0.9
	_mesh_box(Vector3(0.3, 0.16, 0.05) * k, Vector3(0, -0.06, -0.14) * k, _bandana_mat, head)     # over the face
	_mesh_box(Vector3(0.3, 0.16, 0.05) * k, Vector3(0, -0.06, 0.14) * k, _bandana_mat, head)      # round the back
	for sx in [-1.0, 1.0]:
		_mesh_box(Vector3(0.04, 0.16, 0.3) * k, Vector3(sx * 0.145, -0.06, 0) * k, _bandana_mat, head)
	var tip := _mesh_box(Vector3(0.17, 0.17, 0.03) * k, Vector3(0, -0.16, -0.15) * k, _bandana_mat, head)
	tip.rotation.z = PI * 0.25                                                             # the point
	# two white dots of pattern, so it reads as a kerchief and not a beard
	var dot_m := _m(Color(0.95, 0.9, 0.85))
	for dx in [-0.07, 0.07]:
		_mesh_box(Vector3(0.025, 0.025, 0.01) * k, Vector3(dx, -0.04, -0.168) * k, dot_m, head)


## A lawman's tin star, pinned over the heart: a five-point star cut from sheet tin.
func _tin_star(parent: Node3D, at: Vector3) -> MeshInstance3D:
	if _tin_mat == null:
		_tin_mat = StandardMaterial3D.new()
		# polished tin: bright, a little emissive so it catches the lamplight from any angle
		_tin_mat.albedo_color = Color(0.86, 0.87, 0.9)
		_tin_mat.metallic = 0.3
		_tin_mat.roughness = 0.2
		_tin_mat.emission_enabled = true
		_tin_mat.emission = Color(0.55, 0.55, 0.58)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for k in 10:
		var a := PI * 0.5 + TAU * k / 10.0
		var r := 0.075 if k % 2 == 0 else 0.032
		pts.append(Vector3(cos(a) * r, sin(a) * r, 0))
	var c := Vector3.ZERO
	for k in 10:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[(k + 1) % 10]
		for face in [[c, b, a, -1.0], [c, a, b, 1.0]]:
			st.set_normal(Vector3(0, 0, face[3]))
			st.add_vertex(face[0] + Vector3(0, 0, face[3] * 0.004))
			st.add_vertex(face[1] + Vector3(0, 0, face[3] * 0.004))
			st.add_vertex(face[2] + Vector3(0, 0, face[3] * 0.004))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _tin_mat
	mi.position = at
	parent.add_child(mi)
	return mi


func _update_label() -> void:
	if label == null:
		return
	var ammo := ""
	if gun == "colt":
		ammo = "dry" if total_ammo() == 0 else "%d+%d" % [cylinder, spare]
	elif loadout_stars > 0:
		ammo = "%d stars" % cylinder
	if grade == "Super":
		ammo += " *"
	if has_bottle:
		ammo += " +bottle"

	var txt := "%s %d  %s" % [gm_name, int(ceil(hp)), ammo]
	var wl := PackedStringArray()
	if legs_hit() == 2:
		wl.append("crawling")
	elif legs_hit() == 1:
		wl.append("limping")
	if arms_hit() == 2:
		wl.append("arms shot")
	elif wounds["arm_r"] > 0:
		wl.append("gun arm shot")
	elif wounds["arm_l"] > 0:
		wl.append("left arm shot")
	if wounds["gut"] > 0:
		wl.append("gut-shot")
	if bleed > 0.0:
		wl.append("bleeding ~%ds" % int(hp / bleed))
	if wl.size() > 0 and alive:
		txt += "\n" + ", ".join(wl)
	if alive and not celebrating:
		var st := shown_stance()
		if show_intent:
			txt += "\n" + st.to_upper() + ("" if mode == st or mode == "" else " - " + mode)
			if last_rule != "":
				txt += "\n[" + last_rule + "]"

		elif st in ["cower", "hide", "flank", "rush", "duck"]:
			txt += "\n" + st.to_upper()
	if reloading:
		txt += " (rel)"
	if jammed:
		txt += " JAMMED"
	label.text = txt


func legs_hit() -> int:
	return int(wounds["leg_l"] > 0) + int(wounds["leg_r"] > 0)


func arms_hit() -> int:
	return int(wounds["arm_r"] > 0) + int(wounds["arm_l"] > 0)


## Shot through the gun arm he shifts the Colt to his left hand: wide, and slow to settle.
## Both arms gone and he can barely hold it up.
func gun_hand_penalty() -> float:
	if arms_hit() == 2:
		return 3.2
	if wounds["arm_r"] > 0:
		return 2.0
	return 1.0


## Thumbing cartridges into the gate takes two hands.
func reload_penalty() -> float:
	return [1.0, 2.0, 3.0][arms_hit()]


## A man can't throw a punch with an arm that has a slug in it; with both he can't punch at all.
func can_punch() -> bool:
	return arms_hit() < 2


func punch_power() -> float:
	return 1.0 if arms_hit() == 0 else 0.4


func weapon() -> Dictionary:
	return Roster.WEAPONS.get(melee, Roster.WEAPONS["fists"])


func reach() -> float:
	return float(weapon()["reach"])


## A ninja with a blade or staff closes in to fight; a gunman shoots and punches when he must.
func melee_first() -> bool:
	return gun == "" and melee != "fists"


func throws_stars() -> bool:
	return gun == "" and loadout_stars > 0


## Rounds or stars he started with - what "dry" means for him.
func total_rounds() -> int:
	return TOTAL if gun == "colt" else maxi(loadout_stars, 1)


func total_ammo() -> int:
	return cylinder + spare


## The stance as you'd describe it from across the room: a man ducking behind his table is
## ducking, whatever he is in the middle of.
func shown_stance() -> String:
	if wrestle_t >= 0.0:
		return "wrestle"
	if stance == "cower":
		return "cower"
	if duck_t > 0.0:
		return "duck"
	return stance


# ---------------------------------------------------------------- helpers

func height() -> float:
	return H_CROUCH if crouched or knocked_t > 0.0 or legs_hit() == 2 else H_STAND


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
	return 1 if global_position.y > Saloon.HIGH_Y else (2 if global_position.y > 0.4 else 0)


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
	if falling:
		_traverse(delta)
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
	stance_t += delta
	stance_lock -= delta
	cower_cd -= delta
	if bleed > 0.0:
		hp -= bleed * delta
		stats["bled"] += bleed * delta
		_drip_t -= delta
		if _drip_t <= 0.0:
			_drip_t = 0.25
			if manager.blood != null:
				manager.blood.pour(global_position + Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15)), bleed * 0.25 * 0.8)
			if int(manager.elapsed * 4.0) % 8 == 0:
				_update_label()
		if hp <= 0.0:
			hp = 0.0
			stats["death_part"] = "bled out"
			brain.log_event("%s has bled out" % gm_name, true)
			say("die")
			_die(bleed_by, "gun", forward())
			return
	var ss := shown_stance()
	stats["modes"][ss] = float(stats["modes"].get(ss, 0.0)) + delta
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
		sense_t = lerpf(0.28, 0.12, ab_smarts) + rng.randf() * 0.06
		_sense()
	decide_t -= delta
	if decide_t <= 0.0:
		decide_t = lerpf(0.75, 0.28, ab_smarts) + rng.randf() * 0.2
		_decide()
		_update_label()

	if trav_t >= 0.0:
		_traverse(delta)
		_pose(delta)
		return
	# a gunman running in with rounds left pulls up short of 3 m - close enough to shoot, not
	# so close he can't - unless he's a brawler who wants it hand to hand
	if path_i < path.size() and gun == "colt" and cylinder > 0 and not jammed and not reloading and p("brawl") < 0.6 and stance in ["rush", "advance", "hunt"]:
		var ahead := _nearest_enemy_alive(4.2)
		if ahead != null and flat_dist(ahead.global_position) > NO_SHOOT and visible_enemies.has(ahead):
			_stop()
	if wrestle_t >= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		if wrestle_with != null and is_instance_valid(wrestle_with):
			face_toward(wrestle_with.global_position, delta)
	else:
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


# ---------------------------------------------------------------- the rule script

## What a rule condition sees. Everything here is something the man could know.
func rule_value(name: String) -> Variant:
	match name:
		"bleeding": return bleed > 0.0
		"reloading": return reloading
		"jammed": return jammed
		"dry": return total_ammo() == 0 and not reloading
		"wounded": return stats["wounds"].size() > 0
		"leg_hit": return legs_hit() > 0
		"arm_hit": return arms_hit() > 0
		"pinned": return suppression > 0.75
		"has_bottle": return has_bottle and held_kind == "bottle"
		"holding": return has_bottle
		"near_chair": return saloon.chair_within(global_position, 7.0) != null
		"near_knife": return saloon.knife_within(global_position, 7.0) != null
		"has_knife": return has_bottle and held_kind == "knife"
		"clinch": return _nearest_enemy_alive(CLINCH) != null
		"close": return _close_enemy() != null
		"wrestling": return wrestle_t >= 0.0
		"near_bottle": return saloon.bottle_within(global_position, 7.0) != null
		"edge": return global_position.y > 1.2 and not saloon.fall_edge(global_position, 1.2).is_empty()
		"alone":
			for m in brain.members:
				if m != self and m.alive and m.global_position.distance_to(global_position) < 8.0:
					return false
			return true
		"aimed_at":
			for e in visible_enemies:
				if is_instance_valid(e) and e.alive and e.aim_target == self:
					return true
			return false
		"enemy_seen": return visible_enemies.size() > 0
		"enemy_reloading": return brain.empty_contact_near(global_position, 15.0) != null
		"enemy_dry":
			for e in brain.contacts:
				if is_instance_valid(e) and e.alive and brain.is_dry_est(e):
					return true
			return false
		"enemy_high":
			for e in brain.contacts:
				if is_instance_valid(e) and e.alive and float(brain.contacts[e]["pos"].y) > Saloon.HIGH_Y:
					return true
			return false
		"enemy_melee":
			var ne := brain.best_contact_for(self, false)
			return ne != null and ne.melee_first()
		"high": return level() == 1
		"in_cover": return _in_cover()
		"mate_down": return manager.elapsed - brain.mate_down_t < 5.0 and brain.mate_down_pos.distance_to(global_position) < 6.0
		"stalemate": return manager.elapsed - brain.last_action_t() > 5.0
		"outnumbered": return manager.alive_count(team) < manager.alive_count(1 - team)
		"ahead": return manager.alive_count(team) > manager.alive_count(1 - team)
		"even": return manager.alive_count(team) == manager.alive_count(1 - team)
		"sudden_death": return manager.sudden_death
		"super": return grade == "Super"
		"minion": return grade == "Minion"
		"melee": return melee_first()
		"gunman": return gun == "colt"
		"ninja": return family == "ninja"
		"has_stars": return gun == "" and cylinder > 0
		"in_reach": return _nearest_enemy_alive(reach() + 0.2) != null
		"hp": return hp
		"bleed_secs": return hp / bleed if bleed > 0.0 else 999.0
		"ammo": return total_ammo()
		"loaded": return cylinder
		"mates": return manager.alive_count(team)
		"foes": return manager.alive_count(1 - team)
		"diff": return manager.alive_count(team) - manager.alive_count(1 - team)
		"time": return 0.0 if manager.sudden_death else maxf(manager.time_left, 0.0)
		"nearest":
			var c := brain.best_contact_for(self, false)
			return flat_dist(brain.contact_pos(c)) if c != null else 99.0
		"seen": return visible_enemies.size()
		"suppression": return suppression
		"random": return rng.randf() * 100.0
		"speed": return ab_speed
		"smarts": return ab_smarts
	return false


## Run the side's script. True if a rule decided what he does this time.
func _run_script(o: Dictionary) -> bool:
	if script_rules == null or script_rules.rules.is_empty():
		last_rule = ""
		return false
	var tried: Array = []
	for attempt in 4:
		var r := script_rules.first_match(self, tried)
		if r.is_empty():
			last_rule = ""
			return false
		if String(r["action"]) == "default":
			last_rule = "L%d default" % int(r["line"])
			_count_rule(r)
			return false
		if _do_rule(r, o):
			last_rule = "L%d %s" % [int(r["line"]), String(r["action"]) + (" " + String(r["arg"]) if String(r["arg"]) != "" else "")]
			_count_rule(r)
			return true
		tried.append(r["line"])   # couldn't do it: the next rule gets a go
	return false


func _count_rule(r: Dictionary) -> void:
	var k := "L%d: %s" % [int(r["line"]), String(r["text"])]
	stats["rules"][k] = int(stats["rules"].get(k, 0)) + 1


func _do_rule(r: Dictionary, o: Dictionary) -> bool:
	var lock := float(r["lock"])
	var tag := "rule L%d" % int(r["line"])
	match String(r["action"]):
		"hold":
			var oo := o.duplicate()
			oo["role"] = "hold"
			oo["push"] = minf(float(o.get("push", 0.0)), -0.3)
			_choose_spot(oo)
			stance = "hold"
			stance_lock = lock
			mode = tag
			return true
		"advance":
			var oo := o.duplicate()
			oo["role"] = "push"
			oo["push"] = 1.0
			_choose_spot(oo)
			stance = "advance"
			stance_lock = lock
			mode = tag
			return true
		"hide":
			if brain.threat_count() == 0:
				return false
			_enter("hide", tag, lock if lock > 0.0 else 2.0)
			_go_hide()
			return true
		"cower":
			_enter("cower", tag, lock if lock > 0.0 else 2.0)
			_stop()
			return true
		"flank":
			if brain.flanker != null and brain.flanker != self or legs_hit() > 0:
				return false
			var fg := _pick_flank_spot()
			if fg < 0:
				return false
			brain.flanker = self
			flank_goal = fg
			stats["flanks"] += 1
			_enter("flank", tag, lock if lock > 0.0 else 12.0)
			move_mode = "run"
			_go_to(fg, 99.0)
			return true
		"rush":
			var t := _rule_target(String(r["arg"]))
			if t == null or legs_hit() > 0:
				return false
			focus = t
			_enter("rush", tag, lock if lock > 0.0 else 2.0)
			_charge(t)
			return true
		"fall back":
			_enter("fall back", tag, lock if lock > 0.0 else 1.5)
			_go_fallback()
			return true
		"take high":
			if level() == 1 or saloon.high_ids.is_empty():
				return false
			var hp_ := saloon.high_point(global_position.x, brain.side)
			_enter("advance", tag, lock if lock > 0.0 else 2.0)
			move_mode = "run"
			_go_to(saloon.nearest_node(hp_), 50.0)
			return true
		"hunt":
			_enter("hunt", tag, lock)
			_go_to(saloon.nearest_node(brain.enemy_home()), 0.0)
			return true
		"grab knife":
			if has_bottle:
				return false
			var kn: Node3D = saloon.knife_within(global_position, 7.0)
			if kn == null:
				return false
			if flat_dist(kn.position) < 1.6:
				grab_t = 0.3 / ab_speed
				_enter("hold", tag, 0.6)
				return true
			_enter("advance", tag, 2.5)
			_go_to(saloon.nearest_node(kn.position + flat(global_position - kn.position).normalized() * 0.7), 50.0)
			return true
		"grab chair":
			if has_bottle:
				return false
			var ch: Node3D = saloon.chair_within(global_position, 7.0)
			if ch == null:
				return false
			if flat_dist(ch.position) < 1.6:
				grab_t = 0.5 / ab_speed
				_enter("hold", tag, 0.8)
				return true
			var stand := ch.position + flat(global_position - ch.position).normalized() * 0.8
			stand.y = global_position.y
			_enter("advance", tag, 2.5)
			_go_to(saloon.nearest_node(stand), 50.0)
			return true
		"grab bottle":
			if has_bottle:
				return false
			if saloon.bottle_near(global_position, 1.7) != null:
				grab_t = 0.4 / ab_speed
				_enter("hold", tag, 0.8)
				return true
			return _go_for_bottle(7.0)
		"flip table":
			var tb := saloon.table_near(global_position, 4.0)
			if tb == null or brain.threat_count() == 0 or level() != 0:
				return false
			flip_table = tb
			tb.claimed_by = self
			_enter("advance", tag, 1.2)
			move_mode = "sprint"
			var threat := brain.threat_centroid()
			path = PackedVector3Array([tb.position - flat(threat - tb.position).normalized() * 0.95])
			path_ids = PackedInt64Array()
			path_i = 0
			goal_id = -1
			return true
	return false


func _rule_target(which: String) -> Gunman:
	var best: Gunman = null
	var bs := INF
	for e in brain.contacts:
		if not is_instance_valid(e) or not e.alive:
			continue
		var d := flat_dist(brain.contact_pos(e))
		var s := d
		match which:
			"weakest": s = e.hp + d * 0.5 if visible_enemies.has(e) else INF
			"reloading": s = d if brain.is_empty_est(e) and d < 18.0 else INF
			"high": s = d if float(brain.contacts[e]["pos"].y) > Saloon.HIGH_Y else INF
			"aiming": s = d if e.aim_target == self and visible_enemies.has(e) else INF
			"melee": s = d if e.melee_first() else INF
		if s < bs:
			bs = s
			best = e
	return best


# ---------------------------------------------------------------- the brain

func _decide() -> void:
	var o := order()
	var near := _nearest_enemy_alive(reach() + 0.3)
	var contacts := brain.contacts
	# --- a man in your face: fists, or back off if you can still shoot him. Even a cowering
	# man fights when he's grabbed - fight or flight.
	if near != null:
		focus = near
		if p("caution") > 0.75 and hp < 45.0 and p("brawl") < 0.4 and total_ammo() > 0:
			_enter("fall back", "backing off", 0.8)
			_go_fallback()
		else:
			_enter("brawl", "fists up", 0.0)
			if flat_dist(near.global_position) > reach() - 0.1:
				_step_in(near)   # not quite in reach: one more step
			else:
				_stop()
		return
	# --- last guard against a stand-off at arm's length (a wall or rail between, a bad route):
	# after a few seconds he goes round to get at him
	var any_near := _nearest_enemy_alive(3.0)
	if any_near != null and manager.elapsed - last_hurt_t > 1.5 and manager.elapsed - any_near.last_hurt_t > 1.5 and wrestle_t < 0.0:
		_stall_t += 0.5
		if _stall_t > 4.0 and legs_hit() < 2:
			_stall_t = 0.0
			focus = any_near
			_enter("rush", "no more waiting", 2.0)
			_charge(any_near)
			return
	else:
		_stall_t = 0.0
	# --- inside 3 m and out of reach: no shooting here, so close in or make room
	var cl := _close_enemy()
	if cl == null:
		_band_t = 0.0
	if cl != null and not cl.falling and wrestle_t < 0.0 and legs_hit() < 2 and not (has_bottle and stance_lock > 0.0):
		focus = cl
		_band_t += 0.5
		# backing off that gets nowhere (a wall, a corner, a man who follows) turns into a fight
		var keen := minf(_band_t * 0.2, 0.6) + 0.5 * (p("brawl") + p("aggression")) + 0.15 * p("nerve") + (0.35 if melee_first() or total_ammo() == 0 or jammed else 0.0) - (0.25 if cl.melee_first() and not melee_first() else 0.0)
		if has_bottle:
			_enter("hold", "throwing", 0.6)
			_stop()
		else:
			var away := global_position + flat(global_position - cl.global_position).normalized() * 3.2
			var back_id := saloon.nearest_node(away)
			# nowhere to back off to (a wall, the bar, a corner): then it's a fight
			var can_back := back_id >= 0 and flat_dist(saloon.node_pos(back_id)) > 1.5 and saloon.node_pos(back_id).distance_to(cl.global_position) > NO_SHOOT
			# something to throw within a few strides - a knife best of all - is worth the run
			var fetch: Node3D = saloon.throwable_within(global_position, 4.5)
			var fetch_w := 0.0
			if fetch != null and arms_hit() < 2 and legs_hit() == 0:
				fetch_w = 0.55 - 0.08 * flat_dist(fetch.position) + (0.25 if saloon.kind_of(fetch) == "knife" else 0.0) - 0.3 * p("brawl")
			if fetch_w > 0.2 and rng.randf() < fetch_w + 0.25:
				_enter("advance", "running for a %s" % saloon.kind_of(fetch), 1.5)
				move_mode = "sprint"
				path = PackedVector3Array([fetch.position + flat(global_position - fetch.position).normalized() * 0.7 + Vector3(0, global_position.y - fetch.position.y, 0)])
				path_ids = PackedInt64Array()
				path_i = 0
				goal_id = -1
			elif (keen > 0.5 and can_punch()) or legs_hit() > 0 or not can_back:
				_enter("brawl", "closing in", 0.6)
				_step_in(cl)
			else:
				_enter("fall back", "making room to shoot", 0.9)
				move_mode = "run"
				_go_to(back_id, 40.0)
		return
	# --- the side's rule script gets first say (a cowering man isn't reading anything)
	if not (stance == "cower" and stance_lock > 0.0):
		var locked_rule := stance_lock > 0.0 and mode.begins_with("rule")
		if not locked_rule and _run_script(o):
			return
		if locked_rule and _continue_stance(o):
			return
	# --- a lull: nobody hurt for a while and nobody in sight. Sitting in corners ends here - the
	# keen go first, then everybody; a dry man fetches something to throw on the way
	var quiet := manager.quiet_time()
	if quiet > 6.0 and visible_enemies.is_empty() and legs_hit() < 2 and stance != "hunt" and (quiet > 11.0 or p("aggression") + 0.5 * p("nerve") + (0.4 if bleed > 0.0 else 0.0) > 0.7):
		if gun == "colt" and total_ammo() == 0 and not has_bottle and _go_for_bottle(12.0):
			return
		var tgt := _nearest_enemy_alive(99.0)
		if tgt == null:
			for e in manager.alive_gunmen():
				if e.team != team and (tgt == null or flat_dist(e.global_position) < flat_dist(tgt.global_position)):
					tgt = e
		if tgt != null:
			focus = tgt
			_enter("hunt", "flushing them out", 3.0)
			move_mode = "run"
			var where: Vector3 = brain.contact_pos(tgt) if brain.contacts.has(tgt) and quiet < 15.0 else tgt.global_position
			_go_to(saloon.nearest_node(where), 60.0)
			return
	# --- modes that hold a man until they run their course
	if stance_lock > 0.0 and _continue_stance(o):
		return
	# --- the gun is empty for good: 18 rounds and that's your lot
	if total_ammo() == 0 and not reloading and not melee_first():
		if stats["dry_at"] < 0.0:
			stats["dry_at"] = manager.elapsed
			brain.log_event("%s is out of cartridges" % gm_name, false)
			say("out")
		var c := brain.best_contact_for(self, true)
		if not has_bottle and arms_hit() < 2 and _go_for_bottle(7.0):
			return
		if c != null and legs_hit() == 0 and can_punch() and (p("brawl") + p("aggression")) * 0.5 + 0.2 * p("nerve") > 0.42:
			focus = c
			_enter("rush", "fists only", 4.0)
			_charge(c)
		else:
			_enter("hide", "out of rounds", 4.0)
			_go_hide()
		return
	# --- orders to punish a man the team has counted empty
	if legs_hit() == 0 and String(o.get("role", "")) == "punish" and o.get("focus") != null and is_instance_valid(o["focus"]) and (o["focus"] as Gunman).alive:
		focus = o["focus"]
		_enter("rush", "punishing a reload", 3.0)
		_charge(focus)
		return
	# --- own initiative: a counted-out man close by
	var empty := brain.empty_contact_near(global_position, 12.0)
	if empty != null and legs_hit() == 0 and cylinder >= 2 and (p("aggression") + p("brawl")) * 0.5 + rng.randf() * 0.25 > 0.62:
		focus = empty
		_enter("rush", "he's empty - go!", 3.0)
		_charge(empty)
		return
	# --- a blade has to close: go for the nearest man in reach of a run
	if melee_first() and legs_hit() == 0 and arms_hit() < 2:
		var mt := _melee_target()
		if mt != null:
			focus = mt
			_enter("rush", "closing in", 1.2)
			_charge(mt)
			return
	# --- the doctrine says charge
	if legs_hit() == 0 and String(o.get("role", "")) == "push" and float(o.get("push", 0.0)) >= 0.95 and String(o.get("move", "")) == "sprint" and contacts.size() > 0:
		var tgt := brain.best_contact_for(self, true)
		if tgt != null:
			focus = tgt
			_enter("rush", "charging", 2.0)
			_charge(tgt)
			return
	# --- gun jammed: a careful man gets out of sight while he works it free
	if jammed and brain.threat_count() > 0 and p("caution") > 0.4 and stance != "hide":
		_enter("hide", "clearing a jam", jam_t)
		_go_hide()
		return
	# --- bleeding out and knows it: a man with nerve makes it count
	if bleed > 0.0 and hp / bleed < 15.0 and p("nerve") + p("aggression") > 1.0 and legs_hit() == 0 and total_ammo() > 0:
		var lt := brain.best_contact_for(self, false)
		if lt != null:
			focus = lt
			_enter("rush", "last stand", 3.0)
			_charge(lt)
			return
	# --- hurt and losing nerve
	if hp < 45.0 and p("nerve") < 0.5 and rng.randf() < 0.8:
		_enter("fall back", "hurt", 2.0)
		_go_fallback()
		return
	# --- pinned: the careful man gets out of sight altogether, the rest duck where they are
	if suppression > 0.75 and p("nerve") < 0.6:
		if p("caution") > 0.45 or brain.crouch_exposure(goal_id) > 0.01:
			_enter("hide", "pinned down", 1.5 + 2.0 * p("caution"))
			_go_hide()
		else:
			duck_t = maxf(duck_t, 0.8)
		return
	# --- reloading in the open: get out of their eyes first
	if reloading and brain.threat_count() > 0 and brain.stand_sight(saloon.nearest_node(global_position)) > 0.0 and p("discipline") + p("caution") > 0.6:
		_enter("hide", "reloading", 1.5)
		_go_hide()
		return
	# --- nobody known: hunt
	if contacts.is_empty():
		_enter("hunt", "", 0.0)
		move_mode = "sneak" if p("cunning") > 0.5 or p("caution") > 0.6 else "run"
		var z: Vector3 = o.get("zone", brain.enemy_home())
		if o.get("role", "") == "hold" or o.get("role", "") == "guard" or o.get("role", "") == "ambush":
			_choose_spot(o)
			stance = "hunt" if stance != "hold" else stance
		else:
			_go_to(saloon.nearest_node(z.lerp(brain.enemy_home(), 0.5)), 0.0)
		return
	# --- flank: ordered, or a cunning man's own idea when the fight has gone quiet
	var ordered_flank := String(o.get("role", "")) == "flank"
	var stalemate := manager.elapsed - brain.last_action_t() > 5.0
	if (ordered_flank or (stalemate and p("cunning") > 0.45 and rng.randf() < 0.12 + 0.35 * p("cunning"))) and brain.flanker == null and total_ammo() >= 4 and hp > 50.0 and legs_hit() == 0:
		var fg := _pick_flank_spot()
		if fg >= 0:
			brain.flanker = self
			flank_goal = fg
			stats["flanks"] += 1
			_enter("flank", "working round them", 14.0)
			move_mode = "run"
			_go_to(fg, 99.0)
			brain.claim(self, fg)
			brain.log_event("%s slips off to flank" % gm_name, true)
			return
	# --- a table to kick over when there is nothing better nearby
	if flip_table == null and brain.threat_count() > 0 and level() == 0:
		var here_prot := 1.0 - brain.crouch_exposure(saloon.nearest_node(global_position))
		if here_prot < 0.5 and rng.randf() < 0.25 + 0.5 * maxf(p("cunning"), p("caution")):
			var tb := saloon.table_near(global_position, 3.5)
			if tb != null:
				flip_table = tb
				tb.claimed_by = self
				_enter("advance", "kicking over a table", 1.2)
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


## Switch modes. `lock` is how long the new mode holds before ordinary decisions resume.
func _enter(st: String, detail: String, lock: float) -> void:
	if st != stance:
		if stance == "flank" and brain.flanker == self:
			brain.flanker = null
		stance = st
		stance_t = 0.0
		if st == "hide":
			stats["hides"] += 1
		elif st == "rush":
			stats["rushes"] += 1
		elif st == "cower":
			stats["cowers"] += 1
		ambush_ready = false
	stance_lock = maxf(stance_lock, lock) if st == stance and stance_t > 0.0 else lock
	mode = detail if detail != "" else st
	_update_label()


## Keep doing the locked mode; false means it has run its course (or broken) and the man
## should decide afresh.
func _continue_stance(o: Dictionary) -> bool:
	match stance:
		"cower":
			_stop()
			return true
		"hide":
			# break cover early when an enemy walks into the lane: up and already aimed
			for e in visible_enemies:
				if is_instance_valid(e) and e.alive and flat_dist(e.global_position) < 7.0 and total_ammo() > 0 and not reloading:
					ambush_ready = true
					stance_lock = 0.0
					_enter("hold", "ambush!", 0.0)
					return false
			if reloading or suppression > 0.35:
				stance_lock = maxf(stance_lock, 0.4)
			if goal_id >= 0 and brain.stand_sight(goal_id) > 0.0 and path_i >= path.size():
				_go_hide()   # they've moved; so does he
			return true
		"flank":
			if flank_goal < 0 or hp < 45.0 or (manager.elapsed - last_hurt_t < 0.3):
				# spotted and hit on the way round: abort to cover
				brain.flanker = null if brain.flanker == self else brain.flanker
				stance_lock = 0.0
				return false
			if path_i >= path.size() and flat_dist(saloon.node_pos(flank_goal)) < 0.9:
				brain.log_event("%s is round their flank" % gm_name, true)
				brain.flanker = null if brain.flanker == self else brain.flanker
				still_t = 1.0   # settled the moment he arrives
				_enter("hold", "on their flank", 4.0 + 4.0 * p("patience"))
				goal_id = flank_goal
				flank_goal = -1
				return true
			# creep the last stretch
			move_mode = "sneak" if _near_contacts(8.0) else "run"
			if path.is_empty():
				_go_to(flank_goal, 99.0)
			return true
		"rush":
			if focus == null or not is_instance_valid(focus) or not focus.alive:
				stance_lock = 0.0
				return false
			if hp < 35.0 and p("nerve") < 0.6:
				stance_lock = 0.0
				return false
			if path_i >= path.size() or rng.randf() < 0.35:
				_charge(focus)
			return true
		"fall back", "hold", "advance":
			return true
	return false


func _near_contacts(r: float) -> bool:
	for e in brain.contacts:
		if is_instance_valid(e) and e.alive and global_position.distance_to(brain.contacts[e]["pos"]) < r:
			return true
	return false


## Fight or flight's third option. A shock - a near miss, a wound, a mate dropping beside
## him - can freeze a man with no nerve: down on his haunches, arms over his head, no gun up.
## He comes out of it after a second or three, usually to hide.
func _maybe_cower(intensity: float) -> void:
	if not alive or stance == "cower" or cower_cd > 0.0 or stance == "brawl" or knocked_t > 0.0:
		return
	var chance := intensity * pow(1.0 - p("nerve"), 1.6) * (0.4 + 0.6 * p("caution"))
	if rng.randf() >= chance:
		return
	cower_cd = 7.0 + 6.0 * p("nerve")
	aim_target = null
	aim_t = 0.0
	_stop()
	_enter("cower", "cowering", lerpf(3.2, 1.2, p("nerve")) + rng.randf() * 0.8)
	brain.log_event("%s cowers" % gm_name, false)


func _set_mode(m: String) -> void:
	if m != mode:
		mode = m
		_update_label()


func _charge(target: Gunman) -> void:
	move_mode = "sprint"
	var tp := brain.contact_pos(target) if brain.contacts.has(target) else target.global_position
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
	var rt := saloon.route(team, global_position, id, stealthy, jump_cls if legs_hit() == 0 else 0)
	path = rt["pts"]
	path_ids = rt["ids"]
	path_i = 0
	# drop waypoints already behind us
	while path_i < path.size() - 1 and flat_dist(path[path_i]) < 0.9 and _link_at(path_i) == "":
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
	var wd := 0.25 + 1.3 * p("cunning") + 0.6 * ab_smarts + (0.5 * ob if role == "flank" or role == "high" else 0.0)
	var wa := 0.9 * p("aggression") - 0.6 * p("caution") + ob * push * 1.4
	var wz := (1.3 * ob) if zone != Vector3.INF else 0.0
	var wh := 0.9 * p("height") + (1.6 * ob if role == "high" or role == "overwatch_high" else 0.0) - (1.2 * ob if role == "ground" else 0.0)
	var wdist := 0.6 + 0.4 * p("caution") - 0.3 * p("aggression")
	if melee_first():
		# a blade has to get there: close the distance, keep behind something on the way -
		# and against guns, never across open floor: cover to cover, the smarter the safer
		var guns := false
		for e in brain.contacts:
			if is_instance_valid(e) and e.alive and e.gun == "colt" and e.total_ammo() > 0:
				guns = true
				break
		wa += 0.6 if guns else 1.3
		ws *= 0.35 if not throws_stars() else 0.7
		wp += (1.0 + 0.8 * ab_smarts) if guns else 0.4
		wd *= 0.5
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
		s += rng.randf() * lerpf(0.3, 0.03, ab_smarts)
		if id == goal_id:
			cur_s = s + 0.25   # hysteresis: don't dither between two equal spots
			s = cur_s
		if s > best_s:
			best_s = s
			best = id
	if best < 0:
		return
	var label_txt := _role_label(role)
	var bp := saloon.node_pos(best)
	var going_fwd := flat_dist(bp) > 1.2 and Vector2(bp.x - ec.x, bp.z - ec.z).length() < my_d_enemy - 0.5
	_enter("advance" if going_fwd else "hold", label_txt, 0.0)
	move_mode = String(o.get("move", "run"))
	if best != goal_id or path.is_empty() and flat_dist(saloon.node_pos(best)) > 0.6:
		_go_to(best, best_s)
	brain.claim(self, best)


func _role_label(role: String) -> String:
	match role:
		"hold": return "holding"
		"guard": return "guarding the way up"
		"ambush": return "lying in wait"
		"high", "overwatch_high": return "taking the high ground"
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


## Out of every enemy's eye altogether - not just below the top of the cover, but somewhere
## nobody they know about can see even a standing man. Close by, and away from them.
func _go_hide() -> void:
	var ec := brain.threat_centroid()
	var my_d := flat_dist(ec)
	var best := -1
	var best_s := -INF
	for id in saloon.tac_ids:
		var np: Vector3 = saloon.nodes[id]["pos"]
		var d := flat_dist(np) + absf(np.y - global_position.y) * 2.0
		if d > 11.0:
			continue
		var s := -3.0 * brain.stand_sight(id) - 3.0 * brain.crouch_exposure(id) - d / 7.0
		s += (Vector2(np.x - ec.x, np.z - ec.z).length() - my_d) / 12.0
		if saloon.nodes[id]["spot"]:
			s += 0.3
		s -= brain.crowding(id, self)
		if s > best_s:
			best_s = s
			best = id
	move_mode = "sprint" if suppression > 0.4 else "run"
	_go_to(best, best_s)
	brain.claim(self, best)


## Somewhere off to the side of the line between us and them, that is hidden from them
## crouched but from which a man can hit them even when they crouch - the angle that beats
## their cover. Reached the long way round, out of sight.
func _pick_flank_spot() -> int:
	var ec := brain.threat_centroid()
	var tc := brain.team_centroid()
	var axis := flat(ec - tc)
	if axis.length() < 1.0:
		return -1
	axis = axis.normalized()
	var best := -1
	var best_s := 0.15
	for id in saloon.tac_ids:
		var np: Vector3 = saloon.nodes[id]["pos"]
		var d := flat_dist(np)
		if d < 4.0 or d > 20.0:
			continue
		var deny := brain.deny_value(id)
		if deny <= 0.0:
			continue
		var rel := flat(np - tc)
		var lateral := absf(axis.cross(rel).y)            # off to the side of the line
		var to_e := Vector2(np.x - ec.x, np.z - ec.z).length()
		if to_e < 4.0 or to_e > 14.0:
			continue
		var s := 1.4 * deny - 1.6 * brain.crouch_exposure(id) - 0.6 * brain.stand_sight(id) + 0.09 * lateral - d / 30.0
		if int(saloon.nodes[id]["level"]) == 1:
			s += 0.3 * p("height")
		s -= brain.crowding(id, self)
		if s > best_s:
			best_s = s
			best = id
	return best


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


## Walk straight at him - the line between them is clear, no nav needed.
func _step_in(e: Gunman) -> void:
	move_mode = "sprint"
	path = PackedVector3Array([e.global_position])
	path_ids = PackedInt64Array()
	path_i = 0
	goal_id = -1


## The nearest enemy inside 3 m that he could actually get at - nothing solid (the bar, a
## flipped table, a wall) between their knees. Across the bar it's still a gunfight.
func _close_enemy() -> Gunman:
	var best: Gunman = null
	var bd := NO_SHOOT
	for e in manager.alive_gunmen():
		if e.team == team or e.falling:
			continue
		if absf(e.global_position.y - global_position.y) > 1.2:
			continue
		var d := flat_dist(e.global_position)
		if d < bd and saloon.line_clear(global_position + Vector3(0, 0.45, 0), e.global_position + Vector3(0, 0.45, 0)):
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
	spd *= ab_speed
	if legs_hit() == 1:
		spd = minf(spd, RUN) * 0.5    # a limp: no sprinting on that leg
	elif legs_hit() == 2:
		spd = 0.8                     # dragging himself along
	if wounds["gut"] > 0:
		spd *= 0.85
	if reloading:
		spd = minf(spd, RUN * 0.8)
	if stagger_t > 0.0:
		spd *= 0.3
	# a man brawling squares up to his opponent
	var near := focus if focus != null and is_instance_valid(focus) and focus.alive and flat_dist(focus.global_position) < reach() - 0.05 else null
	if flip_table != null:
		if not is_instance_valid(flip_table) or flip_table.flipped and flip_table.claimed_by != self:
			flip_table = null
	if stance == "cower":
		path_i = path.size()
	if near == null and path_i < path.size():
		var wp := path[path_i]
		var to := flat(wp - global_position)
		var last := path_i == path.size() - 1
		if to.length() < (0.25 if last else 0.6) and absf(wp.y - global_position.y) < 1.4:
			path_i += 1
			if path_i >= path.size():
				_arrived()
			else:
				var lt := _link_at(path_i - 1)
				if lt != "":
					_start_trav(lt, path[path_i])
					return
		else:
			want = to.normalized() * spd
	elif flip_table != null and path_i >= path.size():
		_do_flip()
	# a steady man stops to take his shot instead of firing on the run
	if aim_target != null and move_mode != "sprint" and stance != "rush" and stance != "flank" and stance != "fall back" and p("discipline") + 0.3 * p("patience") > 0.4 and want.length() > 0.0:
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
	_check_slip()
	if Vector2(velocity.x, velocity.z).length() < 0.4:
		still_t += delta
	else:
		still_t = 0.0
	# crouch when settled in cover, sneaking, pinned or ducking
	var at_cover: bool = path_i >= path.size() and goal_id >= 0 and saloon.nodes[goal_id]["spot"] and flat_dist(saloon.node_pos(goal_id)) < 0.7
	var want_crouch: bool = (at_cover and not _peeking()) or move_mode == "sneak" and want.length() > 0.1 or duck_t > 0.0 or (suppression > 0.6 and not _peeking())
	if reloading and (at_cover or suppression > 0.3):
		want_crouch = true
	if stance == "cower":
		want_crouch = true
	elif stance == "hide" and want.length() < 0.1:
		want_crouch = true
	elif stance == "rush":
		want_crouch = false
	crouched = want_crouch
	# face: the man we're shooting, else where we're going, else the threat
	if stance == "cower":
		pass
	elif aim_target != null and is_instance_valid(aim_target) and aim_target.alive:
		face_toward(aim_target.global_position, delta, 12.0)
	elif near != null:
		face_toward(near.global_position, delta, 12.0)
	elif want.length() > 0.3:
		face_toward(global_position + want, delta, 8.0)
	elif brain.threat_count() > 0:
		face_toward(brain.threat_centroid(), delta, 4.0)


## Running through a pool of blood: each slick cell he steps into at speed is a chance to go
## down. A careful man creeping, or a man standing, keeps his feet.
func _check_slip() -> void:
	if manager.blood == null:
		return
	var c: Vector3i = manager.blood.cell_of(global_position)
	if c == _last_cell:
		return
	_last_cell = c
	var spd := Vector2(velocity.x, velocity.z).length()
	if spd < 2.2 or not manager.blood.is_slick(global_position):
		return
	var v: float = manager.blood.volume_at(global_position)
	var chance := 0.16 * (spd / 3.9) * clampf(v / Blood.SLICK, 1.0, 2.0) * (1.6 if legs_hit() > 0 else 1.0)
	if rng.randf() < chance:
		stats["slips"] += 1
		brain.log_event("%s slips in the blood!" % gm_name, true)
		manager.sound("thud", global_position + Vector3(0, 0.3, 0), 0.7)
		knock_down(1.1)


func _link_at(i: int) -> String:
	if i < 0 or i + 1 >= path_ids.size():
		return ""
	return saloon.link_type(int(path_ids[i]), int(path_ids[i + 1]))


## Vault, drop, hop, leap or climb along a nav link: a scripted arc, no walking physics.
## A better jumper does it quicker; a ladder is the same slow climb for everyone.
func _start_trav(t: String, to: Vector3) -> void:
	trav_type = t
	trav_from = global_position
	trav_to = to + Vector3(0, 0.02, 0)
	var d := Vector2(to.x - trav_from.x, to.z - trav_from.z).length()
	var dy := to.y - trav_from.y
	var nimble := (1.3 - 0.55 * ab_jump) / ab_speed
	match t:
		"vault":
			trav_h = 0.9
			trav_dur = (0.35 + d * 0.14) * nimble
		"hop":
			trav_h = 0.45
			trav_dur = (0.35 + d * 0.1) * nimble
		"drop":
			trav_h = 0.35
			trav_dur = (0.3 + sqrt(2.0 * maxf(-dy, 0.0) / 9.8)) * clampf(nimble, 0.8, 1.3)
		"leap":
			trav_h = 0.55
			trav_dur = (0.55 + d * 0.08) * nimble
		_:
			trav_h = 0.0
			trav_dur = (0.9 + absf(dy) * 0.35) / ab_speed
	trav_t = 0.0
	crouched = false
	aim_target = null
	velocity = Vector3.ZERO
	collision_mask = 0
	stats["jumps"] += 1
	if t != "climb" and t != "climbdown":
		manager.sound("swing", global_position + Vector3(0, 1.0, 0), 0.7, -10.0)
	face_toward(to, 1.0, 1.0)


func _traverse(delta: float) -> void:
	trav_t += delta
	var u := clampf(trav_t / maxf(trav_dur, 0.05), 0.0, 1.0)
	var p: Vector3
	if trav_type == "climb":
		# up the ladder first, then step off onto the deck
		var cu := clampf(u / 0.8, 0.0, 1.0)
		var su := clampf((u - 0.8) / 0.2, 0.0, 1.0)
		p = Vector3(trav_from.x, lerpf(trav_from.y, trav_to.y, cu), trav_from.z).lerp(trav_to, su)
	elif trav_type == "climbdown":
		var over := Vector3(trav_to.x, trav_from.y, trav_to.z)
		if u < 0.2:
			p = trav_from.lerp(over, u / 0.2)
		else:
			p = Vector3(trav_to.x, lerpf(trav_from.y, trav_to.y, (u - 0.2) / 0.8), trav_to.z)
	elif trav_type == "drop" or trav_type == "fall":
		p = trav_from.lerp(trav_to, u)
		p.y = lerpf(trav_from.y, trav_to.y, u * u) + 4.0 * u * (1.0 - u) * trav_h
	else:
		# rise over the higher end by trav_h, a parabola through take-off and landing
		p = trav_from.lerp(trav_to, u)
		var top := maxf(trav_from.y, trav_to.y) + trav_h
		var straight := lerpf(trav_from.y, trav_to.y, u)
		var lift := 4.0 * u * (1.0 - u) * (top - (trav_from.y + trav_to.y) * 0.5)
		p.y = straight + lift
	global_position = p
	if trav_type == "fall":
		if body_root != null:
			body_root.rotation.x = lerpf(-0.3, -1.5, u)   # over he goes, head first
			body_root.rotation.z = 0.5 * sin(u * 5.0)
		if u >= 1.0:
			_land_fall()
		return
	if body_root != null:
		body_root.rotation.x = -0.35 if trav_type in ["vault", "leap", "hop"] and u < 0.8 else 0.0
	if u >= 1.0:
		trav_t = -1.0
		global_position = trav_to
		collision_mask = Saloon.LAYER_WORLD | Saloon.LAYER_MEN | Saloon.LAYER_MOVE | Saloon.LAYER_SOFT
		if body_root != null:
			body_root.rotation.x = 0.0
		if trav_type == "drop" and trav_from.y - trav_to.y > 2.0:
			manager.sound("thud", global_position, 0.6, -6.0)
			_land_drop(trav_from.y - trav_to.y)
			if not alive:
				return
		path_i += 1
		if path_i >= path.size():
			_arrived()


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
	_enter("hold", "behind the table", 1.5)


func _peeking() -> bool:
	return aim_target != null or peek_hold > 0.0


# ---------------------------------------------------------------- fighting

func _fight(delta: float) -> void:
	# --- fists in close
	var near := _nearest_enemy_alive(reach())
	var grappled := grappled_by != null and is_instance_valid(grappled_by) and grappled_by.alive and manager.elapsed - grappled_t < 1.0 and flat_dist(grappled_by.global_position) < reach() + 0.3
	if punch_wind >= 0.0:
		punch_wind -= delta
		if punch_wind < 0.0:
			_punch_land()
		return
	# --- locked together: nobody shoots, nobody walks off
	if wrestle_t >= 0.0:
		aim_target = null
		wrestle_t -= delta
		if wrestle_with == null or not is_instance_valid(wrestle_with) or not wrestle_with.alive or wrestle_with.falling or wrestle_with.wrestle_with != self:
			_end_wrestle()
		elif wrestle_t < 0.0 and wrestle_lead:
			_resolve_wrestle()
		return
	# --- inside 3 m: no gunplay. In reach it's fists, boots or wrestling; short of that, throw
	# what's in his hand (or grab something) - otherwise he closes in or backs off (_decide)
	var close := _close_enemy()
	if close != null and not close.falling and close.trav_t < 0.0 and knocked_t <= 0.0:
		aim_target = null
		fanning = false
		if flat_dist(close.global_position) <= reach() + 0.15:
			if stagger_t > 0.0 or punch_cd > 0.0 or not facing(close.global_position, 0.0):
				return
			_close_quarters(close)
			return
		if not _bottle_step(delta) and stance == "brawl" and (path_i >= path.size() or path[path.size() - 1].distance_to(close.global_position) > 0.8):
			_step_in(close)
		return
	if near != null:
		# right in front of him: shoot from the hip, or knock his gun aside and hit him? Decided
		# afresh every so often - brawlers, and men whose own gun is on them, go for the fists
		_close_choice_t -= delta
		if _close_choice_t <= 0.0:
			_close_choice_t = 0.7
			var their_gun_on_me := near.aim_target == self and not near.jammed and near.total_ammo() > 0
			_close_fists = rng.randf() < 0.15 + 0.6 * p("brawl") + (0.2 if their_gun_on_me else 0.0) - 0.15 * p("trigger")
		var want_fists := (melee_first() or grappled or cylinder == 0 or jammed or _close_fists or stagger_t > 0.0) and can_punch()
		if want_fists:
			aim_target = null
			# he sees a blow coming: a cool swordsman keeps his guard up and lets it come
			if melee_first() and near.punch_wind >= 0.0 and near.punch_target == self and float(weapon()["block"]) > 0.0:
				if rng.randf() < 0.25 + 0.6 * ab_smarts:
					punch_cd = maxf(punch_cd, near.punch_wind + 0.05)
					return
			if punch_cd <= 0.0 and facing(near.global_position, 0.3):
				var w := weapon()
				punch_target = near
				punch_wind = float(w["wind"]) / ab_speed * (0.55 if _riposte else 1.0)
				_riposte = false
				punch_cd = (float(w["cd"]) - 0.15 * p("brawl")) * (1.0 if arms_hit() == 0 else 1.6) / ab_speed
				stats["punches"] += 1
				manager.sound("swing", global_position + Vector3(0, 1.4, 0), 1.25 if melee == "nunchaku" else 1.0, -6.0)
				if melee_first() and rng.randf() < 0.25:
					say("kiai")
			return
	# --- bottles: off the bar or a table, and at a man's head
	if _bottle_step(delta):
		return
	# --- a jammed gun: work it free
	if jammed:
		aim_target = null
		jam_t -= delta
		if jam_t <= 0.0:
			jammed = false
			manager.sound("load", global_position + Vector3(0, 1.0, 0), 0.8)
			_update_label()
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
				reload_t = ROUND_LOAD * reload_penalty() / ab_speed
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
	# modes that keep the gun down
	if stance == "cower":
		aim_target = null
		aim_t = 0.0
		return
	if stance == "hide" and not ambush_ready:
		aim_target = null
		aim_t = 0.0
		return
	# --- pick a target, aim, fire
	var tgt := _best_target()
	if tgt == null:
		aim_target = null
		aim_t = 0.0
		# with only 18 rounds, suppressing fire is a luxury for a man with plenty left
		if String(order().get("fire", "")) == "suppress" and cylinder > 2 and total_ammo() > 10 and cock_t <= 0.0 and stance != "flank":
			_suppress()
		return
	# a flanker keeps his powder dry until he's round - unless he's spotted or right on them
	if stance == "flank" and tgt.aim_target != self and flat_dist(tgt.global_position) > 6.0:
		aim_target = null
		return
	if tgt != aim_target:
		var reacquire := tgt == last_target and manager.elapsed - last_target_t < 2.5
		aim_target = tgt
		aim_t = 0.0
		if not reacquire:
			consec = 0
		var d := flat_dist(tgt.global_position)
		fanning = gun == "colt" and wounds["arm_r"] == 0 and arms_hit() < 2 and (p("trigger") > 0.45 and d < 7.0 + 5.0 * p("trigger") or (p("trigger") > 0.8 and d < 14.0) or (stance == "rush" and d < 6.0 and p("trigger") > 0.25))
		# already pointed that way: a set man watching his lane, a man coming back up where he
		# ducked, or a hider whose victim walked into him, starts with his aim half settled
		rested = still_t > 0.8 and facing(tgt.global_position, 0.6)
		if rested or reacquire:
			aim_t = 0.35
		if ambush_ready:
			aim_t = 0.55
			ambush_ready = false
	if stagger_t > 0.0:
		return
	aim_need = _want_aim(tgt)
	var rate := 1.0 - 0.4 * minf(suppression, 1.0)
	if is_moving():
		rate *= 0.45   # you can't settle a front sight at a run
	aim_t += delta * rate * ab_speed
	if aim_t >= aim_need and cock_t <= 0.0:
		_fire(tgt)


## How long he means to aim before he squeezes. Every extra moment tightens the shot (see
## aim_spread); the question is how long he dares. Patience buys time; a gun pointed back at
## him, a man close enough to reach him, or wounds take it away. A man getting low on his
## 18 rounds takes more care with each.
func _want_aim(tgt: Gunman) -> float:
	if fanning:
		return 0.1
	var t := clampf(0.22 + 1.05 * p("patience") - 0.25 * p("trigger"), 0.15, 1.4)
	var d := flat_dist(tgt.global_position)
	if tgt.aim_target == self and tgt.aim_t > 0.2 and not tgt.reloading:
		t *= lerpf(0.4, 0.85, p("nerve"))      # he's on me - get it off first
	if d < 5.0:
		t *= 0.6
	if (tgt.reloading or tgt.total_ammo() == 0) and d > 6.0:
		t *= 1.35                               # he can't shoot back: make it count
	if hp < 35.0:
		t *= 0.8
	if wounds["arm_r"] > 0:
		t *= 1.3   # off hand: he knows he needs longer
	if stance == "rush":
		t *= 0.6
	if script_rules != null:
		t *= script_rules.aim_mult
	t *= 1.0 + 0.5 * (1.0 - float(total_ammo()) / total_rounds()) * p("discipline")
	if gun == "":
		t *= 0.6   # a star is thrown, not aimed down a barrel
	# a cool head: takes his time when nobody's on him, gets it off when somebody is
	t *= lerpf(1.0, 1.15, ab_smarts) if tgt.aim_target != self else lerpf(1.0, 0.8, ab_smarts)
	return t


## Spread multiplier for a shot loosed after aiming for `t` seconds: a snap shot is about
## three times as wide as a settled one; a second of aim gets most of the way there.
static func aim_spread(t: float) -> float:
	return 1.0 + 2.2 * exp(-t / AIM_TAU)


func _in_cover() -> bool:
	return goal_id >= 0 and saloon.nodes[goal_id]["spot"] and flat_dist(saloon.node_pos(goal_id)) < 0.9


func _start_reload() -> void:
	reloading = true
	reload_t = (ROUND_LOAD + 0.25) * reload_penalty() / ab_speed   # flip the gate, punch the empties
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
	thr += 0.15 * (1.0 - float(total_ammo()) / total_rounds()) * p("discipline")
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
		if gun == "" and d > 16.0:
			continue
		var pd := clampf(1.25 - d / ((20.0 if gun == "colt" else 13.0) * (0.75 + 0.25 * ab_aim)), 0.15, 1.0) * expo
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
		var tol := 0.6 + along * _expected_sigma() * 2.5
		if r.x < tol:
			return true
	return false


## Roughly how wide his next shot will be - fanning, off-hand, on the move - so the lane check
## clears enough room for his mates.
func _expected_sigma() -> float:
	var s := BASE_SIGMA * gun_hand_penalty()
	s *= 3.0 if fanning else aim_spread(aim_need)
	if is_moving():
		s *= 2.0
	return s


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
	if _close_enemy() != null:
		aim_target = null
		return
	crouched = false
	# the hammer falls - and sometimes nothing happens. Fighting with a man at arm's length,
	# hanging on your wrist, it happens a good deal more.
	var scuffle := (grappled_by != null and is_instance_valid(grappled_by) and manager.elapsed - grappled_t < 1.2) or flat_dist(tgt.global_position) < reach()
	if gun == "colt" and rng.randf() < MISFIRE + (JAM_SCUFFLE if scuffle else 0.0):
		_jam("misfire" if not scuffle else "jammed in the scuffle")
		return
	var sigma := BASE_SIGMA
	if is_moving():
		# a cool hand shoots nearly as well on the move; a greenhorn sprays
		var mv: float = {"sprint": 2.8, "run": 2.0, "sneak": 1.5}.get(move_mode, 2.0)
		sigma *= 1.0 + (mv - 1.0) * (1.3 - ab_smarts)
	if tgt.is_moving():
		sigma *= 1.25
	sigma *= 1.0 + suppression * 1.2
	sigma *= gun_hand_penalty()
	sigma /= ab_aim
	var shot_aim := aim_t
	stats["fan"] = int(stats.get("fan", 0)) + (1 if fanning else 0)
	stats["mv"] = int(stats.get("mv", 0)) + (1 if is_moving() else 0)
	stats["sup"] = float(stats.get("sup", 0.0)) + suppression
	stats["sig"] = float(stats.get("sig", 0.0)) + sigma
	stats["dsum"] = float(stats.get("dsum", 0.0)) + flat_dist(tgt.global_position)
	if fanning:
		sigma *= 3.0 - 1.2 * ab_smarts
		shot_aim = 0.0
	else:
		sigma *= aim_spread(aim_t / (1.0 if wounds["arm_r"] == 0 else 1.7))
	var res := manager.throw_star(self, _aim_point(tgt), sigma) if gun == "" else manager.fire_bullet(self, _aim_point(tgt), sigma)
	cylinder -= 1
	consec += 1
	var b := 0
	while b < AIM_BUCKETS.size() and shot_aim >= float(AIM_BUCKETS[b]):
		b += 1
	var dist := flat_dist(tgt.global_position)
	var rb := 0 if dist < 7.0 else (1 if dist < 14.0 else 2)
	stats["aimb"][b][0] += 1
	stats["aimr"][rb * 4 + b][0] += 1
	stats["aim_sum"] += shot_aim
	var hit_m = res.get("hit")
	if hit_m != null and (hit_m as Gunman).team != team:
		stats["aimb"][b][1] += 1
		stats["aimr"][rb * 4 + b][1] += 1
	cock_t = (FAN if fanning else COCK + 0.1 * (1.0 - p("trigger")) + (0.25 if wounds["arm_r"] > 0 else 0.0)) / ab_speed
	if gun == "":
		cock_t = 0.45 / ab_speed
	aim_t = 0.0 if fanning else aim_t * 0.4   # recoil: the sight comes back on, not all the way
	peek_hold = 0.3 + 1.2 * p("nerve") * (1.0 - p("caution"))
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
	manager.fire_bullet(self, tp, BASE_SIGMA * 3.0)
	stats["aimb"][0][0] += 1
	cylinder -= 1
	cock_t = COCK + 0.25
	peek_hold = 0.4
	_flash()


func _flash() -> void:
	if flash_mi != null:
		flash_mi.visible = true
		_flash_t = 0.06


func _jam(why: String) -> void:
	jammed = true
	jam_t = JAM_CLEAR * reload_penalty() * rng.randf_range(0.8, 1.3) / ab_speed
	aim_target = null
	aim_t = 0.0
	stats["jams"] += 1
	manager.sound("click", global_position + Vector3(0, 1.2, 0), 0.8, 2.0)
	brain.log_event("%s's gun %s" % [gm_name, "jams" if why != "knocked" else "is knocked out of line"], false)
	_update_label()


func _punch_land() -> void:
	var e := punch_target
	punch_target = null
	if e == null or not is_instance_valid(e) or not e.alive:
		return
	if flat_dist(e.global_position) > reach() + 0.25 or not facing(e.global_position, 0.2):
		return
	var dir := flat(e.global_position - global_position).normalized()
	# the other man's defence: he has to see it coming, and be free to act
	if e.facing(global_position, 0.3) and e.knocked_t <= 0.0 and e.punch_wind < 0.0 and e.trav_t < 0.0 and e.stance != "cower":
		var dodge := 0.06 + 0.2 * e.ab_jump * clampf(e.ab_speed / 1.2, 0.6, 1.2) + 0.08 * e.p("caution")
		if e.legs_hit() > 0:
			dodge *= 0.3
		var block := float(e.weapon()["block"]) * (0.7 + 0.3 * e.ab_smarts) * (1.0 - 0.3 * ab_smarts) * (1.0 if e.arms_hit() == 0 else 0.35)
		if rng.randf() < dodge:
			blow = ""
			e.stats["dodges"] += 1
			e.velocity += dir * 3.5
			manager.sound("swing", e.global_position + Vector3(0, 1.2, 0), 0.8, -8.0)
			return
		if rng.randf() < block:
			blow = ""
			e.stats["blocks"] += 1
			e._riposte = true
			e.punch_cd = minf(e.punch_cd, 0.05)
			var steel: bool = melee == "katana" or e.melee == "katana"
			manager.sound("clang" if steel else "thud", e.global_position + Vector3(0, 1.3, 0), rng.randf_range(0.9, 1.15), -2.0)
			if rng.randf() < 0.12 + 0.35 * e.ab_smarts:
				# a parry: his blow turned aside and him left open
				e.stats["parries"] += 1
				stagger_t = 0.45
				punch_cd = maxf(punch_cd, 0.6)
			return
	stats["punch_hits"] += 1
	e.grappled_by = self
	e.grappled_t = manager.elapsed
	e.stagger_t = 0.3
	# a blow into a man who has his gun up: knock it aside, maybe jam it
	if (e.aim_target != null or e.peek_hold > 0.0) and not e.jammed and e.total_ammo() > 0:
		e.aim_target = null
		e.aim_t = 0.0
		if e.gun == "colt" and rng.randf() < PUNCH_JAM * punch_power():
			stats["gun_knocks"] += 1
			e._jam("knocked")
	if blow == "kick":
		blow = ""
		stats["kick_hits"] += 1
		manager.sound("thud", e.global_position + Vector3(0, 1.0, 0), 0.75, 1.0)
		# the boot: in the gut or the knee, and it drives him back a stride
		var knee := rng.randf() < 0.22
		var broke := knee and rng.randf() < 0.25 * punch_power()
		e.velocity += dir * (3.0 + 1.5 * ab_jump)
		e.take_damage((9.0 + 5.0 * ab_jump) * punch_power(), "kick", self, ("leg_r" if rng.randf() < 0.5 else "leg_l") if broke else "bruise", dir)
		if e.alive and not e.falling and e.knocked_t <= 0.0 and rng.randf() < 0.28 + 0.25 * ab_jump + (0.25 if e.legs_hit() > 0 else 0.0):
			stats["knockdowns"] += 1
			e.knock_down(1.3)
		return
	var w := weapon()
	var kd := rng.randf() < float(w["kd"]) * punch_power() * (1.0 + 0.6 * p("brawl")) + (0.25 if e.legs_hit() > 0 else 0.0)
	match melee:
		"katana":
			# where the cut lands: a better swordsman finds the throat and the heart more often
			stats["melee_hits"] += 1
			var vital := 0.07 + 0.1 * ab_smarts + 0.04 * p("brawl")
			var r := rng.randf()
			var part := "gut"
			if r < vital * 0.6:
				part = "head"
			elif r < vital:
				part = "heart"
			elif r < vital + 0.34:
				part = "gut"
			elif r < vital + 0.58:
				part = "arm_r" if rng.randf() < 0.5 else "arm_l"
			else:
				part = "leg_r" if rng.randf() < 0.5 else "leg_l"
			var dmg: float = {"head": 999.0, "heart": 999.0, "gut": 24.0}.get(part, 12.0) * punch_power()
			manager.sound("thud", e.global_position + Vector3(0, 1.3, 0), 1.4, -2.0)
			e.take_damage(dmg, "blade", self, part, dir)
		"nunchaku", "staff":
			stats["melee_hits"] += 1
			var r := rng.randf()
			var legs := 0.3 if melee == "staff" else 0.18
			var head_p := 0.28 if melee == "nunchaku" else 0.2
			manager.sound("thud", e.global_position + Vector3(0, 1.3, 0), 1.15 if melee == "nunchaku" else 0.9)
			if r < head_p:
				e.take_damage(22.0 * punch_power(), "blunt", self, "head_blunt", dir)
				if e.alive and not e.falling:
					e.knock_down(1.5)   # rung like a bell
				kd = false
			elif r < head_p + legs:
				var leg := "leg_r" if rng.randf() < 0.5 else "leg_l"
				var broke := rng.randf() < 0.3 * punch_power()
				e.take_damage(10.0 * punch_power(), "blunt", self, leg if broke else "bruise", dir)
				kd = kd or melee == "staff"
			elif r < head_p + legs + 0.15:
				var arm := "arm_r" if rng.randf() < 0.5 else "arm_l"
				var broke2 := rng.randf() < 0.3 * punch_power()
				e.take_damage(10.0 * punch_power(), "blunt", self, arm if broke2 else "bruise", dir)
			else:
				e.take_damage(float(w["dmg"]) * punch_power(), "blunt", self, "bruise", dir)
		_ when has_bottle and held_kind == "knife":
			# the knife, close: in under the ribs - a better man finds the heart
			stats["melee_hits"] += 1
			var r := rng.randf()
			var vital := 0.1 + 0.12 * ab_smarts
			var kpart := "gut"
			if r < vital:
				kpart = "heart"
			elif r < vital + 0.45:
				kpart = "gut"
			elif r < vital + 0.75:
				kpart = "arm_r" if rng.randf() < 0.5 else "arm_l"
			else:
				kpart = "leg_r" if rng.randf() < 0.5 else "leg_l"
			manager.sound("thud", e.global_position + Vector3(0, 1.2, 0), 1.3, -3.0)
			e.take_damage({"heart": 999.0, "gut": 22.0}.get(kpart, 10.0) * punch_power(), "knife", self, kpart, dir)
			kd = false
		_ when has_bottle:
			# the bottle (or the chair) over his head
			var was := held_kind
			_drop_bottle()
			held_kind = ""
			stats["bottle_hits"] += 1
			if was == "chair":
				manager.sound("wood", e.global_position + Vector3(0, 1.6, 0), 0.7, 3.0)
				manager.sound("thud", e.global_position + Vector3(0, 1.5, 0), 0.7, 0.0)
			else:
				manager.sound("smash", e.global_position + Vector3(0, 1.7, 0))
				manager.glass(e.global_position + Vector3(0, 1.7, 0))
			e.take_damage((20.0 if was == "chair" else 16.0) * punch_power(), "chair" if was == "chair" else "bottle", self, "head_blunt", dir)
			if e.alive and e.knocked_t <= 0.0 and not e.falling:
				e.knock_down(1.6)
			kd = false
		_:
			var dmg2 := (12.0 + 5.0 * p("brawl")) * punch_power()
			manager.sound("thud", e.global_position + Vector3(0, 1.4, 0))
			e.take_damage(dmg2, "fists", self, "fists", dir)
	if kd and e.alive and e.knocked_t <= 0.0 and not e.falling:
		stats["knockdowns"] += 1
		e.knock_down(1.3)


## Who a blade-man goes for: the nearest enemy he can see, if he's close enough to be worth the
## run. A cautious man won't run at a loaded gun pointed at him from across the room - he works
## round through cover instead.
func _melee_target() -> Gunman:
	var best: Gunman = null
	var bd := 5.5 + 5.0 * p("aggression") + 2.0 * ab_speed
	for e in visible_enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var d := flat_dist(e.global_position) + absf(e.global_position.y - global_position.y) * 2.0
		if d > bd:
			continue
		# a loaded gun watching him across open floor is death; wait for it to look away, run
		# dry, reload or jam - or get so close he can reach it first
		var guns_on := 0
		for o in visible_enemies:
			if is_instance_valid(o) and o.alive and o.gun == "colt" and o.cylinder > 0 and not o.reloading and not o.jammed and o.facing(global_position, 0.5):
				guns_on += 1
		var reach_first := 3.0 + 2.0 * ab_speed * (1.0 - 0.6 * ab_smarts) + 2.0 * p("aggression") * (1.0 - ab_smarts)
		if guns_on > 0 and d > reach_first:
			continue
		bd = d
		best = e
	return best


# ---------------------------------------------------------------- inside 3 feet

## Chest to chest there's no room to level a Colt: a man punches, kicks or grabs hold. A blade-
## or staff-man still swings (short), and kicks. Every so often he picks afresh.
func _close_quarters(e: Gunman) -> void:
	var fists := can_punch()
	var legs := legs_hit() == 0
	# about 70% blows, 30% grabbing him and throwing him - a better brawler throws more
	var w_wrestle := 0.0
	if not melee_first() and arms_hit() < 2 and e.wrestle_t < 0.0 and wrestle_t < 0.0:
		w_wrestle = 0.18 + 0.25 * p("brawl") + 0.06 * (ab_speed - 1.0) * 5.0
	var strikes := 1.0 - w_wrestle
	var w_kick := strikes * (0.2 + 0.25 * ab_jump + (0.15 if family == "ninja" else 0.0)) if legs else 0.0
	var w_punch := (strikes - w_kick) if fists else 0.0
	if melee_first():
		w_punch = 0.65   # the blade, close
	var tot := w_punch + w_kick + w_wrestle
	if tot <= 0.0:
		return   # nothing left to fight with: he can only hang on
	var r := rng.randf() * tot
	if r < w_wrestle:
		_start_wrestle(e)
		return
	punch_target = e
	if r < w_wrestle + w_kick:
		blow = "kick"
		stats["kicks"] += 1
		punch_wind = 0.36 / ab_speed
		punch_cd = 0.95 / ab_speed
		manager.sound("swing", global_position + Vector3(0, 0.9, 0), 0.8, -6.0)
		if family == "ninja" and rng.randf() < 0.3:
			say("kiai")
		return
	blow = ""
	var w := weapon()
	punch_wind = float(w["wind"]) * (0.8 if melee_first() else 1.0) / ab_speed
	punch_cd = (float(w["cd"]) - 0.15 * p("brawl")) * (1.0 if arms_hit() == 0 else 1.6) / ab_speed
	stats["punches"] += 1
	manager.sound("swing", global_position + Vector3(0, 1.4, 0), 1.25 if melee == "nunchaku" else 1.0, -6.0)


## Grab him: both locked a second or two, no shooting, no walking; then one throws the other.
func _start_wrestle(e: Gunman) -> void:
	stats["wrestles"] += 1
	var t := rng.randf_range(0.9, 1.8)
	wrestle_t = t
	wrestle_with = e
	wrestle_lead = true
	e.wrestle_t = t + 0.5
	e.wrestle_with = self
	e.wrestle_lead = false
	e.aim_target = null
	e.reloading = false
	e.punch_wind = -1.0
	e.punch_target = null
	e.throw_wind = -1.0
	e.grab_t = -1.0
	_stop()
	e._stop()
	# the grab pulls them together
	var gap := flat(e.global_position - global_position)
	if gap.length() > 0.8:
		var pull := gap.normalized() * (gap.length() - 0.75) * 0.5
		global_position += pull
		e.global_position -= pull
	manager.sound("thud", global_position + Vector3(0, 1.2, 0), 0.6, -6.0)
	# a gun between two men wrestling for it goes off - or jams
	for m in [self, e]:
		if m.gun == "colt" and m.cylinder > 0 and not m.jammed and rng.randf() < JAM_SCUFFLE:
			m._jam("jammed in the wrestle")


func _wrestle_strength() -> float:
	return 0.5 + 0.3 * p("brawl") + 0.2 * p("nerve") + 0.35 * (ab_speed - 1.0) + 0.2 * ab_smarts - 0.25 * legs_hit() - 0.2 * arms_hit() - (0.15 if wounds["gut"] > 0 else 0.0) + rng.randf() * 0.5


func _resolve_wrestle() -> void:
	var e := wrestle_with
	var win := _wrestle_strength() >= e._wrestle_strength()
	var top: Gunman = self if win else e
	var bottom: Gunman = e if win else self
	_end_wrestle()
	top.stats["throws"] += 1
	manager.sound("thud", bottom.global_position + Vector3(0, 0.3, 0), 0.6, 2.0)
	var dir := top.flat(bottom.global_position - top.global_position).normalized()
	# over the hip and down, a stride away (if there's floor there)
	var land := bottom.global_position + dir * 1.1
	if saloon.line_clear(bottom.global_position + Vector3(0, 0.4, 0), land + Vector3(0, 0.4, 0)):
		bottom.global_position = land
	bottom.take_damage(9.0 * top.punch_power(), "throw", top, "fists", dir)
	if bottom.alive and not bottom.falling:
		bottom.knock_down(1.6)
		top.punch_cd = 0.15


func _end_wrestle() -> void:
	var e := wrestle_with
	wrestle_t = -1.0
	wrestle_with = null
	if e != null and is_instance_valid(e) and e.wrestle_with == self:
		e.wrestle_t = -1.0
		e.wrestle_with = null


# ---------------------------------------------------------------- bottles

## Bottles are for a man whose Colt is empty or jammed, a ninja out of stars - or a brawler who
## just fancies it. Returns true while the bottle has his hands.
func _bottle_step(delta: float) -> bool:
	if throw_wind >= 0.0:
		throw_wind -= delta
		if throw_target != null and is_instance_valid(throw_target):
			face_toward(throw_target.global_position, delta, 14.0)
		if throw_wind < 0.0:
			_throw_bottle()
		return true
	if grab_t >= 0.0:
		grab_t -= delta
		if grab_t < 0.0:
			var got := saloon.take_throwable(global_position, 1.7)
			if not got.is_empty():
				held_kind = String(got["kind"])
				has_bottle = true
				_show_bottle(true)
				manager.sound("load", global_position + Vector3(0, 1.2, 0), 1.6, -12.0)
				_update_label()
		return true
	if arms_hit() >= 2 or stagger_t > 0.0:
		return false
	if grappled_by != null and is_instance_valid(grappled_by) and manager.elapsed - grappled_t < 1.0:
		return false
	_bottle_cd -= delta
	if has_bottle:
		# he picked it up to throw it - unless he's about to squeeze off an aimed shot
		if aim_target != null and aim_t > 0.25 and not _bottle_time():
			return false
		var t := _bottle_target()
		if t == null:
			return false
		aim_target = null
		throw_target = t
		throw_wind = 0.34 / ab_speed
		manager.sound("swing", global_position + Vector3(0, 1.6, 0), 0.8, -6.0)
		return true
	if _bottle_cd > 0.0:
		return false
	_bottle_cd = 0.35
	# anybody passing a table or the bar with a man in throwing range may pick something up; a
	# brawler likes to, a disciplined man less; inside 3 m (no shooting) everyone does
	var in_band := _close_enemy() != null
	var keen := _bottle_time() or in_band or (aim_target == null and rng.randf() < (0.22 + 0.35 * p("brawl")) * (1.0 - 0.5 * p("discipline")))
	var cand := saloon.throwable_near(global_position, 1.7)
	if not keen or cand.is_empty() or _bottle_target(String(cand["kind"])) == null:
		return false
	aim_target = null
	grab_t = 0.4 / ab_speed
	return true


## No better way to hurt anybody from here: gun dry or jammed, out of stars.
func _bottle_time() -> bool:
	if gun == "colt":
		return (total_ammo() == 0 and not reloading) or jammed
	if loadout_stars > 0:
		return cylinder == 0 and _melee_target() == null
	return _melee_target() == null


func _bottle_target(kind := "") -> Gunman:
	if kind == "":
		kind = held_kind
	var far := 8.0 if kind == "chair" else (11.0 if kind == "knife" else 13.0)
	var best: Gunman = null
	var bv := -INF
	for e in visible_enemies:
		if not is_instance_valid(e) or not e.alive or e.falling:
			continue
		var d := flat_dist(e.global_position)
		if d < reach() + 0.2 or d > far:
			continue
		if not saloon.line_clear(muzzle(), e.global_position + Vector3(0, e.height() * 0.85, 0)):
			continue
		if _mate_near_line(e.chest()):
			continue
		var v := -d + (3.0 if e.aim_target == self else 0.0) + (2.0 if e.reloading or e.jammed else 0.0)
		if v > bv:
			bv = v
			best = e
	return best


func _throw_bottle() -> void:
	var t := throw_target
	throw_target = null
	if not has_bottle:
		return
	var kind0 := held_kind
	_drop_bottle()
	held_kind = kind0
	if t == null or not is_instance_valid(t) or not t.alive:
		held_kind = ""
		return
	var sigma := BASE_SIGMA * 2.0 / ab_aim * gun_hand_penalty() * (1.6 if is_moving() else 1.0) * (1.0 + 0.8 * minf(suppression, 1.0))
	stats["bottles"] += 1
	var kind := held_kind
	held_kind = ""
	if kind == "chair":
		stats["chairs"] = int(stats.get("chairs", 0)) + 1
	if kind == "knife":
		stats["knives"] = int(stats.get("knives", 0)) + 1
	manager.throw_bottle(self, t.global_position + Vector3(0, t.height() * (0.86 if kind == "bottle" else (0.7 if kind == "knife" else 0.6)), 0), sigma * (1.3 if kind == "chair" else (0.8 if kind == "knife" else 1.0)), kind)


## Off a table or the bar within `r`, while there's nobody right on him: go and get it.
func _go_for_bottle(r: float) -> bool:
	if legs_hit() >= 2:
		return false
	var b: Node3D = saloon.bottle_within(global_position, r)
	var ch: Node3D = saloon.chair_within(global_position, r)
	if b == null or (ch != null and flat_dist(ch.position) < flat_dist(b.position)):
		b = ch
	if b == null:
		return false
	if _nearest_enemy_alive(3.0) != null:
		return false
	# stand at the near side of it
	var stand := b.position + flat(global_position - b.position).normalized() * 0.85
	stand.y = global_position.y
	var id := saloon.nearest_node(stand)
	if id < 0 or saloon.node_pos(id).distance_to(stand) > 1.6:
		return false
	_enter("advance", "after a chair" if not (b is MeshInstance3D) else "after a bottle", 2.5)
	move_mode = "run"
	_go_to(id, 50.0)
	return true


var chair_held: Node3D = null


func _show_bottle(on: bool) -> void:
	if body_root == null or arm_l == null:
		return
	if held_kind == "chair" or (not on and chair_held != null):
		if on and chair_held == null:
			chair_held = Saloon.chair_mesh(saloon.mat("wood"), saloon.mat("dark"))
			chair_held.position = Vector3(0, 1.75, -0.35)
			chair_held.rotation = Vector3(PI, 0, 0)
			body_root.add_child(chair_held)
		if chair_held != null:
			chair_held.visible = on
		if held_kind == "chair":
			return
	if held_kind == "knife":
		if on:
			if bottle_mi != null:
				bottle_mi.queue_free()
			bottle_mi = Saloon.knife_mesh(saloon.mat("dark"))
			bottle_mi.position = Vector3(0, -0.66, -0.05)
			arm_l.add_child(bottle_mi)
		elif bottle_mi != null:
			bottle_mi.visible = false
		return
	if bottle_mi != null and bottle_mi.get_child_count() > 0:
		bottle_mi.queue_free()   # a knife was here; make a fresh bottle
		bottle_mi = null
	if on and bottle_mi == null:
		bottle_mi = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.055
		cm.height = 0.3
		cm.radial_segments = 8
		bottle_mi.mesh = cm
		bottle_mi.material_override = saloon.mat("glass_g")
		bottle_mi.position = Vector3(0, -0.62, 0)
		arm_l.add_child(bottle_mi)
	if bottle_mi != null:
		bottle_mi.visible = on


func _drop_bottle() -> void:
	has_bottle = false
	_show_bottle(false)
	_update_label()


# ---------------------------------------------------------------- over the rail

## A man hit at the open edge of a balcony, rafter or roof can go over it: a dead man slumps over
## the rail, a live one is knocked through it. From the balcony the floor kills him.
func _maybe_fall(how: String, by: Gunman, dir: Vector3, fatal: bool) -> bool:
	if falling or trav_t >= 0.0 or global_position.y < 1.2:
		return false
	var shove := how in ["fists", "blunt", "blade", "bottle", "kick", "throw", "chair", "knife"]
	var toward := flat(dir).normalized() if shove and flat(dir).length() > 0.01 else Vector3.ZERO
	# a dying man staggers a step or two before he goes; a blow drives a man back a good stride
	var e := saloon.fall_edge(global_position, 1.5 if fatal else (1.6 if shove else 0.9), toward)
	if e.is_empty():
		return false
	var chance := 0.0
	match how:
		"gun", "star":
			chance = 0.8 if fatal else 0.28
		"fists":
			chance = 0.95 if fatal else 0.3 + 0.25 * (by.punch_power() if by != null and is_instance_valid(by) else 1.0)
		"blunt", "bottle":
			chance = 0.95 if fatal else 0.5
		"kick", "throw", "chair":
			chance = 0.95 if fatal else 0.6
		"blade", "knife":
			chance = 0.9 if fatal else 0.3
	if knocked_t > 0.0 or legs_hit() > 0:
		chance += 0.2
	if rng.randf() >= chance:
		return false
	_start_fall(e, by, how, fatal)
	return true


func _start_fall(e: Dictionary, by: Gunman, how: String, fatal: bool) -> void:
	if wrestle_t >= 0.0:
		_end_wrestle()
	falling = true
	fall_dead = fatal
	fall_by = by
	fall_how = how
	stats["falls"] += 1
	_stop()
	knocked_t = 0.0
	aim_target = null
	reloading = false
	punch_target = null
	punch_wind = -1.0
	throw_wind = -1.0
	grab_t = -1.0
	if has_bottle:
		_drop_bottle()
	if flip_table != null and flip_table.claimed_by == self:
		flip_table.claimed_by = null
	flip_table = null
	if bool(e["rail"]):
		saloon.break_rail(global_position)
		manager.sound("wood", global_position + Vector3(0, 0.9, 0), 0.6, 2.0)
	trav_type = "fall"
	trav_from = global_position
	trav_to = e["to"]
	trav_h = 0.3
	trav_dur = 0.25 + sqrt(2.0 * float(e["drop"]) / 9.8)
	trav_t = 0.0
	velocity = Vector3.ZERO
	collision_mask = 0
	if not fatal:
		say("die")
	brain.log_event("%s goes %s!" % [gm_name, "through the rail" if bool(e["rail"]) else "over the edge"], true)


## Jumped down off a deck on purpose: over 2 m he lands hard and goes down; a better jumper
## less so. It can cost a leg.
func _land_drop(h: float) -> void:
	var sev := maxf(h - 1.8, 0.0) * (1.0 - 0.6 * ab_jump)
	stats["drop_hurts"] = int(stats.get("drop_hurts", 0)) + 1
	hp -= 7.0 * sev
	if rng.randf() < 0.35 * sev:
		var leg := "leg_r" if rng.randf() < 0.5 else "leg_l"
		wounds[leg] += 1
		stats["wounds"].append(leg)
		_wound_visual(leg)
		say("leg")
	if hp <= 0.0:
		hp = 0.0
		stats["death_part"] = "fall"
		stats["death_how"] = "fall"
		_die(null, "fall", Vector3.DOWN)
		return
	knock_down(0.6 + 0.7 * sev)
	_update_label()


## Down. From the balcony (3 m and more) it's the end of him; off a lower roof he's winded,
## maybe with a broken leg.
func _land_fall() -> void:
	falling = false
	trav_t = -1.0
	global_position = trav_to
	collision_mask = Saloon.LAYER_WORLD | Saloon.LAYER_MEN | Saloon.LAYER_MOVE | Saloon.LAYER_SOFT
	if body_root != null:
		body_root.rotation = Vector3.ZERO
	var drop := trav_from.y - trav_to.y
	manager.sound("thud", global_position + Vector3(0, 0.3, 0), 0.5, 3.0)
	manager.sound("wood", global_position + Vector3(0, 0.2, 0), 0.55, -2.0)
	if manager.blood != null:
		manager.blood.pour(global_position, 1.5)
	var by: Gunman = fall_by if fall_by != null and is_instance_valid(fall_by) else null
	if fall_dead or drop >= 3.0:
		if not fall_dead:
			stats["death_part"] = "fall"
			stats["death_how"] = "fall"
			if by != null and by.team != team:
				by.stats["fall_kills"] += 1
		stats["fell"] = true
		hp = 0.0
		_die(by, "fall", (trav_to - trav_from).normalized() * 0.4)
		return
	# a shorter drop: knocked flat; maybe a leg goes
	hp -= 12.0
	if rng.randf() < 0.25 + 0.15 * drop:
		var leg := "leg_r" if rng.randf() < 0.5 else "leg_l"
		wounds[leg] += 1
		stats["wounds"].append(leg)
		_wound_visual(leg)
	if hp <= 0.0:
		hp = 0.0
		stats["death_part"] = "fall"
		stats["death_how"] = "fall"
		_die(by, "fall", Vector3.DOWN)
		return
	knock_down(1.8)
	_update_label()


# ---------------------------------------------------------------- getting hurt

func take_damage(amount: float, how: String, by: Gunman, part: String, dir: Vector3) -> void:
	if not alive or falling:
		return
	hp -= amount
	last_hurt_t = manager.elapsed
	stats["taken"] += amount
	if by != null:
		if by.team == team:
			by.stats["ff"] += amount
		else:
			by.stats["dmg"] += amount
	if wounds.has(part):
		wounds[part] += 1
		stats["wounds"].append(part)
		_wound_visual(part)
		if how != "blunt" and how != "kick":
			bleed += float(BLEED.get(part, 1.2))
			bleed_by = by
		if manager.blood != null:
			manager.blood.pour(global_position + flat(dir) * 0.6, 1.2)   # the spray
		if part.begins_with("leg") and legs_hit() == 2:
			brain.log_event("%s is down on the floor - both legs" % gm_name, true)
	suppression = minf(1.5, suppression + 0.5)
	_hurt_flash()
	if how == "gun" or how == "blade" or how == "star" or how == "knife":
		manager.spray(global_position + Vector3(0, height() * 0.7, 0), dir)
	if how == "star" and part != "head" and part != "heart" and not wounds.has(part):
		bleed += 0.5   # a star in the flesh bleeds even where it hits nothing that matters
		bleed_by = by
	if hp <= 0.0:
		hp = 0.0
		stats["death_part"] = part if how != "fists" else "fists"
		stats["death_how"] = how
		if how != "fists" and part != "head":
			say("die")
		if _maybe_fall(how, by, dir, true):
			return
		_die(by, how, dir)
	else:
		if _maybe_fall(how, by, dir, false):
			_update_label()
			return
		decide_t = minf(decide_t, 0.05)
		brain.member_hit(self, by)
		if how != "fists":
			say("leg" if part.begins_with("leg") else ("arm" if part.begins_with("arm") else ("got" if rng.randf() < 0.55 else "hit")))
			_maybe_cower(0.55 + (0.35 if hp < 40.0 else 0.0))
	_update_label()


## Shout a line, in his own voice. One line at a time per man.
func say(line: String) -> void:
	if manager.headless or manager.sfx == null:
		return
	if manager.elapsed - _voice_t < 1.2 and line != "die":
		return
	_voice_t = manager.elapsed
	if family == "ninja":
		# a ninja doesn't say "my leg" - he grunts, shouts as he strikes, and dies quietly
		match line:
			"kiai": line = "kiai"
			"die": line = "ndie"
			"out": return
			_: line = "nhit"
	elif line == "kiai":
		return
	manager.sfx.voice(line, voice_id, global_position + Vector3(0, 1.7, 0), voice_pitch)


## A red patch where he was hit, and the limb hangs.
func _wound_visual(part: String) -> void:
	if body_root == null:
		return
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.55, 0.05, 0.04)
	var parent: Node3D = null
	var pos := Vector3.ZERO
	match part:
		"arm_r":
			parent = arm_r
			pos = Vector3(0, -0.3, 0)
		"arm_l":
			parent = arm_l
			pos = Vector3(0, -0.3, 0)
		"leg_l":
			parent = leg_l
			pos = Vector3(0, -0.4, 0)
		"leg_r":
			parent = leg_r
			pos = Vector3(0, -0.4, 0)
		"gut":
			parent = body_root.get_node("upper")
			pos = Vector3(0, 1.0, -0.16)
	if parent == null:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.14, 0.2) if part != "gut" else Vector3(0.18, 0.14, 0.04)
	mi.mesh = bm
	mi.material_override = red
	mi.position = pos
	parent.add_child(mi)


func knock_down(t: float) -> void:
	if wrestle_t >= 0.0:
		_end_wrestle()
	blow = ""
	punch_wind = -1.0
	knocked_t = t
	aim_target = null
	reloading = false
	if body_root != null:
		body_root.rotation = Vector3(-1.3, 0, 0)


func suppress(amount: float, by: Gunman) -> void:
	suppression = minf(1.5, suppression + amount * (1.0 - 0.5 * p("nerve")))
	if suppression > 0.9:
		_maybe_cower(0.25 * amount / 0.35)
	if by != null and by.team != team:
		brain.heard_shot_near(by, self)


func _hurt_flash() -> void:
	if torso_mi == null:
		return
	var m := mat_shirt
	var was := m.albedo_color
	m.albedo_color = Color(1, 0.9, 0.9)
	get_tree().create_timer(0.08).timeout.connect(func(): if is_instance_valid(self): m.albedo_color = was)


func _die(by: Gunman, how: String, dir: Vector3) -> void:
	if wrestle_t >= 0.0:
		_end_wrestle()
	alive = false
	stats["alive"] = false
	stats["hp"] = 0.0
	stats["died_at"] = manager.elapsed
	stats["killed_by"] = by.gm_name if by != null else "?"
	if by != null and by.team != team:
		by.stats["kills"] += 1
		if how == "fists" or how == "kick" or how == "throw":
			by.stats["fist_kills"] += 1
		elif how == "blade" or how == "blunt":
			by.stats["melee_kills"] += 1
	collision_layer = 0
	collision_mask = Saloon.LAYER_WORLD
	if flip_table != null and flip_table.claimed_by == self:
		flip_table.claimed_by = null
	if brain.flanker == self:
		brain.flanker = null
	manager.sound("death", global_position + Vector3(0, 1.2, 0))
	if body_root != null:
		_spawn_ragdoll(dir * (5.0 if how == "gun" else 3.0))
	died.emit(self, by, how)


func _spawn_ragdoll(impulse: Vector3) -> void:
	ragdoll = Ragdoll.new()
	get_parent().add_child(ragdoll)
	ragdoll.build(global_transform, mat_shirt, mat_pants, mat_skin)
	if ragdoll.bodies.has("head") and family == "west":
		var hat := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.3
		bc.bottom_radius = 0.3
		bc.height = 0.03
		hat.mesh = bc
		hat.material_override = mat_hat
		hat.position = Vector3(0, 0.2, 0)
		(ragdoll.bodies["head"] as Node3D).add_child(hat)
		if faction == "outlaws":
			_bandana(ragdoll.bodies["head"], 1.3)
		elif ragdoll.bodies.has("torso"):
			_tin_star(ragdoll.bodies["torso"], Vector3(-0.14, 0.15, -0.18))
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
	# a limp: the shot leg barely swings and the body dips onto the good one
	var lw := 0.25 if wounds["leg_l"] > 0 else 1.0
	var rw := 0.25 if wounds["leg_r"] > 0 else 1.0
	body_root.position.y = (absf(sin(_walk_phase)) * -0.07 if legs_hit() == 1 and spd > 0.3 else 0.0)
	body_root.rotation.z = (0.08 * (1.0 if wounds["leg_l"] > 0 else -1.0) if legs_hit() == 1 else 0.0)
	if legs_hit() == 2:
		# down on the boards, dragging himself on his elbows
		leg_l.rotation.x = lerpf(leg_l.rotation.x, -1.45, clampf(delta * 8.0, 0, 1))
		leg_r.rotation.x = lerpf(leg_r.rotation.x, -1.45, clampf(delta * 8.0, 0, 1))
		leg_l.position.y = 0.3
		leg_r.position.y = 0.3
	elif crouched:
		leg_l.rotation.x = lerpf(leg_l.rotation.x, -1.2 + swing * 0.3, clampf(delta * 12.0, 0, 1))
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.3 - swing * 0.3, clampf(delta * 12.0, 0, 1))
		leg_l.position.y = 0.5
		leg_r.position.y = 0.5
	else:
		leg_l.rotation.x = swing * lw
		leg_r.rotation.x = -swing * rw
		leg_l.position.y = 0.85
		leg_r.position.y = 0.85
	# right arm: raised and pointing when aiming or peeking, else down at the side
	if stance == "cower":
		# down on his haunches, both arms wrapped over his hat, shaking
		arm_r.rotation.x = lerpf(arm_r.rotation.x, 2.7, clampf(delta * 10.0, 0, 1))
		arm_l.rotation.x = lerpf(arm_l.rotation.x, 2.7, clampf(delta * 10.0, 0, 1))
		arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.5, clampf(delta * 10.0, 0, 1))
		arm_l.rotation.z = lerpf(arm_l.rotation.z, -0.5, clampf(delta * 10.0, 0, 1))
		upper.rotation.x = lerpf(upper.rotation.x, -0.45, clampf(delta * 8.0, 0, 1))
		upper.position.x = sin(manager.elapsed * 40.0) * 0.015
		return
	arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.0, clampf(delta * 10.0, 0, 1))
	arm_l.rotation.z = lerpf(arm_l.rotation.z, 0.0, clampf(delta * 10.0, 0, 1))
	upper.rotation.x = lerpf(upper.rotation.x, (-0.3 if stance == "rush" and Vector2(velocity.x, velocity.z).length() > 3.0 else 0.0), clampf(delta * 8.0, 0, 1))
	upper.position.x = 0.0
	# the gun hand: the right, unless it's been shot - then the Colt moves to the left
	var gun_arm := arm_r
	var off_arm := arm_l
	if wounds["arm_r"] > 0 and wounds["arm_l"] == 0:
		gun_arm = arm_l
		off_arm = arm_r
		if gun_mi.get_parent() != arm_l:
			gun_mi.reparent(arm_l, false)
			flash_mi.reparent(arm_l, false)
	var aiming := aim_target != null or peek_hold > 0.0
	var target_rx := 1.57 if aiming else (0.35 if reloading else (-0.2 if stance == "hide" else -swing * 0.6))
	if arms_hit() == 2 and aiming:
		target_rx = 0.9   # can't get it any higher
	if stance == "brawl" and not aiming:
		target_rx = 1.2   # fists up
	gun_arm.rotation.x = lerpf(gun_arm.rotation.x, target_rx, clampf(delta * 14.0, 0, 1))
	var off_rx := 0.9 if reloading else (1.2 if stance == "brawl" else swing * 0.6)
	off_arm.rotation.x = lerpf(off_arm.rotation.x, off_rx, clampf(delta * 10.0, 0, 1))
	# a shot arm that isn't holding the gun just hangs
	for side in [["arm_l", arm_l], ["arm_r", arm_r]]:
		if wounds[side[0]] > 0 and side[1] != gun_arm:
			(side[1] as Node3D).rotation.x = lerpf((side[1] as Node3D).rotation.x, 0.05, clampf(delta * 6.0, 0, 1))
			(side[1] as Node3D).rotation.z = lerpf((side[1] as Node3D).rotation.z, 0.12 * (1.0 if side[0] == "arm_l" else -1.0), clampf(delta * 6.0, 0, 1))
	if gun_mi != null:
		gun_mi.visible = gun == "" or total_ammo() > 0 or reloading
	if punch_wind >= 0.0:
		if melee_first():
			# the weapon arm comes over: a cut, a whip of the chain, a thrust of the staff
			var wu := 1.0 - clampf(punch_wind / maxf(float(weapon()["wind"]) / ab_speed, 0.05), 0.0, 1.0)
			gun_arm.rotation.x = lerpf(2.8, 0.9, wu)
			if melee == "staff":
				off_arm.rotation.x = gun_arm.rotation.x
		else:
			off_arm.rotation.x = 1.6
	elif melee_first() and weapon_root != null:
		# blade up and ready when there's a fight on; low otherwise
		var ready := stance in ["brawl", "rush"] or (focus != null and is_instance_valid(focus) and flat_dist(focus.global_position) < 5.0)
		if aim_target == null:
			gun_arm.rotation.x = lerpf(gun_arm.rotation.x, 1.1 if ready else 0.3, clampf(delta * 10.0, 0, 1))
			if melee == "staff":
				off_arm.rotation.x = lerpf(off_arm.rotation.x, 1.0 if ready else 0.4, clampf(delta * 10.0, 0, 1))
	# the boot coming up
	if blow == "kick" and punch_wind >= 0.0:
		var ku := 1.0 - clampf(punch_wind / maxf(0.36 / ab_speed, 0.05), 0.0, 1.0)
		leg_r.rotation.x = lerpf(0.2, 1.5, ku)
		gun_arm.rotation.x = lerpf(gun_arm.rotation.x, 0.6, clampf(delta * 10.0, 0, 1))
	# locked together: leaning in, both arms round him
	if wrestle_t >= 0.0:
		body_root.rotation.x = lerpf(body_root.rotation.x, -0.35, clampf(delta * 10.0, 0, 1))
		arm_l.rotation.x = lerpf(arm_l.rotation.x, 1.3, clampf(delta * 12.0, 0, 1))
		arm_r.rotation.x = lerpf(arm_r.rotation.x, 1.3, clampf(delta * 12.0, 0, 1))
		arm_l.rotation.z = 0.0
		arm_r.rotation.z = 0.0
	elif knocked_t <= 0.0 and trav_t < 0.0 and not falling and absf(body_root.rotation.x + 0.35) < 0.02:
		body_root.rotation.x = 0.0


var _celebrate_phase := 0.0


func celebrate() -> void:
	celebrating = true
	_celebrate_t = rng.randf() * 0.3
	_celebrate_phase = rng.randf() * 1.6
	aim_target = null
	crouched = false
	velocity = Vector3.ZERO
	stance = "hold"
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
	# shots into the air and bottles flung up, over and over, with a jig between
	var beat_t := fmod(t + _celebrate_phase, 1.6)
	var prev_t := fmod(t - delta + _celebrate_phase, 1.6)
	var shoot := beat_t < 0.6
	arm_r.rotation.x = lerpf(arm_r.rotation.x, 3.0 if shoot or gun == "" else 2.6, clampf(delta * 8.0, 0, 1))
	if gun == "colt" and prev_t < 0.3 and beat_t >= 0.3:
		_flash()
		manager.sound("shot", global_position + Vector3(0, 2.2, 0), rng.randf_range(0.95, 1.08), -4.0)
	if prev_t < 0.95 and beat_t >= 0.95:
		if family == "west":
			arm_l.rotation.x = 3.0
			manager.toss_bottle(global_position + Vector3(-0.2, 2.0, 0), rng)
		else:
			say("kiai")
	if t < 0.8:
		pass
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
