extends Control

const PIXEL_SCALE := 3
const GLYPH_ADVANCE := 6
const ICON_GAP := 12
const TEXT_COLOR := Color("fff0c9")
const ICON_COLOR := Color("f5c66f")
const SHADOW_COLOR := Color("60351f")

const GLYPHS := {
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
	"6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
	":": ["00000", "00100", "00100", "00000", "00100", "00100", "00000"],
}
const CLOCK_ICON := ["0011100", "0100010", "1001001", "1001101", "1000101", "0100010", "0011100"]
const COIN_ICON := ["0011100", "0111110", "1100011", "1101011", "1100011", "0111110", "0011100"]

var _coins := -1
var _remaining_seconds := -1


func set_values(coins: int, remaining_seconds: int) -> void:
	remaining_seconds = maxi(0, remaining_seconds)
	if _coins == coins and _remaining_seconds == remaining_seconds: return
	_coins = coins
	_remaining_seconds = remaining_seconds
	queue_redraw()


func _draw() -> void:
	if _coins < 0: return
	var minutes := int(_remaining_seconds / 60)
	var time_text := "%02d:%02d" % [minutes, _remaining_seconds % 60]
	_draw_row(CLOCK_ICON, time_text, 20)
	_draw_row(COIN_ICON, str(_coins), 82)


func _draw_row(icon: Array, value: String, top: int) -> void:
	var text_width := value.length() * GLYPH_ADVANCE * PIXEL_SCALE - PIXEL_SCALE
	var total_width := 7 * PIXEL_SCALE + ICON_GAP + text_width
	var left := roundi((size.x - total_width) / 2.0)
	_draw_bitmap(icon, Vector2i(left, top), ICON_COLOR)
	var text_left := left + 7 * PIXEL_SCALE + ICON_GAP
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if GLYPHS.has(character):
			_draw_bitmap(GLYPHS[character], Vector2i(text_left + index * GLYPH_ADVANCE * PIXEL_SCALE, top), TEXT_COLOR)


func _draw_bitmap(pattern: Array, origin: Vector2i, color: Color) -> void:
	for row in range(pattern.size()):
		var bits: String = pattern[row]
		for column in range(bits.length()):
			if bits.substr(column, 1) != "1": continue
			var at := origin + Vector2i(column, row) * PIXEL_SCALE
			draw_rect(Rect2(at.x + 1, at.y + 1, PIXEL_SCALE, PIXEL_SCALE), SHADOW_COLOR)
			draw_rect(Rect2(at.x, at.y, PIXEL_SCALE, PIXEL_SCALE), color)
