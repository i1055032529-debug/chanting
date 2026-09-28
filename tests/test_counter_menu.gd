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
	check(game.model.coins == 1000 and game.model.employee_hired_count == 3 and game.model.wage_reserved == 54, "new game begins with 1000 coins and three hired workers")
	game._toggle_preopen()
	check(not game.player.locked and not game.preopen_panel.visible, "preopening player can walk through restaurant")
	game._request_store()
	check(not game.store_panel.visible, "recipe window requires approaching its counter")
	game.player.global_position = game.MENU_DESK
	game._process(0.0)
	check(not game.menu_access_button.disabled, "recipe button becomes available at menu counter")
	game._request_store()
	check(game.store_panel.visible and game.store_grid.visible and game.store_labels.has("card_rice") and game.store_labels.has("card_egg_noodles"), "recipe index has four illustrated dishes")
	check(game.store_grid is ScrollContainer and game.store_cards.columns == 6, "recipe list scrolls vertically with six cards per row")
	var first_card: Button = game.store_cards.get_child(0)
	var card_picture: Sprite2D = first_card.get_child(0)
	check(card_picture.scale.x * 256.0 <= 82.1 and card_picture.position.x + card_picture.scale.x * 256.0 < first_card.size.x, "dish picture remains inside its card")
	check(FileAccess.get_file_as_bytes("res://assets/recipes/dishes.png").size() < 400 * 1024, "four-dish sprite sheet stays below the image budget")
	game.model.inventory.rice = 0
	game.model.inventory.egg = 0
	game._show_recipe("rice")
	check(game.store_detail.visible and not game.store_grid.visible and game.store_labels.detail_picture.texture != null, "dish card opens illustrated detail")
	game._buy_recipe_target()
	check(game.model.portions_available("rice") == 3 and game.model.coins == 985 and game.model.ledger.size() == 1, "automatic purchase fills only missing ingredients in one transaction")
	game.store_labels.plus_egg.pressed.emit()
	game.store_labels.buy_egg.pressed.emit()
	check(game.model.inventory.egg == 5 and game.model.coins == 979, "single-ingredient purchase remains available in detail")
	game._toggle_store()
	game._request_management()
	check(not game.management_panel.visible, "staff settings require approaching the hiring counter")
	game.player.global_position = game.STAFF_DESK
	game._process(0.0)
	game._request_management()
	check(game.management_list_page.visible and game.staff_list_scroll is ScrollContainer and game.staff_list_items.get_child_count() == 3, "staff page lists three scrollable employee cards")
	game.staff_list_items.get_node("lan").get_child(1).pressed.emit()
	check(game.management_panel.visible and game.model.employee_hired_count == 3 and game.model.planned_employee_count() == 2, "staff window queues two workers for tomorrow")
	check(game.model.planned_staff_ids() == ["lin", "qing"], "dismiss button removes the selected employee rather than a generic slot")
	game.hire_button.pressed.emit()
	check(game.management_hire_page.visible and game.hire_list_scroll is ScrollContainer and game.hire_list_items.has_node("mei"), "plus opens the scrollable candidate list")
	game.hire_list_items.get_node("mei").get_child(0).pressed.emit()
	check(game.management_list_page.visible and game.model.planned_staff_ids() == ["lin", "qing", "mei"] and game.staff_list_items.has_node("mei"), "hiring a candidate inserts a named card in the employee list")
	game.staff_list_items.get_node("mei").get_child(0).pressed.emit()
	check(game.management_detail_page.visible and game.staff_detail_name.text == "阿梅", "employee card opens its named detail page")
	game._toggle_employee_work("cook")
	check(not game.staff_settings_by_id["mei"].work_enabled.cook, "a pending employee can have independent work settings")
	game._show_management_list()
	game.staff_list_items.get_node("mei").get_child(1).pressed.emit()
	game._open_staff_detail("qing")
	game._move_employee_priority("cook")
	game._toggle_management()
	check(game.start_day() and game.model.employee_attending_count == 3, "scheduled headcount does not change today's three workers")
	game.player.global_position = game.MENU_DESK
	game._request_store()
	check(game.store_panel.visible and paused, "opening recipe during service pauses the restaurant")
	game._show_recipe("rice")
	game._toggle_store()
	check(not paused and not game.store_panel.visible, "closing recipe resumes service")
	game.model.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(game.prepare_next_day() and game.model.employee_hired_count == 2 and game.model.wage_reserved == 36, "next morning applies planned hires and reserves wages")
	check(game.model.staff_roster == ["lin", "qing"] and game.employees[1].title_label.text == "青栀", "remaining staff keep their identity when the roster closes a gap")
	check(game.employees[1].priority == ["serve", "clear", "cook", "clean"], "employee priority follows the person into the next day's worker slot")
	game.model.coins = 36
	check(game.model.purchase_recipe_portions("rice", 6) == false, "batch purchase respects payroll reserve when cash is short")
	game.reset_run()
	check(game.model.coins == 1000 and game.model.employee_hired_count == 3 and game.model.wage_reserved == 54, "new-game reset restores the requested starter cash and staff")
	print("COUNTER MENU: %d checks, %d failures." % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
