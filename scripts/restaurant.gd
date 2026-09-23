extends Node2D

const Model = preload("res://scripts/day_model.gd")
const Customer = preload("res://scenes/actors/customer.tscn")
const TableScene = preload("res://scenes/furniture/table.tscn")
const ChairScene = preload("res://scenes/furniture/chair.tscn")
const CookingScreen = preload("res://scenes/cooking/cooking_screen.tscn")
const StainScript = preload("res://scripts/stain.gd")
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
var summary_panel: Panel
var summary_text: Label
var reset_dialog: ConfirmationDialog
var debug_label: Label
var debug_visible := false
var toast := "欢迎开店！先看上方四张桌子的订单。"
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
	model.customer_requested.connect(_spawn_customer)
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
	player.locked = is_instance_valid(cooking_screen) or model.ended
	player.carried = model.carrying
	if model.carrying == Model.Carry.FOOD and model.orders.has(model.carried_order_id):
		player.avatar.held.modulate = Model.RECIPES[model.orders[model.carried_order_id].recipe].color
	else:
		player.avatar.held.modulate = Color.WHITE
	_sync_stains()
	_refresh_ui()
	nearest = closest_target()
	prompt.text = "[ E ] %s · %s" % [stations[nearest].display_name, _action_hint(nearest)] if nearest != "" else "靠近工作台、餐桌或污渍按 E 交互；Q 切换待做订单"
	labels.toast.text = toast if toast_time > 0.0 else _next_step()
	for id: String in stations:
		stations[id].set_highlight(id == nearest)
	stations.pass.show_item(model.pass_order_id != 0)
	stations.pass.item.modulate = Model.RECIPES[model.orders[model.pass_order_id].recipe].color if model.pass_order_id != 0 and model.orders.has(model.pass_order_id) else Color.WHITE
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
	debug_label.text = "时间 %.1f / %.1f\n订单 %s\n在场 %d  污渍 %d\n选中 #%d  炉灶 #%d  出餐 #%d" % [model.elapsed, Model.DAY_SECONDS, str(model.orders), customers.size(), model.stains.size(), model.selected_order_id, model.cooking_order_id, model.pass_order_id]


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(cooking_screen) or model.ended: return
	if event.is_action_pressed("interact") and not event.is_echo():
		try_interact(closest_target())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_order") and not event.is_echo():
		var id := model.select_next()
		_show_feedback("已选中订单 #%d，%02d 号桌。" % [id, model.orders[id].table + 1] if id != 0 else "当前没有待做订单。")
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
	if is_instance_valid(cooking_screen) or model.ended: return false
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
	_close_cooking()
	for customer in customers.values():
		if is_instance_valid(customer): customer.free()
	customers.clear()
	for key: String in stain_nodes:
		stations.erase(key)
		if is_instance_valid(stain_nodes[key]): stain_nodes[key].queue_free()
	stain_nodes.clear()
	model.reset()
	player.global_position = $PlayerStart.global_position
	player.velocity = Vector2.ZERO
	player.locked = false
	player.carried = 0
	summary_panel.hide()
	_show_feedback("新营业日开始！")
	_refresh_ui()


func _setup_input() -> void:
	var bindings := {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN], "interact": [KEY_E, KEY_SPACE], "select_order": [KEY_Q], "pause_game": [KEY_ESCAPE], "toggle_debug": [KEY_F1], "debug_spawn": [KEY_N], "debug_reset": [KEY_R], "cook_heat": [KEY_SPACE], "cook_stir": [KEY_F], "cook_plate": [KEY_E], "cook_back": [KEY_B]}
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


