class_name DayModel
extends RefCounted
## Restaurant-day simulation plus the run's cash, reports and transaction ledger.

signal changed
signal feedback(message: String)
signal customer_requested(order_id: int, table_id: int)
signal customer_browsing(customer_id: int)
signal customer_leave_requested(order_id: int)
signal cooking_requested(order_id: int, attempt_id: int, recipe_id: String)
signal cooking_expired(order_id: int)
signal day_finished(summary: Dictionary)

enum Carry { NONE, FOOD, PLATE }
const TABLE_COUNT := 4
const STOVES := ["stove", "stove_2"]
const PASS_CAPACITY := 2
const EXPENSE_KINDS := ["purchase", "wages", "furniture", "equipment", "expansion"]
const STARTING_CASH := 60
const DAILY_WAGE := 18
const MAX_EMPLOYEES := 3
const WORKER_IDS := ["employee", "employee_2", "employee_3"]
const INGREDIENTS := {
	"rice": {"name": "米饭", "price": 2, "starting": 8},
	"egg": {"name": "鸡蛋", "price": 3, "starting": 8},
	"noodles": {"name": "面条", "price": 3, "starting": 8},
	"tomato": {"name": "番茄", "price": 4, "starting": 8},
}
const RECIPE_IDS := ["rice", "noodles", "tomato_egg", "egg_noodles"]
const DAY_SECONDS := 180.0
const CLOSING_GRACE := 35.0
const PATIENCE := 48.0
const EAT_SECONDS := 4.0
const STAIN_LIMIT := 3
const LOW_INTERVAL := 14.0
const PEAK_INTERVAL := 8.0
const WAVE_SECONDS := 70.0
const PEAK_START := 25.0
const PEAK_END := 55.0
const RECIPES := {
	"rice": {"name": "香煎蛋饭", "price": 18, "speed": 1.0, "color": Color("e7bf70"), "ingredients": {"rice": 1, "egg": 1}},
	"noodles": {"name": "番茄炒面", "price": 24, "speed": 0.82, "color": Color("d97853"), "ingredients": {"noodles": 1, "tomato": 1}},
	"tomato_egg": {"name": "番茄炒蛋", "price": 20, "speed": 0.9, "color": Color("e6a45f"), "ingredients": {"tomato": 1, "egg": 1}},
	"egg_noodles": {"name": "鸡蛋拌面", "price": 22, "speed": 0.93, "color": Color("d6b86c"), "ingredients": {"noodles": 1, "egg": 1}},
}
const CookingRules = preload("res://scripts/cooking/cooking_model.gd")

var phase := "preopen"
var day_number := 1
var day_opening_cash := STARTING_CASH
var ledger: Array[Dictionary] = []
var day_reports: Array[Dictionary] = []
var transaction_keys: Dictionary = {}
var elapsed := 0.0
var day_closed := false
var ended := false
var coins := STARTING_CASH
var employee_hired := false
var employee_attending := false
var employee_hired_count := 0
var employee_attending_count := 0
var wage_reserved := 0
var inventory: Dictionary = {}
var reserved_inventory: Dictionary = {}
var menu_enabled := {"rice": true, "noodles": true, "tomato_egg": true, "egg_noodles": true}
var menu_prices := {"rice": 18, "noodles": 24, "tomato_egg": 20, "egg_noodles": 22}
var browsers: Dictionary = {}
var purchase_sequence := 1
var emergency_uses_today := 0
var ingredient_consumed_cost := 0
var served := 0
var lost := 0
var no_sale := 0
var missing_first_choices: Dictionary = {}
var price_refusals := 0
var good_reviews := 0
var bad_reviews := 0
var next_order_id := 1
var next_attempt_id := 1
var spawn_clock := 0.0
var selected_order_id := 0
var orders: Dictionary = {}
var tables: Array[int] = [0, 0, 0, 0]
var pass_order_id := 0
var pass_order_ids: Array[int] = []
var carrying: Carry = Carry.NONE
var carried_order_id := 0
var carried_table_id := -1
var cooking_order_id := 0
var cooking_attempt_id := 0
var stains: Array[Dictionary] = []
var next_stain_id := 1
var payments: Array[int] = []
var reviews: Array[Dictionary] = []
var wait_records: Array[float] = []
# A task is reserved before either actor walks to it. Keys are stable per order/stain.
var task_owners: Dictionary = {}
var task_active: Dictionary = {}
var cook_stations: Dictionary = {}
var employee_carrying: Carry = Carry.NONE
var employee_carried_order_id := 0
var employee_carried_table_id := -1
var worker_carry: Dictionary = {}


func _init() -> void:
	_reset_inventory()


func _reset_inventory() -> void:
	inventory.clear()
	reserved_inventory.clear()
	for ingredient: String in INGREDIENTS:
		inventory[ingredient] = INGREDIENTS[ingredient].starting
		reserved_inventory[ingredient] = 0


func ingredient_available(id: String) -> int:
	if not INGREDIENTS.has(id): return 0
	return maxi(0, inventory[id] - reserved_inventory[id])


func spendable_cash() -> int:
	return maxi(0, coins - wage_reserved) if phase == "preopen" else coins


