extends SceneTree
## Capture actual 4.5 placement preview and purchased/upgraded room.

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var game = preload("res://scenes/restaurant.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.model.coins = 160
	game._toggle_layout()
	game._begin_layout_preview(true)
	await process_frame
	await RenderingServer.frame_post_draw
	var first_error := root.get_texture().get_image().save_webp("res://docs/stage-4-5-placement.webp", false, 0.76)
	game._confirm_layout_preview()
	game._upgrade_equipment()
	game.layout_selected = game.model.table_count()
	game._begin_layout_preview(false)
	game._move_layout_preview(Vector2(465, 196))
	game._confirm_layout_preview()
	await process_frame
	await RenderingServer.frame_post_draw
	var second_error := root.get_texture().get_image().save_webp("res://docs/stage-4-5-upgraded.webp", false, 0.76)
	print("STAGE 4.5 PREVIEW: ", error_string(first_error), ", ", error_string(second_error))
	game.queue_free()
	await process_frame
	quit(0 if first_error == OK and second_error == OK else 1)
