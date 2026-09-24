extends Node2D

const Model = preload("res://scripts/day_model.gd")
const Customer = preload("res://scenes/actors/customer.tscn")
const TableScene = preload("res://scenes/furniture/table.tscn")
const ChairScene = preload("res://scenes/furniture/chair.tscn")
const CookingScreen = preload("res://scenes/cooking/cooking_screen.tscn")
const StainScript = preload("res://scripts/stain.gd")
const EmployeeScene = preload("res://scenes/actors/employee.tscn")
const INTERACT_DISTANCE := 55.0
const CREAM := Color("f4e5cd")
const MUTED := Color("bea993")
const GOLD := Color("edbc72")
const RED := Color("e59172")
const GREEN := Color("91bf8b")
const TABLE_POSITIONS := [Vector2(530, 460), Vector2(900, 460), Vector2(530, 575), Vector2(900, 575)]
const STAIN_POSITIONS := [Vector2(455, 532), Vector2(795, 532), Vector2(455, 630), Vector2(795, 630)]

var model := Model.new()
var player: CharacterBody2D
var employee: Node2D
var actors: Node2D
var customers: Dictionary = {}
var stations: Dictionary = {}
var stain_nodes: Dictionary = {}
var font: SystemFont
var ui: Control
var labels: Dictionary = {}
var order_cards: Array[Label] = []
var prompt: Label
var pause_panel: Panel
var preopen_panel: Panel
var preopen_text: Label
var store_panel: Panel
var store_labels: Dictionary = {}
var purchase_quantities := {"rice": 1, "egg": 1, "noodles": 1, "tomato": 1}
var summary_panel: Panel
var summary_text: Label
var management_panel: Panel
var work_buttons: Dictionary = {}
var reset_dialog: ConfirmationDialog
var debug_label: Label
var debug_visible := false
var toast := "先查看开店准备，再开始今天的营业。"
var toast_time := 8.0
var nearest := ""
var cooking_screen: Control
var cooking_layer: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_setup_input()
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	_build_room()
	_build_ui()
	player.locked = true
	model.customer_requested.connect(_spawn_customer)
	model.customer_browsing.connect(_spawn_browser)
	model.customer_leave_requested.connect(_leave_customer)
	model.cooking_requested.connect(_open_cooking)
	model.cooking_expired.connect(_expire_cooking)
	model.day_finished.connect(_show_summary)
	model.changed.connect(_refresh_ui)
	model.feedback.connect(_show_feedback)
	_refresh_ui()


func _process(delta: float) -> void:
	toast_time = maxf(0.0, toast_time - delta)
	model.advance(delta)
	player.locked = is_instance_valid(cooking_screen) or model.phase != "open"
	player.carried = model.carrying
	if model.carrying == Model.Carry.FOOD and model.orders.has(model.carried_order_id):
		player.avatar.held.modulate = Model.RECIPES[model.orders[model.carried_order_id].recipe].color
	else:
		player.avatar.held.modulate = Color.WHITE
	_sync_stains()
	_refresh_ui()
	_refresh_employee_panel()
	nearest = closest_target() if model.phase == "open" else ""
	prompt.text = "[ E ] %s · %s" % [stations[nearest].display_name, _action_hint(nearest)] if nearest != "" else ("点击开始营业，进入第 %d 天。" % model.day_number if model.phase == "preopen" else "查看今日结算，准备下一天。" if model.phase == "summary" else "靠近工作台、餐桌或污渍按 E 交互；Q 切换待做订单")
	labels.toast.text = toast if toast_time > 0.0 else _next_step()
	for id: String in stations:
		stations[id].set_highlight(id == nearest)
	var pass_items: Array[Sprite2D] = [stations.pass.item, stations.pass.get_node("ItemMount/Item2")]
	for i in range(Model.PASS_CAPACITY):
		var meal := pass_items[i]
		meal.visible = i < model.pass_order_ids.size()
		if meal.visible:
			var food_id: int = model.pass_order_ids[i]
			meal.modulate = Model.RECIPES[model.orders[food_id].recipe].color if model.orders.has(food_id) else Color.WHITE
	stations.pass.caption.text = "出餐台 %d/%d" % [model.pass_order_ids.size(), Model.PASS_CAPACITY]
	for i in range(Model.TABLE_COUNT):
		var table = stations["table_%d" % (i + 1)]
		var order_id: int = model.tables[i]
		var order: Dictionary = model.orders.get(order_id, {})
		table.show_item(order.get("state", "") in ["eating", "leaving_paid", "dirty"], order.get("state", "") != "eating")
		table.item.modulate = Model.RECIPES[order.recipe].color if order.has("recipe") and order.state == "eating" else Color.WHITE
	if is_instance_valid(cooking_screen):
		var lines: Array[String] = []
		for i in range(Model.TABLE_COUNT):
			var id: int = model.tables[i]
			if id == 0 or not model.orders.has(id):
				lines.append("%02d 桌 · 空闲" % (i + 1))
			else:
				var order: Dictionary = model.orders[id]
				var state: String = {"arriving": "入店", "waiting": "待做", "cooking": "制作", "ready": "取餐", "carried": "上菜", "eating": "用餐", "leaving_paid": "离店", "leaving_lost": "流失", "dirty": "收盘", "clearing": "回收"}.get(order.state, "")
				lines.append("%02d 桌 · %s%s" % [i + 1, state, ("  剩 %d 秒" % ceili(model.patience_remaining(id))) if order.state in ["waiting", "cooking", "ready", "carried"] else ""])
		cooking_screen.labels.world.text = "餐厅继续营业
