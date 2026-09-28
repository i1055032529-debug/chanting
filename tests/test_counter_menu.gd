extends SceneTree
const Day = preload("res://scripts/day_model.gd")
const Restaurant = preload("res://scenes/restaurant.tscn")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var game = Restaurant.instantiate()
	root.add_child(game)
	await process_frame
	game._toggle_preopen()
	check(not game.player.locked and not game.preopen_panel.visible, "preopening player can walk through restaurant")
	game._request_store()
	check(not game.store_panel.visible, "recipe window requires approaching its counter")
	game.player.global_position = game.MENU_DESK
	game._process(0.0)
	check(not game.menu_access_button.disabled, "recipe button becomes available at menu counter")
	game._request_store()
	check(game.store_panel.visible and game.store_grid.visible and game.store_labels.has("card_rice") and game.store_labels.has("card_egg_noodles"), "recipe index has four illustrated dishes")
	check(FileAccess.get_file_as_bytes("res://assets/recipes/dishes.png").size() < 400 * 1024, "four-dish sprite sheet stays below the image budget")
	game.model.inventory.rice = 0
	game.model.inventory.egg = 0
	game._show_recipe("rice")
	check(game.store_detail.visible and not game.store_grid.visible and game.store_labels.detail_picture.texture != null, "dish card opens illustrated detail")
	game._buy_recipe_target()
	check(game.model.portions_available("rice") == 3 and game.model.coins == 45 and game.model.ledger.size() == 1, "automatic purchase fills only missing ingredients in one transaction")
	game.store_labels.plus_egg.pressed.emit()
	game.store_labels.buy_egg.pressed.emit()
	check(game.model.inventory.egg == 5 and game.model.coins == 39, "single-ingredient purchase remains available in detail")
	game._toggle_store()
	game._request_management()
	check(not game.management_panel.visible, "staff settings require approaching the hiring counter")
	game.player.global_position = game.STAFF_DESK
	game._process(0.0)
	game._request_management()
	game.hire_button.pressed.emit()
	game.hire_button.pressed.emit()
	check(game.management_panel.visible and game.model.employee_hired_count == 0 and game.model.planned_employee_count() == 2, "staff window queues two workers for tomorrow")
	game._toggle_management()
	check(game.start_day() and game.model.employee_attending_count == 0, "scheduled hires do not attend today")
	game.player.global_position = game.MENU_DESK
	game._request_store()
	check(game.store_panel.visible and paused, "opening recipe during service pauses the restaurant")
	game._show_recipe("rice")
	game._toggle_store()
	check(not paused and not game.store_panel.visible, "closing recipe resumes service")
	game.model.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(game.prepare_next_day() and game.model.employee_hired_count == 2 and game.model.wage_reserved == 36, "next morning applies planned hires and reserves wages")
	check(game.model.purchase_recipe_portions("rice", 6) == false, "batch purchase respects payroll reserve when cash is short")
	print("COUNTER MENU: %d checks, %d failures." % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
