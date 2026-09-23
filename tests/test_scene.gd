extends SceneTree

const Restaurant = preload("res://scenes/restaurant.tscn")
const Bot = preload("res://tests/cooking_bot.gd")
const Model = preload("res://scripts/service_model.gd")
var checks := 0
var failures := 0
var game: Node2D


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	game = Restaurant.instantiate()
	root.add_child(game)
	await process_frame
	check(game.player != null, "player created")
	check(not game.try_interact("stove"), "distant interaction rejected")
	game.model.request_customer()
	check(game.customer != null, "arrival signal creates customer")
	# Drive real customer path to completion without real-time waiting.
	for i in range(3):
		game.customer._process(10.0)
	check(game.model.phase == Model.Phase.WAITING, "customer walking emits seating and order")
	game.player.position = game.target_position("stove")
	check(game.closest_target() == "stove", "operation position selects stove")
	check(game.try_interact("stove"), "scene starts cooking")
	check(is_instance_valid(game.cooking_screen), "stove opens dedicated cooking screen")
	check(game.player.locked, "restaurant movement locked during cooking")
	check(not game.try_interact("pass"), "cooking blocks restaurant interaction")
	game.cooking_screen.start_round()
	var result: Dictionary = Bot.finish(game.cooking_screen.rules)
	check(game.model.phase == Model.Phase.COOKING, "result waits for acknowledgment")
	game.cooking_screen.acknowledge()
	check(not is_instance_valid(game.cooking_screen), "acknowledgment closes cooking screen")
	check(game.model.phase == Model.Phase.READY, "scene updates cooking")
	game.player.position = game.target_position("pass")
	check(game.try_interact("pass"), "scene picks up food")
	game.player.position = game.target_position("table")
	check(game.try_interact("table"), "scene serves food")
	game._process(Model.EAT_SECONDS)
	check(game.model.coins == 18 + preload("res://scripts/cooking/cooking_model.gd").bonus_for_result(result) and game.customer.leaving, "payment and departure connected")
	for i in range(3):
		game.customer._process(10.0)
	check(game.model.phase == Model.Phase.DIRTY, "departure enables clearing")
	check(game.try_interact("table"), "scene picks up dirty plate")
	game.player.position = game.target_position("sink")
	check(game.try_interact("sink"), "scene recycles plate")
	check(game.model.completed_cycles == 1, "scene completes entire service")
	await process_frame
	# Moving furniture in the editor also moves its collision and interaction point.
	var station: Node2D = game.stations["stove"]
	var original: Vector2 = station.position
	var old_target: Vector2 = game.target_position("stove")
	station.position += Vector2(25, 0)
	check(game.target_position("stove").is_equal_approx(old_target + Vector2(25, 0)), "furniture movement updates interaction point")
	station.position = original
	# Collision tests use actual CharacterBody2D movement and fixed physics ticks.
	game.player.position = Vector2(75, 520)
	Input.action_press("move_left")
	for i in range(30):
		await physics_frame
	Input.action_release("move_left")
	check(game.player.position.x >= 59.0, "wall blocks player")
	game.player.position = game.target_position("stove")
	Input.action_press("move_up")
	for i in range(25):
		await physics_frame
	Input.action_release("move_up")
	check(game.player.position.y >= 395.0, "stove blocks player")
	# Pause through input event handling, then resume through the always-active node.
	var pause_event := InputEventKey.new()
	pause_event.keycode = KEY_ESCAPE
	pause_event.physical_keycode = KEY_ESCAPE
	pause_event.pressed = true
	Input.parse_input_event(pause_event)
	Input.flush_buffered_events()
	await process_frame
	check(paused and game.pause_panel.visible, "Escape pauses game")
	var before: float = game.model.spawn_clock
	for i in range(3):
		await process_frame
	check(is_equal_approx(before, game.model.spawn_clock), "paused simulation does not advance")
	var release := pause_event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	Input.parse_input_event(pause_event)
	Input.flush_buffered_events()
	await process_frame
	check(not paused, "Escape resumes game")
	game.reset_run()
	await process_frame
	check(not is_instance_valid(game.customer) and game.model.coins == 0, "reset cleans customer and money")
	game.model.request_customer()
	game.reset_run()
	await process_frame
	check(game.model.phase == Model.Phase.EMPTY, "reset during arrival is safe")
	print("SCENE INTEGRATION: %d checks, %d failures." % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
