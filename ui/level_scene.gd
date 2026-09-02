class_name LevelScene
extends Control
## 关卡场景(美术参考图 information/art_spec_20260829/image 4.png):
## 乳黄底 + 左侧仪器架(图)+ 中间棋盘(GraphEdit,自带工具条挂必需按钮)+ 右缘诺拉的笔记抽屉(图)。
## 不显示当前关名/目标文字(美术要求);目标纹样只在棋盘的目标织机节点上看。
## 小机「请指导我」(Robot.guide_requested):坏掉前(3-1 通关前)小机回头到极限后直接代解(无鼓励无庆祝),
## 坏掉后(3-2 起)只会乱动(判定在 Game.robot_mode;结局 4-3 剧情播完才修好)。
## 无机器人模式(Robot.enabled = false):求助提示不显示、发呆计时不跑、代解入口关闭(见 _robot_on)。
## 有 Game autoload 且设了 current 关卡时从 LevelDef 读配置(含棋盘恢复);
## 否则用下面的默认字段(冒烟测试直接注入)。
## 坐标为 3840×2160 逻辑像素;美术调位置改下面常量。

var session := ProofSession.new()

const BG_COLOR := Color(0.957, 0.925, 0.847)           # 乳黄
const PALETTE_POS := Vector2(27, 20)                    # 仪器架左上角(图 687×2117;关内预览图顶/底花纹双锚点匹配实测 (27,20)±10)
const BOARD_RECT := Rect2(884, 22, 2436, 2116)          # 棋盘区(右侧留出笔记夹子 NotebookUI.CLOSED_PEEK)
const TOOLBAR_FONT_SIZE := 44
const IDLE_HINT_SEC := 45.0
const GUIDE_TURN_SEC := 0.8    # 小机回头到位后再代解
const GUIDE_HOLD_SEC := 2.5    # 代解后小机保持回头的时间,再转回来
const GUIDE_HINT := "有困难可以对小机说:「请指导我」或「请帮帮我」"   # 小机坏掉前(mode == "guide")才显示
const GUIDE_HINT_FONT_SIZE := 40
const GUIDE_HINT_POS := Vector2(920, 2090)   # 棋盘左下角外侧
const STEP_HINT_POS := Vector2(920, 2036)    # 操作指引(StepGuide):求助提示的上一行;美术之后换图/挪位改这里
const STEP_HINT_FONT_SIZE := 40
const STEP_HINT_COLOR := Color(0.627, 0.275, 0.227)   # 红棕,与求助提示区分

var _game: Node = null
var _board: ProofBoard
var _palette: PalettePanel
var _status: Label
var _win_flash: ColorRect
var _editor: PatternEditor
var _notebook_ui: NotebookUI
var _win_popup: WinPopup              # 通关弹窗「织成了」(v1.2):「继续」推进下一关/结局
var _guide_hint: Label
var _step_hint: Label                 # 操作指引一行字(做过一次的操作不再提示)
var _steps_local: Dictionary = {}     # 无 Game(冒烟注入)时的已做操作表
var _pin_target := Vector2i(-1, -1)   # (node_id, out_port) 正在编辑的假设口
var _fresh_state: Dictionary = {}     # setup 刚完成的快照,重置用
var _idle_sec := 0.0                  # 发呆计时 → 小机出声引导
var _restoring := false               # 载入旧棋盘中:求解信号不算玩家操作(不叫小机、不弹通关)
var _guiding := false                 # 小机代解/回头演出进行中(防重入、免鼓励)
var _suppress_win_cue := false        # 代解通关不庆祝
var _last_hint_step: StringName = &""  # 上次显示的指引步骤(换成新一条才响)

# 默认配置(无 Game 时生效;冒烟测试注入)
var assumptions: Array[String] = ["A & B"]
var goal_text := "B & A"
var allowed_rules: Array[StringName] = [&"and_intro", &"and_elim"]
var atom_colors: Dictionary = {&"A": LevelDef.DEFAULT_COLORS[&"A"], &"B": LevelDef.DEFAULT_COLORS[&"B"]}
var atoms: Array[StringName] = [&"A", &"B"]
var allow_bot := false


