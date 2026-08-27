#!/usr/bin/env python3
"""Emit the reference line-RAM decode for a dumped frame.

Runs tools/f3_render.py's read_line_ram over all 256 screen lines exactly as
render_frame does -- including the flipscreen walk, where the line RAM index
counts DOWN as the raster goes down -- and writes one row of decoded state per
line for sim/check_line.py to diff the RTL against.

    sim/gen_line_ref.py [dump_dir] [frame] > sim/line_ref.txt
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import f3_render as R

d = sys.argv[1] if len(sys.argv) > 1 else "dump"
frame = int(sys.argv[2]) if len(sys.argv) > 2 else 1800

dump = R.Dump(d, frame)
extend = 1 if (dump.control_1[7] & 0x80) else 0
flip = True          # Ray Force: graphics flipped in ROM, flipscreen bit set

line = R.LineInf()
print(f"# extend {extend} flip {int(flip)}")
for sy in range(256):
    y = (255 - sy) if flip else sy
    R.read_line_ram(dump.line_ram, line, y, dump.control_1)
    f = [sy, y]
    f += [c[0] & 0x1FF for c in line.clip] + [c[1] & 0x1FF for c in line.clip]
    f += [int(b) for b in line.blend]
    f += [line.x_sample, line.fx_6400, line.bg_palette]
    f += [line.pivot.pivot_control, int(line.pivot.blend_select_v),
          line.pivot.pivot_enable, line.pivot.mix_value,
          int(line.pivot.x_sample_enable)]
    f += [sp.mix_value for sp in line.sp]
    f += [int(sp.blend_select_v) for sp in line.sp]
    f += [int(line.sp[0].x_sample_enable)]
    f += [p.colscroll for p in line.pf]
    f += [int(p.alt_tilemap) for p in line.pf]
    f += [p.x_scale for p in line.pf]
    f += [p.y_scale for p in line.pf]
    f += [p.pal_add & 0xFFFF for p in line.pf]
    f += [p.rowscroll & 0xFFFFF for p in line.pf]
    f += [p.mix_value for p in line.pf]
    f += [int(p.x_sample_enable) for p in line.pf]
    print(" ".join(str(v) for v in f))
