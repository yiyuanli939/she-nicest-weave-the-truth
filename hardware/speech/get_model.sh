#!/bin/zsh
# 下载 Vosk 离线中文小模型(42 MB;只有小模型支持动态语法约束)到 hardware/speech/model/。
# 用法: bash hardware/speech/get_model.sh   (已存在则跳过)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL="vosk-model-small-cn-0.22"
if [ -f "$DIR/model/graph/HCLr.fst" ]; then
	echo "模型已在 $DIR/model"; exit 0
fi
cd "$DIR"
curl -L -o "$MODEL.zip" "https://alphacephei.com/vosk/models/$MODEL.zip"
rm -rf "$MODEL" model
unzip -q "$MODEL.zip"
mv "$MODEL" model
rm -f "$MODEL.zip"
[ -f model/graph/HCLr.fst ] || { echo "FAIL: 模型没有动态语法图(graph/HCLr.fst)"; exit 1; }
echo "模型就绪: $DIR/model"
