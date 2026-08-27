#!/usr/bin/env python3
"""Convert a raw ARGB32 frame from oracle_f3dump.lua into a PNG.

The oracle writes the reference picture as raw pixels (see the note in
oracle_f3dump.lua about MAME's auto-incrementing snapshot names). This is
just the viewer for it.

    tools/rf_argb2png.py dump/f3_01800_frame.argb [out.png]
"""
import sys, os
import numpy as np
from PIL import Image

src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(src)[0] + ".png"
meta = os.path.splitext(src)[0] + ".txt"
w, h = (int(v) for v in open(meta).read().split())

raw = np.frombuffer(open(src, "rb").read(), dtype=np.uint8).reshape(h, w, 4)
# MAME bitmap_argb32 is little-endian 0xAARRGGBB, so bytes come out B,G,R,A
Image.fromarray(raw[:, :, [2, 1, 0]]).save(dst)
print(f"{dst}  {w}x{h}")
