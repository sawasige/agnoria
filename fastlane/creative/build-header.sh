#!/bin/bash
# 製品ページのヘッダー用アセット（21:9 3840x1646、文字なし）を、中央に女神を置いた元絵から作る。
# 16:9 の共通アセット（5244x2950）は iPhone で中央だけを拡大して表示され構図が崩れるので使わない。
# 21:9 は RunRun と同じで、iPhone では左右が約 8% ずつ切れて左上・右上にボタンが重なるだけ（SPEC-REVIEW M7）。
# 使い方: fastlane/creative/build-header.sh [出力.png]
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$DIR/header-21x9-3840x1646.png}
SRC=$DIR/header-source-1536x1024.png
# 元絵（1536x1024、顔の中心 x≈800）から幅いっぱい・高さ 658 を y=330 から切り出す（月桂冠の上に余白、肩まで入る）
magick "$SRC" -crop 1536x658+0+330 +repage -filter Lanczos -resize 3840x1646! -strip PNG24:"$OUT"
echo "wrote $OUT"
