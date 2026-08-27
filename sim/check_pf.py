#!/usr/bin/env python3
"""Diff rf_video_pf's line samples against the model's.

A playfield whose row is unused contributes nothing, so its samples are only
compared when both sides agree it IS used; the used flag itself is always
compared.
"""
import sys

ref = sys.argv[1] if len(sys.argv) > 1 else "pf_ref.txt"
got = sys.argv[2] if len(sys.argv) > 2 else "pf_out.txt"

R = [l.split() for l in open(ref) if not l.startswith("#")]
G = [l.split() for l in open(got) if not l.startswith("#")]
if len(R) != len(G):
    sys.exit(f"row count differs: ref {len(R)} rtl {len(G)}")

bad_rows = used_diff = px_bad = px_total = 0
shown = 0
for r, g in zip(R, G):
    sy, pf, ur = int(r[0]), int(r[1]), int(r[2])
    ug = int(g[2])
    if ur != ug:
        used_diff += 1
        if shown < 4:
            print(f"  sy={sy} pf{pf}: used ref={ur} rtl={ug}")
            shown += 1
        continue
    if not ur:
        continue
    rv, gv = r[3:], g[3:]
    px_total += len(rv)
    diffs = [x for x in range(len(rv)) if rv[x] != gv[x]]
    if diffs:
        bad_rows += 1
        px_bad += len(diffs)
        if shown < 4:
            x = diffs[0]
            print(f"  sy={sy} pf{pf}: {len(diffs)} px differ, first x={x}: "
                  f"ref {int(rv[x]):#06x} rtl {int(gv[x]):#06x}")
            shown += 1

print(f"{len(R) - bad_rows - used_diff}/{len(R)} playfield-lines match; "
      f"{px_total - px_bad}/{px_total} compared pixels identical; "
      f"{used_diff} used-flag mismatches")
sys.exit(1 if (bad_rows or used_diff) else 0)
