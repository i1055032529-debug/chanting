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
	var model = Day.new(0, 60)
	model.coins = 3000
	var first_right := Vector2i(Layout.INITIAL_COLUMNS, 2)
	var first_down := Vector2i(10, Layout.ROOM_ROWS)
	check(Layout.TILE_SIZE == 32 and Layout.ROOM_CELL == 32.0, "room uses one 32x32 tile per expansion cell")
	check(model.can_expand(first_right) and model.can_expand(first_down) and not model.can_expand(Vector2i(10, 5)), "the starting floor keeps its area and expands by 32-pixel cells")
	check(not model.can_expand(Vector2i(-1, 2)) and not model.can_expand(Vector2i(2, -1)) and not model.can_expand(Vector2i(50, 2)), "left and top boundaries hold and distant ground is unavailable")
	check(Layout.frontier(model.expansion_cells).has(first_right) and Layout.frontier(model.expansion_cells).has(first_down), "the world highlights only one-step neighbors")
	var right_cells: Array[Vector2i] = []
	for row in range(4, 10):
		for column in range(Layout.INITIAL_COLUMNS, 45): right_cells.append(Vector2i(column, row))
	for cell in right_cells: check(model.buy_expansion(cell), "connected right cell %s can be purchased" % cell)
	var down_cells: Array[Vector2i] = []
	for row in range(Layout.ROOM_ROWS, 24):
		for column in range(24, 35): down_cells.append(Vector2i(column, row))
	for cell in down_cells: check(model.buy_expansion(cell), "connected bottom cell %s can be purchased" % cell)
	var bought_count := right_cells.size() + down_cells.size()
	check(model.expansion_cells.size() == bought_count and model.summary().expenses.expansion == bought_count * Day.EXPANSION_PRICE, "every purchased cell is billed once")
	var cash_before: int = model.coins
	check(not model.buy_expansion(right_cells[0]) and model.coins == cash_before, "a filled cell cannot be purchased twice")
	check(Layout.owned_bounds(model.expansion_cells).x > 1440.0 and Layout.owned_bounds(model.expansion_cells).y > 1000.0, "floor bounds grow to actual purchased cells")
	var right_tables: Array[Vector2] = model.table_positions.duplicate()
	right_tables.append(Vector2(1340, 500))
	check(Layout.valid(right_tables, model.device_positions, model.expansion_cells), "right expansion accepts a reachable table")
	check(not Layout.customer_route(right_tables, Vector2(1440, 525), model.device_positions, model.expansion_cells).is_empty(), "customer route reaches the right-side table")
	check(model.move_device("sink", Vector2(1320, 490)) and model.move_device("sink", Layout.DEFAULT_DEVICES.sink), "equipment can move into and out of added floor")
	check(model.buy_table(Vector2(1340, 500)), "table can be purchased on new right-side floor")
	var down_tables: Array[Vector2] = model.table_positions.duplicate()
	down_tables.append(Vector2(920, 975))
	check(Layout.valid(down_tables, model.device_positions, model.expansion_cells), "bottom expansion accepts a reachable table")
	check(not Layout.customer_route(down_tables, Vector2(1020, 1000), model.device_positions, model.expansion_cells).is_empty(), "customer route extends downward")
	check(model.start_day() and not model.can_expand(Vector2i(45, 4)), "expansion is unavailable during service")
	model.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(model.next_day() and model.expansion_cells.size() == bought_count, "purchased floor survives the next day")
	model.new_game()
	check(model.expansion_cells.is_empty() and model.table_count() == 4, "new game restores the starting floor")

	var game = Restaurant.instantiate()
	game.model = Day.new(0, 60)
	root.add_child(game)
	await process_frame
	game.model.coins = 300
	game._toggle_expansion()
	var background = game.get_node("Background")
	check(game.expansion_panel.visible and background.preview_enabled and background.FLOOR_TILE_SIZE == Layout.TILE_SIZE * 2, "64-pixel pictures span four 32-pixel expansion cells")
	check(background.floor_variant_by_tile.size() == 4, "each alternate floor picture occurs only once")
	check(game._click_expansion(center_of(right_cells[0])) and game.model.expansion_cells.has(right_cells[0]) and game.expansion_panel.visible, "clicking a highlighted world cell immediately fills it")
	var first_corner := Layout.ROOM_ORIGIN + Vector2(right_cells[0]) * Layout.TILE_SIZE
	var cropped_floor := false
	for child in background.get_children():
		if child is Sprite2D and child.position == first_corner and child.region_enabled and child.region_rect.size == Vector2(32, 32): cropped_floor = true
	check(cropped_floor, "buying one cell reveals only one quarter of its 64-pixel floor picture")
	check(not game._click_expansion(center_of(right_cells[0])) and game.model.summary().expenses.expansion == Day.EXPANSION_PRICE, "clicking the same cell again does not charge")
	for i in range(1, right_cells.size()): check(game._click_expansion(center_of(right_cells[i])), "world click fills another connected cell")
	var complete_floor := false
	for child in background.get_children():
		if child is Sprite2D and child.position == first_corner and not child.region_enabled and child.texture.get_size() == Vector2(64, 64): complete_floor = true
	check(complete_floor, "four purchased cells restore one complete 64-pixel floor picture")
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
