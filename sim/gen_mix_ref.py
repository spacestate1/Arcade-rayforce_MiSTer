#!/usr/bin/env python3
"""Reference for sim/mix_tb.cpp: the sprite and pivot samples the mixer
would see on each line, and the frame the mixer must produce.

Sprites and the pivot layer have no RTL yet, so the bench feeds their line
samples straight from the model, exactly as render_frame samples them, and
compares the mixer's output against the model's frame -- which is MAME's
frame, pixel for pixel (tools/f3_regress.py). That makes this an end-to-end
check of line decode + playfield build + tile fetch + mixer against MAME,
with only the two unbuilt layers stubbed by their oracle.

    sim/gen_mix_ref.py [dump_dir] [frame] > sim/mix_ref.txt

Per line:  L sy pv_used sp_used
           PV 320 values   (color | opaque << 13)
           SP 320 values   (sprite framebuffer colour, 0 = none)
           RGB 320 hex     (visible lines only)

Sprite lag is 2 (gunlock), so the two preceding frames must be dumped too.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import numpy as np
import f3_gfx
import f3_render as R

d = sys.argv[1] if len(sys.argv) > 1 else "dump"
frame = int(sys.argv[2]) if len(sys.argv) > 2 else 1800

gfxs = R.load_gfx(d)
eng = R.SpriteEngine(gfxs["spr"])

# same sequencing as f3_render.main: frames f-2, f-1 feed the sprite engine,
# the last frame is rendered with the framebuffer as it stands before its
# own draw_sprites
frames = [f for f in (frame - 2, frame - 1, frame)
          if os.path.exists(os.path.join(d, "f3_%05d_spriteram.bin" % f))]
if len(frames) < 3:
    sys.exit("need dumps for frame-2 and frame-1 as well (sprite_lag 2)")

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

flip = eng.flipscreen
vram_pix, vram_flg = R.build_vram_layer(dump, gfxs["char"], flip)
pixel_pix, pixel_flg = R.build_pixel_layer(dump, gfxs["pivot"], flip)
text_used = R.row_usage_text(dump)

line = R.LineInf()
if flip:
    line.pivot.reg_sx = (dump.control_1[4] - 12) & 0xFFFF
    line.pivot.reg_sy = dump.control_1[5] & 0xFFFF
else:
    line.pivot.reg_sx = (-dump.control_1[4] - 5) & 0xFFFF
    line.pivot.reg_sy = (-dump.control_1[5]) & 0xFFFF

xs = np.arange(R.H_START, R.H_START + R.H_VIS)
print(f"# frame {frame} flip {int(flip)}")
for sy in range(256):
    R.read_line_ram(dump.line_ram, line, (255 - sy) if flip else sy, dump.control_1)
    line.y = sy
    pv = line.pivot
    if pv.use_pix():
        pv.pix, pv.flg = pixel_pix, pixel_flg
    else:
        pv.pix, pv.flg = vram_pix, vram_flg

    ya = pv.y_index(sy)
    ya = (0x1FF - ya) if flip else ya
    pv_used = int(pv.use_pix() or text_used[ya >> 3])
    sp_used = int(eng.row_usage[sy]) & 0xF

    rx = R.mosaic(xs, line.x_sample) if pv.x_sample_enable else xs
    gx = pv.x_index(rx)
    y = pv.y_index(sy)
    pvc = pv.pix[y][gx].astype(np.int64) & 0xFFFF
    pvo = ((pv.flg[y][gx].astype(np.int64) & 0xF0) != 0).astype(np.int64)

    rxs = R.mosaic(xs, line.x_sample) if line.sp[0].x_sample_enable else xs
    spc = eng.fb[sy][rxs].astype(np.int64) & 0xFFFF

    print(f"L {sy} {pv_used} {sp_used}")
    print("PV " + " ".join(str(int(v)) for v in (pvc | (pvo << 13))))
    print("SP " + " ".join(str(int(v)) for v in spc))
    if R.VIS_Y0 <= sy <= R.VIS_Y1:
        row = img[sy - R.VIS_Y0]
        print("RGB " + " ".join("%02x%02x%02x" % (p[0], p[1], p[2]) for p in row))
    if sy != 0:
        for pf in line.pf:
            pf.reg_fx_y += pf.y_scale
