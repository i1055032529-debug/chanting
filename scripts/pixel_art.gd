class_name PixelArt
extends RefCounted
## Small original, code-drawn pixel placeholders; no external assets required.

static func box(canvas: CanvasItem, at: Vector2, size: Vector2, color: Color) -> void:
	canvas.draw_rect(Rect2(at.round(), size), color)


static func person(canvas: CanvasItem, at: Vector2, shirt: Color, chef: bool, direction: Vector2, walking: bool, time: float) -> void:
	var step := 2.0 if walking and sin(time * 12.0) > 0.0 else 0.0
	box(canvas, at + Vector2(-12, -3), Vector2(24, 6), Color("393d3866"))
	box(canvas, at + Vector2(-8, -12 - step), Vector2(6, 12), Color("303f46"))
	box(canvas, at + Vector2(2, -12 + step), Vector2(6, 12), Color("303f46"))
	box(canvas, at + Vector2(-11, -30), Vector2(22, 20), shirt)
	box(canvas, at + Vector2(-15, -26), Vector2(5, 14), Color("d6a17c"))
	box(canvas, at + Vector2(10, -26), Vector2(5, 14), Color("d6a17c"))
	box(canvas, at + Vector2(-9, -47), Vector2(18, 19), Color("edbb90"))
	box(canvas, at + Vector2(-10, -48), Vector2(20, 6), Color("493f39"))
	if direction.y >= 0:
		var eye_x := 2.0 * signf(direction.x)
		box(canvas, at + Vector2(-5 + eye_x, -38), Vector2(3, 3), Color("343e3c"))
		box(canvas, at + Vector2(3 + eye_x, -38), Vector2(3, 3), Color("343e3c"))
	if chef:
		box(canvas, at + Vector2(-12, -57), Vector2(24, 12), Color("f5f0db"))
		box(canvas, at + Vector2(-7, -61), Vector2(14, 6), Color("fff8e6"))
		box(canvas, at + Vector2(-7, -28), Vector2(14, 16), Color("f5f0db"))
	else:
		box(canvas, at + Vector2(-11, -50), Vector2(22, 8), Color("714937"))


static func plate(canvas: CanvasItem, at: Vector2, food: bool) -> void:
	box(canvas, at + Vector2(-17, -5), Vector2(34, 10), Color("d5dccf"))
	box(canvas, at + Vector2(-12, -8), Vector2(24, 14), Color("fff6dc"))
	if food:
		box(canvas, at + Vector2(-10, -7), Vector2(20, 10), Color("d99c50"))
		box(canvas, at + Vector2(-6, -9), Vector2(14, 9), Color("fff8d9"))
		box(canvas, at + Vector2(-1, -8), Vector2(6, 6), Color("f4bc4f"))
		box(canvas, at + Vector2(-10, 0), Vector2(4, 4), Color("67965a"))
	else:
		box(canvas, at + Vector2(-5, -3), Vector2(7, 3), Color("af956e"))
		box(canvas, at + Vector2(5, 1), Vector2(3, 3), Color("8b9b62"))
