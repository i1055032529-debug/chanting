class_name LayoutRules
extends RefCounted
## Placement uses the same furniture footprints as the scene, plus walking clearance.

const ROOM := Rect2(310, 445, 810, 185)
const GRID_ORIGIN := Vector2(320, 300)
const CELL := 10.0
const GRID_SIZE := Vector2i(90, 38)
const FIXED := [
	Rect2(50, 293, 242, 120),
	Rect2(575, 340, 120, 52),
	Rect2(705, 340, 120, 52),
	Rect2(840, 340, 120, 52),
	Rect2(1040, 340, 120, 52),
]
const WORK_POINTS := [Vector2(635, 414), Vector2(765, 414), Vector2(900, 414), Vector2(1100, 414)]


static func table_footprints(center: Vector2) -> Array[Rect2]:
	return [Rect2(center + Vector2(-60, -44), Vector2(120, 52)), Rect2(center + Vector2(76, -30), Vector2(48, 38))]


static func valid(positions: Array[Vector2]) -> bool:
	if positions.is_empty(): return false
	var obstacles: Array[Rect2] = []
	for fixed in FIXED: obstacles.append(fixed)
	for center in positions:
		if not ROOM.has_point(center): return false
		for footprint in table_footprints(center):
			if footprint.position.x < 305.0 or footprint.end.x > 1224.0 or footprint.position.y < 300.0 or footprint.end.y > 665.0: return false
			for obstacle in obstacles:
				if footprint.intersects(obstacle): return false
			obstacles.append(footprint)
	var visited := {}
	var queue: Array[Vector2i] = [Vector2i(5, 1)] # Entrance-side floor, near (370, 310).
	if _blocked(queue[0], obstacles): return false
	visited[queue[0]] = true
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if visited.has(next) or _blocked(next, obstacles): continue
			visited[next] = true
			queue.append(next)
	for point in WORK_POINTS:
		if not _near_reachable(point, visited): return false
	for center in positions:
		if not _near_reachable(center + Vector2(0, 30), visited): return false
		if not _near_reachable(center + Vector2(100, 25), visited): return false
	return true


static func customer_route(positions: Array[Vector2], destination: Vector2) -> Array[Vector2]:
	var obstacles: Array[Rect2] = []
	for fixed in FIXED: obstacles.append(fixed)
	for center in positions:
		obstacles.append_array(table_footprints(center))
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, GRID_SIZE)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = GRID_ORIGIN
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y in range(GRID_SIZE.y):
		for x in range(GRID_SIZE.x):
			var cell := Vector2i(x, y)
			if _blocked(cell, obstacles): grid.set_point_solid(cell)
	var start := Vector2i(5, 1)
	var base := Vector2i(roundi((destination.x - GRID_ORIGIN.x) / CELL), roundi((destination.y - GRID_ORIGIN.y) / CELL))
	var best := PackedVector2Array()
	for radius in range(4):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var goal := base + Vector2i(x, y)
				if _blocked(goal, obstacles): continue
				var candidate := grid.get_point_path(start, goal)
				if not candidate.is_empty() and (best.is_empty() or candidate[-1].distance_to(destination) < best[-1].distance_to(destination)):
					best = candidate
		if not best.is_empty(): break
	var route: Array[Vector2] = []
	for point in best: route.append(point)
	return route


static func _blocked(cell: Vector2i, obstacles: Array[Rect2]) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= GRID_SIZE.x or cell.y >= GRID_SIZE.y: return true
	var point := GRID_ORIGIN + Vector2(cell) * CELL
	for obstacle in obstacles:
		if obstacle.has_point(point): return true
	return false


static func _near_reachable(point: Vector2, visited: Dictionary) -> bool:
	var base := Vector2i(roundi((point.x - GRID_ORIGIN.x) / CELL), roundi((point.y - GRID_ORIGIN.y) / CELL))
	for y in range(-1, 2):
		for x in range(-1, 2):
			if visited.has(base + Vector2i(x, y)): return true
	return false
