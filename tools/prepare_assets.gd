extends SceneTree
## Offline import utility: normalize generated PNGs, retain alpha, resize and compress.
## Usage: godot --headless --path . --script tools/prepare_assets.gd -- /path/manifest.json

var failed := false
var report: Array[Dictionary] = []


func _initialize() -> void:
	_prepare.call_deferred()


func _prepare() -> void:
	DirAccess.make_dir_recursive_absolute("res://test-results")
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Provide source manifest JSON: background plus optional asset source paths.")
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if manifest.has("background"):
		var background := Image.load_from_file(manifest.background)
		background.resize(1216, 521, Image.INTERPOLATE_NEAREST)
		var destination := "res://assets/backgrounds/restaurant.webp"
		background.save_webp(destination, false)
		if FileAccess.open(destination, FileAccess.READ).get_length() >= 390000:
			background.save_webp(destination, true, 0.90)
		_record(destination, background)
	for key: String in manifest:
		if key == "background": continue
		var source := Image.load_from_file(manifest[key])
		if source == null:
			push_error("Could not load: " + key)
			failed = true
			continue
		source.convert(Image.FORMAT_RGBA8)
		if not source.is_invisible() and source.detect_alpha() == Image.ALPHA_NONE:
			push_error(key + " has no transparency; regenerate asset with alpha.")
			failed = true
			continue
		if key in ["chef", "customer"]:
			_character(source, key)
		elif key == "meal":
			_meal(source)
		else:
			var size := Vector2i(128, 96)
			if key == "table": size = Vector2i(128, 90)
			elif key == "chair": size = Vector2i(56, 70)
			var fitted := _fit(source, size, size - Vector2i(4, 4))
			_save("res://assets/furniture/" + key + ".png", fitted)
	var file := FileAccess.open("res://test-results/asset-import-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))
	quit(1 if failed else 0)


func _bands(source: Image, horizontal: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var length := source.get_height() if horizontal else source.get_width()
	var breadth := source.get_width() if horizontal else source.get_height()
	var start := -1
	var last := -1
	for i in range(length):
		var count := 0
		for j in range(breadth):
			var alpha := source.get_pixel(j, i).a if horizontal else source.get_pixel(i, j).a
			if alpha > 0.15: count += 1
		var occupied := count >= maxi(3, int(breadth * 0.003))
		if occupied:
			if start < 0: start = i
			last = i
		elif start >= 0 and i - last > 5:
			result.append(Vector2i(maxi(0, start - 2), mini(length, last + 3)))
			start = -1
	if start >= 0: result.append(Vector2i(maxi(0, start - 2), mini(length, last + 3)))
	return result


func _character(source: Image, key: String) -> void:
	var rows := _bands(source, true)
	if rows.size() != 4:
		push_error("Expected four character rows for %s, got %s" % [key, rows])
		failed = true
		return
	var output := Image.create(256, 352, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	for y in range(4):
		var strip := source.get_region(Rect2i(0, rows[y].x, source.get_width(), rows[y].y - rows[y].x))
		var columns := _bands(strip, false)
		if columns.size() != 4:
			push_error("Expected four character columns for %s row %d, got %s" % [key, y, columns])
			failed = true
			return
		for x in range(4):
			var frame := strip.get_region(Rect2i(columns[x].x, 0, columns[x].y - columns[x].x, strip.get_height()))
			frame = _fit(frame, Vector2i(64, 88), Vector2i(58, 82))
			output.blit_rect(frame, Rect2i(0, 0, 64, 88), Vector2i(x * 64, y * 88))
	_save("res://assets/characters/" + key + ".png", output)


func _meal(source: Image) -> void:
	var columns := _bands(source, false)
	if columns.size() != 2:
		push_error("Expected two meal state columns, got %s" % [columns])
		failed = true
		return
	var output := Image.create(80, 28, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	for x in range(2):
		var region := source.get_region(Rect2i(columns[x].x, 0, columns[x].y - columns[x].x, source.get_height()))
		var frame := _fit(region, Vector2i(40, 28), Vector2i(38, 24))
		output.blit_rect(frame, Rect2i(0, 0, 40, 28), Vector2i(x * 40, 0))
	_save("res://assets/items/meal.png", output)


func _fit(source: Image, canvas_size: Vector2i, maximum: Vector2i) -> Image:
	# Generative cutouts can contain almost invisible alpha far from the object.
	# Use a visible-alpha bound so those margins do not shrink or float the sprite.
	var used := _visible_bounds(source)
	var cropped := source.get_region(used)
	var ratio := minf(float(maximum.x) / used.size.x, float(maximum.y) / used.size.y)
	var size := Vector2i(maxi(1, roundi(used.size.x * ratio)), maxi(1, roundi(used.size.y * ratio)))
	cropped.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	var output := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	output.blit_rect(cropped, Rect2i(Vector2i.ZERO, size), Vector2i((canvas_size.x - size.x) / 2, canvas_size.y - size.y - 2))
	return output


func _visible_bounds(source: Image) -> Rect2i:
	var minimum := source.get_size()
	var maximum := Vector2i.ZERO
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			if source.get_pixel(x, y).a > 0.15:
				minimum.x = mini(minimum.x, x)
				minimum.y = mini(minimum.y, y)
				maximum.x = maxi(maximum.x, x)
				maximum.y = maxi(maximum.y, y)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)


func _save(path: String, image: Image) -> void:
	if image.save_png(path) != OK:
		push_error("Cannot save: " + path)
		failed = true
	_record(path, image)


func _record(path: String, image: Image) -> void:
	var bytes := FileAccess.open(path, FileAccess.READ).get_length()
	if bytes >= 400000:
		push_error("Asset exceeds 400 KB: " + path)
		failed = true
	report.append({"path": path, "width": image.get_width(), "height": image.get_height(), "bytes": bytes})
	print("ASSET %s: %dx%d, %d bytes" % [path, image.get_width(), image.get_height(), bytes])
