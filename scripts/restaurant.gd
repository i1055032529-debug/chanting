extends Node2D

const Model = preload("res://scripts/service_model.gd")
const Customer = preload("res://scenes/actors/customer.tscn")
const INTERACT_DISTANCE := 55.0
const CREAM := Color("f4e5cd")
const MUTED := Color("bea993")
const GOLD := Color("edbc72")

var model := Model.new()
var player: CharacterBody2D
var customer: Node2D
var actors: Node2D
var stations: Dictionary = {}
var font: SystemFont
var ui: Control
var labels: Dictionary = {}
var prompt: Label
var bar: ProgressBar
var reset_dialog: ConfirmationDialog
var pause_panel: Panel
var debug_label: Label
var debug_visible := false
var nearest := ""
var toast := "欢迎开店！用 WASD 移动，靠近工作台按 E 交互。"
var toast_time := 8.0
var elapsed := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_setup_input()
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	_build_room()
	_build_ui()
	model.customer_requested.connect(_spawn_customer)
	model.departure_requested.connect(_customer_leave)
	model.changed.connect(_refresh_ui)
	model.feedback.connect(_show_feedback)
	_refresh_ui()


func _process(delta: float) -> void:
	elapsed += delta
	toast_time = maxf(0.0, toast_time - delta)
	model.advance(delta)
	player.locked = model.phase == Model.Phase.COOKING
	player.carried = model.carrying
	nearest = closest_target()
	prompt.text = "[ E ]  %s · %s" % [stations[nearest].display_name, _action_hint(nearest)] if not nearest.is_empty() else "靠近工作台或餐桌的正下方，按 E 交互"
	labels.toast.text = toast if toast_time > 0.0 else _next_step()
	bar.visible = model.phase in [Model.Phase.COOKING, Model.Phase.EATING]
	bar.value = model.progress() * 100.0
	debug_label.text = "DEBUG / F1 关闭\nN 生成顾客 · R 重置\n订单 #%d · %s\n位置 (%d, %d)\n任务 %s" % [model.order_id, model.phase_label(), player.position.x, player.position.y, str(model.tasks)]
	for station_id: String in stations:
		stations[station_id].set_highlight(station_id == nearest)
	stations["pass"].show_item(model.phase == Model.Phase.READY)
	stations["table"].show_item(model.phase in [Model.Phase.EATING, Model.Phase.LEAVING, Model.Phase.DIRTY], model.phase != Model.Phase.EATING)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo():
		try_interact(closest_target())
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
	for key: String in stations:
		var distance: float = player.global_position.distance_to(target_position(key))
		if distance < best:
			result = key
			best = distance
	return result


func try_interact(target: String) -> bool:
	if target.is_empty() or not stations.has(target):
		_show_feedback("靠近工作台或餐桌的正下方，再按 E 交互。")
		return false
	if player.global_position.distance_to(target_position(target)) >= INTERACT_DISTANCE:
		_show_feedback("距离太远了，请靠近目标。")
		return false
	var succeeded: bool = model.interact(target)
	if succeeded:
		player.direction = (stations[target].global_position - player.global_position).normalized()
	return succeeded


func reset_run() -> void:
	if is_instance_valid(customer):
		customer.free()
	customer = null
	model.reset()
	player.global_position = $PlayerStart.global_position
	player.velocity = Vector2.ZERO
	player.locked = false
	player.carried = 0
	_show_feedback("本局已重置，欢迎重新开店！")
	_refresh_ui()


func _setup_input() -> void:
	var bindings := {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN], "interact": [KEY_E, KEY_SPACE], "pause_game": [KEY_ESCAPE], "toggle_debug": [KEY_F1], "debug_spawn": [KEY_N], "debug_reset": [KEY_R]}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)


func target_position(station_id: String) -> Vector2:
	return stations[station_id].interaction_position()


func _build_room() -> void:
	actors = $World
	player = $World/Player
	for child in actors.get_children():
		if child.has_method("interaction_position"):
			stations[child.station_id] = child