" + "
".join(lines)
	debug_label.text = "时间 %.1f / %.1f\n订单 %s\n在场 %d  污渍 %d\n选中 #%d  炉灶 %s  出餐 %s" % [model.elapsed, Model.DAY_SECONDS, str(model.orders), customers.size(), model.stains.size(), model.selected_order_id, str(model.cook_stations), str(model.pass_order_ids)]


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(cooking_screen) or model.phase == "summary": return
	if event.is_action_pressed("interact") and not event.is_echo() and model.phase == "open":
		try_interact(closest_target())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_order") and not event.is_echo() and model.phase == "open":
		var id := model.select_next()
		_show_feedback("已选中订单 #%d，%02d 号桌。" % [id, model.orders[id].table + 1] if id != 0 else "当前没有待做订单。")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("employee_menu") and not event.is_echo():
		_toggle_management()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_debug"):
		debug_visible = not debug_visible
		debug_label.visible = debug_visible
	elif debug_visible and event.is_action_pressed("debug_spawn"):
		model.request_customer()
	elif debug_visible and event.is_action_pressed("debug_reset"):
		_open_reset()


func closest_target() -> String:
	var result := ""
	var best := INTERACT_DISTANCE
	for id: String in stations:
		var distance: float = player.global_position.distance_to(stations[id].interaction_position())
		if distance < best:
			result = id
			best = distance
	return result


func target_position(id: String) -> Vector2:
	return stations[id].interaction_position()


func try_interact(id: String) -> bool:
	if is_instance_valid(cooking_screen) or model.phase != "open": return false
	if id == "" or not stations.has(id):
		_show_feedback("请靠近工作台、餐桌或污渍。")
		return false
	if player.global_position.distance_to(target_position(id)) >= INTERACT_DISTANCE:
		_show_feedback("距离太远了，请靠近目标。")
		return false
	var succeeded: bool = model.interact(id)
	if succeeded:
		player.direction = (stations[id].global_position - player.global_position).normalized()
	return succeeded


func reset_run() -> void:
	_clear_scene_day()
	model.new_game()
	employee.reset_new_game()
	preopen_panel.show()
	_show_feedback("新游戏已建立。准备第 1 天营业。")
	_refresh_ui()


func prepare_next_day() -> bool:
	if model.phase != "summary": return false
	_clear_scene_day()
	if not model.next_day(): return false
	employee.reset_day()
	preopen_panel.show()
	_show_feedback("第 %d 天准备就绪。" % model.day_number)
	_refresh_ui()
	return true


func start_day() -> bool:
	if not model.start_day(): return false
	preopen_panel.hide()
	store_panel.hide()
	management_panel.hide()
	player.locked = false
	_refresh_ui()
	return true


func _clear_scene_day() -> void:
	_close_cooking()
	for customer in customers.values():
		if is_instance_valid(customer): customer.free()
	customers.clear()
	for key: String in stain_nodes:
		stations.erase(key)
		if is_instance_valid(stain_nodes[key]): stain_nodes[key].queue_free()
	stain_nodes.clear()
	management_panel.hide()
	store_panel.hide()
	player.global_position = $PlayerStart.global_position
	player.velocity = Vector2.ZERO
	player.locked = true
	player.carried = 0
	summary_panel.hide()