func _ready() -> void:
	_game = get_node_or_null("/root/Game")
	var lv: LevelDef = _game.current if _game != null else null
	if lv != null:
		assumptions = lv.assumptions
		goal_text = lv.goal
		allowed_rules = lv.allowed_rules
		atoms = lv.atoms
		atom_colors = lv.effective_colors()
		allow_bot = lv.allow_bot
	var bgm := get_node_or_null("/root/Bgm")
	if bgm != null:
		bgm.play(bgm.slot_for_chapter(_game.current_chapter() if _game != null else -1))
	add_child(session)
	_build_ui()
	session.proof_completed.connect(_on_win)
	session.board_updated.connect(_on_conflict_check)
	session.board_updated.connect(func() -> void: _idle_sec = 0.0)
	var robot := get_node_or_null("/root/Robot")
	if robot != null:
		robot.guide_requested.connect(_on_guide_requested)
	set_process(_robot_on())   # 发呆计时只服务小机语音提示;无机器人模式不跑每帧
	var err := session.setup(assumptions, goal_text)
	assert(err == "", err)
	_layout_endpoints()
	_fresh_state = session.save_state()
	_palette.set_rules(allowed_rules)
	# 本关的笔记整页图现在就读进来(每张 3840×2160 同步解码约 20 ms),翻页时不再卡一帧
	_notebook_ui.preload_pages(_game.notebook if _game != null else NotebookCatalog.load_default(), allowed_rules)
	if lv != null:
		var saved: Dictionary = _game.save.board_state(lv.id)
		if not saved.is_empty():
			# 已通关的关重开:恢复记录的棋盘但拆掉接进目标织机的线(「差一步完成」,v1.2);
			# 拆线在会话层读档时做,不进撤销栈、也不会重发 proof_completed
			_restoring = true
			_sfx_mute(true)
			session.load_state(saved, _game.save.is_solved(lv.id))
			_sfx_mute(false)
			_restoring = false
			_board.apply_positions()
		if lv.robot_cue_on_enter != "":
			_game.robot_cue(lv.robot_cue_on_enter)
		var debut: Array = _game.catalog.debut_rules(lv)
		if not debut.is_empty():   # 本关首次上架的仪器:进关自动翻到它的笔记页(v1.1 §5;每次进关都弹)
			_notebook_ui.open_at(_game.notebook, allowed_rules, debut[0])
	session.board_updated.connect(_refresh_step_hint)
	_refresh_step_hint()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_palette = PalettePanel.new()
	_palette.position = PALETTE_POS
	add_child(_palette)

	_board = ProofBoard.new()
	_board.position = BOARD_RECT.position
	_board.size = BOARD_RECT.size
	_board.atom_colors = atom_colors
	_board.bind(session)
	add_child(_board)
	_palette.machine_requested.connect(_board.place_machine_at_center)

	# 必需按钮挂在棋盘工具条上(纯文字,悬停变浅走 theme)
	_board.add_toolbar_item(_make_tool_button("重置", _on_reset))
	if _game != null:
		# 测试用「示答」:仅调试版、且本关有脚本化解法时出现;点了重置后自动摆出答案
		if OS.is_debug_build() and _game.current != null and LevelSolutions.DATA.has(_game.current.id):
			var answer_btn := _make_tool_button("示答", _on_show_answer)
			answer_btn.tooltip_text = "测试用:重置并自动摆出本关答案(仅调试版可见)"
			answer_btn.modulate.a = 0.7
			_board.add_toolbar_item(answer_btn)
		_board.add_toolbar_item(_make_tool_button("选关", _on_back))
	# 状态文字放在按钮之后:文字长短变化不会把按钮推来推去(通关瞬间按钮曾从鼠标下溜走)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", TOOLBAR_FONT_SIZE)
	_board.add_toolbar_item(_status)

	_win_flash = ColorRect.new()
	_win_flash.color = Color(0.2, 0.85, 0.35, 0.0)
	_win_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_win_flash)

	# 「请指导我 / 请帮帮我」提示(用户要求要提示出来);第三四章不代解就不显示
	_guide_hint = Label.new()
	_guide_hint.text = GUIDE_HINT
	_guide_hint.position = GUIDE_HINT_POS
	_guide_hint.add_theme_font_size_override("font_size", GUIDE_HINT_FONT_SIZE)
	_guide_hint.modulate.a = 0.85
	_guide_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_hint.visible = _game != null and _game.robot_mode() == "guide" and _robot_on()
	add_child(_guide_hint)

	# 操作指引(用户要求加;美术文档没有 → 先纯文字,位置/字号/颜色在顶部常量):按棋盘状态提示下一步操作,做过一次就不再显示
	_step_hint = Label.new()
	_step_hint.position = STEP_HINT_POS
	_step_hint.add_theme_font_size_override("font_size", STEP_HINT_FONT_SIZE)
	_step_hint.add_theme_color_override("font_color", STEP_HINT_COLOR)
	_step_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_step_hint.visible = false
	add_child(_step_hint)

	_editor = PatternEditor.new()
	_editor.pattern_committed.connect(_on_pattern_committed)
	_editor.pattern_cleared.connect(_on_pattern_cleared)
	add_child(_editor)
	_board.pin_requested.connect(_on_pin_requested)

	# 右缘诺拉的笔记抽屉(七台仪器说明),点夹子划出/收回
	_notebook_ui = NotebookUI.new()
	_notebook_ui.open_requested.connect(_on_open_notebook)
	add_child(_notebook_ui)

	# 通关弹窗(v1.2,替代工具条「下一关」):随场景销毁;无 Game/关卡(冒烟注入)时建了不弹
	_win_popup = WinPopup.new()
	_win_popup.continue_pressed.connect(_on_continue)
	add_child(_win_popup)


