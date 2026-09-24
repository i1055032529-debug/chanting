extends SceneTree
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
	await physics_frame
	await process_frame
	check(game.employee != null and game.employee.grid != null, "employee and obstacle grid exist")
	var menu_key := InputEventKey.new()
	menu_key.keycode = KEY_M
	menu_key.physical_keycode = KEY_M
	menu_key.pressed = true
	Input.parse_input_event(menu_key)
	Input.flush_buffered_events()
	check(game.management_panel.visible, "M opens employee management")
	var menu_release := menu_key.duplicate()
	menu_release.pressed = false
	Input.parse_input_event(menu_release)
	Input.parse_input_event(menu_key.duplicate())
	Input.flush_buffered_events()
	check(not game.management_panel.visible, "M closes employee management")
	game.model.request_customer()
	var first_id: int = game.model.next_order_id - 1
	for i in range(3): game.customers[first_id]._process(10.0)
	check(game.model.orders[first_id].state == "waiting", "customer has active order")
	# Drive the same model, customer and employee steps deterministically.
	for i in range(800):
		game.model.advance(0.1)
		game.employee._physics_process(0.1)
		for customer in game.customers.values():
			if is_instance_valid(customer): customer._process(0.1)
		game._sync_stains()
	check(game.employee.tasks_completed.cook > 0, "employee cooks")
	check(game.employee.tasks_completed.serve > 0, "employee serves")
	check(game.employee.tasks_completed.clear > 0, "employee clears and returns plate")
	check(game.employee.tasks_completed.clean > 0, "employee cleans stains")
	check(game.model.served > 0 and (game.model.tables[0] == 0 or game.model.tables[0] != first_id), "autonomous service frees table for reuse")
	check(game.employee.priority == ["serve", "clear", "clean", "cook"], "default priority is explicit")
	game.employee.move_priority_up("cook")
	check(game.employee.priority == ["serve", "clear", "cook", "clean"], "priority can be reordered")
	game.employee.toggle_work("clean")
	check(not game.employee.work_enabled.clean, "work type can be disabled")
	game.employee.toggle_work("clean")
	game.reset_run()
	game.employee.work_enabled.cook = false
	game.model.request_customer()
	var disabled_id: int = game.model.next_order_id - 1
	for i in range(3): game.customers[disabled_id]._process(10.0)
	game.employee._physics_process(0.1)
	check(game.employee.job.is_empty() and game.model.task_owner("cook", disabled_id) == "", "disabled work is not newly claimed")
	game.employee.work_enabled.cook = true
	game.employee._physics_process(0.1)
	check(game.model.task_owner("cook", disabled_id) == "employee", "enabled work is claimed before travel")
	game.employee.work_enabled.cook = false
	game.employee._physics_process(0.1)
	check(not game.employee.job.is_empty(), "turning off a work type does not interrupt current job")
	game.employee.work_enabled.cook = true
	game.reset_run()
	var stove_position: Vector2 = game.stations.stove.position
	game.stations.stove.position = Vector2(5, 5)
	game.model.request_customer()
	var blocked_id: int = game.model.next_order_id - 1
	for i in range(3): game.customers[blocked_id]._process(10.0)
	game.employee._physics_process(0.1)
	check(game.employee.failure_reason.contains("路径不可达"), "unreachable station shows reason")
	check(game.model.task_owner("cook", blocked_id) == "" and game.model.orders[blocked_id].state == "waiting", "unreachable task is released and can be retried")
	game.stations.stove.position = stove_position
	var totals: Array[int] = []
	for day in range(3):
		game.reset_run()
		for step in range(2180):
			game.model.advance(0.1)
			game.employee._physics_process(0.1)
			for customer in game.customers.values():
				if is_instance_valid(customer): customer._process(0.1)
			game._sync_stains()
			if game.model.ended: break
		check(game.model.ended and game.model.task_owners.is_empty(), "three day run reaches summary without held reservations")
		check(game.model.served > 0, "unassisted employee completes service each day")
		totals.append(game.model.served)
	print("EMPLOYEE: %d checks, %d failures; three day served counts %s" % [checks, failures, str(totals)])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