func _setup_input() -> void:
	var bindings := {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN], "interact": [KEY_E, KEY_SPACE], "select_order": [KEY_Q], "employee_menu": [KEY_M], "pause_game": [KEY_ESCAPE], "toggle_debug": [KEY_F1], "debug_spawn": [KEY_N], "debug_reset": [KEY_R], "cook_heat": [KEY_SPACE], "cook_stir": [KEY_F], "cook_plate": [KEY_E], "cook_back": [KEY_B]}
	for action: String in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		for code: int in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			if not InputMap.action_has_event(action, event): InputMap.action_add_event(action, event)


func _build_room() -> void:
	actors = $World
	player = $World/Player
	var first_table = $World/Table
	var first_chair = $World/Chair
	first_table.position = TABLE_POSITIONS[0]
	first_chair.position = TABLE_POSITIONS[0] + Vector2(100, 0)
	for i in range(Model.TABLE_COUNT):
		var table = first_table if i == 0 else TableScene.instantiate()
		var chair = first_chair if i == 0 else ChairScene.instantiate()
		if i > 0:
			table.position = TABLE_POSITIONS[i]
			chair.position = TABLE_POSITIONS[i] + Vector2(100, 0)
			actors.add_child(table)
			actors.add_child(chair)
		table.station_id = "table_%d" % (i + 1)
		table.display_name = "%02d 号桌" % (i + 1)
		table.get_node("Caption").text = table.display_name
		stations[table.station_id] = table
	for id: String in ["stove", "pass", "sink"]:
		stations[id] = actors.get_node(id.capitalize())
	stations["stove_2"] = actors.get_node("Stove2")
	employee = EmployeeScene.instantiate()
	employee.position = Vector2(375, 570)
	employee.configure(model, stations)
	actors.add_child(employee)


func _spawn_customer(id: int, table_id: int) -> void:
	var customer = Customer.instantiate()
	var seat: Vector2 = stations["table_%d" % (table_id + 1)].get_node("Seat").global_position
	var route: Array[Vector2] = [Vector2(440, 420), Vector2(seat.x, 420)]
	customer.configure($Entrance.global_position, route, seat)
	customer.seated.connect(func(): model.seat_customer(id))
	customer.departed.connect(func():
		customers.erase(id)
		model.customer_departed(id))
	customers[id] = customer
	actors.add_child(customer)


func _spawn_browser(id: int) -> void:
	var customer = Customer.instantiate()
	customer.configure_browsing($Entrance.global_position, Vector2(575 + id % 3 * 42, 375))
	customer.seated.connect(func(): model.browser_arrived(id))
	customer.departed.connect(func():
		customers.erase(id)
		model.customer_departed(id))
	customers[id] = customer
	actors.add_child(customer)


func _leave_customer(id: int) -> void:
	if customers.has(id) and is_instance_valid(customers[id]): customers[id].leave()


func _sync_stains() -> void:
	var current: Dictionary = {}
	for stain_data in model.stains:
		var key: String = "stain_%d" % stain_data.id
		current[key] = true
		if not stain_nodes.has(key):
			var stain = StainScript.new()
			stain.station_id = key
			stain.position = STAIN_POSITIONS[stain_data.table] + Vector2((stain_data.id % 2) * 14, 0)
			actors.add_child(stain)
			stain_nodes[key] = stain
			stations[key] = stain
	for key: String in stain_nodes.keys():
		if not current.has(key):
			stations.erase(key)
			stain_nodes[key].queue_free()
			stain_nodes.erase(key)


func _open_cooking(id: int, attempt: int, recipe_id: String) -> void:
	player.locked = true
	player.velocity = Vector2.ZERO
	management_panel.hide()
	cooking_layer = CanvasLayer.new()
	cooking_layer.layer = 10
	cooking_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(cooking_layer)
	cooking_screen = CookingScreen.instantiate()
	cooking_screen.order_id = id
	cooking_screen.recipe_id = recipe_id
	cooking_screen.recipe_name = model.recipe_name(recipe_id)
	cooking_screen.recipe_speed = Model.RECIPES[recipe_id].speed
	cooking_screen.completed.connect(func(result: Dictionary):
		if not model.complete_cooking(id, attempt, result): model.cancel_cooking(id, attempt)
		_close_cooking())
	cooking_screen.abandoned.connect(func():
		model.cancel_cooking(id, attempt)
		_close_cooking())
	cooking_screen.pause_requested.connect(_toggle_pause)
	cooking_layer.add_child(cooking_screen)


