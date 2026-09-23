class_name CookingModel
extends RefCounted
## Pure cooking rules. Visuals/input can be replaced without changing scoring.

signal feedback(message: String, good: bool)
signal finished(result: Dictionary)

enum State { READY, RUNNING, RESULT }
const MAX_SECONDS := 45.0
const MIN_DONENESS := 80.0
const BURN_LIMIT := 75.0
const GOOD_START := 0.65
const GOOD_END := 0.94
const PERFECT_START := 0.76
const PERFECT_END := 0.86
const FIXED_STEP := 1.0 / 120.0

var state: State = State.READY
var temperature := 35.0
var doneness := 0.0
var burn := 0.0
var elapsed := 0.0
var stir_progress := 0.0
var stir_cooldown := 0.0
var attempts := 0
var perfects := 0
var goods := 0
var misses := 0
var result: Dictionary = {}


func start() -> bool:
	if state != State.READY: return false
	state = State.RUNNING
	return true


func advance(delta: float, heating: bool) -> void:
	if state != State.RUNNING or delta <= 0.0: return
	var remaining := delta
	while remaining > 0.000001 and state == State.RUNNING:
		var step := minf(remaining, FIXED_STEP)
		_tick(step, heating)
		remaining -= step


func _tick(delta: float, heating: bool) -> void:
	elapsed += delta
	stir_cooldown = maxf(0.0, stir_cooldown - delta)
	temperature = clampf(temperature + (38.0 if heating else -22.0) * delta, 25.0, 120.0)
	doneness += clampf((temperature - 35.0) / 65.0, 0.0, 1.35) * 10.0 * delta
	burn += maxf(temperature - 94.0, 0.0) * 0.32 * delta
	if temperature > 45.0:
		stir_progress += (0.25 + temperature / 230.0) * delta
		if stir_progress >= 1.0:
			stir_progress = 0.0
			misses += 1
			burn += 4.0 + maxf(temperature - 85.0, 0.0) * 0.25
			feedback.emit("错过翻炒，食物开始粘锅。", false)
	if doneness > 104.0:
		burn += (doneness - 104.0) * 0.22 * delta
	if burn >= BURN_LIMIT:
		burn = BURN_LIMIT
		_finish(false, "烧焦了", false)
	elif elapsed >= MAX_SECONDS:
		_finish(doneness >= MIN_DONENESS, "烹饪超时", true)


func stir() -> String:
	if state != State.RUNNING or stir_cooldown > 0.0: return "ignored"
	stir_cooldown = 0.25
	if temperature <= 45.0:
		feedback.emit("锅还没热，先按住空格加热。", false)
		return "cold"
	attempts += 1
	var hit := "early"
	if stir_progress >= PERFECT_START and stir_progress <= PERFECT_END:
		perfects += 1
		doneness += 12.0
		temperature = maxf(25.0, temperature - 9.0)
		feedback.emit("漂亮！熟度 +12，锅温下降。", true)
		hit = "perfect"
	elif stir_progress >= GOOD_START and stir_progress <= GOOD_END:
		goods += 1
		doneness += 8.0
		temperature = maxf(25.0, temperature - 6.0)
		feedback.emit("翻炒成功，熟度 +8。", true)
		hit = "good"
	else:
		burn += 1.5
		hit = "early" if stir_progress < GOOD_START else "late"
		feedback.emit("太早了，等游标进入亮色区再翻炒。" if hit == "early" else "慢了一点，留意下一次时机。", false)
	stir_progress = 0.0
	if burn >= BURN_LIMIT:
		burn = BURN_LIMIT
		_finish(false, "烧焦了", false)
	return hit


func plate() -> bool:
	if state != State.RUNNING: return false
	if doneness < MIN_DONENESS:
		feedback.emit("还没熟：熟度至少达到 80 才能出锅。", false)
		return false
	_finish(true, "主动出锅", false)
	return true


func _finish(success: bool, reason: String, timed_out: bool) -> void:
	if state != State.RUNNING: return
	state = State.RESULT
	var accuracy := (perfects + goods * 0.65) / maxf(1.0, attempts + misses)
	var completion := clampf(100.0 - absf(doneness - 98.0) * 1.6, 0.0, 100.0)
	var score := clampi(roundi(completion * 0.60 + accuracy * 40.0 - burn * 0.65 - maxf(0.0, doneness - 104.0) * 2.0 - (15.0 if timed_out else 0.0)), 0, 100)
	var grade := "需要再练练"
	if success:
		grade = "合格"
		if score >= 85 and doneness >= 95.0 and doneness <= 104.0 and burn <= 12.0: grade = "出色"
		elif score >= 65: grade = "美味"
		elif burn >= 20.0 or doneness > 110.0: grade = "偏焦"
	else:
		grade = "烧焦了" if burn >= BURN_LIMIT else "未完成"
	result = {"success": success, "reason": reason, "score": score, "grade": grade, "doneness": doneness, "burn": burn, "seconds": elapsed, "perfects": perfects, "goods": goods, "misses": misses, "attempts": attempts}
	finished.emit(result.duplicate(true))


static func bonus_for_result(value: Dictionary) -> int:
	if not value.get("success", false): return 0
	if value.get("score", 0) >= 85 and value.get("doneness", 0.0) >= 95.0 and value.get("doneness", 0.0) <= 104.0 and value.get("burn", 100.0) <= 12.0: return 6
	if value.get("score", 0) >= 65: return 2
	return 0
