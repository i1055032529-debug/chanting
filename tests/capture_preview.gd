extends SceneTree
## Render the actual game viewport for visual review; requires a display.

func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var game := preload("res://scenes/restaurant.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.model.request_customer()
	for i in range(3):
		game.customer._process(10.0)
	game.player.position = game.target_position("stove")
	game.try_interact("stove")
	game._process(1.2)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-results")
	var error := root.get_texture().get_image().save_png("res://test-results/stage1-preview.png")
	game._process(3.0)
	game.player.position = game.target_position("pass")
	game.try_interact("pass")
	game._process(0.0)
	game.player.position = Vector2(682, 570)
	game.player.direction = Vector2.RIGHT
	game.player.avatar.update_pose(Vector2.RIGHT, false, game.model.carrying)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/carry-preview.png")
	game.player.position = game.target_position("table")
	game.try_interact("table")
	game._process(0.0)
	game.player.position = Vector2(682, 570)
	game.player.avatar.update_pose(Vector2.RIGHT, false)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/serve-preview.png")
	root.get_texture().get_image().save_webp("res://docs/image-assets-preview.webp", false)
	print("PREVIEW: cooking, carrying and served; ", error_string(error))
	game.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