func _expire_cooking(id: int) -> void:
	if is_instance_valid(cooking_screen) and cooking_screen.order_id == id:
		_close_cooking()
		_show_feedback("顾客等餐超时，本次烹饪已自动结束。")


func _close_cooking() -> void:
	if is_instance_valid(cooking_screen):
		cooking_screen.active = false
		cooking_screen.hide()
	if is_instance_valid(cooking_layer): cooking_layer.queue_free()
	cooking_screen = null
	cooking_layer = null
	if is_instance_valid(player): player.locked = false


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	ui.theme = theme
	layer.add_child(ui)
	var pause_input := Node.new()
	pause_input.set_script(preload("res://scripts/pause_input.gd"))
	pause_input.toggle_requested.connect(_toggle_pause)
	layer.add_child(pause_input)
	_panel(Rect2(0, 0, 1280, 166), Color("2d2119"))
	_label("title", "一人食堂 · 营业日", Vector2(28, 15), Vector2(280, 43), 27, CREAM)
	_label("coins", "0 金币", Vector2(310, 22), Vector2(160, 37), 23, GOLD)
	_label("served", "接待 0", Vector2(495, 28), Vector2(130, 29), 18, CREAM)
	_label("lost", "流失 0", Vector2(630, 28), Vector2(130, 29), 18, RED)
	_label("time", "营业 03:00", Vector2(780, 22), Vector2(220, 37), 23, GOLD)
	_label("clean", "整洁 100%", Vector2(1040, 28), Vector2(210, 30), 18, GREEN)
	_label("employee", "员工：待命", Vector2(29, 58), Vector2(900, 25), 14, GREEN)
	_button(ui, "M · 员工管理", Rect2(1044, 56, 208, 26), _toggle_management)
	for i in range(Model.TABLE_COUNT):
		var x := 26 + i * 312
		_panel(Rect2(x, 86, 296, 66), Color("493321"))
		var card := _label("card%d" % i, "%02d 号桌  ·  空闲" % (i + 1), Vector2(x + 13, 92), Vector2(272, 57), 16, CREAM)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		order_cards.append(card)
	_panel(Rect2(0, 701, 1280, 99), Color("2d2119"))
	_label("toast", toast, Vector2(32, 710), Vector2(1210, 28), 16, CREAM)
	prompt = _label("prompt", "", Vector2(32, 750), Vector2(810, 26), 15, GOLD)
	_label("controls", "WASD 移动  E 交互  Q 订单  M 员工  Esc 暂停", Vector2(802, 752), Vector2(457, 28), 14, MUTED)
	debug_label = _label("debug", "", Vector2(35, 370), Vector2(640, 260), 12, CREAM)
	debug_label.visible = false
	management_panel = _panel(Rect2(808, 177, 445, 402), Color("30291f"))
	management_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	management_panel.hide()
	_child_label(management_panel, "员工工作安排", Vector2(20, 15), Vector2(300, 42), 26, GOLD)
	_child_label(management_panel, "顺序越靠上越优先；调整后先完成手头任务。", Vector2(20, 57), Vector2(402, 32), 14, MUTED)
	_button(management_panel, "启用 / 休息", Rect2(20, 94, 170, 32), _toggle_employee)
	for i in range(4):
		var row_kind: String = ["serve", "clear", "cook", "clean"][i]
		var row_y := 139 + i * 57
		var row := _child_label(management_panel, "", Vector2(20, row_y), Vector2(200, 34), 18, CREAM)
		work_buttons["label_" + row_kind] = row
		var toggle := _make_button(management_panel, "开 / 关", Rect2(246, row_y, 80, 32), func(): _toggle_employee_work(row_kind))
		work_buttons["toggle_" + row_kind] = toggle
		var up_button := _make_button(management_panel, "↑ 优先", Rect2(336, row_y, 89, 32), func(): _move_employee_priority(row_kind))
		work_buttons["up_" + row_kind] = up_button
	_child_label(management_panel, "双炉灶可同时做菜；主角可接手员工尚未开始的任务。", Vector2(20, 370), Vector2(420, 24), 13, MUTED)
	preopen_panel = _panel(Rect2(325, 225, 630, 350), Color("30291f"))
	preopen_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_child_label(preopen_panel, "开店准备", Vector2(34, 24), Vector2(550, 48), 30, GOLD)
	preopen_text = _child_label(preopen_panel, "", Vector2(34, 86), Vector2(560, 120), 19, CREAM)
	_button(preopen_panel, "开始营业", Rect2(34, 220, 562, 48), start_day)
	_button(preopen_panel, "采购与菜单", Rect2(34, 286, 177, 38), _toggle_store)
	_button(preopen_panel, "员工安排 · M", Rect2(226, 286, 177, 38), _toggle_management)
	_button(preopen_panel, "开始新游戏", Rect2(418, 286, 178, 38), _open_reset)
	_build_store_panel()
	pause_panel = _panel(Rect2(425, 270, 430, 260), Color("38291f"))
	pause_panel.visible = false
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_child_label(pause_panel, "休息一下", Vector2(34, 26), Vector2(350, 48), 29, CREAM)
	_child_label(pause_panel, "营业时间与顾客耐心已暂停。", Vector2(34, 82), Vector2(360, 30), 16, MUTED)
	_button(pause_panel, "继续营业 · Esc", Rect2(34, 137, 362, 42), _toggle_pause)
	_button(pause_panel, "开始新游戏", Rect2(34, 192, 362, 38), _open_reset)
	summary_panel = _panel(Rect2(290, 176, 700, 440), Color("30291f"))
	summary_panel.hide()
	summary_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_child_label(summary_panel, "今日营业结算", Vector2(34, 23), Vector2(620, 48), 31, GOLD)
	summary_text = _child_label(summary_panel, "", Vector2(34, 94), Vector2(630, 255), 17, CREAM)
	_button(summary_panel, "准备下一营业日", Rect2(34, 364, 430, 50), prepare_next_day)
	_button(summary_panel, "新游戏", Rect2(480, 364, 186, 50), _open_reset)
	reset_dialog = ConfirmationDialog.new()
	reset_dialog.title = "开始新游戏"
	reset_dialog.dialog_text = "这会清空所有营业日的金币、账本和经营进度。确定开始新游戏吗？"
	reset_dialog.ok_button_text = "开始新游戏"
	reset_dialog.cancel_button_text = "返回"
	reset_dialog.min_size = Vector2i(450, 140)
	reset_dialog.confirmed.connect(func():
		reset_run()
		get_tree().paused = false
		pause_panel.hide())
	reset_dialog.canceled.connect(func(): get_tree().paused = pause_panel.visible)
	ui.add_child(reset_dialog)
	var modal_layer := CanvasLayer.new()
	modal_layer.layer = 30
	modal_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(modal_layer)
	var modal_root := Control.new()
	modal_root.theme = ui.theme
	modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(modal_root)
	pause_panel.reparent(modal_root)
	preopen_panel.reparent(modal_root)
	store_panel.reparent(modal_root)
	summary_panel.reparent(modal_root)
	reset_dialog.reparent(modal_root)


