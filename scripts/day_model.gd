class_name DayModel
extends RefCounted
## Four-table manual service. All time, reservations and money live here.

signal changed
signal feedback(message: String)
signal customer_requested(order_id: int, table_id: int)
signal customer_leave_requested(order_id: int)
signal cooking_requested(order_id: int, attempt_id: int, recipe_id: String)
signal cooking_expired(order_id: int)
signal day_finished(summary: Dictionary)

enum Carry { NONE, FOOD, PLATE }
const TABLE_COUNT := 4
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
	"rice": {"name": "香煎蛋饭", "price": 18, "speed": 1.0, "color": Color("e7bf70")},
	"noodles": {"name": "番茄炒面", "price": 24, "speed": 0.82, "color": Color("d97853")},
}
const CookingRules = preload("res://scripts/cooking/cooking_model.gd")

var elapsed := 0.0
var day_closed := false
var ended := false
var coins := 0
var served := 0
var lost := 0
var good_reviews := 0
var bad_reviews := 0
var next_order_id := 1
var next_attempt_id := 1
var spawn_clock := 0.0
var selected_order_id := 0
var orders: Dictionary = {}
var tables: Array[int] = [0, 0, 0, 0]
var pass_order_id := 0
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


func advance(delta: float) -> void:
	if ended or delta <= 0.0: return
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
	if day_closed or ended or orders.size() >= TABLE_COUNT: return false
	var table_id := -1
	for i in range(TABLE_COUNT):
		if tables[i] == 0:
			table_id = i
			break
	if table_id < 0: return false
	var id := next_order_id
	next_order_id += 1
	var recipe_id := "rice" if id % 2 == 1 else "noodles"
	orders[id] = {"id": id, "table": table_id, "recipe": recipe_id, "state": "arriving", "waited": 0.0, "eat_clock": 0.0, "score": 0, "bonus": 0, "review": "", "cook_attempt": 0}
	tables[table_id] = id
	customer_requested.emit(id, table_id)
	changed.emit()
	return true


func seat_customer(id: int) -> bool:
	if not orders.has(id) or orders[id].state != "arriving": return false
	orders[id].state = "waiting"
	if selected_order_id == 0: selected_order_id = id
	feedback.emit("%02d 号桌点了%s。" % [orders[id].table + 1, recipe_name(orders[id].recipe)])
	changed.emit()
	return true


func customer_departed(id: int) -> bool:
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


func start_cooking() -> bool:
	if carrying != Carry.NONE: return _reject("双手已占用，先交付手中物品。")
	if cooking_order_id != 0: return _reject("炉灶正在使用。")
	if pass_order_id != 0: return _reject("出餐台已有一份菜，请先送走。")
	var id := selected_order_id
	if not orders.has(id) or orders[id].state != "waiting":
		id = most_urgent_waiting()
	if id == 0: return _reject("当前没有等待制作的订单。")
	selected_order_id = id
	cooking_order_id = id
	cooking_attempt_id = next_attempt_id
	next_attempt_id += 1
	orders[id].state = "cooking"
	orders[id].cook_attempt = cooking_attempt_id
	cooking_requested.emit(id, cooking_attempt_id, orders[id].recipe)
	changed.emit()
	return true


func complete_cooking(id: int, attempt: int, result: Dictionary) -> bool:
	if cooking_order_id != id or cooking_attempt_id != attempt or not orders.has(id) or pass_order_id != 0: return false
	if orders[id].state != "cooking" or not result.get("success", false) or result.get("doneness", 0.0) < CookingRules.MIN_DONENESS or result.get("burn", 100.0) >= CookingRules.BURN_LIMIT: return false
	orders[id].score = result.get("score", 0)
	orders[id].bonus = CookingRules.bonus_for_result(result)
	orders[id].state = "ready"
	pass_order_id = id
	cooking_order_id = 0
	cooking_attempt_id = 0
	feedback.emit("%02d 号桌的%s已出锅，去出餐台取餐。" % [orders[id].table + 1, recipe_name(orders[id].recipe)])
	changed.emit()
	return true


func cancel_cooking(id: int, attempt: int) -> bool:
	if cooking_order_id != id or cooking_attempt_id != attempt or not orders.has(id): return false
	if orders[id].state != "cooking": return false
	orders[id].state = "waiting"
	cooking_order_id = 0
	cooking_attempt_id = 0
	feedback.emit("本次烹饪已取消，订单仍在。")
	changed.emit()
	return true


