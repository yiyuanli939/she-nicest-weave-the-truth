extends TestBase
## 合成音效(tools/sfx_synth.gd 配方 + tools/gen_sfx.gd 出文件 → assets/sfx/候选/D_合成):配方覆盖 CLIPS 全部槽位;每条渲染出来
## 都不刺耳且有界(峰值 ≤ -1 dBFS、RMS 归到 -18、峰值因子 < 22 dB、4 kHz 以上占比 < 0.2、无直流、首尾无爆音、时长上限);
## 同名配方逐样本可重现;磁盘文件 = 当前配方(改了配方没重出就红)。候选目录 .gdignore,这里用 FileAccess / load_from_file 直接读。

const DIR := "res://assets/sfx/候选/D_合成"


func _synth() -> RefCounted:
	return load("res://tools/sfx_synth.gd").new()


func test_recipes_cover_every_clip_slot() -> bool:
	var synth := _synth()
	var sfx := load("res://game/sfx.gd") as GDScript   # 动态取槽位表:不依赖 SoundFx 的全局类缓存
	if not check(sfx != null, "game/sfx.gd 读不到"):
		return false
	var clips: Dictionary = sfx.CLIPS
	var ok := check(synth.NAMES.size() + synth.ALIASES.size() == clips.size(),
			"配方 + 别名 = 槽位数(%d + %d vs %d)" % [synth.NAMES.size(), synth.ALIASES.size(), clips.size()])
	for slot in clips:
		var name := String(slot)
		ok = check(synth.NAMES.has(name) or synth.ALIASES.has(name), "槽位 %s 没有配方也不是别名" % name) and ok
	for a in synth.ALIASES:
		ok = check(synth.NAMES.has(synth.ALIASES[a]) and not synth.NAMES.has(a), "别名 %s 要指向已有配方且自己不是配方" % a) and ok
	return ok


func test_every_recipe_is_soft_and_bounded() -> bool:
	var synth := _synth()
	var ok := true
	for name in synth.NAMES:
		var buf: PackedFloat32Array = synth.render(name)
		var s: Dictionary = synth.stats(buf)
		var limit := 5.0 if name == "win" else 2.0
		ok = check(float(s.dur) >= 0.03 and float(s.dur) <= limit, "%s 时长 %.2f 应在 0.03..%.0f s" % [name, s.dur, limit]) and ok
		ok = check(float(s.peak_db) <= -0.9 and float(s.peak_db) >= -12.0, "%s 峰值 %.1f dBFS 应 ≤ -1 且不至于太轻" % [name, s.peak_db]) and ok
		ok = check(float(s.rms_db) <= -17.5 and float(s.rms_db) >= -28.0, "%s RMS %.1f 应归到 -18(峰值封顶时略低)" % [name, s.rms_db]) and ok
		ok = check(float(s.crest) < 22.0, "%s 峰值因子 %.1f dB 太尖" % [name, s.crest]) and ok
		ok = check(float(s.hi4k) < 0.2, "%s 4 kHz 以上占比 %.2f 太多" % [name, s.hi4k]) and ok
		ok = check(absf(float(s.dc)) < 0.005, "%s 有直流 %.4f" % [name, s.dc]) and ok
		ok = check(absf(buf[0]) < 0.02 and absf(buf[buf.size() - 1]) < 0.02, "%s 首尾要淡到零(%.3f / %.3f)" % [name, buf[0], buf[buf.size() - 1]]) and ok
	return ok


func test_render_is_deterministic_and_files_match_recipes() -> bool:
	var synth := _synth()
	var a: PackedFloat32Array = synth.render("page")   # 噪声最多的一条:种子固定才会逐样本一样
	var b: PackedFloat32Array = _synth().render("page")
	var ok := check(a.size() > 0 and a == b, "同名配方两次渲染逐样本相同")
	for name in synth.NAMES:
		var path := "%s/%s.wav" % [DIR, name]
		if not check(FileAccess.file_exists(path), "缺文件 %s(跑 tools/gen_sfx.gd)" % path):
			ok = false
			continue
		var disk := AudioStreamWAV.load_from_file(path)
		var fresh: AudioStreamWAV = synth.to_wav(synth.render(name))
		ok = check(disk != null and disk.format == fresh.format and disk.mix_rate == fresh.mix_rate and not disk.stereo
				and disk.data == fresh.data, "%s 磁盘文件与当前配方不同(改了配方要重出)" % name) and ok
	for alias in synth.ALIASES:
		var src := FileAccess.get_file_as_bytes("%s/%s.wav" % [DIR, synth.ALIASES[alias]])
		var dst := FileAccess.get_file_as_bytes("%s/%s.wav" % [DIR, alias])
		ok = check(not dst.is_empty() and dst == src, "别名 %s.wav 应与 %s.wav 相同" % [alias, synth.ALIASES[alias]]) and ok
	return ok
