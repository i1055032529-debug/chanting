extends SceneTree

const Rules = preload("res://scripts/cooking/cooking_model.gd")
const Bot = preload("res://tests/cooking_bot.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var rules := Rules.new()
	rules.advance(3.0, true)
	check(rules.elapsed == 0.0, "instruction screen does not cook before start")
	check(rules.start(), "can start once")
	check(not rules.start(), "starting twice cannot reset progress")
	check(not rules.plate(), "raw food cannot be plated")
	rules.advance(1.0, false)
	check(is_equal_approx(rules.temperature, 25.0) and rules.doneness == 0.0, "cold idle cannot cook food")
	check(rules.stir() == "cold", "cold stirring does not boost progress")
	rules.advance(1.5, true)
	var before: float = rules.doneness
	check(rules.stir() == "early", "early stirring is not rewarded")
	check(is_equal_approx(before, rules.doneness), "mashing gives no doneness bonus")
	check(rules.stir() == "ignored", "stirring is rate limited")
	var skilled: Dictionary = Bot.finish(Rules.new())
	var conservative: Dictionary = Bot.finish(Rules.new(), 60.0, 98.0, 0.67)
	var early: Dictionary = Bot.finish(Rules.new(), 88.0, 80.0)
	var spam: Dictionary = Bot.finish(Rules.new(), 88.0, 98.0, 0.8, 1.0 / 120.0, true)
	check(skilled.success and conservative.success, "skilled and conservative styles can both finish")
	check(skilled.seconds < conservative.seconds, "controlled high heat and accurate stirring finish faster")
	check(skilled.score > conservative.score, "accurate stirring improves quality")
	check(skilled.grade == "出色" and Rules.bonus_for_result(skilled) == 6, "excellent cooking earns the best bonus")
	check(early.seconds < skilled.seconds and early.score < skilled.score, "early plating trades quality for speed")
	check(not spam.success or spam.score < skilled.score, "mashing cannot outperform accurate play")
	check(early.doneness >= 80.0, "successful dish meets minimum doneness")
	var unattended := Rules.new()
	unattended.start()
	unattended.advance(45.0, true)
	check(unattended.state == Rules.State.RESULT and not unattended.result.success, "unattended full heat fails safely")
	check(unattended.burn == Rules.BURN_LIMIT and unattended.temperature <= 120.0, "burn and temperature are bounded")
	var timed := Rules.new()
	timed.start()
	timed.advance(46.0, false)
	check(timed.state == Rules.State.RESULT and not timed.result.success, "idle cooking times out rather than trapping player")
	check(timed.result.reason == "烹饪超时", "timeout has explicit reason")
	var done := Rules.new()
	var events := [0]
	done.finished.connect(func(_result: Dictionary): events[0] += 1)
	Bot.finish(done)
	var snapshot := done.result.duplicate(true)
	done.advance(100.0, true)
	done.stir()
	check(not done.plate() and events[0] == 1, "result can only be finalized once")
	check(done.result == snapshot, "completed result is stable")
	for fps in [30.0, 60.0, 120.0]:
		var sample: Dictionary = Bot.finish(Rules.new(), 88.0, 98.0, 0.80, 1.0 / fps)
		check(sample.success and sample.grade == skilled.grade, "frame rate preserves quality at %d FPS" % fps)
		check(absf(sample.seconds - skilled.seconds) < 0.25, "frame rate preserves completion time")
	print("PLAY BALANCE: skilled %.2fs/%d points; conservative %.2fs/%d; early %.2fs/%d; spam success=%s score=%d" % [skilled.seconds, skilled.score, conservative.seconds, conservative.score, early.seconds, early.score, spam.success, spam.score])
	print("COOKING RULES: %d checks, %d failures." % [checks, failures])
	quit(1 if failures else 0)
