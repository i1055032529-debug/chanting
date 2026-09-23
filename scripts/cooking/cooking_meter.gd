extends Control
## Presentation-only meter; all limits and progress come from CookingModel.

var value := 0.0
var maximum := 100.0
var zones: Array = []
var tint := Color("e7b75e")
var pointer := false


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("1c1d18"))
	for zone: Array in zones:
		draw_rect(Rect2(size.x * zone[0], 0, size.x * (zone[1] - zone[0]), size.y), zone[2])
	var x := size.x * clampf(value / maximum, 0.0, 1.0)
	if pointer:
		draw_rect(Rect2(x - 2, -5, 4, size.y + 10), Color("fff0cd"))
	else:
		draw_rect(Rect2(0, size.y * 0.38, x, size.y * 0.24), tint)
		draw_rect(Rect2(x - 1, -3, 3, size.y + 6), tint)
