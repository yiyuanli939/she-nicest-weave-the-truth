extends RefCounted
## 操作音效合成器(纯 GDScript,只用 AudioStreamWAV 拼 PCM,不下载素材):每个槽位一份配方 = 几层「材质」按时间叠加 ——
## 黄铜轻击 _brass(基频 + 2.4 / 4.1 倍非谐分音,各自快速衰减)/ 木质轻叩 _knock(低频正弦滑落 + 一撮低通噪声瞬态)/
## 木琴音 _wood(正弦 + 4 倍泛音)/ 小铃 _bell(1 / 2.0 / 2.98 / 4.2 倍非谐分音,高分音衰减更快)/ 织物·纸张摩擦 _noise(带通噪声扫频)。
## 「不刺耳」从源头保证:没有方波锯齿,任何分音 ≥ 3.8 kHz 就不加,噪声一律高通 150 Hz 以上 + 低通 ≤ 3.5 kHz,再整体 6 kHz 四阶低通;
## 起音 ≥ 1 ms、首尾淡入淡出,不会有爆音。响度统一:按峰值 -60 dB 去尾后 RMS 归到 -18 dBFS、峰值封顶 -1 dBFS
## (与 tools/sfx_audit.py 同一口径,所以 game/sfx.gd 的 GAIN_DB 对合成版只表达「意图」:悬停轻、警告轻……)。
## 噪声用槽位名做种,输出逐样本可重现(tests/test_sfx_synth.gd 盯着磁盘文件 = 当前配方)。
## 出文件走 tools/gen_sfx.gd → assets/sfx/候选/D_合成/(候选目录 .gdignore 不进引擎,试听定了由音效会话复制到 assets/sfx/);运行时不需要本脚本。

const RATE := 44100
const TARGET_RMS_DB := -18.0
const PEAK_CEIL_DB := -1.0
const LOWPASS_HZ := 6000.0
const PARTIAL_MAX_HZ := 3800.0
const TAIL_DB := -60.0
const FADE_IN_SEC := 0.001
const FADE_OUT_SEC := 0.005

## 全部配方名 = 文件名;CLIPS 里另有四个别名槽位(ALIASES)共用文件,出文件时复制一份
const NAMES: PackedStringArray = [
	"click", "hover", "back", "confirm", "open", "close", "toggle", "slider", "reset_progress",
	"place", "delete", "refuse", "pick", "drop", "plug", "unplug", "error", "warn", "snap", "move", "zoom",
	"redo", "reset_board",
	"brush", "paint", "clear",
	"drawer_open", "drawer_close", "page", "hint", "guide", "next", "portrait", "win",
]

const ALIASES: Dictionary = {"undo": "back", "unpin": "close", "pin_error": "error", "skip": "zoom"}

var _rng := RandomNumberGenerator.new()


## 双二阶滤波(RBJ cookbook)
class Biquad:
	var b0 := 1.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func _setup(kind: int, fc: float, q: float) -> void:
		var w0 := TAU * clampf(fc, 10.0, RATE * 0.45) / RATE
		var cw := cos(w0)
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		match kind:
			0:   # 低通
				b0 = (1.0 - cw) * 0.5 / a0
				b1 = (1.0 - cw) / a0
				b2 = b0
			1:   # 高通
				b0 = (1.0 + cw) * 0.5 / a0
				b1 = -(1.0 + cw) / a0
				b2 = b0
		a1 = -2.0 * cw / a0
		a2 = (1.0 - alpha) / a0

	func lowpass(fc: float, q: float = 0.7071) -> void:
		_setup(0, fc, q)

	func highpass(fc: float, q: float = 0.7071) -> void:
		_setup(1, fc, q)

	func run(x: float) -> float:
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y


# ---- 对外 ----

## 渲染一个配方:叠层 → 6 kHz 低通 → 去尾 → 淡入淡出 → 响度归一。返回 -1..1 的单声道浮点样本
func render(name: String) -> PackedFloat32Array:
	assert(NAMES.has(name), "没有这个配方:" + name)
	_rng.seed = hash(name)
	var buf: PackedFloat32Array = call("_r_" + name)
	buf = _lowpass4(buf, LOWPASS_HZ)
	buf = _trim_tail(buf)
	_fade_edges(buf)
	_normalize(buf)
	return buf


