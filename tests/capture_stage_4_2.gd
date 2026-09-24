extends SceneTree
## Render the stage 4.2 purchasing screen and a day with purchase expenses.
const RESULT := {"success": true, "doneness": 98.0, "burn": 0.0, "score": 90, "grade": "出色"}

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var game = preload("res://scenes/restaurant.tscn").instantiate()
	root.add_child(game)
	game.employee.enabled = false
	await process_frame
	game._toggle_store()
	await process_frame
	await RenderingServer.frame_post_draw
	var first_error := root.get_texture().get_image().save_webp("res://docs/stage-4-2-store.webp", false, 0.82)
	game._adjust_purchase("egg", 2)
	game._buy_ingredient("egg")
	game._toggle_recipe("noodles")
	game._toggle_store()
	game.start_day()
	game.model.request_customer()
	var id: int = game.model.next_order_id - 1
	for i in range(3): game.customers[id]._process(10.0)
	game.model.start_cooking()
	game.model.complete_cooking(id, game.model.orders[id].cook_attempt, RESULT)
	game.model.interact("pass")
	game.model.interact("table_1")
	game.model.advance(game.model.EAT_SECONDS)
	for i in range(3): game.customers[id]._process(10.0)
	game.model.interact("table_1")
	game.model.interact("sink")
	game.model.advance(game.model.DAY_SECONDS)
	await process_frame
	await RenderingServer.frame_post_draw
	var second_error := root.get_texture().get_image().save_webp("res://docs/stage-4-2-summary.webp", false, 0.82)
	print("STAGE 4.2 PREVIEW: ", error_string(first_error), ", ", error_string(second_error))
	game.queue_free()
	await process_frame
	quit(0 if first_error == OK and second_error == OK else 1)
