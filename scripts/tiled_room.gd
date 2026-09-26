extends Node2D
## Draws the restaurant from small bitmap tiles; purchased cells add floor and remove blockers.

const Layout = preload("res://scripts/layout_rules.gd")
const FLOOR = preload("res://assets/backgrounds/tiles/floor.png")
const WALL = preload("res://assets/backgrounds/tiles/wall.png")
const BORDER = preload("res://assets/backgrounds/tiles/border.png")
const ORIGINAL = preload("res://assets/backgrounds/restaurant.webp")

var expansion_cells: Array[Vector2i] = []
var preview_enabled := false


func _ready() -> void:
	_rebuild()


func set_expansion(cells: Array[Vector2i]) -> void:
	expansion_cells = cells.duplicate()
	_rebuild()


func set_expansion_preview(enabled: bool) -> void:
	preview_enabled = enabled
	_rebuild()


func _rebuild() -> void:
	for child in get_children(): child.free()
	var origin: Vector2 = Layout.ROOM_ORIGIN
	var size: float = Layout.ROOM_CELL
	var backdrop := Polygon2D.new()
	backdrop.polygon = PackedVector2Array([Vector2(-100000, -100000), Vector2(100000, -100000), Vector2(100000, 100000), Vector2(-100000, 100000)])
	backdrop.color = Color("38291f")
	add_child(backdrop)
	var owned: Array[Vector2i] = []
	for row in range(Layout.ROOM_ROWS):
		for column in range(Layout.INITIAL_COLUMNS): owned.append(Vector2i(column, row))
	for cell in expansion_cells: owned.append(cell)
	for cell in owned: _sprite(FLOOR, origin + Vector2(cell) * size)
	if preview_enabled:
		for cell in Layout.frontier(expansion_cells):
			var position := origin + Vector2(cell) * size
			_sprite(FLOOR, position).modulate = Color(1.0, 0.92, 0.68, 0.46)
			var outline := Line2D.new()
			outline.points = PackedVector2Array([position, position + Vector2(size, 0), position + Vector2(size, size), position + Vector2(0, size), position])
			outline.width = 3.0
			outline.default_color = Color("edbc72")
			add_child(outline)
	# Keep the original doorway, menu board and register as independent decorative regions.
	_region(Rect2(0, 0, 1216, 130), Vector2(32, 170))
	_region(Rect2(0, 125, 265, 120), Vector2(32, 295))
	for cell in owned:
		if cell.y == 0 and cell.x >= Layout.INITIAL_COLUMNS:
			_sprite(WALL, Vector2(origin.x + cell.x * size, 170))
		if cell.x == 0:
			var side := _sprite(BORDER, Vector2(56, origin.y + cell.y * size))
			side.rotation = PI / 2.0
	var blockers := StaticBody2D.new()
	blockers.collision_layer = 1
	blockers.collision_mask = 0
	add_child(blockers)
	for cell in owned:
		var top_left := origin + Vector2(cell) * size
		if not Layout.owned_cell(cell + Vector2i.LEFT, expansion_cells): _block(blockers, top_left + Vector2(0, size * 0.5), Vector2(8, size))
		if not Layout.owned_cell(cell + Vector2i.RIGHT, expansion_cells): _block(blockers, top_left + Vector2(size, size * 0.5), Vector2(8, size))
		if not Layout.owned_cell(cell + Vector2i.UP, expansion_cells): _block(blockers, top_left + Vector2(size * 0.5, 0), Vector2(size, 8))
		if not Layout.owned_cell(cell + Vector2i.DOWN, expansion_cells): _block(blockers, top_left + Vector2(size * 0.5, size), Vector2(size, 8))


func _sprite(texture: Texture2D, position: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = position
	add_child(sprite)
	return sprite


func _region(rect: Rect2, position: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = ORIGINAL
	sprite.region_enabled = true
	sprite.region_rect = rect
	sprite.centered = false
	sprite.position = position
	add_child(sprite)


func _block(body: StaticBody2D, position: Vector2, dimensions: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = dimensions
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = position
	body.add_child(collision)
