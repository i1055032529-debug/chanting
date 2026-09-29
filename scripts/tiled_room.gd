extends Node2D
## Draws the restaurant from small bitmap tiles; purchased cells add floor and remove blockers.

const Layout = preload("res://scripts/layout_rules.gd")
const FLOOR_TILE_SIZE := 120
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
var floor_textures: Array[Texture2D] = []


func _ready() -> void:
	for source_texture in FLOOR_VARIANTS:
		var image := source_texture.get_image()
		image.resize(FLOOR_TILE_SIZE, FLOOR_TILE_SIZE, Image.INTERPOLATE_NEAREST)
		floor_textures.append(ImageTexture.create_from_image(image))
	var initial_tiles: Array[Vector2i] = []
	for row in range(floori(Layout.ROOM_ROWS * Layout.ROOM_CELL / FLOOR_TILE_SIZE)):
		for column in range(floori(Layout.INITIAL_COLUMNS * Layout.ROOM_CELL / FLOOR_TILE_SIZE)):
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
	_draw_owned_floor(owned, origin)
	if preview_enabled:
		for cell in Layout.frontier(expansion_cells):
			var position := origin + Vector2(cell) * size
			_draw_floor_cell(cell, origin, Color(1.0, 0.92, 0.68, 0.46))
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


func _draw_owned_floor(owned: Array[Vector2i], origin: Vector2) -> void:
	var cell_size := int(Layout.ROOM_CELL)
	var owned_set: Dictionary = {}
	var max_cell := Vector2i(Layout.INITIAL_COLUMNS, Layout.ROOM_ROWS)
	for cell in owned:
		owned_set[cell] = true
		max_cell.x = maxi(max_cell.x, cell.x + 1)
		max_cell.y = maxi(max_cell.y, cell.y + 1)
	for tile_y in range(ceili(float(max_cell.y * cell_size) / FLOOR_TILE_SIZE)):
		for tile_x in range(ceili(float(max_cell.x * cell_size) / FLOOR_TILE_SIZE)):
			var tile_cell := Vector2i(tile_x, tile_y)
			var tile_rect := _floor_tile_rect(tile_cell)
			var parts: Array[Rect2i] = []
			var covered_area := 0
			var first_cell := Vector2i(floori(float(tile_rect.position.x) / cell_size), floori(float(tile_rect.position.y) / cell_size))
			var last_cell := Vector2i(ceili(float(tile_rect.end.x) / cell_size), ceili(float(tile_rect.end.y) / cell_size))
			for cell_y in range(first_cell.y, last_cell.y):
				for cell_x in range(first_cell.x, last_cell.x):
					var cell := Vector2i(cell_x, cell_y)
					if not owned_set.has(cell): continue
					var part := tile_rect.intersection(Rect2i(cell * cell_size, Vector2i(cell_size, cell_size)))
					if not part.has_area(): continue
					parts.append(part)
					covered_area += part.size.x * part.size.y
			if covered_area == FLOOR_TILE_SIZE * FLOOR_TILE_SIZE:
				_sprite(_floor_texture(tile_cell), origin + Vector2(tile_rect.position))
			else:
				for part in parts: _floor_fragment(tile_cell, tile_rect, part, origin)


func _draw_floor_cell(cell: Vector2i, origin: Vector2, tint: Color) -> void:
	var cell_size := int(Layout.ROOM_CELL)
	var cell_rect := Rect2i(cell * cell_size, Vector2i(cell_size, cell_size))
	var first_tile := Vector2i(floori(float(cell_rect.position.x) / FLOOR_TILE_SIZE), floori(float(cell_rect.position.y) / FLOOR_TILE_SIZE))
	var last_tile := Vector2i(ceili(float(cell_rect.end.x) / FLOOR_TILE_SIZE), ceili(float(cell_rect.end.y) / FLOOR_TILE_SIZE))
	for tile_y in range(first_tile.y, last_tile.y):
		for tile_x in range(first_tile.x, last_tile.x):
			var tile_cell := Vector2i(tile_x, tile_y)
			var tile_rect := _floor_tile_rect(tile_cell)
			var part := tile_rect.intersection(cell_rect)
			if part.has_area(): _floor_fragment(tile_cell, tile_rect, part, origin).modulate = tint


func _floor_tile_rect(tile_cell: Vector2i) -> Rect2i:
	return Rect2i(tile_cell * FLOOR_TILE_SIZE, Vector2i(FLOOR_TILE_SIZE, FLOOR_TILE_SIZE))


func _floor_texture(tile_cell: Vector2i) -> Texture2D:
	var tile_index: int = floor_variant_by_tile.get(tile_cell, 0)
	return floor_textures[tile_index]


func _floor_fragment(tile_cell: Vector2i, tile_rect: Rect2i, part: Rect2i, origin: Vector2) -> Sprite2D:
	var sprite := _sprite(_floor_texture(tile_cell), origin + Vector2(part.position))
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2(part.position - tile_rect.position), Vector2(part.size))
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
