extends Node2D
## Visual state is independent of movement; replace SpriteFrames in the editor.

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var held: Sprite2D = $HeldItem


func update_pose(direction: Vector2, walking: bool, carried := 0, working := false) -> void:
	var facing := "down"
	if absf(direction.x) > absf(direction.y):
		facing = "right" if direction.x > 0.0 else "left"
	elif direction.y < 0.0:
		facing = "up"
	var activity := "idle"
	if working:
		activity = "work"
	elif walking:
		activity = "carry" if carried != 0 else "walk"
	sprite.play(activity + "_" + facing)
	held.visible = carried != 0
	held.frame = 0 if carried == 1 else 1
	# Keep held items within the actor's Y-sort group, above the room background.
	var item_index := 0 if facing == "up" else get_child_count() - 1
	if held.get_index() != item_index:
		move_child(held, item_index)
	held.position = Vector2(0, -27)
	if facing == "left": held.position.x = -17
	elif facing == "right": held.position.x = 17
