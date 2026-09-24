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
var browsing := false
var thought: Label
var direction := Vector2.DOWN
@onready var avatar: Node2D = $Avatar


func configure(entry: Vector2, waypoints: Array[Vector2], seat_position: Vector2) -> void:
	entrance = entry
	seat = seat_position
	arrival_route = waypoints.duplicate()
	arrival_route.append(seat)
	position = entrance
	route = arrival_route.duplicate()


func configure_browsing(entry: Vector2, spot: Vector2) -> void:
	browsing = true
	configure(entry, [], spot)


func _ready() -> void:
	thought = Label.new()
	thought.text = "…"
	thought.position = Vector2(-13, -53)
	thought.add_theme_font_size_override("font_size", 27)
	thought.add_theme_color_override("font_color", Color("fff0d2"))
	thought.add_theme_color_override("font_outline_color", Color("493321"))
	thought.add_theme_constant_override("outline_size", 4)
	thought.visible = false
	add_child(thought)


func leave() -> void:
	leaving = true
	if thought != null: thought.visible = false
	route = arrival_route.duplicate()
	route.reverse()
	route.pop_front()
	route.append(entrance)


func _process(delta: float) -> void:
	walking = not route.is_empty()
	var travel := SPEED * delta
	while not route.is_empty() and travel > 0.0:
		direction = (route[0] - position).normalized()
		var step := minf(travel, position.distance_to(route[0]))
		position = position.move_toward(route[0], step)
		travel -= step
		if position.distance_to(route[0]) < 0.1:
			route.pop_front()
			if route.is_empty():
				walking = false
				if leaving:
					departed.emit()
					queue_free()
				else:
					direction = Vector2.LEFT
					if browsing: thought.visible = true
					seated.emit()
		else:
			break
	avatar.update_pose(direction, walking)
