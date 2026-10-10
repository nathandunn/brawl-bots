class_name Saloon
extends Node3D
## The room: floor, walls, a balcony along the back wall reached by a stair at each end, a bar,
## a piano, posts, barrels, crates and a dozen tables that can be kicked over into cover.
## Mirror-symmetric about x = 0 so neither side starts with the better ground.
##
## Also owns the navigation graph (a 1 m grid on the floor and the balcony, stitched together by
## the two stairs) and the cover spots - places hugging a piece of furniture where a man can
## crouch - which the team brains score against known enemies.

const LAYER_WORLD := 1        # blocks bullets and men
const LAYER_MEN := 2
const LAYER_RAGDOLL := 16
const LAYER_MOVE := 32        # blocks men only (the footprint of an upright table)
const LAYER_SOFT := 64        # balusters: men can't walk through, eyes see through, slugs stop half the time
const SOFT_STOP := 0.5

const HALF_X := 15.0
const HALF_Z := 10.0
const BALC_Y := 3.25
const BALC_Z := -6.5          # balcony front edge; the balcony is z in [-10, -6.5]
const STAIR_X := 14.1         # stair centre line at x = +-14.1
const STAIR_HW := 0.8
const STAIR_BOT_Z := 2.0
const STAIR_TOP_Z := -6.5
const CLEAR := 0.42           # body radius + a whisker
const RAIL_H := 0.9

## obstacles per level: {kind, c: Vector2, half: Vector2 | r: float, h: float, level, cover, name}
var obstacles: Array[Dictionary] = []
var tables: Array[Table] = []
var bottles: Array[MeshInstance3D] = []

## navigation
var astar := AStar3D.new()            # plain distances
var team_astar: Array[AStar3D] = []   # per team, weighted by exposure to known enemies
var nodes: Array[Dictionary] = []     # id -> {pos, level, spot, tac, cover_h, normal, name}
var tac_ids: PackedInt32Array = []    # nodes the team brains score (spots + a sparse grid)
var spot_ids: PackedInt32Array = []
var stair_top: Array[int] = [-1, -1]  # [west, east]
var stair_bottom: Array[int] = [-1, -1]
var stair_ids: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]

var _mats := {}


func _ready() -> void:
	_build_materials()
	_build_shell()
	_build_furniture()
	_build_stairs()
	_build_nav()


# ---------------------------------------------------------------- materials

