extends SceneTree

const Model = preload("res://scripts/service_model.gd")
var checks := 0
var failures := 0
const DISH := {"success": true, "doneness": 82.0, "burn": 0.0, "score": 60, "grade": "合格"}


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var game := Model.new()
	check(not game.interact("stove"), "cannot cook without an order")
	check(not game.interact("pass"), "cannot take nonexistent food")
	check(not game.interact("sink"), "cannot recycle empty hands")
	var last_task_id := 0
	for cycle in range(1, 11):
		game.advance(Model.ARRIVAL_DELAY)
		check(game.phase == Model.Phase.ARRIVING, "auto arrival %d" % cycle)
		check(not game.request_customer(), "table reservation blocks duplicate customer")
		check(game.seat_customer(), "seat customer")
		check(not game.seat_customer(), "no duplicate order from duplicate seating callback")
		check(game.order_id == cycle, "unique sequential order ID")
		check(not game.interact("table"), "cannot serve empty hands")
		check(game.interact("stove"), "start cooking")
		check(not game.interact("stove"), "cannot duplicate cooking")
		check(not game.interact("pass"), "cannot collect unfinished food")
		game.advance(1.4)
		check(game.phase == Model.Phase.COOKING, "cooking waits for player result")
		game.advance(10.0)
		check(game.phase == Model.Phase.COOKING, "timer alone never produces food")
		check(game.complete_cooking(game.order_id, game.cooking_attempt, DISH), "accept valid cooking result")
		check(not game.complete_cooking(game.order_id, game.cooking_attempt, DISH), "duplicate result rejected")
		check(game.phase == Model.Phase.READY, "dish goes to counter")
		check(not game.interact("stove"), "cannot remake a ready order")
		check(game.interact("pass"), "pick up food")
		check(game.carrying == Model.Carry.FOOD, "food carried")
		check(not game.interact("stove"), "occupied hands reject cooking")
		check(not game.interact("sink"), "food cannot be recycled as a plate")
		check(game.carrying == Model.Carry.FOOD, "invalid action preserves item")
		check(game.interact("pass"), "can put food back")
		check(game.phase == Model.Phase.READY and game.carrying == Model.Carry.NONE, "put-back preserves exactly one dish")
		check(game.interact("pass"), "can take returned food")
		check(game.interact("table"), "serve matching order")
		check(not game.interact("table"), "duplicate serve has no effect")
		game.advance(Model.EAT_SECONDS)
		check(game.coins == Model.PRICE * cycle, "one payment per order")
		game.advance(999.0)
		check(game.coins == Model.PRICE * cycle, "no repeated payment during departure")
		check(not game.interact("table"), "cannot clear before customer leaves")
		check(game.customer_departed(), "customer completes departure")
		check(not game.customer_departed(), "duplicate departure is safe")
		check(not game.request_customer(), "dirty table blocks new arrival")
		game.advance(999.0)
		check(game.phase == Model.Phase.DIRTY, "dirty table remains blocked")
		check(game.interact("table"), "pick up plate")
		check(not game.interact("table"), "cannot pick up second plate")
		check(not game.interact("pass"), "plate cannot become food")
		check(not game.request_customer(), "table blocked until recycling")
		check(game.interact("sink"), "recycle plate")
		check(not game.interact("sink"), "cannot recycle twice")
		check(game.phase == Model.Phase.EMPTY and game.carrying == Model.Carry.NONE, "cycle restores clean table and hands")
		check(game.completed_cycles == cycle and game.served == cycle, "cycle and served totals")
		check(game.tasks.size() == 3, "one cook, serve and clear task per order")
		for task in game.tasks:
			check(task.state == "done" and task.id > last_task_id, "tasks finish with unique IDs")
			last_task_id = task.id
	# Exercise reset with an active order and held item.
	game.request_customer()
	game.seat_customer()
	game.interact("stove")
	game.complete_cooking(game.order_id, game.cooking_attempt, DISH)
	game.interact("pass")
	game.reset()
	check(game.phase == Model.Phase.EMPTY and game.carrying == Model.Carry.NONE, "reset releases active items")
	check(game.coins == 0 and game.order_id == 0 and game.tasks.is_empty(), "reset clears counters and tasks")
	game.advance(-1.0)
	check(game.spawn_clock == 0.0, "negative delta ignored")
	# A canceled or pre-reset attempt cannot deliver into a later session.
	game.request_customer()
	game.seat_customer()
	game.interact("stove")
	var stale_order: int = game.order_id
	var stale_attempt: int = game.cooking_attempt
	check(game.cancel_cooking(stale_order, stale_attempt), "abandon returns order to waiting")
	check(game.tasks.size() == 1 and game.tasks[0].state == "pending", "abandon releases cooking task")
	game.interact("stove")
	check(not game.complete_cooking(stale_order, stale_attempt, DISH), "old attempt cannot replace current attempt")
	check(not game.complete_cooking(game.order_id, game.cooking_attempt, {"success": true, "doneness": 20.0, "burn": 0.0}), "raw result rejected")
	check(not game.complete_cooking(game.order_id, game.cooking_attempt, {"success": false}), "failed cooking cannot create food")
	game.reset()
	game.request_customer()
	game.seat_customer()
	game.interact("stove")
	check(not game.complete_cooking(stale_order, stale_attempt, DISH), "reset invalidates earlier callbacks even when order IDs repeat")
	var premium := {"success": true, "doneness": 98.0, "burn": 0.0, "score": 100, "grade": "出色"}
	check(game.complete_cooking(game.order_id, game.cooking_attempt, premium), "premium result accepted")
	check(game.coins == 0 and game.quality_bonus == 6, "bonus waits for customer payment")
	game.interact("pass")
	game.interact("table")
	game.advance(Model.EAT_SECONDS)
	check(game.coins == 24, "customer pays base plus quality bonus once")
	game.advance(100.0)
	check(game.coins == 24, "bonus cannot be paid twice")
	print("SERVICE MODEL: %d checks, %d failures; 10 complete service cycles." % [checks, failures])
	quit(1 if failures else 0)
