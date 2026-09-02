extends TestBase
## ProofSession 门面:团队实际使用的每条路径都在这里过一遍。
## 注意 ProofSession 是 Node,测试里 new 出来的必须 free。


func test_setup_creates_spool_and_loom() -> bool:
	var s := ProofSession.new()
	var err := s.setup(["A & B", "C"], "B & A")
	var spool := s.describe_node(s.assumption_ids[0])
	var loom := s.describe_node(s.goal_id)
	var bad := s.setup(["A &"], "B")
	var ok := check(err == "", "正常建关应返回空串,实际: " + err) \
		and check(s.assumption_ids.size() == 2, "两条假设应建两个线轴") \
		and check(spool.type == ProofSession.NodeType.ASSUMPTION and spool.title == "线轴",
				"线轴的描述应正确") \
		and check(loom.type == ProofSession.NodeType.GOAL and loom.inputs[0].label == "B & A",
				"目标织机应带目标纹样文本") \
		and check(bad != "", "坏公式建关应返回错误文案")
	s.free()
	return ok


func test_place_wire_solve() -> bool:
	var s := ProofSession.new()
	_build_conj_proof(s)
	var woven := s.get_input_pattern(s.goal_id, 0)
	var ok := check(s.is_solved(), "纯 session API 应能完成 A∧B ⊢ B∧A") \
		and check(woven != null and woven.equals(f("B & A")), "目标口应织出 B∧A")
	s.free()
	return ok


func test_connect_replaces_occupied_port() -> bool:
	var s := ProofSession.new()
	s.setup(["A", "B"], "A & B")
	var join := s.place_machine(&"and_intro")
	s.connect_wire(s.assumption_ids[0], 0, join, 0)
	s.connect_wire(s.assumption_ids[1], 0, join, 0)   # 拖到已占用口 → 替换旧线
	var into_port_0: Array[int] = []
	for w in s.get_wires():
		if w.to_id == join and w.to_port == 0:
			into_port_0.append(w.from_id)
	var ok := check(into_port_0 == [s.assumption_ids[1]], "占用口重连应只剩新线")
	s.free()
	return ok


func test_pin_errors_and_success() -> bool:
	var s := ProofSession.new()
	s.setup([], "A > A")
	var m := s.place_machine(&"imp_intro")
	var ok := check(s.pin_hypothesis(m, 1, "A &") != "", "解析失败应返回文案") \
		and check(s.pin_hypothesis(m, 0, "A") == "该口不可钉纹样", "非可钉口应被拦下") \
		and check(s.pin_hypothesis(m, 1, "?x") != "", "含未染纱应被拦下") \
		and check(s.pin_hypothesis(m, 1, "A") == "", "合法钉入应返回空串") \
		and check(s.describe_node(m).pinned[1] == "A", "钉住的纹样应出现在节点描述里")
	s.free()
	return ok


func test_wire_state_and_missing() -> bool:
	var s := ProofSession.new()
	s.setup(["A"], "B")
	s.connect_wire(s.assumption_ids[0], 0, s.goal_id, 0)
	var conflict := s.get_wire_state(s.assumption_ids[0], 0, s.goal_id, 0)
	var s2 := ProofSession.new()
	s2.setup(["A & B"], "B & A")
	var join := s2.place_machine(&"and_intro")
	s2.connect_wire(join, 0, s2.goal_id, 0)
	var ok := check(conflict == ProofSession.WireState.CONFLICT, "A 接 B 应查到冲突态") \
		and check(s2.get_missing_inputs().has(Vector2i(join, 0)), "缺的输入口应在清单里")
	s.free()
	s2.free()
	return ok


func test_undo_redo_preserves_ids() -> bool:
	var s := ProofSession.new()
	s.setup(["A"], "A")
	var no_undo_at_start := not s.can_undo()
	var m := s.place_machine(&"and_intro", Vector2(120, 80))
	s.undo()
	var gone := s.describe_node(m) == null
	s.redo()
	var back := s.describe_node(m)
	var ok := check(no_undo_at_start, "刚建关不应有可撤销项") \
		and check(gone, "undo 后仪器应消失") \
		and check(back != null and back.rule_id == &"and_intro", "redo 应以同一 id 回来") \
		and check(s.get_node_position(m) == Vector2(120, 80), "位置应随快照恢复") \
		and check(not s.can_redo(), "redo 用尽后应置灰")
	s.free()
	return ok


func test_signals() -> bool:
	var s := ProofSession.new()
	var counts := {"updated": 0, "rebuilt": 0, "completed": 0}
	s.board_updated.connect(func() -> void: counts.updated += 1)
	s.board_rebuilt.connect(func() -> void: counts.rebuilt += 1)
	s.proof_completed.connect(func() -> void: counts.completed += 1)
	_build_conj_proof(s)                       # setup + 2 放置 + 4 连线 = 7 次编辑
	var last := s.get_wires()[-1]
	s.disconnect_wire(last.from_id, last.from_port, last.to_id, last.to_port)
	s.connect_wire(last.from_id, last.from_port, last.to_id, last.to_port)
	var ok := check(counts.updated == 9, "每次编辑都应发 board_updated,实际 %d" % counts.updated) \
		and check(counts.rebuilt == 1, "只有 setup 应发 board_rebuilt,实际 %d" % counts.rebuilt) \
		and check(counts.completed == 2, "完成→断线→再完成应发两次 proof_completed,实际 %d" % counts.completed)
	s.free()
	return ok


