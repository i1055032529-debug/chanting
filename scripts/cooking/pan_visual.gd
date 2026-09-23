extends Node2D
## Pixel placeholder view only. Later replace with sprites at the same scene node.

var cooking: RefCounted
var heating := false
var toss := 0.0
var time := 0.0


func _process(delta: float) -> void:
	time += delta
	toss = maxf(0.0, toss - delta)
	queue_redraw()


func _box(x: float, y: float, width: float, height: float, color: String) -> void:
	draw_rect(Rect2(roundf(x), roundf(y), width, height), Color(color))


func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	for y in range(-int(radius.y), int(radius.y) + 1, 2):
		var width := floorf(radius.x * sqrt(maxf(0.0, 1.0 - pow(float(y) / radius.y, 2.0))))
		draw_rect(Rect2(center.x - width, center.y + y, width * 2, 2), color)


func _draw() -> void:
	var heat: float = cooking.temperature if cooking else 35.0
	var done: float = cooking.doneness if cooking else 0.0
	var charred: float = cooking.burn if cooking else 0.0
	var noodles: bool = cooking != null and cooking.recipe_id == "noodles"
	# Counter and stove: deliberately coarse 3x pixels, independently replaceable.
	_box(6, 96, 224, 34, "493324")
	for x in range(6, 229, 28): _box(x, 96, 2, 34, "35291f")
	_box(44, 87, 148, 39, "776657")
	_box(48, 90, 140, 28, "a9987b")
	_box(49, 119, 137, 10, "403d38")
	_box(57, 122, 10, 5, "daba7e")
	_box(166, 122, 10, 5, "daba7e")
	_ellipse(Vector2(118, 91), Vector2(58, 14), Color("232827"))
	if heating:
		for i in range(9):
			var flame_h := 6 + int(heat / 15) + (i % 3) * 2 + int(sin(time * 15 + i) * 3)
			_box(75 + i * 10, 102 - flame_h, 6, flame_h, "db702f")
			_box(77 + i * 10, 107 - flame_h, 2, flame_h - 4, "f6c765")
	_box(164, 78, 59, 10, "2e302c")
	_box(186, 79, 40, 8, "936545")
	_box(192, 80, 30, 3, "c29867")
	_ellipse(Vector2(114, 68), Vector2(68, 32), Color("292e2d"))
	_ellipse(Vector2(114, 65), Vector2(66, 28), Color("6a7369"))
	_ellipse(Vector2(114, 64), Vector2(61, 25), Color("1c2525"))
	_ellipse(Vector2(114, 65), Vector2(55, 21), Color("3b3930"))
	var jump := sin(clampf(toss / 0.45, 0.0, 1.0) * PI) * 22.0
	var rice := (Color("ecc085") if noodles else Color("f1deb0")).lerp(Color("d9784c") if noodles else Color("dba24b"), clampf(done / 100.0, 0.0, 1.0)).lerp(Color("614330"), charred / 90.0)
	for i in range(46):
		var x := 73 + (i * 23) % 85
		var y := 50 + (i * 13) % 25
		var lift := jump * (0.5 + (i % 3) * 0.2)
		draw_rect(Rect2(x, roundf(y - lift), 5, 3), rice.lightened((i % 3) * 0.06))
		if i % 7 == 0: _box(x + 2, y - lift - 2, 3, 3, "b24735" if noodles else "769155")
	# Egg and spatula use the same low-resolution pixel coordinates.
	if noodles:
		for i in range(8): _box(88 + i * 9, 53 + (i % 3) * 5 - jump, 14, 3, "f4d092")
	else:
		_ellipse(Vector2(117, 61 - jump), Vector2(17, 9), Color("fff0c5"))
		_ellipse(Vector2(119, 60 - jump), Vector2(7, 5), Color("eab744"))
	_box(160, 44 - jump / 2, 12, 21, "bdb7a0")
	_box(164, 25 - jump / 2, 4, 23, "8e694a")
	if heat > 65.0:
		for i in range(5):
			var offset := fmod(time * 10 + i * 9, 31)
			var steam := Color("e5d6b4")
			steam.a = (1.0 - offset / 31.0) * 0.48
			draw_rect(Rect2(84 + i * 16, 43 - offset, 3, 6), steam)
