extends SceneTree
## Render actual stage-two game screens for visual review; requires a display.

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var game := preload("res://scenes/restaurant.tscn").instantiate()
	root.add_child(game)
	game.employee.enabled = false
	await process_frame
	for n in range(4): game.model.request_customer()
	for customer in game.customers.values():
		for i in range(3): customer._process(10.0)
	game._process(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-results")
	var error := root.get_texture().get_image().save_webp("res://docs/stage-2-preview.webp", false, 0.85)
	game.model.select_next()
	game.player.position = game.target_position("stove")
	game.try_interact("stove")
	game.cooking_screen.start_round()
	game.cooking_screen.rules.advance(1.6, true)
	game.cooking_screen._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_webp("res://docs/cooking-preview.webp", false, 0.85)
	preload("res://tests/cooking_bot.gd").finish(game.cooking_screen.rules)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/cooking-result.png")
	game.cooking_screen.acknowledge()
	game.model.advance(190.0)
	game.model.advance(36.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_webp("res://docs/day-summary-preview.webp", false, 0.85)
	print("PREVIEW: stage two room, cooking and summary; ", error_string(error))
	game.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
