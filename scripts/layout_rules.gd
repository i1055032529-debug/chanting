class_name LayoutRules
extends RefCounted
## Placement uses the same furniture footprints as the scene, plus walking clearance.

const TABLE_ROOM := Rect2(305, 420, 825, 210)
const DEVICE_ROOM := Rect2(305, 365, 825, 265)
const ROOM_ORIGIN := Vector2(40, 285)
const ROOM_CELL := 80.0
const INITIAL_COLUMNS := 15
const ROOM_ROWS := 5
const GRID_ORIGIN := Vector2(320, 300)
const CELL := 10.0
const REGISTER := Rect2(50, 293, 242, 120)
const DOOR_CLEAR := Rect2(335, 300, 110, 105)
const SPAWN_POINTS := [Vector2(500, 520), Vector2(375, 570), Vector2(405, 570), Vector2(435, 570)]
const DEVICE_IDS := ["stove", "stove_2", "pass", "sink"]
const DEFAULT_DEVICES := {"stove": Vector2(635, 384), "stove_2": Vector2(765, 384), "pass": Vector2(900, 384), "sink": Vector2(1100, 384)}


static func free_table_position(positions: Array[Vector2], devices: Dictionary = DEFAULT_DEVICES, expansion_cells: Array[Vector2i] = []) -> Vector2:
	var candidate: Array[Vector2] = positions.duplicate()
	for preferred in [Vector2(715, 575), Vector2(715, 460)]:
		candidate.append(preferred)
		if valid(candidate, devices, expansion_cells): return preferred
		candidate.pop_back()
	var bounds := owned_bounds(expansion_cells)
	for y in range(400, int(bounds.y - 40), 20):
		for x in range(380, int(bounds.x - 60), 20):
			var position := Vector2(x, y)
			candidate.append(position)
			if valid(candidate, devices, expansion_cells): return position
			candidate.pop_back()
	return Vector2.ZERO


static func table_footprints(center: Vector2) -> Array[Rect2]:
	return [Rect2(center + Vector2(-60, -44), Vector2(120, 52)), Rect2(center + Vector2(76, -30), Vector2(48, 38))]


static func device_footprint(center: Vector2) -> Rect2:
	return Rect2(center + Vector2(-60, -44), Vector2(120, 52))


static func owned_cell(cell: Vector2i, expansion_cells: Array[Vector2i]) -> bool:
	return cell.x >= 0 and cell.y >= 0 and ((cell.x < INITIAL_COLUMNS and cell.y < ROOM_ROWS) or cell in expansion_cells)


static func frontier(expansion_cells: Array[Vector2i]) -> Array[Vector2i]:
	var found := {}
	for row in range(ROOM_ROWS): found[Vector2i(INITIAL_COLUMNS, row)] = true
	for column in range(INITIAL_COLUMNS): found[Vector2i(column, ROOM_ROWS)] = true
	for cell in expansion_cells:
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + direction
			if neighbor.x >= 0 and neighbor.y >= 0 and not owned_cell(neighbor, expansion_cells): found[neighbor] = true
	var result: Array[Vector2i] = []
	for cell: Vector2i in found: result.append(cell)
	return result


static func owned_bounds(expansion_cells: Array[Vector2i]) -> Vector2:
	var last := Vector2i(INITIAL_COLUMNS - 1, ROOM_ROWS - 1)
	for cell in expansion_cells:
		last.x = maxi(last.x, cell.x)
		last.y = maxi(last.y, cell.y)
	return ROOM_ORIGIN + Vector2(last + Vector2i.ONE) * ROOM_CELL


static func grid_size(expansion_cells: Array[Vector2i]) -> Vector2i:
	var bounds := owned_bounds(expansion_cells)
	return Vector2i(ceili((bounds.x - GRID_ORIGIN.x) / CELL) + 2, ceili((bounds.y - GRID_ORIGIN.y) / CELL) + 2)


