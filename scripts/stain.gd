extends Node2D
## Replaceable pixel stain marker with a proximity interaction.
var station_id := ""
var display_name := "地面污渍"
var pulse := 0.0

func interaction_position() -> Vector2:
	return global_position

func set_highlight(active: bool) -> void:
	modulate = Color("ffe4a2") if active else Color.WHITE

func _process(delta: float) -> void:
	pulse += delta
	queue_redraw()

func _draw() -> void:
	var color := Color("805c3c")
	draw_rect(Rect2(-16, -5, 30, 10), color)
	draw_rect(Rect2(-11, -9, 17, 18), color)
	draw_rect(Rect2(12, -2, 6, 5), color)
	draw_rect(Rect2(-20, 1, 5, 3), color)
	draw_rect(Rect2(-7, -5, 6, 5), Color("b27f4e"))
	if sin(pulse * 3.0) > 0.0:
		draw_rect(Rect2(-2, -14, 3, 3), Color("ead694"))
