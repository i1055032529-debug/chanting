extends SceneTree
const Day = preload("res://scripts/day_model.gd")
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

func ready_order(model, id: int) -> void:
	model.selected_order_id = id
	model.start_cooking()
	model.complete_cooking(id, model.orders[id].cook_attempt, RESULT)

func active_day():
	var model = Day.new()
	model.start_day()
	return model

func _run() -> void:
	var model = active_day()
	for id in [1, 2, 3]:
		model.request_customer()
		model.seat_customer(id)
	check(model.claim_task("cook", 1, "employee", "stove"), "employee reserves first stove")
	check(model.claim_task("cook", 2, "employee", "stove_2"), "second stove can be reserved independently")
	check(not model.claim_task("cook", 3, "employee"), "NPC reservations remain exclusive")
	model.selected_order_id = 1
	check(model.start_cooking("stove") and model.task_owner("cook", 1) == "player", "player takes cook task from travelling employee")
	check(model.start_cooking_as(2, "employee"), "employee can start on second stove")
	check(not model.claim_task("cook", 2, "player", "stove_2"), "player cannot take active employee cooking")
	check(not model.start_cooking("stove_2"), "occupied stove blocks player")
	check(model.complete_cooking(1, model.orders[1].cook_attempt, RESULT), "player dish reaches pass")
	check(model.complete_cooking(2, model.orders[2].cook_attempt, RESULT), "employee dish reaches second pass position")
	check(model.pass_order_ids == [1, 2], "pass keeps both dishes")
	check(model.claim_task("serve", 1, "employee"), "employee reserves first meal")
	check(not model.claim_task("serve", 1, "employee"), "NPC cannot duplicate serve reservation")
	check(model.interact("pass") and model.task_owner("serve", 1) == "player", "player takes food before employee reaches pass")
	check(not model.interact_as("employee", "pass", 1), "displaced employee cannot pick same food")
	check(model.interact("table_1"), "player serves claimed meal")
	check(model.claim_task("serve", 2, "employee"), "employee reserves second meal")
	check(model.interact_as("employee", "pass", 2), "employee picks second meal")
	check(not model.claim_task("serve", 2, "player") and not model.interact("pass"), "active delivery cannot be stolen")
	model.advance(Day.PATIENCE + 0.1)
	check(model.task_owner("serve", 2) == "" and model.employee_carrying == Day.Carry.FOOD, "timeout releases reservation but keeps invalid food for disposal")
	check(model.discard_employee_food(), "employee can dispose invalid food")
	model.customer_departed(2)
	var clearing = active_day()
	clearing.request_customer()
	clearing.seat_customer(1)
	ready_order(clearing, 1)
	clearing.interact("pass")
	clearing.interact("table_1")
	clearing.advance(Day.EAT_SECONDS)
	clearing.customer_departed(1)
	check(clearing.claim_task("clear", 1, "employee"), "employee reserves dirty table")
	check(clearing.interact("table_1") and clearing.task_owner("clear", 1) == "player", "player takes plate before employee arrives")
	check(not clearing.interact_as("employee", "table_1"), "employee cannot duplicate player's collection")
	check(clearing.interact("sink"), "player returns plate")
	var active_clear = active_day()
	active_clear.request_customer()
	active_clear.seat_customer(1)
	ready_order(active_clear, 1)
	active_clear.interact("pass")
	active_clear.interact("table_1")
	active_clear.advance(Day.EAT_SECONDS)
	active_clear.customer_departed(1)
	active_clear.claim_task("clear", 1, "employee")
	check(active_clear.interact_as("employee", "table_1"), "employee begins clearing")
	check(not active_clear.claim_task("clear", 1, "player") and not active_clear.interact("table_1"), "player cannot steal collected plate")
	active_clear.abort_employee_job("clear", 1, "测试中断")
	check(active_clear.orders[1].state == "dirty" and active_clear.task_owner("clear", 1) == "", "abort restores plate to table")
	check(active_clear.interact("table_1") and active_clear.interact("sink"), "player recovers released task")
	var cleaning = active_day()
	cleaning.stains.append({"id": 7, "table": 0})
	check(cleaning.claim_task("clean", 7, "employee"), "employee reserves stain")
	check(cleaning.interact("stain_7") and cleaning.stains.is_empty(), "player can clean stain before employee arrives")
	check(not cleaning.interact_as("employee", "stain_7"), "employee cannot clean removed stain")
	print("EMPLOYEE MODEL: %d checks, %d failures." % [checks, failures])
	quit(1 if failures else 0)