func _build_store_panel() -> void:
	store_panel = _panel(Rect2(190, 71, 900, 625), Color("30291f"))
	store_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	store_panel.hide()
	_child_label(store_panel, "食材采购与菜单", Vector2(30, 18), Vector2(660, 45), 28, GOLD)
	store_labels["overview"] = _child_label(store_panel, "", Vector2(30, 65), Vector2(820, 28), 16, CREAM)
	for i in range(Model.INGREDIENTS.size()):
		var ingredient: String = Model.INGREDIENTS.keys()[i]
		var y := 98 + i * 49
		store_labels["stock_" + ingredient] = _child_label(store_panel, "", Vector2(30, y), Vector2(395, 32), 17, CREAM)
		store_labels["minus_" + ingredient] = _make_button(store_panel, "−", Rect2(430, y, 40, 32), func(): _adjust_purchase(ingredient, -1))
		store_labels["quantity_" + ingredient] = _child_label(store_panel, "", Vector2(477, y), Vector2(48, 32), 17, CREAM)
		store_labels["plus_" + ingredient] = _make_button(store_panel, "+", Rect2(530, y, 40, 32), func(): _adjust_purchase(ingredient, 1))
		store_labels["subtotal_" + ingredient] = _child_label(store_panel, "", Vector2(584, y), Vector2(120, 32), 16, GOLD)
		store_labels["buy_" + ingredient] = _make_button(store_panel, "购买", Rect2(720, y, 135, 32), func(): _buy_ingredient(ingredient))
	_child_label(store_panel, "总菜谱 · 每份用料 / 今日定价", Vector2(30, 306), Vector2(550, 32), 22, GOLD)
	_child_label(store_panel, "价格越高，顾客愿意购买的概率越低。", Vector2(570, 312), Vector2(300, 26), 14, MUTED)
	for i in range(Model.RECIPE_IDS.size()):
		var recipe_id: String = Model.RECIPE_IDS[i]
		var y := 340 + i * 59
		store_labels["menu_" + recipe_id] = _child_label(store_panel, "", Vector2(30, y), Vector2(420, 26), 17, CREAM)
		store_labels["ingredients_" + recipe_id] = _child_label(store_panel, "", Vector2(30, y + 27), Vector2(430, 25), 15, MUTED)
		store_labels["price_minus_" + recipe_id] = _make_button(store_panel, "−", Rect2(459, y + 9, 40, 32), func(): _adjust_menu_price(recipe_id, -1))
		store_labels["price_" + recipe_id] = _child_label(store_panel, "", Vector2(510, y + 11), Vector2(100, 28), 17, GOLD)
		store_labels["price_plus_" + recipe_id] = _make_button(store_panel, "+", Rect2(614, y + 9, 40, 32), func(): _adjust_menu_price(recipe_id, 1))
		store_labels["toggle_" + recipe_id] = _make_button(store_panel, "", Rect2(710, y + 9, 145, 32), func(): _toggle_recipe(recipe_id))
	store_labels["emergency"] = _make_button(store_panel, "应急补给 · 1 份蛋饭食材", Rect2(30, 583, 400, 34), _claim_emergency)
	_button(store_panel, "返回开店准备", Rect2(596, 583, 259, 34), _toggle_store)


