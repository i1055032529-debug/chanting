extends SceneTree
## Same deterministic arrivals, same scripted player cadence, with or without one employee.
const Restaurant = preload("res://scenes/restaurant.tscn")
const Bot = preload("res://tests/cooking_bot.gd")
const Day = preload("res://scripts/day_model.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var manual: Dictionary = await _simulate(false)
	var together: Dictionary = await _simulate(true)
	print("COMPARISON manual=", manual, " together=", together)
	var okay: bool = manual.served > 0 and together.served >= manual.served and together.employee_tasks > 0 and together.manual_actions > 0
	if not okay: push_error("FAIL: employee should contribute while player remains active")
	quit(0 if okay else 1)

func _simulate(with_employee: bool) -> Dictionary:
	var game = Restaurant.instantiate()
	root.add_child(game)
	await physics_frame
	await process_frame
	if with_employee: game.model.set_employee_hired(true)
	game.employee.enabled = with_employee
	game.start_day()
	var next_manual := 0.0
	var manual_cook_done := -1.0
	var actions := 0
	for step in range(2200):
		game.model.advance(0.1)
		game.employee._physics_process(0.1)
		for customer in game.customers.values():
			if is_instance_valid(customer): customer._process(0.1)
		game._sync_stains()
		if game.model.ended: break
		if manual_cook_done >= 0.0:
			if game.model.elapsed >= manual_cook_done:
				if is_instance_valid(game.cooking_screen):
					game.cooking_screen.start_round()
					Bot.finish(game.cooking_screen.rules)
					game.cooking_screen.acknowledge()
					actions += 1
				manual_cook_done = -1.0
				next_manual = game.model.elapsed + 3.0
			continue
		if game.model.elapsed < next_manual: continue
		var target := ""
		if game.model.carrying == Day.Carry.FOOD and game.model.orders.has(game.model.carried_order_id):
			target = "table_%d" % (game.model.orders[game.model.carried_order_id].table + 1)
		elif game.model.carrying == Day.Carry.PLATE:
			target = "sink"
		elif game.model.pass_order_id != 0 and game.model.task_owner("serve", game.model.pass_order_id) == "":
			target = "pass"
		else:
			for id: int in game.model.orders:
				if game.model.orders[id].state == "dirty" and game.model.task_owner("clear", id) == "":
					target = "table_%d" % (game.model.orders[id].table + 1)
					break
			if target == "" and game.model.pass_order_id == 0 and game.model.cooking_order_id == 0:
				for id: int in game.model.orders:
					if game.model.task_available("cook", id):
						game.model.selected_order_id = id
						target = "stove"
						break
			if target == "":
				for stain in game.model.stains:
					if game.model.task_available("clean", stain.id):
						target = "stain_%d" % stain.id
						break
		if target != "" and game.model.interact(target):
			actions += 1
			if target == "stove": manual_cook_done = game.model.elapsed + 7.0
			next_manual = game.model.elapsed + 3.0
	var worker_tasks := 0
	for count in game.employee.tasks_completed.values(): worker_tasks += count
	var result := {"served": game.model.served, "lost": game.model.lost, "manual_actions": actions, "employee_tasks": worker_tasks}
	game.queue_free()
	await process_frame
	return result
