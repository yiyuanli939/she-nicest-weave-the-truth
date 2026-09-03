#!/bin/zsh
# 按 hardware/firmware/sounds/lines.json(中文音色 voice + 五句 lines → <名>.wav;英文音色 voice_en + lines_en → <名>_en.wav)整表重做小机语音。
# 用法: bash hardware/make_voices.sh [日志文件]          (游戏「小机维护」面板的「保存并生成语音」跑这个;需联网)
#       bash hardware/make_voices.sh --check-only         (只解析表、列出要生成的句子并检查 edge-tts 在不在,不联网)
# 日志逐行 [i/n] …,末行 DONE 或 FAIL: …。生成后记得「刷入固件与语音」(flash_robot.sh 整目录拷,<名>_en.wav 自动上板;
# 英文模式下游戏发 say <名>_en,固件只按文件名找声音,不用改固件)。
HW="$(cd "$(dirname "$0")" && pwd)"
CHECK=0
[ "$1" = "--check-only" ] && { CHECK=1; shift; }
LOG="${1:-$HW/.run/voices.log}"
mkdir -p "$(dirname "$LOG")"
: > "$LOG"
say() { echo "$1" | tee -a "$LOG"; }
CFG="$HW/firmware/sounds/lines.json"
[ -f "$CFG" ] || { say "FAIL: 缺 $CFG"; exit 1; }
"$HW/.venv/bin/python" - "$CFG" <<'PY' > "$HW/.run/voices.list" || { say "FAIL: lines.json 解析失败"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(d.get("gain", 0.9))
zh = d.get("voice", "zh-CN-XiaoyiNeural"); en = d.get("voice_en", "en-GB-SoniaNeural")
for k, v in d["lines"].items():
    print(f"{k}\t{zh}\t{v}")
for k, v in d.get("lines_en", {}).items():
    print(f"{k}_en\t{en}\t{v}")
PY
GAIN="$(sed -n 1p "$HW/.run/voices.list")"
N=$(($(wc -l < "$HW/.run/voices.list") - 1))
if [ "$CHECK" = 1 ]; then
	tail -n +2 "$HW/.run/voices.list" | while IFS=$'\t' read -r name voice text; do say "  $name  $voice  $text"; done
	[ -x "$HW/.venv/bin/edge-tts" ] || { say "FAIL: 缺 hardware/.venv/bin/edge-tts"; exit 1; }
	say "DONE ($N 句,音量 $GAIN;--check-only 未生成)"; exit 0
fi
i=0
tail -n +2 "$HW/.run/voices.list" | while IFS=$'\t' read -r name voice text; do
	i=$((i + 1))
	say "[$i/$N] $name($voice):$text"
	bash "$HW/make_voice.sh" "$name" "$text" "$voice" "$GAIN" >> "$LOG" 2>&1 || { say "FAIL: $name 生成失败(需联网;看日志)"; exit 1; }
done || exit 1
say "DONE"
