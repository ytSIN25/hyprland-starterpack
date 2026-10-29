#!/bin/bash
# Usage: build_logo.sh [icon_cells] [word_cells] [gap_cells]
# Layout: circular logo on the left, "PlayerA" on the right, in colored half-block pixels.
cd ~/.config/screensaver || exit 1

ICON=${1:-72}      # circle width in cells (pixel grid is ICON x ICON, since 1 cell = 1x2 pixels)
WORD=${2:-110}     # "PlayerA" width in cells
GAP=${3:-6}        # empty cells between logo and word
WORD_COLOR="#29a3e0"
FONT=${FONT:-$(fc-match -f '%{file}' 'sans:bold')}
export GAP

# 1) Circular logo, original SVG colors (rendered large, then downsampled for clean edges)
rsvg-convert -w 1600 -h 1600 image.svg -o logo.png
magick logo.png -resize 1200x1200 -background black -alpha remove -alpha off \
  \( -size 1200x1200 xc:black -fill white -draw "circle 600,600 600,4" \) \
  -compose Multiply -composite icon.png

# 2) "PlayerA" wording as an image
magick -background black -fill "$WORD_COLOR" -font "$FONT" -pointsize 300 \
  label:"PlayerA" -trim +repage -bordercolor black -border 10 word.png

# 3) Both to colored half-block pixels (square pixels)
chafa --format=symbols --symbols=vhalf --colors=full --dither=none --bg=000000 \
  --size=${ICON}x$((ICON / 2)) icon.png > icon_art.txt
chafa --format=symbols --symbols=vhalf --colors=full --dither=none --bg=000000 \
  --size=${WORD}x$((ICON / 2)) word.png > word_art.txt

# 4) Put them side by side, vertically centered -> logo.txt
python3 - << 'PY'
import os, re
ANSI = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')
NON_SGR = re.compile(r'\x1b\[[0-9;?]*[A-Za-ln-z]')
vis = lambda s: len(ANSI.sub('', s))

def load(name):
    rows = [NON_SGR.sub('', r) for r in open(name).read().split('\n')]
    while rows and rows[-1] == '':
        rows.pop()
    return rows

def pad(rows):
    w = max(map(vis, rows))
    return [r + '\x1b[0m' + ' ' * (w - vis(r)) for r in rows], w

def vcenter(rows, w, H):
    top = (H - len(rows)) // 2
    blank = ' ' * w
    return [blank] * top + rows + [blank] * (H - len(rows) - top)

icon, iw = pad(load('icon_art.txt'))
word, ww = pad(load('word_art.txt'))
H = max(len(icon), len(word))
gap = ' ' * int(os.environ['GAP'])
lines = [a + gap + b for a, b in zip(vcenter(icon, iw, H), vcenter(word, ww, H))]
open('logo.txt', 'w').write('\n'.join(lines) + '\n')
print(f'logo.txt: {len(lines)} lines x {iw + len(gap) + ww} cols')
PY
