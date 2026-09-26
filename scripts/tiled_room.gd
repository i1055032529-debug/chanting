extends Node2D
## Draws the restaurant from small bitmap tiles; purchased cells add floor and remove blockers.

const Layout = preload("res://scripts/layout_rules.gd")
const FLOOR = preload("res://assets/backgrounds/tiles/floor.png")
const WALL = preload("res://assets/backgrounds/tiles/wall.png")
const BORDER = preload("res://assets/backgrounds/tiles/border.png")
const ORIGINAL = preload("res://assets/backgrounds/restaurant.webp")

var expansion_cells: Array[Vector2i] = []


func _ready() -> void:
	_rebuild()


func set_expansion(cells: Array[Vector2i]) -> void:
	expansion_cells = cells.duplicate()
	_rebuild()


func _rebuild() -> void:
	for child in get_children(): child.free()
	var origin: Vector2 = Layout.ROOM_ORIGIN
	var size: float = Layout.ROOM_CELL
	var lot := Polygon2D.new()
	lot.polygon = PackedVector2Array([Vector2(1240, 285), Vector2(1640, 285), Vector2(1640, 685), Vector2(1240, 685)])
	lot.color = Color("38291f")
	add_child(lot)
	for row in range(Layout.ROOM_ROWS):
		for column in range(Layout.TOTAL_COLUMNS):
			var cell := Vector2i(column, row)
			if column < Layout.INITIAL_COLUMNS or cell in expansion_cells:
				_sprite(FLOOR, origin + Vector2(column, row) * size)
			elif column >= Layout.INITIAL_COLUMNS:
				var outline := Line2D.new()
				outline.points = PackedVector2Array([origin + Vector2(column, row) * size, origin + Vector2(column + 1, row) * size, origin + Vector2(column + 1, row + 1) * size, origin + Vector2(column, row + 1) * size, origin + Vector2(column, row) * size])
				outline.width = 1.0
				outline.default_color = Color("71452c")
				add_child(outline)
	# Keep the original doorway, menu board and register as independent decorative regions.
	_region(Rect2(0, 0, 1216, 130), Vector2(32, 170))
	_region(Rect2(0, 125, 265, 120), Vector2(32, 295))
	for column in range(Layout.INITIAL_COLUMNS, Layout.TOTAL_COLUMNS):
		_sprite(WALL, Vector2(origin.x + column * size, 170))
	for column in range(Layout.TOTAL_COLUMNS):
		_sprite(BORDER, Vector2(origin.x + column * size, 685))
	var blockers := StaticBody2D.new()
	blockers.collision_layer = 1
	blockers.collision_mask = 0
	add_child(blockers)
	for row in range(Layout.ROOM_ROWS):
		for column in range(Layout.INITIAL_COLUMNS, Layout.TOTAL_COLUMNS):
			if Vector2i(column, row) not in expansion_cells:
				_block(blockers, origin + Vector2(column + 0.5, row + 0.5) * size, Vector2(size, size))
	_block(blockers, Vector2(1648, 485), Vector2(16, 400))
	_block(blockers, Vector2(1440, 691), Vector2(400, 14))
	_block(blockers, Vector2(1440, 226), Vector2(400, 132))


func _sprite(texture: Texture2D, position: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = position
	add_child(sprite)


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