func _make_tool_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", TOOLBAR_FONT_SIZE)
	b.pressed.connect(cb)
	if text == "重置":
		b.set_meta(SoundFx.META, &"")       # _on_reset 里响 reset_board
	elif text == "选关":
		b.set_meta(SoundFx.META, &"back")
	return b


func _on_open_notebook() -> void:
	var nb: NotebookCatalog = _game.notebook if _game != null else NotebookCatalog.load_default()
	_notebook_ui.open(nb, allowed_rules)   # 只显示本关上架仪器的说明


# ---- 操作指引(StepGuide) ----

func _steps_done() -> Dictionary:
	return _game.save.steps if _game != null else _steps_local


## 记一次操作;首次记下返回 true
func _mark_step(step: StringName) -> bool:
	if _game != null:
		return _game.save.mark_step_done(step)
	if _steps_local.has(String(step)):
		return false
	_steps_local[String(step)] = true
	return true


## 每次棋盘变化:先把棋盘上已经做出来的操作记为做过,再挑下一条要提示的
func _refresh_step_hint() -> void:
	var facts := StepGuide.facts_of(session, not allowed_rules.is_empty())
	var dirty := false
	for step in StepGuide.newly_done(facts):
		dirty = _mark_step(step) or dirty
	if dirty and _game != null:
		_game.save.save()
	var step := StepGuide.next_step(facts, _steps_done())
	_step_hint.text = StepGuide.TEXT.get(step, "")
	_step_hint.visible = step != &""
	if step != &"" and step != _last_hint_step and not _restoring:
		SoundFx.hit(self, &"hint")
	_last_hint_step = step


## 线轴排左列、目标织机放右侧(棋盘画布坐标)
func _layout_endpoints() -> void:
	var y := 160.0
	for id in session.assumption_ids:
		session.set_node_position(id, Vector2(120, y))
		y += 300
	session.set_node_position(session.goal_id, Vector2(1800, 300))
	_board.apply_positions()


# ---- 假设口钉纹样 ----

func _on_pin_requested(node_id: int, out_port: int) -> void:
	_pin_target = Vector2i(node_id, out_port)
	var info := session.describe_node(node_id)
	var initial: Formula = null
	var pinned := info != null and info.pinned.has(out_port)
	if pinned:
		initial = FormulaParser.parse(info.pinned[out_port])
	_editor.open_for(atoms, atom_colors, initial, allow_bot)


func _on_pattern_committed(f: Formula) -> void:
	var err := session.pin_hypothesis(_pin_target.x, _pin_target.y, FormulaParser.to_text(f))
	if err != "":
		_status.text = err
		SoundFx.hit(self, &"pin_error")
	else:
		SoundFx.hit(self, &"confirm")
		if not session.is_solved():
			_status.text = ""


func _on_pattern_cleared() -> void:
	session.unpin_hypothesis(_pin_target.x, _pin_target.y)
	SoundFx.hit(self, &"unpin")


func _unhandled_input(event: InputEvent) -> void:
	if _win_popup.visible:
		return   # 通关弹窗开着:遮罩只挡鼠标,撤销/重做会把弹窗后面的通关盘改掉
	if event.is_action_pressed("ui_undo"):
		if session.can_undo():
			SoundFx.hit(self, &"undo")   # 栈空不响(undo() 本身是空操作)
		session.undo()
		_status.text = ""
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_redo"):
		if session.can_redo():
			SoundFx.hit(self, &"redo")
		session.redo()
		get_viewport().set_input_as_handled()


## 发呆太久 → 小机语音引导(Robot 侧对 hint 也有节流)
func _process(delta: float) -> void:
	if _game == null or session.is_solved():
		return
	_idle_sec += delta
	if _idle_sec >= IDLE_HINT_SEC:
		_idle_sec = 0.0
		_game.robot_cue("hint")


## 接出冲突线 → 小机困惑(Robot 侧自带节流,这里只管报);代解期间不鼓励
func _on_conflict_check() -> void:
	if _game == null or _guiding:
		return
	for w in session.get_wires():
		if w.state == ProofSession.WireState.CONFLICT:
			_game.robot_cue("confused")
			return


