extends SceneTree
const Day = preload("res://scripts/day_model.gd")
const Restaurant = preload("res://scenes/restaurant.tscn")
const RESULT := {"success": true, "doneness": 98.0, "burn": 0.0, "score": 90, "grade": "出色"}
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var model = Day.new()
	check(Day.RECIPE_IDS.size() == 4 and model.recipe_ingredients_text("rice") == "米饭×1 + 鸡蛋×1", "four recipes expose exact per-serving ingredients")
	var favorites: Dictionary = {}
	for id in range(1, 5):
		var choices: Array[String] = model.customer_preferences(id)
		check(choices.size() == 3 and choices[0] not in favorites, "each personality ranks three distinct dishes with a rotating favorite")
		favorites[choices[0]] = true
	check(favorites.size() == 4, "all four dishes can be a first choice")
	var original_chance := model.purchase_probability(1, "rice")
	check(model.set_menu_price("rice", 99) and model.purchase_probability(1, "rice") < original_chance and model.customer_preferences(1)[0] != "rice", "higher price reduces willingness and can change priority")
	check(not model.set_menu_price("rice", 100) and model.menu_prices.rice == 99, "menu price has a valid range")
	model.new_game()
	check(model.menu_prices.rice == 18, "new game resets menu prices")
	var fallback = Day.new()
	check(fallback.set_menu_enabled("rice", false) and fallback.start_day() and fallback.request_customer(), "unavailable first choice falls through to next dish")
	check(fallback.orders[1].recipe == "noodles" and fallback.orders[1].choice_rank == 1 and fallback.orders[1].satisfaction == 80, "fallback lowers satisfaction without inventing a fourth choice")
	var third = Day.new()
	third.next_order_id = 2
	third.set_menu_enabled("noodles", false)
	third.set_menu_enabled("tomato_egg", false)
	third.start_day()
	third.request_customer()
	check(third.orders[2].recipe == "rice" and third.orders[2].choice_rank == 2 and third.orders[2].satisfaction == 60, "third preference is selected with a larger satisfaction loss")
	var fixed = Day.new()
	fixed.set_menu_price("rice", 20)
	fixed.start_day()
	fixed.request_customer()
	check(fixed.orders[1].recipe == "rice" and fixed.orders[1].price == 20 and not fixed.set_menu_price("rice", 25), "accepted order snapshots its price and service locks changes")
	fixed.seat_customer(1)
	fixed.start_cooking()
	fixed.complete_cooking(1, fixed.orders[1].cook_attempt, RESULT)
	fixed.interact("pass")
	fixed.interact("table_1")
	fixed.advance(Day.EAT_SECONDS)
	check(fixed.payments == [26], "payment uses player-set price plus quality bonus")
	var priced = Day.new()
	priced.set_menu_price("rice", 21)
	priced.start_day()
	priced.advance(Day.DAY_SECONDS + Day.CLOSING_GRACE)
	check(priced.next_day() and priced.menu_prices.rice == 21, "player price persists into the next day")
	var game = Restaurant.instantiate()
	root.add_child(game)
	await process_frame
	game._toggle_store()
	check(game.store_labels["ingredients_egg_noodles"].text == "每份：面条×1 + 鸡蛋×1", "store shows complete recipe ingredients")
	game.store_labels["price_plus_rice"].pressed.emit()
	check(game.model.menu_prices.rice == 19 and game.store_labels["price_rice"].text == "19 金币", "store controls update dish price")
	for recipe_id: String in Day.RECIPE_IDS: game.model.set_menu_price(recipe_id, 99)
	game._toggle_store()
	game.start_day()
	check(game.model.request_customer() and game.model.browsers.has(1) and game.model.orders.is_empty(), "customer enters without a table when all offers are rejected")
	var browser = game.customers[1]
	browser._process(10.0)
	check(game.model.browsers[1].state == "browsing" and browser.thought.visible, "browsing customer shows an ellipsis above the head")
	game.model.advance(3.6)
	check(game.model.browsers[1].state == "leaving", "browsing customer leaves after a short display")
	browser._process(10.0)
	check(game.model.browsers.is_empty() and game.model.lost == 1 and game.model.bad_reviews == 1, "no-sale departure records lost customer once")
	print("CUSTOMER CHOICE: %d checks, %d failures." % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
