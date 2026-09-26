extends Node2D
## One worker instance; the model owns shared task reservations and per-worker carry state.

const CookingRules = preload("res://scripts/cooking/cooking_model.gd")
const SPEED := 160.0
const IDLE_SPEED := 48.0
const IDLE_RADIUS := 68.0
const CELL := 20.0
const GRID_ORIGIN := Vector2(70, 310)
const GRID_WIDTH := 80
const GRID_HEIGHT := 18
const HOME := Vector2(375, 570)
const WORK_LABELS := {"cook": "做菜", "serve": "上菜", "clear": "收盘", "clean": "清洁"}

var model: RefCounted
var stations: Dictionary = {}
var actor_id := "employee"
var home_position := HOME
var enabled := true
var work_enabled := {"serve": true, "clear": true, "clean": true, "cook": true}
var priority: Array[String] = ["serve", "clear", "clean", "cook"]
var job: Dictionary = {}
var stage := "idle"
var status := "待命"
var failure_reason := ""
var route: PackedVector2Array = PackedVector2Array()
var route_index := 0
var grid: AStarGrid2D
var cook_rules: RefCounted
var failed_until: Dictionary = {}
var clock := 0.0
var idle_center := HOME
var idle_wait := 0.0
var tasks_completed := {"serve": 0, "clear": 0, "clean": 0, "cook": 0}
@onready var avatar: Node2D = $Avatar
@onready var title_label: Label = $Title


func configure(day_model: RefCounted, all_stations: Dictionary, worker_id: String = "employee", home: Vector2 = HOME) -> void:
	model = day_model
	stations = all_stations
	actor_id = worker_id
	home_position = home
	idle_center = home


func _ready() -> void:
	avatar.sprite.modulate = [Color("8cbad6"), Color("d6a48c"), Color("a8c890")][model.WORKER_IDS.find(actor_id)]
	title_label.text = "员工 %d" % (model.WORKER_IDS.find(actor_id) + 1)


func _physics_process(delta: float) -> void:
	if model == null or model.phase != "open" or model.ended or not model.worker_active(actor_id): return
	clock += delta
	if grid == null: _build_grid()
	if model.worker_carrying(actor_id) == model.Carry.FOOD and (not model.orders.has(model.worker_carried_order(actor_id)) or model.orders[model.worker_carried_order(actor_id)].state != "carried"):
		_begin_discard()
	if not job.is_empty() and stage != "discard" and not _job_valid():
		_finish_invalid()
	if job.is_empty():
		if enabled: _choose_job()
		else: status = "休息中"
	if not job.is_empty():
		if stage == "cooking": _cook(delta)
		else: _move(delta)
	else:
		_wander(delta)
	avatar.update_pose(_direction(), not route.is_empty() and route_index < route.size(), model.worker_carrying(actor_id))
	if model.worker_carrying(actor_id) == model.Carry.FOOD and model.orders.has(model.worker_carried_order(actor_id)):
		avatar.held.modulate = model.RECIPES[model.orders[model.worker_carried_order(actor_id)].recipe].color
	else: avatar.held.modulate = Color.WHITE


func _direction() -> Vector2:
	if route_index < route.size(): return (route[route_index] - position).normalized()
	return Vector2.DOWN


func _choose_job() -> void:
	var choices: Array[Dictionary] = []
	for candidate in model.available_tasks():
		if not work_enabled[candidate.kind] or failed_until.get(model.task_key(candidate.kind, candidate.id), 0.0) > clock: continue
		var destination := _first_target(candidate)
		if not stations.has(destination): continue
		var rank := priority.find(candidate.kind)
		candidate["rank"] = rank
		candidate["distance"] = position.distance_to(stations[destination].interaction_position())
		choices.append(candidate)
	choices.sort_custom(func(a: Dictionary, b: Dictionary):
		if a.rank != b.rank: return a.rank < b.rank
		if not is_equal_approx(a.urgency, b.urgency): return a.urgency > b.urgency
		return a.distance < b.distance)
	for candidate in choices:
		if not model.claim_task(candidate.kind, candidate.id, actor_id, candidate.get("station", "")): continue
		job = candidate
		stage = "moving"
		status = "%s · %02d 号桌" % [WORK_LABELS[job.kind], job.table + 1]
		if _route_to(stations[_first_target(job)].interaction_position()): return
		_failed_path()
	status = "出餐位已占用，等待上菜" if model.pass_order_id != 0 else ("暂时没有可领取的工作" if model.orders.size() > 0 else "待命")


