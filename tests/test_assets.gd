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
	var paths := ["backgrounds/restaurant.webp", "backgrounds/tiles/floor.png", "backgrounds/tiles/wall.png", "backgrounds/tiles/border.png", "characters/chef.png", "characters/customer.png", "furniture/stove.png", "furniture/serving_counter.png", "furniture/sink.png", "furniture/table.png", "furniture/chair.png", "items/meal.png"]
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
	for character: String in ["chef", "customer"]:
		var frames := load("res://assets/characters/%s_frames.tres" % character) as SpriteFrames
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
