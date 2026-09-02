extends TestBase
## 操作音效 autoload(game/sfx.gd,SoundFx):槽位表文件齐全且短、播放器池取空闲 / 同帧同槽位去重 / 静音计数 / 玩家音量、
## 按钮总钩子(BaseButton 进树自动接 pressed,meta 覆盖与静音)。不碰 /root/Sfx,每例 new() 一个挂到 root 上再释放。


func _make() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var sfx: Node = load("res://game/sfx.gd").new()
	tree.root.add_child(sfx)   # 播放器在 _init 建好;play() 要在树里;_ready 接 node_added
	return sfx


func _drop(sfx: Node) -> void:
	(Engine.get_main_loop() as SceneTree).root.remove_child(sfx)
	sfx.free()


func test_clip_table_files_exist_and_short() -> bool:
	var ok := check(SoundFx.CLIPS.size() >= 30, "槽位表至少 30 条(得 %d)" % SoundFx.CLIPS.size())
	for slot in SoundFx.CLIPS:
		var p: String = SoundFx.CLIPS[slot]
		if p == "":
			continue
		ok = check(ResourceLoader.exists(p), "音效 %s 的文件缺失:%s(改了文件先 --import)" % [slot, p]) and ok
		if not ResourceLoader.exists(p):
			continue
		var stream: AudioStream = load(p)
		var limit := 5.0 if slot == &"win" else 2.0
		ok = check(stream != null and stream.get_length() > 0.0 and stream.get_length() <= limit,
				"音效 %s 应为 0..%.0f s 的短音(得 %.2f)" % [slot, limit, stream.get_length() if stream != null else -1.0]) and ok
	for slot in SoundFx.GAIN_DB:
		ok = check(SoundFx.CLIPS.has(slot), "GAIN_DB 里有不存在的槽位 %s" % slot) and ok
		ok = check(float(SoundFx.GAIN_DB[slot]) >= -12.0 and float(SoundFx.GAIN_DB[slot]) <= 6.0, "增益 %s 越界" % slot) and ok
	# 修正后不削波:基准 -6 dB,片段峰值都在 -1 dB 上下,增益封顶在 +6
	ok = check(SoundFx.BASE_VOLUME <= 0.5, "基准音量不超过 -6 dB(得 %.2f)" % SoundFx.BASE_VOLUME) and ok
	return ok


func test_play_uses_idle_player_and_dedupes_same_frame() -> bool:
	var sfx := _make()
	var ok := check(sfx.play(&"click"), "play 返回 true")
	ok = check(sfx.last_slot == &"click" and sfx.play_count == 1, "记下 last_slot / play_count") and ok
	var busy := 0
	for p in sfx._players:
		if p.playing:
			busy += 1
	ok = check(busy == 1, "只占一个播放器(得 %d)" % busy) and ok
	ok = check(not sfx.play(&"click"), "同一帧同槽位第二次不播") and ok
	ok = check(sfx.play(&"place"), "同一帧不同槽位照播") and ok
	busy = 0
	for p in sfx._players:
		if p.playing:
			busy += 1
	ok = check(busy == 2 and sfx.play_count == 2, "两个槽位占两个播放器(得 %d)" % busy) and ok
	# 池满了就抢:9 个不同槽位全部成功
	var slots: Array = SoundFx.CLIPS.keys()
	var n := 0
	for s in slots:
		if s == &"click" or s == &"place":
			continue
		if sfx.play(s):
			n += 1
		if n >= 7:
			break
	ok = check(n == 7 and sfx.play_count == 9, "池满后仍能播(第 9 声抢最早的;play_count %d)" % sfx.play_count) and ok
	ok = check(not sfx.play(&"no_such_slot"), "未知槽位静默返回 false") and ok
	_drop(sfx)
	return ok


func test_mute_depth_and_user_volume() -> bool:
	var sfx := _make()
	sfx.push_mute()
	sfx.push_mute()
	var ok := check(sfx.is_muted() and not sfx.play(&"click"), "静音中不播")
	sfx.pop_mute()
	ok = check(sfx.is_muted() and not sfx.play(&"click"), "计数没归零仍静音") and ok
	sfx.pop_mute()
	sfx.pop_mute()   # 多 pop 一次不出负
	ok = check(not sfx.is_muted() and sfx.play(&"click"), "归零后恢复") and ok
	sfx.set_user_volume(0.5)
	sfx.play(&"place")
	var vol := -1.0
	for p in sfx._players:
		if p.playing and p.stream == sfx._streams[SoundFx.CLIPS[&"place"]]:
			vol = p.volume_linear
	ok = check(is_equal_approx(vol, SoundFx.target_volume(&"place") * 0.5), "音量 = 基准 × 增益 × 玩家音量(得 %.3f)" % vol) and ok
	sfx.set_user_volume(3.0)
	ok = check(is_equal_approx(sfx.user_volume, 1.0), "玩家音量夹到 1") and ok
	ok = check(is_equal_approx(SoundFx.target_volume(&"no_gain_slot"), SoundFx.BASE_VOLUME), "没有增益条目 = 基准") and ok
	_drop(sfx)
	return ok


func test_button_hook_meta_override_and_silence() -> bool:
	var sfx := _make()
	var tree := Engine.get_main_loop() as SceneTree
	var b := Button.new()
	tree.root.add_child(b)   # node_added → 自动接 pressed
	sfx.last_slot = &""
	b.pressed.emit()
	var ok := check(sfx.last_slot == &"click", "普通按钮按下 → click(得 %s)" % sfx.last_slot)
	var b2 := Button.new()
	b2.set_meta(SoundFx.META, &"back")
	tree.root.add_child(b2)
	b2.pressed.emit()
	ok = check(sfx.last_slot == &"back", "meta 覆盖槽位(得 %s)" % sfx.last_slot) and ok
	var b3 := Button.new()
	b3.set_meta(SoundFx.META, &"")
	tree.root.add_child(b3)
	var before: int = sfx.play_count
	b3.pressed.emit()
	ok = check(sfx.play_count == before, "meta 空串 = 该按钮不出声") and ok
	# 悬停:鼠标刚移动过 → 普通按钮响 hover;禁用 / 静音按钮不响;没有鼠标移动的 mouse_entered(换场景 / 弹窗落在光标底下)不响
	sfx.last_slot = &""
	sfx._mouse_moved_frame = -1
	b.mouse_entered.emit()
	ok = check(sfx.last_slot == &"", "没有鼠标移动的 mouse_entered 不响 hover(得 %s)" % sfx.last_slot) and ok
	sfx._mouse_moved_frame = Engine.get_process_frames()
	b.mouse_entered.emit()
	ok = check(sfx.last_slot == &"hover", "悬停 → hover") and ok
	before = sfx.play_count
	b.disabled = true
	b.mouse_entered.emit()
	b3.mouse_entered.emit()
	ok = check(sfx.play_count == before, "禁用 / 静音按钮悬停不响") and ok
	# 非按钮节点不接
	var l := Label.new()
	tree.root.add_child(l)
	ok = check(SoundFx.button_slot(b2) == &"back" and SoundFx.button_slot(b) == SoundFx.BUTTON_DEFAULT, "button_slot 读 meta") and ok
	for n in [b, b2, b3, l]:
		tree.root.remove_child(n)
		n.free()
	_drop(sfx)
	return ok


func test_static_hit_is_safe_without_autoload() -> bool:
	var n := Node.new()
	SoundFx.hit(n, &"click")   # 不在树里:静默
	SoundFx.hit(null, &"click")
	n.free()
	return check(true, "hit 不在树 / null 都不报错")
