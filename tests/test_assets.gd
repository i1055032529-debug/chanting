extends SceneTree

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
	var paths := ["backgrounds/restaurant.webp", "backgrounds/tiles/floor.png", "backgrounds/tiles/wall.png", "backgrounds/tiles/border.png", "characters/chef.png", "characters/customer.png", "furniture/stove.png", "furniture/serving_counter.png", "furniture/cash_register_counter.png", "furniture/sink.png", "furniture/table.png", "furniture/chair.png", "items/meal.png"]
	var total := 0
	for relative: String in paths:
		var path := "res://assets/" + relative
		var file := FileAccess.open(path, FileAccess.READ)
		check(file != null, "asset exists: " + relative)
		if file == null: continue
		var bytes := file.get_length()
		total += bytes
		check(bytes < 400000, "asset below 400 KB: " + relative)
		var texture := load(path) as Texture2D
		check(texture != null, "Godot imports texture: " + relative)
		if texture == null: continue
		var image := texture.get_image()
		if relative == "backgrounds/restaurant.webp":
			check(image.get_size() == Vector2i(1216, 521), "background preserves complete wide composition")
		elif relative.begins_with("backgrounds/tiles"):
			var expected := Vector2i(80, 80) if relative.ends_with("floor.png") else Vector2i(80, 130) if relative.ends_with("wall.png") else Vector2i(80, 16)
			check(image.get_size() == expected, "room tile imports at expected cell size: " + relative)
		else:
			check(image.detect_alpha() != Image.ALPHA_NONE, "sprite retains alpha: " + relative)
			check(image.get_pixel(0, 0).a < 0.01, "sprite corner is transparent: " + relative)
	for index in range(1, 6):
		var floor := load("res://assets/backgrounds/tiles/floor_tile_%d.png" % index) as Texture2D
		check(floor != null and Vector2i(floor.get_size()) == Vector2i(64, 64), "floor picture is exactly 64x64: %d" % index)
	var low_resolution_assets := {
		"backgrounds/tiles/wall_32.png": Vector2i(32, 65),
		"backgrounds/tiles/border_32.png": Vector2i(32, 8),
		"backgrounds/restaurant_wall_32.png": Vector2i(608, 65),
		"furniture/table_32.png": Vector2i(64, 32),
		"furniture/chair_32.png": Vector2i(28, 35),
		"furniture/stove_32.png": Vector2i(64, 48),
		"furniture/sink_32.png": Vector2i(64, 48),
		"furniture/serving_counter_32.png": Vector2i(64, 48),
		"furniture/cash_register_counter_32.png": Vector2i(64, 19),
		"characters/chef_32.png": Vector2i(128, 176),
		"characters/customer_32.png": Vector2i(128, 176),
		"items/meal_32.png": Vector2i(40, 14),
		"recipes/dishes_32.png": Vector2i(128, 128),
		"ui/wood_board_32.png": Vector2i(112, 36),
	}
	for relative: String in low_resolution_assets:
		var path: String = "res://assets/" + relative
		var asset := load(path) as Texture2D
		check(asset != null and Vector2i(asset.get_size()) == low_resolution_assets[relative], "32-pixel art size: " + relative)
		check(FileAccess.get_file_as_bytes(path).size() < 400000, "32-pixel art below 400 KB: " + relative)
	check(FileAccess.get_file_as_bytes("res://assets/furniture/cash_register_counter.png").size() < 30000, "cash counter sprite stays below 30 KB")
	for relative in ["ui/wood_board.png"]:
		var path: String = "res://assets/" + relative
		check(FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() < 400000, "pixel sign fits the image budget: " + relative)
		check(load(path) is Texture2D, "Godot imports pixel sign: " + relative)
	for character: String in ["chef", "customer"]:
		var frames := load("res://assets/characters/%s_frames_32.tres" % character) as SpriteFrames
		for facing: String in ["down", "up", "left", "right"]:
			for activity: String in ["idle", "walk", "carry", "work"]:
				var animation := activity + "_" + facing
				check(frames.has_animation(animation), "animation exists: " + character + "/" + animation)
				check(frames.get_frame_count(animation) > 0, "animation is not empty")
	for key in ["stove", "pass", "sink", "table"]:
		var scene := load("res://scenes/furniture/%s.tscn" % key) as PackedScene
		var station := scene.instantiate()
		root.add_child(station)
		check(station.get_node("Sprite2D").texture != null, "furniture image assigned")
		check(station.get_node("CollisionShape2D").shape != null, "furniture collider assigned")
		var before: Vector2 = station.interaction_position()
		station.position += Vector2(73, 41)
		check(station.interaction_position().is_equal_approx(before + Vector2(73, 41)), "interaction follows furniture placement")
		station.queue_free()
	await process_frame
	print("IMAGE ASSETS: %d checks, %d failures; %d assets, %d bytes total." % [checks, failures, paths.size(), total])
	quit(1 if failures else 0)
