extends SceneTree
## 操作音效自合成出文件(配方在 tools/sfx_synth.gd,这里只渲染落盘并打印量测):
##   "$GODOT" --headless --path . --script res://tools/gen_sfx.gd            # 全部 34 个
##   "$GODOT" --headless --path . --script res://tools/gen_sfx.gd -- click win   # 只重出这几个
## 出 assets/sfx/候选/D_合成/<槽位>.wav(16 bit 单声道 44.1 kHz;别名槽位 undo/unpin/pin_error/skip 复制一份),候选目录有 .gdignore
## 不进引擎、不用 --import;tests/test_sfx_synth.gd 盯着磁盘文件 = 当前配方逐样本相同,改了配方必须重出。
## 试听定了用这套 → 音效会话复制到 assets/sfx/ 并重生成 GAIN_DB(合成版已归到 RMS -18 dBFS,建议值都在 0 附近)。
## 表头:时长 / 峰值 / RMS(dBFS)/ 峰值因子 / >4k 能量占比;「刺耳」口径同 tools/sfx_audit.py(那边多量频谱质心,
## 想看就 hardware/.venv/bin/python tools/sfx_audit.py assets/sfx/synth)。退出码 = 越界条数。

const OUT_DIR := "res://assets/sfx/候选/D_合成"
const CREST_MAX := 22.0
const HI4K_MAX := 0.30


func _initialize() -> void:
	var scr := load("res://tools/sfx_synth.gd") as GDScript
	if scr == null or not scr.can_instantiate():
		print("tools/sfx_synth.gd 加载失败(语法错误?)")
		quit(1)
		return
	var synth: RefCounted = scr.new()
	var names: PackedStringArray = synth.NAMES
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		names = PackedStringArray(args)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var bad := 0
	print("%-16s %5s %6s %6s %5s %5s  判定" % ["名字", "时长", "峰值", "RMS", "峰因", ">4k"])
	var t0 := Time.get_ticks_msec()
	for name in names:
		if not synth.NAMES.has(name):
			print("%-16s 没有这个配方" % name)
			bad += 1
			continue
		var buf: PackedFloat32Array = synth.render(name)
		var wav: AudioStreamWAV = synth.to_wav(buf)
		var path := "%s/%s.wav" % [OUT_DIR, name]
		var err := wav.save_to_wav(path)
		var s: Dictionary = synth.stats(buf)
		var why: PackedStringArray = []
		if err != OK:
			why.append("写失败 %d" % err)
		if float(s.crest) > CREST_MAX:
			why.append("尖峰")
		if float(s.hi4k) > HI4K_MAX:
			why.append("高频多")
		if not why.is_empty():
			bad += 1
		print("%-16s %5.2f %6.1f %6.1f %5.1f %5.2f  %s" % [name, s.dur, s.peak_db, s.rms_db, s.crest, s.hi4k,
				"柔和" if why.is_empty() else "越界:" + "/".join(why)])
		for alias in synth.ALIASES:
			if synth.ALIASES[alias] == name:
				wav.save_to_wav("%s/%s.wav" % [OUT_DIR, alias])
	print("出了 %d 个到 %s,用时 %.1f s,越界 %d" % [names.size(), OUT_DIR, (Time.get_ticks_msec() - t0) / 1000.0, bad])
	quit(bad)
