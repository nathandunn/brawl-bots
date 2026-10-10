class_name Blood
extends Node3D
## Blood on the boards. The floor and the balcony are split into 0.5 m cells; every drop a
## bleeding man sheds, every spray from a hit and every pool round a body adds to its cell.
## A cell that has had enough poured into it is slick: a man who crosses it at a run may go
## down. Drawn as dark discs that spread as the cell fills; tracked even headless, because the
## slipping is part of the fight.

const CELL := 0.5
const SLICK := 4.0          # a cell this full is slippery
const MAX_V := 30.0
const STAIRS := 2

var saloon: Saloon
var headless := false
var cells := {}             # Vector3i(ix, iz, level) -> volume
var _decals := {}           # same key -> MeshInstance3D
var _mats: Array[StandardMaterial3D] = []
var _disc: CylinderMesh


func _ready() -> void:
	_disc = CylinderMesh.new()
	_disc.top_radius = 0.5
	_disc.bottom_radius = 0.5
	_disc.height = 0.006
	_disc.radial_segments = 12
	for c in [Color(0.42, 0.03, 0.03), Color(0.33, 0.02, 0.02), Color(0.26, 0.01, 0.01)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.15
		m.metallic_specular = 0.8
		_mats.append(m)


func clear() -> void:
	cells.clear()
	for k in _decals:
		if is_instance_valid(_decals[k]):
			_decals[k].queue_free()
	_decals.clear()


func _key(p: Vector3, level: int) -> Vector3i:
	return Vector3i(int(floor(p.x / CELL)), int(floor(p.z / CELL)), level)


static func level_of(p: Vector3) -> int:
	if p.y > 2.6:
		return 1
	if p.y > 0.4:
		return STAIRS
	return 0


## Pour `amount` at `p`. Stairs don't hold a pool (it runs down them); nothing is drawn there.
func pour(p: Vector3, amount: float) -> void:
	var lv := level_of(p)
	if lv == STAIRS or amount <= 0.0:
		return
	var k := _key(p, lv)
	var v: float = minf(float(cells.get(k, 0.0)) + amount, MAX_V)
	cells[k] = v
	if not headless:
		_draw(k, v)


## A body empties into the cells round it.
func pool(p: Vector3, amount: float) -> void:
	pour(p, amount * 0.6)
	for d in [Vector3(CELL, 0, 0), Vector3(-CELL, 0, 0), Vector3(0, 0, CELL), Vector3(0, 0, -CELL)]:
		pour(p + d, amount * 0.1)


func volume_at(p: Vector3) -> float:
	var lv := level_of(p)
	if lv == STAIRS:
		return 0.0
	return float(cells.get(_key(p, lv), 0.0))


func is_slick(p: Vector3) -> bool:
	return volume_at(p) >= SLICK


func cell_of(p: Vector3) -> Vector3i:
	return _key(p, level_of(p))


func _draw(k: Vector3i, v: float) -> void:
	var mi: MeshInstance3D = _decals.get(k)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.mesh = _disc
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var y := saloon.level_y(k.z) + 0.004 + randf() * 0.002
		mi.position = Vector3((k.x + 0.5) * CELL + randf_range(-0.1, 0.1), y, (k.y + 0.5) * CELL + randf_range(-0.1, 0.1))
		mi.rotation.y = randf() * TAU
		add_child(mi)
		_decals[k] = mi
	# a few drops are specks; a slick is a puddle that fills its cell and darkens
	var r := clampf(0.08 + 0.12 * sqrt(v), 0.08, 0.62)
	mi.scale = Vector3(r * 2.0, 1.0, r * 2.0 * randf_range(0.8, 1.2))
	mi.material_override = _mats[0 if v < SLICK * 0.6 else (1 if v < SLICK * 2.0 else 2)]
