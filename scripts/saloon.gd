class_name Saloon
extends Node3D
## The arena (named for the first map it ever built). Builds one of several maps -
## the Saloon, the Dojo, the Bamboo Grove, the Temple Rooftops - each mirror-symmetric about
## x = 0 so neither side starts with the better ground, and owns everything the AI needs to
## read it:
##
## * decks - level 0 is the ground; levels 1.. are raised platforms (a balcony, rafters, roofs)
## * ramps - stairs, walked by anyone; ladders - climbed by anyone, slowly
## * the navigation graph - a 1 m grid on every level, cover spots hugging every piece of cover,
##   and jump links found automatically: vaults over low cover and gaps, drops off a deck,
##   hops up a short step, and leaps up onto a deck. Each man walks the graph his legs allow:
##   class 0 (no jumping), 1 (vault, drop, hop), 2 (also leap up).
## * sight and bullet rays, including paper screens (block the eye, not the slug) and
##   balustrades (block neither, stop half the slugs).

const LAYER_WORLD := 1        # blocks bullets, eyes and men
const LAYER_MEN := 2
const LAYER_RAGDOLL := 16
const LAYER_MOVE := 32        # blocks men only (an upright table's footprint, water)
const LAYER_SOFT := 64        # balusters / bamboo: men can't pass, eyes see through, slugs stop half the time
const LAYER_SCREEN := 128     # paper screens: block the eye, slugs and stars go through most of the time
const SOFT_STOP := 0.5
const SCREEN_STOP := 0.25
const CLEAR := 0.42           # body radius + a whisker
const RAMP := -1              # the level number of nodes on a stair
const HIGH_Y := 1.5           # anything above this is "high ground"
const RAIL_H := 0.9
const MAPS: Array[String] = ["saloon", "dojo", "bamboo", "temple"]
const MAP_TITLES := {"saloon": "The Saloon", "dojo": "The Dojo", "bamboo": "Bamboo Grove", "temple": "Temple Rooftops"}
const MAP_HELP := {
	"saloon": "Bar, piano, flippable tables; a balcony along the back reached by two stairs",
	"dojo": "Paper screens you can shoot through but not see through; rafters up the ladders",
	"bamboo": "Dense bamboo, a stream crossed by one bridge (or a jump), shrines with climbable roofs",
	"temple": "Courtyard walls and a pond to vault, hall roofs and a gallery to run along",
}

var map_id := "saloon"
var half_x := 15.0
var half_z := 10.0
var mid_z := 2.0              # the z the fighting lines tend to form along
## obstacles: {kind, c: Vector2, half: Vector2 | r: float, h: float, level, cover, name}
## h == 0 marks a gap (water): no walking, but vaultable
var obstacles: Array[Dictionary] = []
var decks: Array[Dictionary] = []      # {rect: Rect2 (x, z), y, name}; decks[0] is the ground
var ramps: Array[Dictionary] = []      # {foot, top: Vector3, hw, lo, hi}
var ladders: Array[Dictionary] = []    # {bottom, top: Vector3, lo, hi}
var spawn_rects: Array[Rect2] = [Rect2(), Rect2()]
var spawns: Array = [[], []]
var tables: Array[Table] = []
var bottles: Array[MeshInstance3D] = []
var rail_posts: Array[MeshInstance3D] = []
var chairs: Array[Node3D] = []               # saloon chairs: pick one up and throw it   # the balusters, so a man can go through them
var _splinters: Array[Node3D] = []
var env := {}                          # lighting for main.gd

## navigation
var nodes: Array[Dictionary] = []      # id -> {pos, level, spot, tac, cover_h, normal, name}
var graphs: Array[AStar3D] = []        # by jump class
var team_graphs := [[], []]            # [team][class], weighted by exposure to known enemies
var astar: AStar3D                     # graphs[0], for old callers
var links := {}                        # Vector2i(from, to) -> {type, cls}
var tac_ids: PackedInt32Array = []
var spot_ids: PackedInt32Array = []
var high_ids: PackedInt32Array = []
var _base_edges: Array = []            # [a, b]
var _mats := {}


