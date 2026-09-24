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
	var lean = Day.new()
	check(lean.hire_employee() and lean.hire_employee() and lean.hire_employee() and not lean.hire_employee(), "hire up to three distinct workers")
	check(lean.employee_hired_count == 3 and lean.wage_reserved == Day.DAILY_WAGE and lean.spendable_cash() == 12, "only affordable daily wages are reserved")
	check(lean.start_day() and lean.employee_attending_count == 1 and lean.worker_active("employee") and not lean.worker_active("employee_2"), "partial budget brings only one worker on duty")
	lean.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(lean.summary().expenses.wages == Day.DAILY_WAGE and lean.coins == 12, "payroll charges only workers who attended")
	var model = Day.new()
	model.coins = 100
	for i in range(3): model.hire_employee()
	check(model.wage_reserved == 54 and model.spendable_cash() == 46 and not model.spend("equipment", 47, "too-expensive"), "three wages are protected from other spending")
	check(model.start_day() and model.employee_attending_count == 3, "three funded workers attend together")
	for id in [1, 2]:
		model.request_customer()
		model.seat_customer(id)
	check(model.claim_task("cook", 1, "employee", "stove") and model.claim_task("cook", 2, "employee_2", "stove_2"), "different workers reserve both stoves")
	check(not model.claim_task("cook", 1, "employee_3") and not model.claim_task("cook", 2, "employee_3"), "third worker cannot duplicate reserved cooking")
	check(model.start_cooking_as(1, "employee") and model.start_cooking_as(2, "employee_2"), "two workers cook simultaneously")
	check(model.complete_cooking(1, model.orders[1].cook_attempt, RESULT) and model.complete_cooking(2, model.orders[2].cook_attempt, RESULT), "independent cooking fills both pass positions")
	check(model.claim_task("serve", 1, "employee") and model.claim_task("serve", 2, "employee_2"), "workers reserve separate dishes")
	check(model.interact_as("employee", "pass", 1) and model.interact_as("employee_2", "pass", 2), "workers pick up separate dishes")
	check(model.worker_carrying("employee") == Day.Carry.FOOD and model.worker_carrying("employee_2") == Day.Carry.FOOD and model.worker_carried_order("employee") == 1 and model.worker_carried_order("employee_2") == 2, "carried food never overwrites another worker's state")
	check(model.interact_as("employee", "table_1") and model.interact_as("employee_2", "table_2"), "both workers serve their own table")
	model.advance(Day.EAT_SECONDS)
	model.customer_departed(1)
	model.customer_departed(2)
	check(model.claim_task("clear", 1, "employee") and model.claim_task("clear", 2, "employee_2"), "workers reserve separate plate clearing tasks")
	check(model.interact_as("employee", "table_1") and model.interact_as("employee_2", "table_2"), "workers carry distinct dirty plates")
	check(model.worker_carried_table("employee") == 0 and model.worker_carried_table("employee_2") == 1, "plate locations remain private to each worker")
	check(model.interact_as("employee", "sink") and model.interact_as("employee_2", "sink") and model.tables[0] == 0 and model.tables[1] == 0, "both plates return and release their tables")
	model.stains.append({"id": 99, "table": 0})
	check(model.claim_task("clean", 99, "employee_3") and model.interact_as("employee_3", "stain_99") and not model.task_owners.has("clean:99"), "third worker independently cleans while others handle tables")
	for stain in model.stains.duplicate(): model.interact_as("employee_3", "stain_%d" % stain.id)
	model.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(model.summary().expenses.wages == 54 and model.coins >= 0, "three-worker payroll settles once without negative cash")
	check(model.next_day() and model.employee_hired_count == 3 and model.wage_reserved <= model.coins, "employment persists and next-day reserve respects funds")
	check(model.dismiss_employee() and model.employee_hired_count == 2, "preopening can reduce headcount")
	var preempt = Day.new()
	preempt.coins = 100
	preempt.hire_employee()
	preempt.hire_employee()
	preempt.start_day()
	preempt.request_customer()
	preempt.seat_customer(1)
	check(preempt.claim_task("cook", 1, "employee_2", "stove_2") and preempt.start_cooking("stove_2") and preempt.task_owner("cook", 1) == "player", "player can take a travelling second worker's task")
	var stale = Day.new()
	stale.coins = 100
	stale.hire_employee()
	stale.hire_employee()
	stale.start_day()
	for id in [1, 2]:
		stale.request_customer()
		stale.seat_customer(id)
	var worker_ids := ["employee", "employee_2"]
	for i in range(2):
		var id := i + 1
		var actor: String = worker_ids[i]
		stale.claim_task("cook", id, actor, Day.STOVES[i])
		stale.start_cooking_as(id, actor)
		stale.complete_cooking(id, stale.orders[id].cook_attempt, RESULT)
		stale.claim_task("serve", id, actor)
		stale.interact_as(actor, "pass", id)
	stale.advance(Day.PATIENCE + 0.1)
	check(stale.worker_carrying("employee") == Day.Carry.FOOD and stale.worker_carrying("employee_2") == Day.Carry.FOOD, "expired food remains independently held for disposal")
	check(stale.discard_employee_food("employee") and stale.worker_carrying("employee_2") == Day.Carry.FOOD and stale.discard_employee_food("employee_2"), "disposing one worker's invalid food never clears another's")
	var game = Restaurant.instantiate()
	root.add_child(game)
	await process_frame
	game.model.coins = 100
	game._toggle_management()
	for i in range(3): game.hire_button.pressed.emit()
	check(game.model.employee_hired_count == 3 and game.selected_employee_index == 2 and game.hire_button.disabled, "management can hire three and enforces cap")
	game._toggle_employee_work("cook")
	check(not game.employees[2].work_enabled.cook and game.employees[0].work_enabled.cook, "per-worker assignment stays independent")
	game.dismiss_button.pressed.emit()
	check(game.model.employee_hired_count == 2 and game.employees[2].work_enabled.cook and game.selected_employee_index == 1, "dismissing the last worker resets only that slot")
	game.hire_button.pressed.emit()
	check(game.model.employee_hired_count == 3 and game.selected_employee_index == 2 and game.employees[2].work_enabled.cook, "rehiring fills the free slot with default work settings")
	game._select_employee(-1)
	check(game.selected_employee_index == 1 and game.management_title.text.contains("2/3"), "management can select another worker")
	game._toggle_management()
	check(game.start_day() and game.employees.all(func(worker: Node2D): return worker.visible), "three employees appear in the restaurant")
	check(game.labels.employee.text.contains("3/3"), "service header shows full attendance")
	game.model.request_customer()
	game.model.request_customer()
	for id in [1, 2]: game.model.seat_customer(id)
	for worker in game.employees: worker._physics_process(0.1)
	check(game.model.task_owner("cook", 1) != "" and game.model.task_owner("cook", 2) != "" and game.model.task_owner("cook", 1) != game.model.task_owner("cook", 2), "actual worker instances dispatch to separate cooking jobs")
	for step in range(2300):
		game.model.advance(0.1)
		for worker in game.employees: worker._physics_process(0.1)
		for customer in game.customers.values():
			if is_instance_valid(customer): customer._process(0.1)
		game._sync_stains()
		if game.model.ended: break
	var completed: Array[int] = []
	for worker in game.employees:
		var total := 0
		for count in worker.tasks_completed.values(): total += count
		completed.append(total)
	check(game.model.ended and completed.min() > 0, "all three hired workers complete real service tasks in one营业日")
	check(game.model.task_owners.is_empty() and game.model.summary().expenses.wages == 54, "parallel service closes without held tasks and pays three wages")
	print("MULTI EMPLOYEE: %d checks, %d failures." % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