func set_employee_hired(hired: bool) -> bool:
	if phase != "preopen" or employee_hired == hired: return false
	if hired: return hire_employee()
	employee_hired_count = 0
	_update_staff_counts()
	_refresh_wage_reservation()
	changed.emit()
	return true


func hire_employee() -> bool:
	if phase != "preopen" or employee_hired_count >= MAX_EMPLOYEES: return false
	employee_hired_count += 1
	_update_staff_counts()
	_refresh_wage_reservation()
	feedback.emit("已雇佣 %d 名员工；今日预计 %d 人出勤，预留工资 %d。" % [employee_hired_count, wage_reserved / DAILY_WAGE, wage_reserved])
	changed.emit()
	return true


func dismiss_employee() -> bool:
	if phase != "preopen" or employee_hired_count <= 0: return false
	employee_hired_count -= 1
	_update_staff_counts()
	_refresh_wage_reservation()
	feedback.emit("现有 %d 名员工；工资预留已重算为 %d。" % [employee_hired_count, wage_reserved])
	changed.emit()
	return true


func _update_staff_counts() -> void:
	employee_hired = employee_hired_count > 0
	employee_attending = employee_attending_count > 0


func _refresh_wage_reservation() -> void:
	wage_reserved = mini(employee_hired_count, coins / DAILY_WAGE) * DAILY_WAGE if phase == "preopen" else 0


func worker_active(actor: String) -> bool:
	var index := WORKER_IDS.find(actor)
	return index >= 0 and index < employee_attending_count


func worker_carrying(actor: String) -> Carry:
	return worker_carry.get(actor, {"kind": Carry.NONE}).kind


func worker_carried_order(actor: String) -> int:
	return worker_carry.get(actor, {"order": 0}).order


func worker_carried_table(actor: String) -> int:
	return worker_carry.get(actor, {"table": -1}).table


func portions_available(recipe_id: String) -> int:
	if not RECIPES.has(recipe_id): return 0
	var portions := 999999
	for ingredient: String in RECIPES[recipe_id].ingredients:
		portions = mini(portions, ingredient_available(ingredient) / int(RECIPES[recipe_id].ingredients[ingredient]))
	return portions


func purchase(ingredient_id: String, quantity: int) -> bool:
	if phase != "preopen" or not INGREDIENTS.has(ingredient_id) or quantity <= 0 or quantity > 99: return false
	var cost: int = INGREDIENTS[ingredient_id].price * quantity
	if not spend("purchase", cost, "purchase:%d" % purchase_sequence):
		return _reject("采购失败：余额不足。")
	purchase_sequence += 1
	inventory[ingredient_id] += quantity
	feedback.emit("购入%s ×%d，支出 %d 金币。" % [INGREDIENTS[ingredient_id].name, quantity, cost])
	changed.emit()
	return true


func set_menu_enabled(recipe_id: String, enabled_menu: bool) -> bool:
	if phase != "preopen" or not RECIPES.has(recipe_id): return false
	if menu_enabled[recipe_id] == enabled_menu: return false
	if not enabled_menu:
		var remaining := false
		for other: String in RECIPE_IDS:
			if other != recipe_id and menu_enabled[other]: remaining = true
		if not remaining: return _reject("菜单至少保留一道菜。")
	menu_enabled[recipe_id] = enabled_menu
	changed.emit()
	return true


func set_menu_price(recipe_id: String, price: int) -> bool:
	if phase != "preopen" or not RECIPES.has(recipe_id) or price < 1 or price > 99 or menu_prices[recipe_id] == price: return false
	menu_prices[recipe_id] = price
	changed.emit()
	return true


func recipe_ingredients_text(recipe_id: String) -> String:
	if not RECIPES.has(recipe_id): return ""
	var parts: Array[String] = []
	for ingredient: String in RECIPES[recipe_id].ingredients:
		parts.append("%s×%d" % [INGREDIENTS[ingredient].name, RECIPES[recipe_id].ingredients[ingredient]])
	return " + ".join(parts)


func customer_preferences(customer_id: int) -> Array[String]:
	var ranked: Array[Dictionary] = []
	var favorite := (customer_id - 1 + day_number - 1) % RECIPE_IDS.size()
	var indices := [favorite, (favorite + 1) % RECIPE_IDS.size(), (favorite + 3) % RECIPE_IDS.size()]
	for distance in range(3):
		var i: int = indices[distance]
		var recipe_id: String = RECIPE_IDS[i]
		var taste: float = [0.98, 0.82, 0.66][distance]
		var personality := float((customer_id * 13 + i * 19) % 7 - 3) * 0.005
		ranked.append({"id": recipe_id, "score": (taste + personality) * _price_factor(recipe_id)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary): return a.score > b.score)
	var result: Array[String] = []
	for entry in ranked: result.append(entry.id)
	return result


func _price_factor(recipe_id: String) -> float:
	var ratio := float(menu_prices[recipe_id]) / float(RECIPES[recipe_id].price)
	return clampf(1.0 - maxf(0.0, ratio - 1.0) * 0.8 + maxf(0.0, 1.0 - ratio) * 0.1, 0.04, 1.05)


