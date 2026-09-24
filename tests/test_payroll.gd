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
	var model = Day.new()
	check(not model.employee_hired and model.wage_reserved == 0 and model.spendable_cash() == Day.STARTING_CASH, "new game begins without hired staff")
	check(model.set_employee_hired(true) and not model.set_employee_hired(true), "one employee can be hired only once")
	check(model.wage_reserved == Day.DAILY_WAGE and model.spendable_cash() == Day.STARTING_CASH - Day.DAILY_WAGE, "daily wage is reserved before opening")
	check(not model.purchase("tomato", 4) and model.purchase("tomato", 3), "procurement cannot consume reserved wages")
	check(model.coins == Day.DAILY_WAGE and model.wage_reserved == Day.DAILY_WAGE and model.spendable_cash() == 0, "purchase leaves reserved payroll untouched")
	check(model.set_employee_hired(false) and model.wage_reserved == 0 and model.spendable_cash() == Day.DAILY_WAGE, "stopping employment releases the reservation")
	check(model.set_employee_hired(true) and model.start_day() and model.employee_attending, "rehired worker attends an affordable day")
	check(not model.set_employee_hired(false) and not model.purchase("egg", 1), "employment and purchases cannot change during service")
	model.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(model.ended and model.coins == 0 and model.summary().expenses.wages == Day.DAILY_WAGE, "wage is paid once at closing")
	check(model.summary().operating_profit == -Day.DAILY_WAGE and model.ledger.size() == 2, "wages enter ledger and operating result")
	check(not model.spend("wages", 1, "extra-pay") and model.summary().expenses.wages == Day.DAILY_WAGE, "manual spending cannot create duplicate wage payments")
	model.advance(30.0)
	check(model.summary().expenses.wages == Day.DAILY_WAGE and model.ledger.size() == 2, "repeated settling does not duplicate payroll")
	check(model.next_day() and model.employee_hired and model.wage_reserved == 0, "employment persists but broke next day reserves no wage")
	check(model.start_day() and not model.employee_attending and model.coins == 0, "unfunded worker does not attend; player can open")
	model.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(model.summary().expenses.wages == 0, "absent employee receives no wage")
	var poor = Day.new()
	poor.spend("equipment", 25, "leave-five")
	check(poor.set_employee_hired(true) and poor.wage_reserved == 0 and poor.spendable_cash() == 5, "insufficient cash permits a contract but no payroll reserve")
	poor.start_day()
	poor.request_customer()
	poor.seat_customer(1)
	check(not poor.claim_task("cook", 1, "employee", "stove") and poor.start_cooking(), "absent worker cannot claim a job while player can cook")
	poor.complete_cooking(1, poor.orders[1].cook_attempt, RESULT)
	poor.interact("pass")
	poor.interact("table_1")
	poor.advance(Day.EAT_SECONDS)
	poor.customer_departed(1)
	poor.interact("table_1")
	poor.interact("sink")
	poor.advance(Day.DAY_SECONDS)
	check(poor.summary().expenses.wages == 0 and poor.coins > Day.DAILY_WAGE, "manual service earns cash without charging the absent worker")
	check(poor.next_day() and poor.wage_reserved == Day.DAILY_WAGE and poor.start_day() and poor.employee_attending, "contracted employee returns automatically once next-day cash covers wage")
	var game = Restaurant.instantiate()
	root.add_child(game)
	await process_frame
	check(not game.employee.visible and not game.model.employee_hired, "scene hides uncontracted employee")
	game._toggle_management()
	game.hire_button.pressed.emit()
	check(game.model.employee_hired and game.model.wage_reserved == Day.DAILY_WAGE and game.employment_label.text.contains("预留"), "hire button updates contract and visible wage reserve")
	game.work_buttons["employee_enabled"].pressed.emit()
	check(not game.employee.enabled and game.work_buttons["employee_enabled"].text == "安排工作", "preopening schedule can set a hired employee to rest")
	game.work_buttons["employee_enabled"].pressed.emit()
	game._toggle_management()
	game._toggle_store()
	check(game.store_labels.overview.text.contains("可采购 12") and game.store_labels["buy_tomato"].disabled == false, "store shows spendable balance after payroll reservation")
	game._toggle_store()
	check(game.start_day() and game.employee.visible and game.model.employee_attending, "contracted worker appears for service")
	game.model.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(game.summary_panel.visible and game.model.summary().expenses.wages == Day.DAILY_WAGE and game.summary_text.text.contains("工资 18"), "day-end screen reports paid wage")
	check(game.prepare_next_day() and game.model.employee_hired and not game.employee.visible, "contract and work settings survive into preparation")
	game.reset_run()
	check(not game.model.employee_hired and not game.employee.visible and game.model.wage_reserved == 0, "new game removes contract and wage reserve")
	print("PAYROLL: %d checks, %d failures." % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
