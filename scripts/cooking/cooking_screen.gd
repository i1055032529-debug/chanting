extends Control
## Dedicated cooking screen. Owns input/UI, never edits restaurant inventory/money.

signal completed(result: Dictionary)
signal abandoned
signal pause_requested

const Rules = preload("res://scripts/cooking/cooking_model.gd")
const Meter = preload("res://scripts/cooking/cooking_meter.gd")
const CREAM := Color("f2e5c8")
const MUTED := Color("b5ac95")
const GOLD := Color("edc476")
const GREEN := Color("8bb98a")
const RED := Color("e59172")

var rules := Rules.new()
var order_id := 0
var recipe_id := "rice"
var recipe_name := "香煎蛋饭"
var recipe_speed := 1.0
var heating := false
var active := true
var feedback_left := 0.0
var labels: Dictionary = {}
var meters: Dictionary = {}
var intro: Panel
var summary: Panel
var summary_title: Label
var summary_text: Label
var summary_button: Button
var plate_button: Button
@onready var pan: Node2D = $PanVisual


func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	rules.recipe_speed = recipe_speed
	rules.recipe_id = recipe_id
	_build_ui()
	_connect_rules()
	_refresh()


func _connect_rules() -> void:
	pan.cooking = rules
	rules.feedback.connect(_feedback)
	rules.finished.connect(_finish)


func start_round() -> void:
	if not active: return
	if rules.state == Rules.State.RESULT:
		rules = Rules.new()
		rules.recipe_speed = recipe_speed
		rules.recipe_id = recipe_id
		_connect_rules()
	if not rules.start(): return
	intro.hide()
	summary.hide()
	heating = false
	feedback_left = 0.0
	_refresh()


func _process(delta: float) -> void:
	if not active: return
	rules.advance(delta, heating)
	pan.heating = heating and rules.state == Rules.State.RUNNING
	feedback_left = maxf(0.0, feedback_left - delta)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		heating = false
		if is_inside_tree() and active and rules.state == Rules.State.RUNNING and not get_tree().paused:
			pause_requested.emit()


func _input(event: InputEvent) -> void:
	if not active or not event is InputEventKey or event.is_echo(): return
	if event.is_action("cook_heat"):
		if event.is_pressed() and rules.state == Rules.State.READY: start_round()
		heating = event.is_pressed() and rules.state == Rules.State.RUNNING
		get_viewport().set_input_as_handled()
	elif event.is_pressed():
		if event.is_action_pressed("cook_stir"):
			_stir()
		elif event.is_action_pressed("cook_plate"):
			if rules.state == Rules.State.RESULT: acknowledge()
			else: rules.plate()
		elif event.is_action_pressed("cook_back"):
			abandon()
		elif event.is_action_pressed("pause_game"):
			return # Shared always-active pause handler owns Escape.
		# Consume restaurant movement, debug keys and interaction while in the kitchen.
		get_viewport().set_input_as_handled()


func _stir() -> void:
	var hit: String = rules.stir()
	if hit in ["good", "perfect"]: pan.toss = 0.45


func acknowledge() -> void:
	if not active or rules.state != Rules.State.RESULT: return
	if not rules.result.success:
		start_round()
		return
	active = false
	heating = false
	completed.emit(rules.result.duplicate(true))


func abandon() -> void:
	if not active: return
	active = false
	heating = false
	abandoned.emit()


func clear_heat() -> void:
	heating = false
	pan.heating = false


func _feedback(message: String, good: bool) -> void:
	labels.feedback.text = message
	labels.feedback.add_theme_color_override("font_color", GREEN if good else RED)
	feedback_left = 1.5


func _finish(value: Dictionary) -> void:
	heating = false
	summary.show()
	summary_title.text = "%s  /  %d 分" % [value.grade, value.score] if value.success else value.grade
	var bonus: int = Rules.bonus_for_result(value)
	summary_text.text = "用时 %.1f 秒    熟度 %.1f    焦糊 %.1f\n\n完美翻炒 %d 次  ·  成功翻炒 %d 次  ·  漏炒 %d 次\n\n%s" % [value.seconds, value.doneness, value.burn, value.perfects, value.goods, value.misses, ("本单品质奖励 +%d 金币，顾客付款时结算。\n返回餐厅后，到出餐台取餐。" % bonus) if value.success else "这次没有成品，订单仍保留。\n可以立即重做，或返回餐厅再试。"]
	if value.reason == "烹饪超时": summary_text.text += "\n已达到 45 秒上限，自动结束本次烹饪。"
	summary_button.text = "返回餐厅，准备上菜  ·  E" if value.success else "再试一次  ·  E"
	_refresh()