func purchase_probability(customer_id: int, recipe_id: String) -> float:
	if not RECIPES.has(recipe_id): return 0.0
	var favorite := (customer_id - 1 + day_number - 1) % RECIPE_IDS.size()
	var index := RECIPE_IDS.find(recipe_id)
	var indices := [favorite, (favorite + 1) % RECIPE_IDS.size(), (favorite + 3) % RECIPE_IDS.size()]
	var distance := indices.find(index)
	if distance < 0: return 0.0
	var taste: float = [0.98, 0.82, 0.66][distance]
	var personality := float((customer_id * 13 + index * 19) % 7 - 3) * 0.005
	return clampf((taste + personality) * _price_factor(recipe_id), 0.0, 1.0)


func _purchase_roll(customer_id: int, recipe_id: String) -> float:
	return float((customer_id * 17 + RECIPE_IDS.find(recipe_id) * 23 + day_number * 11) % 100) / 100.0


func emergency_available() -> bool:
	if phase != "preopen" or emergency_uses_today >= 1: return false
	var cheapest_completion := 999999
	for recipe_id: String in RECIPE_IDS:
		if portions_available(recipe_id) > 0: return false
		var missing_cost := 0
		for ingredient: String in RECIPES[recipe_id].ingredients:
			var required: int = RECIPES[recipe_id].ingredients[ingredient]
			missing_cost += maxi(0, required - ingredient_available(ingredient)) * int(INGREDIENTS[ingredient].price)
		cheapest_completion = mini(cheapest_completion, missing_cost)
	return spendable_cash() < cheapest_completion


func claim_emergency_supply() -> bool:
	if not emergency_available(): return false
	inventory.rice += 1
	inventory.egg += 1
	emergency_uses_today += 1
	menu_enabled.rice = true
	feedback.emit("获得一份应急蛋饭食材。")
	changed.emit()
	return true


func _reserve_recipe(recipe_id: String) -> bool:
	if portions_available(recipe_id) <= 0: return false
	for ingredient: String in RECIPES[recipe_id].ingredients:
		reserved_inventory[ingredient] += int(RECIPES[recipe_id].ingredients[ingredient])
	changed.emit()
	return true


func _release_order_ingredients(id: int) -> void:
	if not orders.has(id) or not orders[id].ingredients_reserved: return
	for ingredient: String in RECIPES[orders[id].recipe].ingredients:
		reserved_inventory[ingredient] -= int(RECIPES[orders[id].recipe].ingredients[ingredient])
	orders[id].ingredients_reserved = false
	changed.emit()


func _consume_order_ingredients(id: int) -> bool:
	if not orders.has(id) or not orders[id].ingredients_reserved: return false
	for ingredient: String in RECIPES[orders[id].recipe].ingredients:
		var quantity: int = RECIPES[orders[id].recipe].ingredients[ingredient]
		if inventory[ingredient] < quantity or reserved_inventory[ingredient] < quantity: return false
	for ingredient: String in RECIPES[orders[id].recipe].ingredients:
		var quantity: int = RECIPES[orders[id].recipe].ingredients[ingredient]
		inventory[ingredient] -= quantity
		reserved_inventory[ingredient] -= quantity
		ingredient_consumed_cost += quantity * int(INGREDIENTS[ingredient].price)
	orders[id].ingredients_reserved = false
	orders[id].ingredients_consumed = true
	changed.emit()
	return true


func advance(delta: float) -> void:
	if phase != "open" or ended or delta <= 0.0: return
	elapsed += delta
	if not day_closed and elapsed >= DAY_SECONDS:
		day_closed = true
		feedback.emit("营业时间结束，停止接待新顾客；请完成手头订单。")
		changed.emit()
	var ids := orders.keys()
	for id: int in ids:
		if not orders.has(id): continue
		var order: Dictionary = orders[id]
		match order.state:
			"waiting", "cooking", "ready", "carried":
				order.waited += delta
				if order.waited >= PATIENCE:
					_timeout(id)
			"eating":
				order.eat_clock += delta
				if order.eat_clock >= EAT_SECONDS:
					_pay_and_leave(id)
	for browser_id: int in browsers.keys():
		if browsers[browser_id].state != "browsing": continue
		browsers[browser_id].remaining -= delta
		if browsers[browser_id].remaining <= 0.0:
			browsers[browser_id].state = "leaving"
			customer_leave_requested.emit(browser_id)
	if not day_closed:
		spawn_clock += delta
		var wave_time := fmod(elapsed, WAVE_SECONDS)
		var interval := PEAK_INTERVAL if wave_time >= PEAK_START and wave_time < PEAK_END else LOW_INTERVAL
		if spawn_clock >= interval:
			spawn_clock = 0.0
			request_customer()
	elif elapsed >= DAY_SECONDS + CLOSING_GRACE:
		_force_finish()
	else:
		_finish_if_clear()


