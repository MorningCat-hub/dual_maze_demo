extends SceneTree

## 逻辑自测（headless）：
##   godot --headless --path . --script res://tests/logic_test.gd
##
## 这里最重要的是**公平性**那一组断言：
##   有追逐者的关卡，不许存在「拿掉某一格就让起点到不了终点」的割点，
##   也不许有死胡同（每格至少两个出口）。
## 只要这两条成立，一只追逐者就不可能永远堵死玩家。

const MazeScript := preload("res://scripts/maze.gd")

const SIZES: Array[Vector2i] = [
	Vector2i(13, 9),
	Vector2i(17, 11),
	Vector2i(23, 15),
]

var fails: int = 0
var cases: int = 0


func _initialize() -> void:
	for size: Vector2i in SIZES:
		var with_chaser: bool = (size != Vector2i(13, 9))
		for side in 2:
			for seed_value in range(1, 21):
				_check_case(size, side, seed_value, with_chaser)

	print("cases=%d fails=%d" % [cases, fails])
	if fails == 0:
		print("ALL OK")
	quit(0 if fails == 0 else 1)


func _fail(msg: String) -> void:
	fails += 1
	printerr("FAIL " + msg)


func _check_case(size: Vector2i, side: int, seed_value: int, with_chaser: bool) -> void:
	cases += 1
	var tag := "size=%s side=%d seed=%d" % [str(size), side, seed_value]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + side * 131

	var built: Dictionary = MazeScript.build_half(size.x, size.y, side, rng, with_chaser)
	var m = built["maze"]
	var start: Vector2i = built["start"]
	var goal: Vector2i = built["goal"]
	var gates: Dictionary = built["gates"]

	if m.width % 2 == 0 or m.height % 2 == 0:
		_fail("迷宫尺寸必须是奇数 " + tag)
		return

	if not m.is_floor_at(start):
		_fail("起点没挖开 " + tag)
		return
	if not m.is_floor_at(goal):
		_fail("终点没挖开 " + tag)
		return
	if gates.size() != 3:
		_fail("终点门数量不是 3 " + tag)
		return
	for g: Vector2i in gates.keys():
		if not m.is_floor_at(g):
			_fail("门没挖开 %s %s" % [str(g), tag])
			return
		if absi(g.x - goal.x) + absi(g.y - goal.y) != 1:
			_fail("门不贴着终点 %s %s" % [str(g), tag])
			return

	var dist: Dictionary = MazeScript.bfs_distances(m, start)
	var reachable_gate := false
	for g: Vector2i in gates.keys():
		if dist.has(g):
			reachable_gate = true
			break
	if not reachable_gate:
		_fail("起点到不了终点任何一个门 " + tag)
		return

	if with_chaser:
		# 公平性 1：没有任何一格是割点（站上去就把玩家和终点彻底隔开）。
		# 门格也要算进来 —— 追逐者可以站在门口，那样玩家得还能从另外两个门进去。
		for c: Vector2i in m.floor_cells():
			if c == start or c == goal:
				continue
			if not MazeScript.route_exists(m, start, gates, c):
				_fail("割点存在：站在 %s 就能堵死玩家 %s" % [str(c), tag])
				return
		# 公平性 2：没有死胡同（每格至少两个出口），不会被逼进死角
		for c: Vector2i in m.floor_cells():
			if m.degree(c) < 2:
				_fail("死胡同：%s 只有 %d 个出口 %s" % [str(c), m.degree(c), tag])
				return

	# 真的顺着 BFS 从起点走到终点
	var cur: Vector2i = start
	var walked: int = 0
	while cur != goal and walked < 4000:
		var nxt: Vector2i = MazeScript.bfs_next_step(m, cur, goal)
		if nxt == cur:
			break
		cur = nxt
		walked += 1
	if cur != goal:
		_fail("走不到终点 walked=%d %s" % [walked, tag])
		return

	# 追逐者从另一头出发，也得能一路朝玩家挪过来
	if with_chaser:
		var probe := Vector2i(m.width - 2, m.height - 2)
		if m.is_floor_at(probe):
			var hunter: Vector2i = probe
			var steps: int = 0
			while hunter != start and steps < 4000:
				var hs: Vector2i = MazeScript.bfs_next_step(m, hunter, start)
				if hs == hunter:
					break
				hunter = hs
				steps += 1
			if hunter != start:
				_fail("追逐者被卡住 %s" % tag)
