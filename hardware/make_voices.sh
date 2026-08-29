#!/bin/zsh
# 按 hardware/firmware/sounds/lines.json(音色 / 音量 / 六句台词)整表重做小机语音。
# 用法: bash hardware/make_voices.sh [日志文件]   (游戏「小机维护」面板的「保存并生成语音」跑这个;需联网)
# 日志逐行 [i/n] …,末行 DONE 或 FAIL: …。生成后记得「刷入固件与语音」。
HW="$(cd "$(dirname "$0")" && pwd)"
LOG="${1:-$HW/.run/voices.log}"
mkdir -p "$(dirname "$LOG")"
: > "$LOG"
say() { echo "$1" | tee -a "$LOG"; }
CFG="$HW/firmware/sounds/lines.json"
[ -f "$CFG" ] || { say "FAIL: 缺 $CFG"; exit 1; }
"$HW/.venv/bin/python" - "$CFG" <<'PY' > "$HW/.run/voices.list" || { say "FAIL: lines.json 解析失败"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(d.get("voice", "zh-CN-XiaoyiNeural")); print(d.get("gain", 0.9))
for k, v in d["lines"].items():
    print(f"{k}\t{v}")
PY
VOICE="$(sed -n 1p "$HW/.run/voices.list")"
GAIN="$(sed -n 2p "$HW/.run/voices.list")"
N=$(($(wc -l < "$HW/.run/voices.list") - 2))
i=0
tail -n +3 "$HW/.run/voices.list" | while IFS=$'\t' read -r name text; do
	i=$((i + 1))
	say "[$i/$N] $name:$text"
	bash "$HW/make_voice.sh" "$name" "$text" "$VOICE" "$GAIN" >> "$LOG" 2>&1 || { say "FAIL: $name 生成失败(需联网;看日志)"; exit 1; }
done || exit 1
say "DONE"
