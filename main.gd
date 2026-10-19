extends Control

## 双窗迷宫
##   · 一个窗口里左、右两个子视口，各画同一张大地图的左半边 / 右半边
##   · 左窗起始归属 W/S（上下），右窗起始归属 A/D（左右）
##   · 按 E 只交换「移动方式」：两组按键归属互换，两个角色原地不动
##   · 两个角色都站到大地图中心（那道缝）才算通关
##   · 难度 1/2/3：迷宫尺寸 + 追逐者有无与速度
##
## 命令行（开发用）：
##   godot --path . -- --capture=D:/x/shot.png   跑一会儿截图后退出
##   godot --headless --path . -- --selftest     跑按键路由/交换/通关的集成自测

const LEVELS: Array[Dictionary] = [
	{"label": "简单 · 13×9 · 无追逐者", "w": 13, "h": 9, "chaser": 0.0},
	{"label": "普通 · 17×11 · 有追逐者", "w": 17, "h": 11, "chaser": 0.85},
	{"label": "困难 · 23×15 · 追逐者更快", "w": 23, "h": 15, "chaser": 0.50},
]

const STEP_INTERVAL: float = 0.135

var level_index: int = 1
var vertical_panel: int = 0
var state: String = "playing"

var _panels: Array[PanelWorld] = []
var _ui_font: Font = null
var _rng := RandomNumberGenerator.new()
var _v_timer: float = 0.0
var _h_timer: float = 0.0
var _test_fails: int = 0

@onready var _diff_label: Label = $TopBar/Difficulty
@onready var _status_label: Label = $TopBar/Status
@onready var _left_box: SubViewportContainer = $Split/LeftBox
@onready var _right_box: SubViewportContainer = $Split/RightBox


func _ready() -> void:
	_setup_input()
	_ui_font = _load_ui_font()
	var th := Theme.new()
	th.default_font = _ui_font
	th.default_font_size = 17
	theme = th
	_rng.randomize()
	_panels = [_make_panel(_left_box), _make_panel(_right_box)]
	var start_level: int = level_index
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			start_level = clampi(int(arg.split("=")[1]) - 1, 0, LEVELS.size() - 1)
	start_game(start_level)
	print("[dual-maze] ready, panels=", _panels.size())
	if "--selftest" in OS.get_cmdline_user_args():
		_run_selftest()
	else:
		_maybe_capture()


## 输入映射在代码里建，避免手写 project.godot 的 InputEvent 序列化。
func _setup_input() -> void:
	_bind_action("up", [KEY_W])
	_bind_action("down", [KEY_S])
	_bind_action("left", [KEY_A])
	_bind_action("right", [KEY_D])
	_bind_action("swap", [KEY_E])
	_bind_action("restart", [KEY_R])
	_bind_action("level_1", [KEY_1])
	_bind_action("level_2", [KEY_2])
	_bind_action("level_3", [KEY_3])


func _bind_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, 0.2)
	for k: int in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _load_ui_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei",
		"Noto Sans CJK SC", "PingFang SC", "sans-serif",
	])
	return f


func _make_panel(box: SubViewportContainer) -> PanelWorld:
	var vp := box.get_child(0) as SubViewport
	var world := PanelWorld.new()
	world.name = "World"
	world.badge_font = _ui_font
	world.reached_goal.connect(_on_reached_goal)
	world.player_caught.connect(_on_player_caught)
	vp.add_child(world)
	return world