func _first_target(task: Dictionary) -> String:
	match task.kind:
		"cook": return task.station
		"serve": return "pass"
		"clear": return "table_%d" % (task.table + 1)
		"clean": return "stain_%d" % task.id
	return ""


func _job_valid() -> bool:
	if job.is_empty() or job.kind == "discard": return true
	if model.task_owner(job.kind, job.id) != actor_id: return false
	if job.kind == "clean":
		for stain in model.stains:
			if stain.id == job.id: return true
		return false
	if not model.orders.has(job.id): return false
	var state: String = model.orders[job.id].state
	match job.kind:
		"cook": return state in ["waiting", "cooking"]
		"serve": return state in ["ready", "carried"]
		"clear": return state in ["dirty", "clearing"]
	return false


func _move(delta: float, speed: float = SPEED) -> void:
	if route_index >= route.size():
		_arrived()
		return
	var target: Vector2 = route[route_index]
	position = position.move_toward(target, speed * delta)
	if position.distance_to(target) <= 1.5:
		route_index += 1
		if route_index >= route.size(): _arrived()


func _arrived() -> void:
	route = PackedVector2Array()
	route_index = 0
	if job.is_empty(): return
	var kind: String = job.kind
	var id: int = job.id
	if stage == "discard":
		model.discard_employee_food(actor_id)
		job.clear()
		stage = "idle"
		idle_center = position
		idle_wait = randf_range(0.8, 1.8)
		status = "失效菜品已回收"
		return
	match kind:
		"cook":
			if not model.start_cooking_as(id, actor_id):
				_finish_invalid()
				return
			cook_rules = CookingRules.new()
			cook_rules.recipe_id = model.orders[id].recipe
			cook_rules.recipe_speed = model.RECIPES[cook_rules.recipe_id].speed * model.cooking_speed_multiplier()
			cook_rules.start()
			stage = "cooking"
			status = "正在制作%s" % model.recipe_name(cook_rules.recipe_id)
		"serve":
			if stage == "moving":
				if not model.interact_as(actor_id, "pass", id):
					_finish_invalid()
					return
				stage = "delivering"
				if not _route_to(stations["table_%d" % (job.table + 1)].interaction_position()): _failed_path()
			else:
				if model.interact_as(actor_id, "table_%d" % (job.table + 1)): _finish_job()
				else: _finish_invalid()
		"clear":
			if stage == "moving":
				if not model.interact_as(actor_id, "table_%d" % (job.table + 1)):
					_finish_invalid()
					return
				stage = "returning"
				if not _route_to(stations.sink.interaction_position()): _failed_path()
			else:
				if model.interact_as(actor_id, "sink"): _finish_job()
				else: _finish_invalid()
		"clean":
			if model.interact_as(actor_id, "stain_%d" % id): _finish_job()
			else: _finish_invalid()


func _cook(delta: float) -> void:
	if cook_rules == null or job.is_empty(): return
	var recipe_id: String = cook_rules.recipe_id
	var heat: bool = cook_rules.temperature < 88.0
	cook_rules.advance(delta, heat)
	if cook_rules.state == CookingRules.State.RUNNING and cook_rules.stir_progress >= 0.8 and cook_rules.doneness + 12.0 <= 102.0:
		cook_rules.stir()
	if cook_rules.state == CookingRules.State.RUNNING and cook_rules.doneness >= 98.0: cook_rules.plate()
	if cook_rules.state == CookingRules.State.RESULT:
		var id: int = job.id
		var attempt: int = model.orders[id].cook_attempt if model.orders.has(id) else 0
		if cook_rules.result.success and model.complete_cooking(id, attempt, cook_rules.result):
			_finish_job()
		else:
			model.cancel_cooking(id, attempt)
			_finish_invalid()
		cook_rules = null


func _finish_job() -> void:
	if not job.is_empty() and tasks_completed.has(job.kind): tasks_completed[job.kind] += 1
	idle_center = position
	idle_wait = randf_range(0.8, 1.8)
	job.clear()
	stage = "idle"
	status = "待命"
	failure_reason = ""
	route = PackedVector2Array()
	route_index = 0


func _finish_invalid() -> void:
	var transferred: bool = not job.is_empty() and job.kind != "discard" and model.task_owner(job.kind, job.id) != actor_id
	if not job.is_empty() and job.kind != "discard":
		if not transferred: model.abort_employee_job(job.kind, job.id, "订单已失效", actor_id)
	job.clear()
	idle_center = position
	idle_wait = 0.8
	stage = "idle"
	route = PackedVector2Array()
	route_index = 0
	status = "任务已更新，重新安排" if transferred else "任务失效，重新排班"