func request_customer() -> bool:
	if phase != "open" or day_closed or ended: return false
	var id := next_order_id
	var preferences := customer_preferences(id)
	var recipe_id := ""
	var choice_rank := -1
	for rank in range(preferences.size()):
		var candidate: String = preferences[rank]
		if menu_enabled[candidate] and portions_available(candidate) > 0 and _purchase_roll(id, candidate) < purchase_probability(id, candidate):
			recipe_id = candidate
			choice_rank = rank
			break
	if recipe_id == "":
		next_order_id += 1
		var first_choice: String = preferences[0]
		var first_reason := "停售" if not menu_enabled[first_choice] else "缺货" if portions_available(first_choice) <= 0 else "售价或口味"
		browsers[id] = {"state": "arriving", "remaining": 3.5, "first_choice": first_choice, "first_reason": first_reason}
		customer_browsing.emit(id)
		feedback.emit("一位顾客没找到愿意购买的菜，正在店内看看。")
		changed.emit()
		return true
	var table_id := -1
	for i in range(TABLE_COUNT):
		if tables[i] == 0:
			table_id = i
			break
	if table_id < 0 or not _reserve_recipe(recipe_id): return false
	next_order_id += 1
	orders[id] = {"id": id, "table": table_id, "recipe": recipe_id, "price": menu_prices[recipe_id], "choice_rank": choice_rank, "satisfaction": 100 - choice_rank * 20, "state": "arriving", "waited": 0.0, "eat_clock": 0.0, "score": 0, "bonus": 0, "review": "", "cook_attempt": 0, "ingredients_reserved": true, "ingredients_consumed": false}
	tables[table_id] = id
	customer_requested.emit(id, table_id)
	changed.emit()
	return true


func browser_arrived(id: int) -> bool:
	if not browsers.has(id) or browsers[id].state != "arriving": return false
	browsers[id].state = "browsing"
	changed.emit()
	return true


func seat_customer(id: int) -> bool:
	if not orders.has(id) or orders[id].state != "arriving": return false
	orders[id].state = "waiting"
	if selected_order_id == 0: selected_order_id = id
	if orders[id].choice_rank > 0:
		feedback.emit("%02d 号桌没买到首选，改点%s；满意度 %d。" % [orders[id].table + 1, recipe_name(orders[id].recipe), orders[id].satisfaction])
	else:
		feedback.emit("%02d 号桌点了%s。" % [orders[id].table + 1, recipe_name(orders[id].recipe)])
	changed.emit()
	return true


func customer_departed(id: int) -> bool:
	if browsers.has(id):
		_record_no_sale(id)
		_finish_if_clear()
		return true
	if not orders.has(id): return false
	var order: Dictionary = orders[id]
	if order.state == "leaving_paid":
		order.state = "dirty"
		_make_stain(order.table)
		feedback.emit("%02d 号桌待收盘；地面也可能需要清洁。" % [order.table + 1])
	elif order.state == "leaving_lost":
		tables[order.table] = 0
		orders.erase(id)
	else: return false
	changed.emit()
	_finish_if_clear()
	return true


func _record_no_sale(id: int) -> void:
	if not browsers.has(id): return
	var browser: Dictionary = browsers[id]
	browsers.erase(id)
	lost += 1
	no_sale += 1
	bad_reviews += 1
	if browser.first_reason in ["缺货", "停售"]:
		missing_first_choices[browser.first_choice] = int(missing_first_choices.get(browser.first_choice, 0)) + 1
	else:
		price_refusals += 1
	reviews.append({"table": 0, "good": false, "reason": browser.first_reason, "first_choice": browser.first_choice, "satisfaction": 0})
	changed.emit()


func cancel_order(id: int) -> bool:
	if phase != "open" or not orders.has(id): return false
	if orders[id].state not in ["arriving", "waiting", "cooking", "ready", "carried"]: return false
	_timeout(id)
	return true


func select_next() -> int:
	var choices: Array[int] = []
	for id: int in orders:
		if orders[id].state == "waiting": choices.append(id)
	choices.sort()
	if choices.is_empty():
		selected_order_id = 0
		return 0
	var index := choices.find(selected_order_id)
	selected_order_id = choices[(index + 1) % choices.size()]
	changed.emit()
	return selected_order_id


func task_key(kind: String, id: int) -> String:
	return "%s:%d" % [kind, id]


func task_owner(kind: String, id: int) -> String:
	return task_owners.get(task_key(kind, id), "")


func task_available(kind: String, id: int, station: String = "") -> bool:
	if phase != "open" or ended or task_owner(kind, id) != "": return false
	match kind:
		"cook":
			if not orders.has(id) or orders[id].state != "waiting" or not orders[id].ingredients_reserved or _output_occupancy() >= PASS_CAPACITY: return false
			return _free_stove(station) != ""
		"serve": return orders.has(id) and orders[id].state == "ready" and id in pass_order_ids
		"clear": return orders.has(id) and orders[id].state == "dirty"
		"clean":
			for stain in stains:
				if stain.id == id: return true
	return false


func claim_task(kind: String, id: int, actor: String, station: String = "") -> bool:
	if phase != "open": return false
	if actor != "player" and actor not in WORKER_IDS: return false
	if actor != "player" and not worker_active(actor): return false
	if actor == "player" and carrying != Carry.NONE: return false
	if actor != "player" and worker_carrying(actor) != Carry.NONE: return false
	var key := task_key(kind, id)
	var owner := task_owner(kind, id)
	if owner != "":
		if actor != "player" or owner not in WORKER_IDS or task_active.get(key, false): return false
		if kind == "cook":
			if not orders.has(id) or orders[id].state != "waiting" or not orders[id].ingredients_reserved: return false
			if station != "" and station != cook_stations.get(id, ""):
				if _free_stove(station) == "": return false
				cook_stations[id] = station
		elif not _task_still_possible(kind, id): return false
	else:
		if not task_available(kind, id, station): return false
		if kind == "cook": cook_stations[id] = _free_stove(station)
	task_owners[key] = actor
	task_active[key] = false
	changed.emit()
	return true