func _spawn_customer() -> void:
	customer = Customer.instantiate()
	var waypoints: Array[Vector2] = []
	for point in $CustomerRoute.get_children():
		waypoints.append(point.global_position)
	customer.configure($Entrance.global_position, waypoints, $World/Table/Seat.global_position)
	customer.seated.connect(model.seat_customer)
	customer.departed.connect(model.customer_departed)
	actors.add_child(customer)


func _customer_leave() -> void:
	if is_instance_valid(customer):
		customer.leave()


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
	# A lightweight always-processing node handles Escape while the scene is paused.
	var pause_input := Node.new()
	pause_input.set_script(preload("res://scripts/pause_input.gd"))
	pause_input.toggle_requested.connect(_toggle_pause)
	layer.add_child(pause_input)
	_label("kicker", "CHANTING  /  小店营业中", Vector2(32, 18), Vector2(300, 21), 12, MUTED)
	_label("title", "一人食堂", Vector2(30, 42), Vector2(310, 50), 34, CREAM)
	_label("subtitle", "从一份热饭，开始小店生活。", Vector2(32, 100), Vector2(330, 24), 14, MUTED)
	_panel(Rect2(354, 27, 130, 66), Color("493321"))
	_label("coins", "0 金币", Vector2(370, 42), Vector2(112, 36), 22, GOLD)
	_panel(Rect2(494, 27, 148, 66), Color("493321"))
	_label("served", "已接待 0 位", Vector2(510, 46), Vector2(129, 32), 18, CREAM)
	_label("hands", "双手空闲", Vector2(357, 102), Vector2(310, 26), 15, CREAM)
	_panel(Rect2(670, 20, 578, 108), Color("38291f"))
	_label("dish", "等待顾客入座", Vector2(688, 34), Vector2(275, 33), 22, CREAM)
	_label("order", "", Vector2(688, 78), Vector2(310, 34), 14, MUTED)
	_label("status", "● 等待入店", Vector2(1016, 38), Vector2(225, 30), 17, GOLD)
	bar = ProgressBar.new()
	bar.position = Vector2(1017, 83)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _style(Color("211811")))
	bar.add_theme_stylebox_override("fill", _style(GOLD))
	ui.add_child(bar)
	bar.size = Vector2(204, 7)
	var step_x := [36, 347, 659, 971]
	for i in range(4):
		_label("step%d" % i, "", Vector2(step_x[i], 136), Vector2(280, 27), 15, MUTED)
	_panel(Rect2(32, 708, 1216, 41), Color("493321"))
	_label("toast", toast, Vector2(47, 717), Vector2(1180, 28), 15, CREAM)
	prompt = _label("prompt", "", Vector2(32, 761), Vector2(675, 28), 15, GOLD)
	_label("controls", "WASD 移动   E 交互   Esc 暂停   F1 调试", Vector2(768, 764), Vector2(480, 25), 14, MUTED)
	debug_label = _label("debug", "", Vector2(48, 450), Vector2(500, 160), 12, CREAM, true)
	debug_label.add_theme_stylebox_override("normal", _style(Color("24190ff0")))
	debug_label.visible = false
	pause_panel = _panel(Rect2(430, 277, 420, 246), Color("38291f"))
	pause_panel.visible = false
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var pause_title := Label.new()
	pause_title.text = "休息一下"
	pause_title.position = Vector2(34, 26)
	pause_title.add_theme_font_size_override("font_size", 28)
	pause_panel.add_child(pause_title)
	var pause_note := Label.new()
	pause_note.text = "营业已暂停。本阶段进度仅保留在本局。"
	pause_note.position = Vector2(34, 77)
	pause_note.add_theme_font_size_override("font_size", 15)
	pause_panel.add_child(pause_note)
	_button(pause_panel, "继续营业  ·  Esc", Vector2(34, 125), Vector2(352, 42), _toggle_pause)
	_button(pause_panel, "重新开店", Vector2(34, 181), Vector2(352, 36), _open_reset)
	reset_dialog = ConfirmationDialog.new()
	reset_dialog.title = "重新开店"
	reset_dialog.dialog_text = "将清空本局金币、订单和接待记录，确定重新开始吗？"
	reset_dialog.ok_button_text = "重新开始"
	reset_dialog.cancel_button_text = "返回"
	reset_dialog.min_size = Vector2i(450, 140)
	reset_dialog.confirmed.connect(func():
		reset_run()
		get_tree().paused = false
		pause_panel.hide())
	reset_dialog.canceled.connect(func():
		get_tree().paused = pause_panel.visible)
	ui.add_child(reset_dialog)