func _adjust_purchase(ingredient: String, amount: int) -> void:
	purchase_quantities[ingredient] = clampi(purchase_quantities[ingredient] + amount, 1, 20)
	_refresh_store_panel()


func _buy_ingredient(ingredient: String) -> void:
	model.purchase(ingredient, purchase_quantities[ingredient])
	_refresh_store_panel()


func _toggle_recipe(recipe_id: String) -> void:
	model.set_menu_enabled(recipe_id, not model.menu_enabled[recipe_id])
	_refresh_store_panel()


func _adjust_menu_price(recipe_id: String, amount: int) -> void:
	model.set_menu_price(recipe_id, model.menu_prices[recipe_id] + amount)
	_refresh_store_panel()


func _claim_emergency() -> void:
	if not model.claim_emergency_supply():
		_show_feedback("仅在没有可做的菜且买不起任何一份所缺食材时，每天可领取一次应急补给。")
	_refresh_store_panel()


func _toggle_store() -> void:
	if model.phase != "preopen": return
	store_panel.visible = not store_panel.visible
	if store_panel.visible: management_panel.hide()
	preopen_panel.visible = not store_panel.visible
	_refresh_store_panel()


func _refresh_store_panel() -> void:
	if store_labels.is_empty(): return
	store_labels.overview.text = "现金 %d 金币  ·  下方列出全部菜谱、每份原料及可制作数量" % model.coins
	for ingredient: String in Model.INGREDIENTS:
		var definition: Dictionary = Model.INGREDIENTS[ingredient]
		store_labels["stock_" + ingredient].text = "%s  单价 %d   库存 %d / 预留 %d / 可用 %d" % [definition.name, definition.price, model.inventory[ingredient], model.reserved_inventory[ingredient], model.ingredient_available(ingredient)]
		store_labels["quantity_" + ingredient].text = "×%d" % purchase_quantities[ingredient]
		store_labels["subtotal_" + ingredient].text = "合计 %d" % (definition.price * purchase_quantities[ingredient])
		store_labels["minus_" + ingredient].disabled = purchase_quantities[ingredient] <= 1
		store_labels["plus_" + ingredient].disabled = purchase_quantities[ingredient] >= 20
		store_labels["buy_" + ingredient].disabled = definition.price * purchase_quantities[ingredient] > model.coins
	for recipe_id: String in Model.RECIPE_IDS:
		store_labels["menu_" + recipe_id].text = "%s  ·  建议 %d  ·  可做 %d 份" % [model.recipe_name(recipe_id), Model.RECIPES[recipe_id].price, model.portions_available(recipe_id)]
		store_labels["ingredients_" + recipe_id].text = "每份：" + model.recipe_ingredients_text(recipe_id)
		store_labels["price_" + recipe_id].text = "%d 金币" % model.menu_prices[recipe_id]
		store_labels["price_minus_" + recipe_id].disabled = model.menu_prices[recipe_id] <= 1
		store_labels["price_plus_" + recipe_id].disabled = model.menu_prices[recipe_id] >= 99
		store_labels["toggle_" + recipe_id].text = "在售" if model.menu_enabled[recipe_id] else "已停售"
	store_labels.emergency.disabled = not model.emergency_available()