func test_save_load_json_roundtrip() -> bool:
	var s := ProofSession.new()
	_build_conj_proof(s)
	s.set_node_position(s.goal_id, Vector2(300, 40))
	var text := JSON.stringify(s.save_state())
	var s2 := ProofSession.new()
	s2.load_state(JSON.parse_string(text))
	var ok := check(s2.is_solved(), "读档回来应仍是完成态") \
		and check(s2.get_node_position(s2.goal_id) == Vector2(300, 40), "位置应随档恢复") \
		and check(not s2.can_undo(), "读档应清空撤销历史")
	s.free()
	s2.free()
	return ok


func test_describe_rule_metadata() -> bool:
	var m := ProofSession.describe_rule(&"imp_intro")
	return check(ProofSession.all_rule_ids().size() == 7, "应有七台仪器") \
		and check(m.cn_name == "封程机" and m.inputs.size() == 1 and m.outputs.size() == 2,
				"封程机应为 1 入 2 出") \
		and check(m.outputs[1].is_hypothesis and m.outputs[1].scope_input == 0,
				"1 号输出应是假设口、封存于 0 号输入") \
		and check(not m.outputs[0].is_hypothesis, "0 号输出是普通口") \
		and check(m.outputs[1].pinnable and not m.outputs[0].pinnable, "封程机只有假设口可钉") \
		and check(ProofSession.describe_rule(&"or_intro").outputs[1].pinnable, "岔纹机两口可钉") \
		and check(not ProofSession.describe_rule(&"or_elim").outputs[1].pinnable, "汇路机假设口不可钉") \
		and check(ProofSession.describe_rule(&"nope") == null, "未知仪器应返回 null")


## 纯 session API 复现 A∧B ⊢ B∧A(多个测试共用)
func _build_conj_proof(s: ProofSession) -> void:
	s.setup(["A & B"], "B & A")
	var split := s.place_machine(&"and_elim")
	var join := s.place_machine(&"and_intro")
	s.connect_wire(s.assumption_ids[0], 0, split, 0)
	s.connect_wire(split, 1, join, 0)
	s.connect_wire(split, 0, join, 1)
	s.connect_wire(join, 0, s.goal_id, 0)


func test_wire_carries_hyp() -> bool:
	var s := ProofSession.new()
	var ok := check(s.setup([], "A > A") == "", "setup")
	var m := s.place_machine(&"imp_intro")
	ok = check(s.pin_hypothesis(m, 1, "A") == "", "钉 A") and ok
	s.connect_wire(m, 1, m, 0)
	s.connect_wire(m, 0, s.goal_id, 0)
	ok = check(s.get_wire_carries_hyp(m, 1, m, 0) and not s.get_wire_carries_hyp(m, 0, s.goal_id, 0), "假设口→Q 口的线搭载假设,出口→目标的不搭载") and ok
	var n_hyp := 0
	for w in s.get_wires():
		if w.carries_hyp:
			n_hyp += 1
	ok = check(n_hyp == 1, "WireInfo.carries_hyp 与查询一致(得 %d)" % n_hyp) and ok
	ok = check(not s.get_wire_carries_hyp(m, 0, m, 0), "不存在的线 → false") and ok
	s.free()
	return ok


func test_connected_getters() -> bool:
	var s := ProofSession.new()
	s.setup(["A | B"], "B | A")
	var oe := s.place_machine(&"or_elim", Vector2.ZERO)
	s.connect_wire(s.assumption_ids[0], 0, oe, 0)
	var ok := check(s.is_input_connected(oe, 0), "已接线输入口应 connected") \
		and check(not s.is_input_connected(oe, 1), "未接线支路口不应 connected") \
		and check(not s.is_output_connected(oe, 0), "未接线输出口不应 connected") \
		and check(s.pin_hypothesis(oe, 1, "A") != "", "汇路机假设口由入口正向决定,不可钉")
	var oi := s.place_machine(&"or_intro", Vector2.ZERO)
	var err := s.pin_hypothesis(oi, 0, "B")
	ok = ok and check(err == "", "钉岔纹机上口应成功,实际: " + err) \
		and check(s.is_output_connected(oi, 0), "钉住的口应算 connected(玩家显式承诺,实显)") \
		and check(not s.is_output_connected(oi, 1), "没钉没线的另一口不算 connected")
	s.free()
	return ok


## 自动断开的错线(record_undo = false)不记撤销步,且断开后棋盘回到接线前 → 连接线那一步也弹掉(撤销历史里没有这条线);
## 玩家自己断线照旧记一步
func test_disconnect_without_undo_entry() -> bool:
	var s := ProofSession.new()
	var ok := check(s.setup(["A & B"], "B & A") == "", "setup")
	var m := s.place_machine(&"and_intro")
	var spool: int = s.assumption_ids[0]
	var goal: int = s.goal_id
	var ok_wire := s.connect_wire(spool, 0, goal, 0)
	ok = check(ok_wire and s.get_wire_state(spool, 0, goal, 0) == ProofSession.WireState.CONFLICT, "线轴 A&B 直接接目标 B&A = 冲突线") and ok
	s.disconnect_wire(spool, 0, goal, 0, false)
	ok = check(s.get_wires().is_empty() and s.can_undo() and not s.can_redo(), "自动断开:线没了,只剩「放仪器」可撤销") and ok
	s.undo()
	ok = check(s.get_node_ids().size() == 2 and not s.can_undo(), "撤销一步直接回到放仪器之前(不会复活错线)") and ok
	s.redo()
	s.connect_wire(spool, 0, goal, 0)
	s.disconnect_wire(spool, 0, goal, 0)
	ok = check(s.get_wires().is_empty() and s.can_undo(), "玩家手动断线照旧记一步") and ok
	s.undo()
	ok = check(s.get_wires().size() == 1, "撤销手动断线 → 线回来") and ok
	s.free()
	return ok
