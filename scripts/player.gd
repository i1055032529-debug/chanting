extends CharacterBody2D

const SPEED := 185.0
var direction := Vector2.DOWN
var locked := false
var carried := 0
@onready var avatar: Node2D = $Avatar


func _physics_process(_delta: float) -> void:
	var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down") if not locked else Vector2.ZERO
	if movement.length_squared() > 0:
		direction = movement
	velocity = movement * SPEED
	move_and_slide()
	avatar.update_pose(direction, velocity.length() > 1.0, carried, locked)
