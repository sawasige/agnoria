#!/bin/bash
# 製品ページのヘッダー用の共通アセット（16:9 5244x2950、文字なし）を、中央に女神を置いた元絵から作る。
# 顔（目〜あご）を Apple のテンプレートの安全領域（中央の帯 x 1498〜3746・y 1024〜1927）に入れる。SPEC-REVIEW M7
# 使い方: fastlane/creative/build-header.sh [出力.png]
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$DIR/universal-16x9-5244x2950.png}
SRC=$DIR/header-source-1536x1024.png
# 元絵の顔の中心 (800, 600) がキャンバスの中心に来るよう 1472x828 を (64,186) から切り出して 5244x2950 に拡大
magick "$SRC" -crop 1472x828+64+186 +repage -filter Lanczos -resize 5244x2950! -strip PNG24:"$OUT"
echo "wrote $OUT"
