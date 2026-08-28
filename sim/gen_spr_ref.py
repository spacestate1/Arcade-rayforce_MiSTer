#!/usr/bin/env python3
"""Reference for sim/spr_tb.cpp: the sprite LIST that get_sprite_info produces.

Stage (a) of the sprite engine -- the list walker -- is pure logic over
sprite RAM: the Axis position/zoom state machine, the bank switch, the jump
command, multi-block sprites and the scroll-mode globals. No graphics, no
framebuffer. This dumps the model's resulting sprite list so the RTL walker
can be checked entry-for-entry against it.

With sprite_lag 2 the sprites shown on frame F were built from get_sprite_info
of frame F-2's sprite RAM, run on a freshly-reset engine (bank=0, flip=0),
exactly as gen_mix_ref.py primes it. So the displayed list is simply
get_sprite_info over the F-2 dump. We emit that dump's sprite RAM alongside
the list so the bench feeds the RTL the identical bytes.

    sim/gen_spr_ref.py [dump_dir] [frame] > sim/spr_ref.txt

Output:
    # frame F src F-2 flip <0|1> extra <0-3> penmask <hex> n <count>
    S <tx> <ty> <scale_x> <scale_y> <code> <color> <fx> <fy> <pri>   (one per sprite)
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import f3_render as R

d = sys.argv[1] if len(sys.argv) > 1 else "dump"
frame = int(sys.argv[2]) if len(sys.argv) > 2 else 1800

src = frame - 2
if not os.path.exists(os.path.join(d, "f3_%05d_spriteram.bin" % src)):
    sys.exit("need the frame-2 dump (sprite_lag 2)")

gfxs = R.load_gfx(d)
eng = R.SpriteEngine(gfxs["spr"])
dump = R.Dump(d, src)
eng.get_sprite_info(dump.spriteram)

print("# frame %d src %d flip %d extra %d penmask %x n %d" % (
    frame, src, int(eng.flipscreen), eng.extra_planes, eng.pen_mask,
    len(eng.spritelist)))
for s in eng.spritelist:
    # tx/ty are signed .8 fixed; print as signed decimals
    print("S %d %d %d %d %d %d %d %d %d" % (
        s.x, s.y, s.scale_x, s.scale_y, s.code, s.color,
        int(s.flip_x), int(s.flip_y), s.pri))
