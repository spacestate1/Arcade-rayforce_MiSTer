#!/usr/bin/env python3
"""Full model frame (playfields + pivot + sprites) for sim/pipe_tb.cpp.

rf_video_pipe now renders everything the model does except the pivot pixel-
layer corner cases, so the reference is the whole picture. Sprites lag 2
frames in the model; the bench feeds the RTL sprite RAM from frame-2 so the
two agree. Rows are hex RGB, visible lines only.

    sim/gen_pipe_ref.py [dump_dir] [frame] > sim/pipe_ref.txt
"""
import os
import sys

os.environ["F3_ONLY"] = "pv,pf0,pf1,pf2,pf3,sp0,sp1,sp2,sp3"
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import f3_gfx
import f3_render as R

d = sys.argv[1] if len(sys.argv) > 1 else "dump"
frame = int(sys.argv[2]) if len(sys.argv) > 2 else 1800

gfxs = R.load_gfx(d)
eng = R.SpriteEngine(gfxs["spr"])
frames = [f for f in (frame - 2, frame - 1, frame)
          if os.path.exists(os.path.join(d, "f3_%05d_spriteram.bin" % f))]
img = None
for i, f in enumerate(frames):
    dump = R.Dump(d, f)
    gfxs["char"] = f3_gfx.decode_char(dump.charram_raw)
    gfxs["pivot"] = f3_gfx.decode_char(dump.pivot_raw)
    if i == len(frames) - 1:
        img = R.render_frame(dump, gfxs, eng)
        break
    eng.draw_sprites()
    eng.get_sprite_info(dump.spriteram)

print(f"# frame {frame} playfields + pivot + sprites")
for sy in range(R.VIS_Y0, R.VIS_Y1 + 1):
    row = img[sy - R.VIS_Y0]
    print(f"{sy} " + " ".join("%02x%02x%02x" % (p[0], p[1], p[2]) for p in row))
