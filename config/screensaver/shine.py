#!/usr/bin/env python3
# Sunlight-shine sweep over the "Arch Linux" rows, left to right.
import os, re, sys, time

HOME = os.path.expanduser('~/.config/screensaver')
SWEEPS = int(sys.argv[1]) if len(sys.argv) > 1 else 4
DX, DY = 0, 0            # nudge if the shine is off by a cell
FPS, SPEED = 60, 1.1     # frames/sec, cells moved per frame
HALF, SLANT, STRENGTH = 7, 3, 0.9
PAUSE = 1.2              # seconds between sweeps

meta = dict(l.strip().split('=') for l in open(f'{HOME}/layout.txt') if '=' in l)
start, end, width = int(meta['word_start']), int(meta['word_end']), int(meta['width'])
art = open(f'{HOME}/logo.txt').read().split('\n')
while art and art[-1] == '':
    art.pop()
rows = art[start:end]

NON_SGR = re.compile(r'\x1b\[[0-9;?]*[A-Za-ln-z]')
SGR = re.compile(r'\x1b\[([0-9;]*)m')

def parse(line):
    line = NON_SGR.sub('', line)
    cells, fg, bg, pos = [], None, None, 0
    for m in SGR.finditer(line):
        cells += [(ch, fg, bg) for ch in line[pos:m.start()]]
        pos = m.end()
        p = [int(x) if x else 0 for x in m.group(1).split(';')]
        i = 0
        while i < len(p):
            c = p[i]
            if c == 0: fg = bg = None
            elif c == 39: fg = None
            elif c == 49: bg = None
            elif c in (38, 48) and p[i + 1:i + 2] == [2]:
                col = tuple(p[i + 2:i + 5])
                if c == 38: fg = col
                else: bg = col
                i += 4
            i += 1
    cells += [(ch, fg, bg) for ch in line[pos:]]
    return cells

grid = [parse(r) for r in rows]

def lit(c, f):
    if c is None or sum(c) < 60 or f <= 0:   # leave black background alone
        return c
    return tuple(int(v + (255 - v) * f) for v in c)

def sgr(fg, bg):
    a = '\x1b[38;2;%d;%d;%dm' % fg if fg else '\x1b[39m'
    b = '\x1b[48;2;%d;%d;%dm' % bg if bg else '\x1b[49m'
    return a + b

def frame(pos):
    cols, lines = os.get_terminal_size(sys.stdout.fileno())
    left = (cols - width) // 2 + DX
    top = (lines - len(art)) // 2 + DY
    out = []
    for r, cells in enumerate(grid):
        out.append('\x1b[%d;%dH' % (top + start + r + 1, left + 1))
        prev = None
        for x, (ch, fg, bg) in enumerate(cells):
            d = (x + r * SLANT) - pos
            f = max(0.0, 1 - abs(d) / HALF) ** 1.5 * STRENGTH
            cur = (lit(fg, f), lit(bg, f))
            if cur != prev:
                out.append(sgr(*cur))
                prev = cur
            out.append(ch)
        out.append('\x1b[0m')
    sys.stdout.write(''.join(out))
    sys.stdout.flush()

sys.stdout.write('\x1b[?25l')
span = width + HALF * 2 + SLANT * len(grid)
try:
    time.sleep(0.4)
    for _ in range(SWEEPS):
        pos = -HALF
        while pos < span:
            frame(pos)
            pos += SPEED
            time.sleep(1 / FPS)
        frame(-9999)          # restore the plain word
        time.sleep(PAUSE)
except (KeyboardInterrupt, BrokenPipeError):
    pass
