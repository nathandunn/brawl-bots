class_name NavAStar
extends AStar3D
## A* whose edge cost is distance plus a penalty on some links - a long drop off a deck hurts,
## so a man takes the stairs unless the drop saves him a long way round.

var penalty := {}   # Vector2i(from, to) -> extra metres


func _compute_cost(from_id: int, to_id: int) -> float:
	return get_point_position(from_id).distance_to(get_point_position(to_id)) + float(penalty.get(Vector2i(from_id, to_id), 0.0))


func _estimate_cost(from_id: int, to_id: int) -> float:
	return get_point_position(from_id).distance_to(get_point_position(to_id))