func _toggle_pause() -> void:
	if reset_dialog.visible:
		return
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused


func _open_reset() -> void:
	get_tree().paused = true
	reset_dialog.popup_centered()


func _button(parent: Control, text: String, at: Vector2, size_value: Vector2, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = size_value
	button.add_theme_stylebox_override("normal", _style(Color("755132")))
	button.add_theme_stylebox_override("hover", _style(Color("946b44")))
	button.pressed.connect(callback)
	parent.add_child(button)


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style


func _panel(rect: Rect2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(color))
	ui.add_child(panel)
	return panel


func _label(key: String, text: String, at: Vector2, size_value: Vector2, font_size: int, color: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = size_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.add_child(label)
	labels[key] = label
	return label


func _show_feedback(message: String) -> void:
	toast = message
	toast_time = 6.0


func _refresh_ui() -> void:
	if labels.is_empty():
		return
	labels.coins.text = "%d 金币" % model.coins
	labels.served.text = "已接待 %d 位" % model.served
	labels.dish.text = "香煎蛋饭" if model.phase not in [Model.Phase.EMPTY, Model.Phase.ARRIVING] else "等待顾客入座"
	labels.order.text = "订单 #%03d  ·  售价 18 金币" % model.order_id if model.phase not in [Model.Phase.EMPTY, Model.Phase.ARRIVING] else "每一桌好生意，从干净餐桌开始。"
	labels.status.text = "● " + model.phase_label()
	labels.hands.text = ["双手空闲", "一份香煎蛋饭", "用过的餐盘"][model.carrying]
	var step := 0
	if model.phase in [Model.Phase.READY, Model.Phase.CARRIED]: step = 1
	elif model.phase in [Model.Phase.EATING, Model.Phase.LEAVING]: step = 2
	elif model.phase in [Model.Phase.DIRTY, Model.Phase.CLEARING]: step = 3
	var titles := ["烹饪台制作热饭", "出餐台取餐并上菜", "等待顾客用餐付款", "收盘并送回回收台"]
	for i in range(4):
		labels["step%d" % i].text = "%s  %s" % ["→" if i == step else ("✓" if i < step else "%02d" % (i + 1)), titles[i]]
		labels["step%d" % i].add_theme_color_override("font_color", GOLD if i == step else MUTED)


func _next_step() -> String:
	match model.phase:
		Model.Phase.EMPTY, Model.Phase.ARRIVING: return "顾客会自动入店点单。用 WASD 熟悉一下你的小店。"
		Model.Phase.WAITING: return "下一步：到烹饪台下方按 E，制作香煎蛋饭。"
		Model.Phase.COOKING: return "正在做菜。第一阶段使用短时计时制作，无需额外操作。"
		Model.Phase.READY: return "下一步：到出餐台下方按 E，拿起食物。"
		Model.Phase.CARRIED: return "下一步：到 01 号桌下方按 E，把食物送给顾客。"
		Model.Phase.EATING: return "顾客正在用餐，稍后会自动付款。"
		Model.Phase.LEAVING: return "顾客正在离店；离开后收拾餐桌。"
		Model.Phase.DIRTY: return "下一步：到餐桌下方按 E，拿起用过的餐盘。"
	return "下一步：将餐盘送到回收台，恢复餐桌。"


func _action_hint(target: String) -> String:
	match target:
		"stove": return "制作" if model.phase == Model.Phase.WAITING else "查看"
		"pass": return "放回食物" if model.carrying == Model.Carry.FOOD else "取餐"
		"table": return "上菜" if model.carrying == Model.Carry.FOOD else ("收盘" if model.phase == Model.Phase.DIRTY else "查看")
		"sink": return "回收餐盘"
	return "交互"