# ---- 胜负与流程 ----

func _on_win() -> void:
	_status.text = "织成了!"
	if _restoring:
		return   # 记档未通关却载入了通关盘(不该发生的旧档):不闪光、不叫小机、不记档、不弹
	var tw := create_tween()
	tw.tween_property(_win_flash, "color:a", 0.35, 0.25)
	tw.tween_property(_win_flash, "color:a", 0.0, 0.9)
	if not _suppress_win_cue:
		SoundFx.hit(self, &"win")   # 玩家自己织成的才响;小机代解不庆祝
	if _game != null:
		_game.notify_solved(session.save_state(), not _suppress_win_cue)
		if _game.current != null:   # 冒烟注入的关(current 为空)没有推进目标,不弹
			_win_popup.open()       # 小机代解通关也弹(原来「下一关」也会出现)


# ---- 小机「请指导我」 ----

## 实体小机是否启用(Robot autoload 在且非无机器人模式);关掉时一切指向小机的提示/演出都不出现
func _robot_on() -> bool:
	var robot := get_node_or_null("/root/Robot")
	return robot != null and bool(robot.enabled)


func _on_guide_requested() -> void:
	if _game == null or _guiding or session.is_solved() or not _robot_on():
		return
	var robot := get_node_or_null("/root/Robot")
	if robot == null:
		return
	match _game.robot_mode():
		"guide":
			SoundFx.hit(self, &"guide")
			_run_guide(robot)
		"broken":
			_game.robot_cue("glitch")   # 故障态:任何 cue 都是故障演出


## 第一二章:回头到极限 → 代解(无鼓励无庆祝)→ 停一会儿 → 转回来
func _run_guide(robot: Node) -> void:
	_guiding = true
	robot.cue("think")
	robot.turn_to_limit()
	await get_tree().create_timer(GUIDE_TURN_SEC).timeout
	if not is_inside_tree():
		return
	_idle_sec = 0.0
	if not session.is_solved():   # 等待窗口里玩家自己解出来了:不重摆、不覆盖玩家的解,只完成回头演出
		_suppress_win_cue = true
		_sfx_mute(true)   # 代解的放机/接线/钉纹样不是玩家操作,不响
		_reset_board()
		LevelSolutions.apply(self, _board, _game.current.id)
		_sfx_mute(false)
		_suppress_win_cue = false
	await get_tree().create_timer(GUIDE_HOLD_SEC).timeout
	if not is_inside_tree():
		return   # 场景已销毁:回正由 _exit_tree 兜底
	robot.return_center()
	robot.cue("idle")
	_guiding = false


## 演出/代解期间点「继续/选关」离开:协程随场景销毁,await 之后的回正永不执行 ——
## 否则实体小机会永远停在极限角 + think 脸。这里兜底转回正面。
func _exit_tree() -> void:
	if not _guiding:
		return
	_guiding = false
	var robot := get_node_or_null("/root/Robot")
	if robot != null:
		robot.return_center()
		robot.cue("idle")


## 通关弹窗「继续」:有下一关 → 下一关;最后一关且有结局剧情 → 播 4-3 → 感谢游玩;
## 都没有(目录外注入的关)→ 回选关。通关盘已由 notify_solved 记档,弹窗是模态的,盘不会再变
func _on_continue() -> void:
	if _game.next_level() != null:
		_game.start_level(_game.next_level())
	elif _game.current != null and _game.current.outro_dialogue != null \
			and not _game.current.outro_dialogue.lines.is_empty():
		_game.play_ending()
	else:
		_game.goto_select()


func _on_back() -> void:
	_game.store_board(session.save_state())
	_game.goto_select()


func _on_reset() -> void:
	if _guiding:
		return   # 小机代解/回头演出中,别和它抢棋盘
	_reset_board()
	SoundFx.hit(self, &"reset_board")


## 静音计数进出(代解 / 载入旧棋盘):没有 Sfx autoload(测试)就跳过
func _sfx_mute(on: bool) -> void:
	var sfx := get_node_or_null(^"/root/Sfx") if is_inside_tree() else null
	if sfx == null:
		return
	if on:
		sfx.push_mute()
	else:
		sfx.pop_mute()


func _reset_board() -> void:
	session.load_state(_fresh_state)
	_layout_endpoints()
	_status.text = ""


## 测试用:重置后按 levels/level_solutions.gd 的脚本化解法自动通关(仅调试版有入口)
func _on_show_answer() -> void:
	if _guiding:
		return   # 代解 0.8s 窗口内点示答会双重摆盘、庆祝 cue 和演出打架
	_reset_board()
	_sfx_mute(true)
	LevelSolutions.apply(self, _board, _game.current.id)
	_sfx_mute(false)
