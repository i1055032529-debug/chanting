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


func center_of(cell: Vector2i) -> Vector2:
	return Layout.ROOM_ORIGIN + (Vector2(cell) + Vector2.ONE * 0.5) * Layout.ROOM_CELL


func _run() -> void:
	var model = Day.new()
	model.coins = 1000
	check(model.can_expand(Vector2i(15, 2)) and model.can_expand(Vector2i(10, 5)), "right and bottom neighbors are available from the starting floor")
	check(not model.can_expand(Vector2i(-1, 2)) and not model.can_expand(Vector2i(2, -1)) and not model.can_expand(Vector2i(30, 2)), "left and top boundaries hold and distant ground is unavailable")
	check(Layout.frontier(model.expansion_cells).has(Vector2i(15, 2)) and Layout.frontier(model.expansion_cells).has(Vector2i(10, 5)), "the world highlights only one-step neighbors")
	var right_cells: Array[Vector2i] = [Vector2i(15, 2), Vector2i(16, 2), Vector2i(17, 2), Vector2i(15, 3), Vector2i(16, 3), Vector2i(17, 3)]
	for cell in right_cells: check(model.buy_expansion(cell), "connected right cell %s can be purchased" % cell)
	for column in range(18, 26): check(model.buy_expansion(Vector2i(column, 2)), "rightward expansion continues beyond the former reserved lot")
	var down_cells: Array[Vector2i] = [Vector2i(10, 5), Vector2i(11, 5), Vector2i(12, 5), Vector2i(10, 6), Vector2i(11, 6), Vector2i(12, 6)]
	for cell in down_cells: check(model.buy_expansion(cell), "connected bottom cell %s can be purchased" % cell)
	var bought_count := right_cells.size() + 8 + down_cells.size()
	check(model.expansion_cells.size() == bought_count and model.summary().expenses.expansion == bought_count * Day.EXPANSION_PRICE, "every purchased cell is billed once")
	var cash_before: int = model.coins
	check(not model.buy_expansion(right_cells[0]) and model.coins == cash_before, "a filled cell cannot be purchased twice")
	check(Layout.owned_bounds(model.expansion_cells).x > 1640.0 and Layout.owned_bounds(model.expansion_cells).y > 800.0, "floor bounds grow to actual purchased cells")
	var right_tables: Array[Vector2] = model.table_positions.duplicate()
	right_tables.append(Vector2(1340, 500))
	check(Layout.valid(right_tables, model.device_positions, model.expansion_cells), "right expansion accepts a reachable table")
	check(not Layout.customer_route(right_tables, Vector2(1440, 525), model.device_positions, model.expansion_cells).is_empty(), "customer route reaches the right-side table")
	check(model.move_device("sink", Vector2(1320, 490)) and model.move_device("sink", Layout.DEFAULT_DEVICES.sink), "equipment can move into and out of added floor")
	check(model.buy_table(Vector2(1340, 500)), "table can be purchased on new right-side floor")
	var down_tables: Array[Vector2] = model.table_positions.duplicate()
	down_tables.append(Vector2(920, 740))
	check(Layout.valid(down_tables, model.device_positions, model.expansion_cells), "bottom expansion accepts a reachable table")
	check(not Layout.customer_route(down_tables, Vector2(1020, 765), model.device_positions, model.expansion_cells).is_empty(), "customer route extends downward")
	check(model.start_day() and not model.can_expand(Vector2i(26, 2)), "expansion is unavailable during service")
	model.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(model.next_day() and model.expansion_cells.size() == bought_count, "purchased floor survives the next day")
	model.new_game()
	check(model.expansion_cells.is_empty() and model.table_count() == 4, "new game restores the starting floor")

	var game = Restaurant.instantiate()
	root.add_child(game)
	await process_frame
	game.model.coins = 200
	game._toggle_expansion()
	check(game.expansion_panel.visible and game.get_node("Background").preview_enabled, "expansion mode highlights candidates directly in the restaurant")
	check(game._click_expansion(center_of(right_cells[0])) and game.model.expansion_cells.has(right_cells[0]) and game.expansion_panel.visible, "clicking a highlighted world cell immediately fills it")
	check(not game._click_expansion(center_of(right_cells[0])) and game.model.summary().expenses.expansion == Day.EXPANSION_PRICE, "clicking the same cell again does not charge")
	for i in range(1, right_cells.size()): check(game._click_expansion(center_of(right_cells[i])), "world click fills another connected cell")
	game._move_camera_focus(Vector2(160, 120))
	check(game.camera_focus.x > 640.0 and game.camera_focus.y > 400.0, "expansion mode can pan right and down")
	check(game.model.buy_table(Vector2(1340, 500)), "world has room for a table after clicked purchases")
	game._sync_layout_nodes()
	await physics_frame
	game.employee._build_grid()
	check(game.employee._route_to(game.stations.table_5.interaction_position()), "employee route enters the purchased area")
	game._toggle_expansion()
	check(not game.expansion_panel.visible and not game.get_node("Background").preview_enabled and game.preopen_panel.visible, "ending expansion hides only the candidate overlays")
	check(game.get_node("Boundaries/RightWall").disabled and game.get_node("Boundaries/BottomWall").disabled, "there are no fixed right or bottom wall colliders")
	check(game.start_day(), "expanded restaurant can open for service")
	for i in range(5): game.model.request_customer()
	for step in range(120):
		for customer in game.customers.values():
			if is_instance_valid(customer): customer._process(0.1)
	check(game.model.tables[4] != 0 and game.model.orders[game.model.tables[4]].state == "waiting", "customer reaches the added-area table")
	game.player.position = Vector2(1340, 550)
	game._process(0.0)
	check(game.get_node("Camera").position.x > 640.0 and game.get_node("Camera").position.y > 400.0, "camera follows service across the expanded floor")
	game.reset_run()
	check(game.model.expansion_cells.is_empty() and game.get_node("Background").expansion_cells.is_empty() and game.camera_focus == Vector2(640, 400), "new game resets tiles and camera")
	game.queue_free()
	await process_frame
	print("OPEN GRID EXPANSION: %d checks, %d failures." % [checks, failures])
	quit(1 if failures else 0)
