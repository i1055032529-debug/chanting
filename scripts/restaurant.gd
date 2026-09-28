extends Node2D

const Model = preload("res://scripts/day_model.gd")
const Customer = preload("res://scenes/actors/customer.tscn")
const TableScene = preload("res://scenes/furniture/table.tscn")
const ChairScene = preload("res://scenes/furniture/chair.tscn")
const StoveScene = preload("res://scenes/furniture/stove.tscn")
const PassScene = preload("res://scenes/furniture/pass.tscn")
const SinkScene = preload("res://scenes/furniture/sink.tscn")
const CookingScreen = preload("res://scenes/cooking/cooking_screen.tscn")
const StainScript = preload("res://scripts/stain.gd")
const EmployeeScene = preload("res://scenes/actors/employee.tscn")
const Layout = preload("res://scripts/layout_rules.gd")
const DISH_SHEET = preload("res://assets/recipes/dishes.png")
const STAFF_SHEET = preload("res://assets/characters/chef.png")
const WOOD_BOARD = preload("res://assets/ui/wood_board.png")
const WALL_RECORD = preload("res://assets/ui/wall_record.png")
const INTERACT_DISTANCE := 55.0
const DESK_DISTANCE := 95.0
const MENU_DESK := Vector2(108, 320)
const STAFF_DESK := Vector2(224, 320)
const CREAM := Color("f4e5cd")
const MUTED := Color("bea993")
const GOLD := Color("edbc72")
const RED := Color("e59172")
const GREEN := Color("91bf8b")

var model := Model.new()
var player: CharacterBody2D
var employee: Node2D
var employees: Array[Node2D] = []
var selected_employee_index := 0
var actors: Node2D
var customers: Dictionary = {}
var stations: Dictionary = {}
var table_nodes: Array[Node2D] = []
var chair_nodes: Array[Node2D] = []
var order_card_panels: Array[Panel] = []
var stain_nodes: Dictionary = {}
var font: SystemFont
var ui: Control
var labels: Dictionary = {}
var order_cards: Array[Label] = []
var order_list_scroll: ScrollContainer
var order_list_items: VBoxContainer
var prompt: Label
var pause_panel: Panel
var preopen_panel: Panel
var preopen_text: Label
var store_panel: Panel
var store_labels: Dictionary = {}
var purchase_quantities := {"rice": 1, "egg": 1, "noodles": 1, "tomato": 1}
var recipe_target_portions := 3
var selected_recipe := ""
var store_grid: ScrollContainer
var store_cards: GridContainer
var store_detail: Control
var menu_access_button: Button
var staff_access_button: Button
var preopen_access_button: Button
var summary_panel: Panel
var summary_text: Label
var management_panel: Panel
var management_list_page: Control
var management_detail_page: Control
var management_hire_page: Control
var staff_list_scroll: ScrollContainer
var staff_list_items: VBoxContainer
var hire_list_scroll: ScrollContainer
var hire_list_items: VBoxContainer
var management_page := "list"
var selected_staff_id := ""
var staff_settings_by_id: Dictionary = {}
var staff_detail_name: Label
var staff_detail_bio: Label
var staff_detail_cost: Label
var staff_detail_avatar: Sprite2D
var layout_panel: Panel
var layout_labels: Dictionary = {}
var layout_selected := 0
var layout_editing := false
var layout_new_table := false
var layout_preview_position := Vector2.ZERO
var layout_preview_table: Node2D
var layout_preview_chair: Node2D
var camera_focus := Vector2(640, 400)
var expansion_panel: Panel
var expansion_labels: Dictionary = {}
var hire_button: Button
var select_previous_button: Button
var select_next_button: Button
var management_title: Label
var management_status: Label
var employment_label: Label
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
	_apply_staff_roster_settings()
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
	_refresh_employee_presence()
	_refresh_ui()