func _refresh() -> void:
	if labels.is_empty(): return
	labels.timer.text = "%05.1f 秒" % rules.elapsed
	labels.temperature.text = "%03d" % roundi(rules.temperature)
	labels.doneness.text = "%05.1f" % rules.doneness
	labels.burn.text = "%04.1f / 75" % rules.burn
	labels.hits.text = "完美 %d  ·  成功 %d  ·  漏炒 %d" % [rules.perfects, rules.goods, rules.misses]
	meters.temperature.value = rules.temperature
	meters.doneness.value = rules.doneness
	meters.burn.value = rules.burn
	meters.stir.value = rules.stir_progress
	for meter in meters.values(): meter.queue_redraw()
	if feedback_left <= 0.0:
		labels.feedback.add_theme_color_override("font_color", CREAM)
		if rules.temperature > 94.0:
			labels.feedback.text = "锅温偏高！松开空格降温，别忘了翻炒。"
			labels.feedback.add_theme_color_override("font_color", RED)
		elif rules.doneness >= 95.0:
			labels.feedback.text = "已经很香了，按 E 出锅，别让它过火！"
		elif rules.doneness >= Rules.MIN_DONENESS:
			labels.feedback.text = "现在可以出锅；继续接近熟度 98，争取更好品质。"
		elif rules.temperature < 65.0:
			labels.feedback.text = "按住空格升温；锅温 65–94 时，烹饪更高效。"
		else:
			labels.feedback.text = "保持锅温，游标进入亮色区时按 F 翻炒。"
	plate_button.disabled = rules.state != Rules.State.RUNNING or rules.doneness < Rules.MIN_DONENESS
	plate_button.text = "E  出锅" if rules.doneness >= Rules.MIN_DONENESS else "E  出锅（熟度至少 80）"
	labels.fire.text = "正在加热" if heating else "离火降温"
	labels.fire.add_theme_color_override("font_color", GOLD if heating else MUTED)


