#!/bin/bash
# 製品ページのヘッダー用の共通アセット（16:9 5244x2950、文字なし）を、中央に女神を置いた元絵から作る。
# 顔は横の中央・目を高さの 39% に（iPhone の表示範囲は上寄り。下の計算を参照）。SPEC-REVIEW M7
# 使い方: fastlane/creative/build-header.sh [出力.png]
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$DIR/universal-16x9-5244x2950.png}
SRC=$DIR/header-source-1536x1024.png
# iPhone の製品ページは、この 16:9 の「上から約 70%・中央の約 55%」（x 1050〜3960, y 0〜2050）を表示し、
# 上の 2 割は Dynamic Island と戻る/共有ボタンに隠れる（1.2 のプレビューを 2 回測って逆算。SPEC-REVIEW M7）。
# なので顔は横の中央、目を y≈1150（高さの 39%）に置く: 元絵の 1324x744 を (138,280) から切り出して 5244x2950 に拡大
magick "$SRC" -crop 1324x744+138+280 +repage -filter Lanczos -resize 5244x2950! -strip PNG24:"$OUT"
echo "wrote $OUT"