func release_task(kind: String, id: int, actor: String = "") -> void:
	var key := task_key(kind, id)
	if not task_owners.has(key): return
	if actor != "" and task_owners[key] != actor: return
	task_owners.erase(key)
	task_active.erase(key)
	if kind == "cook": cook_stations.erase(id)
	changed.emit()


func _task_still_possible(kind: String, id: int) -> bool:
	match kind:
		"serve": return orders.has(id) and orders[id].state == "ready" and id in pass_order_ids
		"clear": return orders.has(id) and orders[id].state == "dirty"
		"clean":
			for stain in stains:
				if stain.id == id: return true
	return false


func _free_stove(preferred: String = "") -> String:
	var choices := [preferred] if preferred != "" else STOVES
	for station in choices:
		if station not in STOVES: continue
		if station not in cook_stations.values(): return station
	return ""


func _output_occupancy() -> int:
	return pass_order_ids.size() + cook_stations.size()


func _sync_pass_primary() -> void:
	pass_order_id = pass_order_ids[0] if not pass_order_ids.is_empty() else 0


func _sync_cooking_primary() -> void:
	cooking_order_id = 0
	cooking_attempt_id = 0
	for id: int in cook_stations:
		if orders.has(id) and orders[id].state == "cooking":
			cooking_order_id = id
			cooking_attempt_id = orders[id].cook_attempt
			return


func available_tasks() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for id: int in orders:
		var order: Dictionary = orders[id]
		for kind in ["serve", "clear", "cook"]:
			if task_available(kind, id):
				found.append({"kind": kind, "id": id, "table": order.table, "urgency": order.waited / PATIENCE if kind != "clear" else 0.0, "station": _free_stove() if kind == "cook" else ""})
	for stain in stains:
		if task_available("clean", stain.id):
			found.append({"kind": "clean", "id": stain.id, "table": stain.table, "urgency": float(stains.size()) / STAIN_LIMIT})
	return found


func start_cooking(station: String = "stove") -> bool:
	if carrying != Carry.NONE: return _reject("双手已占用，先交付手中物品。")
	var id := selected_order_id
	if not orders.has(id) or orders[id].state != "waiting" or not orders[id].ingredients_reserved: id = most_urgent_waiting()
	if id == 0: return _reject("当前没有食材充足的待制作订单。")
	if not claim_task("cook", id, "player", station):
		return _reject("这个炉灶已在做菜，或两个出餐位都已安排菜品。")
	return start_cooking_as(id, "player")


func start_cooking_as(id: int, actor: String) -> bool:
	if task_owner("cook", id) != actor or not cook_stations.has(id) or not orders.has(id) or orders[id].state != "waiting":
		return false
	if not _consume_order_ingredients(id): return false
	if actor == "player": selected_order_id = id
	var attempt := next_attempt_id
	next_attempt_id += 1
	orders[id].state = "cooking"
	orders[id].cook_attempt = attempt
	task_active[task_key("cook", id)] = true
	_sync_cooking_primary()
	if actor == "player": cooking_requested.emit(id, attempt, orders[id].recipe)
	changed.emit()
	return true


func complete_cooking(id: int, attempt: int, result: Dictionary) -> bool:
	if not orders.has(id) or not cook_stations.has(id) or orders[id].cook_attempt != attempt or pass_order_ids.size() >= PASS_CAPACITY: return false
	if orders[id].state != "cooking" or not result.get("success", false) or result.get("doneness", 0.0) < CookingRules.MIN_DONENESS or result.get("burn", 100.0) >= CookingRules.BURN_LIMIT: return false
	orders[id].score = result.get("score", 0)
	orders[id].bonus = CookingRules.bonus_for_result(result)
	orders[id].state = "ready"
	pass_order_ids.append(id)
	_sync_pass_primary()
	release_task("cook", id)
	_sync_cooking_primary()
	feedback.emit("%02d 号桌的%s已出锅，去出餐台取餐。" % [orders[id].table + 1, recipe_name(orders[id].recipe)])
	changed.emit()
	return true


func cancel_cooking(id: int, attempt: int) -> bool:
	if not orders.has(id) or not cook_stations.has(id) or orders[id].cook_attempt != attempt: return false
	if orders[id].state != "cooking": return false
	orders[id].state = "waiting"
	release_task("cook", id)
	_sync_cooking_primary()
	if _reserve_recipe(orders[id].recipe):
		orders[id].ingredients_reserved = true
		feedback.emit("本次烹饪已取消，已重新预留一份食材。")
	else:
		feedback.emit("本次烹饪已取消；食材已消耗，库存不足以重做。")
	changed.emit()
	return true


func interact(target: String) -> bool:
	return interact_as("player", target)