func start_game(idx: int) -> void:
	level_index = clampi(idx, 0, LEVELS.size() - 1)
	var cfg: Dictionary = LEVELS[level_index]
	var w: int = int(cfg["w"])
	var h: int = int(cfg["h"])
	var chase_every: float = float(cfg["chaser"])
	var seed_value: int = _rng.randi()
	for i in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value + i * 7919
		var built: Dictionary = Maze.build_half(w, h, i, rng, chase_every > 0.0)
		_panels[i].configure(built["maze"], i, built["start"], built["goal"], chase_every)
	vertical_panel = 0
	state = "playing"
	_v_timer = 0.0
	_h_timer = 0.0
	_refresh_ui()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("swap"):
		if state == "playing":
			vertical_panel = 1 - vertical_panel
			_refresh_ui()
	elif event.is_action_pressed("restart"):
		start_game(level_index)
	elif event.is_action_pressed("level_1"):
		start_game(0)
	elif event.is_action_pressed("level_2"):
		start_game(1)
	elif event.is_action_pressed("level_3"):
		start_game(2)


func _process(delta: float) -> void:
	if state != "playing" or _panels.size() < 2:
		return
	# W/S 永远表示「上下」，只是当前归 vertical_panel 那个窗口
	var vdir: int = 0
	var up: bool = Input.is_action_pressed("up")
	var down: bool = Input.is_action_pressed("down")
	if up and not down:
		vdir = -1
	elif down and not up:
		vdir = 1
	if vdir != 0:
		_v_timer -= delta
		if _v_timer <= 0.0:
			_panels[vertical_panel].step(Vector2i(0, vdir))
			_v_timer = STEP_INTERVAL
	else:
		_v_timer = 0.0

	# A/D 永远表示「左右」，归另一个窗口
	var hdir: int = 0
	var left: bool = Input.is_action_pressed("left")
	var right: bool = Input.is_action_pressed("right")
	if left and not right:
		hdir = -1
	elif right and not left:
		hdir = 1
	if hdir != 0:
		_h_timer -= delta
		if _h_timer <= 0.0:
			_panels[1 - vertical_panel].step(Vector2i(hdir, 0))
			_h_timer = STEP_INTERVAL
	else:
		_h_timer = 0.0


func _on_reached_goal() -> void:
	if state != "playing":
		return
	if _panels[0].at_goal and _panels[1].at_goal:
		state = "win"
	_refresh_ui()


func _on_player_caught() -> void:
	if state != "playing":
		return
	state = "lose"
	_refresh_ui()


func _refresh_ui() -> void:
	if _panels.size() < 2:
		return
	var cfg: Dictionary = LEVELS[level_index]
	_diff_label.text = "难度 %d/%d · %s" % [level_index + 1, LEVELS.size(), cfg["label"]]
	for i in _panels.size():
		_panels[i].keys_vertical = (i == vertical_panel)
		_panels[i].queue_redraw()
	match state:
		"win":
			_status_label.text = "通关！两个角色都到达中心 · R 再来一局"
			_status_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.70))
		"lose":
			_status_label.text = "被追逐者抓到 · R 重来"
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.46))
		_:
			_status_label.text = "E 交换上下/左右操作"
			_status_label.add_theme_color_override("font_color", Color(0.62, 0.72, 0.88))


# ---------------------------------------------------------------- 开发用工具


func _maybe_capture() -> void:
	var target: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture"):
			target = arg.split("=")[1] if "=" in arg else "user://capture.png"
	if target.is_empty():
		return
	await get_tree().create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(target)
	print("[dual-maze] capture -> %s (err=%d)" % [target, err])
	get_tree().quit()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		_test_fails += 1
		printerr("  FAIL ", msg)


## 全开放的小迷宫，用来测「哪组按键驱动哪个窗口」这条链路。
func _setup_test_maze() -> void:
	for i in 2:
		var m := Maze.new(7, 7)
		for y in range(1, 6):
			for x in range(1, 6):
				m.carve(x, y)
		_panels[i].configure(m, i, Vector2i(1, 1), Vector2i(3, 1), 0.0)
	vertical_panel = 0
	_v_timer = 0.0
	_h_timer = 0.0


