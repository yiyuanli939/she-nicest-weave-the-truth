extends SceneTree
## M2 开窗验收:三例证明走 view 路径(palette 放置 + connection_request + 纹样编辑器钉假设)。
##   godot --path . --script res://tests/visual_smoke_m2.gd
## 通关三例且无脚本错误 → 退出码 0;截图在 tests/screenshots/。

const OUT_DIR := "res://tests/screenshots"
const EDITOR_RECT := Rect2(0, 0, 720, 440)   # 与 PatternEditor.PREVIEW_SIZE 一致

var _fails := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await _scenario_imp()
	await _scenario_or()
	await _scenario_bot()
	print("M2_SMOKE_FAILS=", _fails)
	quit(_fails)


func _open(assumptions: Array[String], goal: String, rules: Array[StringName],
		atoms: Array[StringName], allow_bot: bool) -> LevelScene:
	var scene: LevelScene = (load("res://ui/level_scene.tscn") as PackedScene).instantiate()
	scene.assumptions = assumptions
	scene.goal_text = goal
	scene.allowed_rules = rules
	scene.atoms = atoms
	scene.allow_bot = allow_bot
	root.add_child(scene)
	await process_frame
	await process_frame
	return scene


func _board_of(scene: LevelScene) -> ProofBoard:
	return scene.find_children("*", "ProofBoard", true, false)[0]


func _wire(b: ProofBoard, from_id: int, fp: int, to_id: int, tp: int) -> void:
	b.session.connect_wire(from_id, fp, to_id, tp)   # 模型口号(棋盘的 connection_request 是 GraphEdit 图口号)


## 走编辑器 UI 路径把单原子纹样钉到 (node, port)
func _pin_atom(scene: LevelScene, node_id: int, port: int, atom: String) -> void:
	scene._on_pin_requested(node_id, port)
	var e: PatternEditor = scene._editor
	e.brush = "atom:" + atom
	e.apply_brush_at(EDITOR_RECT.get_center(), EDITOR_RECT)
	e.pattern_committed.emit(e.tree)
	e.hide()


func _finish(scene: LevelScene, tag: String) -> void:
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.get_viewport().get_texture().get_image().save_png("%s/m2_%s.png" % [OUT_DIR, tag])
	if scene.session.is_solved():
		print("✓ ", tag)
	else:
		print("✗ ", tag, " 未通关")
		_fails += 1
	scene.queue_free()
	await process_frame


## ⊢ A→(B→A):双封程嵌套 + 编辑器钉 A、B
func _scenario_imp() -> void:
	var s := await _open([], "A > (B > A)", [&"imp_intro"], [&"A", &"B"], false)
	var b := _board_of(s)
	b.place_machine_at_center(&"imp_intro")
	b.place_machine_at_center(&"imp_intro")
	var ids := s.session.get_node_ids()
	var outer: int = ids[-2]
	var inner: int = ids[-1]
	s.session.set_node_position(outer, Vector2(1040, 240))
	s.session.set_node_position(inner, Vector2(1120, 520))
	b.apply_positions()
	_wire(b, inner, 0, outer, 0)                 # (B→A) 汇入外层散口
	_wire(b, outer, 1, inner, 0)                 # 外层假设 A 流入内层子证明
	_wire(b, outer, 0, s.session.goal_id, 0)
	_pin_atom(s, outer, 1, "A")
	_pin_atom(s, inner, 1, "B")
	await _finish(s, "imp_nested")


## A∨B ⊢ B∨A:汇路机 + 两台岔纹机
func _scenario_or() -> void:
	var s := await _open(["A | B"], "B | A", [&"or_elim", &"or_intro"], [&"A", &"B"], false)
	var b := _board_of(s)
	b.place_machine_at_center(&"or_elim")
	b.place_machine_at_center(&"or_intro")
	b.place_machine_at_center(&"or_intro")
	var ids := s.session.get_node_ids()
	var elim: int = ids[-3]
	var i1: int = ids[-2]
	var i2: int = ids[-1]
	s.session.set_node_position(elim, Vector2(600, 220))
	s.session.set_node_position(i1, Vector2(1120, 120))
	s.session.set_node_position(i2, Vector2(560, 260))
	b.apply_positions()
	var spool: int = s.session.assumption_ids[0]
	_wire(b, spool, 0, elim, 0)
	_wire(b, elim, 1, i1, 0)                     # hyp A → 岔纹机1
	_wire(b, i1, 1, elim, 1)                     # 下口 R∨P:B∨A → 散口1
	_wire(b, elim, 2, i2, 0)                     # hyp B → 岔纹机2
	_wire(b, i2, 0, elim, 2)                     # 上口 P∨Q:B∨A → 散口2
	_wire(b, elim, 0, s.session.goal_id, 0)
	_pin_atom(s, i1, 1, "B")                     # 另一支由玩家钉,不从汇路机反推
	_pin_atom(s, i2, 0, "A")
	await _finish(s, "or_commute")


## ⊥ ⊢ A:溃散机
func _scenario_bot() -> void:
	var s := await _open(["false"], "A", [&"false_elim"], [&"A"], true)
	var b := _board_of(s)
	b.place_machine_at_center(&"false_elim")
	var elim: int = s.session.get_node_ids()[-1]
	s.session.set_node_position(elim, Vector2(720, 260))
	b.apply_positions()
	_wire(b, s.session.assumption_ids[0], 0, elim, 0)
	_wire(b, elim, 0, s.session.goal_id, 0)
	_pin_atom(s, elim, 0, "A")                   # 溃散机织什么由玩家钉
	await _finish(s, "explosion")