func _build_ui() -> void:
	_label("eyebrow", "厨房  /  %s  /  订单 #%03d" % [recipe_name, order_id], Vector2(38, 24), Vector2(760, 24), 14, MUTED)
	_label("title", "掌勺时间", Vector2(33, 57), Vector2(400, 56), 38, CREAM)
	_label("subtitle", "控好火，翻得准，让一份热饭更快出锅。", Vector2(38, 119), Vector2(700, 28), 17, MUTED)
	_label("world", "餐厅继续营业", Vector2(766, 51), Vector2(308, 106), 14, GREEN)
	_button(self, "暂停  ·  Esc", Rect2(1088, 26, 160, 42), func(): pause_requested.emit())
	_label("dish", recipe_name, Vector2(54, 184), Vector2(320, 28), 20, CREAM)
	_label("timer", "00.0 秒", Vector2(665, 184), Vector2(128, 30), 22, GOLD)
	_label("fire", "离火降温", Vector2(54, 230), Vector2(200, 25), 14, MUTED)
	_label("feedback", "", Vector2(54, 571), Vector2(720, 31), 16, CREAM)
	_panel(Rect2(824, 166, 424, 445), Color("292a21"))
	_label("temp_label", "锅温  /  65–94 高效区", Vector2(846, 189), Vector2(270, 28), 17, CREAM)
	_label("temperature", "035", Vector2(1157, 186), Vector2(76, 32), 24, GOLD)
	_meter("temperature", Rect2(846, 232, 376, 20), 120.0, [[65.0/120, 94.0/120, Color("557452")], [94.0/120, 1.0, Color("8f4932")]])
	_label("done_label", "熟度  /  80 可出锅", Vector2(846, 279), Vector2(260, 28), 17, CREAM)
	_label("doneness", "000.0", Vector2(1140, 276), Vector2(94, 32), 24, GOLD)
	_meter("doneness", Rect2(846, 322, 376, 20), 130.0, [[80.0/130, 95.0/130, Color("496149")], [95.0/130, 104.0/130, Color("b08b48")], [104.0/130, 1.0, Color("76452f")]])
	_label("burn_label", "焦糊  /  越少越好", Vector2(846, 369), Vector2(240, 28), 17, CREAM)
	_label("burn", "00.0 / 75", Vector2(1114, 370), Vector2(130, 32), 21, RED)
	_meter("burn", Rect2(846, 412, 376, 15), 75.0, [])
	meters.burn.tint = RED
	_label("hits", "", Vector2(846, 468), Vector2(384, 27), 16, MUTED)
	_label("quality", "优质目标：熟度 95–104，少焦糊。\n准确翻炒既能提速，也能提升品质。\n温度过高、漏炒和过熟都会损失品质。", Vector2(846, 515), Vector2(378, 81), 15, MUTED)
	_panel(Rect2(32, 629, 1216, 139), Color("30281e"))
	_label("stir_title", "翻炒时机", Vector2(54, 646), Vector2(160, 30), 19, CREAM)
	_label("stir_hint", "进入绿色区按 F，金色区为完美翻炒。乱按不会加速。", Vector2(218, 641), Vector2(780, 30), 15, MUTED)
	_meter("stir", Rect2(218, 681, 760, 17), 1.0, [[Rules.GOOD_START, Rules.GOOD_END, Color("668b60")], [Rules.PERFECT_START, Rules.PERFECT_END, GOLD]])
	meters.stir.pointer = true
	_button(self, "F  翻炒", Rect2(1014, 661, 208, 43), _stir)
	var heat_button := _button(self, "按住空格加热 / 松开降温", Rect2(54, 719, 368, 36), func(): pass)
	heat_button.button_down.connect(func():
		if rules.state == Rules.State.READY: start_round()
		heating = rules.state == Rules.State.RUNNING)
	heat_button.button_up.connect(clear_heat)
	plate_button = _button(self, "E  出锅", Rect2(438, 719, 376, 36), func(): rules.plate())
	_button(self, "返回餐厅，放弃本次  ·  B", Rect2(830, 719, 392, 36), abandon)
	intro = _panel(Rect2(265, 236, 750, 338), Color("24281f"))
	_child_label(intro, "热锅开炒", Vector2(36, 25), Vector2(660, 45), 30, GOLD)
	_child_label(intro, "按住空格加热，松开降温。\n看下方游标：绿色区按 F 翻炒，金色区更好。\n熟度达到 80 可按 E 出锅，95–104 品质更佳。\n动作准确，就能更快做熟；锅温太高则容易焦。", Vector2(36, 88), Vector2(678, 144), 19, CREAM)
	_button(intro, "开始烹饪  ·  空格", Rect2(36, 265, 678, 47), start_round)
	summary = _panel(Rect2(286, 210, 708, 415), Color("24281f"))
	summary.hide()
	summary_title = _child_label(summary, "", Vector2(34, 23), Vector2(640, 48), 31, GOLD)
	summary_text = _child_label(summary, "", Vector2(34, 91), Vector2(640, 210), 18, CREAM)
	summary_button = _button(summary, "", Rect2(34, 314, 640, 49), acknowledge)
	_button(summary, "放弃本次，返回餐厅  ·  B", Rect2(34, 373, 640, 30), abandon)


func _meter(key: String, rect: Rect2, maximum: float, zones: Array) -> void:
	var meter := Meter.new()
	meter.position = rect.position
	meter.size = rect.size
	meter.maximum = maximum
	meter.zones = zones
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(meter)
	meters[key] = meter


func _panel(rect: Rect2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel


func _label(key: String, text: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := _child_label(self, text, at, dimensions, font_size, color)
	labels[key] = label
	return label


func _child_label(parent: Node, text: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	for entry in [["normal", Color("5d5035")], ["hover", Color("796346")], ["pressed", Color("947446")], ["disabled", Color("302e24")]]:
		var style := StyleBoxFlat.new()
		style.bg_color = entry[1]
		button.add_theme_stylebox_override(entry[0], style)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