func build(id: String) -> void:
	map_id = id if MAPS.has(id) else "saloon"
	_build_materials()
	decks = [{"rect": Rect2(-half_x, -half_z, half_x * 2, half_z * 2), "y": 0.0, "name": "ground"}]
	match map_id:
		"dojo": _map_dojo()
		"bamboo": _map_bamboo()
		"temple": _map_temple()
		_: _map_saloon()
	decks[0]["rect"] = Rect2(-half_x, -half_z, half_x * 2, half_z * 2)
	for r in ramps:
		_build_ramp(r)
	for l in ladders:
		_build_ladder(l)
	_build_nav()
	_pick_spawns()


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
	for k in ["lamp"]:
		(_mats[k] as StandardMaterial3D).emission_enabled = true
		(_mats[k] as StandardMaterial3D).emission = Color(1.0, 0.8, 0.45)
		(_mats[k] as StandardMaterial3D).emission_energy_multiplier = 2.0
	for k in ["glass_g", "glass_b"]:
		(_mats[k] as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# the east
	_mat("tatami", Color(0.56, 0.52, 0.34))
	_mat("tatami2", Color(0.48, 0.45, 0.29))
	_mat("plaster", Color(0.86, 0.82, 0.72))
	_mat("paper", Color(0.95, 0.93, 0.85, 0.85))
	(_mats["paper"] as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat("lacquer", Color(0.55, 0.08, 0.06), 0.4)
	_mat("black", Color(0.08, 0.07, 0.07), 0.5)
	_mat("grass", Color(0.3, 0.4, 0.2))
	_mat("grass2", Color(0.25, 0.34, 0.17))
	_mat("bamboo", Color(0.45, 0.6, 0.25), 0.6)
	_mat("bamboo2", Color(0.35, 0.5, 0.2), 0.6)
	_mat("leaf", Color(0.25, 0.45, 0.18))
	_mat("rock", Color(0.45, 0.45, 0.43))
	_mat("water", Color(0.2, 0.35, 0.45, 0.85), 0.05)
	(_mats["water"] as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat("stone", Color(0.58, 0.56, 0.52))
	_mat("stone2", Color(0.5, 0.48, 0.45))
	_mat("tile", Color(0.2, 0.22, 0.26), 0.6)
	_mat("trunk", Color(0.3, 0.22, 0.15))
	_mat("canopy", Color(0.2, 0.35, 0.18))
	_mat("drum", Color(0.55, 0.32, 0.15))
	_mat("skin", Color(0.85, 0.8, 0.68))


func mat(name: String) -> Material:
	return _mats.get(name, _mats["wood"])


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
	if m != "":
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


func _deco_cyl(r: float, h: float, pos: Vector3, m: String, r_top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r if r_top < 0.0 else r_top
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
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
	if m != "":
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


func _add_deck(rect: Rect2, y: float, name: String) -> int:
	decks.append({"rect": rect, "y": y, "name": name})
	return decks.size() - 1


func level_y(level: int) -> float:
	if level <= 0 or level >= decks.size():
		return 0.0
	return float(decks[level]["y"])


## Invisible walls round an outdoor map so nobody wanders off it.
func _fence() -> void:
	for s in [-1.0, 1.0]:
		_box(Vector3(half_x * 2 + 1, 4.0, 0.3), Vector3(0, 2.0, s * (half_z + 0.15)), "", LAYER_WORLD | LAYER_MOVE)
		_box(Vector3(0.3, 4.0, half_z * 2 + 1), Vector3(s * (half_x + 0.15), 2.0, 0), "", LAYER_WORLD | LAYER_MOVE)


func _lamp_post(at: Vector3, h: float) -> void:
	_deco_box(Vector3(0.22, 0.3, 0.22), at + Vector3(0, h, 0), "lamp")


# ---------------------------------------------------------------- the saloon

func _map_saloon() -> void:
	half_x = 15.0
	half_z = 10.0
	mid_z = 2.0
	env = {"bg": Color(0.1, 0.08, 0.07), "ambient": Color(0.75, 0.62, 0.5), "ambient_e": 0.6,
		"sun": Color(1.0, 0.92, 0.8), "sun_e": 0.9, "lamps": [Vector3(-6, 4.8, 1.5), Vector3(6, 4.8, 1.5)], "lamp_c": Color(1.0, 0.78, 0.45)}
	var balc_y := 3.25
	var balc_z := -6.5
	var stair_x := 14.1
	var stair_hw := 0.8
	var balc := _add_deck(Rect2(-half_x, -half_z, half_x * 2, half_z + balc_z), balc_y, "balcony")
	for s in [-1.0, 1.0]:
		ramps.append({"foot": Vector3(s * stair_x, 0, 2.0), "top": Vector3(s * stair_x, balc_y, balc_z), "hw": stair_hw, "lo": 0, "hi": balc, "banister": -s})
	spawn_rects = [Rect2(-14.0, 2.5, 5.5, 7.0), Rect2(8.5, 2.5, 5.5, 7.0)]
	# floor: planks in two tones
	_box(Vector3(half_x * 2 + 1, 0.4, half_z * 2 + 1), Vector3(0, -0.2, 0), "floor")
	for i in range(-14, 15, 2):
		_deco_box(Vector3(1.0, 0.01, half_z * 2), Vector3(i + 0.5, 0.005, 0), "floor2")
	# walls: the back wall full height; the sides full height where the balcony and stairs are,
	# waist-high elsewhere so the camera can see in
	_box(Vector3(half_x * 2 + 0.6, 7.0, 0.3), Vector3(0, 3.5, -half_z - 0.15), "wall")
	_box(Vector3(half_x * 2 + 0.6, 1.0, 0.3), Vector3(0, 0.5, half_z + 0.15), "wall")
	for s in [-1.0, 1.0]:
		var x: float = s * (half_x + 0.15)
		var tall_len := 2.6 + half_z
		_box(Vector3(0.3, 4.6, tall_len), Vector3(x, 2.3, -half_z + tall_len * 0.5), "wall")
		var low_len := half_z - 2.6
		_box(Vector3(0.3, 1.0, low_len), Vector3(x, 0.5, half_z - low_len * 0.5), "wall")
		for dz in [-0.45, 0.45]:
			_deco_box(Vector3(0.08, 1.1, 0.85), Vector3(s * (half_x - 0.05), 1.1, 6.0 + dz), "door")
	for x in [-9.0, -3.0, 3.0, 9.0]:
		_deco_box(Vector3(1.2, 2.2, 0.06), Vector3(x, balc_y + 1.1, -half_z + 0.03), "door")
	# balcony slab
	_box(Vector3(half_x * 2, 0.25, 3.5), Vector3(0, balc_y - 0.125, -half_z + 1.75), "wood")
	# the balustrade: see between the balusters, a slug gets through half the time
	var rail_half := half_x - stair_hw * 2 - 0.05
	var rail := StaticBody3D.new()
	rail.collision_layer = LAYER_SOFT
	rail.collision_mask = 0
	var rcs := CollisionShape3D.new()
	var rsh := BoxShape3D.new()
	rsh.size = Vector3(rail_half * 2, RAIL_H, 0.1)
	rcs.shape = rsh
	rail.position = Vector3(0, balc_y + RAIL_H * 0.5, balc_z)
	rail.add_child(rcs)
	add_child(rail)
	var bx := -rail_half
	while bx <= rail_half:
		rail_posts.append(_deco_box(Vector3(0.07, RAIL_H, 0.07), Vector3(bx, balc_y + RAIL_H * 0.5, balc_z), "dark"))
		bx += 0.16
	_deco_box(Vector3(rail_half * 2, 0.08, 0.16), Vector3(0, balc_y + RAIL_H, balc_z), "wood")
	_deco_box(Vector3(rail_half * 2, 0.06, 0.12), Vector3(0, balc_y + 0.05, balc_z), "wood")
	_rect_obs(Vector2(0, balc_z), Vector2(rail_half, 0.05), RAIL_H, balc, false, "railing")
	for x in [-10.0, -4.5, 4.5, 10.0]:
		_box(Vector3(0.3, balc_y, 0.3), Vector3(x, balc_y * 0.5, balc_z - 0.1), "dark")
		_rect_obs(Vector2(x, balc_z - 0.1), Vector2(0.15, 0.15), 3.0, 0, true, "post")
	for x in [-6.0, 6.0]:
		_deco_box(Vector3(1.2, 0.08, 1.2), Vector3(x, 5.2, 1.5), "brass")
		for dx in [-0.5, 0.5]:
			for dz in [-0.5, 0.5]:
				_deco_box(Vector3(0.14, 0.22, 0.14), Vector3(x + dx, 5.33, 1.5 + dz), "lamp")
	# the bar and the shelf of bottles
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
			_bottle(Vector3(-5.6 + i * 0.53 + brng.randf_range(-0.08, 0.08), 2.36 if row == 0 else 1.45, 9.45), "glass_g" if brng.randf() < 0.5 else "glass_b")
	for x in [-4.2, -1.1, 0.7, 3.6, 5.1]:
		_bottle(Vector3(x, 1.37, 7.55), "glass_b")
	_box(Vector3(2.0, 1.3, 0.7), Vector3(0, 0.65, -3.8), "piano")
	_deco_box(Vector3(1.7, 0.05, 0.25), Vector3(0, 0.78, -3.35), "keys")
	_rect_obs(Vector2(0, -3.8), Vector2(1.0, 0.35), 1.3, 0, true, "piano")
	_cyl(0.32, 3.2, Vector3(0, 1.6, 2.2), "hoop")
	_circ_obs(Vector2(0, 2.2), 0.32, 3.2, 0, true, "stove")
	for s in [-1.0, 1.0]:
		for p in [Vector2(2.6, -0.8), Vector2(6.5, -3.0), Vector2(9.0, 1.0), Vector2(5.5, 3.8), Vector2(2.7, 5.0), Vector2(10.8, -3.6)]:
			_table(Vector2(p.x * s, p.y))
		for p in [Vector2(11.6, 8.6), Vector2(12.5, 8.9), Vector2(8.0, 6.9), Vector2(11.2, 4.8)]:
			var c := Vector2(p.x * s, p.y)
			_barrel(Vector3(c.x, 0, c.y))
			_circ_obs(c, 0.42, 1.05, 0, true, "barrel")
		for p in [Vector2(7.2, -8.6), Vector2(1.9, -8.8)]:
			var c := Vector2(p.x * s, p.y)
			_box(Vector3(1.0, 1.0, 1.0), Vector3(c.x, 0.5, c.y), "crate")
			_rect_obs(c, Vector2(0.5, 0.5), 1.0, 0, true, "crate")
		for p in [Vector2(6.0, -8.9), Vector2(1.6, -8.9)]:
			var c := Vector2(p.x * s, p.y)
			_box(Vector3(1.0, 1.0, 1.0), Vector3(c.x, balc_y + 0.5, c.y), "crate")
			_rect_obs(c, Vector2(0.5, 0.5), 1.0, balc, true, "crate")
		var bc := Vector2(10.5 * s, -8.9)
		_barrel(Vector3(bc.x, balc_y, bc.y))
		_circ_obs(bc, 0.42, 1.05, balc, true, "barrel")


func _bottle(at: Vector3, m: String) -> void:
	var b := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.06
	cm.height = 0.32
	cm.radial_segments = 8
	b.mesh = cm
	b.material_override = _mats[m]
	b.position = at
	add_child(b)
	bottles.append(b)


func _table(c: Vector2) -> void:
	var tb := Table.new()
	tb.saloon = self
	tb.position = Vector3(c.x, 0, c.y)
	add_child(tb)
	tables.append(tb)
	_circ_obs(c, 0.62, 0.8, 0, true, "table")
	tb.obstacle_index = obstacles.size() - 1
	# two chairs at every saloon table
	if map_id == "saloon":
		for k in 2:
			var ang := float(k) * PI + c.x * 0.7
			var ch := Saloon.chair_mesh(_mats["wood"], _mats["dark"])
			ch.position = Vector3(c.x + cos(ang) * 0.95, 0.0, c.y + sin(ang) * 0.95)
			ch.rotation.y = -ang - PI * 0.5
			add_child(ch)
			chairs.append(ch)
	# a bottle or two on every table, for drinking or throwing
	var n := 1 + (1 if (int(absf(c.x * 7.0 + c.y * 3.0)) % 2) == 0 else 0)
	for k in n:
		var off := Vector2(0.22, 0.0).rotated(float(k) * 2.4 + c.x)
		_bottle(Vector3(c.x + off.x, Table.TOP_Y + 0.19, c.y + off.y), "glass_g" if k == 0 else "glass_b")


func _barrel(at: Vector3) -> void:
	_cyl(0.42, 1.05, at + Vector3(0, 0.525, 0), "barrel")
	for y in [0.2, 0.85]:
		_deco_cyl(0.44, 0.06, at + Vector3(0, y, 0), "hoop")


# ---------------------------------------------------------------- the dojo

func _map_dojo() -> void:
	half_x = 13.0
	half_z = 9.0
	mid_z = 0.0
	env = {"bg": Color(0.09, 0.07, 0.06), "ambient": Color(0.8, 0.7, 0.55), "ambient_e": 0.65,
		"sun": Color(1.0, 0.9, 0.75), "sun_e": 0.8, "lamps": [Vector3(-7, 4.5, 0), Vector3(7, 4.5, 0), Vector3(0, 4.5, -5)], "lamp_c": Color(1.0, 0.75, 0.45)}
	spawn_rects = [Rect2(-12.3, -4.0, 3.6, 8.0), Rect2(8.7, -4.0, 3.6, 8.0)]
	(_mats["felt"] as StandardMaterial3D).albedo_color = Color(0.32, 0.2, 0.12)   # low lacquered tables, not card tables
	# tatami in two tones, a dark border
	_box(Vector3(half_x * 2 + 1, 0.4, half_z * 2 + 1), Vector3(0, -0.2, 0), "dark")
	for ix in range(-6, 6):
		for iz in range(-4, 4):
			var horiz := (ix + iz) % 2 == 0
			_deco_box(Vector3(1.95 if horiz else 0.95, 0.02, 0.95 if horiz else 1.95) if true else Vector3.ONE, Vector3(ix * 2 + 1, 0.01, iz * 2 + 1), "tatami" if (ix + iz) % 2 == 0 else "tatami2")
	# walls: plaster and dark beams; the front wall is low for the camera
	_box(Vector3(half_x * 2 + 0.6, 6.0, 0.3), Vector3(0, 3.0, -half_z - 0.15), "plaster")
	_box(Vector3(half_x * 2 + 0.6, 1.0, 0.3), Vector3(0, 0.5, half_z + 0.15), "dark")
	for s in [-1.0, 1.0]:
		_box(Vector3(0.3, 4.6, half_z * 2 + 0.3), Vector3(s * (half_x + 0.15), 2.3, 0), "plaster")
		for z in [-6.0, 0.0, 6.0]:
			_deco_box(Vector3(0.12, 4.6, 0.25), Vector3(s * (half_x - 0.02), 2.3, z), "dark")
	for x in [-9.0, -3.0, 3.0, 9.0]:
		_deco_box(Vector3(0.25, 6.0, 0.12), Vector3(x, 3.0, -half_z + 0.02), "dark")
	# rafters at 3.2 m: two long beams and a cross beam, ladders at the four ends
	var ry := 3.2
	var north := _add_deck(Rect2(-11.0, -6.65, 22.0, 1.3), ry, "north rafter")
	var south := _add_deck(Rect2(-11.0, 5.35, 22.0, 1.3), ry, "south rafter")
	var cross := _add_deck(Rect2(-0.65, -5.35, 1.3, 10.7), ry, "cross rafter")
	for d in [[Vector3(0, ry - 0.15, -6.0), Vector3(22.0, 0.3, 1.3)], [Vector3(0, ry - 0.15, 6.0), Vector3(22.0, 0.3, 1.3)], [Vector3(0, ry - 0.15, 0), Vector3(1.3, 0.3, 10.7)]]:
		_box(d[1], d[0], "dark")
	for s in [-1.0, 1.0]:
		for z in [-6.0, 6.0]:
			for x in [11.0, 5.5]:
				_box(Vector3(0.3, ry - 0.3, 0.3), Vector3(s * x, (ry - 0.3) * 0.5, z), "dark")
				_rect_obs(Vector2(s * x, z), Vector2(0.15, 0.15), ry, 0, true, "post")
			ladders.append({"bottom": Vector3(s * 12.1, 0, z), "top": Vector3(s * 10.5, ry, z), "lo": 0, "hi": north if z < 0 else south})
	# paper screens: hide a man, not stop a slug
	for s in [-1.0, 1.0]:
		for zr in [[-3.6, -0.9], [0.9, 3.6]]:
			var zc: float = (zr[0] + zr[1]) * 0.5
			var hz: float = (zr[1] - zr[0]) * 0.5
			_box(Vector3(0.06, 2.1, hz * 2), Vector3(s * 6.5, 1.05, zc), "paper", LAYER_SCREEN)
			for zz in [zr[0], zc, zr[1]]:
				_deco_box(Vector3(0.1, 2.15, 0.06), Vector3(s * 6.5, 1.07, zz), "dark")
			_deco_box(Vector3(0.1, 0.06, hz * 2), Vector3(s * 6.5, 2.1, zc), "dark")
			_deco_box(Vector3(0.1, 0.04, hz * 2), Vector3(s * 6.5, 1.0, zc), "dark")
			_rect_obs(Vector2(s * 6.5, zc), Vector2(0.05, hz), 2.1, 0, true, "screen")
		# weapon racks on the back wall
		for x in [8.0, 3.0]:
			_box(Vector3(2.0, 1.7, 0.5), Vector3(s * x, 0.85, -8.3), "lacquer")
			for k in 5:
				_deco_box(Vector3(0.05, 1.6, 0.05), Vector3(s * x - 0.8 + k * 0.4, 1.0, -8.0), "wood")
			_rect_obs(Vector2(s * x, -8.3), Vector2(1.0, 0.25), 1.7, 0, true, "rack")
		# training dummies
		for z in [-2.4, 2.4]:
			_cyl(0.22, 1.7, Vector3(s * 9.5, 0.85, z), "wood")
			_deco_box(Vector3(0.9, 0.12, 0.12), Vector3(s * 9.5, 1.3, z), "wood")
			_circ_obs(Vector2(s * 9.5, z), 0.22, 1.7, 0, true, "dummy")
		# low tables that kick over
		for p in [Vector2(3.2, 5.0), Vector2(3.4, -4.6), Vector2(9.6, 6.8)]:
			_table(Vector2(p.x * s, p.y))
		# a stack of floor cushions and a chest by each wall
		_box(Vector3(1.2, 0.9, 0.8), Vector3(s * 11.6, 0.45, 2.8), "lacquer")
		_rect_obs(Vector2(s * 11.6, 2.8), Vector2(0.6, 0.4), 0.9, 0, true, "chest")
	# the great drum in the middle
	_cyl(0.75, 1.15, Vector3(0, 0.575, 0), "drum")
	_deco_cyl(0.77, 0.05, Vector3(0, 1.16, 0), "skin")
	_circ_obs(Vector2(0, 0), 0.75, 1.15, 0, true, "drum")
	for x in [-7.0, 7.0, 0.0]:
		_deco_box(Vector3(0.4, 0.6, 0.4), Vector3(x, 4.6, 0 if x != 0.0 else -5.0), "lamp")


# ---------------------------------------------------------------- the bamboo grove

func _map_bamboo() -> void:
	half_x = 16.0
	half_z = 11.0
	mid_z = 0.0
	env = {"bg": Color(0.35, 0.42, 0.5), "ambient": Color(0.7, 0.78, 0.7), "ambient_e": 0.75,
		"sun": Color(1.0, 0.85, 0.65), "sun_e": 1.1, "lamps": [], "lamp_c": Color(1, 0.8, 0.5)}
	spawn_rects = [Rect2(-15.0, -2.0, 4.6, 9.5), Rect2(10.4, -2.0, 4.6, 9.5)]
	_box(Vector3(half_x * 2 + 1, 0.4, half_z * 2 + 1), Vector3(0, -0.2, 0), "grass")
	var grng := RandomNumberGenerator.new()
	grng.seed = 5
	for i in 40:
		_deco_box(Vector3(grng.randf_range(1.5, 4.0), 0.01, grng.randf_range(1.0, 3.0)), Vector3(grng.randf_range(-15, 15), 0.006, grng.randf_range(-10, 10)), "grass2")
	_fence()
	# the stream down the middle, one bridge across
	var bw := 1.3
	for s in [-1.0, 1.0]:
		var z0: float = bw if s > 0 else -half_z
		var z1: float = half_z if s > 0 else -bw
		var zc := (z0 + z1) * 0.5
		var hz := (z1 - z0) * 0.5
		_deco_box(Vector3(2.0, 0.02, hz * 2), Vector3(0, 0.003, zc), "water")
		_box(Vector3(2.0, 1.0, hz * 2), Vector3(0, 0.5, zc), "", LAYER_MOVE)
		_rect_obs(Vector2(0, zc), Vector2(1.0, hz), 0.0, 0, false, "stream")
		for k in 6:
			_deco_cyl(grng.randf_range(0.15, 0.3), 0.15, Vector3(s * 1.05, 0.05, zc + grng.randf_range(-hz, hz)), "rock")
	_deco_box(Vector3(2.6, 0.12, bw * 2), Vector3(0, 0.06, 0), "wood")
	for k in 7:
		_deco_box(Vector3(0.08, 0.02, bw * 2), Vector3(-1.2 + k * 0.4, 0.13, 0), "dark")
	var clumps := [[4.0, -7.0, 0.7], [6.5, -3.0, 0.6], [3.5, 3.0, 0.75], [7.0, 6.5, 0.6], [10.0, -8.5, 0.8], [11.5, -2.6, 0.55], [9.0, 9.2, 0.7], [13.2, -5.6, 0.6], [5.2, 9.0, 0.5], [2.6, -9.6, 0.6], [8.8, 2.4, 0.5]]
	for s in [-1.0, 1.0]:
		for c in clumps:
			_bamboo(Vector2(s * c[0], c[1]), c[2], grng)
		for r in [[5.0, 0.2, 0.8, 1.0], [9.2, -5.2, 0.7, 0.9], [12.0, 2.6, 0.6, 0.8], [2.4, 6.6, 0.7, 1.0]]:
			var rc := Vector2(s * r[0], r[1])
			var mi := _deco_cyl(r[2], r[3], Vector3(rc.x, r[3] * 0.5, rc.y), "rock", r[2] * 0.7)
			mi.scale = Vector3(1.0, 1.0, 1.25)
			_cyl(r[2], r[3], Vector3(rc.x, r[3] * 0.5, rc.y), "")
			_circ_obs(rc, r[2], r[3], 0, true, "rock")
		for lg in [[6.6, -9.4, 1.3, 0.25], [12.4, 6.6, 0.25, 1.3]]:
			_box(Vector3(lg[2] * 2, 0.5, lg[3] * 2), Vector3(s * lg[0], 0.25, lg[1]), "trunk")
			_rect_obs(Vector2(s * lg[0], lg[1]), Vector2(lg[2], lg[3]), 0.55, 0, true, "log")
		# a little shrine whose roof makes a lookout; a ladder up the back
		var sc := Vector2(s * 12.4, -8.4)
		var shrine := _add_deck(Rect2(sc.x - 1.6, sc.y - 1.3, 3.2, 2.6), 2.4, "shrine roof")
		_box(Vector3(3.2, 2.4, 2.6), Vector3(sc.x, 1.2, sc.y), "lacquer")
		_deco_box(Vector3(3.6, 0.15, 3.0), Vector3(sc.x, 2.43, sc.y), "tile")
		_deco_box(Vector3(1.0, 1.6, 0.05), Vector3(sc.x, 0.8, sc.y + 1.31), "black")
		_rect_obs(sc, Vector2(1.6, 1.3), 2.4, 0, true, "shrine")
		ladders.append({"bottom": Vector3(sc.x - s * 2.1, 0, sc.y), "top": Vector3(sc.x - s * 1.0, 2.4, sc.y), "lo": 0, "hi": shrine})
		for k in 3:
			_deco_box(Vector3(0.05, 0.05, 1.6), Vector3(sc.x - s * 1.65, 0.6 + k * 0.6, sc.y), "wood")


func _bamboo(c: Vector2, r: float, rng: RandomNumberGenerator) -> void:
	_cyl(r, 6.0, Vector3(c.x, 3.0, c.y), "", LAYER_WORLD)
	_circ_obs(c, r, 6.0, 0, true, "bamboo")
	var n := int(6 + r * 10)
	for i in n:
		var a := rng.randf() * TAU
		var d := rng.randf() * r * 0.9
		var h := rng.randf_range(4.5, 7.5)
		_deco_cyl(0.06, h, Vector3(c.x + cos(a) * d, h * 0.5, c.y + sin(a) * d), "bamboo" if i % 2 == 0 else "bamboo2")
	# a few leaf tufts high up - not a lid, or nobody could see the fight
	for k in 3:
		var a2 := rng.randf() * TAU
		var tuft := _deco_box(Vector3(0.7, 0.12, 0.35), Vector3(c.x + cos(a2) * r * 0.7, rng.randf_range(5.5, 7.2), c.y + sin(a2) * r * 0.7), "leaf")
		tuft.rotation.y = a2


# ---------------------------------------------------------------- the temple rooftops

func _map_temple() -> void:
	half_x = 16.0
	half_z = 11.0
	mid_z = 2.0
	env = {"bg": Color(0.05, 0.06, 0.12), "ambient": Color(0.45, 0.5, 0.7), "ambient_e": 0.55,
		"sun": Color(0.7, 0.75, 1.0), "sun_e": 0.6, "lamps": [Vector3(-3.5, 2.0, -3.5), Vector3(3.5, 2.0, -3.5), Vector3(-9, 2.0, 2), Vector3(9, 2.0, 2), Vector3(0, 2.2, 5)], "lamp_c": Color(1.0, 0.65, 0.35)}
	spawn_rects = [Rect2(-15.0, -3.0, 4.5, 11.0), Rect2(10.5, -3.0, 4.5, 11.0)]
	_box(Vector3(half_x * 2 + 1, 0.4, half_z * 2 + 1), Vector3(0, -0.2, 0), "stone")
	for ix in range(-8, 8):
		for iz in range(-5, 6):
			if (ix + iz) % 2 == 0:
				_deco_box(Vector3(1.96, 0.01, 1.96), Vector3(ix * 2 + 1, 0.005, iz * 2), "stone2")
	_box(Vector3(half_x * 2 + 0.6, 5.0, 0.4), Vector3(0, 2.5, -half_z - 0.2), "plaster")
	_box(Vector3(half_x * 2 + 0.6, 1.0, 0.4), Vector3(0, 0.5, half_z + 0.2), "stone2")
	for s in [-1.0, 1.0]:
		_box(Vector3(0.4, 3.0, half_z * 2 + 0.4), Vector3(s * (half_x + 0.2), 1.5, 0), "plaster")
		_deco_box(Vector3(0.6, 0.2, half_z * 2 + 0.6), Vector3(s * (half_x + 0.2), 3.1, 0), "tile")
	# halls at each end: solid buildings with flat walkable roofs
	var hall_y := 2.8
	var gal_y := 2.6
	var gallery := _add_deck(Rect2(-9.0, -10.6, 18.0, 2.1), gal_y, "gallery roof")
	_box(Vector3(18.0, 0.2, 2.1), Vector3(0, gal_y - 0.1, -9.55), "tile")
	for x in [-9.0, -4.5, 0.0, 4.5, 9.0]:
		_box(Vector3(0.25, gal_y - 0.2, 0.25), Vector3(x, (gal_y - 0.2) * 0.5, -8.6), "lacquer")
		_rect_obs(Vector2(x, -8.6), Vector2(0.13, 0.13), gal_y, 0, true, "pillar")
	for s in [-1.0, 1.0]:
		var hc := Vector2(s * 12.6, -7.6)
		var hall := _add_deck(Rect2(hc.x - 3.0, hc.y - 2.5, 6.0, 5.0), hall_y, "hall roof")
		_box(Vector3(6.0, hall_y, 5.0), Vector3(hc.x, hall_y * 0.5, hc.y), "lacquer")
		_deco_box(Vector3(6.4, 0.18, 5.4), Vector3(hc.x, hall_y + 0.02, hc.y), "tile")
		for k in 3:
			_deco_box(Vector3(1.2, 2.0, 0.05), Vector3(hc.x - 2.0 + k * 2.0, 1.0, hc.y + 2.51), "black")
		_rect_obs(hc, Vector2(3.0, 2.5), hall_y, 0, true, "hall")
		ladders.append({"bottom": Vector3(hc.x + s * 0.0 - s * 2.2, 0, hc.y + 3.2), "top": Vector3(hc.x - s * 2.2, hall_y, hc.y + 1.9), "lo": 0, "hi": hall})
		# low courtyard walls to vault, stone lanterns, trees
		for w in [[6.0, 2.0, 0.2, 1.8], [5.0, 7.6, 1.6, 0.2], [10.5, 4.6, 1.4, 0.2]]:
			_box(Vector3(w[2] * 2, 1.1, w[3] * 2), Vector3(s * w[0], 0.55, w[1]), "stone2")
			_deco_box(Vector3(w[2] * 2 + 0.1, 0.12, w[3] * 2 + 0.1), Vector3(s * w[0], 1.15, w[1]), "tile")
			_rect_obs(Vector2(s * w[0], w[1]), Vector2(w[2], w[3]), 1.1, 0, true, "wall")
		for l in [Vector2(3.5, -3.5), Vector2(3.5, 3.0), Vector2(9.0, 1.0), Vector2(8.2, 8.6)]:
			_cyl(0.3, 1.4, Vector3(s * l.x, 0.7, l.y), "stone")
			_deco_box(Vector3(0.6, 0.35, 0.6), Vector3(s * l.x, 1.2, l.y), "stone2")
			_deco_box(Vector3(0.3, 0.2, 0.3), Vector3(s * l.x, 1.2, l.y), "lamp")
			_circ_obs(Vector2(s * l.x, l.y), 0.3, 1.4, 0, true, "lantern")
		for t in [Vector2(13.2, 3.4), Vector2(8.4, -3.0)]:
			_cyl(0.35, 4.0, Vector3(s * t.x, 2.0, t.y), "trunk")
			_deco_cyl(1.6, 1.6, Vector3(s * t.x, 4.6, t.y), "canopy", 0.4)
			_circ_obs(Vector2(s * t.x, t.y), 0.35, 4.0, 0, true, "tree")
	# the pagoda in the middle, and the koi pond in front of it
	_box(Vector3(3.2, 3.6, 3.2), Vector3(0, 1.8, -1.0), "lacquer")
	for k in 3:
		_deco_box(Vector3(4.4 - k * 0.9, 0.25, 4.4 - k * 0.9), Vector3(0, 3.7 + k * 1.0, -1.0), "tile")
		if k < 2:
			_deco_box(Vector3(2.4 - k * 0.7, 0.8, 2.4 - k * 0.7), Vector3(0, 4.2 + k * 1.0, -1.0), "lacquer")
	_rect_obs(Vector2(0, -1.0), Vector2(1.6, 1.6), 3.6, 0, true, "pagoda")
	_deco_cyl(1.8, 0.02, Vector3(0, 0.004, 5.2), "water")
	_cyl(1.8, 1.0, Vector3(0, 0.5, 5.2), "", LAYER_MOVE)
	_circ_obs(Vector2(0, 5.2), 1.8, 0.0, 0, false, "pond")
	for k in 10:
		var a := TAU * k / 10.0
		_deco_cyl(0.22, 0.2, Vector3(cos(a) * 1.95, 0.1, 5.2 + sin(a) * 1.95), "rock")


# ---------------------------------------------------------------- ramps and ladders

## A stair: a solid wedge (nothing passes under it) with steps drawn on top.
func _build_ramp(r: Dictionary) -> void:
	var foot: Vector3 = r["foot"]
	var top: Vector3 = r["top"]
	var hw: float = r["hw"]
	var dir := Vector3(top.x - foot.x, 0, top.z - foot.z)
	var run := dir.length()
	dir = dir.normalized()
	var side := Vector3(-dir.z, 0, dir.x) * hw
	var sb := StaticBody3D.new()
	sb.collision_layer = LAYER_WORLD
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	var f0 := Vector3(foot.x, 0, foot.z)
	var t0 := Vector3(top.x, 0, top.z)
	sh.points = PackedVector3Array([f0 - side, f0 + side, t0 - side, t0 + side, t0 - side + Vector3(0, top.y, 0), t0 + side + Vector3(0, top.y, 0)])
	cs.shape = sh
	sb.add_child(cs)
	add_child(sb)
	var steps := 13
	for i in steps:
		var h := top.y * float(i + 1) / steps
		var mi := _deco_box(Vector3(hw * 2, h, run / steps), f0 + dir * (run * (float(i) + 0.5) / steps) + Vector3(0, h * 0.5, 0), "wood" if i % 2 == 0 else "floor2")
		mi.rotation.y = atan2(dir.x, dir.z)
	# what the wedge takes out of the floor
	var c := (f0 + t0) * 0.5
	var half := Vector2(absf(dir.x) * run * 0.5 + absf(side.x), absf(dir.z) * run * 0.5 + absf(side.z))
	_rect_obs(Vector2(c.x, c.z), half, top.y, int(r["lo"]), false, "stair")


func _build_ladder(l: Dictionary) -> void:
	var b: Vector3 = l["bottom"]
	var t: Vector3 = l["top"]
	var x := Vector3(b.x + (t.x - b.x) * 0.25, 0, b.z + (t.z - b.z) * 0.25)
	var h: float = t.y
	for sx in [-0.25, 0.25]:
		var dirp := Vector3(t.x - b.x, 0, t.z - b.z).normalized()
		var perp := Vector3(-dirp.z, 0, dirp.x)
		_deco_box(Vector3(0.06, h + 0.4, 0.06), x + perp * sx + Vector3(0, (h + 0.4) * 0.5, 0), "wood")
	for k in int(h / 0.35):
		var mi := _deco_box(Vector3(0.55, 0.04, 0.04), x + Vector3(0, 0.3 + k * 0.35, 0), "wood")
		mi.rotation.y = atan2(t.x - b.x, t.z - b.z) + PI * 0.5


# ---------------------------------------------------------------- navigation

func _dist_to_obs(p: Vector2, o: Dictionary) -> float:
	var c: Vector2 = o["c"]
	if o["kind"] == "circle":
		return p.distance_to(c) - float(o["r"])
	var half: Vector2 = o["half"]
	var d := (p - c).abs() - half
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0)


func is_clear(p: Vector2, level: int, margin := CLEAR, ignore_low := -1.0) -> bool:
	if level < 0 or level >= decks.size():
		return false
	var r: Rect2 = decks[level]["rect"]
	var m := minf(margin, minf(r.size.x, r.size.y) * 0.5 - 0.1) if level > 0 else margin
	if p.x < r.position.x + m or p.x > r.end.x - m or p.y < r.position.y + m or p.y > r.end.y - m:
		return false
	for o in obstacles:
		if int(o["level"]) != level:
			continue
		if ignore_low >= 0.0 and float(o["h"]) <= ignore_low:
			continue
		if _dist_to_obs(p, o) < margin:
			return false
	return true


func _seg_clear(a: Vector2, b: Vector2, level: int, ignore_low := -1.0) -> bool:
	var n := int(ceil(a.distance_to(b) / 0.2))
	for i in range(1, n):
		if not is_clear(a.lerp(b, float(i) / n), level, CLEAR - 0.08, ignore_low):
			return false
	return true


func _add_node(pos: Vector3, level: int, extra := {}) -> int:
	var id := nodes.size()
	var d := {"pos": pos, "level": level, "spot": false, "tac": false, "cover_h": 0.0, "normal": Vector3.ZERO, "name": ""}
	d.merge(extra, true)
	nodes.append(d)
	return id


func _edge(a: int, b: int) -> void:
	_base_edges.append([a, b])


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
			_edge(id, j)
			linked += 1
	return linked


func _build_nav() -> void:
	# 1 m grid on every level
	var grid := {}
	for level in decks.size():
		var r: Rect2 = decks[level]["rect"]
		var y: float = decks[level]["y"]
		var xs: Array = []
		var zs: Array = []
		if r.size.x < 1.6:
			xs = [r.get_center().x]
		else:
			for ix in range(int(ceil(r.position.x + 0.5)), int(floor(r.end.x - 0.5)) + 1):
				xs.append(float(ix))
		if r.size.y < 1.6:
			zs = [r.get_center().y]
		else:
			for iz in range(int(ceil(r.position.y + 0.5)), int(floor(r.end.y - 0.5)) + 1):
				zs.append(float(iz))
		for xi in xs.size():
			for zi in zs.size():
				var p := Vector2(xs[xi], zs[zi])
				if not is_clear(p, level):
					continue
				var tac := level > 0 or (posmod(int(p.x), 2) == 0 and posmod(int(p.y), 2) == 0)
				grid[Vector3i(xi, zi, level)] = _add_node(Vector3(p.x, y, p.y), level, {"tac": tac})
	for key in grid:
		var k: Vector3i = key
		var id: int = grid[k]
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var nk := Vector3i(k.x + dx, k.y + dz, k.z)
				if not grid.has(nk) or grid[nk] < id:
					continue
				var a: Vector3 = nodes[id]["pos"]
				var b: Vector3 = nodes[grid[nk]]["pos"]
				if _seg_clear(Vector2(a.x, a.z), Vector2(b.x, b.z), k.z):
					_edge(id, grid[nk])
	# stairs: a chain of nodes up the slope
	for r in ramps:
		var foot: Vector3 = r["foot"]
		var top: Vector3 = r["top"]
		var dir := Vector3(top.x - foot.x, 0, top.z - foot.z).normalized()
		var chain := PackedInt32Array()
		chain.append(_add_node(foot - dir * 0.7, int(r["lo"]), {"tac": true, "name": "stair_foot"}))
		for i in range(1, 8):
			chain.append(_add_node(foot.lerp(top, float(i) / 8.0), RAMP, {"tac": i % 2 == 0, "name": "stair"}))
		chain.append(_add_node(top + dir * 0.7, int(r["hi"]), {"tac": true, "name": "stair_top"}))
		for i in range(chain.size() - 1):
			_edge(chain[i], chain[i + 1])
		_link_to_level(chain[0], int(r["lo"]), 1.6)
		_link_to_level(chain[-1], int(r["hi"]), 1.6)
		r["foot_id"] = chain[0]
	# cover spots
	for oi in obstacles.size():
		var o: Dictionary = obstacles[oi]
		if not o["cover"]:
			continue
		var level: int = o["level"]
		var y := level_y(level)
		var c: Vector2 = o["c"]
		var cands: Array = []
		if o["kind"] == "circle":
			var rr: float = float(o["r"]) + 0.45
			var nseg := 8 if float(o["r"]) < 1.0 else 12
			for k in nseg:
				var a := TAU * k / nseg
				var n := Vector2(cos(a), sin(a))
				cands.append([c + n * rr, n])
		else:
			var half: Vector2 = o["half"]
			for axis in 2:
				var along := half.y if axis == 0 else half.x
				var across := half.x if axis == 0 else half.y
				for sgn in [-1.0, 1.0]:
					var count := maxi(1, int(round(along * 2.0)))
					for i in count:
						var u := -along + along * 2.0 * (float(i) + 0.5) / count if count > 1 else 0.0
						var n := Vector2(sgn, 0) if axis == 0 else Vector2(0, sgn)
						cands.append([c + n * (across + 0.45) + (Vector2(0, u) if axis == 0 else Vector2(u, 0)), n])
		for cd in cands:
			var p: Vector2 = cd[0]
			if not is_clear(p, level, CLEAR - 0.05):
				continue
			var nn: Vector2 = cd[1]
			var id := _add_node(Vector3(p.x, y, p.y), level, {"spot": true, "tac": true, "cover_h": float(o["h"]), "normal": Vector3(nn.x, 0, nn.y), "name": String(o["name"]), "obs": oi})
			if _link_to_level(id, level, 1.6) == 0:
				nodes[id]["dead"] = true
				continue
			spot_ids.append(id)
	# ladders: climbed by anyone
	for l in ladders:
		var b := _add_node(l["bottom"], int(l["lo"]), {"tac": false, "name": "ladder_foot"})
		var t := _add_node(l["top"], int(l["hi"]), {"tac": true, "name": "ladder_top"})
		_link_to_level(b, int(l["lo"]), 1.6)
		_link_to_level(t, int(l["hi"]), 1.6)
		links[Vector2i(b, t)] = {"type": "climb", "cls": 0}
		links[Vector2i(t, b)] = {"type": "climbdown", "cls": 0}
		l["foot_id"] = b
	_find_jumps()
	for i in nodes.size():
		if nodes[i].get("dead", false):
			continue
		if nodes[i]["tac"]:
			tac_ids.append(i)
		if float(nodes[i]["pos"].y) > HIGH_Y and int(nodes[i]["level"]) > 0:
			high_ids.append(i)
	graphs.clear()
	for cls in 3:
		graphs.append(_make_graph(cls))
	astar = graphs[0]
	team_graphs = [[], []]
	for t in 2:
		for cls in 3:
			team_graphs[t].append(_make_graph(cls))


## Vaults (over low cover or water on one level), drops off a deck, hops up a step, leaps up.
func _find_jumps() -> void:
	var bucket := {}
	for i in nodes.size():
		if nodes[i].get("dead", false) or int(nodes[i]["level"]) == RAMP:
			continue
		var p: Vector3 = nodes[i]["pos"]
		var k := Vector2i(int(floor(p.x / 2.0)), int(floor(p.z / 2.0)))
		if not bucket.has(k):
			bucket[k] = []
		bucket[k].append(i)
	var connected := {}
	for e in _base_edges:
		connected[Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))] = true
	for i in nodes.size():
		if nodes[i].get("dead", false) or int(nodes[i]["level"]) == RAMP:
			continue
		var a: Vector3 = nodes[i]["pos"]
		var la: int = nodes[i]["level"]
		var ka := Vector2i(int(floor(a.x / 2.0)), int(floor(a.z / 2.0)))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for j in bucket.get(ka + Vector2i(dx, dz), []):
					if j <= i:
						continue
					var b: Vector3 = nodes[j]["pos"]
					var lb: int = nodes[j]["level"]
					var d := Vector2(a.x - b.x, a.z - b.z).length()
					if la == lb:
						if d < 1.3 or d > 3.1 or connected.has(Vector2i(i, j)):
							continue
						var pa := Vector2(a.x, a.z)
						var pb := Vector2(b.x, b.z)
						if _seg_clear(pa, pb, la):
							continue
						if not _seg_clear(pa, pb, la, 1.25):
							continue
						links[Vector2i(i, j)] = {"type": "vault", "cls": 1}
						links[Vector2i(j, i)] = {"type": "vault", "cls": 1}
					else:
						if d < 0.5 or d > 2.7:
							continue
						var hi_i: int = i if a.y > b.y else j
						var lo_i: int = j if hi_i == i else i
						var ph: Vector3 = nodes[hi_i]["pos"]
						var pl: Vector3 = nodes[lo_i]["pos"]
						var dy := ph.y - pl.y
						if dy > 4.8:
							continue
						# no dropping through a floor: the low end can't be under any deck between the two
						if _under_deck(Vector2(pl.x, pl.z), pl.y, ph.y, int(nodes[lo_i]["level"])):
							continue
						if dy < 0.6:
							links[Vector2i(hi_i, lo_i)] = {"type": "hop", "cls": 1}
							links[Vector2i(lo_i, hi_i)] = {"type": "hop", "cls": 1}
						else:
							links[Vector2i(hi_i, lo_i)] = {"type": "drop", "cls": 1}
							if dy <= 1.35:
								links[Vector2i(lo_i, hi_i)] = {"type": "hop", "cls": 1}
							elif dy <= 3.7:
								links[Vector2i(lo_i, hi_i)] = {"type": "leap", "cls": 2}


func _under_deck(p: Vector2, ylo: float, yhi: float, own: int) -> bool:
	for k in range(1, decks.size()):
		if k == own:
			continue
		var y: float = decks[k]["y"]
		if y > ylo + 0.3 and y < yhi + 0.5 and (decks[k]["rect"] as Rect2).grow(0.2).has_point(p):
			return true
	return false


func _make_graph(cls: int) -> AStar3D:
	var a := NavAStar.new()
	for i in nodes.size():
		if not nodes[i].get("dead", false):
			a.add_point(i, nodes[i]["pos"])
	for e in _base_edges:
		if a.has_point(e[0]) and a.has_point(e[1]):
			a.connect_points(e[0], e[1])
	for k in links:
		var l: Dictionary = links[k]
		if int(l["cls"]) <= cls and a.has_point(k.x) and a.has_point(k.y):
			a.connect_points(k.x, k.y, false)
			if String(l["type"]) == "drop":
				var dy: float = (nodes[k.x]["pos"] as Vector3).y - (nodes[k.y]["pos"] as Vector3).y
				# a drop that lands hard (see Gunman._land_drop) is a last resort
				a.penalty[k] = 0.0 if dy < 1.4 else (4.0 if dy < 2.0 else 30.0 + 6.0 * dy)
	return a


func link_type(from_id: int, to_id: int) -> String:
	var l = links.get(Vector2i(from_id, to_id))
	return "" if l == null else String(l["type"])


func nearest_node(p: Vector3) -> int:
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


## A route for a man of jump class `cls`: {"pts": positions, "ids": node ids}.
func route(team: int, from: Vector3, to_id: int, stealthy: bool, cls: int) -> Dictionary:
	cls = clampi(cls, 0, 2)
	var a: AStar3D = team_graphs[team][cls] if stealthy and team >= 0 else graphs[cls]
	var s := nearest_node(from)
	if s < 0 or to_id < 0 or not a.has_point(to_id):
		return {"pts": PackedVector3Array(), "ids": PackedInt64Array()}
	return {"pts": a.get_point_path(s, to_id), "ids": a.get_id_path(s, to_id)}


func path(team: int, from: Vector3, to_id: int, stealthy: bool) -> PackedVector3Array:
	return route(team, from, to_id, stealthy, 0)["pts"]


func node_pos(id: int) -> Vector3:
	return nodes[id]["pos"]


func node_level(id: int) -> int:
	return int(nodes[id]["level"])


func is_high(p: Vector3) -> bool:
	return p.y > HIGH_Y


# ---------------------------------------------------------------- anchors for the team brains

func _pick_spawns() -> void:
	for side in 2:
		var r: Rect2 = spawn_rects[side]
		var cands: Array = []
		var z := r.position.y
		while z <= r.end.y:
			var x := r.position.x
			while x <= r.end.x:
				var p := Vector2(x, z)
				if is_clear(p, 0, 0.55):
					cands.append(p)
				x += 0.9
			z += 0.9
		var focus := r.get_center()
		cands.sort_custom(func(a, b): return a.distance_to(focus) < b.distance_to(focus))
		var picked: Array = []
		for p in cands:
			var ok := true
			for q in picked:
				if (p as Vector2).distance_to(q) < 1.05:
					ok = false
					break
			if ok:
				picked.append(p)
			if picked.size() >= 16:
				break
		spawns[side] = picked


func spawn_point(side: int, i: int) -> Vector3:
	var list: Array = spawns[side]
	if list.is_empty():
		return Vector3((-1.0 if side == 0 else 1.0) * half_x * 0.7, 0, 0)
	var p: Vector2 = list[i % list.size()]
	return Vector3(p.x, 0.05, p.y)


## A point at fraction `f` of the half-width toward side `s` (-1 west, +1 east), on the fighting line.
func zone(s: float, f: float, dz := 0.0) -> Vector3:
	return Vector3(s * f * half_x, 0, mid_z + dz)


func home(s: float) -> Vector3:
	var side := 0 if s < 0 else 1
	return Vector3(spawn_rects[side].get_center().x, 0, spawn_rects[side].get_center().y)


## The high ground nearest to x - balcony, rafter or roof. Falls back to a zone point.
func high_point(x: float, s: float) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for id in high_ids:
		var p: Vector3 = nodes[id]["pos"]
		var d := absf(p.x - x)
		if d < bd:
			bd = d
			best = p
	return best if best != Vector3.INF else zone(s, 0.5)


func has_high_ground() -> bool:
	return high_ids.size() > 0


## The foot of the way up on our side (a stair or ladder), for guards.
func way_up(s: float) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for r in ramps:
		var f: Vector3 = r["foot"]
		if signf(f.x) == signf(s) or absf(f.x) < 0.5:
			var d := absf(f.x - s * half_x)
			if d < bd:
				bd = d
				best = f
	for l in ladders:
		var f: Vector3 = l["bottom"]
		if signf(f.x) == signf(s):
			var d := absf(f.x - s * half_x)
			if d < bd:
				bd = d
				best = f
	return best if best != Vector3.INF else zone(s, 0.8)


# ---------------------------------------------------------------- sight and slugs

func line_clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD | LAYER_SCREEN)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q)


