class_name Table
extends Node3D
## A round saloon table. Standing, it stops nothing worth mentioning - the top is a plank at
## knee height and a crouching man's head is above it. Kicked over, the top becomes a board
## 1.2 m high between you and whoever you flipped it at. Flipping takes a second, and the
## noise tells the room where you are.

const R := 0.6
const TOP_Y := 0.76

var saloon: Saloon
var obstacle_index := -1
var flipped := false
var flip_dir := Vector3.FORWARD   # the side the board faces (toward the threat)
var claimed_by: Node = null
var _top_body: StaticBody3D
var _top_shape: CollisionShape3D
var _move_block: StaticBody3D
var _visual: Node3D
var _board_shape: BoxShape3D
var _disc_shape: CylinderShape3D
var _tween: Tween
var _cards: MeshInstance3D


func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var top := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = R
	cm.bottom_radius = R
	cm.height = 0.06
	cm.radial_segments = 18
	top.mesh = cm
	top.material_override = saloon.mat("wood")
	top.position = Vector3(0, TOP_Y, 0)
	_visual.add_child(top)
	var felt := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = R * 0.82
	fm.bottom_radius = R * 0.82
	fm.height = 0.01
	felt.mesh = fm
	felt.material_override = saloon.mat("felt")
	felt.position = Vector3(0, TOP_Y + 0.035, 0)
	_visual.add_child(felt)
	var leg := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.06
	lm.bottom_radius = 0.1
	lm.height = TOP_Y
	leg.mesh = lm
	leg.material_override = saloon.mat("dark")
	leg.position = Vector3(0, TOP_Y * 0.5, 0)
	_visual.add_child(leg)

	_top_body = StaticBody3D.new()
	_top_body.collision_layer = Saloon.LAYER_WORLD
	_top_body.collision_mask = 0
	_top_shape = CollisionShape3D.new()
	_disc_shape = CylinderShape3D.new()
	_disc_shape.radius = R
	_disc_shape.height = 0.06
	_board_shape = BoxShape3D.new()
	_board_shape.size = Vector3(R * 2.0, R * 2.0, 0.08)
	_top_shape.shape = _disc_shape
	_top_shape.position = Vector3(0, TOP_Y, 0)
	_top_body.add_child(_top_shape)
	add_child(_top_body)

	_move_block = StaticBody3D.new()
	_move_block.collision_layer = Saloon.LAYER_MOVE
	_move_block.collision_mask = 0
	var mcs := CollisionShape3D.new()
	var msh := CylinderShape3D.new()
	msh.radius = R - 0.05
	msh.height = 0.9
	mcs.shape = msh
	mcs.position = Vector3(0, 0.45, 0)
	_move_block.add_child(mcs)
	add_child(_move_block)


func reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	flipped = false
	claimed_by = null
	_visual.transform = Transform3D.IDENTITY
	_top_shape.shape = _disc_shape
	_top_shape.transform = Transform3D(Basis.IDENTITY, Vector3(0, TOP_Y, 0))


## Over she goes, the top ending up as a wall facing `toward` (a flat direction).
func flip(toward: Vector3) -> void:
	if flipped:
		return
	flipped = true
	var d := Vector3(toward.x, 0, toward.z)
	if d.length() < 0.01:
		d = Vector3.FORWARD
	d = d.normalized()
	flip_dir = d
	# board stands at the threat side of the table's centre, its face toward the threat
	var yaw := atan2(d.x, d.z)
	var b := Basis(Vector3.UP, yaw)
	_top_shape.shape = _board_shape
	_top_shape.transform = Transform3D(b, d * 0.32 + Vector3(0, R, 0))
	# the drawn table: lift the top to the origin, stand it on its edge, set it down as the board
	var pivot_axis := (b * Vector3.RIGHT).normalized()
	var end_t := Transform3D(Basis.IDENTITY, d * 0.32 + Vector3(0, R, 0)) * Transform3D(Basis(pivot_axis, -PI * 0.5), Vector3.ZERO) * Transform3D(Basis.IDENTITY, Vector3(0, -TOP_Y, 0))
	if is_inside_tree():
		_tween = create_tween()
		_tween.tween_property(_visual, "transform", end_t, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		_visual.transform = end_t


## Where a man should crouch to use this table: behind the board, away from the threat.
func crouch_spot() -> Vector3:
	return position - flip_dir * 0.55
