extends Node2D
## Draws the restaurant from small bitmap tiles; purchased cells add floor and remove blockers.

const Layout = preload("res://scripts/layout_rules.gd")
const FLOOR_CELLS_PER_TILE := 2
const FLOOR_VARIANTS: Array[Texture2D] = [
	preload("res://assets/backgrounds/tiles/floor_grain_1.png"),
	preload("res://assets/backgrounds/tiles/floor_grain_2.png"),
	preload("res://assets/backgrounds/tiles/floor_grain_3.png"),
	preload("res://assets/backgrounds/tiles/floor_grain_4.png"),
	preload("res://assets/backgrounds/tiles/floor_grain_5.png"),
]
const WALL = preload("res://assets/backgrounds/tiles/wall.png")
const BORDER = preload("res://assets/backgrounds/tiles/border.png")
const ORIGINAL = preload("res://assets/backgrounds/restaurant.webp")

var expansion_cells: Array[Vector2i] = []
var preview_enabled := false
var floor_variant_by_tile: Dictionary = {}


func _ready() -> void:
	var initial_tiles: Array[Vector2i] = []
	for row in range(floori(float(Layout.ROOM_ROWS) / FLOOR_CELLS_PER_TILE)):
		for column in range(floori(float(Layout.INITIAL_COLUMNS) / FLOOR_CELLS_PER_TILE)):
			initial_tiles.append(Vector2i(column, row))
	initial_tiles.shuffle()
	for variant_index in range(1, FLOOR_VARIANTS.size()):
		floor_variant_by_tile[initial_tiles[variant_index - 1]] = variant_index
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
	var owned_set: Dictionary = {}
	for cell in owned: owned_set[cell] = true
	var drawn_tiles: Dictionary = {}
	for cell in owned:
		var tile_cell := _floor_tile_cell(cell)
		if drawn_tiles.has(tile_cell): continue
		drawn_tiles[tile_cell] = true
		var first_cell: Vector2i = tile_cell * FLOOR_CELLS_PER_TILE
		var complete := true
		for y in range(FLOOR_CELLS_PER_TILE):
			for x in range(FLOOR_CELLS_PER_TILE):
				if not owned_set.has(first_cell + Vector2i(x, y)): complete = false
		if complete:
			var tile := _sprite(_floor_texture(tile_cell), origin + Vector2(first_cell) * size)
			tile.scale = Vector2.ONE * FLOOR_CELLS_PER_TILE
		else:
			for y in range(FLOOR_CELLS_PER_TILE):
				for x in range(FLOOR_CELLS_PER_TILE):
					var part := first_cell + Vector2i(x, y)
					if owned_set.has(part): _floor_fragment(part, origin + Vector2(part) * size)
	if preview_enabled:
		for cell in Layout.frontier(expansion_cells):
			var position := origin + Vector2(cell) * size
			_floor_fragment(cell, position).modulate = Color(1.0, 0.92, 0.68, 0.46)
			var outline := Line2D.new()
			outline.points = PackedVector2Array([position, position + Vector2(size, 0), position + Vector2(size, size), position + Vector2(0, size), position])
			outline.width = 3.0
			outline.default_color = Color("edbc72")
			add_child(outline)
	# The supplied wall art already has a menu board and framed record; keep it visible.
	_region(Rect2(0, 0, 1216, 130), Vector2(32, 170))
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


func _floor_tile_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / FLOOR_CELLS_PER_TILE), floori(float(cell.y) / FLOOR_CELLS_PER_TILE))


func _floor_texture(tile_cell: Vector2i) -> Texture2D:
	var tile_index: int = floor_variant_by_tile.get(tile_cell, 0)
	return FLOOR_VARIANTS[tile_index]


func _floor_fragment(cell: Vector2i, position: Vector2) -> Sprite2D:
	var sprite := _sprite(_floor_texture(_floor_tile_cell(cell)), position)
	var region_size := sprite.texture.get_size() / FLOOR_CELLS_PER_TILE
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2(cell.x % FLOOR_CELLS_PER_TILE, cell.y % FLOOR_CELLS_PER_TILE) * region_size, region_size)
	sprite.scale = Vector2.ONE * FLOOR_CELLS_PER_TILE
	return sprite


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