func _expire_cooking(_id: int) -> void:
	if is_instance_valid(cooking_screen):
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
	for i in range(Model.TABLE_COUNT):
		var x := 26 + i * 312
		_panel(Rect2(x, 86, 296, 66), Color("493321"))
		var card := _label("card%d" % i, "%02d 号桌  ·  空闲" % (i + 1), Vector2(x + 13, 92), Vector2(272, 57), 16, CREAM)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		order_cards.append(card)
	_panel(Rect2(0, 701, 1280, 99), Color("2d2119"))
	_label("toast", toast, Vector2(32, 710), Vector2(1210, 28), 16, CREAM)
	prompt = _label("prompt", "", Vector2(32, 750), Vector2(810, 26), 15, GOLD)
	_label("controls", "WASD 移动  E 交互  Q 切换订单  Esc 暂停", Vector2(837, 752), Vector2(420, 28), 14, MUTED)
	debug_label = _label("debug", "", Vector2(35, 370), Vector2(640, 260), 12, CREAM)
	debug_label.visible = false
	pause_panel = _panel(Rect2(425, 270, 430, 260), Color("38291f"))
	pause_panel.visible = false
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_child_label(pause_panel, "休息一下", Vector2(34, 26), Vector2(350, 48), 29, CREAM)
	_child_label(pause_panel, "营业时间与顾客耐心已暂停。", Vector2(34, 82), Vector2(360, 30), 16, MUTED)
	_button(pause_panel, "继续营业 · Esc", Rect2(34, 137, 362, 42), _toggle_pause)
	_button(pause_panel, "重新开店", Rect2(34, 192, 362, 38), _open_reset)
	summary_panel = _panel(Rect2(290, 176, 700, 440), Color("30291f"))
	summary_panel.hide()
	summary_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_child_label(summary_panel, "今日营业结算", Vector2(34, 23), Vector2(620, 48), 31, GOLD)
	summary_text = _child_label(summary_panel, "", Vector2(34, 94), Vector2(630, 250), 18, CREAM)
	_button(summary_panel, "开始新营业日", Rect2(34, 364, 632, 50), reset_run)
	reset_dialog = ConfirmationDialog.new()
	reset_dialog.title = "重新开店"
	reset_dialog.dialog_text = "将清空本营业日的金币、订单和评价记录，确定重新开始吗？"
	reset_dialog.ok_button_text = "重新开始"
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
	summary_panel.reparent(modal_root)
	reset_dialog.reparent(modal_root)


func _refresh_ui() -> void:
	if labels.is_empty(): return
	labels.coins.text = "%d 金币" % model.coins
	labels.served.text = "接待 %d" % model.served
	labels.lost.text = "流失 %d" % model.lost
	var remaining: int = maxi(0, ceili(Model.DAY_SECONDS - model.elapsed))
	labels.time.text = ("收尾 %02d:%02d" % [maxi(0, ceili(Model.DAY_SECONDS + Model.CLOSING_GRACE - model.elapsed)) / 60, maxi(0, ceili(Model.DAY_SECONDS + Model.CLOSING_GRACE - model.elapsed)) % 60]) if model.day_closed else ("营业 %02d:%02d" % [remaining / 60, remaining % 60])
	labels.clean.text = "整洁 %d%%" % [roundi((1.0 - float(model.stains.size()) / Model.STAIN_LIMIT) * 100)]
	labels.clean.add_theme_color_override("font_color", GREEN if model.stains.size() <= 1 else RED)
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
		card.text = "%s%02d 号桌 · %s\n%s  %s" % [selected, i + 1, status, model.recipe_name(order.recipe), ("剩 %d 秒 !" % ceili(model.patience_remaining(id))) if order.state in ["waiting", "cooking", "ready", "carried"] else ""]
		card.add_theme_color_override("font_color", RED if urgent else (GOLD if selected != "" else CREAM))


func _show_summary(result: Dictionary) -> void:
	_close_cooking()
	summary_text.text = "收入  %d 金币       完成  %d 桌       流失  %d 位\n\n好评  %d       差评  %d       剩余污渍  %d\n平均等餐 %.1f 秒\n\n%s\n\n%s" % [result.coins, result.served, result.lost, result.good_reviews, result.bad_reviews, result.stains, result.average_wait, ("%d 位顾客因等餐超时离店。" % result.lost) if result.lost > 0 else "全部顾客都获得服务。", "收尾时间已到；可以开始新的一天。" if result.elapsed >= Model.DAY_SECONDS + Model.CLOSING_GRACE else "今日营业已完成。"]
	summary_panel.show()


func _toggle_pause() -> void:
	if reset_dialog.visible or model.ended: return
	get_tree().paused = not get_tree().paused
	if is_instance_valid(cooking_screen): cooking_screen.clear_heat()
	pause_panel.visible = get_tree().paused


func _open_reset() -> void:
	if is_instance_valid(cooking_screen): cooking_screen.clear_heat()
	get_tree().paused = true
	reset_dialog.popup_centered()


func _show_feedback(message: String) -> void:
	toast = message
	toast_time = 6.0


func _next_step() -> String:
	if model.day_closed: return "已停止接客，请完成当前工作；收尾结束后自动日结。"
	if model.pass_order_id != 0: return "出餐台有一份菜，优先取餐上菜。"
	if model.most_urgent_waiting() != 0: return "有顾客正在等餐。Q 可切换目标订单。"
	if not model.stains.is_empty(): return "地面有污渍，靠近按 E 清洁。"
	return "留意四张桌子的状态，合理安排做菜、上菜与清洁。"


func _action_hint(id: String) -> String:
	if id == "stove": return "制作选中订单"
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
	var button := Button.new()
	button.text = value
	button.position = rect.position
	button.size = rect.size
	button.pressed.connect(callback)
	parent.add_child(button)
