#!/usr/bin/env python3
"""Reference playfield samples for sim/pf_tb.cpp, straight from the model.

For every screen line and every playfield: the row-usage flag, then the 320
tilemap samples the mixer would read -- exactly what rf_video_pf hands the
mixer, before any priority or blending. Each sample packs
    bit 14   blend select (flags & 1)
    bit 13   opaque       (flags & 0xf0)
    bits 12:0 color       (pixmap value, palette_code*16 + pen)

    sim/gen_pf_ref.py [dump_dir] [frame] [--mosaic N] > sim/pf_ref.txt

--mosaic N forces the mosaic effect on every playfield with sample N, because
Ray Force never uses it and the path would otherwise ship unverified. The
bench takes the same flag and forces the same values into the RTL.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import numpy as np
import f3_gfx
import f3_render as R

args = [a for a in sys.argv[1:] if not a.startswith("--")]
d = args[0] if len(args) > 0 else "dump"
frame = int(args[1]) if len(args) > 1 else 1800
mosaic = int(sys.argv[sys.argv.index("--mosaic") + 1]) if "--mosaic" in sys.argv else 0

dump = R.Dump(d, frame)
gfx = f3_gfx.load_playfield_gfx(os.path.join(d, "rgn_tilemap.bin"),
                                os.path.join(d, "rgn_tilemap_hi.bin"))
flip = True
pf_pix, pf_flg = R.build_playfields(dump, gfx, flip)
pf_used = R.row_usage_playfields(dump)

line = R.LineInf()
for i in range(R.NUM_PF):
    sx, sy = R.get_pf_scroll(dump.control_0, i, flip)
    line.pf[i].reg_sx, line.pf[i].reg_sy = sx, sy
    line.pf[i].reg_fx_y = sy

xs = np.arange(R.H_START, R.H_START + R.H_VIS)
print(f"# frame {frame} mosaic {mosaic}")
for screen_y in range(256):
    R.read_line_ram(dump.line_ram, line, (255 - screen_y) if flip else screen_y, dump.control_1)
    line.y = screen_y
    if mosaic:
        line.x_sample = mosaic
        for p in line.pf:
            p.x_sample_enable = True
    for i in range(R.NUM_PF):
        pf = line.pf[i]
        pf.pix, pf.flg = pf_pix[i], pf_flg[i]
        pf.reg_fx_x = pf.reg_sx + pf.rowscroll
        pf.reg_fx_x += 10 * (pf.x_scale - (1 << 8))

        ya = pf.y_index(screen_y)
        ya = (0x1FF - ya) if flip else ya
        used = int(pf_used[i][ya >> 4])

        real_x = R.mosaic(xs, line.x_sample) if pf.x_sample_enable else xs
        gx = pf.x_index(real_x)
        y = pf.y_index(screen_y)
        col = pf.pix[y][gx].astype(np.int64)
        fl = pf.flg[y][gx].astype(np.int64)
        v = (col & 0x1FFF) | (((fl & 0xF0) != 0).astype(np.int64) << 13) | ((fl & 1) << 14)
        print(f"{screen_y} {i} {used} " + " ".join(str(int(x)) for x in v))
    if screen_y != 0:
        for pf in line.pf:
            pf.reg_fx_y += pf.y_scale
