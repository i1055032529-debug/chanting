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

func _run() -> void:
	var model = Day.new()
	model.request_customer()
	model.seat_customer(1)
	check(model.claim_task("cook", 1, "employee"), "employee reserves cook before walking")
	check(not model.claim_task("cook", 1, "player") and not model.start_cooking(), "player cannot take reserved cook")
	check(model.start_cooking_as(1, "employee"), "owner can start task")
	var attempt: int = model.cooking_attempt_id
	check(model.complete_cooking(1, attempt, RESULT), "employee uses same cooking result")
	check(model.task_owner("cook", 1) == "", "cooking reservation released on completion")
	check(model.claim_task("serve", 1, "employee"), "employee reserves food before moving")
	check(not model.interact("pass") and model.pass_order_id == 1, "player cannot take reserved food")
	check(model.interact_as("employee", "pass"), "employee picks up claimed food")
	check(model.employee_carrying == Day.Carry.FOOD and model.pass_order_id == 0, "food is in employee hands")
	model.advance(Day.PATIENCE + 0.1)
	check(model.task_owner("serve", 1) == "" and model.employee_carrying == Day.Carry.FOOD, "timeout releases reservation but keeps invalid food for disposal")
	check(model.discard_employee_food(), "employee can dispose invalid food at sink")
	check(model.employee_carrying == Day.Carry.NONE, "disposal frees employee hands")
	model.customer_departed(1)
	check(model.tables[0] == 0, "expired customer releases table")
	var clearing = Day.new()
	clearing.request_customer()
	clearing.seat_customer(1)
	clearing.start_cooking()
	clearing.complete_cooking(1, clearing.cooking_attempt_id, RESULT)
	clearing.interact("pass")
	clearing.interact("table_1")
	clearing.advance(Day.EAT_SECONDS)
	clearing.customer_departed(1)
	check(clearing.claim_task("clear", 1, "employee"), "employee reserves dirty table")
	check(not clearing.interact("table_1"), "player cannot duplicate claimed clearing")
	check(clearing.interact_as("employee", "table_1"), "employee takes plate")
	clearing.abort_employee_job("clear", 1, "测试中断")
	check(clearing.employee_carrying == Day.Carry.NONE and clearing.orders[1].state == "dirty" and clearing.task_owner("clear", 1) == "", "abort returns plate to dirty task")
	check(clearing.interact("table_1") and clearing.interact("sink"), "player can recover released task")
	print("EMPLOYEE MODEL: %d checks, %d failures." % [checks, failures])
	quit(1 if failures else 0)