func interact_as(actor: String, target: String, target_order_id: int = 0) -> bool:
	if (actor != "player" and actor not in WORKER_IDS) or phase != "open" or ended: return false
	if actor != "player" and not worker_active(actor): return false
	if target in STOVES:
		return start_cooking(target) if actor == "player" else false
	var held: Carry = carrying if actor == "player" else worker_carrying(actor)
	var held_id: int = carried_order_id if actor == "player" else worker_carried_order(actor)
	if target == "pass":
		if held == Carry.FOOD:
			if actor != "player": return false
			if pass_order_ids.size() >= PASS_CAPACITY: return _reject("出餐台已放满食物。")
			if not orders.has(held_id) or orders[held_id].state != "carried": return _reject("这份菜已失效。")
			pass_order_ids.append(held_id)
			_sync_pass_primary()
			orders[held_id].state = "ready"
			_set_actor_carry(actor, Carry.NONE, 0, -1)
			release_task("serve", held_id, actor)
			changed.emit()
			return true
		if held != Carry.NONE: return _reject("先把餐盘送到回收台。")
		var id := target_order_id if target_order_id != 0 else pass_order_id
		if id == 0 or id not in pass_order_ids or not orders.has(id): return _reject("出餐台暂无可取的食物。")
		if task_owner("serve", id) != actor:
			if not claim_task("serve", id, actor): return false
		if task_owner("serve", id) != actor: return _reject("这份菜已由员工领取，正在上菜。")
		pass_order_ids.erase(id)
		_sync_pass_primary()
		orders[id].state = "carried"
		task_active[task_key("serve", id)] = true
		_set_actor_carry(actor, Carry.FOOD, id, -1)
		changed.emit()
		return true
	if target == "sink":
		if held != Carry.PLATE: return _reject("这里只回收用过的餐盘。")
		var table_id: int = carried_table_id if actor == "player" else worker_carried_table(actor)
		var id: int = tables[table_id]
		if id == 0 or not orders.has(id) or orders[id].state != "clearing" or task_owner("clear", id) != actor: return false
		orders.erase(id)
		tables[table_id] = 0
		_set_actor_carry(actor, Carry.NONE, 0, -1)
		release_task("clear", id, actor)
		changed.emit()
		_finish_if_clear()
		return true
	if target.begins_with("table_"):
		var table_id := target.trim_prefix("table_").to_int() - 1
		if table_id < 0 or table_id >= TABLE_COUNT: return false
		var id: int = tables[table_id]
		if id == 0 or not orders.has(id): return _reject("这张桌子目前空着。")
		var order: Dictionary = orders[id]
		if held == Carry.FOOD:
			if held_id != id or order.state != "carried": return _reject("这份菜属于另一张桌。")
			if task_owner("serve", id) != actor: return false
			_set_actor_carry(actor, Carry.NONE, 0, -1)
			order.state = "eating"
			order.eat_clock = 0.0
			release_task("serve", id, actor)
			feedback.emit("%02d 号桌上菜完成。" % [table_id + 1])
			changed.emit()
			return true
		if held != Carry.NONE: return _reject("请先回收手中的餐盘。")
		if order.state != "dirty": return _reject("这张桌子尚不需要收盘。")
		if task_owner("clear", id) != actor:
			if not claim_task("clear", id, actor): return false
		if task_owner("clear", id) != actor: return _reject("员工已领取收盘任务。")
		order.state = "clearing"
		task_active[task_key("clear", id)] = true
		_set_actor_carry(actor, Carry.PLATE, 0, table_id)
		changed.emit()
		return true
	if target.begins_with("stain_"):
		if held != Carry.NONE: return _reject("先放下手中的物品，再清洁地面。")
		var stain_id := target.trim_prefix("stain_").to_int()
		if task_owner("clean", stain_id) != actor:
			if not claim_task("clean", stain_id, actor): return false
		if task_owner("clean", stain_id) != actor: return _reject("员工正在清洁这处污渍。")
		for i in range(stains.size()):
			if stains[i].id == stain_id:
				stains.remove_at(i)
				release_task("clean", stain_id, actor)
				feedback.emit("污渍已清理，餐厅更整洁了。")
				changed.emit()
				_finish_if_clear()
				return true
		release_task("clean", stain_id, actor)
	return _reject("这里暂时没有可完成的工作。")


func discard_employee_food(actor: String = "employee") -> bool:
	if worker_carrying(actor) != Carry.FOOD: return false
	var carried_id := worker_carried_order(actor)
	if orders.has(carried_id) and orders[carried_id].state == "carried": return false
	_set_actor_carry(actor, Carry.NONE, 0, -1)
	changed.emit()
	return true


func abort_employee_job(kind: String, id: int, reason: String, actor: String = "employee") -> void:
	# Recovery always releases the reservation and any object in the employee's hands.
	if kind == "cook" and cook_stations.has(id) and orders.has(id) and orders[id].state == "cooking":
		cancel_cooking(id, orders[id].cook_attempt)
	elif kind == "serve" and worker_carrying(actor) == Carry.FOOD and worker_carried_order(actor) == id:
		if orders.has(id) and orders[id].state == "carried" and pass_order_ids.size() < PASS_CAPACITY:
			orders[id].state = "ready"
			pass_order_ids.append(id)
			_sync_pass_primary()
		elif orders.has(id) and orders[id].state == "carried":
			_timeout(id)
		_set_actor_carry(actor, Carry.NONE, 0, -1)
	elif kind == "clear" and worker_carrying(actor) == Carry.PLATE and orders.has(id) and orders[id].state == "clearing":
		orders[id].state = "dirty"
		_set_actor_carry(actor, Carry.NONE, 0, -1)
	release_task(kind, id, actor)
	feedback.emit("员工暂时无法完成%s：%s；任务已释放。" % [kind, reason])
	changed.emit()