## 16 bit 单声道 44.1 kHz 的 AudioStreamWAV(save_to_wav 可直接落盘)
static func to_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var pcm := PackedByteArray()
	pcm.resize(buf.size() * 2)
	for i in buf.size():
		pcm.encode_s16(i * 2, int(round(clampf(buf[i], -1.0, 1.0) * 32767.0)))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = pcm
	return w


## 量测:时长 / 峰值与 RMS(dBFS)/ 峰值因子 / 直流 / 4 kHz 以上能量占比(四阶高通后的能量比,近似频谱占比)
static func stats(buf: PackedFloat32Array) -> Dictionary:
	var peak := 1e-9
	var sum := 0.0
	var dc := 0.0
	var hi := 0.0
	var h1 := Biquad.new()
	var h2 := Biquad.new()
	h1.highpass(4000.0, 0.5412)
	h2.highpass(4000.0, 1.3066)
	for v in buf:
		peak = maxf(peak, absf(v))
		sum += v * v
		dc += v
		var y := h2.run(h1.run(v))
		hi += y * y
	var n := maxi(buf.size(), 1)
	var rms := sqrt(sum / n) + 1e-9
	return {
		"dur": float(buf.size()) / RATE,
		"peak_db": linear_to_db(peak),
		"rms_db": linear_to_db(rms),
		"crest": linear_to_db(peak) - linear_to_db(rms),
		"dc": dc / n,
		"hi4k": hi / maxf(sum, 1e-12),
	}


# ---- 材质 ----

## 一个分音:频率在 glide 秒内从 f0 指数滑到 f1;幅度 = attack 秒线性起音 × 以 tau 为时间常数的指数衰减;tri = 三角波(只有奇次泛音,软)
func _partial(f0: float, f1: float, glide: float, amp: float, attack: float, tau: float, tri: bool = false) -> PackedFloat32Array:
	var out := _zeros(tau * 5.0 + glide)
	var phase := 0.0
	var ga := maxf(glide, 1.0 / RATE)
	var ratio := f1 / f0
	for i in out.size():
		var t := float(i) / RATE
		var f := f0 * pow(ratio, minf(t / ga, 1.0))
		phase += f / RATE
		var s: float
		if tri:
			var p := phase - floorf(phase)
			s = 4.0 * absf(p - 0.5) - 1.0
		else:
			s = sin(TAU * phase)
		out[i] = s * amp * minf(t / maxf(attack, 0.001), 1.0) * exp(-t / tau)
	return out


## 带通噪声:白噪 → 高通 hp_hz → 低通截止在 dur 内从 lp0 线性扫到 lp1 → 包络(attack 起音,hold 秒平台,之后按 tau 衰减)
func _noise(dur: float, amp: float, attack: float, hold: float, tau: float, hp_hz: float, lp0: float, lp1: float) -> PackedFloat32Array:
	var out := _zeros(dur)
	var hp := Biquad.new()
	var lp := Biquad.new()
	hp.highpass(hp_hz)
	var n := out.size()
	for i in n:
		if i % 32 == 0:
			lp.lowpass(lerpf(lp0, lp1, float(i) / n))
		var t := float(i) / RATE
		var env := minf(t / maxf(attack, 0.001), 1.0)
		if t > hold:
			env *= exp(-(t - hold) / tau)
		out[i] = lp.run(hp.run(_rng.randf_range(-1.0, 1.0))) * amp * env
	return out


## 黄铜轻击:基频 + 2.4 / 4.1 倍非谐分音,越高衰减越快
func _brass(f: float, amp: float, tau: float) -> PackedFloat32Array:
	var b := _partial(f, f, 0.0, amp, 0.002, tau)
	b = _add(b, _partial(f * 2.4, f * 2.4, 0.0, amp * 0.45, 0.002, tau * 0.6))
	if f * 4.1 < PARTIAL_MAX_HZ:
		b = _add(b, _partial(f * 4.1, f * 4.1, 0.0, amp * 0.2, 0.002, tau * 0.35))
	return b


## 木质轻叩:低频正弦 30 ms 内从 1.5f 滑落到 f + 一撮低通噪声当敲击瞬态
func _knock(f: float, amp: float, tau: float) -> PackedFloat32Array:
	var b := _partial(f * 1.5, f, 0.03, amp, 0.003, tau)
	return _add(b, _noise(0.03, amp * 0.5, 0.001, 0.0, 0.008, 200.0, 1800.0, 900.0))


