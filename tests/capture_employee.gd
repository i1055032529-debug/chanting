extends SceneTree
## Render the employee actively working and the priority panel.
func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var game = preload("res://scenes/restaurant.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await process_frame
	for n in range(2): game.model.request_customer()
	for customer in game.customers.values():
		for i in range(3): customer._process(10.0)
	for i in range(170):
		game.model.advance(0.1)
		game.employee._physics_process(0.1)
		for customer in game.customers.values():
			if is_instance_valid(customer): customer._process(0.1)
		game._sync_stains()
	game._process(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_webp("res://docs/stage-3-preview.webp", false, 0.84)
	game.management_panel.show()
	game._refresh_employee_panel()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_webp("res://docs/stage-3-management.webp", false, 0.84)
	game.management_panel.hide()
	game.model.advance(240.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_webp("res://docs/stage-3-summary.webp", false, 0.84)
	print("EMPLOYEE PREVIEW: ", error_string(error))
	game.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
