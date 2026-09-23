extends Node2D

signal seated
signal departed

const Art = preload("res://scripts/pixel_art.gd")
const ENTRY := Vector2(374, 623)
const SEAT := Vector2(650, 371)
const SPEED := 150.0
var route: Array[Vector2] = []
var leaving := false
var walking := false
var direction := Vector2.LEFT
var elapsed := 0.0


func _ready() -> void:
	position = ENTRY
	route = [Vector2(722, 623), Vector2(722, 371), SEAT]


func leave() -> void:
	leaving = true
	route = [Vector2(722, 371), Vector2(722, 623), ENTRY]


func _process(delta: float) -> void:
	elapsed += delta
	walking = not route.is_empty()
	if walking:
		direction = (route[0] - position).normalized()
		position = position.move_toward(route[0], SPEED * delta)
		if position.distance_to(route[0]) < 0.1:
			route.pop_front()
			if route.is_empty():
				if leaving:
					departed.emit()
					queue_free()
				else:
					direction = Vector2.LEFT
					seated.emit()
	queue_redraw()


func _draw() -> void:
	Art.person(self, Vector2.ZERO, Color("d99262"), false, direction, walking, elapsed)
