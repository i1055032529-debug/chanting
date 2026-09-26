extends SceneTree
const Day = preload("res://scripts/day_model.gd")
const Layout = preload("res://scripts/layout_rules.gd")
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
	var model = Day.new()
	model.coins = 200
	var expanded_tables: Array[Vector2] = model.table_positions.duplicate()
	expanded_tables.append(Vector2(1340, 500))
	check(not model.can_expand(Vector2i(17, 2)) and not model.buy_expansion(Vector2i(17, 2)), "distant lot cells cannot be bought before a connection")
	check(not Layout.valid(expanded_tables, model.device_positions, model.expansion_cells), "unowned floor cannot hold a table")
	var cells: Array[Vector2i] = [Vector2i(15, 2), Vector2i(16, 2), Vector2i(17, 2), Vector2i(15, 3), Vector2i(16, 3), Vector2i(17, 3)]
	for cell in cells:
		check(model.can_expand(cell) and model.buy_expansion(cell), "connected cell %s can be purchased" % cell)
	check(model.expansion_cells.size() == 6 and model.coins == 200 - 6 * Day.EXPANSION_PRICE and model.summary().expenses.expansion == 6 * Day.EXPANSION_PRICE, "each purchased cell is charged once")
	check(not model.buy_expansion(cells[0]) and model.coins == 80, "an owned cell cannot be billed twice")
	check(Layout.valid(expanded_tables, model.device_positions, model.expansion_cells), "connected floor accepts a table and keeps work points accessible")
	check(not Layout.customer_route(expanded_tables, Vector2(1440, 525), model.device_positions, model.expansion_cells).is_empty(), "customer route reaches a seat in the new area")
	check(model.move_device("sink", Vector2(1320, 490)) and model.device_positions.sink == Vector2(1320, 490), "functional equipment can move onto purchased floor")
	check(model.move_device("sink", Layout.DEFAULT_DEVICES.sink), "equipment can return from the expanded area")
	check(model.buy_table(Vector2(1340, 500)) and model.table_count() == 5, "table can be bought in purchased cells")
	check(model.start_day() and not model.can_expand(Vector2i(18, 2)), "expansion is unavailable during service")
	model.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(model.next_day() and model.expansion_cells.size() == 6 and model.table_positions[4] == Vector2(1340, 500), "expanded floor and its table survive a business day")
	model.new_game()
	check(model.expansion_cells.is_empty() and model.table_count() == 4, "new game restores the starting room")

	var game = Restaurant.instantiate()
	root.add_child(game)
	await process_frame
	game.model.coins = 200
	game._toggle_expansion()
	game.expansion_buttons[cells[0]].pressed.emit()
	check(game.expansion_panel.visible and game.expansion_selected == cells[0] and not game.expansion_labels.confirm.disabled, "clicking the expansion grid previews an adjacent cell")
	game._confirm_expansion()
	check(game.model.expansion_cells.has(cells[0]) and game.layout_panel.visible and not game.expansion_panel.visible and game.camera_focus_x > 640.0, "confirming one cell reveals it and opens furniture placement")
	for i in range(1, cells.size()): check(game.model.buy_expansion(cells[i]), "scene can purchase an additional connected cell")
	game.get_node("Background").set_expansion(game.model.expansion_cells)
	check(game.model.buy_table(Vector2(1340, 500)), "scene can place a table in the expanded room")
	game._sync_layout_nodes()
	await physics_frame
	game.employee._build_grid()
	check(game.employee._route_to(game.stations.table_5.interaction_position()), "employee pathfinding enters purchased cells")
	game._toggle_layout()
	check(game.start_day(), "expanded restaurant can open for service")
	for i in range(5): game.model.request_customer()
	for step in range(120):
		for customer in game.customers.values():
			if is_instance_valid(customer): customer._process(0.1)
	check(game.model.tables[4] != 0 and game.model.orders[game.model.tables[4]].state == "waiting", "customer reaches the new-area table")
	game.player.position = Vector2(1340, 550)
	game._process(0.0)
	check(game.get_node("Camera").position.x > 640.0, "camera follows service into the expanded area")
	game.reset_run()
	check(game.model.expansion_cells.is_empty() and game.get_node("Background").expansion_cells.is_empty() and game.camera_focus_x == 640.0, "new game restores the tiled floor and camera")
	game.queue_free()
	await process_frame
	print("GRID EXPANSION: %d checks, %d failures." % [checks, failures])
	quit(1 if failures else 0)