## 木琴音:正弦 + 4 倍泛音(很快消失)+ 一点敲击噪声
func _wood(f: float, amp: float, tau: float) -> PackedFloat32Array:
	var b := _partial(f, f, 0.0, amp, 0.003, tau)
	if f * 4.0 < PARTIAL_MAX_HZ:
		b = _add(b, _partial(f * 4.0, f * 4.0, 0.0, amp * 0.25, 0.002, tau * 0.2))
	return _add(b, _noise(0.012, amp * 0.3, 0.001, 0.0, 0.004, 300.0, 2000.0, 1500.0))


## 小铃:非谐分音 1 / 2.0 / 2.98 / 4.2 倍,高分音更轻更短
func _bell(f: float, amp: float, tau: float) -> PackedFloat32Array:
	var ratios: Array[float] = [1.0, 2.0, 2.98, 4.2]
	var amps: Array[float] = [1.0, 0.5, 0.3, 0.15]
	var taus: Array[float] = [1.0, 0.7, 0.5, 0.35]
	var b := PackedFloat32Array()
	for i in ratios.size():
		var fi := f * ratios[i]
		if fi >= PARTIAL_MAX_HZ:
			continue
		b = _add(b, _partial(fi, fi, 0.0, amp * amps[i], 0.004, tau * taus[i]))
	return b


# ---- 配方(音高多取 C 大调五声音阶;时间都是秒)----

func _r_click() -> PackedFloat32Array:      # 黄铜轻击 + 木底
	return _add(_brass(880.0, 1.0, 0.03), _knock(240.0, 0.6, 0.03))


func _r_hover() -> PackedFloat32Array:      # 极轻的一触
	return _add(_partial(1320.0, 1320.0, 0.0, 0.5, 0.002, 0.012), _partial(330.0, 330.0, 0.0, 0.8, 0.003, 0.02))


func _r_back() -> PackedFloat32Array:       # 木琴两音下行 E5 → A4
	return _add(_wood(659.25, 1.0, 0.07), _wood(440.0, 1.0, 0.09), 0.09)


func _r_redo() -> PackedFloat32Array:       # back 的镜像:上行
	return _add(_wood(440.0, 1.0, 0.07), _wood(659.25, 1.0, 0.09), 0.09)


func _r_confirm() -> PackedFloat32Array:    # 小铃 C6 + 稍后 C5 托底
	return _add(_bell(1046.5, 1.0, 0.25), _bell(523.25, 0.8, 0.3), 0.07)


func _r_open() -> PackedFloat32Array:       # 织物上扫 + 末尾轻叩
	return _add(_noise(0.2, 1.0, 0.03, 0.08, 0.05, 300.0, 500.0, 2200.0), _knock(260.0, 0.8, 0.04), 0.16)


func _r_close() -> PackedFloat32Array:      # 织物下扫 + 稍重的叩
	return _add(_noise(0.2, 1.0, 0.02, 0.06, 0.05, 300.0, 2200.0, 500.0), _knock(200.0, 1.0, 0.045), 0.15)


func _r_toggle() -> PackedFloat32Array:     # 黄铜拨杆:高低两击
	return _add(_brass(1100.0, 0.8, 0.02), _brass(700.0, 1.0, 0.03), 0.045)


func _r_slider() -> PackedFloat32Array:     # 极短一格
	return _add(_partial(1500.0, 1500.0, 0.0, 0.6, 0.001, 0.008), _partial(400.0, 400.0, 0.0, 0.8, 0.002, 0.012))


func _r_reset_progress() -> PackedFloat32Array:   # 三音下行 D5 B4 G4 + 低叩
	var b := _add(_wood(587.33, 1.0, 0.09), _wood(493.88, 1.0, 0.09), 0.13)
	b = _add(b, _wood(392.0, 1.0, 0.14), 0.26)
	return _add(b, _knock(110.0, 0.7, 0.08), 0.26)


func _r_place() -> PackedFloat32Array:      # 仪器落板:木叩 + 一丝黄铜
	return _add(_knock(180.0, 1.0, 0.07), _brass(1200.0, 0.25, 0.02), 0.005)


