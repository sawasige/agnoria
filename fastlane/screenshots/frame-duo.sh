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
# 画面: 幅（左右 PAD×2）と残りの高さ（下にも PAD）の両方に収まるように縮小し、角丸 + ベゼル。画面全体を見せる
BEZ=$(( 28 * B / 1320 )); R=$(( 150 * B / 1320 ))
SW=$(( W - PAD * 4 - BEZ * 2 )); SH=$(( SW * H / W ))
MAXH=$(( H - TOP - PAD - BEZ * 2 ))
if [ $SH -gt $MAXH ]; then SH=$MAXH; SW=$(( SH * W / H )); fi
if [ $W -lt $H ]; then
  # 閉じた状態: ヒンジ側（左）の角は小さく、右の角は大きい。左半分を小さい角丸、全体を大きい角丸で描いて合成する
  RL=$(( R * 3 / 10 ))
  magick -size "${SW}x${SH}" xc:black -fill white -draw "roundrectangle 0,0,$(( SW - 1 )),$(( SH - 1 )),$R,$R" -draw "roundrectangle 0,0,$(( SW / 2 )),$(( SH - 1 )),$RL,$RL" "$WORK/mask.png"
else
  magick -size "${SW}x${SH}" xc:black -fill white -draw "roundrectangle 0,0,$(( SW - 1 )),$(( SH - 1 )),$R,$R" "$WORK/mask.png"
fi
magick "$IN" -resize "${SW}x${SH}!" "$WORK/mask.png" -alpha off -compose CopyOpacity -composite "$WORK/screen.png"
DW=$(( SW + BEZ * 2 )); DH=$(( SH + BEZ * 2 ))
if [ $W -lt $H ]; then
  # 閉じた状態（外側）: 左に折りたたんだ裏側の半分が少しのぞく。右上にカメラの穴（シミュレータの見た目に合わせる。位置は画面幅の 0.90、高さの 0.073、半径は幅の 0.0435）
  OFF=$(( 10 * B / 1320 ))
  CX=$(( BEZ + SW * 902 / 1000 )); CY=$(( BEZ + SH * 73 / 1000 )); CR=$(( SW * 435 / 10000 ))
  RB=$(( R + BEZ )); RLB=$(( RL + BEZ ))
  magick -size "$(( DW + OFF ))x$(( DH + OFF ))" xc:none \
    -fill "#3a3a3c" -draw "roundrectangle 0,$OFF,$(( DW - 1 )),$(( DH + OFF - 1 )),$RB,$RB" -draw "roundrectangle 0,$OFF,$(( DW / 2 )),$(( DH + OFF - 1 )),$RLB,$RLB" \
    -fill "#1c1c1e" -draw "roundrectangle $OFF,0,$(( DW + OFF - 1 )),$(( DH - 1 )),$RB,$RB" -draw "roundrectangle $OFF,0,$(( DW / 2 + OFF )),$(( DH - 1 )),$RLB,$RLB" \
    "$WORK/screen.png" -geometry "+$(( BEZ + OFF ))+${BEZ}" -compose Over -composite \
    -fill "#000000" -draw "circle $(( CX + OFF )),$CY $(( CX + OFF + CR )),$CY" "$WORK/device.png"
else
  magick -size "${DW}x${DH}" xc:none -fill "#1c1c1e" -draw "roundrectangle 0,0,$(( DW - 1 )),$(( DH - 1 )),$(( R + BEZ )),$(( R + BEZ ))" "$WORK/screen.png" -geometry "+${BEZ}+${BEZ}" -compose Over -composite "$WORK/device.png"
fi
magick "$WORK/bg.png" \
  -gravity North -font "$DIR/fonts/HiraginoKakuGoBold.ttc" -pointsize $KS -fill "#3F51B5" -annotate +0+$PAD "$KEYWORD" \
  -font "$DIR/fonts/HiraginoMaruGo.ttc" -pointsize $TS -fill "#3A3A4A" -annotate +0+$(( PAD + KS + PAD / 2 )) "$TITLE" \
  "$WORK/device.png" -geometry "+0+$TOP" -compose Over -composite \
  -strip PNG24:"$OUT"
echo "wrote $OUT"