func _mat(name: String, c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	_mats[name] = m
	return m


func _build_materials() -> void:
	_mat("floor", Color(0.42, 0.29, 0.18))
	_mat("floor2", Color(0.36, 0.24, 0.15))
	_mat("wall", Color(0.55, 0.42, 0.3))
	_mat("dark", Color(0.24, 0.15, 0.09))
	_mat("wood", Color(0.5, 0.33, 0.19))
	_mat("bar", Color(0.33, 0.2, 0.11), 0.5)
	_mat("brass", Color(0.8, 0.65, 0.3), 0.3)
	_mat("felt", Color(0.15, 0.35, 0.2))
	_mat("piano", Color(0.12, 0.08, 0.06), 0.35)
	_mat("keys", Color(0.92, 0.9, 0.85))
	_mat("barrel", Color(0.45, 0.28, 0.15))
	_mat("hoop", Color(0.2, 0.2, 0.22), 0.4)
	_mat("crate", Color(0.62, 0.48, 0.3))
	_mat("glass_g", Color(0.25, 0.55, 0.3, 0.8), 0.1)
	_mat("glass_b", Color(0.45, 0.3, 0.12, 0.8), 0.1)
	_mat("door", Color(0.3, 0.19, 0.1))
	_mat("lamp", Color(1.0, 0.85, 0.5))
	(_mats["lamp"] as StandardMaterial3D).emission_enabled = true
	(_mats["lamp"] as StandardMaterial3D).emission = Color(1.0, 0.8, 0.45)
	(_mats["lamp"] as StandardMaterial3D).emission_energy_multiplier = 2.0
	for k in ["glass_g", "glass_b"]:
		(_mats[k] as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func mat(name: String) -> Material:
	return _mats[name]


# ---------------------------------------------------------------- building blocks

func _box(size: Vector3, pos: Vector3, m: String, layer := LAYER_WORLD, collide := true) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	sb.position = pos
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mats[m]
	sb.add_child(mi)
	add_child(sb)
	return sb


func _deco_box(size: Vector3, pos: Vector3, m: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mats[m]
	mi.position = pos
	add_child(mi)
	return mi


func _cyl(r: float, h: float, pos: Vector3, m: String, layer := LAYER_WORLD) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	sb.position = pos
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = _mats[m]
	sb.add_child(mi)
	add_child(sb)
	return sb


func _rect_obs(c: Vector2, half: Vector2, h: float, level: int, cover: bool, name: String) -> void:
	obstacles.append({"kind": "rect", "c": c, "half": half, "h": h, "level": level, "cover": cover, "name": name})


func _circ_obs(c: Vector2, r: float, h: float, level: int, cover: bool, name: String) -> void:
	obstacles.append({"kind": "circle", "c": c, "r": r, "h": h, "level": level, "cover": cover, "name": name})


func level_y(level: int) -> float:
	return BALC_Y if level == 1 else 0.0


# ---------------------------------------------------------------- the room

func _build_shell() -> void:
	# floor: planks in two tones
	_box(Vector3(HALF_X * 2 + 1, 0.4, HALF_Z * 2 + 1), Vector3(0, -0.2, 0), "floor")
	for i in range(-14, 15, 2):
		_deco_box(Vector3(1.0, 0.01, HALF_Z * 2), Vector3(i + 0.5, 0.005, 0), "floor2")
	# walls: the back wall is full height; the sides are full height only where the balcony
	# and stairs need them, and waist-high elsewhere so the camera can see in
	_box(Vector3(HALF_X * 2 + 0.6, 7.0, 0.3), Vector3(0, 3.5, -HALF_Z - 0.15), "wall")
	_box(Vector3(HALF_X * 2 + 0.6, 1.0, 0.3), Vector3(0, 0.5, HALF_Z + 0.15), "wall")
	for s in [-1.0, 1.0]:
		var x: float = s * (HALF_X + 0.15)
		var tall_len := (STAIR_BOT_Z + 0.6) + HALF_Z
		_box(Vector3(0.3, 4.6, tall_len), Vector3(x, 2.3, -HALF_Z + tall_len * 0.5), "wall")
		var low_len := HALF_Z - (STAIR_BOT_Z + 0.6)
		_box(Vector3(0.3, 1.0, low_len), Vector3(x, 0.5, HALF_Z - low_len * 0.5), "wall")
	# swinging doors on the west wall, a back door on the east (decoration)
	for s in [-1.0, 1.0]:
		for dz in [-0.45, 0.45]:
			_deco_box(Vector3(0.08, 1.1, 0.85), Vector3(s * (HALF_X - 0.05), 1.1, 6.0 + dz), "door")
	# balcony doors (the rooms upstairs) on the back wall
	for x in [-9.0, -3.0, 3.0, 9.0]:
		_deco_box(Vector3(1.2, 2.2, 0.06), Vector3(x, BALC_Y + 1.1, -HALF_Z + 0.03), "door")
	# balcony slab and its edge beam
	_box(Vector3(HALF_X * 2, 0.25, 3.5), Vector3(0, BALC_Y - 0.125, -HALF_Z + 1.75), "wood")
	# balcony railing (a solid balustrade - low cover for the men upstairs)
	var rail_half := HALF_X - STAIR_HW * 2 - 0.05
	# 0.9 m: a man crouched behind it still shows the crown of his hat to the floor below,
	# so the balcony is strong but not a fortress
	# A balustrade, not a wall: you can see between the balusters, and a slug gets through
	# about half the time - so the balcony is strong ground but not a fortress.
	var rail := StaticBody3D.new()
	rail.collision_layer = LAYER_SOFT
	rail.collision_mask = 0
	var rcs := CollisionShape3D.new()
	var rsh := BoxShape3D.new()
	rsh.size = Vector3(rail_half * 2, RAIL_H, 0.1)
	rcs.shape = rsh
	rail.position = Vector3(0, BALC_Y + RAIL_H * 0.5, BALC_Z)
	rail.add_child(rcs)
	add_child(rail)
	var bx := -rail_half
	while bx <= rail_half:
		_deco_box(Vector3(0.07, RAIL_H, 0.07), Vector3(bx, BALC_Y + RAIL_H * 0.5, BALC_Z), "dark")
		bx += 0.16
	_deco_box(Vector3(rail_half * 2, 0.08, 0.16), Vector3(0, BALC_Y + RAIL_H, BALC_Z), "wood")
	_deco_box(Vector3(rail_half * 2, 0.06, 0.12), Vector3(0, BALC_Y + 0.05, BALC_Z), "wood")
	_rect_obs(Vector2(0, BALC_Z), Vector2(rail_half, 0.05), RAIL_H, 1, false, "railing")
	# posts holding it up
	for x in [-10.0, -4.5, 4.5, 10.0]:
		_box(Vector3(0.3, BALC_Y, 0.3), Vector3(x, BALC_Y * 0.5, BALC_Z - 0.1), "dark")
		_rect_obs(Vector2(x, BALC_Z - 0.1), Vector2(0.15, 0.15), 3.0, 0, true, "post")
	# chandeliers: two lamps over the floor
	for x in [-6.0, 6.0]:
		_deco_box(Vector3(1.2, 0.08, 1.2), Vector3(x, 5.2, 1.5), "brass")
		for dx in [-0.5, 0.5]:
			for dz in [-0.5, 0.5]:
				_deco_box(Vector3(0.14, 0.22, 0.14), Vector3(x + dx, 5.33, 1.5 + dz), "lamp")


func _build_furniture() -> void:
	# the bar along the south side, the shelf of bottles behind it
	_box(Vector3(12.0, 1.15, 0.8), Vector3(0, 0.575, 7.6), "bar")
	_deco_box(Vector3(12.2, 0.06, 0.95), Vector3(0, 1.18, 7.6), "wood")
	_deco_box(Vector3(12.0, 0.05, 0.05), Vector3(0, 0.15, 7.15), "brass")
	_rect_obs(Vector2(0, 7.6), Vector2(6.0, 0.4), 1.15, 0, true, "bar")
	_box(Vector3(12.0, 2.2, 0.4), Vector3(0, 1.1, 9.7), "dark")
	_rect_obs(Vector2(0, 9.7), Vector2(6.0, 0.2), 2.2, 0, false, "shelf")
	var brng := RandomNumberGenerator.new()
	brng.seed = 77
	for row in 2:
		for i in 22:
			var x := -5.6 + i * 0.53 + brng.randf_range(-0.08, 0.08)
			var b := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.035
			cm.bottom_radius = 0.06
			cm.height = 0.32
			cm.radial_segments = 8
			b.mesh = cm
			b.material_override = _mats["glass_g" if brng.randf() < 0.5 else "glass_b"]
			b.position = Vector3(x, 2.36 if row == 0 else 1.45, 9.45)
			add_child(b)
			bottles.append(b)
	# bottles on the bar itself
	for x in [-4.2, -1.1, 0.7, 3.6, 5.1]:
		var b := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.06
		cm.height = 0.32
		b.mesh = cm
		b.material_override = _mats["glass_b"]
		b.position = Vector3(x, 1.37, 7.55)
		add_child(b)
		bottles.append(b)

	# the piano, dead centre under the balcony line
	_box(Vector3(2.0, 1.3, 0.7), Vector3(0, 0.65, -3.8), "piano")
	_deco_box(Vector3(1.7, 0.05, 0.25), Vector3(0, 0.78, -3.35), "keys")
	_rect_obs(Vector2(0, -3.8), Vector2(1.0, 0.35), 1.3, 0, true, "piano")
	# a stove column in the middle of the room
	_cyl(0.32, 3.2, Vector3(0, 1.6, 2.2), "hoop")
	_circ_obs(Vector2(0, 2.2), 0.32, 3.2, 0, true, "stove")

	for s in [-1.0, 1.0]:
		# tables (flippable)
		for p in [Vector2(2.6, -0.8), Vector2(6.5, -3.0), Vector2(9.0, 1.0), Vector2(5.5, 3.8), Vector2(2.7, 5.0), Vector2(10.8, -3.6)]:
			var c := Vector2(p.x * s, p.y)
			var tb := Table.new()
			tb.saloon = self
			tb.position = Vector3(c.x, 0, c.y)
			add_child(tb)
			tables.append(tb)
			_circ_obs(c, 0.62, 0.8, 0, true, "table")
			tb.obstacle_index = obstacles.size() - 1
		# barrels by the spawn and the bar ends
		for p in [Vector2(11.6, 8.6), Vector2(12.5, 8.9), Vector2(8.0, 6.9), Vector2(11.2, 4.8)]:
			var c := Vector2(p.x * s, p.y)
			_barrel(Vector3(c.x, 0, c.y))
			_circ_obs(c, 0.42, 1.05, 0, true, "barrel")
		# crates under the balcony
		for p in [Vector2(7.2, -8.6), Vector2(1.9, -8.8)]:
			var c := Vector2(p.x * s, p.y)
			_box(Vector3(1.0, 1.0, 1.0), Vector3(c.x, 0.5, c.y), "crate")
			_rect_obs(c, Vector2(0.5, 0.5), 1.0, 0, true, "crate")
		# crates and a barrel upstairs
		for p in [Vector2(6.0, -8.9), Vector2(1.6, -8.9)]:
			var c := Vector2(p.x * s, p.y)
			_box(Vector3(1.0, 1.0, 1.0), Vector3(c.x, BALC_Y + 0.5, c.y), "crate")
			_rect_obs(c, Vector2(0.5, 0.5), 1.0, 1, true, "crate")
		var bc := Vector2(10.5 * s, -8.9)
		_barrel(Vector3(bc.x, BALC_Y, bc.y))
		_circ_obs(bc, 0.42, 1.05, 1, true, "barrel")


func _barrel(at: Vector3) -> void:
	_cyl(0.42, 1.05, at + Vector3(0, 0.525, 0), "barrel")
	for y in [0.2, 0.85]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.44
		cm.bottom_radius = 0.44
		cm.height = 0.06
		mi.mesh = cm
		mi.material_override = _mats["hoop"]
		mi.position = at + Vector3(0, y, 0)
		add_child(mi)


## Each stair is a solid wedge (so nothing passes under it) with steps drawn on top and a
## banister on the open side.
func _build_stairs() -> void:
	var run := STAIR_BOT_Z - STAIR_TOP_Z
	for side in 2:
		var s := -1.0 if side == 0 else 1.0
		var x := s * STAIR_X
		var sb := StaticBody3D.new()
		sb.collision_layer = LAYER_WORLD
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := ConvexPolygonShape3D.new()
		var x0 := x - STAIR_HW
		var x1 := x + STAIR_HW
		sh.points = PackedVector3Array([
			Vector3(x0, 0, STAIR_BOT_Z), Vector3(x1, 0, STAIR_BOT_Z),
			Vector3(x0, 0, STAIR_TOP_Z), Vector3(x1, 0, STAIR_TOP_Z),
			Vector3(x0, BALC_Y, STAIR_TOP_Z), Vector3(x1, BALC_Y, STAIR_TOP_Z)])
		cs.shape = sh
		sb.add_child(cs)
		add_child(sb)
		var steps := 13
		for i in steps:
			var z0 := STAIR_BOT_Z - run * float(i) / steps
			var h := BALC_Y * float(i + 1) / steps
			_deco_box(Vector3(STAIR_HW * 2, h, run / steps), Vector3(x, h * 0.5, z0 - run / steps * 0.5), "wood" if i % 2 == 0 else "floor2")
		# banister on the room side
		var bx := x - s * (STAIR_HW + 0.05)
		var ban := StaticBody3D.new()
		ban.collision_layer = LAYER_WORLD
		ban.collision_mask = 0
		var bcs := CollisionShape3D.new()
		var bsh := BoxShape3D.new()
		var slope_len := sqrt(run * run + BALC_Y * BALC_Y)
		bsh.size = Vector3(0.1, 0.9, slope_len)
		bcs.shape = bsh
		ban.add_child(bcs)
		var bmi := MeshInstance3D.new()
		var bbm := BoxMesh.new()
		bbm.size = bsh.size
		bmi.mesh = bbm
		bmi.material_override = _mats["dark"]
		ban.add_child(bmi)
		var ang := atan2(BALC_Y, run)
		ban.position = Vector3(bx, BALC_Y * 0.5 + 0.45, (STAIR_BOT_Z + STAIR_TOP_Z) * 0.5)
		ban.rotation = Vector3(ang, 0, 0)
		add_child(ban)


# ---------------------------------------------------------------- navigation

func _dist_to_obs(p: Vector2, o: Dictionary) -> float:
	var c: Vector2 = o["c"]
	if o["kind"] == "circle":
		return p.distance_to(c) - float(o["r"])
	var half: Vector2 = o["half"]
	var d := (p - c).abs() - half
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0)


func is_clear(p: Vector2, level: int, margin := CLEAR) -> bool:
	if absf(p.x) > HALF_X - margin or p.y > HALF_Z - margin or p.y < -HALF_Z + margin:
		return false
	if level == 1:
		if p.y > BALC_Z - margin:
			return false
	else:
		# the stair wedges
		for s in [-1.0, 1.0]:
			var sx: float = s * STAIR_X
			if absf(p.x - sx) < STAIR_HW + margin and p.y < STAIR_BOT_Z + margin and p.y > STAIR_TOP_Z - margin:
				return false
	for o in obstacles:
		if int(o["level"]) != level:
			continue
		if _dist_to_obs(p, o) < margin:
			return false
	return true


func _seg_clear(a: Vector2, b: Vector2, level: int) -> bool:
	var n := int(ceil(a.distance_to(b) / 0.2))
	for i in range(1, n):
		if not is_clear(a.lerp(b, float(i) / n), level, CLEAR - 0.08):
			return false
	return true


func _add_node(pos: Vector3, level: int, extra := {}) -> int:
	var id := nodes.size()
	var d := {"pos": pos, "level": level, "spot": false, "tac": false, "cover_h": 0.0, "normal": Vector3.ZERO, "name": ""}
	d.merge(extra, true)
	nodes.append(d)
	astar.add_point(id, pos)
	return id


func _build_nav() -> void:
	var grid := {}   # Vector3i(ix, iz, level) -> id
	for level in 2:
		var y := level_y(level)
		for ix in range(-14, 15):
			for iz in range(-9, 10):
				var p := Vector2(float(ix), float(iz))
				if level == 1 and iz > -7:
					continue
				if not is_clear(p, level):
					continue
				var tac := (posmod(ix, 2) == 0 and posmod(iz, 2) == 0) or level == 1
				grid[Vector3i(ix, iz, level)] = _add_node(Vector3(p.x, y, p.y), level, {"tac": tac})
	# grid edges
	for key in grid:
		var k: Vector3i = key
		var id: int = grid[k]
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var nk := Vector3i(k.x + dx, k.y + dz, k.z)
				if not grid.has(nk):
					continue
				var nid: int = grid[nk]
				if nid < id:
					continue
				var a: Vector3 = nodes[id]["pos"]
				var b: Vector3 = nodes[nid]["pos"]
				if _seg_clear(Vector2(a.x, a.z), Vector2(b.x, b.z), k.z):
					astar.connect_points(id, nid)
	# stairs: a chain of nodes up the slope, tied to the floor at the foot and the balcony at the top
	var run := STAIR_BOT_Z - STAIR_TOP_Z
	for side in 2:
		var x := (-1.0 if side == 0 else 1.0) * STAIR_X
		var chain := PackedInt32Array()
		var foot := _add_node(Vector3(x, 0, STAIR_BOT_Z + 0.7), 0, {"tac": true, "name": "stair_foot"})
		chain.append(foot)
		var steps := 8
		for i in range(1, steps):
			var z := STAIR_BOT_Z - run * float(i) / steps
			var y := BALC_Y * float(i) / steps
			chain.append(_add_node(Vector3(x, y, z), 2, {"tac": i % 2 == 0, "name": "stair"}))
		var top := _add_node(Vector3(x, BALC_Y, STAIR_TOP_Z - 0.7), 1, {"tac": true, "name": "stair_top"})
		chain.append(top)
		for i in range(chain.size() - 1):
			astar.connect_points(chain[i], chain[i + 1])
		stair_bottom[side] = foot
		stair_top[side] = top
		stair_ids[side] = chain
		_link_to_level(foot, 0, 1.6)
		_link_to_level(top, 1, 1.6)
	# cover spots hugging every piece of cover
	for oi in obstacles.size():
		var o: Dictionary = obstacles[oi]
		if not o["cover"]:
			continue
		var level: int = o["level"]
		var y := level_y(level)
		var c: Vector2 = o["c"]
		var cands: Array = []   # [pos2, outward normal]
		if o["kind"] == "circle":
			var r: float = float(o["r"]) + 0.45
			for k in 8:
				var a := TAU * k / 8.0
				var n := Vector2(cos(a), sin(a))
				cands.append([c + n * r, n])
		else:
			var half: Vector2 = o["half"]
			for axis in 2:
				var along := half.y if axis == 0 else half.x
				var across := half.x if axis == 0 else half.y
				for sgn in [-1.0, 1.0]:
					var count := maxi(1, int(round(along * 2.0 / 1.0)))
					for i in count:
						var u := -along + along * 2.0 * (float(i) + 0.5) / count if count > 1 else 0.0
						var n := Vector2(sgn, 0) if axis == 0 else Vector2(0, sgn)
						var p := c + n * (across + 0.45) + (Vector2(0, u) if axis == 0 else Vector2(u, 0))
						cands.append([p, n])
		for cd in cands:
			var p: Vector2 = cd[0]
			if not is_clear(p, level, CLEAR - 0.05):
				continue
			var nn: Vector2 = cd[1]
			var id := _add_node(Vector3(p.x, y, p.y), level, {"spot": true, "tac": true, "cover_h": float(o["h"]), "normal": Vector3(nn.x, 0, nn.y), "name": String(o["name"]), "obs": oi})
			if _link_to_level(id, level, 1.6) == 0:
				astar.remove_point(id)
				nodes[id]["dead"] = true
				continue
			spot_ids.append(id)
	for i in nodes.size():
		if nodes[i].get("dead", false):
			continue
		if nodes[i]["tac"]:
			tac_ids.append(i)
	for t in 2:
		var a := AStar3D.new()
		for i in nodes.size():
			if nodes[i].get("dead", false):
				continue
			a.add_point(i, nodes[i]["pos"])
		for i in nodes.size():
			if nodes[i].get("dead", false):
				continue
			for j in astar.get_point_connections(i):
				if j > i:
					a.connect_points(i, j)
		team_astar.append(a)


func _link_to_level(id: int, level: int, radius: float) -> int:
	var p: Vector3 = nodes[id]["pos"]
	var linked := 0
	for j in nodes.size():
		if j == id or nodes[j].get("dead", false):
			continue
		if int(nodes[j]["level"]) != level:
			continue
		var q: Vector3 = nodes[j]["pos"]
		if Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z)) > radius:
			continue
		if _seg_clear(Vector2(p.x, p.z), Vector2(q.x, q.z), level):
			astar.connect_points(id, j)
			linked += 1
	return linked


