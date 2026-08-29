#!/bin/zsh
# 生成/更新一句小机语音:bash hardware/make_voice.sh <名字> "<台词>" [音色] [音量0-1]
#   → hardware/firmware/sounds/<名字>.wav(微软神经语音,需联网 → 16 kHz/16 bit 单声道 → 峰值归一化到「音量」)
# 整表重做用 make_voices.sh(读 firmware/sounds/lines.json)。改完用「小机维护」面板刷入。
set -e
HW="$(cd "$(dirname "$0")" && pwd)"
NAME="$1"; TEXT="$2"; VOICE="${3:-zh-CN-XiaoyiNeural}"; GAIN="${4:-0.9}"
[ -n "$NAME" ] && [ -n "$TEXT" ] || { echo "用法: make_voice.sh <名字> \"<台词>\" [音色] [音量]"; exit 1; }
TMP="$(mktemp -d)"
"$HW/.venv/bin/edge-tts" --voice "$VOICE" --text "$TEXT" --write-media "$TMP/t.mp3"
afconvert -f WAVE -d LEI16@16000 -c 1 "$TMP/t.mp3" "$TMP/t.wav"
"$HW/.venv/bin/python" - "$TMP/t.wav" "$HW/firmware/sounds/$NAME.wav" "$GAIN" <<'PY'
import sys, wave, numpy as np
src, dst, gain = sys.argv[1], sys.argv[2], max(0.05, min(1.0, float(sys.argv[3])))
with wave.open(src, "rb") as w:
    params = w.getparams(); data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32)
peak = float(np.max(np.abs(data))) or 1.0
data = (data / peak * gain * 32767).astype(np.int16)
with wave.open(dst, "wb") as w:
    w.setparams(params); w.writeframes(data.tobytes())
print("写出", dst, f"{len(data)/16000:.2f}s 音量 {gain:.2f}")
PY
rm -rf "$TMP"