func _r_delete() -> PackedFloat32Array:     # 拿走:短下扫 + 软叩
	return _add(_noise(0.14, 1.0, 0.01, 0.03, 0.04, 300.0, 1800.0, 400.0), _knock(150.0, 0.9, 0.05), 0.1)


func _r_refuse() -> PackedFloat32Array:     # 闷闷两下
	return _add(_knock(140.0, 1.0, 0.04), _knock(130.0, 1.0, 0.05), 0.1)


func _r_pick() -> PackedFloat32Array:       # 拿起插头:轻微上滑
	return _add(_partial(700.0, 950.0, 0.04, 1.0, 0.002, 0.035), _noise(0.02, 0.3, 0.001, 0.0, 0.006, 800.0, 2500.0, 2000.0))


func _r_drop() -> PackedFloat32Array:       # 空放:软叩 + 一点织物
	return _add(_knock(200.0, 1.0, 0.05), _noise(0.07, 0.5, 0.005, 0.02, 0.02, 400.0, 1500.0, 800.0))


func _r_plug() -> PackedFloat32Array:       # 接上:上滑到位 + 黄铜咬合
	return _add(_partial(500.0, 1000.0, 0.06, 0.8, 0.003, 0.05), _brass(1000.0, 1.0, 0.03), 0.06)


func _r_unplug() -> PackedFloat32Array:     # 拔线:先咬合再下滑
	return _add(_brass(900.0, 0.8, 0.02), _partial(900.0, 450.0, 0.08, 1.0, 0.003, 0.06), 0.02)


func _r_error() -> PackedFloat32Array:      # 两个相差半音的低三角波,拍频微微发浑
	return _add(_partial(220.0, 220.0, 0.0, 1.0, 0.01, 0.16, true), _partial(233.08, 233.08, 0.0, 1.0, 0.01, 0.16, true))


func _r_warn() -> PackedFloat32Array:       # 单个低音 E4
	return _add(_partial(329.63, 329.63, 0.0, 1.0, 0.01, 0.14), _partial(659.25, 659.25, 0.0, 0.3, 0.01, 0.08))


func _r_snap() -> PackedFloat32Array:       # 线绷断:音高急落的拨弦 + 一撮噪声
	return _add(_partial(800.0, 200.0, 0.04, 1.0, 0.001, 0.045), _noise(0.02, 0.6, 0.001, 0.0, 0.005, 1000.0, 3200.0, 1500.0))


func _r_move() -> PackedFloat32Array:       # 拖动松手:织物滑 + 轻叩
	return _add(_noise(0.15, 1.0, 0.04, 0.04, 0.04, 400.0, 1200.0, 2000.0), _knock(220.0, 0.6, 0.035), 0.12)


func _r_zoom() -> PackedFloat32Array:       # 极软一点
	return _partial(600.0, 600.0, 0.0, 1.0, 0.002, 0.015)


func _r_reset_board() -> PackedFloat32Array:      # 长下扫 + 两叩
	var b := _add(_noise(0.3, 1.0, 0.02, 0.1, 0.08, 300.0, 2200.0, 400.0), _knock(160.0, 0.8, 0.05), 0.22)
	return _add(b, _knock(120.0, 1.0, 0.07), 0.32)


func _r_brush() -> PackedFloat32Array:      # 选笔刷:短织物
	return _noise(0.12, 1.0, 0.02, 0.03, 0.03, 700.0, 1400.0, 2600.0)


func _r_paint() -> PackedFloat32Array:      # 落笔:软点
	return _add(_noise(0.04, 1.0, 0.002, 0.0, 0.012, 300.0, 1200.0, 900.0), _partial(300.0, 300.0, 0.0, 0.8, 0.002, 0.025))


func _r_clear() -> PackedFloat32Array:      # 抹布一擦
	return _noise(0.28, 1.0, 0.03, 0.12, 0.06, 300.0, 2000.0, 500.0)


func _r_drawer_open() -> PackedFloat32Array:      # 木抽屉拉出:低噪滑轨 + 到头一叩
	return _add(_noise(0.3, 1.0, 0.08, 0.12, 0.05, 150.0, 700.0, 1100.0), _knock(160.0, 0.9, 0.05), 0.27)