static func valid(positions: Array[Vector2], devices: Dictionary = DEFAULT_DEVICES, expansion_cells: Array[Vector2i] = []) -> bool:
	if positions.is_empty() or devices.size() != DEVICE_IDS.size(): return false
	var obstacles: Array[Rect2] = [REGISTER]
	for center in positions:
		if not TABLE_ROOM.has_point(center) and not _expanded_center(center, expansion_cells): return false
		for footprint in table_footprints(center):
			if not _fits(footprint, obstacles, expansion_cells): return false
			obstacles.append(footprint)
	for id in DEVICE_IDS:
		if not devices.has(id): return false
		var center: Vector2 = devices[id]
		if not DEVICE_ROOM.has_point(center) and not _expanded_center(center, expansion_cells): return false
		var footprint := device_footprint(center)
		if not _fits(footprint, obstacles, expansion_cells): return false
		obstacles.append(footprint)
	for point in SPAWN_POINTS:
		for obstacle in obstacles:
			if obstacle.has_point(point): return false
	var visited := {}
	var bounds := grid_size(expansion_cells)
	var queue: Array[Vector2i] = [Vector2i(5, 1)] # Entrance-side floor, near (370, 310).
	if _blocked(queue[0], obstacles, expansion_cells, bounds): return false
	visited[queue[0]] = true
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if visited.has(next) or _blocked(next, obstacles, expansion_cells, bounds): continue
			visited[next] = true
			queue.append(next)
	for id in DEVICE_IDS:
		if not _owned(devices[id] + Vector2(0, 30), expansion_cells) or not _near_reachable(devices[id] + Vector2(0, 30), visited): return false
	for point in SPAWN_POINTS:
		if not _near_reachable(point, visited): return false
	for center in positions:
		if not _owned(center + Vector2(0, 30), expansion_cells) or not _near_reachable(center + Vector2(0, 30), visited): return false
		if not _owned(center + Vector2(100, 25), expansion_cells) or not _near_reachable(center + Vector2(100, 25), visited): return false
	return true


static func customer_route(positions: Array[Vector2], destination: Vector2, devices: Dictionary = DEFAULT_DEVICES, expansion_cells: Array[Vector2i] = []) -> Array[Vector2]:
	var obstacles: Array[Rect2] = [REGISTER]
	for center in positions:
		obstacles.append_array(table_footprints(center))
	for id in DEVICE_IDS:
		obstacles.append(device_footprint(devices[id]))
	var grid := AStarGrid2D.new()
	var bounds := grid_size(expansion_cells)
	grid.region = Rect2i(Vector2i.ZERO, bounds)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = GRID_ORIGIN
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y in range(bounds.y):
		for x in range(bounds.x):
			var cell := Vector2i(x, y)
			if _blocked(cell, obstacles, expansion_cells, bounds): grid.set_point_solid(cell)
	var start := Vector2i(5, 1)
	var base := Vector2i(roundi((destination.x - GRID_ORIGIN.x) / CELL), roundi((destination.y - GRID_ORIGIN.y) / CELL))
	var best := PackedVector2Array()
	for radius in range(4):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var goal := base + Vector2i(x, y)
				if _blocked(goal, obstacles, expansion_cells, bounds): continue
				var candidate := grid.get_point_path(start, goal)
				if not candidate.is_empty() and (best.is_empty() or candidate[-1].distance_to(destination) < best[-1].distance_to(destination)):
					best = candidate
		if not best.is_empty(): break
	var route: Array[Vector2] = []
	for point in best: route.append(point)
	return route


static func _fits(footprint: Rect2, obstacles: Array[Rect2], expansion_cells: Array[Vector2i]) -> bool:
	for y in range(int(footprint.position.y), int(footprint.end.y), 10):
		for x in range(int(footprint.position.x), int(footprint.end.x), 10):
			if not _owned(Vector2(x, y), expansion_cells): return false
	if not _owned(footprint.end - Vector2.ONE, expansion_cells): return false
	if footprint.intersects(DOOR_CLEAR): return false
	for obstacle in obstacles:
		if footprint.intersects(obstacle): return false
	return true


static func _blocked(cell: Vector2i, obstacles: Array[Rect2], expansion_cells: Array[Vector2i], bounds: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= bounds.x or cell.y >= bounds.y: return true
	var point := GRID_ORIGIN + Vector2(cell) * CELL
	if not _owned(point, expansion_cells): return true
	for obstacle in obstacles:
		if obstacle.has_point(point): return true
	return false


static func _expanded_center(point: Vector2, expansion_cells: Array[Vector2i]) -> bool:
	var cell := Vector2i(floori((point.x - ROOM_ORIGIN.x) / ROOM_CELL), floori((point.y - ROOM_ORIGIN.y) / ROOM_CELL))
	return cell in expansion_cells


static func _owned(point: Vector2, expansion_cells: Array[Vector2i]) -> bool:
	var cell := Vector2i(floori((point.x - ROOM_ORIGIN.x) / ROOM_CELL), floori((point.y - ROOM_ORIGIN.y) / ROOM_CELL))
	return owned_cell(cell, expansion_cells)


static func _near_reachable(point: Vector2, visited: Dictionary) -> bool:
	var base := Vector2i(roundi((point.x - GRID_ORIGIN.x) / CELL), roundi((point.y - GRID_ORIGIN.y) / CELL))
	for y in range(-1, 2):
		for x in range(-1, 2):
			if visited.has(base + Vector2i(x, y)): return true
	return false
