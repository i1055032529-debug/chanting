extends Node2D

const Model = preload("res://scripts/service_model.gd")
const Art = preload("res://scripts/pixel_art.gd")
const Player = preload("res://scripts/player.gd")
const Customer = preload("res://scripts/customer.gd")
const TARGETS := {"stove": Vector2(148, 307), "pass": Vector2(332, 307), "table": Vector2(574, 418), "sink": Vector2(148, 557)}
const TARGET_NAMES := {"stove": "烹饪台", "pass": "出餐台", "table": "01 号桌", "sink": "回收台"}
const INTERACT_DISTANCE := 55.0
const CREAM := Color("eee7cf")
const MUTED := Color("91a59b")
const GOLD := Color("edc576")

var model := Model.new()
var player: CharacterBody2D
var customer: Node2D
var actors: Node2D
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
	prompt.text = "[ E ]  %s · %s" % [TARGET_NAMES[nearest], _action_hint(nearest)] if not nearest.is_empty() else "靠近工作台下方的标记，按 E 交互"
	labels.toast.text = toast if toast_time > 0.0 else _next_step()
	bar.visible = model.phase in [Model.Phase.COOKING, Model.Phase.EATING]
	bar.value = model.progress() * 100.0
	debug_label.text = "DEBUG / F1 关闭\nN 生成顾客 · R 重置\n订单 #%d · %s\n位置 (%d, %d)\n任务 %s" % [model.order_id, model.phase_label(), player.position.x, player.position.y, str(model.tasks)]
	queue_redraw()


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
	for key: String in TARGETS:
		var distance: float = player.position.distance_to(TARGETS[key])
		if distance < best:
			result = key
			best = distance
	return result


func try_interact(target: String) -> bool:
	if target.is_empty() or not TARGETS.has(target):
		_show_feedback("靠近工作台下方的标记，再按 E 交互。")
		return false
	if player.position.distance_to(TARGETS[target]) >= INTERACT_DISTANCE:
		_show_feedback("距离太远了，请靠近目标。")
		return false
	return model.interact(target)


func reset_run() -> void:
	if is_instance_valid(customer):
		customer.free()
	customer = null
	model.reset()
	player.position = Vector2(374, 465)
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


func _build_room() -> void:
	_solid(Rect2(32, 148, 752, 48))
	_solid(Rect2(32, 196, 16, 456))
	_solid(Rect2(768, 196, 16, 456))
	_solid(Rect2(32, 638, 752, 14))
	_solid(Rect2(96, 224, 104, 56))
	_solid(Rect2(280, 224, 104, 56))
	_solid(Rect2(526, 330, 96, 58))
	_solid(Rect2(634, 350, 34, 32))
	_solid(Rect2(96, 474, 104, 56))
	_solid(Rect2(66, 579, 38, 40))
	_solid(Rect2(704, 215, 38, 38))
	actors = Node2D.new()
	actors.y_sort_enabled = true
	add_child(actors)
	player = Player.new()
	player.name = "Player"
	player.position = Vector2(374, 465)
	actors.add_child(player)