func _refresh_ui() -> void:
	if labels.is_empty(): return
	_refresh_store_panel()
	if model.phase == "summary" and summary_panel != null and summary_panel.visible:
		summary_text.text = _format_summary(model.summary())
	labels.title.text = "一人食堂 · 第 %d 天" % model.day_number
	labels.coins.text = "%d 金币" % model.coins
	labels.served.text = "接待 %d" % model.served
	labels.lost.text = "流失 %d" % model.lost
	var remaining: int = maxi(0, ceili(Model.DAY_SECONDS - model.elapsed))
	if model.phase == "preopen": labels.time.text = "开店准备"
	elif model.phase == "summary": labels.time.text = "今日结算"
	else: labels.time.text = ("收尾 %02d:%02d" % [maxi(0, ceili(Model.DAY_SECONDS + Model.CLOSING_GRACE - model.elapsed)) / 60, maxi(0, ceili(Model.DAY_SECONDS + Model.CLOSING_GRACE - model.elapsed)) % 60]) if model.day_closed else ("营业 %02d:%02d" % [remaining / 60, remaining % 60])
	if preopen_text != null:
		preopen_text.text = "第 %d 天  ·  当前现金 %d 金币\n当前有 %d 道菜谱，可查看每份用料并调整售价。\n\n开店前采购食材、调整菜单；准备好后开始营业。" % [model.day_number, model.coins, Model.RECIPE_IDS.size()]
	labels.clean.text = "整洁 %d%%" % [roundi((1.0 - float(model.stains.size()) / Model.STAIN_LIMIT) * 100)]
	labels.clean.add_theme_color_override("font_color", GREEN if model.stains.size() <= 1 else RED)
	labels.employee.text = "员工：%s%s" % [employee.status, (" · %s" % employee.failure_reason) if employee.failure_reason != "" and employee.failure_reason != employee.status else ""]
	for i in range(Model.TABLE_COUNT):
		var id: int = model.tables[i]
		var card := order_cards[i]
		if id == 0 or not model.orders.has(id):
			card.text = "%02d 号桌  ·  空闲" % (i + 1)
			card.add_theme_color_override("font_color", MUTED)
			continue
		var order: Dictionary = model.orders[id]
		var status: String = {"arriving": "入店中", "waiting": "待制作", "cooking": "制作中", "ready": "待取餐", "carried": "待上菜", "eating": "用餐中", "leaving_paid": "已付款", "leaving_lost": "超时离开", "dirty": "待收盘", "clearing": "待回收"}.get(order.state, order.state)
		var urgent: bool = order.state in ["waiting", "cooking", "ready", "carried"] and model.patience_remaining(id) <= 12.0
		var selected := "▶ " if model.selected_order_id == id and order.state == "waiting" else ""
		var detail := ("剩 %d 秒%s" % [ceili(model.patience_remaining(id)), (" · 满意 %d" % order.satisfaction) if order.choice_rank > 0 else ""]) if order.state in ["waiting", "cooking", "ready", "carried"] else (("满意 %d" % order.satisfaction) if order.choice_rank > 0 else "")
		card.text = "%s%02d 号桌 · %s\n%s  %s" % [selected, i + 1, status, model.recipe_name(order.recipe), detail]
		card.add_theme_color_override("font_color", RED if urgent else (GOLD if selected != "" else CREAM))


func _show_summary(result: Dictionary) -> void:
	_close_cooking()
	summary_text.text = _format_summary(result)
	management_panel.hide()
	summary_panel.show()


