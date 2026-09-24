extends SceneTree
## Render the real preopening employment panel and paid-wage summary.

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var game = preload("res://scenes/restaurant.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._toggle_management()
	game.hire_button.pressed.emit()
	await process_frame
	await RenderingServer.frame_post_draw
	var first_error := root.get_texture().get_image().save_webp("res://docs/stage-4-3-hire.webp", false, 0.82)
	game._toggle_management()
	game.start_day()
	game.model.advance(game.model.DAY_SECONDS + game.model.CLOSING_GRACE)
	await process_frame
	await RenderingServer.frame_post_draw
	var second_error := root.get_texture().get_image().save_webp("res://docs/stage-4-3-summary.webp", false, 0.82)
	print("STAGE 4.3 PREVIEW: ", error_string(first_error), ", ", error_string(second_error))
	game.queue_free()
	await process_frame
	quit(0 if first_error == OK and second_error == OK else 1)
