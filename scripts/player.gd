extends CharacterBody2D

const Art = preload("res://scripts/pixel_art.gd")
const SPEED := 185.0
var direction := Vector2.DOWN
var locked := false
var carried := 0
var walk_time := 0.0


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20, 14)
	collider.shape = shape
	collider.position.y = -5
	add_child(collider)


func _physics_process(delta: float) -> void:
	var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down") if not locked else Vector2.ZERO
	if movement.length_squared() > 0:
		direction = movement
	velocity = movement * SPEED
	move_and_slide()
	walk_time += delta
	queue_redraw()


func _draw() -> void:
	Art.person(self, Vector2.ZERO, Color("4c9287"), true, direction, velocity.length() > 1.0, walk_time)
	if carried != 0:
		Art.plate(self, Vector2(0, -19), carried == 1)