func _r_drawer_close() -> PackedFloat32Array:     # 推回:滑轨 + 合上 + 黄铜把手一颤
	var b := _add(_noise(0.22, 0.8, 0.03, 0.1, 0.04, 150.0, 1100.0, 600.0), _knock(140.0, 1.0, 0.06), 0.2)
	return _add(b, _brass(1300.0, 0.15, 0.03), 0.2)


func _r_page() -> PackedFloat32Array:       # 翻页:纸张两瓣
	return _add(_noise(0.08, 0.8, 0.01, 0.02, 0.025, 900.0, 3000.0, 2000.0), _noise(0.14, 1.0, 0.03, 0.03, 0.04, 700.0, 1800.0, 3200.0), 0.06)


func _r_hint() -> PackedFloat32Array:       # 两声小铃上行 G5 → B5
	return _add(_bell(783.99, 1.0, 0.15), _bell(987.77, 1.0, 0.18), 0.1)


func _r_guide() -> PackedFloat32Array:      # 木琴三音上行 C5 E5 G5
	var b := _add(_wood(523.25, 1.0, 0.18), _wood(659.25, 1.0, 0.18), 0.14)
	return _add(b, _wood(783.99, 1.0, 0.24), 0.28)


func _r_next() -> PackedFloat32Array:       # 对话推进:纸的一触
	return _add(_noise(0.03, 0.8, 0.001, 0.0, 0.01, 400.0, 2000.0, 1200.0), _partial(500.0, 500.0, 0.0, 1.0, 0.002, 0.015))


func _r_portrait() -> PackedFloat32Array:   # 换人:短织物
	return _noise(0.13, 1.0, 0.03, 0.03, 0.035, 500.0, 1000.0, 2000.0)


func _r_win() -> PackedFloat32Array:        # 织成:C4 低音垫 + 小铃琶音 C5 E5 G5 C6 + 收尾 E6
	var b := _partial(261.63, 261.63, 0.0, 0.5, 0.02, 0.3)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.5]
	for i in notes.size():
		b = _add(b, _bell(notes[i], 0.9, 0.35), 0.14 * i)
	return _add(b, _bell(1318.5, 0.6, 0.45), 0.62)


# ---- 缓冲工具 ----

func _zeros(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(int(ceil(sec * RATE)), 1))
	b.fill(0.0)
	return b


## 把 src 从 at 秒起叠进 dst(不够长就补零延长),返回 dst
func _add(dst: PackedFloat32Array, src: PackedFloat32Array, at: float = 0.0) -> PackedFloat32Array:
	var off := int(round(at * RATE))
	var need := off + src.size()
	if dst.size() < need:
		var old := dst.size()
		dst.resize(need)
		for i in range(old, need):
			dst[i] = 0.0
	for i in src.size():
		dst[off + i] += src[i]
	return dst


## 四阶巴特沃斯低通(两级双二阶)
func _lowpass4(buf: PackedFloat32Array, fc: float) -> PackedFloat32Array:
	var l1 := Biquad.new()
	var l2 := Biquad.new()
	l1.lowpass(fc, 0.5412)
	l2.lowpass(fc, 1.3066)
	for i in buf.size():
		buf[i] = l2.run(l1.run(buf[i]))
	return buf


## 去掉相对峰值 -60 dB 以下的尾巴(留 5 ms)
func _trim_tail(buf: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	var floor_v := peak * db_to_linear(TAIL_DB)
	var last := buf.size() - 1
	while last > 0 and absf(buf[last]) < floor_v:
		last -= 1
	buf.resize(mini(buf.size(), last + 1 + int(FADE_OUT_SEC * RATE)))
	return buf


func _fade_edges(buf: PackedFloat32Array) -> void:
	var fi := mini(int(FADE_IN_SEC * RATE), buf.size())
	for i in fi:
		buf[i] *= float(i) / fi
	var fo := mini(int(FADE_OUT_SEC * RATE), buf.size())
	for i in fo:
		buf[buf.size() - 1 - i] *= float(i) / fo


## RMS 归到 TARGET_RMS_DB,峰值不许超过 PEAK_CEIL_DB
func _normalize(buf: PackedFloat32Array) -> void:
	var s := stats(buf)
	var g := db_to_linear(TARGET_RMS_DB - float(s.rms_db))
	g = minf(g, db_to_linear(PEAK_CEIL_DB - float(s.peak_db)))
	for i in buf.size():
		buf[i] *= g
