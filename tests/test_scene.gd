extends SceneTree

const Restaurant = preload("res://scenes/restaurant.tscn")
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
	game.player.position = game.TARGETS.stove
	check(game.closest_target() == "stove", "operation position selects stove")
	check(game.try_interact("stove"), "scene starts cooking")
	game._process(Model.COOK_SECONDS)
	check(game.model.phase == Model.Phase.READY, "scene updates cooking")
	game.player.position = game.TARGETS.pass
	check(game.try_interact("pass"), "scene picks up food")
	game.player.position = game.TARGETS.table
	check(game.try_interact("table"), "scene serves food")
	game._process(Model.EAT_SECONDS)
	check(game.model.coins == 18 and game.customer.leaving, "payment and departure connected")
	for i in range(3):
		game.customer._process(10.0)
	check(game.model.phase == Model.Phase.DIRTY, "departure enables clearing")
	check(game.try_interact("table"), "scene picks up dirty plate")
	game.player.position = game.TARGETS.sink
	check(game.try_interact("sink"), "scene recycles plate")
	check(game.model.completed_cycles == 1, "scene completes entire service")
	await process_frame
	# Collision tests use actual CharacterBody2D movement and fixed physics ticks.
	game.player.position = Vector2(70, 430)
	Input.action_press("move_left")
	for i in range(30):
		await physics_frame
	Input.action_release("move_left")
	check(game.player.position.x >= 57.0, "wall blocks player")
	game.player.position = Vector2(148, 310)
	Input.action_press("move_up")
	for i in range(25):
		await physics_frame
	Input.action_release("move_up")
	check(game.player.position.y >= 291.0, "stove blocks player")
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
