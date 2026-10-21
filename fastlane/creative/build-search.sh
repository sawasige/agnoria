#!/bin/bash
# 検索結果用 3:2 (3840x2560): ヒーロー画像 + キャッチコピー（+ 任意でホーム画面のモック）
# 使い方: fastlane/creative/build-search.sh [出力.png] [mock]（ヘッダーは universal-16x9 を使い、検索結果だけこの 3:2 を使う。SPEC-REVIEW M7）
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${1:-$(dirname "$0")/search-3x2-3840x2560.png}; MOCK=${2:-}
WORK=$(mktemp -d)
FONT_JA=$REPO/fastlane/screenshots/fonts/HiraginoKakuGoBold.ttc
SRC=$REPO/docs/assets/hero.jpg
mock() {  # $1 src $2 dst $3 width（角丸スクショ + 黒ベゼル + 影）
  local src=$1 dst=$2 w=$3
  local h=$(( w * 2868 / 1320 )); local r=$(( w * 165 / 1320 )); local b=$(( w * 34 / 1320 )); local R=$(( r + b ))
  local Wd=$(( w + 2*b )) Hd=$(( h + 2*b ))
  magick "$src" -resize "${w}x${h}!" \( +clone -alpha extract -fill black -colorize 100 -fill white -draw "roundrectangle 0,0,$((w-1)),$((h-1)),$r,$r" \) -alpha off -compose CopyOpacity -composite "$WORK/screen.png"
  magick -size "${Wd}x${Hd}" xc:none -fill '#1c1c1e' -draw "roundrectangle 0,0,$((Wd-1)),$((Hd-1)),$R,$R" "$WORK/screen.png" -geometry "+${b}+${b}" -compose Over -composite \( +clone -background black -shadow 55x40+0+30 \) +swap -background none -layers merge +repage "$dst"
}
# 背景: ヒーローを 3:2 に（女神は左、x≈1800 より右は空）
magick "$SRC" -filter Lanczos -resize x2560 -gravity NorthWest -crop 3840x2560+0+0 +repage "$WORK/bg.png"
# 文字: 女神の右端（最大 x≈1920）から余白を取って x=2020 から。白い縁取りで雲の上でも読める
TXT=( -gravity NorthWest -font "$FONT_JA"
      -stroke white -strokewidth 22 -fill white -pointsize 270 -annotate +2020+400 "1日10問、" -annotate +2020+710 "3分で終わる"
      -pointsize 100 -annotate +2026+1060 "英単語・文法・応答問題 450〜600点" -annotate +2026+1215 "今の実力に合わせて出題します"
      -stroke none -fill '#1d2a6b' -pointsize 270 -annotate +2020+400 "1日10問、" -annotate +2020+710 "3分で終わる"
      -fill '#2b3a7a' -pointsize 100 -annotate +2026+1060 "英単語・文法・応答問題 450〜600点" -annotate +2026+1215 "今の実力に合わせて出題します" )
if [ "$MOCK" = mock ]; then
  mock "$REPO/fastlane/screenshots/ja/iPhone 17 Pro Max-01-home.png" "$WORK/p1.png" 1000
  magick "$WORK/bg.png" "$WORK/p1.png" -geometry +2720+1480 -composite "${TXT[@]}" -alpha off PNG24:"$OUT"
else
  magick "$WORK/bg.png" "${TXT[@]}" -alpha off PNG24:"$OUT"
fi
echo "wrote $OUT"
