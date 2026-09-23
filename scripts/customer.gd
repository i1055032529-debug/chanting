extends Node2D

signal seated
signal departed

const SPEED := 150.0
var entrance := Vector2.ZERO
var seat := Vector2.ZERO
var arrival_route: Array[Vector2] = []
var route: Array[Vector2] = []
var leaving := false
var walking := false
var direction := Vector2.DOWN
@onready var avatar: Node2D = $Avatar


func configure(entry: Vector2, waypoints: Array[Vector2], seat_position: Vector2) -> void:
	entrance = entry
	seat = seat_position
	arrival_route = waypoints.duplicate()
	arrival_route.append(seat)
	position = entrance
	route = arrival_route.duplicate()


func leave() -> void:
	leaving = true
	route = arrival_route.duplicate()
	route.reverse()
	route.pop_front()
	route.append(entrance)


func _process(delta: float) -> void:
	walking = not route.is_empty()
	if walking:
		direction = (route[0] - position).normalized()
		position = position.move_toward(route[0], SPEED * delta)
		if position.distance_to(route[0]) < 0.1:
			route.pop_front()
			if route.is_empty():
				walking = false
				if leaving:
					departed.emit()
					queue_free()
				else:
					direction = Vector2.LEFT
					seated.emit()
	avatar.update_pose(direction, walking)