## A slug's (or a star's) flight: hard cover stops it; balusters stop it half the time;
## paper screens a quarter of the time.
func bullet_ray(from: Vector3, to: Vector3, rng: RandomNumberGenerator, screen_stop := SCREEN_STOP) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD | LAYER_SOFT | LAYER_SCREEN)
	var excl: Array[RID] = []
	for i in 6:
		q.exclude = excl
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return hit
		var col: CollisionObject3D = hit["collider"]
		if col.collision_layer & LAYER_SOFT and rng.randf() > SOFT_STOP:
			excl.append(hit["rid"])
			continue
		if col.collision_layer & LAYER_SCREEN and rng.randf() > screen_stop:
			excl.append(hit["rid"])
			continue
		return hit
	return {}


func reset_props() -> void:
	for tb in tables:
		tb.reset()
	for b in bottles:
		b.visible = true
	for rp in rail_posts:
		rp.visible = true
	for ch in chairs:
		ch.visible = true
	for sp in _splinters:
		if is_instance_valid(sp):
			sp.queue_free()
	_splinters.clear()


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


## The nearest whole bottle a man standing at `p` can reach - off the bar, the shelf behind
## it or a table.
func bottle_near(p: Vector3, reach: float) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var bd := reach
	for b in bottles:
		if not b.visible:
			continue
		var dy := b.position.y - p.y
		if dy < 0.3 or dy > 2.5:
			continue
		var d := Vector2(b.position.x - p.x, b.position.z - p.z).length()
		if d < bd:
			bd = d
			best = b
	return best