func _set_actor_carry(actor: String, kind: Carry, id: int, table_id: int) -> void:
	if actor == "player":
		carrying = kind
		carried_order_id = id
		carried_table_id = table_id
	else:
		worker_carry[actor] = {"kind": kind, "order": id, "table": table_id}
		if actor == "employee":
			employee_carrying = kind
			employee_carried_order_id = id
			employee_carried_table_id = table_id


func most_urgent_waiting() -> int:
	var best_id := 0
	var best_time := -1.0
	for id: int in orders:
		if orders[id].state == "waiting" and orders[id].ingredients_reserved and orders[id].waited > best_time:
			best_time = orders[id].waited
			best_id = id
	return best_id


func patience_remaining(id: int) -> float:
	if not orders.has(id): return 0.0
	return maxf(0.0, PATIENCE - orders[id].waited)


func recipe_name(id: String) -> String:
	return RECIPES.get(id, RECIPES.rice).name


func summary() -> Dictionary:
	var totals := {"income": 0, "purchase": 0, "wages": 0, "furniture": 0, "equipment": 0, "expansion": 0}
	for entry in ledger:
		totals[entry.kind] += absi(entry.amount)
	return {"day": day_number, "opening_cash": day_opening_cash, "coins": coins, "cash_change": coins - day_opening_cash, "income": totals.income, "expenses": {"purchase": totals.purchase, "wages": totals.wages, "furniture": totals.furniture, "equipment": totals.equipment, "expansion": totals.expansion}, "ingredient_cost": ingredient_consumed_cost, "operating_profit": totals.income - ingredient_consumed_cost - totals.wages, "ledger": ledger.duplicate(true), "served": served, "lost": lost, "no_sale": no_sale, "missing_first_choices": missing_first_choices.duplicate(), "price_refusals": price_refusals, "good_reviews": good_reviews, "bad_reviews": bad_reviews, "stains": stains.size(), "elapsed": elapsed, "payments": payments.duplicate(), "reviews": reviews.duplicate(true), "average_wait": _average_wait(), "reason": "未找到想买的菜" if lost > 0 and no_sale == lost else "等餐超时" if lost > 0 else "营业完成"}


func start_day() -> bool:
	if phase != "preopen": return false
	var can_serve := false
	for recipe_id: String in RECIPE_IDS:
		if menu_enabled[recipe_id] and portions_available(recipe_id) > 0: can_serve = true
	if not can_serve: return _reject("没有可制作的在售菜品；请采购食材、调整菜单或领取应急补给。")
	employee_attending_count = wage_reserved / DAILY_WAGE
	_update_staff_counts()
	phase = "open"
	feedback.emit("第 %d 天营业开始；%d/%d 名员工出勤。" % [day_number, employee_attending_count, employee_hired_count])
	changed.emit()
	return true


func next_day() -> bool:
	if phase != "summary" or not ended: return false
	day_number += 1
	day_opening_cash = coins
	ledger.clear()
	transaction_keys.clear()
	_clear_day()
	phase = "preopen"
	_refresh_wage_reservation()
	changed.emit()
	return true


func new_game() -> void:
	day_number = 1
	coins = STARTING_CASH
	employee_hired_count = 0
	employee_attending_count = 0
	_update_staff_counts()
	wage_reserved = 0
	day_opening_cash = STARTING_CASH
	_reset_inventory()
	menu_enabled = {"rice": true, "noodles": true, "tomato_egg": true, "egg_noodles": true}
	menu_prices = {"rice": 18, "noodles": 24, "tomato_egg": 20, "egg_noodles": 22}
	purchase_sequence = 1
	ledger.clear()
	day_reports.clear()
	transaction_keys.clear()
	_clear_day()
	phase = "preopen"
	changed.emit()


func reset() -> void:
	new_game()


func spend(kind: String, amount: int, reference: String) -> bool:
	if kind not in EXPENSE_KINDS or kind == "wages" or amount <= 0 or phase not in ["preopen", "summary"]: return false
	if phase == "preopen" and coins - amount < wage_reserved: return false
	return _post_transaction(kind, -amount, reference)


func _post_transaction(kind: String, amount: int, reference: String) -> bool:
	if reference == "" or amount == 0: return false
	if transaction_keys.has(reference) or coins + amount < 0: return false
	if kind == "income" and (amount < 0 or phase != "open"): return false
	if kind != "income" and (amount > 0 or kind not in EXPENSE_KINDS): return false
	transaction_keys[reference] = true
	coins += amount
	ledger.append({"day": day_number, "kind": kind, "amount": amount, "reference": reference})
	if phase == "summary" and not day_reports.is_empty(): day_reports[-1] = summary().duplicate(true)
	changed.emit()
	return true


