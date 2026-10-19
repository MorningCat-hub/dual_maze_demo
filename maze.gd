class_name Maze
extends RefCounted

## 半张迷宫的网格数据，压成一维数组。
## 约定：0 = 可走，1 = 墙。
## 结构上格子落在「奇数, 奇数」，两格之间的通道落在「奇数, 偶数」或「偶数, 奇数」，
## 「偶数, 偶数」是柱子（永远不挖），所以看起来是一格宽的迷宫。

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const STEPS: Array[Vector2i] = [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]

var width: int = 0
var height: int = 0
var cells: PackedByteArray = PackedByteArray()


func _init(w: int = 1, h: int = 1) -> void:
	width = maxi(1, w)
	height = maxi(1, h)
	cells = PackedByteArray()
	cells.resize(width * height)
	cells.fill(1)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func is_floor(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return cells[y * width + x] == 0


func is_floor_at(c: Vector2i) -> bool:
	return is_floor(c.x, c.y)


func carve(x: int, y: int) -> void:
	if not in_bounds(x, y):
		return
	cells[y * width + x] = 0


func carve_at(c: Vector2i) -> void:
	carve(c.x, c.y)


func floor_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in height:
		for x in width:
			if cells[y * width + x] == 0:
				out.append(Vector2i(x, y))
	return out


func floor_neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in DIRS:
		var n: Vector2i = c + d
		if is_floor_at(n):
			out.append(n)
	return out


func degree(c: Vector2i) -> int:
	return floor_neighbors(c).size()


## 边界格不参与「额外开洞」，免得把外墙挖穿（终点那一圈是单独显式挖的）。
func is_border(c: Vector2i) -> bool:
	return c.x <= 0 or c.y <= 0 or c.x >= width - 1 or c.y >= height - 1


## 递归回溯法生成完美迷宫：所有奇数 x/y 的格子都会被访问到。
static func generate(w: int, h: int, rng: RandomNumberGenerator) -> Maze:
	var gw: int = w if w % 2 == 1 else w + 1
	var gh: int = h if h % 2 == 1 else h + 1
	var m := Maze.new(gw, gh)
	var start := Vector2i(1, 1)
	m.carve_at(start)
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var cur: Vector2i = stack[stack.size() - 1]
		var options: Array[Vector2i] = []
		for d: Vector2i in STEPS:
			var nxt: Vector2i = cur + d
			if nxt.x >= 1 and nxt.y >= 1 and nxt.x <= gw - 2 and nxt.y <= gh - 2 and not m.is_floor_at(nxt):
				options.append(nxt)
		if options.is_empty():
			stack.pop_back()
			continue
		var pick: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		m.carve((cur.x + pick.x) / 2, (cur.y + pick.y) / 2)
		m.carve_at(pick)
		stack.append(pick)
	return m


# ------------------------------------------------------------------ 公平性改造


## 打通死胡同：让每一格至少有两个可走邻居。
## 完美迷宫里走进死胡同 = 被追逐者堵死，所以有追逐者的关卡必须先跑这个。
func braid(rng: RandomNumberGenerator) -> int:
	var opened: int = 0
	var guard: int = 0
	var limit: int = width * height * 2
	var fails: int = 0
	while guard < limit and fails < 4:
		guard += 1
		var dead: Array[Vector2i] = []
		for c: Vector2i in floor_cells():
			if degree(c) < 2:
				dead.append(c)
		if dead.is_empty():
			break
		var target: Vector2i = dead[rng.randi_range(0, dead.size() - 1)]
		if _open_wall_next_to(target, rng):
			opened += 1
			fails = 0
		else:
			fails += 1
	return opened


## 在 c 旁边挑一堵墙挖开。优先挖「后面本来就有一条走廊」的墙，这样能直接连成环。
func _open_wall_next_to(c: Vector2i, rng: RandomNumberGenerator) -> bool:
	var loops: Array[Vector2i] = []
	var plain: Array[Vector2i] = []
	for d: Vector2i in DIRS:
		var w: Vector2i = c + d
		if not in_bounds(w.x, w.y) or is_floor_at(w):
			continue
		if is_border(w):
			continue
		var beyond: Vector2i = w + d
		if is_floor_at(beyond):
			loops.append(w)
		else:
			plain.append(w)
	var pool: Array[Vector2i] = loops if not loops.is_empty() else plain
	if pool.is_empty():
		return false
	carve_at(pool[rng.randi_range(0, pool.size() - 1)])
	return true


## 在 cut 附近挖一堵「两侧都是路」的墙，制造一条绕开它的环。
func open_bypass_near(cut: Vector2i, rng: RandomNumberGenerator, radius: int = 3) -> bool:
	for r in range(1, radius + 1):
		var pool: Array[Vector2i] = []
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var w := Vector2i(cut.x + dx, cut.y + dy)
				if not in_bounds(w.x, w.y) or is_floor_at(w) or is_border(w):
					continue
				if floor_neighbors(w).size() >= 2:
					pool.append(w)
		if not pool.is_empty():
			carve_at(pool[rng.randi_range(0, pool.size() - 1)])
			return true
	return false


## 全图随便找一堵两侧都是路的墙挖开。
func open_random_loop(rng: RandomNumberGenerator) -> bool:
	var pool: Array[Vector2i] = []
	for y in height:
		for x in width:
			var w := Vector2i(x, y)
			if is_floor_at(w) or is_border(w):
				continue
			if floor_neighbors(w).size() >= 2:
				pool.append(w)
	if pool.is_empty():
		return false
	carve_at(pool[rng.randi_range(0, pool.size() - 1)])
	return true


## 从 start 出发能不能走到 goals 里的任意一格；blocked 那格当成不存在。
static func route_exists(m: Maze, start: Vector2i, goals: Dictionary, blocked: Vector2i) -> bool:
	if start == blocked or not m.is_floor_at(start):
		return false
	if goals.has(start):
		return true
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for d: Vector2i in DIRS:
			var nxt: Vector2i = cur + d
			if nxt == blocked or not m.is_floor_at(nxt) or seen.has(nxt):
				continue
			if goals.has(nxt):
				return true
			seen[nxt] = true
			queue.append(nxt)
	return false


## 起点到 goals 的一条最短路径（用于缩小割点扫描范围）。
static func path_to_goal(m: Maze, start: Vector2i, goals: Dictionary) -> Array[Vector2i]:
	if not m.is_floor_at(start):
		return []
	var parent: Dictionary = {start: Vector2i(-1, -1)}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	var found := Vector2i(-1, -1)
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if goals.has(cur) and cur != start:
			found = cur
			break
		for d: Vector2i in DIRS:
			var nxt: Vector2i = cur + d
			if not m.is_floor_at(nxt) or parent.has(nxt):
				continue
			parent[nxt] = cur
			queue.append(nxt)
	if found.x < 0:
		return []
	var path: Array[Vector2i] = []
	var node: Vector2i = found
	while node != Vector2i(-1, -1):
		path.push_front(node)
		node = parent[node]
	return path


## 找出一个「拿掉之后起点就到不了终点」的格子。找不到返回 (-1,-1)。
## protected_cell 是追逐者不许站的那格（终点），不算候选。
## 割点必然落在任意一条起点->终点的路径上，所以只扫这条路径就够了。
static func find_cut_vertex(m: Maze, start: Vector2i, goals: Dictionary, protected_cell: Vector2i) -> Vector2i:
	for c: Vector2i in path_to_goal(m, start, goals):
		if c == start or c == protected_cell:
			continue
		if not route_exists(m, start, goals, c):
			return c
	return Vector2i(-1, -1)


## 反复「找割点 -> 在旁边开绕行通道」，直到没有单个格子能切断起点到终点的路。
## 这就是玩家不会被一只追逐者堵死的保证：任何一格被占，都还有路。
static func ensure_robust(m: Maze, start: Vector2i, goals: Dictionary, protected_cell: Vector2i,
		rng: RandomNumberGenerator, max_carves: int = 200) -> int:
	var carves: int = 0
	while carves < max_carves:
		var cut: Vector2i = find_cut_vertex(m, start, goals, protected_cell)
		if cut.x < 0:
			return carves
		var ok: bool = m.open_bypass_near(cut, rng)
		if not ok:
			ok = m.open_random_loop(rng)
		if not ok:
			return carves
		carves += 1
	return carves


# ------------------------------------------------------------------ 迷宫生成入口


## 造出「半边地图」：迷宫 + 中心的终点 + 三个门 + 公平性改造。
## side: 0 = 左半边（终点贴在右边缘），1 = 右半边（终点贴在左边缘）。
## with_chaser: 有追逐者时才做打通死胡同 / 消除割点 —— 否则玩家会被一只怪堵死在必经之路上。
## 返回 { "maze": Maze, "start": Vector2i, "goal": Vector2i, "gates": Dictionary }
static func build_half(w: int, h: int, side: int, rng: RandomNumberGenerator, with_chaser: bool) -> Dictionary:
	var m := Maze.generate(w, h, rng)
	var cy: int = clampi(int((float(h) - 1.0) * 0.5) | 1, 3, m.height - 4)
	var inner: int = -1 if side == 0 else 1
	var goal := Vector2i(m.width - 1, cy) if side == 0 else Vector2i(0, cy)
	var start := Vector2i(1, 1) if side == 0 else Vector2i(m.width - 2, m.height - 2)

	# 终点有三个口：正对迷宫的一道，上下各一道绕过来的侧门。
	# 只开一个口的话，追逐者往那一站就是必死局。
	m.carve_at(goal)
	m.carve(goal.x + inner, goal.y)
	m.carve(goal.x, goal.y - 1)
	m.carve(goal.x + inner, goal.y - 1)
	m.carve(goal.x + inner, goal.y - 2)
	m.carve(goal.x, goal.y + 1)
	m.carve(goal.x + inner, goal.y + 1)
	m.carve(goal.x + inner, goal.y + 2)

	var gates: Dictionary = {}
	gates[Vector2i(goal.x + inner, goal.y)] = true
	gates[Vector2i(goal.x, goal.y - 1)] = true
	gates[Vector2i(goal.x, goal.y + 1)] = true

	if with_chaser:
		m.braid(rng)
		ensure_robust(m, start, gates, goal, rng)

	return {"maze": m, "start": start, "goal": goal, "gates": gates}


# ------------------------------------------------------------------ 寻路


## 从 from 出发的 BFS 步数表，键是 Vector2i，值是该格子的步数。
static func bfs_distances(m: Maze, from: Vector2i) -> Dictionary:
	var dist: Dictionary = {}
	if not m.is_floor_at(from):
		return dist
	dist[from] = 0
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = int(dist[cur])
		for dir: Vector2i in DIRS:
			var nxt: Vector2i = cur + dir
			if not m.is_floor_at(nxt) or dist.has(nxt):
				continue
			dist[nxt] = d + 1
			queue.append(nxt)
	return dist


## 从 from 朝 to 沿最短路径走一格；走不到或已经在 to 就返回 from。
static func bfs_next_step(m: Maze, from: Vector2i, to: Vector2i) -> Vector2i:
	if from == to:
		return from
	var dist: Dictionary = bfs_distances(m, to)
	if not dist.has(from):
		return from
	var best: Vector2i = from
	var best_d: int = int(dist[from])
	for dir: Vector2i in DIRS:
		var nxt: Vector2i = from + dir
		if not m.is_floor_at(nxt) or not dist.has(nxt):
			continue
		var nd: int = int(dist[nxt])
		if nd < best_d:
			best_d = nd
			best = nxt
	return best
