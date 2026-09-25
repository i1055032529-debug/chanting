extends SceneTree
const Day = preload("res://scripts/day_model.gd")
const Layout = preload("res://scripts/layout_rules.gd")
const Restaurant = preload("res://scenes/restaurant.tscn")
const RESULT := {"success": true, "doneness": 98.0, "burn": 0.0, "score": 90, "grade": "出色"}
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
	var model = Day.new()
	check(Layout.valid(model.table_positions), "starting room keeps all tables and workstations reachable")
	var fifth: Array[Vector2] = model.table_positions.duplicate()
	fifth.append(Day.FIFTH_TABLE_POSITION)
	check(Layout.valid(fifth), "suggested fifth table fits and remains reachable")
	check(Layout.customer_route(fifth, Day.FIFTH_TABLE_POSITION + Vector2(100, 25)).size() > 0, "customer route reaches a new table through the walkable floor")
	check(not model.move_device("stove", model.device_positions.stove_2) and model.device_positions.stove == Vector2(635, 384), "functional equipment cannot overlap another station")
	check(not model.move_device("sink", Vector2(1250, 384)), "functional equipment cannot leave the room")
	check(model.move_device("stove", Vector2(1100, 580)) and model.device_positions.stove == Vector2(1100, 580), "existing stove can be repositioned across the room")
	check(model.move_device("stove_2", Vector2(765, 404)) and model.move_device("pass", Vector2(900, 374)) and model.move_device("sink", Vector2(1120, 384)), "both stoves, serving counter and sink can all move")
	check(not model.move_table(0, model.table_positions[1]) and model.table_positions[0] == Day.STARTING_TABLE_POSITIONS[0], "overlap cannot move existing furniture")
	check(not model.move_table(0, Vector2(500, 520)), "furniture cannot cover the player's starting position")
	check(not model.move_table(0, Vector2(1250, 500)), "placement outside the room is rejected")
	check(not model.buy_table(model.table_positions[0]) and model.coins == Day.STARTING_CASH, "invalid purchase charges nothing")
	check(model.move_table(0, Vector2(530, 480)) and model.table_positions[0] == Vector2(530, 480), "valid placement updates the layout")
	check(model.buy_table() and model.table_count() == 5 and model.tables.size() == 5 and model.coins == Day.STARTING_CASH - Day.TABLE_PRICE, "buying a table adds a fifth service slot")
	check(not model.buy_table() and model.summary().expenses.furniture == Day.TABLE_PRICE, "fifth table cannot be billed twice")
	check(not model.upgrade_equipment() and model.equipment_level == 0, "upgrade respects the available balance")
	model.coins = 100
	check(model.upgrade_equipment() and model.equipment_level == 1 and is_equal_approx(model.cooking_speed_multiplier(), 1.25), "equipment upgrades cooking speed")
	check(not model.upgrade_equipment() and model.summary().expenses.equipment == Day.EQUIPMENT_PRICE, "equipment can be bought and billed only once")
	check(model.start_day() and not model.move_table(0, Vector2(530, 460)) and not model.move_device("stove", Vector2(635, 384)) and not model.buy_table(), "furniture and equipment cannot move during service")
	for i in range(5):
		check(model.request_customer(), "fifth table can receive arrivals")
	check(model.tables[4] != 0 and model.orders[model.tables[4]].table == 4, "fifth table receives a distinct order")
	var order_id: int = model.tables[4]
	model.seat_customer(order_id)
	model.selected_order_id = order_id
	check(model.start_cooking() and model.complete_cooking(order_id, model.orders[order_id].cook_attempt, RESULT), "fifth-table order can be cooked")
	check(model.interact("pass") and model.interact("table_5") and model.orders[order_id].state == "eating", "fifth table can be served")
	model.advance(Day.EAT_SECONDS)
	model.customer_departed(order_id)
	check(model.interact("table_5") and model.interact("sink") and model.tables[4] == 0, "fifth table can have plates cleared")
	model.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(model.next_day() and model.table_count() == 5 and model.equipment_level == 1 and model.table_positions[0] == Vector2(530, 480) and model.device_positions.stove == Vector2(1100, 580), "furniture, equipment positions and upgrades survive the next business day")
	model.new_game()
	check(model.table_count() == 4 and model.equipment_level == 0 and model.table_positions == Day.STARTING_TABLE_POSITIONS and model.device_positions == Layout.DEFAULT_DEVICES, "new game resets furniture, equipment positions and upgrade")
	var game = Restaurant.instantiate()
	root.add_child(game)
	await process_frame
	game._toggle_layout()
	game._begin_layout_preview(false)
	game._move_layout_preview(Vector2(0, 20))
	check(game.layout_editing and game._preview_layout_valid() and game.model.table_positions[0] == Day.STARTING_TABLE_POSITIONS[0], "moving furniture previews without changing the model")
	game._cancel_layout_preview()
	check(not game.layout_editing and game.table_nodes[0].visible and game.model.table_positions[0] == Day.STARTING_TABLE_POSITIONS[0], "cancel restores the original furniture with no charge")
	game._begin_layout_preview(true)
	game._confirm_layout_preview()
	check(game.model.table_count() == 5 and game.table_nodes.size() == 5 and game.stations.has("table_5") and game.order_cards[4].visible, "buying table updates the rendered room and order card")
	for id in Day.DEVICE_IDS:
		game.layout_selected = game.model.table_count() + Day.DEVICE_IDS.find(id)
		game._refresh_layout_panel()
		check(game.layout_labels.selected.text.contains(game.stations[id].display_name), "layout panel exposes each functional station")
	game.layout_selected = game.model.table_count()
	game._begin_layout_preview(false)
	game._move_layout_preview(Vector2(465, 196))
	check(game._preview_layout_valid() and game.model.device_positions.stove == Vector2(635, 384), "stove preview leaves the original in place")
	game._cancel_layout_preview()
	check(game.stations.stove.visible and game.stations.stove.position == Vector2(635, 384), "cancelling a station move restores it")
	game._begin_layout_preview(false)
	game._move_layout_preview(Vector2(465, 196))
	game._confirm_layout_preview()
	check(game.model.device_positions.stove == Vector2(1100, 580) and game.stations.stove.position == Vector2(1100, 580), "confirming a station move updates model and scene")
	for device_id in ["stove_2", "pass", "sink"]:
		var offset: Vector2 = {"stove_2": Vector2(0, 20), "pass": Vector2(0, -10), "sink": Vector2(20, 0)}[device_id]
		game.layout_selected = game.model.table_count() + Day.DEVICE_IDS.find(device_id)
		game._begin_layout_preview(false)
		game._move_layout_preview(offset)
		var valid_preview: bool = game._preview_layout_valid()
		game._confirm_layout_preview()
		check(valid_preview and game.stations[device_id].position == Layout.DEFAULT_DEVICES[device_id] + offset, "placement preview and scene update work for " + device_id)
	game._select_layout_at(game.stations.sink.position)
	check(game._layout_device_id() == "sink", "clicking a functional station selects it for placement")
	await physics_frame
	game.employee._build_grid()
	check(game.employee._route_to(game.stations.table_5.interaction_position()), "employee pathfinding reaches the fifth table")
	check(game.employee._route_to(game.stations.stove.interaction_position()), "employee pathfinding reaches the moved stove")
	check(game.employee._route_to(game.stations.pass.interaction_position()) and game.employee._route_to(game.stations.sink.interaction_position()), "employee pathfinding reaches moved serving and dish stations")
	game.model.coins = 100
	game._upgrade_equipment()
	check(game.model.equipment_level == 1 and game.layout_labels.upgrade.disabled, "equipment upgrade changes the model")
	game._toggle_layout()
	game.model.hire_employee()
	check(game.start_day(), "upgraded room can start service")
	for i in range(5): game.model.request_customer()
	for step in range(120):
		for customer in game.customers.values():
			if is_instance_valid(customer): customer._process(0.1)
	check(game.model.tables[4] != 0 and game.model.orders[game.model.tables[4]].state == "waiting", "customer walks to the fifth table and orders")
	game.player.position = game.target_position("stove")
	check(game.try_interact("stove") and is_equal_approx(game.cooking_screen.recipe_speed, Day.RECIPES[game.model.orders[1].recipe].speed * 1.25), "player can use the moved stove at upgraded speed")
	check(game.model.claim_task("cook", 2, "employee", "stove_2"), "employee can reserve the other upgraded stove")
	game.employee.job = {"kind": "cook", "id": 2, "table": 1}
	game.employee.stage = "moving"
	game.employee._arrived()
	check(is_equal_approx(game.employee.cook_rules.recipe_speed, Day.RECIPES[game.model.orders[2].recipe].speed * 1.25), "employee cooking uses upgraded speed")
	check(game.model.complete_cooking(1, game.model.orders[1].cook_attempt, RESULT), "moved stove completes food")
	game._close_cooking()
	game.player.position = game.target_position("pass")
	check(game.try_interact("pass"), "player picks up food from the moved serving counter")
	game.player.position = game.target_position("table_1")
	check(game.try_interact("table_1"), "player serves from moved counter to a table")
	game.model.advance(Day.EAT_SECONDS)
	game.model.customer_departed(1)
	game.player.position = game.target_position("table_1")
	check(game.try_interact("table_1"), "player clears the table after the customer leaves")
	game.player.position = game.target_position("sink")
	check(game.try_interact("sink") and game.model.tables[0] == 0, "player returns a plate to the moved dish station")
	game.queue_free()
	await process_frame
	var wandering = Restaurant.instantiate()
	root.add_child(wandering)
	await process_frame
	wandering.model.hire_employee()
	wandering.start_day()
	var worker = wandering.employee
	var initial: Vector2 = worker.position
	var previous: Vector2 = initial
	var max_step := 0.0
	for i in range(120):
		worker._physics_process(0.1)
		max_step = maxf(max_step, worker.position.distance_to(previous))
		previous = worker.position
	check(worker.position.distance_to(initial) > 8.0 and worker.position.distance_to(initial) < 150.0 and max_step <= worker.IDLE_SPEED * 0.1 + 0.01, "idle worker wanders locally at a slow speed")
	wandering.model.request_customer()
	wandering.model.seat_customer(1)
	worker._physics_process(0.1)
	check(not worker.job.is_empty() and worker.job.kind == "cook", "wandering worker immediately switches to an available task")
	wandering.queue_free()
	await process_frame
	print("LAYOUT AND EQUIPMENT: %d checks, %d failures." % [checks, failures])
	quit(1 if failures else 0)