func _process(delta: float) -> void:
	$Camera.position = Vector2(maxf(player.position.x, 640.0), maxf(player.position.y, 400.0)) if model.phase == "open" else camera_focus
	toast_time = maxf(0.0, toast_time - delta)
	model.advance(delta)
	player.locked = is_instance_valid(cooking_screen) or model.phase == "summary" or preopen_panel.visible or store_panel.visible or management_panel.visible or layout_panel.visible or expansion_panel.visible
	if model.phase == "preopen" and not layout_panel.visible and not expansion_panel.visible and not preopen_panel.visible:
		camera_focus = Vector2(maxf(player.position.x, 640.0), maxf(player.position.y, 400.0))
	menu_access_button.disabled = player.global_position.distance_to(MENU_DESK) > DESK_DISTANCE or model.phase == "summary"
	staff_access_button.disabled = player.global_position.distance_to(STAFF_DESK) > DESK_DISTANCE or model.phase == "summary"
	preopen_access_button.visible = model.phase == "preopen"
	player.carried = model.carrying
	if model.carrying == Model.Carry.FOOD and model.orders.has(model.carried_order_id):
		player.avatar.held.modulate = Model.RECIPES[model.orders[model.carried_order_id].recipe].color
	else:
		player.avatar.held.modulate = Color.WHITE
	_sync_stains()
	_refresh_ui()
	_refresh_employee_panel()
	nearest = closest_target() if model.phase == "open" else ""
	prompt.text = "[ E ] %s · %s" % [stations[nearest].display_name, _action_hint(nearest)] if nearest != "" else ("走到左上角，点击墙上的菜谱或雇佣记录；准备好后开店。" if model.phase == "preopen" else "查看今日结算，准备下一天。" if model.phase == "summary" else "点击左上角墙面记录；靠近工作台、餐桌或污渍按 E 交互，Q 切换订单。")
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
	for i in range(model.table_count()):
		var table = stations["table_%d" % (i + 1)]
		var order_id: int = model.tables[i]
		var order: Dictionary = model.orders.get(order_id, {})
		table.show_item(order.get("state", "") in ["eating", "leaving_paid", "dirty"], order.get("state", "") != "eating")
		table.item.modulate = Model.RECIPES[order.recipe].color if order.has("recipe") and order.state == "eating" else Color.WHITE
	if is_instance_valid(cooking_screen):
		var lines: Array[String] = []
		for i in range(model.table_count()):
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
	if model.phase == "preopen" and expansion_panel.visible and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.position.y > 166.0 and event.position.y < 700.0 and not expansion_panel.get_global_rect().has_point(event.position):
			_click_expansion(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		return
	if model.phase == "preopen" and layout_panel.visible and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.position.x > 320.0 and event.position.y > 300.0 and event.position.y < 700.0:
			if layout_editing:
				var world_position := get_global_mouse_position()
				layout_preview_position = Vector2(roundi(world_position.x / 10.0) * 10, roundi(world_position.y / 10.0) * 10)
				_refresh_layout_preview()
			else: _select_layout_at(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and not event.is_echo() and model.phase == "open":
		try_interact(closest_target())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_order") and not event.is_echo() and model.phase == "open":
		var id := model.select_next()
		if id != 0:
			var table_index: int = model.orders[id].table
			if table_index < order_card_panels.size(): order_list_scroll.ensure_control_visible(order_card_panels[table_index])
			_refresh_ui()
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
	get_tree().paused = false
	_cancel_layout_preview()
	if layout_panel != null: layout_panel.hide()
	if expansion_panel != null: expansion_panel.hide()
	$Background.set_expansion_preview(false)
	_clear_scene_day()
	model.new_game()
	$Background.set_expansion(model.expansion_cells)
	camera_focus = Vector2(640, 400)
	_sync_layout_nodes()
	for worker in employees: worker.reset_new_game()
	staff_settings_by_id.clear()
	_apply_staff_roster_settings()
	selected_employee_index = 0
	selected_staff_id = ""
	preopen_panel.show()
	_refresh_employee_presence()
	_show_feedback("新游戏已建立。准备第 1 天营业。")
	_refresh_ui()


func prepare_next_day() -> bool:
	if model.phase != "summary": return false
	_snapshot_staff_settings()
	_clear_scene_day()
	if not model.next_day(): return false
	for worker in employees: worker.reset_new_game()
	_apply_staff_roster_settings()
	selected_staff_id = ""
	selected_employee_index = mini(selected_employee_index, maxi(0, model.employee_hired_count - 1))
	preopen_panel.show()
	_refresh_employee_presence()
	_show_feedback("第 %d 天准备就绪。" % model.day_number)
	_refresh_ui()
	return true


func start_day() -> bool:
	if layout_editing: return false
	if not model.start_day(): return false
	preopen_panel.hide()
	store_panel.hide()
	management_panel.hide()
	layout_panel.hide()
	expansion_panel.hide()
	$Background.set_expansion_preview(false)
	_refresh_employee_presence()
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
	$Background.set_expansion(model.expansion_cells)
	actors = $World
	player = $World/Player
	var first_table = $World/Table
	var first_chair = $World/Chair
	table_nodes.append(first_table)
	chair_nodes.append(first_chair)
	for id: String in ["stove", "pass", "sink"]:
		stations[id] = actors.get_node(id.capitalize())
	stations["stove_2"] = actors.get_node("Stove2")
	_sync_layout_nodes()
	for i in range(Model.MAX_EMPLOYEES):
		var worker = EmployeeScene.instantiate()
		var home := Vector2(375 + i * 30, 570)
		worker.position = home
		worker.configure(model, stations, Model.WORKER_IDS[i], home)
		actors.add_child(worker)
		employees.append(worker)
	employee = employees[0]


func _sync_layout_nodes() -> void:
	for id in Model.DEVICE_IDS:
		stations[id].position = model.device_positions[id]
		stations[id].visible = true
	while table_nodes.size() > model.table_count():
		var old_index := table_nodes.size() - 1
		stations.erase("table_%d" % (old_index + 1))
		table_nodes.pop_back().queue_free()
		chair_nodes.pop_back().queue_free()
	while table_nodes.size() < model.table_count():
		var table = TableScene.instantiate()
		var chair = ChairScene.instantiate()
		actors.add_child(table)
		actors.add_child(chair)
		table_nodes.append(table)
		chair_nodes.append(chair)
	for i in range(model.table_count()):
		var table = table_nodes[i]
		var chair = chair_nodes[i]
		table.position = model.table_positions[i]
		chair.position = model.table_positions[i] + Vector2(100, 0)
		table.station_id = "table_%d" % (i + 1)
		table.display_name = "%02d 号桌" % (i + 1)
		table.get_node("Caption").text = table.display_name
		table.visible = true
		chair.visible = true
		stations[table.station_id] = table
	_layout_order_cards()
	for worker in employees: worker.grid = null


func _layout_order_cards() -> void:
	if order_list_items == null: return
	while order_cards.size() < model.table_count():
		var card := Panel.new()
		card.custom_minimum_size = Vector2(224, 80)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		order_list_items.add_child(card)
		var board := TextureRect.new()
		board.texture = WOOD_BOARD
		board.position = Vector2.ZERO
		board.size = Vector2(224, 80)
		board.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		board.stretch_mode = TextureRect.STRETCH_SCALE
		board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		board.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(board)
		var label := _child_label(card, "", Vector2(13, 11), Vector2(197, 61), 14, CREAM)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		order_card_panels.append(card)
		order_cards.append(label)
	while order_cards.size() > model.table_count():
		order_cards.pop_back()
		var old_card: Panel = order_card_panels.pop_back()
		order_list_items.remove_child(old_card)
		old_card.queue_free()


func _spawn_customer(id: int, table_id: int) -> void:
	var customer = Customer.instantiate()
	var seat: Vector2 = stations["table_%d" % (table_id + 1)].get_node("Seat").global_position
	var route: Array[Vector2] = Layout.customer_route(model.table_positions, seat + Vector2(0, 30), model.device_positions, model.expansion_cells)
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
			var table_position: Vector2 = model.table_positions[stain_data.table]
			stain.position = table_position + Vector2(-75 + (stain_data.id % 2) * 14, 55 if table_position.y > 510 else 72)
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
	cooking_screen.recipe_speed = Model.RECIPES[recipe_id].speed * model.cooking_speed_multiplier()
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
	pause_input.employee_menu_requested.connect(_request_management)
	layer.add_child(pause_input)
	menu_access_button = _wall_record_button("菜谱\n记录", Rect2(48, 207, 112, 64), _request_store)
	staff_access_button = _wall_record_button("雇佣\n记录", Rect2(164, 207, 112, 64), _request_management)
	var coin_board := TextureRect.new()
	coin_board.texture = WOOD_BOARD
	coin_board.position = Vector2(1028, 18)
	coin_board.size = Vector2(224, 72)
	coin_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ui.add_child(coin_board)
	labels.coins = _child_label(coin_board, "1000 金币", Vector2(14, 16), Vector2(196, 40), 25, GOLD)
	labels.coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_child_label(ui, "桌位记录", Vector2(1037, 138), Vector2(190, 30), 19, GOLD)
	order_list_scroll = ScrollContainer.new()
	order_list_scroll.position = Vector2(1018, 174)
	order_list_scroll.size = Vector2(246, 523)
	order_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.add_child(order_list_scroll)
	order_list_items = VBoxContainer.new()
	order_list_items.custom_minimum_size.x = 224
	order_list_items.add_theme_constant_override("separation", 6)
	order_list_scroll.add_child(order_list_items)
	_layout_order_cards()
	_panel(Rect2(0, 700, 1280, 100), Color("2d2119"))
	labels.capacity = _child_label(ui, "", Vector2(25, 706), Vector2(1230, 22), 13, CREAM)
	labels.employee = _child_label(ui, "", Vector2(25, 729), Vector2(1230, 22), 13, GREEN)
	labels.toast = _child_label(ui, toast, Vector2(25, 750), Vector2(1230, 22), 14, CREAM)
	prompt = _child_label(ui, "", Vector2(25, 773), Vector2(1230, 22), 14, GOLD)
	preopen_access_button = _make_button(ui, "开店准备", Rect2(880, 660, 118, 34), _toggle_preopen)
	debug_label = _label("debug", "", Vector2(35, 370), Vector2(640, 260), 12, CREAM)
	debug_label.visible = false
	management_panel = _panel(Rect2(700, 167, 555, 515), Color("30291f"))
	management_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	management_panel.hide()
	management_title = _child_label(management_panel, "员工管理", Vector2(20, 13), Vector2(350, 42), 26, GOLD)
	_make_button(management_panel, "关闭", Rect2(449, 17, 86, 32), _toggle_management)
	employment_label = _child_label(management_panel, "", Vector2(20, 57), Vector2(510, 28), 15, CREAM)
	management_list_page = _management_page_root()
	hire_button = _make_button(management_list_page, "＋", Rect2(459, 3, 72, 36), _show_hire_page)
	_child_label(management_list_page, "已雇佣员工（点击卡片查看详情）", Vector2(20, 7), Vector2(400, 28), 17, GOLD)
	staff_list_scroll = _staff_scroll(management_list_page, Vector2(20, 49), Vector2(515, 325))
	staff_list_items = _staff_list_contents(staff_list_scroll)
	_child_label(management_list_page, "雇佣与解除次日生效；今日出勤和工资不变。", Vector2(20, 385), Vector2(515, 28), 14, MUTED)
	management_hire_page = _management_page_root()
	_make_button(management_hire_page, "← 返回", Rect2(20, 4, 105, 34), _show_management_list)
	_child_label(management_hire_page, "可雇佣员工 · 日薪均为 18 金币", Vector2(145, 8), Vector2(385, 27), 17, GOLD)
	hire_list_scroll = _staff_scroll(management_hire_page, Vector2(20, 49), Vector2(515, 325))
	hire_list_items = _staff_list_contents(hire_list_scroll)
	_child_label(management_hire_page, "点击员工卡片预约雇佣；最多同时雇佣 5 人。", Vector2(20, 385), Vector2(515, 28), 14, MUTED)
	management_detail_page = _management_page_root()
	_make_button(management_detail_page, "← 返回列表", Rect2(20, 3, 130, 34), _show_management_list)
	select_previous_button = _make_button(management_detail_page, "←", Rect2(439, 44, 43, 31), func(): _select_employee(-1))
	select_next_button = _make_button(management_detail_page, "→", Rect2(490, 44, 43, 31), func(): _select_employee(1))
	staff_detail_avatar = _staff_avatar("lin", Vector2(24, 46), 0.88)
	management_detail_page.add_child(staff_detail_avatar)
	staff_detail_name = _child_label(management_detail_page, "", Vector2(105, 48), Vector2(320, 34), 23, GOLD)
	staff_detail_bio = _child_label(management_detail_page, "", Vector2(105, 84), Vector2(400, 28), 15, CREAM)
	staff_detail_cost = _child_label(management_detail_page, "", Vector2(105, 111), Vector2(400, 27), 15, MUTED)
	work_buttons["employee_enabled"] = _make_button(management_detail_page, "", Rect2(20, 146, 173, 34), _toggle_employee)
	for i in range(4):
		var row_kind: String = ["serve", "clear", "cook", "clean"][i]
		var row_y := 195 + i * 47
		var row := _child_label(management_detail_page, "", Vector2(20, row_y), Vector2(200, 34), 18, CREAM)
		work_buttons["label_" + row_kind] = row
		var toggle := _make_button(management_detail_page, "开 / 关", Rect2(272, row_y, 93, 32), func(): _toggle_employee_work(row_kind))
		work_buttons["toggle_" + row_kind] = toggle
		var up_button := _make_button(management_detail_page, "↑ 优先", Rect2(380, row_y, 147, 32), func(): _move_employee_priority(row_kind))
		work_buttons["up_" + row_kind] = up_button
	management_status = _child_label(management_detail_page, "", Vector2(20, 389), Vector2(515, 26), 14, CREAM)
	management_hire_page.hide()
	management_detail_page.hide()
	preopen_panel = _panel(Rect2(325, 200, 630, 400), Color("30291f"))
	preopen_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_child_label(preopen_panel, "开店准备", Vector2(34, 24), Vector2(550, 48), 30, GOLD)
	preopen_text = _child_label(preopen_panel, "", Vector2(34, 86), Vector2(560, 120), 19, CREAM)
	_button(preopen_panel, "开始营业", Rect2(34, 220, 562, 48), start_day)
	_button(preopen_panel, "进入餐厅", Rect2(34, 286, 370, 38), _toggle_preopen)
	_button(preopen_panel, "家具设备", Rect2(418, 286, 178, 38), _toggle_layout)
	_button(preopen_panel, "逐格扩建", Rect2(34, 334, 270, 38), _toggle_expansion)
	_button(preopen_panel, "新游戏", Rect2(326, 334, 270, 38), _open_reset)
	_build_store_panel()
	_build_layout_panel()
	_build_expansion_panel()
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
	management_panel.reparent(modal_root)
	layout_panel.reparent(modal_root)
	expansion_panel.reparent(modal_root)
	summary_panel.reparent(modal_root)
	reset_dialog.reparent(modal_root)


func _management_page_root() -> Control:
	var page := Control.new()
	page.position = Vector2(0, 94)
	page.size = Vector2(555, 420)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	management_panel.add_child(page)
	return page


func _staff_scroll(parent: Control, at: Vector2, dimensions: Vector2) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.position = at
	scroll.size = dimensions
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	return scroll


func _staff_list_contents(scroll: ScrollContainer) -> VBoxContainer:
	var contents := VBoxContainer.new()
	contents.custom_minimum_size.x = 494
	contents.add_theme_constant_override("separation", 8)
	scroll.add_child(contents)
	return contents


func _staff_avatar(profile_id: String, at: Vector2, size_scale: float) -> Sprite2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = STAFF_SHEET
	atlas.region = Rect2(0, 0, 64, 88)
	var portrait := Sprite2D.new()
	portrait.texture = atlas
	portrait.centered = false
	portrait.position = at
	portrait.scale = Vector2.ONE * size_scale
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.modulate = Model.STAFF_PROFILES[profile_id].color
	return portrait


func _staff_card(profile_id: String, candidate: bool) -> Panel:
	var row := Panel.new()
	row.name = profile_id
	row.custom_minimum_size = Vector2(494, 114)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("493321")
	style.border_color = Color("a6784b")
	style.set_border_width_all(2)
	row.add_theme_stylebox_override("panel", style)
	var content_width := 478 if candidate else 369
	var open := _make_button(row, "", Rect2(8, 7, content_width, 100), func(): _hire_profile(profile_id) if candidate else _open_staff_detail(profile_id))
	open.add_child(_staff_avatar(profile_id, Vector2(10, 15), 0.69))
	_child_label(open, Model.STAFF_PROFILES[profile_id].name, Vector2(67, 8), Vector2(295, 26), 19, GOLD)
	_child_label(open, Model.STAFF_PROFILES[profile_id].bio, Vector2(67, 32), Vector2(296, 22), 14, CREAM)
	_child_label(open, "工作设置：" + _staff_work_summary(profile_id), Vector2(67, 55), Vector2(300, 21), 13, CREAM)
	_child_label(open, "雇佣费用：%d 金币/日%s" % [Model.DAILY_WAGE, " · 次日到岗" if candidate or profile_id not in model.staff_roster else ""], Vector2(67, 77), Vector2(300, 19), 12, MUTED)
	if candidate:
		open.disabled = model.planned_employee_count() >= Model.MAX_EMPLOYEES
	else:
		var remove := _make_button(row, "解除雇佣", Rect2(383, 35, 101, 43), func(): _dismiss_profile(profile_id))
		remove.tooltip_text = "次日生效"
	return row


func _rebuild_staff_lists() -> void:
	for child in staff_list_items.get_children():
		staff_list_items.remove_child(child)
		child.queue_free()
	for child in hire_list_items.get_children():
		hire_list_items.remove_child(child)
		child.queue_free()
	var planned := model.planned_staff_ids()
	for profile_id: String in planned: staff_list_items.add_child(_staff_card(profile_id, false))
	for profile_id: String in Model.STAFF_PROFILE_IDS:
		if profile_id not in planned: hire_list_items.add_child(_staff_card(profile_id, true))
	if planned.is_empty():
		_child_label(staff_list_items, "尚未安排员工，点击右上角 ＋ 选择。", Vector2(8, 15), Vector2(470, 40), 16, MUTED)
	if model.planned_employee_count() >= Model.MAX_EMPLOYEES:
		_child_label(hire_list_items, "名额已满，可先在员工列表解除一人。", Vector2(8, 15), Vector2(470, 40), 15, MUTED)
	_refresh_employee_panel()


func _show_management_list() -> void:
	management_page = "list"
	management_list_page.show()
	management_hire_page.hide()
	management_detail_page.hide()
	_rebuild_staff_lists()


func _show_hire_page() -> void:
	management_page = "hire"
	management_list_page.hide()
	management_hire_page.show()
	management_detail_page.hide()
	_rebuild_staff_lists()


func _open_staff_detail(profile_id: String) -> void:
	if profile_id not in model.planned_staff_ids(): return
	selected_staff_id = profile_id
	selected_employee_index = maxi(0, model.staff_roster.find(profile_id))
	management_page = "detail"
	management_list_page.hide()
	management_hire_page.hide()
	management_detail_page.show()
	_refresh_employee_panel()


func _hire_profile(profile_id: String) -> void:
	if model.schedule_hire_profile(profile_id): _show_management_list()


func _dismiss_profile(profile_id: String) -> void:
	if model.schedule_dismiss_profile(profile_id): _show_management_list()


func _snapshot_staff_settings() -> void:
	for i in range(model.staff_roster.size()):
		var worker = employees[i]
		staff_settings_by_id[model.staff_roster[i]] = {
			"enabled": worker.enabled,
			"work_enabled": worker.work_enabled.duplicate(true),
			"priority": worker.priority.duplicate(),
		}


func _staff_settings_for(profile_id: String) -> Dictionary:
	var active_index := model.staff_roster.find(profile_id)
	if active_index >= 0 and active_index < employees.size():
		var worker = employees[active_index]
		return {
			"enabled": worker.enabled,
			"work_enabled": worker.work_enabled.duplicate(true),
			"priority": worker.priority.duplicate(),
		}
	if staff_settings_by_id.has(profile_id): return staff_settings_by_id[profile_id].duplicate(true)
	return {
		"enabled": true,
		"work_enabled": {"serve": true, "clear": true, "clean": true, "cook": true},
		"priority": ["serve", "clear", "clean", "cook"],
	}


func _apply_selected_staff_settings(profile_id: String, settings: Dictionary) -> void:
	staff_settings_by_id[profile_id] = settings.duplicate(true)
	var active_index := model.staff_roster.find(profile_id)
	if active_index < 0 or active_index >= employees.size(): return
	var worker = employees[active_index]
	worker.enabled = settings.enabled
	worker.work_enabled = settings.work_enabled.duplicate(true)
	var priority: Array[String] = []
	for kind: String in settings.priority: priority.append(kind)
	worker.priority = priority


func _apply_staff_roster_settings() -> void:
	for i in range(employees.size()):
		var worker = employees[i]
		if i >= model.staff_roster.size(): continue
		var profile_id: String = model.staff_roster[i]
		var profile: Dictionary = Model.STAFF_PROFILES[profile_id]
		worker.avatar.sprite.modulate = profile.color
		worker.title_label.text = profile.name
		if staff_settings_by_id.has(profile_id):
			_apply_selected_staff_settings(profile_id, staff_settings_by_id[profile_id])


func _staff_work_summary(profile_id: String) -> String:
	var settings := _staff_settings_for(profile_id)
	if not settings.enabled: return "休息中"
	var kinds: Array[String] = []
	for kind: String in settings.priority:
		if settings.work_enabled[kind]: kinds.append(employees[0].WORK_LABELS[kind])
	return "、".join(kinds) if not kinds.is_empty() else "未分配任务"


func _selected_profile_id() -> String:
	if selected_staff_id != "" and selected_staff_id in model.planned_staff_ids(): return selected_staff_id
	if selected_employee_index >= 0 and selected_employee_index < model.staff_roster.size(): return model.staff_roster[selected_employee_index]
	return ""


func _build_store_panel() -> void:
	store_panel = _panel(Rect2(258, 171, 764, 512), Color("30291f"))
	store_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	store_panel.hide()
	_child_label(store_panel, "餐厅菜谱", Vector2(28, 16), Vector2(360, 43), 28, GOLD)
	store_labels["overview"] = _child_label(store_panel, "", Vector2(28, 62), Vector2(650, 27), 15, CREAM)
	_make_button(store_panel, "关闭", Rect2(657, 19, 80, 33), _toggle_store)
	store_grid = ScrollContainer.new()
	store_grid.position = Vector2(24, 96)
	store_grid.size = Vector2(716, 390)
	store_grid.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	store_panel.add_child(store_grid)
	store_cards = GridContainer.new()
	store_cards.columns = 6
	store_cards.custom_minimum_size.x = 700
	store_cards.add_theme_constant_override("h_separation", 8)
	store_cards.add_theme_constant_override("v_separation", 8)
	store_grid.add_child(store_cards)
	for i in range(Model.RECIPE_IDS.size()):
		var recipe_id: String = Model.RECIPE_IDS[i]
		var card := _make_button(store_cards, "", Rect2(Vector2.ZERO, Vector2(108, 174)), func(): _show_recipe(recipe_id))
		card.custom_minimum_size = Vector2(108, 174)
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color("493321")
		card_style.border_color = Color("ab7649")
		card_style.set_border_width_all(2)
		card.add_theme_stylebox_override("normal", card_style)
		card.add_child(_recipe_image(recipe_id, Vector2(13, 10), Vector2(82, 82)))
		_child_label(card, Model.RECIPES[recipe_id].name, Vector2(6, 104), Vector2(98, 26), 14, CREAM)
		store_labels["card_" + recipe_id] = _child_label(card, "", Vector2(6, 130), Vector2(98, 41), 12, GOLD)
	store_detail = Control.new()
	store_detail.position = Vector2(0, 96)
	store_detail.size = Vector2(764, 410)
	store_panel.add_child(store_detail)
	store_detail.hide()
	_make_button(store_detail, "← 返回菜谱", Rect2(28, 4, 135, 32), _show_recipe_grid)
	store_labels["detail_name"] = _child_label(store_detail, "", Vector2(28, 43), Vector2(300, 35), 25, GOLD)
	store_labels["detail_intro"] = _child_label(store_detail, "", Vector2(28, 84), Vector2(315, 58), 16, CREAM)
	store_labels["detail_available"] = _child_label(store_detail, "", Vector2(28, 132), Vector2(315, 28), 15, GOLD)
	store_labels["detail_picture"] = _recipe_image("rice", Vector2(50, 159), Vector2(225, 225))
	store_detail.add_child(store_labels["detail_picture"])
	_child_label(store_detail, "每份用料 / 单项采购", Vector2(360, 40), Vector2(370, 33), 21, GOLD)
	for i in range(Model.INGREDIENTS.size()):
		var ingredient: String = Model.INGREDIENTS.keys()[i]
		var y := 84 + i * 49
		store_labels["stock_" + ingredient] = _child_label(store_detail, "", Vector2(360, y), Vector2(172, 27), 14, CREAM)
		store_labels["minus_" + ingredient] = _make_button(store_detail, "−", Rect2(536, y, 28, 29), func(): _adjust_purchase(ingredient, -1))
		store_labels["quantity_" + ingredient] = _child_label(store_detail, "", Vector2(568, y), Vector2(41, 28), 14, CREAM)
		store_labels["plus_" + ingredient] = _make_button(store_detail, "+", Rect2(606, y, 28, 29), func(): _adjust_purchase(ingredient, 1))
		store_labels["buy_" + ingredient] = _make_button(store_detail, "购买", Rect2(643, y, 78, 29), func(): _buy_ingredient(ingredient))
	store_labels["target"] = _child_label(store_detail, "", Vector2(410, 292), Vector2(185, 28), 16, CREAM)
	_make_button(store_detail, "−", Rect2(360, 290, 39, 31), func(): _adjust_recipe_target(-1))
	_make_button(store_detail, "+", Rect2(590, 290, 39, 31), func(): _adjust_recipe_target(1))
	store_labels["auto_buy"] = _make_button(store_detail, "补足食材", Rect2(643, 290, 88, 31), _buy_recipe_target)
	store_labels["price_minus"] = _make_button(store_detail, "定价 −", Rect2(360, 337, 80, 31), func(): _adjust_menu_price(selected_recipe, -1))
	store_labels["price"] = _child_label(store_detail, "", Vector2(450, 339), Vector2(105, 29), 16, GOLD)
	store_labels["price_plus"] = _make_button(store_detail, "定价 +", Rect2(550, 337, 80, 31), func(): _adjust_menu_price(selected_recipe, 1))
	store_labels["toggle"] = _make_button(store_detail, "", Rect2(643, 337, 88, 31), func(): _toggle_recipe(selected_recipe))
	store_labels["emergency"] = _make_button(store_detail, "应急补给", Rect2(360, 377, 150, 30), _claim_emergency)


func _build_layout_panel() -> void:
	layout_panel = _panel(Rect2(20, 170, 300, 530), Color("30291f"))
	layout_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	layout_panel.hide()
	_child_label(layout_panel, "家具与设备", Vector2(18, 14), Vector2(265, 40), 25, GOLD)
	layout_labels["balance"] = _child_label(layout_panel, "", Vector2(18, 60), Vector2(265, 28), 15, CREAM)
	layout_labels["selected"] = _child_label(layout_panel, "", Vector2(70, 101), Vector2(155, 30), 18, CREAM)
	layout_labels["previous"] = _make_button(layout_panel, "←", Rect2(18, 98, 42, 32), func(): _select_layout_table(-1))
	layout_labels["next"] = _make_button(layout_panel, "→", Rect2(235, 98, 42, 32), func(): _select_layout_table(1))
	layout_labels["move"] = _make_button(layout_panel, "移动选中物品", Rect2(18, 141, 259, 35), func(): _begin_layout_preview(false))
	layout_labels["buy"] = _make_button(layout_panel, "", Rect2(18, 184, 259, 35), func(): _begin_layout_preview(true))
	layout_labels["upgrade"] = _make_button(layout_panel, "", Rect2(18, 227, 259, 35), _upgrade_equipment)
	layout_labels["instructions"] = _child_label(layout_panel, "点击物品选中；布置时点击地面或用箭头预览。\n绿色可放，红色不可放；确认前不扣款。", Vector2(18, 272), Vector2(265, 58), 14, MUTED)
	layout_labels["left"] = _make_button(layout_panel, "←", Rect2(18, 333, 55, 32), func(): _move_layout_preview(Vector2(-20, 0)))
	layout_labels["right"] = _make_button(layout_panel, "→", Rect2(82, 333, 55, 32), func(): _move_layout_preview(Vector2(20, 0)))
	layout_labels["up"] = _make_button(layout_panel, "↑", Rect2(146, 333, 55, 32), func(): _move_layout_preview(Vector2(0, -20)))
	layout_labels["down"] = _make_button(layout_panel, "↓", Rect2(210, 333, 67, 32), func(): _move_layout_preview(Vector2(0, 20)))
	layout_labels["valid"] = _child_label(layout_panel, "", Vector2(18, 371), Vector2(265, 24), 14, CREAM)
	layout_labels["confirm"] = _make_button(layout_panel, "确认位置", Rect2(18, 402, 124, 35), _confirm_layout_preview)
	layout_labels["cancel"] = _make_button(layout_panel, "取消布置", Rect2(153, 402, 124, 35), _cancel_layout_preview)
	_make_button(layout_panel, "返回开店准备", Rect2(18, 446, 259, 32), _toggle_layout)
	_make_button(layout_panel, "←", Rect2(18, 486, 55, 32), func(): _move_camera_focus(Vector2(-160, 0)))
	_make_button(layout_panel, "→", Rect2(82, 486, 55, 32), func(): _move_camera_focus(Vector2(160, 0)))
	_make_button(layout_panel, "↑", Rect2(146, 486, 55, 32), func(): _move_camera_focus(Vector2(0, -120)))
	_make_button(layout_panel, "↓", Rect2(210, 486, 67, 32), func(): _move_camera_focus(Vector2(0, 120)))
	_refresh_layout_panel()


func _build_expansion_panel() -> void:
	expansion_panel = _panel(Rect2(20, 170, 300, 230), Color("30291f"))
	expansion_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	expansion_panel.hide()
	_child_label(expansion_panel, "逐格扩建", Vector2(18, 14), Vector2(265, 40), 25, GOLD)
	expansion_labels["balance"] = _child_label(expansion_panel, "", Vector2(18, 57), Vector2(265, 28), 15, CREAM)
	_child_label(expansion_panel, "点击场景中发光的相邻地块，立即铺设。\n可向右、向下不断扩展。", Vector2(18, 88), Vector2(265, 53), 14, MUTED)
	_make_button(expansion_panel, "←", Rect2(18, 146, 55, 32), func(): _move_camera_focus(Vector2(-160, 0)))
	_make_button(expansion_panel, "→", Rect2(82, 146, 55, 32), func(): _move_camera_focus(Vector2(160, 0)))
	_make_button(expansion_panel, "↑", Rect2(146, 146, 55, 32), func(): _move_camera_focus(Vector2(0, -120)))
	_make_button(expansion_panel, "↓", Rect2(210, 146, 67, 32), func(): _move_camera_focus(Vector2(0, 120)))
	_make_button(expansion_panel, "结束扩建", Rect2(18, 187, 259, 32), _toggle_expansion)
	_refresh_expansion_panel()


func _toggle_expansion() -> void:
	if model.phase != "preopen": return
	expansion_panel.visible = not expansion_panel.visible
	if expansion_panel.visible:
		store_panel.hide()
		management_panel.hide()
		layout_panel.hide()
	preopen_panel.visible = not expansion_panel.visible
	$Background.set_expansion_preview(expansion_panel.visible)
	_refresh_expansion_panel()


func _refresh_expansion_panel() -> void:
	if expansion_panel == null: return
	expansion_labels.balance.text = "可用 %d · 每格 %d · 已扩建 %d 格" % [model.spendable_cash(), Model.EXPANSION_PRICE, model.expansion_cells.size()]


func _click_expansion(point: Vector2) -> bool:
	var cell := Vector2i(floori((point.x - Layout.ROOM_ORIGIN.x) / Layout.ROOM_CELL), floori((point.y - Layout.ROOM_ORIGIN.y) / Layout.ROOM_CELL))
	if not model.can_expand(cell) or not model.buy_expansion(cell): return false
	$Background.set_expansion(model.expansion_cells)
	for worker in employees: worker.grid = null
	_refresh_expansion_panel()
	return true


func _move_camera_focus(amount: Vector2) -> void:
	if model.phase != "preopen" or (not layout_panel.visible and not expansion_panel.visible): return
	var edge := Layout.owned_bounds(model.expansion_cells) + Vector2(Layout.ROOM_CELL, Layout.ROOM_CELL)
	camera_focus.x = clampf(camera_focus.x + amount.x, 640.0, maxf(640.0, edge.x - 500.0))
	camera_focus.y = clampf(camera_focus.y + amount.y, 400.0, maxf(400.0, edge.y - 300.0))
	$Camera.position = camera_focus


func _toggle_layout() -> void:
	if model.phase != "preopen": return
	if layout_panel.visible:
		_cancel_layout_preview()
		layout_panel.hide()
		_refresh_layout_panel()
		preopen_panel.show()
	else:
		store_panel.hide()
		management_panel.hide()
		expansion_panel.hide()
		$Background.set_expansion_preview(false)
		preopen_panel.hide()
		layout_panel.show()
	_refresh_layout_panel()


func _select_layout_table(delta: int) -> void:
	if layout_editing: return
	layout_selected = clampi(layout_selected + delta, 0, model.table_count() + Model.DEVICE_IDS.size() - 1)
	_refresh_layout_panel()


func _select_layout_at(point: Vector2) -> void:
	var nearest_index := -1
	var nearest_distance := 70.0
	for i in range(model.table_count()):
		var distance := minf(point.distance_to(model.table_positions[i]), point.distance_to(model.table_positions[i] + Vector2(100, 0)))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = i
	for i in range(Model.DEVICE_IDS.size()):
		var distance: float = point.distance_to(model.device_positions[Model.DEVICE_IDS[i]])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = model.table_count() + i
	if nearest_index >= 0:
		layout_selected = nearest_index
		_refresh_layout_panel()


func _layout_device_id() -> String:
	var index := layout_selected - model.table_count()
	return Model.DEVICE_IDS[index] if index >= 0 and index < Model.DEVICE_IDS.size() else ""


func _begin_layout_preview(new_table: bool) -> void:
	if model.phase != "preopen" or layout_editing: return
	var free_position := Layout.free_table_position(model.table_positions, model.device_positions, model.expansion_cells) if new_table else Vector2.ZERO
	if new_table and free_position == Vector2.ZERO:
		model.feedback.emit("餐厅暂无可摆放餐桌的位置；请调整布局。")
		return
	layout_new_table = new_table
	layout_editing = true
	var device_id := "" if new_table else _layout_device_id()
	layout_preview_position = free_position if new_table else model.device_positions[device_id] if device_id != "" else model.table_positions[layout_selected]
	if not new_table:
		if device_id != "": stations[device_id].visible = false
		else:
			table_nodes[layout_selected].visible = false
			chair_nodes[layout_selected].visible = false
	layout_preview_table = (StoveScene if device_id in Model.STOVES else PassScene if device_id == "pass" else SinkScene).instantiate() if device_id != "" else TableScene.instantiate()
	actors.add_child(layout_preview_table)
	layout_preview_table.collision_layer = 0
	layout_preview_table.get_node("CollisionShape2D").disabled = true
	if device_id == "":
		layout_preview_chair = ChairScene.instantiate()
		actors.add_child(layout_preview_chair)
		layout_preview_chair.collision_layer = 0
		layout_preview_chair.get_node("CollisionShape2D").disabled = true
	layout_preview_table.get_node("Caption").text = "新餐桌" if new_table else stations[device_id].display_name if device_id != "" else "%02d 号桌" % (layout_selected + 1)
	_refresh_layout_preview()


func _move_layout_preview(offset: Vector2) -> void:
	if not layout_editing: return
	layout_preview_position += offset
	_refresh_layout_preview()


func _preview_layout_valid() -> bool:
	var positions: Array[Vector2] = model.table_positions.duplicate()
	var devices: Dictionary = model.device_positions.duplicate(true)
	if layout_new_table: positions.append(layout_preview_position)
	elif _layout_device_id() != "": devices[_layout_device_id()] = layout_preview_position
	else: positions[layout_selected] = layout_preview_position
	return Layout.valid(positions, devices, model.expansion_cells)


func _refresh_layout_preview() -> void:
	if not layout_editing: return
	layout_preview_table.position = layout_preview_position
	if is_instance_valid(layout_preview_chair): layout_preview_chair.position = layout_preview_position + Vector2(100, 0)
	var tint := Color(0.65, 1.0, 0.65, 0.7) if _preview_layout_valid() else Color(1.0, 0.5, 0.45, 0.7)
	layout_preview_table.modulate = tint
	if is_instance_valid(layout_preview_chair): layout_preview_chair.modulate = tint
	_refresh_layout_panel()


func _confirm_layout_preview() -> void:
	if not layout_editing or not _preview_layout_valid(): return
	var device_id := "" if layout_new_table else _layout_device_id()
	var original: Vector2 = model.device_positions[device_id] if device_id != "" else model.table_positions[layout_selected] if not layout_new_table else Vector2.ZERO
	if not layout_new_table and original == layout_preview_position:
		_cancel_layout_preview()
		return
	var success: bool = model.buy_table(layout_preview_position) if layout_new_table else model.move_device(device_id, layout_preview_position) if device_id != "" else model.move_table(layout_selected, layout_preview_position)
	if not success: return
	_cancel_layout_preview()
	_sync_layout_nodes()
	if layout_new_table: layout_selected = model.table_count() - 1
	_refresh_ui()
	_refresh_layout_panel()


func _cancel_layout_preview() -> void:
	if not layout_editing: return
	if not layout_new_table:
		var device_id := _layout_device_id()
		if device_id != "": stations[device_id].visible = true
		else:
			table_nodes[layout_selected].visible = true
			chair_nodes[layout_selected].visible = true
	layout_preview_table.queue_free()
	if is_instance_valid(layout_preview_chair): layout_preview_chair.queue_free()
	layout_preview_table = null
	layout_preview_chair = null
	layout_editing = false
	_refresh_layout_panel()


func _upgrade_equipment() -> void:
	model.upgrade_equipment()
	_refresh_layout_panel()


func _refresh_layout_panel() -> void:
	if layout_panel == null: return
	var total := model.table_count() + Model.DEVICE_IDS.size()
	layout_selected = mini(layout_selected, total - 1)
	layout_labels.balance.text = "现金 %d · 可用 %d" % [model.coins, model.spendable_cash()]
	layout_labels.selected.text = "%d/%d · %s" % [layout_selected + 1, total, stations[_layout_device_id()].display_name if _layout_device_id() != "" else "%02d 号桌" % (layout_selected + 1)]
	layout_labels.previous.disabled = layout_editing or layout_selected == 0
	layout_labels.next.disabled = layout_editing or layout_selected >= total - 1
	layout_labels.move.disabled = layout_editing
	layout_labels.buy.text = "购买第 %d 张桌 · %d 金币" % [model.table_count() + 1, Model.TABLE_PRICE]
	layout_labels.buy.disabled = layout_editing or model.spendable_cash() < Model.TABLE_PRICE
	layout_labels.upgrade.text = "烹饪加速 25%% · %d 金币" % Model.EQUIPMENT_PRICE if model.equipment_level == 0 else "设备已升级 · 制作提速 25%"
	layout_labels.upgrade.disabled = layout_editing or model.equipment_level > 0 or model.spendable_cash() < Model.EQUIPMENT_PRICE
	for key in ["left", "right", "up", "down", "cancel"]: layout_labels[key].disabled = not layout_editing
	layout_labels.confirm.disabled = not layout_editing or not _preview_layout_valid() or (layout_new_table and model.spendable_cash() < Model.TABLE_PRICE)
	layout_labels.valid.text = ("位置可用" if _preview_layout_valid() else "位置不可用：碰撞、越界或堵住通路") if layout_editing else ""
	layout_labels.valid.add_theme_color_override("font_color", GREEN if layout_editing and _preview_layout_valid() else RED)
	for i in range(table_nodes.size()):
		var tint := Color("fff4c7") if layout_panel.visible and not layout_editing and layout_selected == i else Color.WHITE
		table_nodes[i].modulate = tint
		chair_nodes[i].modulate = tint
	for i in range(Model.DEVICE_IDS.size()):
		stations[Model.DEVICE_IDS[i]].modulate = Color("fff4c7") if layout_panel.visible and not layout_editing and layout_selected == model.table_count() + i else Color.WHITE


func _adjust_purchase(ingredient: String, amount: int) -> void:
	purchase_quantities[ingredient] = clampi(purchase_quantities[ingredient] + amount, 1, 20)
	_refresh_store_panel()


func _recipe_image(recipe_id: String, at: Vector2, dimensions: Vector2) -> Sprite2D:
	var index := Model.RECIPE_IDS.find(recipe_id)
	var atlas := AtlasTexture.new()
	atlas.atlas = DISH_SHEET
	atlas.region = Rect2((index % 2) * 256, (index / 2) * 256, 256, 256)
	var picture := Sprite2D.new()
	picture.texture = atlas
	picture.position = at
	picture.centered = false
	picture.scale = Vector2.ONE * (minf(dimensions.x, dimensions.y) / 256.0)
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return picture


func _show_recipe(recipe_id: String) -> void:
	if not Model.RECIPES.has(recipe_id): return
	selected_recipe = recipe_id
	store_grid.hide()
	store_detail.show()
	var atlas: AtlasTexture = store_labels.detail_picture.texture
	var index := Model.RECIPE_IDS.find(recipe_id)
	atlas.region = Rect2((index % 2) * 256, (index / 2) * 256, 256, 256)
	_refresh_store_panel()


func _show_recipe_grid() -> void:
	selected_recipe = ""
	store_detail.hide()
	store_grid.show()


func _adjust_recipe_target(amount: int) -> void:
	recipe_target_portions = clampi(recipe_target_portions + amount, 1, 20)
	_refresh_store_panel()


func _buy_recipe_target() -> void:
	if selected_recipe != "": model.purchase_recipe_portions(selected_recipe, recipe_target_portions)
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
	if model.phase == "summary" or is_instance_valid(cooking_screen): return
	store_panel.visible = not store_panel.visible
	if store_panel.visible:
		management_panel.hide()
		preopen_panel.hide()
		expansion_panel.hide()
		$Background.set_expansion_preview(false)
		_show_recipe_grid()
	player.locked = store_panel.visible
	if model.phase == "open": get_tree().paused = store_panel.visible
	_refresh_store_panel()


func _request_store() -> void:
	if player.global_position.distance_to(MENU_DESK) > DESK_DISTANCE:
		_show_feedback("请靠近左上角墙上的菜谱记录。")
		return
	_toggle_store()


func _request_management() -> void:
	if player.global_position.distance_to(STAFF_DESK) > DESK_DISTANCE:
		_show_feedback("请靠近左上角墙上的雇佣记录。")
		return
	_toggle_management()


func _toggle_preopen() -> void:
	if model.phase != "preopen": return
	preopen_panel.visible = not preopen_panel.visible
	if preopen_panel.visible:
		store_panel.hide()
		management_panel.hide()
	player.locked = preopen_panel.visible


func _refresh_store_panel() -> void:
	if store_labels.is_empty(): return
	store_labels.overview.text = "现金 %d · 工资预留 %d · 可采购 %d 金币" % [model.coins, model.wage_reserved, model.spendable_cash()]
	for ingredient: String in Model.INGREDIENTS:
		var definition: Dictionary = Model.INGREDIENTS[ingredient]
		var per_portion: int = int(Model.RECIPES[selected_recipe].ingredients.get(ingredient, 0)) if selected_recipe != "" else 0
		var visible_row := per_portion > 0
		var row_index: int = Model.RECIPES[selected_recipe].ingredients.keys().find(ingredient) if selected_recipe != "" else -1
		var row_y: int = 90 + row_index * 59
		store_labels["stock_" + ingredient].text = "%s×%d  库存%d  单价%d" % [definition.name, per_portion, model.ingredient_available(ingredient), definition.price]
		store_labels["quantity_" + ingredient].text = "×%d" % purchase_quantities[ingredient]
		for prefix in ["stock_", "minus_", "quantity_", "plus_", "buy_"]:
			store_labels[prefix + ingredient].visible = visible_row
			store_labels[prefix + ingredient].position.y = row_y
		store_labels["minus_" + ingredient].disabled = purchase_quantities[ingredient] <= 1
		store_labels["plus_" + ingredient].disabled = purchase_quantities[ingredient] >= 20
		store_labels["buy_" + ingredient].text = "买 %d" % (definition.price * purchase_quantities[ingredient])
		store_labels["buy_" + ingredient].disabled = definition.price * purchase_quantities[ingredient] > model.spendable_cash()
	for recipe_id: String in Model.RECIPE_IDS:
		store_labels["card_" + recipe_id].text = "可做 %d 份\n%s · %d 金币" % [model.portions_available(recipe_id), "在售" if model.menu_enabled[recipe_id] else "停售", model.menu_prices[recipe_id]]
	if selected_recipe != "":
		store_labels.detail_name.text = model.recipe_name(selected_recipe)
		store_labels.detail_intro.text = {"rice": "米饭配香煎蛋，简单又饱腹。", "noodles": "酸甜番茄裹着热腾腾的炒面。", "tomato_egg": "番茄与鸡蛋炒成家常味道。", "egg_noodles": "鸡蛋拌入面条，香软顺口。"}[selected_recipe]
		store_labels.detail_available.text = "当前可做 %d 份 · 建议售价 %d" % [model.portions_available(selected_recipe), Model.RECIPES[selected_recipe].price]
		store_labels.target.text = "补足到可做 %d 份" % recipe_target_portions
		var cost := 0
		for ingredient: String in Model.RECIPES[selected_recipe].ingredients:
			var required: int = int(Model.RECIPES[selected_recipe].ingredients[ingredient]) * recipe_target_portions
			cost += maxi(0, required - model.ingredient_available(ingredient)) * int(Model.INGREDIENTS[ingredient].price)
		store_labels.auto_buy.text = "购买 %d" % cost if cost > 0 else "已充足"
		store_labels.auto_buy.disabled = cost == 0 or cost > model.spendable_cash()
		store_labels.price.text = "%d 金币" % model.menu_prices[selected_recipe]
		store_labels.price_minus.disabled = model.phase != "preopen" or model.menu_prices[selected_recipe] <= 1
		store_labels.price_plus.disabled = model.phase != "preopen" or model.menu_prices[selected_recipe] >= 99
		store_labels.toggle.text = "在售" if model.menu_enabled[selected_recipe] else "已停售"
		store_labels.toggle.disabled = model.phase != "preopen"
	store_labels.emergency.disabled = not model.emergency_available()


func _refresh_ui() -> void:
	if labels.is_empty(): return
	_refresh_store_panel()
	_refresh_expansion_panel()
	if model.phase == "summary" and summary_panel != null and summary_panel.visible:
		summary_text.text = _format_summary(model.summary())
	labels.coins.text = "%d 金币" % model.coins
	if preopen_text != null:
		preopen_text.text = "第 %d 天 · 现金 %d · 工资预留 %d · 可用 %d\n今日雇员 %d 人，次日计划 %d 人。\n\n进入餐厅后，靠近左上角墙面点击菜谱或雇佣记录。" % [model.day_number, model.coins, model.wage_reserved, model.spendable_cash(), model.employee_hired_count, model.planned_employee_count()]
	if model.phase == "preopen":
		labels.employee.text = "员工：今日 %d · 次日计划 %d" % [model.employee_hired_count, model.planned_employee_count()]
	elif model.phase == "summary":
		labels.employee.text = "员工：%d 人已下班" % model.employee_attending_count
	else:
		var worker_states: Array[String] = []
		for i in range(model.employee_attending_count):
			var worker = employees[i]
			var activity: String = worker.WORK_LABELS.get(worker.job.get("kind", ""), "待命") if worker.enabled else "休息"
			worker_states.append("%d%s" % [i + 1, activity])
		labels.employee.text = "员工：%d/%d · %s" % [model.employee_attending_count, model.employee_hired_count, " ".join(worker_states) if not worker_states.is_empty() else "由主角经营"]
	var portions: Array[String] = []
	for recipe_id: String in Model.RECIPE_IDS:
		portions.append("%s %d" % [model.recipe_name(recipe_id), model.portions_available(recipe_id)])
	labels.capacity.text = "剩余可做：" + " · ".join(portions)
	for slot in range(order_cards.size()):
		var i := slot
		if i >= model.table_count(): continue
		var id: int = model.tables[i]
		var card := order_cards[slot]
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
	_refresh_employee_presence()
	summary_text.text = _format_summary(result)
	management_panel.hide()
	summary_panel.show()


func _format_summary(result: Dictionary) -> String:
	var expenses: Dictionary = result.expenses
	var spending: int = expenses.purchase + expenses.wages + expenses.furniture + expenses.equipment + expenses.expansion
	var missing: Array[String] = []
	for recipe_id: String in Model.RECIPE_IDS:
		var count: int = result.missing_first_choices.get(recipe_id, 0)
		if count > 0: missing.append("%s %d 位" % [model.recipe_name(recipe_id), count])
	var missing_text := "、".join(missing) if not missing.is_empty() else "无"
	var completed := {"cook": 0, "serve": 0, "clear": 0, "clean": 0}
	for worker in employees:
		for kind: String in completed: completed[kind] += worker.tasks_completed[kind]
	return "第 %d 天  日初 %d  +营业 %d  -支出 %d  =日末 %d\n现金变化 %+d · 食材消耗成本 %d · 估算经营收益 %d\n采购 %d · 工资 %d · 家具 %d · 设备 %d · 扩建 %d\n完成 %d 桌 · 流失 %d 位（未购买 %d）· 好评 %d · 差评 %d\n缺菜离店（按首选统计）：%s\n售价/口味未成交：%d 位\n平均等餐 %.1f 秒 · 剩余污渍 %d\n员工完成：做菜 %d · 上菜 %d · 收盘 %d · 清洁 %d\n%s" % [result.day, result.opening_cash, result.income, spending, result.coins, result.cash_change, result.ingredient_cost, result.operating_profit, expenses.purchase, expenses.wages, expenses.furniture, expenses.equipment, expenses.expansion, result.served, result.lost, result.no_sale, result.good_reviews, result.bad_reviews, missing_text, result.price_refusals, result.average_wait, result.stains, completed.cook, completed.serve, completed.clear, completed.clean, ("%d 位顾客未完成消费。" % result.lost) if result.lost > 0 else "今日营业已完成。"]


func _toggle_pause() -> void:
	if reset_dialog.visible or model.phase != "open": return
	if store_panel.visible:
		_toggle_store()
		return
	if management_panel.visible:
		_toggle_management()
		return
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
	if layout_panel.visible:
		_cancel_layout_preview()
		layout_panel.hide()
	management_panel.visible = not management_panel.visible
	if management_panel.visible: store_panel.hide()
	if management_panel.visible:
		expansion_panel.hide()
		$Background.set_expansion_preview(false)
	if management_panel.visible: preopen_panel.hide()
	player.locked = management_panel.visible
	if model.phase == "open": get_tree().paused = management_panel.visible
	if management_panel.visible: _show_management_list()
	_refresh_employee_panel()


func _toggle_employee() -> void:
	var profile_id := _selected_profile_id()
	if profile_id == "": return
	var settings := _staff_settings_for(profile_id)
	settings.enabled = not settings.enabled
	_apply_selected_staff_settings(profile_id, settings)
	_refresh_employee_panel()


func _toggle_hire() -> void:
	if model.schedule_employee_count(model.planned_employee_count() + 1): _refresh_ui()
	_rebuild_staff_lists()
	_refresh_employee_panel()


func _dismiss_employee() -> void:
	if model.schedule_employee_count(model.planned_employee_count() - 1): _refresh_ui()
	_rebuild_staff_lists()
	_refresh_employee_panel()


func _select_employee(delta: int) -> void:
	var planned := model.planned_staff_ids()
	if planned.is_empty(): return
	var current := planned.find(selected_staff_id) if selected_staff_id != "" else selected_employee_index
	_open_staff_detail(planned[clampi(current + delta, 0, planned.size() - 1)])


func _refresh_employee_presence() -> void:
	for i in range(employees.size()):
		employees[i].visible = model.phase == "open" and i < model.employee_attending_count


func _toggle_employee_work(kind: String) -> void:
	var profile_id := _selected_profile_id()
	if profile_id == "": return
	var settings := _staff_settings_for(profile_id)
	settings.work_enabled[kind] = not settings.work_enabled[kind]
	_apply_selected_staff_settings(profile_id, settings)
	_rebuild_staff_lists()
	_refresh_employee_panel()


func _move_employee_priority(kind: String) -> void:
	var profile_id := _selected_profile_id()
	if profile_id == "": return
	var settings := _staff_settings_for(profile_id)
	var order: Array = settings.priority
	var index := order.find(kind)
	if index > 0:
		order.remove_at(index)
		order.insert(index - 1, kind)
		settings.priority = order
		_apply_selected_staff_settings(profile_id, settings)
		_rebuild_staff_lists()
	_refresh_employee_panel()


func _refresh_employee_panel() -> void:
	if management_panel == null: return
	employment_label.text = "今日 %d 人 · 次日计划 %d 人 · 每人日薪 %d 金币" % [model.employee_hired_count, model.planned_employee_count(), Model.DAILY_WAGE]
	management_title.text = "员工管理" if management_page == "list" else "可雇佣员工" if management_page == "hire" else "员工详情"
	if management_page != "detail": return
	var profile_id := _selected_profile_id()
	if profile_id == "": return
	var planned := model.planned_staff_ids()
	management_title.text = "员工详情 · %d/%d" % [planned.find(profile_id) + 1, planned.size()]
	var profile: Dictionary = Model.STAFF_PROFILES[profile_id]
	var portrait: AtlasTexture = staff_detail_avatar.texture
	portrait.region = Rect2(0, 0, 64, 88)
	staff_detail_avatar.modulate = profile.color
	staff_detail_name.text = profile.name
	staff_detail_bio.text = profile.bio
	staff_detail_cost.text = "雇佣费用：%d 金币/日 · %s" % [Model.DAILY_WAGE, "次日到岗" if profile_id not in model.staff_roster else "已在岗"]
	var settings := _staff_settings_for(profile_id)
	var order: Array = settings.priority
	for i in range(order.size()):
		var kind: String = order[i]
		var row_y := 195 + i * 47
		work_buttons["label_" + kind].position.y = row_y
		work_buttons["toggle_" + kind].position.y = row_y
		work_buttons["up_" + kind].position.y = row_y
		work_buttons["label_" + kind].text = "%d  %s" % [i + 1, employees[0].WORK_LABELS[kind]]
		work_buttons["toggle_" + kind].text = "开启" if settings.work_enabled[kind] else "关闭"
		work_buttons["up_" + kind].disabled = i == 0
	select_previous_button.disabled = planned.find(profile_id) <= 0
	select_next_button.disabled = planned.find(profile_id) >= planned.size() - 1
	work_buttons["employee_enabled"].text = "安排休息" if settings.enabled else "安排工作"
	var active_index := model.staff_roster.find(profile_id)
	management_status.text = "当前状态：%s" % employees[active_index].status if active_index >= 0 and active_index < model.employee_attending_count and model.phase == "open" else "次日到岗后执行以上设置" if active_index < 0 else "今日未出勤"


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


func _wall_record_button(value: String, rect: Rect2, callback: Callable) -> Button:
	var button := _make_button(actors, value, rect, callback)
	button.z_index = 20
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_disabled_color", MUTED)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxTexture.new()
		style.texture = WALL_RECORD
		button.add_theme_stylebox_override(state, style)
	return button
