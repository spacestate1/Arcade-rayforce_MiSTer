#!/usr/bin/env python3
"""Check sim/gfx_tb's fetched tile rows against tools/f3_gfx.py.

    make -C sim gfx

f3_gfx.py is the decoder that makes tools/f3_render.py reproduce MAME's own
frames pixel-exact, so it is the reference here -- not a second set of
hand-worked expected values that could be wrong the same way.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import f3_gfx

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
dump = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "dump")
fetched = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "sim", "fetched.txt")

pf = f3_gfx.load_playfield_gfx(os.path.join(dump, "rgn_tilemap.bin"),
                               os.path.join(dump, "rgn_tilemap_hi.bin"))
bad = n = 0
for line in open(fetched):
    v = [int(x) for x in line.split()]
    code, row, pix = v[0], v[1], v[2:]
    exp = pf[code, row].tolist()
    n += 1
    if pix != exp:
        bad += 1
        if bad <= 3:
            print(f"  MISMATCH code={code} row={row}\n    rtl {pix}\n    exp {exp}")

print(f"{n - bad}/{n} tile rows match the validated decoder")
sys.exit(1 if bad or n == 0 else 0)
