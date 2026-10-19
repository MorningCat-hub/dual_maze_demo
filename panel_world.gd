class_name PanelWorld
extends Node2D

## 一个窗口（半边迷宫）的全部内容：迷宫绘制、角色、追逐者。
## 游戏逻辑完全按格子走，绘制坐标做平滑插值。

signal reached_goal
signal player_caught

const MARGIN_X: float = 14.0
const MARGIN_TOP: float = 50.0
const MARGIN_BOTTOM: float = 14.0

const BG := Color(0.035, 0.045, 0.07)
const FLOOR_LEFT := Color(0.055, 0.075, 0.125)
const FLOOR_RIGHT := Color(0.045, 0.082, 0.075)
const WALL_LEFT := Color(0.150, 0.200, 0.310)
const WALL_RIGHT := Color(0.115, 0.215, 0.195)
const ACCENT_LEFT := Color(0.365, 0.620, 0.980)
const ACCENT_RIGHT := Color(0.250, 0.830, 0.680)
const CHASER_COLOR := Color(1.000, 0.360, 0.420)
const GOAL_COLOR := Color(0.360, 0.950, 0.720)

var maze: Maze = null
var panel_index: int = 0
var goal_cell: Vector2i = Vector2i.ZERO
var player_cell: Vector2i = Vector2i.ZERO
var player_vis: Vector2 = Vector2.ZERO
var chaser_cell: Vector2i = Vector2i.ZERO
var chaser_vis: Vector2 = Vector2.ZERO
var has_chaser: bool = false
var chaser_interval: float = 0.8
var keys_vertical: bool = true
var badge_font: Font = null
var at_goal: bool = false
var game_over: bool = false

var _chaser_wait: float = 0.0
var _cell: float = 24.0
var _origin: Vector2 = Vector2.ZERO
var _vp_size: Vector2 = Vector2.ZERO
var _time: float = 0.0


func configure(m: Maze, index: int, start: Vector2i, goal: Vector2i, chase_every: float) -> void:
	maze = m
	panel_index = index
	goal_cell = goal
	player_cell = start
	player_vis = Vector2(start)
	at_goal = false
	game_over = false
	has_chaser = chase_every > 0.0
	chaser_interval = chase_every
	_chaser_wait = chase_every
	if has_chaser:
		chaser_cell = _pick_chaser_start(start)
		chaser_vis = Vector2(chaser_cell)
	_fit()
	queue_redraw()


## 角色尝试走一格，返回是否真的走动了。
func step(dir: Vector2i) -> bool:
	if maze == null or game_over or at_goal:
		return false
	var target: Vector2i = player_cell + dir
	if not maze.is_floor(target.x, target.y):
		return false
	player_cell = target
	if has_chaser and player_cell == chaser_cell:
		game_over = true
		player_caught.emit()
		return true
	if player_cell == goal_cell:
		at_goal = true
		reached_goal.emit()
	return true


func _process(delta: float) -> void:
	_time += delta
	if maze == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp != _vp_size:
		_fit()
	var k: float = 1.0 - exp(-18.0 * delta)
	player_vis = player_vis.lerp(_cell_center(player_cell), k)
	chaser_vis = chaser_vis.lerp(_cell_center(chaser_cell), 1.0 - exp(-11.0 * delta))
	if has_chaser and not game_over and not at_goal:
		_chaser_wait -= delta
		if _chaser_wait <= 0.0:
			_chaser_wait = chaser_interval
			_chaser_step()
	queue_redraw()


func _chaser_step() -> void:
	var nxt: Vector2i = Maze.bfs_next_step(maze, chaser_cell, player_cell)
	if nxt == chaser_cell:
		return
	if nxt == goal_cell:
		# 追逐者不许踏进终点格，否则玩家最后一步是必死的
		return
	chaser_cell = nxt
	if chaser_cell == player_cell:
		game_over = true
		player_caught.emit()


## 追逐者出生点：离角色约一半路程的地方，别贴脸，也别堵在终点门口。
func _pick_chaser_start(start: Vector2i) -> Vector2i:
	var dist: Dictionary = Maze.bfs_distances(maze, start)
	if dist.size() <= 1:
		return start
	var max_d: int = 0
	for key: Vector2i in dist.keys():
		max_d = maxi(max_d, int(dist[key]))
	var want: int = int(round(float(max_d) * 0.55))
	var best: Vector2i = start
	var best_gap: int = 1 << 30
	for key: Vector2i in dist.keys():
		var d: int = int(dist[key])
		if d <= 0:
			continue
		# 终点及其门口两格不放追逐者
		if absi(key.x - goal_cell.x) + absi(key.y - goal_cell.y) <= 2:
			continue
		var gap: int = absi(d - want)
		if gap < best_gap:
			best_gap = gap
			best = key
	return best


func _fit() -> void:
	if maze == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x < 8.0 or vp.y < 8.0:
		return
	_vp_size = vp
	var avail := Vector2(vp.x - MARGIN_X * 2.0, vp.y - MARGIN_TOP - MARGIN_BOTTOM)
	var fit: float = minf(avail.x / float(maze.width), avail.y / float(maze.height))
	_cell = maxf(6.0, floorf(fit))
	var total := Vector2(maze.width, maze.height) * _cell
	_origin = Vector2((vp.x - total.x) * 0.5, MARGIN_TOP + (avail.y - total.y) * 0.5)


