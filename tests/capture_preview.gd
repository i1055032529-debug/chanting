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
	game.player.position = game.TARGETS.stove
	game.model.interact("stove")
	game._process(1.2)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-results")
	var error := root.get_texture().get_image().save_png("res://test-results/stage1-preview.png")
	print("PREVIEW: ", error_string(error))
	game.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