func nearest_node(p: Vector3) -> int:
	# the plain closest point, but prefer the right storey: a man on the balcony is not
	# standing on the floor node underneath him
	var best := -1
	var best_d := INF
	for i in nodes.size():
		if nodes[i].get("dead", false):
			continue
		var q: Vector3 = nodes[i]["pos"]
		var d := Vector2(p.x - q.x, p.z - q.z).length_squared() + absf(p.y - q.y) * 9.0
		if d < best_d:
			best_d = d
			best = i
	return best


func path(team: int, from: Vector3, to_id: int, stealthy: bool) -> PackedVector3Array:
	var a: AStar3D = team_astar[team] if stealthy and team >= 0 else astar
	var s := nearest_node(from)
	if s < 0 or to_id < 0:
		return PackedVector3Array()
	return a.get_point_path(s, to_id)


func node_pos(id: int) -> Vector3:
	return nodes[id]["pos"]


func node_level(id: int) -> int:
	return int(nodes[id]["level"])


# ---------------------------------------------------------------- sight

func line_clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q)


## A slug's flight: hard cover stops it; balusters stop it with probability SOFT_STOP.
func bullet_ray(from: Vector3, to: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD | LAYER_SOFT)
	var excl: Array[RID] = []
	for i in 4:
		q.exclude = excl
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return hit
		var col: CollisionObject3D = hit["collider"]
		if col.collision_layer & LAYER_SOFT and rng.randf() > SOFT_STOP:
			excl.append(hit["rid"])
			continue
		return hit
	return {}


func reset_props() -> void:
	for tb in tables:
		tb.reset()
	for b in bottles:
		b.visible = true


func table_near(p: Vector3, radius: float) -> Table:
	var best: Table = null
	var bd := radius
	for tb in tables:
		if tb.flipped or tb.claimed_by != null:
			continue
		var d := Vector2(tb.position.x - p.x, tb.position.z - p.z).length()
		if d < bd and absf(p.y) < 1.0:
			bd = d
			best = tb
	return best


## A bottle within reach of where a slug struck goes to pieces.
func bottle_hit(at: Vector3) -> MeshInstance3D:
	for b in bottles:
		if b.visible and b.position.distance_to(at) < 0.32:
			b.visible = false
			return b
	return null