func _run_selftest() -> void:
	print("[selftest] start")
	state = "playing"
	_setup_test_maze()

	# 1) 纵向键归左窗
	await _tap("down")
	_check(_panels[0].player_cell == Vector2i(1, 2), "S 让左窗角色下移 -> %s" % str(_panels[0].player_cell))
	_check(_panels[1].player_cell == Vector2i(1, 1), "S 不影响右窗角色")
	await _tap("up")
	_check(_panels[0].player_cell == Vector2i(1, 1), "W 让左窗角色上移回来")

	# 2) 撞墙不动
	_check(not _panels[0].step(Vector2i(-1, 0)), "撞墙时 step() 返回 false")

	# 3) 横向键归右窗
	await _tap("right")
	_check(_panels[1].player_cell == Vector2i(2, 1), "D 让右窗角色右移 -> %s" % str(_panels[1].player_cell))
	_check(_panels[0].player_cell == Vector2i(1, 1), "D 不影响左窗角色")

	# 4) 右窗先到终点
	await _tap("right")
	_check(_panels[1].at_goal, "右窗角色到达终点")
	_check(state == "playing", "只有一侧到终点，还不算通关")

	# 5) 按 E 交换移动方式，角色原地不动
	var before_a: Vector2i = _panels[0].player_cell
	var before_b: Vector2i = _panels[1].player_cell
	_press_key(KEY_E)
	_check(vertical_panel == 1, "E 之后上下键归右窗")
	_check(_panels[0].player_cell == before_a and _panels[1].player_cell == before_b, "E 不动角色，只换操作")

	# 6) 交换后横向键归左窗，把左窗也送到终点
	await _tap("right")
	_check(_panels[0].player_cell == Vector2i(2, 1), "E 之后 D 驱动左窗角色")
	await _tap("right")
	_check(_panels[0].at_goal, "左窗角色到达终点")
	_check(state == "win", "两侧都到终点 -> 通关")
	_check(not _panels[0].step(Vector2i(0, 1)), "到终点后角色被钉住，不会被 E/按键带走")

	# 7) 难度切换会重开
	_press_key(KEY_3)
	_check(level_index == 2, "按 3 切到困难")
	_check(state == "playing", "切难度后是新的一局")
	_check(_panels[0].maze.width == 23, "困难难度迷宫宽 23 -> %d" % _panels[0].maze.width)

	# 8) 被追逐者碰到 -> 失败
	var m2 := Maze.new(7, 7)
	for y in range(1, 6):
		for x in range(1, 6):
			m2.carve(x, y)
	_panels[0].configure(m2, 0, Vector2i(1, 1), Vector2i(5, 5), 0.5)
	state = "playing"
	_panels[0].chaser_cell = Vector2i(1, 2)
	_panels[0]._chaser_step()
	_check(state == "lose", "追逐者抓到角色 -> 失败")

	# 9) 追逐者不许踏进终点格（否则最后一格是必死）
	var m3 := Maze.new(7, 7)
	for y in range(1, 6):
		for x in range(1, 6):
			m3.carve(x, y)
	_panels[0].configure(m3, 0, Vector2i(1, 1), Vector2i(3, 3), 0.5)
	state = "playing"
	_panels[0].chaser_cell = Vector2i(2, 3)
	_panels[0].player_cell = Vector2i(3, 3)
	_panels[0]._chaser_step()
	_check(_panels[0].chaser_cell == Vector2i(2, 3), "追逐者不会踏进终点格")

	# 10) 困难难度开一局的耗时（打通死胡同 + 消除割点别太贵）
	var t0: int = Time.get_ticks_msec()
	start_game(2)
	var cost: int = Time.get_ticks_msec() - t0
	_check(cost < 400, "困难难度生成两张地图耗时 %d ms" % cost)

	print("[selftest] fails=", _test_fails)
	get_tree().quit(1 if _test_fails > 0 else 0)


func _tap(action: String) -> void:
	Input.action_release(action)
	await get_tree().process_frame
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame


func _press_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	_input(ev)
