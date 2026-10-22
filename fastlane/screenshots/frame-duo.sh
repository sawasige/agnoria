#!/bin/bash
# iPhone Duo 用スクリーンショットの枠付け（frameit に Duo の端末フレームがないので、同じ背景・フォント・色で ImageMagick で作る）。
# 出力は入力と同じサイズ（外側 1398x2034 / 内側 2007x2853）。上にキーワード（太字・藍）とタイトル（丸ゴ・濃灰）、下に角丸 + 黒いベゼルの画面。
# 使い方: fastlane/screenshots/frame-duo.sh 入力.png "キーワード" "タイトル" 出力.png
set -euo pipefail
IN=$1; KEYWORD=$2; TITLE=$3; OUT=$4
DIR=$(cd "$(dirname "$0")" && pwd)
read W H < <(magick identify -format "%w %h\n" "$IN")
WORK=$(mktemp -d)
# 背景: frameit と同じ background.png を出力サイズに
magick "$DIR/background.png" -resize "${W}x${H}!" "$WORK/bg.png"
# 文字の大きさは幅 1320（iPhone 縦）での 96 / 64 を短辺に比例させる（横向きでも文字が大きくなりすぎない）
B=$(( W < H ? W : H ))
KS=$(( 96 * B / 1320 )); TS=$(( 64 * B / 1320 )); PAD=$(( 50 * B / 1320 ))
TOP=$(( PAD + KS + TS + PAD * 2 ))
# 画面: 残りの高さに収まるように縮小し、角丸 + ベゼル（iPhone の frameit 出力と同じく下は切れてよい）
BEZ=$(( 28 * B / 1320 )); R=$(( 110 * B / 1320 ))
SW=$(( W - PAD * 4 )); SH=$(( SW * H / W ))
magick "$IN" -resize "${SW}x${SH}!" \( +clone -alpha extract -draw "fill black polygon 0,0 0,$R $R,0 fill white circle $R,$R $R,0" \( +clone -flip \) -compose Multiply -composite \( +clone -flop \) -compose Multiply -composite \) -alpha off -compose CopyOpacity -composite "$WORK/screen.png"
magick -size "$(( SW + BEZ * 2 ))x$(( SH + BEZ * 2 ))" xc:none -fill "#1c1c1e" -draw "roundrectangle 0,0,$(( SW + BEZ * 2 - 1 )),$(( SH + BEZ * 2 - 1 )),$(( R + BEZ )),$(( R + BEZ ))" "$WORK/screen.png" -geometry "+${BEZ}+${BEZ}" -compose Over -composite "$WORK/device.png"
magick "$WORK/bg.png" \
  -gravity North -font "$DIR/fonts/HiraginoKakuGoBold.ttc" -pointsize $KS -fill "#3F51B5" -annotate +0+$PAD "$KEYWORD" \
  -font "$DIR/fonts/HiraginoMaruGo.ttc" -pointsize $TS -fill "#3A3A4A" -annotate +0+$(( PAD + KS + PAD / 2 )) "$TITLE" \
  "$WORK/device.png" -geometry "+0+$TOP" -compose Over -composite \
  -strip PNG24:"$OUT"
echo "wrote $OUT"
