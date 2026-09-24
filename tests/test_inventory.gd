extends SceneTree
const Day = preload("res://scripts/day_model.gd")
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
	var shop = Day.new()
	check(shop.coins == Day.STARTING_CASH and shop.inventory.rice == 8 and shop.ingredient_available("rice") == 8, "new run has starter cash and pantry")
	check(shop.portions_available("rice") == 8 and shop.portions_available("noodles") == 8, "recipe portions reflect required ingredients")
	check(shop.purchase("rice", 3), "preopening purchase succeeds")
	check(shop.inventory.rice == 11 and shop.coins == Day.STARTING_CASH - 6 and shop.summary().expenses.purchase == 6, "purchase adds stock and writes one cash expense")
	check(not shop.purchase("rice", 0) and not shop.purchase("unknown", 1) and not shop.purchase("tomato", 99), "invalid and unaffordable purchases do not change stock")
	check(shop.ledger.size() == 1 and shop.inventory.tomato == 8, "failed purchases add no ledger entries")
	check(shop.set_menu_enabled("noodles", false) and not shop.set_menu_enabled("rice", false), "menu can stop one dish but cannot close all dishes")
	check(shop.start_day() and not shop.purchase("egg", 1) and not shop.set_menu_enabled("noodles", true), "purchasing and menu edits close during service")
	check(shop.request_customer() and shop.request_customer(), "two orders can reserve ingredients")
	check(shop.orders[1].recipe == "rice" and shop.orders[2].recipe == "rice", "stopped dish falls back to available menu item")
	check(shop.reserved_inventory.rice == 2 and shop.reserved_inventory.egg == 2 and shop.ingredient_available("egg") == 6, "orders reserve each ingredient once")
	shop.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(shop.reserved_inventory.rice == 0 and shop.inventory.rice == 11, "closing day releases ingredients reserved for unstarted arrivals")
	check(shop.next_day() and shop.inventory.rice == 11 and not shop.menu_enabled.noodles and shop.ledger.is_empty(), "purchased stock and menu survive the next day")
	var scarce = Day.new()
	scarce.inventory = {"rice": 2, "egg": 2, "noodles": 0, "tomato": 0}
	scarce.set_menu_enabled("noodles", false)
	check(scarce.start_day(), "scarce pantry can open with two portions")
	check(scarce.request_customer() and scarce.request_customer(), "first two simultaneous orders reserve the only portions")
	check(not scarce.request_customer() and scarce.orders.size() == 2 and scarce.reserved_inventory.rice == 2, "third order cannot overbook stock")
	check(scarce.cancel_order(1) and scarce.reserved_inventory.rice == 1 and scarce.inventory.rice == 2, "pre-cooking cancellation releases reservation without consuming stock")
	check(scarce.customer_departed(1), "canceled customer clears table")
	check(scarce.request_customer() and scarce.reserved_inventory.rice == 2, "released portion can serve a new order")
	var replacement: int = scarce.next_order_id - 1
	scarce.seat_customer(2)
	check(scarce.claim_task("cook", 2, "employee", "stove"), "employee can reserve cooking task without consuming another portion")
	check(scarce.inventory.rice == 2 and scarce.reserved_inventory.rice == 2, "employee task preclaim leaves inventory unchanged")
	scarce.selected_order_id = 2
	check(scarce.start_cooking("stove") and scarce.task_owner("cook", 2) == "player", "player preempts travelling employee and starts once")
	check(scarce.inventory.rice == 1 and scarce.reserved_inventory.rice == 1 and scarce.ingredient_consumed_cost == 5, "actual cooking consumes one reserved portion")
	check(scarce.cancel_cooking(2, scarce.orders[2].cook_attempt), "cooking can be canceled")
	check(scarce.inventory.rice == 1 and scarce.reserved_inventory.rice == 1 and not scarce.orders[2].ingredients_reserved, "canceled cooking does not refund used ingredients or steal another reservation")
	scarce.seat_customer(replacement)
	check(not scarce.task_available("cook", 2) and scarce.task_available("cook", replacement), "unstocked retry is blocked while other reserved order remains valid")
	check(scarce.cancel_order(replacement) and scarce.reserved_inventory.rice == 0, "waiting-order cancellation releases its reserved ingredients")
	check(scarce.cancel_order(2) and scarce.inventory.rice == 1 and scarce.ingredient_consumed_cost == 5, "post-start cancellation keeps consumed stock spent")
	var retry = Day.new()
	retry.start_day()
	retry.request_customer()
	retry.seat_customer(1)
	retry.start_cooking()
	var after_first_start: int = retry.inventory.rice
	check(retry.cancel_cooking(1, retry.orders[1].cook_attempt) and retry.orders[1].ingredients_reserved, "cancel can reserve a fresh portion when stock remains")
	check(retry.inventory.rice == after_first_start and retry.reserved_inventory.rice == 1, "cancel does not refund first portion")
	check(retry.start_cooking() and retry.inventory.rice == after_first_start - 1 and retry.ingredient_consumed_cost == 10, "retry consumes a second portion exactly once")
	check(retry.complete_cooking(1, retry.orders[1].cook_attempt, RESULT), "retried dish can be completed")
	retry.orders[1].waited = Day.PATIENCE - 0.1
	retry.advance(0.2)
	check(retry.inventory.rice == after_first_start - 1 and retry.reserved_inventory.rice == 0, "ready-food timeout does not return cooked ingredients")
	var timeout = Day.new()
	timeout.inventory = {"rice": 1, "egg": 1, "noodles": 0, "tomato": 0}
	timeout.start_day()
	timeout.request_customer()
	timeout.seat_customer(1)
	timeout.orders[1].waited = Day.PATIENCE - 0.1
	timeout.advance(0.2)
	check(timeout.reserved_inventory.rice == 0 and timeout.inventory.rice == 1, "waiting timeout releases ingredients")
	var partial = Day.new()
	partial.inventory = {"rice": 1, "egg": 0, "noodles": 0, "tomato": 0}
	partial.spend("equipment", Day.STARTING_CASH - 3, "leave-three")
	check(not partial.emergency_available(), "emergency is unavailable when affordable missing egg completes a dish")
	partial.spend("equipment", 1, "leave-two")
	check(partial.emergency_available(), "emergency becomes available below cheapest missing-ingredient cost")
	var emergency = Day.new()
	for ingredient: String in Day.INGREDIENTS: emergency.inventory[ingredient] = 0
	check(not emergency.start_day(), "cannot open without any offerable dish")
	check(emergency.spend("equipment", Day.STARTING_CASH, "drain-cash") and emergency.emergency_available(), "broke and empty pantry qualifies for emergency supply")
	check(emergency.claim_emergency_supply() and not emergency.claim_emergency_supply(), "one emergency portion can be claimed per day")
	check(emergency.inventory.rice == 1 and emergency.inventory.egg == 1 and emergency.start_day(), "emergency supply restores one sellable basic dish")
	check(emergency.request_customer() and not emergency.request_customer(), "emergency stock cannot be overbooked")
	emergency.seat_customer(1)
	emergency.start_cooking()
	check(emergency.inventory.rice == 0 and emergency.ingredient_consumed_cost == 5, "emergency ingredients are consumed normally")
	emergency.advance(Day.PATIENCE + 0.1)
	emergency.customer_departed(1)
	emergency.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(emergency.next_day() and emergency.emergency_available(), "a broke new day can request one fresh emergency portion")
	var game = Restaurant.instantiate()
	root.add_child(game)
	await process_frame
	game._toggle_store()
	check(game.store_panel.visible and not game.preopen_panel.visible, "preopening store opens as a separate screen")
	game.store_labels["plus_egg"].pressed.emit()
	game.store_labels["plus_egg"].pressed.emit()
	check(game.purchase_quantities.egg == 3, "store quantity controls update cart")
	game.store_labels["buy_egg"].pressed.emit()
	check(game.model.inventory.egg == 11 and game.model.summary().expenses.purchase == 9, "store button uses model purchase and ledger")
	game._toggle_recipe("noodles")
	check(not game.model.menu_enabled.noodles and game.store_labels["toggle_noodles"].text == "已停售", "menu button and label stay in sync")
	game._toggle_store()
	check(game.preopen_panel.visible and not game.store_panel.visible and game.start_day(), "store closes back to preparation and can open for service")
	print("INVENTORY: %d checks, %d failures." % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
