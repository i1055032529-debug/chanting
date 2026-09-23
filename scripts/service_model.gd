class_name ServiceModel
extends RefCounted
## Authoritative single-table service rules. No scene or input dependencies.

signal changed
signal feedback(message: String)
signal customer_requested
signal departure_requested
signal payment_received(amount: int)

enum Phase { EMPTY, ARRIVING, WAITING, COOKING, READY, CARRIED, EATING, LEAVING, DIRTY, CLEARING }
enum Carry { NONE, FOOD, PLATE }

const COOK_SECONDS := 2.8
const EAT_SECONDS := 4.0
const ARRIVAL_DELAY := 2.0
const PRICE := 18

var phase: Phase = Phase.EMPTY
var carrying: Carry = Carry.NONE
var coins := 0
var served := 0
var completed_cycles := 0
var order_id := 0
var clock := 0.0
var spawn_clock := 0.0
var paid := false
var tasks: Array[Dictionary] = []
var next_task_id := 1


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	match phase:
		Phase.EMPTY:
			spawn_clock += delta
			if spawn_clock >= ARRIVAL_DELAY:
				request_customer()
		Phase.COOKING:
			clock += delta
			if clock >= COOK_SECONDS:
				_finish_task("cook")
				_new_task("serve")
				_set_phase(Phase.READY)
				feedback.emit("出餐啦！到出餐台按 E 取餐。")
		Phase.EATING:
			clock += delta
			if clock >= EAT_SECONDS:
				_settle_once()
				_set_phase(Phase.LEAVING)
				departure_requested.emit()
				feedback.emit("顾客已付款 +18 金币，离店后就可以收盘。")


func request_customer() -> bool:
	if phase != Phase.EMPTY:
		return _reject("桌子还未恢复可用，请先完成本桌服务。")
	paid = false
	tasks.clear()
	_set_phase(Phase.ARRIVING)
	customer_requested.emit()
	return true


func seat_customer() -> bool:
	if phase != Phase.ARRIVING:
		return false
	order_id += 1
	_new_task("cook")
	_set_phase(Phase.WAITING)
	feedback.emit("新订单：香煎蛋饭。到烹饪台按 E 开始。")
	return true


func customer_departed() -> bool:
	if phase != Phase.LEAVING:
		return false
	_new_task("clear")
	_set_phase(Phase.DIRTY)
	feedback.emit("餐桌待收盘。拿起餐盘，送到回收台。")
	return true


func interact(target: String) -> bool:
	if phase == Phase.COOKING:
		return _reject("正在烹饪，请稍等片刻。")
	match target:
		"stove":
			if carrying != Carry.NONE:
				return _reject("双手已占用，请先交付手里的物品。")
			if phase != Phase.WAITING:
				return _reject("暂时没有需要制作的订单。")
			_start_task("cook")
			_set_phase(Phase.COOKING)
			feedback.emit("正在制作香煎蛋饭……")
			return true
		"pass":
			if carrying == Carry.FOOD and phase == Phase.CARRIED:
				carrying = Carry.NONE
				_set_phase(Phase.READY)
				feedback.emit("已将食物放回出餐台。")
				return true
			if carrying != Carry.NONE:
				return _reject("双手已占用，请先把餐盘送到回收台。")
			if phase != Phase.READY:
				return _reject("出餐台暂无食物，请先制作订单。")
			_start_task("serve")
			carrying = Carry.FOOD
			_set_phase(Phase.CARRIED)
			feedback.emit("端好啦！到 01 号桌下方按 E 上菜。")
			return true
		"table":
			if carrying == Carry.FOOD and phase == Phase.CARRIED:
				carrying = Carry.NONE
				_finish_task("serve")
				_set_phase(Phase.EATING)
				feedback.emit("上菜完成！顾客用餐后会自动付款。")
				return true
			if carrying != Carry.NONE:
				return _reject("请先把手里的物品送到对应位置。")
			if phase == Phase.DIRTY:
				_start_task("clear")
				carrying = Carry.PLATE
				_set_phase(Phase.CLEARING)
				feedback.emit("已拿起餐盘。送到回收台后，餐桌重新可用。")
				return true
			return _reject("%s" % table_hint())
		"sink":
			if carrying != Carry.PLATE or phase != Phase.CLEARING:
				return _reject("这里只回收用过的餐盘。")
			carrying = Carry.NONE
			_finish_task("clear")
			completed_cycles += 1
			spawn_clock = 0.0
			_set_phase(Phase.EMPTY)
			feedback.emit("一桌服务完成！餐桌已恢复，下一位顾客即将到来。")
			return true
	return _reject("没有可交互的目标。")


func reset() -> void:
	phase = Phase.EMPTY
	carrying = Carry.NONE
	coins = 0
	served = 0
	completed_cycles = 0
	order_id = 0
	clock = 0.0
	spawn_clock = 0.0
	paid = false
	tasks.clear()
	next_task_id = 1
	changed.emit()


func progress() -> float:
	if phase == Phase.COOKING:
		return clampf(clock / COOK_SECONDS, 0.0, 1.0)
	if phase == Phase.EATING:
		return clampf(clock / EAT_SECONDS, 0.0, 1.0)
	return 0.0


func phase_label() -> String:
	return ["等待入店", "顾客入店", "等待制作", "正在烹饪", "等待取餐", "等待上菜", "顾客用餐", "顾客离店", "等待收盘", "等待回收"][phase]


func table_hint() -> String:
	match phase:
		Phase.EMPTY: return "餐桌已可用，等待下一位顾客。"
		Phase.ARRIVING: return "顾客正在入座。"
		Phase.EATING: return "顾客正在用餐，请稍等。"
		Phase.LEAVING: return "顾客正在离店，请稍等再收盘。"
		Phase.CLEARING: return "餐盘送回回收台后，餐桌才能重新使用。"
	return "顾客已自动点单，请先做菜并从出餐台取餐。"


func _settle_once() -> void:
	if paid:
		return
	paid = true
	coins += PRICE
	served += 1
	payment_received.emit(PRICE)
	changed.emit()


func _set_phase(value: Phase) -> void:
	phase = value
	clock = 0.0
	changed.emit()


func _new_task(kind: String) -> void:
	tasks.append({"id": next_task_id, "order_id": order_id, "kind": kind, "state": "pending", "executor": ""})
	next_task_id += 1


func _start_task(kind: String) -> void:
	for task in tasks:
		if task.kind == kind and task.state != "done":
			task.state = "running"
			task.executor = "player"
			return


func _finish_task(kind: String) -> void:
	for task in tasks:
		if task.kind == kind:
			task.state = "done"
			return


func _reject(message: String) -> bool:
	feedback.emit(message)
	return false
