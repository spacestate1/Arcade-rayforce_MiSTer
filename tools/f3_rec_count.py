#!/usr/bin/env python3
"""How many sprite records a frame needs: the RTL's count, from the model.

rf_video_spr stores one record per RUN -- the consecutive source rows of one
sprite that land on the same screen line (a y-shrunk sprite puts several of
its 16 rows on one line). This walks the model's sprite list exactly as the
RTL's expand does and prints, per frame, the sprites, the rows in range, and
the runs. `runs` is what the RTL's rec_peak (SPR REC on the self-test page,
dbg_rec[31:16] in the pipe bench) must read for that sprite RAM.

    tools/f3_rec_count.py dump 2930          # this frame's sprite RAM
    tools/f3_rec_count.py dump 2930 --lag    # frame 2928's: what the pipe
                                             # bench draws for frame 2930
    tools/f3_rec_count.py dump               # every frame in the directory

PER-GAME VISAREA. The run count depends on which rows are in range, so this
follows f3_render's F3_VIS exactly as the benches do. Ray Force is the
default (f3_224a, 224 lines from 31); ANY OTHER GAME MUST SAY SO:

    F3_VIS=f3 tools/f3_rec_count.py dump/ear      # 232 lines from 24

Left at the default, an Elevator Action dump is counted through Ray Force's
window and the 8 lines outside it are silently dropped -- the same class of
mistake as the sprite cull bounds that were hardcoded twice (see "F3
per-game constants" in HANDOFF.md).

The sprite_lag is 2, so the pipe bench (and the board) draw frame f from the
sprite RAM of frame f-2; --lag prints that one, for comparing with the bench.
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f3_render as R


def count(d, frame):
    dump = R.Dump(d, frame)
    eng = R.SpriteEngine([None] * 16384)     # nelem only; no pixels drawn
    eng.get_sprite_info(dump.spriteram)
    rows = runs = 0
    for s in eng.spritelist:
        dy8 = s.y + (0 if eng.flipscreen else 255)
        prev = None
        for yy in range(16):
            dy = dy8 >> 8
            dy8 += s.scale_y
            if dy < R.VIS_Y0 or dy > R.VIS_Y1:
                prev = None
                continue
            rows += 1
            if dy != prev:
                runs += 1
                prev = dy
    return len(eng.spritelist), rows, runs


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    lag = "--lag" in sys.argv
    d = args[0] if args else "dump"
    if len(args) > 1:
        frames = [int(args[1])]
    else:
        frames = sorted(int(re.search(r"f3_(\d+)_spriteram", p).group(1))
                        for p in glob.glob(os.path.join(d, "f3_*_spriteram.bin")))
    print("%-8s %7s %6s %6s %8s" % ("frame", "sprites", "rows", "runs", "rows/run"))
    for f in frames:
        src = f - 2 if lag else f
        n, rows, runs = count(d, src)
        print("%-8d %7d %6d %6d %8.2f" % (f, n, rows, runs, rows / max(runs, 1)))


if __name__ == "__main__":
    main()
