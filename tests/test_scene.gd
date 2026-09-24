extends SceneTree
const Restaurant = preload("res://scenes/restaurant.tscn")
const Bot = preload("res://tests/cooking_bot.gd")
const Day = preload("res://scripts/day_model.gd")
var checks := 0
var failures := 0
var game: Node2D

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	game = Restaurant.instantiate()
	root.add_child(game)
	game.employee.enabled = false
	await process_frame
	check(game.model.phase == "preopen" and not game.model.request_customer(), "new game waits for opening")
	check(game.start_day() and not game.start_day(), "opening happens once")
	check(game.player != null and game.stations.size() == 8, "four tables and four workstations created")
	check(not game.try_interact("stove"), "distant interaction rejected")
	check(game.model.request_customer() and game.model.request_customer(), "two customers reserve tables")
	check("香煎蛋饭 7" in game.labels.capacity.text and "番茄炒面 7" in game.labels.capacity.text and "鸡蛋拌面 7" in game.labels.capacity.text, "service HUD shows remaining portions for all dishes after reservation")
	for customer in game.customers.values():
		for i in range(3): customer._process(10.0)
	check(game.model.orders[1].state == "waiting" and game.model.orders[2].state == "waiting", "two orders coexist")
	game.model.select_next()
	check(game.model.selected_order_id == 2, "player can choose second order")
	game.player.position = game.target_position("stove")
	check(game.try_interact("stove"), "stove opens selected order")
	check(is_instance_valid(game.cooking_screen) and game.cooking_screen.recipe_id == "noodles", "second recipe reaches minigame")
	check(game.player.locked and not game.try_interact("pass"), "cooking locks restaurant controls")
	game.cooking_screen.start_round()
	var result: Dictionary = Bot.finish(game.cooking_screen.rules)
	game.cooking_screen.acknowledge()
	check(game.model.pass_order_id == 2 and game.cooking_screen == null, "cooking returns correct dish to pass")
	game.player.position = game.target_position("pass")
	check(game.try_interact("pass"), "player takes food")
	game.player.position = game.target_position("table_1")
	check(not game.try_interact("table_1"), "wrong table cannot take food")
	game.player.position = game.target_position("table_2")
	check(game.try_interact("table_2"), "correct table receives food")
	game.model.advance(Day.EAT_SECONDS)
	check(game.model.coins == Day.STARTING_CASH + 24 + preload("res://scripts/cooking/cooking_model.gd").bonus_for_result(result), "quality and recipe price settle once")
	for i in range(3):
		if game.customers.has(2): game.customers[2]._process(10.0)
	check(game.model.orders[2].state == "dirty", "customer departure creates clearing task")
	check(game.try_interact("table_2"), "player collects plate")
	game.player.position = game.target_position("sink")
	check(game.try_interact("sink") and game.model.tables[1] == 0, "plate recycling frees table")
	game.model.stains.append({"id": 999, "table": 0})
	game._process(0.0)
	check(game.stations.has("stain_999"), "world displays bounded stain job")
	game.player.position = game.target_position("stain_999")
	check(game.try_interact("stain_999") and game.model.stains.is_empty(), "player cleans visible stain")
	game.reset_run()
	game.model.set_employee_hired(true)
	game.start_day()
	check(game.stations.has("stove_2") and game.target_position("stove").distance_to(game.target_position("stove_2")) > 100.0, "both cooking positions are separately reachable")
	game.model.request_customer()
	game.model.request_customer()
	var simultaneous_ids: Array = game.model.orders.keys()
	simultaneous_ids.sort()
	for id in simultaneous_ids: game.model.seat_customer(id)
	var employee_id: int = simultaneous_ids[0]
	var player_id: int = simultaneous_ids[1]
	check(game.model.claim_task("cook", employee_id, "employee", "stove") and game.model.start_cooking_as(employee_id, "employee"), "employee cooks at first position")
	game.model.selected_order_id = player_id
	game.player.position = game.target_position("stove_2")
	check(game.try_interact("stove_2") and game.cooking_screen.order_id == player_id, "player opens minigame at second position while employee cooks")
	game.model.orders[employee_id].waited = Day.PATIENCE - 1.0
	game.model.advance(2.0)
	check(is_instance_valid(game.cooking_screen) and game.model.orders[player_id].state == "cooking", "employee order timeout does not close player's minigame")
	game.reset_run()
	game.start_day()
	game.model.request_customer()
	for i in range(3): game.customers[game.model.next_order_id - 1]._process(10.0)
	game.player.position = game.target_position("stove")
	game.try_interact("stove")
	game.model.advance(Day.PATIENCE + 0.1)
	check(game.cooking_screen == null and game.model.cooking_order_id == 0, "timeout during cooking closes overlay and frees stove")
	game.reset_run()
	game.start_day()
	game.model.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(game.model.ended and game.summary_panel.visible, "day summary appears")
	game.reset_run()
	check(game.model.phase == "preopen" and game.model.coins == Day.STARTING_CASH, "new game resets progress and enters preparation")
	game.start_day()
	# Real player collision and pause remain valid with new layout.
	game.player.position = Vector2(75, 520)
	Input.action_press("move_left")
	for i in range(30): await physics_frame
	Input.action_release("move_left")
	check(game.player.position.x >= 59.0, "wall blocks player")
	var pause_event := InputEventKey.new()
	pause_event.keycode = KEY_ESCAPE
	pause_event.physical_keycode = KEY_ESCAPE
	pause_event.pressed = true
	Input.parse_input_event(pause_event)
	Input.flush_buffered_events()
	await process_frame
	check(paused and game.pause_panel.visible, "Escape pauses day")
	var before: float = game.model.elapsed
	for i in range(3): await process_frame
	check(is_equal_approx(before, game.model.elapsed), "paused day and patience freeze")
	var release := pause_event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Input.parse_input_event(pause_event)
	Input.flush_buffered_events()
	await process_frame
	check(not paused, "Escape resumes day")
	print("SCENE INTEGRATION: %d checks, %d failures." % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
