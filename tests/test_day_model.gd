extends SceneTree
const Day = preload("res://scripts/day_model.gd")
var checks := 0
var failures := 0
const RESULT := {"success": true, "doneness": 98.0, "burn": 0.0, "score": 92, "grade": "出色"}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func fill(model, count: int) -> void:
	for i in range(count):
		check(model.request_customer(), "customer reserves free table")
		check(model.seat_customer(model.next_order_id - 1), "reservation seats exactly once")

func active_day():
	var model = Day.new()
	model.start_day()
	return model

func _run() -> void:
	var model = active_day()
	fill(model, 4)
	check(not model.request_customer() and model.orders.size() == 4, "four table cap")
	check(model.tables == [1, 2, 3, 4], "each table reserved uniquely")
	check(model.orders[1].recipe == "rice" and model.orders[2].recipe == "noodles", "two recipe configuration")
	check(model.select_next() == 2, "player can cycle selected waiting order")
	check(model.start_cooking() and model.cooking_order_id == 2, "selected order owns stove")
	check(not model.start_cooking(), "stove cannot be double booked")
	var attempt: int = model.cooking_attempt_id
	check(not model.complete_cooking(1, attempt, RESULT), "wrong order cannot claim cooking")
	check(model.complete_cooking(2, attempt, RESULT), "correct result fills pass")
	check(not model.complete_cooking(2, attempt, RESULT), "completion cannot double fire")
	check(model.start_cooking(), "second stove can cook while first dish waits at pass")
	check(model.cooking_order_id == 1, "second stove selects another waiting order")
	check(model.complete_cooking(1, model.cooking_attempt_id, RESULT) and model.pass_order_ids == [2, 1], "both dishes can wait at pass")
	check(not model.start_cooking(), "two full pass positions block further cooking")
	check(model.interact("pass") and model.carrying == Day.Carry.FOOD, "take food from pass")
	check(not model.interact("table_1"), "wrong table rejects food")
	check(model.interact("table_2"), "correct table served")
	model.advance(Day.EAT_SECONDS)
	check(model.coins == 30 and model.served == 1, "noodle base and quality bonus paid once")
	model.advance(0.1)
	check(model.coins == 30, "payment idempotent")
	check(model.customer_departed(2) and model.orders[2].state == "dirty", "paid departure becomes dirty")
	check(model.interact("table_2") and model.interact("sink"), "plate recycling releases table")
	check(model.tables[1] == 0, "table reusable")
	var stale = active_day()
	fill(stale, 1)
	stale.start_cooking()
	var stale_attempt: int = stale.cooking_attempt_id
	stale.advance(Day.PATIENCE + 0.1)
	check(stale.lost >= 1 and stale.cooking_order_id == 0, "cooking timeout releases stove")
	check(not stale.complete_cooking(1, stale_attempt, RESULT), "expired result rejected")
	check(stale.customer_departed(1), "timed out customer exits")
	var ready = active_day()
	fill(ready, 1)
	ready.start_cooking()
	ready.complete_cooking(1, ready.cooking_attempt_id, RESULT)
	ready.advance(Day.PATIENCE + 0.1)
	check(ready.pass_order_id == 0 and ready.lost >= 1, "ready food cleared after timeout")
	var carried = active_day()
	fill(carried, 1)
	carried.start_cooking()
	carried.complete_cooking(1, carried.cooking_attempt_id, RESULT)
	carried.interact("pass")
	carried.advance(Day.PATIENCE + 0.1)
	check(carried.carrying == Day.Carry.NONE and carried.carried_order_id == 0, "held expired food is discarded")
	var cancel = active_day()
	fill(cancel, 1)
	cancel.start_cooking()
	var old_attempt: int = cancel.cooking_attempt_id
	check(cancel.cancel_cooking(1, old_attempt), "cancel returns order to waiting")
	check(cancel.start_cooking() and not cancel.complete_cooking(1, old_attempt, RESULT), "retry invalidates first attempt")
	cancel.reset()
	check(not cancel.complete_cooking(1, old_attempt, RESULT), "reset rejects old result")
	var day = active_day()
	fill(day, 1)
	day.start_cooking()
	day.complete_cooking(1, day.cooking_attempt_id, RESULT)
	day.interact("pass")
	day.interact("table_1")
	day.advance(Day.EAT_SECONDS)
	day.customer_departed(1)
	day.interact("table_1")
	day.interact("sink")
	day.advance(Day.DAY_SECONDS)
	check(day.day_closed and day.ended, "clean day closes automatically when all work is done")
	day.advance(Day.CLOSING_GRACE)
	check(day.ended and day.summary().served == 1, "day reaches summary after grace")
	var cleaning = active_day()
	fill(cleaning, 2)
	for id in [1, 2]:
		cleaning.selected_order_id = id
		cleaning.start_cooking()
		cleaning.complete_cooking(id, cleaning.cooking_attempt_id, RESULT)
		cleaning.interact("pass")
		cleaning.interact("table_%d" % id)
		cleaning.advance(Day.EAT_SECONDS)
		cleaning.customer_departed(id)
		cleaning.interact("table_%d" % id)
		cleaning.interact("sink")
	check(cleaning.stains.size() == 1, "two completed tables generate one bounded stain")
	check(cleaning.interact("stain_1") and cleaning.stains.is_empty(), "cleaning removes stain")
	var low = active_day()
	fill(low, 1)
	low.advance(Day.PATIENCE + 0.1)
	check(low.lost == 1 and low.bad_reviews >= 1 and low.summary().reason == "等餐超时", "lost customer has concrete review reason")
	print("DAY MODEL: %d checks, %d failures." % [checks, failures])
	quit(1 if failures else 0)
