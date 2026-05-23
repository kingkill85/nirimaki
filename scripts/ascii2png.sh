#!/bin/bash
# Render a block-character ASCII art file (one full block per cell) to a
# transparent PNG. Each input character becomes a rectangle, avoiding all
# font/kerning artifacts of rendering ▀ ▄ █ via text.
#
# Usage: ascii2png.sh INPUT.txt OUTPUT.png [CELL_W] [CELL_H] [FILL]
#   CELL_W defaults to 16, CELL_H defaults to 2*CELL_W (matches a terminal
#     monospace cell — block characters then read with the same width-to-
#     height proportions you see from `cat logo.txt`).
#   FILL is any ImageMagick color spec (e.g. white, #7aa2f7). Default white.
#
# Supported source chars: █ ▀ ▄ ▌ ▐ (anything else is treated as blank).
set -euo pipefail
IN="$1"; OUT="$2"; CW="${3:-16}"; CH="${4:-$((CW * 2))}"; FILL="${5:-white}"

mapfile -t LINES < "$IN"
ROWS=${#LINES[@]}
COLS=0
for l in "${LINES[@]}"; do
  len=$(echo -n "$l" | wc -m)
  (( len > COLS )) && COLS=$len
done
W=$((COLS * CW))
H=$((ROWS * CH))

DRAW=""
for ((y=0; y<ROWS; y++)); do
  line="${LINES[y]}"
  for ((x=0; x<${#line}; x++)); do
    ch="${line:x:1}"
    x0=$((x * CW)); y0=$((y * CH))
    x1=$((x0 + CW - 1)); y1=$((y0 + CH - 1))
    yh=$((y0 + CH/2 - 1)); yl=$((y0 + CH/2))
    xh=$((x0 + CW/2 - 1)); xl=$((x0 + CW/2))
    case "$ch" in
      "█") DRAW+=" rectangle $x0,$y0 $x1,$y1" ;;
      "▀") DRAW+=" rectangle $x0,$y0 $x1,$yh" ;;
      "▄") DRAW+=" rectangle $x0,$yl $x1,$y1" ;;
      "▌") DRAW+=" rectangle $x0,$y0 $xh,$y1" ;;
      "▐") DRAW+=" rectangle $xl,$y0 $x1,$y1" ;;
    esac
  done
done

magick -size "${W}x${H}" xc:none -fill "$FILL" -draw "$DRAW" "$OUT"
echo "Wrote $OUT (${W}x${H})"
