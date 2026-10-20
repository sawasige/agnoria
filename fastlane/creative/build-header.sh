#!/bin/bash
# 製品ページのヘッダー用アセット（21:9 3840x1646）: ランディングページのヒーロー画像（女神は左）+ 右にキャッチコピー。
# 16:9 の共通アセット（5244x2950）は iPhone で中央だけを拡大して表示され構図が崩れるので使わない。
# 21:9 は RunRun と同じで、iPhone では左右が約 8%（307px）ずつ切れ、上の約 2 割に戻る/共有ボタンが重なるだけ（SPEC-REVIEW M7）。
# 使い方: fastlane/creative/build-header.sh [出力.png]
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$DIR/../.." && pwd)
OUT=${1:-$DIR/header-21x9-3840x1646.png}
SRC=$REPO/docs/assets/hero.jpg
FONT_JA=$REPO/fastlane/screenshots/fonts/HiraginoKakuGoBold.ttc
WORK=$(mktemp -d)
# 背景: ヒーロー（1671x941）の y=110〜826 を 21:9 で切り出して拡大（月桂冠の上に余白、胸まで）。女神の右端は x≈1800
magick "$SRC" -crop 1671x716+0+110 +repage -filter Lanczos -resize 3840x1646! "$WORK/bg.png"
# 文字: x=1950 から（iPhone で切れる右端 3533 の手前に収める）。上の 330px はボタンの下なので y=480 から。白い縁取り
TXT=( -gravity NorthWest -font "$FONT_JA"
      -stroke white -strokewidth 16 -fill white -pointsize 200 -annotate +1950+480 "1日10問、" -annotate +1950+710 "3分で終わる"
      -pointsize 86 -annotate +1954+980 "英単語と文法 450〜600点" -annotate +1954+1095 "今の実力に合わせて出題します"
      -stroke none -fill '#1d2a6b' -pointsize 200 -annotate +1950+480 "1日10問、" -annotate +1950+710 "3分で終わる"
      -fill '#2b3a7a' -pointsize 86 -annotate +1954+980 "英単語と文法 450〜600点" -annotate +1954+1095 "今の実力に合わせて出題します" )
magick "$WORK/bg.png" "${TXT[@]}" -alpha off -strip PNG24:"$OUT"
echo "wrote $OUT"
