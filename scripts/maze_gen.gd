class_name MazeGen
extends RefCounted
## Grid maze: a recursive backtracker carves a perfect maze, then a share of
## the interior walls is knocked out so there are loops to shake off the
## stalker. A perfect maze would turn every chase into a dead end.

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var w: int
var h: int
## v[x][y]: wall on the west side of cell (x, y); x runs 0..w, so x == w is
## the east border.
var v: Array = []
## hw[x][y]: wall on the north side of cell (x, y); y runs 0..h.
var hw: Array = []
var rng := RandomNumberGenerator.new()


func _init(width: int, height: int, seed_value: int, loop_share := 0.12) -> void:
	w = width
	h = height
	rng.seed = seed_value
	for x in w + 1:
		var col := []
		col.resize(h)
		col.fill(true)
		v.append(col)
	for x in w:
		var col := []
		col.resize(h + 1)
		col.fill(true)
		hw.append(col)
	_carve()
	_add_loops(loop_share)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


## a and b must be orthogonal neighbours.
func set_open(a: Vector2i, b: Vector2i) -> void:
	if b.x != a.x:
		v[maxi(a.x, b.x)][a.y] = false
	else:
		hw[a.x][maxi(a.y, b.y)] = false


func is_open(a: Vector2i, b: Vector2i) -> bool:
	if not in_bounds(a) or not in_bounds(b):
		return false
	if b.x != a.x:
		return not v[maxi(a.x, b.x)][a.y]
	return not hw[a.x][maxi(a.y, b.y)]


## Breadth-first path length (in cells) from `from` to every cell.
func distances(from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var queue: Array[Vector2i] = [from]
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		for d in DIRS:
			var n := c + d
			if not dist.has(n) and is_open(c, n):
				dist[n] = dist[c] + 1
				queue.append(n)
	return dist


func _carve() -> void:
	var start := Vector2i(rng.randi() % w, rng.randi() % h)
	var visited := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var opts: Array[Vector2i] = []
		for d in DIRS:
			var n := c + d
			if in_bounds(n) and not visited.has(n):
				opts.append(n)
		if opts.is_empty():
			stack.pop_back()
			continue
		var n := opts[rng.randi() % opts.size()]
		set_open(c, n)
		visited[n] = true
		stack.append(n)


func _add_loops(share: float) -> void:
	var walls: Array[Vector3i] = []  # (vertical?1:0, x, y)
	for x in range(1, w):
		for y in h:
			if v[x][y]:
				walls.append(Vector3i(1, x, y))
	for x in w:
		for y in range(1, h):
			if hw[x][y]:
				walls.append(Vector3i(0, x, y))
	for i in range(walls.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t := walls[i]
		walls[i] = walls[j]
		walls[j] = t
	for i in int(walls.size() * share):
		var wl := walls[i]
		if wl.x == 1:
			v[wl.y][wl.z] = false
		else:
			hw[wl.y][wl.z] = false
