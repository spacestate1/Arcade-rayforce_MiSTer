#!/usr/bin/env python3
"""Compare a captured write-ring dump against MAME's write stream.

    .venv/bin/python3 tools/rf_uart.py -t 12 -o rf_uart.log   # UART Debug = Write Ring
    python3 tools/rf_ring_check.py rf_uart.log [rf_acc.tr]

The ring holds 4096 architectural bus writes and the dumper prints it in a
loop, so a capture almost always starts mid-pass. rf_write_compare.py compares
from the first op it parses, which then fails for a reason that has nothing to
do with the core. This anchors on a `===` pass header first, which is the
workaround that used to live as a copy-pasted snippet in HANDOFF.md.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rf_write_compare import mame_ops, TARGET, op_hash

cap = sys.argv[1] if len(sys.argv) > 1 else "rf_uart.log"
tr = sys.argv[2] if len(sys.argv) > 2 else "rf_acc.tr"

ops, _ = mame_ops(tr, TARGET)
rx = re.compile(r"^W ([0-9A-F]{6}) ([0-9A-F]{4}) ([0-3])")

entries, headers = [], []
for ln, line in enumerate(open(cap, errors="ignore")):
    if line.startswith("==="):
        headers.append(ln)
    m = rx.match(line)
    if m:
        entries.append((ln, int(m.group(1), 16), int(m.group(2), 16),
                        (int(m.group(3)) >> 1) & 1, int(m.group(3)) & 1))

print(f"{cap}: {len(entries)} ops, {len(headers)} pass headers")

for h in headers:
    seg = [e for e in entries if h < e[0] <= h + 4096][:4096]
    if len(seg) != 4096:
        continue
    if all((e[1], e[2], e[3], e[4]) == (ops[i][0] & ~1, ops[i][1], ops[i][2], ops[i][3])
           for i, e in enumerate(seg)):
        h32 = op_hash([(e[1], e[2], e[3], e[4]) for e in seg])
        print(f"IDENTICAL for 4096 compared ops; hash 0x{h32:08X}")
        sys.exit(0)
    # first divergence, for when it is not identical
    for i, e in enumerate(seg):
        want = (ops[i][0] & ~1, ops[i][1], ops[i][2], ops[i][3])
        got = (e[1], e[2], e[3], e[4])
        if want != got:
            print(f"  pass at line {h}: diverges at op {i}: board {got} vs mame {want}")
            break

print("NO CLEAN PASS FOUND")
sys.exit(1)