func _format_summary(result: Dictionary) -> String:
	var expenses: Dictionary = result.expenses
	var spending: int = expenses.purchase + expenses.wages + expenses.furniture + expenses.equipment + expenses.expansion
	return "第 %d 天  日初 %d  +营业 %d  -支出 %d  =日末 %d\n现金变化 %+d · 食材消耗成本 %d · 估算经营收益 %d\n采购 %d · 工资 %d · 家具 %d · 设备 %d · 扩建 %d\n完成 %d 桌 · 流失 %d 位（未购买 %d）· 好评 %d · 差评 %d\n平均等餐 %.1f 秒 · 剩余污渍 %d\n员工完成：做菜 %d · 上菜 %d · 收盘 %d · 清洁 %d\n%s" % [result.day, result.opening_cash, result.income, spending, result.coins, result.cash_change, result.ingredient_cost, result.operating_profit, expenses.purchase, expenses.wages, expenses.furniture, expenses.equipment, expenses.expansion, result.served, result.lost, result.no_sale, result.good_reviews, result.bad_reviews, result.average_wait, result.stains, employee.tasks_completed.cook, employee.tasks_completed.serve, employee.tasks_completed.clear, employee.tasks_completed.clean, ("%d 位顾客未完成消费。" % result.lost) if result.lost > 0 else "今日营业已完成。"]


func _toggle_pause() -> void:
	if reset_dialog.visible or model.phase != "open": return
	get_tree().paused = not get_tree().paused
	management_panel.hide()
	if is_instance_valid(cooking_screen): cooking_screen.clear_heat()
	pause_panel.visible = get_tree().paused


func _open_reset() -> void:
	if is_instance_valid(cooking_screen): cooking_screen.clear_heat()
	get_tree().paused = true
	reset_dialog.popup_centered()


func _toggle_management() -> void:
	if model.phase == "summary" or is_instance_valid(cooking_screen): return
	management_panel.visible = not management_panel.visible
	if management_panel.visible: store_panel.hide()
	if model.phase == "preopen": preopen_panel.visible = not management_panel.visible
	_refresh_employee_panel()


func _toggle_employee() -> void:
	employee.enabled = not employee.enabled
	_refresh_employee_panel()


func _toggle_employee_work(kind: String) -> void:
	employee.toggle_work(kind)
	_refresh_employee_panel()


func _move_employee_priority(kind: String) -> void:
	employee.move_priority_up(kind)
	_refresh_employee_panel()


func _refresh_employee_panel() -> void:
	if management_panel == null: return
	for i in range(employee.priority.size()):
		var kind: String = employee.priority[i]
		var row_y := 139 + i * 57
		work_buttons["label_" + kind].position.y = row_y
		work_buttons["toggle_" + kind].position.y = row_y
		work_buttons["up_" + kind].position.y = row_y
		work_buttons["label_" + kind].text = "%d  %s" % [i + 1, employee.WORK_LABELS[kind]]
		work_buttons["toggle_" + kind].text = "开启" if employee.work_enabled[kind] else "关闭"
		work_buttons["up_" + kind].disabled = i == 0


func _show_feedback(message: String) -> void:
	toast = message
	toast_time = 6.0


func _next_step() -> String:
	if model.phase == "preopen": return "开店前可查看员工安排；点击开始营业后才会接待顾客。"
	if model.phase == "summary": return "查看收入与支出，然后准备下一营业日。"
	if model.day_closed: return "已停止接客，请完成当前工作；收尾结束后自动日结。"
	if model.pass_order_id != 0: return "出餐台有一份菜，优先取餐上菜。"
	if model.most_urgent_waiting() != 0: return "有顾客正在等餐。Q 可切换目标订单。"
	if not model.stains.is_empty(): return "地面有污渍，靠近按 E 清洁。"
	return "留意四张桌子的状态，合理安排做菜、上菜与清洁。"


func _action_hint(id: String) -> String:
	if id in Model.STOVES: return "制作选中订单"
	if id == "pass": return "取餐 / 放回"
	if id == "sink": return "回收餐盘"
	if id.begins_with("table_"):
		return "上菜 / 收盘"
	if id.begins_with("stain_"): return "清洁"
	return "交互"


func _panel(rect: Rect2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)
	return panel


func _label(key: String, value: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := _child_label(ui, value, at, dimensions, font_size, color)
	labels[key] = label
	return label


func _child_label(parent: Node, value: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Node, value: String, rect: Rect2, callback: Callable) -> void:
	_make_button(parent, value, rect, callback)


func _make_button(parent: Node, value: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.position = rect.position
	button.size = rect.size
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
