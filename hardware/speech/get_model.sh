#!/bin/zsh
# 下载 Vosk 离线小模型(只有小模型支持动态语法约束)到 hardware/speech/:
#   中文 vosk-model-small-cn-0.22(42 MB)→ model/;英文 vosk-model-small-en-us-0.15(40 MB)→ model_en/
# 用法: bash hardware/speech/get_model.sh [zh|en|all]   (默认 all;已存在的跳过)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
WHICH="${1:-all}"
fetch() {   # fetch <模型名> <目录名>
	local MODEL="$1" DEST="$2"
	if [ -f "$DIR/$DEST/graph/HCLr.fst" ]; then
		echo "模型已在 $DIR/$DEST"; return 0
	fi
	cd "$DIR"
	curl -L -o "$MODEL.zip" "https://alphacephei.com/vosk/models/$MODEL.zip"
	rm -rf "$MODEL" "$DEST"
	unzip -q "$MODEL.zip"
	mv "$MODEL" "$DEST"
	rm -f "$MODEL.zip"
	[ -f "$DEST/graph/HCLr.fst" ] || { echo "FAIL: $DEST 没有动态语法图(graph/HCLr.fst)"; return 1; }
	echo "模型就绪: $DIR/$DEST"
}
case "$WHICH" in
	zh) fetch vosk-model-small-cn-0.22 model ;;
	en) fetch vosk-model-small-en-us-0.15 model_en ;;
	all) fetch vosk-model-small-cn-0.22 model; fetch vosk-model-small-en-us-0.15 model_en ;;
	*) echo "用法: get_model.sh [zh|en|all]"; exit 1 ;;
esac