func _begin_discard() -> void:
	if stage == "discard": return
	if not job.is_empty() and job.kind != "discard": model.release_task(job.kind, job.id, actor_id)
	job = {"kind": "discard", "id": 0, "table": -1}
	stage = "discard"
	status = "回收失效菜品"
	if not _route_to(stations.sink.interaction_position()):
		model.discard_employee_food(actor_id)
		job.clear()
		stage = "idle"
		idle_center = position
		failure_reason = "回收台不可达，菜品已安全移除"
		status = failure_reason


func _failed_path() -> void:
	if job.is_empty(): return
	var key: String = model.task_key(job.kind, job.id)
	failed_until[key] = clock + 6.0
	failure_reason = "%s路径不可达" % WORK_LABELS.get(job.kind, "任务")
	model.abort_employee_job(job.kind, job.id, failure_reason, actor_id)
	job.clear()
	stage = "idle"
	idle_center = position
	idle_wait = 0.8
	status = failure_reason
	route = PackedVector2Array()
	route_index = 0


func _wander(delta: float) -> void:
	if route_index < route.size():
		_move(delta, IDLE_SPEED)
		return
	idle_wait -= delta
	if idle_wait > 0.0: return
	idle_wait = randf_range(1.5, 3.0)
	for attempt in range(8):
		var offset := Vector2.RIGHT.rotated(randf_range(0.0, TAU)) * randf_range(25.0, IDLE_RADIUS)
		var candidate := idle_center + offset
		var open_cell := _nearest_open(candidate, 14.0)
		if open_cell.x < 0: continue
		var target := grid.get_point_position(open_cell)
		if position.distance_to(target) < 18.0 or position.distance_to(target) > IDLE_RADIUS * 2.0: continue
		if _route_to(target) and route.size() > 0: return
		route = PackedVector2Array()
		route_index = 0


func reset_day() -> void:
	job.clear()
	stage = "idle"
	status = "待命"
	failure_reason = ""
	cook_rules = null
	route = PackedVector2Array()
	route_index = 0
	failed_until.clear()
	tasks_completed = {"serve": 0, "clear": 0, "clean": 0, "cook": 0}
	position = home_position
	idle_center = position
	idle_wait = randf_range(0.4, 1.4)


func reset_new_game() -> void:
	reset_day()
	enabled = true
	work_enabled = {"serve": true, "clear": true, "clean": true, "cook": true}
	priority = ["serve", "clear", "clean", "cook"]


func toggle_work(kind: String) -> void:
	if work_enabled.has(kind): work_enabled[kind] = not work_enabled[kind]


func move_priority_up(kind: String) -> void:
	var index := priority.find(kind)
	if index > 0:
		priority.remove_at(index)
		priority.insert(index - 1, kind)


func _build_grid() -> void:
	grid = AStarGrid2D.new()
	grid.region = Rect2i(0, 0, GRID_WIDTH, GRID_HEIGHT)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = GRID_ORIGIN
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	var space := get_world_2d().direct_space_state
	var shape := RectangleShape2D.new()
	shape.size = Vector2(18, 12)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	for x in range(GRID_WIDTH):
		for y in range(GRID_HEIGHT):
			var point := Vector2i(x, y)
			query.transform = Transform2D(0.0, grid.get_point_position(point))
			if not space.intersect_shape(query, 1).is_empty(): grid.set_point_solid(point)


func _route_to(destination: Vector2) -> bool:
	if position.distance_to(destination) <= 22.0:
		route = PackedVector2Array()
		route_index = 0
		return true
	if grid == null: return false
	var start := _nearest_open(position, 40.0)
	var goal := _nearest_open(destination, 48.0)
	if start.x < 0 or goal.x < 0: return false
	var path := grid.get_point_path(start, goal)
	if path.is_empty(): return false
	route = path
	if path[path.size() - 1].distance_to(destination) > 45.0: return false
	route.append(destination)
	route_index = 0
	return true


func _nearest_open(point: Vector2, max_distance: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var distance := max_distance
	for x in range(GRID_WIDTH):
		for y in range(GRID_HEIGHT):
			var cell := Vector2i(x, y)
			if grid.is_point_solid(cell): continue
			var value := grid.get_point_position(cell).distance_to(point)
			if value < distance:
				distance = value
				best = cell
	return best