## The nearest whole bottle within `r` (flat) of `p`, wherever it is, for a man to go and get.
func bottle_within(p: Vector3, r: float) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var bd := r
	for b in bottles:
		if not b.visible or absf(b.position.y - p.y) > 2.5:
			continue
		var d := Vector2(b.position.x - p.x, b.position.z - p.z).length()
		if d < bd:
			bd = d
			best = b
	return best


func take_bottle(p: Vector3, reach: float) -> MeshInstance3D:
	var b := bottle_near(p, reach)
	if b != null:
		b.visible = false
	return b


## A plain wooden chair, seat at knee height. Built in code; the same model is carried and thrown.
static func chair_mesh(wood: Material, dark: Material) -> Node3D:
	var n := Node3D.new()
	var parts := [[Vector3(0.44, 0.05, 0.42), Vector3(0, 0.46, 0), wood], [Vector3(0.44, 0.42, 0.04), Vector3(0, 0.7, -0.19), wood]]
	for lx in [-0.19, 0.19]:
		for lz in [-0.18, 0.18]:
			parts.append([Vector3(0.04, 0.46, 0.04), Vector3(lx, 0.23, lz), dark])
	for pr in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pr[0]
		mi.mesh = bm
		mi.position = pr[1]
		mi.material_override = pr[2]
		n.add_child(mi)
	return n