func _cell_center(c: Vector2i) -> Vector2:
	return _origin + Vector2(float(c.x) + 0.5, float(c.y) + 0.5) * _cell


func _cell_rect(x: int, y: int) -> Rect2:
	return Rect2(_origin + Vector2(float(x), float(y)) * _cell, Vector2(_cell, _cell))


func _draw() -> void:
	if maze == null or _vp_size == Vector2.ZERO:
		return
	var accent: Color = ACCENT_LEFT if panel_index == 0 else ACCENT_RIGHT
	var fresh: Color = FLOOR_LEFT if panel_index == 0 else FLOOR_RIGHT
	var wall: Color = WALL_LEFT if panel_index == 0 else WALL_RIGHT

	draw_rect(Rect2(Vector2.ZERO, _vp_size), BG)

	for y in maze.height:
		for x in maze.width:
			var rect := _cell_rect(x, y)
			if maze.is_floor(x, y):
				draw_rect(rect, fresh)
			else:
				draw_rect(rect, wall)
				draw_line(rect.position + Vector2(0.0, 1.0),
					rect.position + Vector2(_cell, 1.0),
					Color(wall.r + 0.06, wall.g + 0.06, wall.b + 0.08, 1.0), 1.0)

	_draw_goal()
	if has_chaser:
		_draw_chaser()
	_draw_player(accent)
	_draw_seam(accent)
	_draw_badge(accent)
	draw_rect(Rect2(Vector2(0.5, 0.5), _vp_size - Vector2(1.0, 1.0)), accent, false, 2.0)


func _draw_goal() -> void:
	var g: Vector2 = _cell_center(goal_cell)
	var pulse: float = 0.5 + 0.5 * sin(_time * 3.2)
	draw_circle(g, _cell * (0.62 + 0.10 * pulse), Color(GOAL_COLOR.r, GOAL_COLOR.g, GOAL_COLOR.b, 0.14 + 0.10 * pulse))
	draw_arc(g, _cell * 0.36, 0.0, TAU, 28, GOAL_COLOR, maxf(1.5, _cell * 0.09), true)
	draw_circle(g, _cell * 0.11, GOAL_COLOR)


func _draw_player(accent: Color) -> void:
	var p: Vector2 = player_vis
	var r: float = _cell * 0.30
	draw_circle(p, r * 2.0, Color(accent.r, accent.g, accent.b, 0.13))
	draw_circle(p, r, Color(0.960, 0.972, 1.000))
	draw_circle(p, r * 0.46, accent)


func _draw_chaser() -> void:
	var c: Vector2 = chaser_vis
	var r: float = _cell * 0.32
	draw_circle(c, r * 1.8, Color(CHASER_COLOR.r, CHASER_COLOR.g, CHASER_COLOR.b, 0.12))
	var pts := PackedVector2Array([
		c + Vector2(0.0, -r),
		c + Vector2(r, 0.0),
		c + Vector2(0.0, r),
		c + Vector2(-r, 0.0),
	])
	draw_colored_polygon(pts, CHASER_COLOR)
	pts.append(pts[0])
	draw_polyline(pts, Color(1.0, 0.78, 0.80), maxf(1.0, _cell * 0.06), true)


## 大地图中心那道缝：左窗画在右边缘外侧，右窗画在左边缘外侧。
func _draw_seam(accent: Color) -> void:
	var gap: float = maxf(4.0, _cell * 0.22)
	var x: float = (_origin.x + float(maze.width) * _cell + gap) if panel_index == 0 else (_origin.x - gap)
	var y0: float = _origin.y
	var y1: float = _origin.y + float(maze.height) * _cell
	var dash: float = maxf(4.0, _cell * 0.4)
	var y: float = y0
	while y < y1:
		draw_line(Vector2(x, y), Vector2(x, minf(y + dash, y1)),
			Color(accent.r, accent.g, accent.b, 0.45), maxf(1.0, _cell * 0.08))
		y += dash * 2.0


func _draw_badge(accent: Color) -> void:
	var font: Font = badge_font if badge_font != null else ThemeDB.fallback_font
	var fs: int = int(clampf(_cell * 0.52, 13.0, 21.0))
	var title: String = "左窗 · 左半张地图" if panel_index == 0 else "右窗 · 右半张地图"
	var keys: String = "W / S   上下移动" if keys_vertical else "A / D   左右移动"
	var w1: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w2: float = font.get_string_size(keys, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Vector2(maxf(w1, w2) + float(fs) * 2.0, float(fs) * 2.9)
	var pos := Vector2(MARGIN_X, 10.0)
	draw_rect(Rect2(pos, box), Color(0.02, 0.03, 0.05, 0.85))
	draw_rect(Rect2(pos, box), Color(accent.r, accent.g, accent.b, 0.75), false, 1.0)
	draw_string(font, pos + Vector2(float(fs) * 0.7, float(fs) * 1.15), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, accent)
	draw_string(font, pos + Vector2(float(fs) * 0.7, float(fs) * 2.35), keys,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.880, 0.910, 0.980))
