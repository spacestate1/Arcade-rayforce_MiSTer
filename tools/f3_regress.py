#!/usr/bin/env python3
"""Render every dumped frame with the F3 model and diff against MAME's own.

The model is only useful as an RTL reference for as long as it stays exact, so
this is the gate: any frame that is not pixel-identical fails the run.

    tools/f3_regress.py [dump_dir]
"""
import glob
import os
import re
import subprocess
import sys

d = sys.argv[1] if len(sys.argv) > 1 else "dump"
have = set(int(re.search(r"f3_(\d+)_spriteram\.bin", f).group(1))
           for f in glob.glob(os.path.join(d, "f3_*_spriteram.bin")))
allf = sorted(int(re.search(r"f3_(\d+)_frame\.argb", f).group(1))
              for f in glob.glob(os.path.join(d, "f3_*_frame.argb")))

# gunlock has sprite_lag 2: the sprites on screen came from sprite RAM two
# frames earlier, so a frame can only be reproduced when its two predecessors
# were dumped too. Frames without that history are skipped, not failed.
frames = [f for f in allf if (f - 1) in have and (f - 2) in have]
skipped = [f for f in allf if f not in frames]
if skipped:
    print("skipping (no 2-frame sprite history): " +
          ", ".join(str(f) for f in skipped) + "\n")

fails = 0
for f in frames:
    r = subprocess.run([sys.executable, "tools/f3_render.py", d, str(f), "--compare"],
                       capture_output=True, text=True)
    m = re.search(r"differing: (\d+) / (\d+)", r.stdout)
    if not m:
        print(f"frame {f:5d}  ERROR\n{r.stdout}{r.stderr}")
        fails += 1
        continue
    bad, total = int(m.group(1)), int(m.group(2))
    status = "ok" if bad == 0 else "FAIL"
    print(f"frame {f:5d}  {bad:6d} / {total}  {status}")
    fails += bad != 0

print(f"\n{len(frames) - fails}/{len(frames)} frames pixel-identical to MAME")
sys.exit(1 if fails else 0)
