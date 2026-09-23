extends SceneTree
const Bot = preload("res://tests/cooking_bot.gd")
const Day = preload("res://scripts/day_model.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func key(code: Key, down: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _run() -> void:
	var game = preload("res://scenes/restaurant.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.model.request_customer()
	for i in range(3): game.customers[1]._process(10.0)
	game.player.position = game.target_position("stove")
	key(KEY_E)
	key(KEY_E, false)
	var screen = game.cooking_screen
	check(is_instance_valid(screen), "interaction opens cooking")
	check(screen.rules.state == screen.Rules.State.READY, "entering key does not start or plate")
	key(KEY_SPACE)
	check(screen.heating and screen.rules.state == screen.Rules.State.RUNNING, "space starts and heats")
	key(KEY_ESCAPE)
	key(KEY_ESCAPE, false)
	check(paused and game.pause_panel.visible, "cooking pauses with menu above overlay")
	check(not screen.heating, "pause clears held heat")
	var elapsed: float = screen.rules.elapsed
	for i in range(3): await process_frame
	check(is_equal_approx(elapsed, screen.rules.elapsed), "paused cooking freezes")
	key(KEY_SPACE, false)
	key(KEY_ESCAPE)
	key(KEY_ESCAPE, false)
	check(not paused and not screen.heating, "resume does not retain heat")
	key(KEY_B)
	key(KEY_B, false)
	check(game.cooking_screen == null and game.model.orders[1].state == "waiting", "cancel keeps order available")
	await process_frame
	game.try_interact("stove")
	screen = game.cooking_screen
	screen.start_round()
	screen.rules.advance(45.1, false)
	check(not screen.rules.result.success, "failed cooking shows retry")
	key(KEY_E)
	key(KEY_E, false)
	check(screen.rules.state == screen.Rules.State.RUNNING and screen.rules.elapsed == 0.0, "retry starts fresh rules")
	Bot.finish(screen.rules)
	key(KEY_E)
	key(KEY_E, false)
	check(game.cooking_screen == null and game.model.pass_order_id == 1, "acknowledge returns with food ready")
	check(game.model.carrying == Day.Carry.NONE, "acknowledge does not trigger restaurant pickup")
	game.reset_run()
	await process_frame
	game.model.request_customer()
	var id: int = game.model.next_order_id - 1
	for i in range(3): game.customers[id]._process(10.0)
	game.player.position = game.target_position("stove")
	game.try_interact("stove")
	game.reset_run()
	await process_frame
	check(game.cooking_screen == null and not game.player.locked, "reset closes cooking and unlocks player")
	print("COOKING SCREEN: %d checks, %d failures." % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