func chair_within(p: Vector3, r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for ch in chairs:
		if not ch.visible or absf(ch.position.y - p.y) > 0.6:
			continue
		var d := Vector2(ch.position.x - p.x, ch.position.z - p.z).length()
		if d < bd:
			bd = d
			best = ch
	return best


## Whatever a man at `p` could pick up and throw: {"node", "kind"} or {}.
func throwable_near(p: Vector3, reach: float) -> Dictionary:
	var b := bottle_near(p, reach)
	var ch := chair_within(p, reach)
	if ch != null and (b == null or Vector2(ch.position.x - p.x, ch.position.z - p.z).length() < Vector2(b.position.x - p.x, b.position.z - p.z).length()):
		return {"node": ch, "kind": "chair"}
	if b != null:
		return {"node": b, "kind": "bottle"}
	return {}


func take_throwable(p: Vector3, reach: float) -> Dictionary:
	var t := throwable_near(p, reach)
	if not t.is_empty():
		(t["node"] as Node3D).visible = false
	return t


## A table going over takes its bottles with it.
func spill_bottles(p: Vector3) -> int:
	var n := 0
	for b in bottles:
		if b.visible and absf(b.position.y - Table.TOP_Y - 0.19) < 0.05 and Vector2(b.position.x - p.x, b.position.z - p.z).length() < 0.5:
			b.visible = false
			n += 1
	return n


## Height of whatever a man falling at `p` lands on: the highest deck below him, or the floor.
func ground_below(p: Vector3) -> float:
	var y := 0.0
	for i in range(1, decks.size()):
		var dy := float(decks[i]["y"])
		if dy < p.y - 0.5 and dy > y and (decks[i]["rect"] as Rect2).grow(0.05).has_point(Vector2(p.x, p.z)):
			y = dy
	return y


## If `p` is within `r` of an open edge of a raised deck - the balcony's rail, the side of a
## rafter, the eaves of a roof - where a man would land going over it:
## {"to": landing point, "drop": metres, "rail": through a balustrade?}. With `toward` set (a
## blow's direction) only an edge on that side counts. Edges against the walls are not open.
func fall_edge(p: Vector3, r: float, toward := Vector3.ZERO) -> Dictionary:
	for i in range(1, decks.size()):
		var y := float(decks[i]["y"])
		if absf(p.y - y) > 0.45:
			continue
		var rc: Rect2 = decks[i]["rect"]
		if not rc.grow(0.25).has_point(Vector2(p.x, p.z)):
			continue
		var best := {}
		var best_s := -INF
		var edges := [[Vector3(-1, 0, 0), p.x - rc.position.x, rc.position.x], [Vector3(1, 0, 0), rc.end.x - p.x, rc.end.x],
			[Vector3(0, 0, -1), p.z - rc.position.y, rc.position.y], [Vector3(0, 0, 1), rc.end.y - p.z, rc.end.y]]
		for e in edges:
			var out: Vector3 = e[0]
			var dist: float = e[1]
			var at: float = e[2]
			if dist > r:
				continue
			if (out.x != 0.0 and absf(at) >= half_x - 0.3) or (out.z != 0.0 and absf(at) >= half_z - 0.3):
				continue
			var lean := out.dot(toward)
			if toward != Vector3.ZERO and lean < 0.15:
				continue
			var land := p + out * (maxf(dist, 0.0) + 0.95)
			land.y = ground_below(Vector3(land.x, y, land.z))
			if y - land.y < 1.2:
				continue
			# not onto the stairs
			var on_stairs := false
			for rp in ramps:
				var a := Vector2(rp["foot"].x, rp["foot"].z)
				var b := Vector2(rp["top"].x, rp["top"].z)
				var q := Vector2(land.x, land.z)
				var t := clampf((q - a).dot(b - a) / maxf((b - a).length_squared(), 0.001), 0.0, 1.0)
				if q.distance_to(a.lerp(b, t)) < float(rp["hw"]) + 0.4:
					on_stairs = true
			if on_stairs:
				continue
			var s := -dist + 2.0 * lean
			if s > best_s:
				best_s = s
				var railed := false
				for rpost in rail_posts:
					if absf(rpost.position.z - at) < 0.2 and out.z != 0.0:
						railed = true
						break
				best = {"to": land, "drop": y - land.y, "rail": railed}
		if not best.is_empty():
			return best
	return {}


## A man going through the balustrade: the balusters by him snap and go flying.
func break_rail(p: Vector3) -> void:
	for rp in rail_posts:
		if rp.visible and absf(rp.position.x - p.x) < 0.42:
			rp.visible = false
			if is_inside_tree() and not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
				var sp := RigidBody3D.new()
				sp.collision_layer = LAYER_RAGDOLL
				sp.collision_mask = LAYER_WORLD
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(0.07, RAIL_H * 0.6, 0.07)
				cs.shape = bs
				sp.add_child(cs)
				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = bs.size
				mi.mesh = bm
				mi.material_override = _mats["dark"]
				sp.add_child(mi)
				sp.position = rp.position
				add_child(sp)
				sp.apply_central_impulse(Vector3(randf_range(-0.6, 0.6), 0.8, randf_range(1.0, 2.2)) * 0.4)
				sp.apply_torque_impulse(Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)))
				_splinters.append(sp)


func bottle_hit(at: Vector3) -> MeshInstance3D:
	for b in bottles:
		if b.visible and b.position.distance_to(at) < 0.32:
			b.visible = false
			return b
	return null