func interact(target: String) -> bool:
	if target == "stove": return start_cooking()
	if target == "pass":
		if carrying == Carry.FOOD:
			if pass_order_id != 0: return _reject("出餐台已有食物。")
			if not orders.has(carried_order_id): return _reject("这份菜已失效。")
			pass_order_id = carried_order_id
			orders[carried_order_id].state = "ready"
			carrying = Carry.NONE
			carried_order_id = 0
			changed.emit()
			return true
		if carrying != Carry.NONE: return _reject("先把餐盘送到回收台。")
		if pass_order_id == 0 or not orders.has(pass_order_id): return _reject("出餐台暂无可取的食物。")
		carried_order_id = pass_order_id
		pass_order_id = 0
		carrying = Carry.FOOD
		orders[carried_order_id].state = "carried"
		changed.emit()
		return true
	if target == "sink":
		if carrying != Carry.PLATE: return _reject("这里只回收用过的餐盘。")
		var id := tables[carried_table_id]
		if id != 0 and orders.has(id) and orders[id].state == "clearing":
			orders.erase(id)
			tables[carried_table_id] = 0
		carrying = Carry.NONE
		carried_table_id = -1
		changed.emit()
		_finish_if_clear()
		return true
	if target.begins_with("table_"):
		var table_id := target.trim_prefix("table_").to_int() - 1
		if table_id < 0 or table_id >= TABLE_COUNT: return false
		var id := tables[table_id]
		if id == 0 or not orders.has(id): return _reject("这张桌子目前空着。")
		var order: Dictionary = orders[id]
		if carrying == Carry.FOOD:
			if carried_order_id != id or order.state != "carried": return _reject("这份菜属于另一张桌。")
			carrying = Carry.NONE
			carried_order_id = 0
			order.state = "eating"
			order.eat_clock = 0.0
			feedback.emit("%02d 号桌上菜完成。" % [table_id + 1])
			changed.emit()
			return true
		if carrying != Carry.NONE: return _reject("请先回收手中的餐盘。")
		if order.state == "dirty":
			order.state = "clearing"
			carrying = Carry.PLATE
			carried_table_id = table_id
			changed.emit()
			return true
		return _reject("这张桌子尚不需要收盘。")
	if target.begins_with("stain_"):
		if carrying != Carry.NONE: return _reject("先放下手中的物品，再清洁地面。")
		var stain_id := target.trim_prefix("stain_").to_int()
		for i in range(stains.size()):
			if stains[i].id == stain_id:
				stains.remove_at(i)
				feedback.emit("污渍已清理，餐厅更整洁了。")
				changed.emit()
				_finish_if_clear()
				return true
	return _reject("这里暂时没有可完成的工作。")


func most_urgent_waiting() -> int:
	var best_id := 0
	var best_time := -1.0
	for id: int in orders:
		if orders[id].state == "waiting" and orders[id].waited > best_time:
			best_time = orders[id].waited
			best_id = id
	return best_id


func patience_remaining(id: int) -> float:
	if not orders.has(id): return 0.0
	return maxf(0.0, PATIENCE - orders[id].waited)


func recipe_name(id: String) -> String:
	return RECIPES.get(id, RECIPES.rice).name


func summary() -> Dictionary:
	return {"coins": coins, "served": served, "lost": lost, "good_reviews": good_reviews, "bad_reviews": bad_reviews, "stains": stains.size(), "elapsed": elapsed, "payments": payments.duplicate(), "reviews": reviews.duplicate(true), "average_wait": _average_wait(), "reason": "等餐超时" if lost > 0 else "营业完成"}


func reset() -> void:
	# Keep sequence numbers monotonic so delayed callbacks cannot attach to a new day.
	next_order_id += 1
	next_attempt_id += 1
	elapsed = 0.0
	day_closed = false
	ended = false
	coins = 0
	served = 0
	lost = 0
	good_reviews = 0
	bad_reviews = 0
	spawn_clock = 0.0
	selected_order_id = 0
	orders.clear()
	tables = [0, 0, 0, 0]
	pass_order_id = 0
	carrying = Carry.NONE
	carried_order_id = 0
	carried_table_id = -1
	cooking_order_id = 0
	cooking_attempt_id = 0
	stains.clear()
	payments.clear()
	reviews.clear()
	wait_records.clear()
	changed.emit()


func _timeout(id: int) -> void:
	if not orders.has(id): return
	var order: Dictionary = orders[id]
	if order.state not in ["waiting", "cooking", "ready", "carried"]: return
	order.state = "leaving_lost"
	lost += 1
	bad_reviews += 1
	wait_records.append(minf(order.waited, PATIENCE))
	reviews.append({"table": order.table + 1, "good": false, "reason": "等餐超时"})
	if cooking_order_id == id:
		cooking_order_id = 0
		cooking_attempt_id = 0
		cooking_expired.emit(id)
	if pass_order_id == id: pass_order_id = 0
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
	order.state = "leaving_paid"
	var clean := stains.size() <= 1
	var prompt := ""
	if order.waited > 34.0: prompt = "等待较久"
	elif order.score < 65: prompt = "菜品品质普通"
	elif not clean: prompt = "地面不够整洁"
	else: prompt = "出餐及时，味道很好"
	var good := prompt == "出餐及时，味道很好"
	order.review = prompt
	reviews.append({"table": order.table + 1, "good": good, "reason": prompt})
	if good: good_reviews += 1
	else: bad_reviews += 1
	wait_records.append(order.waited)
	var amount: int = RECIPES[order.recipe].price + order.bonus
	coins += amount
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
		if orders[id].state in ["waiting", "cooking", "ready", "carried"]: _timeout(id)
	_finish_day()


func _finish_if_clear() -> void:
	if not day_closed or ended: return
	for order in orders.values():
		if order.state not in ["dirty", "clearing"]: return
	if carrying != Carry.NONE or not stains.is_empty(): return
	_finish_day()


func _finish_day() -> void:
	if ended: return
	ended = true
	day_finished.emit(summary())
	changed.emit()


func _reject(message: String) -> bool:
	feedback.emit(message)
	return false


func _average_wait() -> float:
	if wait_records.is_empty(): return 0.0
	var total := 0.0
	for seconds in wait_records: total += seconds
	return total / wait_records.size()