func _clear_day() -> void:
	# Keep sequence numbers monotonic so delayed callbacks cannot attach to a new day.
	next_order_id += 1
	next_attempt_id += 1
	elapsed = 0.0
	day_closed = false
	ended = false
	served = 0
	lost = 0
	employee_attending_count = 0
	_update_staff_counts()
	no_sale = 0
	missing_first_choices.clear()
	price_refusals = 0
	good_reviews = 0
	bad_reviews = 0
	spawn_clock = 0.0
	selected_order_id = 0
	orders.clear()
	browsers.clear()
	tables = [0, 0, 0, 0]
	pass_order_id = 0
	pass_order_ids.clear()
	carrying = Carry.NONE
	carried_order_id = 0
	carried_table_id = -1
	cooking_order_id = 0
	cooking_attempt_id = 0
	stains.clear()
	for ingredient: String in INGREDIENTS: reserved_inventory[ingredient] = 0
	emergency_uses_today = 0
	ingredient_consumed_cost = 0
	task_owners.clear()
	task_active.clear()
	cook_stations.clear()
	employee_carrying = Carry.NONE
	employee_carried_order_id = 0
	employee_carried_table_id = -1
	worker_carry.clear()
	payments.clear()
	reviews.clear()
	wait_records.clear()


func _timeout(id: int) -> void:
	if not orders.has(id): return
	var order: Dictionary = orders[id]
	if order.state not in ["arriving", "waiting", "cooking", "ready", "carried"]: return
	var was_cooking: bool = order.state == "cooking" and cook_stations.has(id)
	_release_order_ingredients(id)
	order.state = "leaving_lost"
	lost += 1
	bad_reviews += 1
	wait_records.append(minf(order.waited, PATIENCE))
	reviews.append({"table": order.table + 1, "good": false, "reason": "等餐超时"})
	for kind in ["cook", "serve", "clear"]: release_task(kind, id)
	_sync_cooking_primary()
	if was_cooking: cooking_expired.emit(id)
	pass_order_ids.erase(id)
	_sync_pass_primary()
	if carrying == Carry.FOOD and carried_order_id == id:
		carrying = Carry.NONE
		carried_order_id = 0
	if selected_order_id == id: selected_order_id = 0
	customer_leave_requested.emit(id)
	feedback.emit("%02d 号桌等餐超时离开了。" % [order.table + 1])
	changed.emit()


func _pay_and_leave(id: int) -> void:
	if not orders.has(id) or orders[id].state != "eating": return
	var order: Dictionary = orders[id]
	var amount: int = order.price + order.bonus
	if not _post_transaction("income", amount, "payment:%d" % id): return
	order.state = "leaving_paid"
	var clean := stains.size() <= 1
	var prompt := ""
	if order.choice_rank >= 2: prompt = "只能选第三喜好的菜"
	elif order.waited > 34.0: prompt = "等待较久"
	elif order.score < 65: prompt = "菜品品质普通"
	elif not clean: prompt = "地面不够整洁"
	elif order.choice_rank == 1: prompt = "没买到首选，但替代菜还不错"
	else: prompt = "出餐及时，味道很好"
	var good := prompt in ["出餐及时，味道很好", "没买到首选，但替代菜还不错"]
	order.review = prompt
	reviews.append({"table": order.table + 1, "good": good, "reason": prompt, "satisfaction": order.satisfaction})
	if good: good_reviews += 1
	else: bad_reviews += 1
	wait_records.append(order.waited)
	payments.append(amount)
	served += 1
	customer_leave_requested.emit(id)
	feedback.emit("%02d 号桌付款 +%d；评价：%s。" % [order.table + 1, amount, prompt])
	changed.emit()


func _make_stain(table_id: int) -> void:
	if stains.size() >= STAIN_LIMIT: return
	if served % 2 != 0: return
	stains.append({"id": next_stain_id, "table": table_id})
	next_stain_id += 1


func _force_finish() -> void:
	for id: int in orders.keys():
		if orders[id].state in ["arriving", "waiting", "cooking", "ready", "carried"]: _timeout(id)
	for id: int in browsers.keys():
		customer_leave_requested.emit(id)
		_record_no_sale(id)
	_finish_day()


func _finish_if_clear() -> void:
	if not day_closed or ended: return
	for order in orders.values():
		if order.state not in ["dirty", "clearing"]: return
	if carrying != Carry.NONE or not stains.is_empty() or not browsers.is_empty(): return
	for actor: String in worker_carry:
		if worker_carrying(actor) != Carry.NONE: return
	_finish_day()


func _finish_day() -> void:
	if ended: return
	if employee_attending_count > 0:
		_post_transaction("wages", -DAILY_WAGE * employee_attending_count, "wages:%d" % day_number)
	wage_reserved = 0
	ended = true
	phase = "summary"
	task_owners.clear()
	task_active.clear()
	cook_stations.clear()
	pass_order_ids.clear()
	pass_order_id = 0
	cooking_order_id = 0
	cooking_attempt_id = 0
	employee_carrying = Carry.NONE
	employee_carried_order_id = 0
	employee_carried_table_id = -1
	worker_carry.clear()
	var report := summary()
	day_reports.append(report.duplicate(true))
	day_finished.emit(report)
	changed.emit()


func _reject(message: String) -> bool:
	feedback.emit(message)
	return false


func _average_wait() -> float:
	if wait_records.is_empty(): return 0.0
	var total := 0.0
	for seconds in wait_records: total += seconds
	return total / wait_records.size()
