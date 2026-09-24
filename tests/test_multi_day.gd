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

func _serve_one(model) -> int:
	check(model.request_customer(), "open day accepts a customer")
	var id: int = model.next_order_id - 1
	check(model.seat_customer(id), "customer is seated")
	check(model.start_cooking(), "order starts cooking")
	check(model.complete_cooking(id, model.orders[id].cook_attempt, RESULT), "dish reaches pass")
	check(model.interact("pass") and model.interact("table_1"), "dish reaches customer")
	model.advance(Day.EAT_SECONDS)
	return id

func _run() -> void:
	var model = Day.new()
	check(model.phase == "preopen" and model.day_number == 1 and model.coins == Day.STARTING_CASH, "new run starts before day one")
	model.advance(30.0)
	check(model.elapsed == 0.0 and not model.request_customer(), "preparation does not advance clock or accept customers")
	check(not model.spend("purchase", Day.STARTING_CASH + 1, "before-income"), "spending cannot overdraw cash")
	check(model.start_day() and not model.start_day(), "day can open only once")
	check(not model.spend("purchase", 1, "during-open"), "management spending is closed during service")
	var first_id := _serve_one(model)
	var first_income: int = model.coins - Day.STARTING_CASH
	var first_closing_cash: int = model.coins
	check(first_income > 0 and model.ledger.size() == 1 and model.ledger[0].kind == "income", "payment writes one ledger entry")
	model.advance(0.1)
	check(model.coins == first_closing_cash and model.ledger.size() == 1, "customer cannot pay twice")
	check(model.customer_departed(first_id), "paid customer leaves")
	check(model.interact("table_1") and model.interact("sink"), "table is cleared")
	model.advance(Day.DAY_SECONDS)
	check(model.phase == "summary" and model.ended and model.day_reports.size() == 1, "first day closes with one report")
	var first_report: Dictionary = model.day_reports[0]
	check(first_report.day == 1 and first_report.opening_cash == Day.STARTING_CASH and first_report.income == first_income and first_report.coins == first_closing_cash, "report reconciles opening cash and revenue")
	model.advance(Day.CLOSING_GRACE)
	check(model.day_reports.size() == 1 and not model.start_day(), "finished day cannot settle or reopen twice")
	check(model.spend("equipment", 5, "upgrade-one"), "summary-phase spending uses ledger")
	check(not model.spend("equipment", 5, "upgrade-one") and not model.spend("wages", first_closing_cash, "too-much"), "duplicate and unaffordable spending are rejected")
	check(model.coins == first_closing_cash - 5 and model.day_reports[0].expenses.equipment == 5 and model.day_reports[0].cash_change == first_income - 5, "late expense updates finalized report")
	check(model.next_day() and not model.next_day(), "next day preparation begins only once")
	check(model.day_number == 2 and model.phase == "preopen" and model.coins == first_closing_cash - 5, "next day retains cash and advances day count")
	check(model.day_opening_cash == model.coins and model.ledger.is_empty() and model.orders.is_empty() and model.task_owners.is_empty() and model.stains.is_empty(), "next day clears temporary state and starts a fresh ledger")
	check(model.served == 0 and model.lost == 0 and model.payments.is_empty() and model.reviews.is_empty(), "daily performance counters reset")
	check(not model.request_customer(), "next day remains closed until opening")
	check(model.spend("purchase", 2, "supplies") and model.summary().expenses.purchase == 2, "preopening purchase is recorded against day two")
	check(model.start_day(), "second day opens")
	var second_id := _serve_one(model)
	check(second_id != first_id and model.coins > first_closing_cash - 5, "new order IDs stay unique and income accumulates")
	model.customer_departed(second_id)
	model.interact("table_1")
	model.interact("sink")
	model.advance(Day.DAY_SECONDS)
	check(model.day_reports.size() == 2 and model.day_reports[1].opening_cash == first_closing_cash - 5, "two reports keep separate opening balances")
	var second_closing_cash: int = model.coins
	check(model.next_day() and model.day_number == 3 and model.coins == second_closing_cash, "third preparation retains second-day cash")
	check(model.start_day(), "third day opens")
	model.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(model.day_reports.size() == 3 and model.day_reports[2].income == 0 and model.coins == second_closing_cash, "quiet third day closes once without changing cash")
	model.new_game()
	check(model.phase == "preopen" and model.day_number == 1 and model.coins == Day.STARTING_CASH and model.day_reports.is_empty() and model.ledger.is_empty(), "new game clears all cross-day progress")
	var game = Restaurant.instantiate()
	root.add_child(game)
	await process_frame
	check(game.preopen_panel.visible and game.player.locked and not game.try_interact("stove"), "scene presents preparation and blocks work")
	game.employee.toggle_work("cook")
	game.employee.move_priority_up("cook")
	check(game.start_day(), "scene starts service from preparation")
	game.model.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(game.summary_panel.visible and game.model.phase == "summary", "scene displays closing report")
	check(game.prepare_next_day() and game.preopen_panel.visible and game.model.day_number == 2, "scene returns to next preparation")
	check(not game.employee.work_enabled.cook and game.employee.priority.find("cook") < 3, "employee settings survive the day transition")
	game.reset_run()
	check(game.model.day_number == 1 and game.employee.work_enabled.cook and game.employee.priority == ["serve", "clear", "clean", "cook"], "new game resets employee settings")
	print("MULTI DAY: %d checks, %d failures." % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