func _solid(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _spawn_customer() -> void:
	customer = Customer.new()
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
	_label("kicker", "CHANTING  /  小店营业中", Vector2(36, 22), Vector2(450, 20), 13, MUTED)
	_label("title", "一人食堂", Vector2(32, 49), Vector2(390, 48), 34, CREAM)
	_label("subtitle", "从一份热饭，开始你的小店生活。", Vector2(35, 104), Vector2(550, 26), 16, MUTED)
	_panel(Rect2(520, 44, 120, 61), Color("203b36"))
	_label("coins", "0 金币", Vector2(536, 55), Vector2(112, 40), 22, GOLD)
	_panel(Rect2(652, 44, 132, 61), Color("203b36"))
	_label("served", "已接待 0 位", Vector2(666, 59), Vector2(120, 32), 17, CREAM)
	_panel(Rect2(808, 44, 280, 220), Color("223832"))
	_label("order_kicker", "01 号桌 / 当前订单", Vector2(830, 64), Vector2(240, 25), 14, MUTED)
	_label("dish", "等待第一位顾客", Vector2(830, 102), Vector2(240, 33), 23, CREAM)
	_label("order", "店里很安静，好好准备一下。", Vector2(830, 149), Vector2(232, 49), 15, MUTED, true)
	_label("status", "● 等待入店", Vector2(830, 216), Vector2(230, 26), 17, GOLD)
	_panel(Rect2(808, 280, 280, 235), Color("1b2e2a"))
	_label("steps_title", "一桌热饭的旅程", Vector2(830, 298), Vector2(240, 28), 19, CREAM)
	for i in range(4):
		_label("step%d" % i, "", Vector2(830, 342 + i * 39), Vector2(238, 30), 16, MUTED)
	_panel(Rect2(808, 531, 280, 121), Color("223832"))
	_label("hands_title", "手持物品", Vector2(830, 548), Vector2(220, 25), 14, MUTED)
	_label("hands", "双手空闲", Vector2(830, 583), Vector2(220, 34), 22, CREAM)
	_panel(Rect2(32, 660, 1056, 42), Color("203b36"))
	_label("toast", toast, Vector2(46, 669), Vector2(1020, 27), 15, CREAM)
	_panel(Rect2(219, 592, 397, 33), Color("172b28e8"))
	prompt = _label("prompt", "", Vector2(225, 597), Vector2(385, 27), 14, GOLD)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("controls", "WASD / 方向键 移动     E / 空格 交互     Esc 暂停     F1 调试", Vector2(260, 155), Vector2(518, 29), 12, CREAM)
	_label("stove", "烹饪台", Vector2(96, 201), Vector2(104, 22), 13, Color("42675b")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("pass", "出餐台", Vector2(280, 201), Vector2(104, 22), 13, Color("42675b")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("sink", "餐盘回收", Vector2(94, 446), Vector2(115, 26), 13, Color("42675b")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("table", "01", Vector2(552, 304), Vector2(50, 25), 17, Color("42675b")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar = ProgressBar.new()
	bar.position = Vector2(830, 197)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _style(Color("152721")))
	bar.add_theme_stylebox_override("fill", _style(GOLD))
	ui.add_child(bar)
	bar.size = Vector2(232, 7)
	debug_label = _label("debug", "", Vector2(234, 204), Vector2(492, 106), 12, CREAM, true)
	debug_label.add_theme_stylebox_override("normal", _style(Color("14251af0")))
	debug_label.visible = false
	pause_panel = _panel(Rect2(350, 237, 420, 246), Color("162d29"))
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
	button.add_theme_stylebox_override("normal", _style(Color("345d50")))
	button.add_theme_stylebox_override("hover", _style(Color("4a7865")))
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
	labels.order.text = "订单 #%03d  ·  18 金币\n现做一份，好好招待。" % model.order_id if model.phase not in [Model.Phase.EMPTY, Model.Phase.ARRIVING] else "每一桌好生意，\n从干净的餐桌开始。"
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
	return "下一步：将餐盘送到左下方的回收台，恢复餐桌。"


func _action_hint(target: String) -> String:
	match target:
		"stove": return "制作" if model.phase == Model.Phase.WAITING else "查看"
		"pass": return "放回食物" if model.carrying == Model.Carry.FOOD else "取餐"
		"table": return "上菜" if model.carrying == Model.Carry.FOOD else ("收盘" if model.phase == Model.Phase.DIRTY else "查看")
		"sink": return "回收餐盘"
	return "交互"


func _draw() -> void:
	# Room shell and checkerboard floor.
	draw_rect(Rect2(32, 148, 752, 504), Color("314d40"))
	for y in range(196, 638, 28):
		for x in range(48, 768, 28):
			var color := Color("d0c3a0") if ((x - 48) / 28 + (y - 196) / 28) % 2 == 0 else Color("c5b793")
			draw_rect(Rect2(x, y, mini(28, 768 - x), mini(28, 638 - y)), color)
	draw_rect(Rect2(48, 180, 720, 16), Color("8b9b71"))
	draw_rect(Rect2(48, 196, 720, 8), Color("a69976"))
	draw_rect(Rect2(334, 623, 80, 15), Color("647e69"))
	for x in range(340, 412, 10):
		draw_rect(Rect2(x, 625, 3, 11), Color("819680"))
	# Wall window and a small counter shelf.
	draw_rect(Rect2(480, 211, 158, 69), Color("687f6a"))
	draw_rect(Rect2(486, 216, 146, 55), Color("b7d6c3"))
	draw_rect(Rect2(494, 221, 62, 46), Color("cfe3c8"))
	draw_rect(Rect2(554, 216, 6, 55), Color("f0dfb6"))
	draw_rect(Rect2(480, 274, 158, 8), Color("886d4d"))
	_counter(Vector2(96, 224), Color("626f67"))
	draw_rect(Rect2(105, 229, 86, 32), Color("424c47"))
	for x in [112, 157]:
		draw_rect(Rect2(x, 234, 25, 21), Color("242f2e"))
		draw_rect(Rect2(x + 5, 239, 15, 11), Color("96694c"))
	if model.phase == Model.Phase.COOKING:
		draw_rect(Rect2(115, 237, 19, 17), GOLD)
		for i in range(3):
			var offset := fmod(elapsed * 18.0 + i * 13.0, 34.0)
			draw_rect(Rect2(117 + i * 7, 229 - offset, 4, 7), Color("f4e9cbb0"))
	_counter(Vector2(280, 224), Color("b6c1a7"))
	draw_rect(Rect2(291, 232, 81, 28), Color("e7d9b4"))
	if model.phase == Model.Phase.READY:
		Art.plate(self, Vector2(332, 245), true)
	_counter(Vector2(96, 474), Color("91b1a4"))
	draw_rect(Rect2(110, 480, 76, 31), Color("536f67"))
	draw_rect(Rect2(117, 485, 62, 20), Color("84a49b"))
	draw_rect(Rect2(157, 464, 6, 23), Color("d9e0cb"))
	draw_rect(Rect2(144, 464, 19, 6), Color("d9e0cb"))
	# Table and chair.
	draw_rect(Rect2(530, 343, 96, 54), Color("6f725755"))
	draw_rect(Rect2(534, 376, 10, 24), Color("785540"))
	draw_rect(Rect2(603, 376, 10, 24), Color("785540"))
	draw_rect(Rect2(526, 330, 96, 55), Color("946d49"))
	draw_rect(Rect2(526, 330, 96, 45), Color("ce9f65"))
	draw_rect(Rect2(532, 336, 84, 32), Color("dcb67c"))
	draw_rect(Rect2(636, 350, 31, 32), Color("a4774d"))
	draw_rect(Rect2(640, 347, 26, 25), Color("c69a65"))
	draw_rect(Rect2(661, 338, 8, 44), Color("916341"))
	if model.phase in [Model.Phase.EATING, Model.Phase.LEAVING, Model.Phase.DIRTY]:
		Art.plate(self, Vector2(574, 350), model.phase == Model.Phase.EATING)
	_plant(Vector2(84, 604))
	_plant(Vector2(722, 242))
	for key: String in TARGETS:
		var point: Vector2 = TARGETS[key]
		var active := key == nearest
		var color := Color("fff0b2") if active else Color("8e987466")
		draw_rect(Rect2(point + Vector2(-17, -5), Vector2(34, 10)), color, false, 2.0)
		if active:
			draw_rect(Rect2(point + Vector2(-4, 9), Vector2(8, 3)), GOLD)


func _counter(at: Vector2, top: Color) -> void:
	draw_rect(Rect2(at + Vector2(3, 10), Vector2(105, 54)), Color("67684644"))
	draw_rect(Rect2(at, Vector2(104, 56)), Color("77654e"))
	draw_rect(Rect2(at, Vector2(104, 42)), top)
	draw_rect(Rect2(at + Vector2(8, 45), Vector2(39, 8)), Color("a59169"))
	draw_rect(Rect2(at + Vector2(56, 45), Vector2(39, 8)), Color("a59169"))


func _plant(at: Vector2) -> void:
	draw_rect(Rect2(at + Vector2(-12, -3), Vector2(24, 19)), Color("a77352"))
	draw_rect(Rect2(at + Vector2(-16, -9), Vector2(32, 9)), Color("cf9b67"))
	draw_rect(Rect2(at + Vector2(-3, -32), Vector2(6, 27)), Color("4b7554"))
	draw_rect(Rect2(at + Vector2(-19, -31), Vector2(18, 14)), Color("6b915d"))
	draw_rect(Rect2(at + Vector2(0, -40), Vector2(17, 20)), Color("5c8655"))
	draw_rect(Rect2(at + Vector2(-12, -47), Vector2(14, 17)), Color("86a76e"))
