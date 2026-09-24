extends SceneTree
## Render multi-worker management and an actual service day with three staff.

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var game = preload("res://scenes/restaurant.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.model.coins = 100
	game._toggle_management()
	for i in range(3): game.hire_button.pressed.emit()
	await process_frame
	await RenderingServer.frame_post_draw
	var first_error := root.get_texture().get_image().save_webp("res://docs/multi-employee-management.webp", false, 0.82)
	game._toggle_management()
	game.start_day()
	game.model.request_customer()
	game.model.request_customer()
	for id in [1, 2]:
		for i in range(3): game.customers[id]._process(10.0)
	for worker in game.employees: worker._physics_process(0.1)
	await process_frame
	await RenderingServer.frame_post_draw
	var second_error := root.get_texture().get_image().save_webp("res://docs/multi-employee-service.webp", false, 0.82)
	print("MULTI EMPLOYEE PREVIEW: ", error_string(first_error), ", ", error_string(second_error))
	game.queue_free()
	await process_frame
	quit(0 if first_error == OK and second_error == OK else 1)
