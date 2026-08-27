#!/usr/bin/env python3
"""Diff rf_video_line's decode against the model's, line by line."""
import sys

ref = sys.argv[1] if len(sys.argv) > 1 else "line_ref.txt"
got = sys.argv[2] if len(sys.argv) > 2 else "line_out.txt"

NAMES = (["sy", "y"] + [f"clip_l{i}" for i in range(4)] + [f"clip_r{i}" for i in range(4)]
         + [f"blend{i}" for i in range(4)]
         + ["x_sample", "fx_6400", "bg_palette",
            "pivot_control", "pivot_bsel", "pivot_enable", "pivot_mix", "pivot_mosaic"]
         + [f"sp_mix{i}" for i in range(4)] + [f"sp_bsel{i}" for i in range(4)]
         + ["sp_mosaic"]
         + [f"pf_colscroll{i}" for i in range(4)] + [f"pf_alt{i}" for i in range(4)]
         + [f"pf_xscale{i}" for i in range(4)] + [f"pf_yscale{i}" for i in range(4)]
         + [f"pf_paladd{i}" for i in range(4)] + [f"pf_rowscroll{i}" for i in range(4)]
         + [f"pf_mix{i}" for i in range(4)] + [f"pf_mosaic{i}" for i in range(4)])

R = [l.split() for l in open(ref) if not l.startswith("#")]
G = [l.split() for l in open(got) if not l.startswith("#")]
if len(R) != len(G):
    sys.exit(f"line count differs: ref {len(R)} rtl {len(G)}")

bad_lines = 0
bad_fields = {}
for r, g in zip(R, G):
    diff = [(NAMES[i], r[i], g[i]) for i in range(len(NAMES)) if r[i] != g[i]]
    if diff:
        bad_lines += 1
        for nm, a, b in diff:
            bad_fields[nm] = bad_fields.get(nm, 0) + 1
        if bad_lines <= 3:
            print(f"  line sy={r[0]} y={r[1]}: " +
                  ", ".join(f"{nm} ref={a} rtl={b}" for nm, a, b in diff[:6]))

print(f"{len(R) - bad_lines}/{len(R)} lines match the model")
if bad_fields:
    print("  fields differing:",
          ", ".join(f"{k} x{v}" for k, v in sorted(bad_fields.items(), key=lambda kv: -kv[1])))
sys.exit(1 if bad_lines else 0)
