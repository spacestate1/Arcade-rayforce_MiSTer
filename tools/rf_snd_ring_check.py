#!/usr/bin/env python3
"""Compare the sound CPU's captured write ring against MAME's sound stream.

    .venv/bin/python3 tools/rf_uart.py -t 12 -o snd_ring.log   # UART Debug = Sound Ring
    python3 tools/rf_snd_ring_check.py snd_ring.log dump/en3/en_writes.txt

The ring holds the last 4096 chip-region writes of the FPGA's sound 68000
(ES5505, bank, volume, ES5510 host, DUART -- the same set the oracle taps)
and rf_uart_dump prints it in a loop, so a capture starts mid-pass; each
`===` header starts a full pass. MAME's stream is the whole run from reset.

The order of writes within a frame depends on when the DUART interrupt
lands relative to the main loop, and TG68K.C is not cycle-identical to
MAME's 68000, so an exact 4096-long substring match is the ideal and a long
common run is the realistic proof. This finds, for each complete pass, the
longest run of consecutive ring entries that appears in order in MAME's
stream, and where. A run of thousands means the program runs; a run of a
few dozen means the map is wrong somewhere and the entries after the break
say where.
"""
import re
import sys


def mame_stream(path):
    out = []
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) < 5:
                continue
            tag = p[1]
            if tag not in ("ES", "BK", "VL", "DSP", "DU"):
                continue
            addr, data, mask = int(p[2], 16), int(p[3], 16), int(p[4], 16)
            uds, lds = (mask >> 8) & 1 if mask & 0xff00 else 0, 1 if mask & 0x00ff else 0
            # the ring stores the 16-bit data with unused lanes zeroed
            d = (data & 0xff00 if uds else 0) | (data & 0x00ff if lds else 0)
            out.append((addr >> 1, d, uds, lds))
    return out


def ring_entries(path):
    rx = re.compile(r"^W ([0-9A-F]{6}) ([0-9A-F]{4}) ([0-3])")
    entries, headers = [], []
    for ln, line in enumerate(open(path, errors="ignore")):
        if line.startswith("==="):
            headers.append(ln)
        m = rx.match(line)
        if m:
            lanes = int(m.group(3))
            uds, lds = (lanes >> 1) & 1, lanes & 1
            # rf_uart_dump prints addr[23:1] as a 6-digit byte address; the
            # data is the CPU's full 16-bit bus, which carries a byte write
            # on both halves -- keep only the lanes that were strobed, as
            # MAME's tap reports it
            d = int(m.group(2), 16)
            d = (d & 0xff00 if uds else 0) | (d & 0x00ff if lds else 0)
            entries.append((ln, int(m.group(1), 16) >> 1, d, uds, lds))
    return entries, headers


def longest_run(ring, mame):
    """Longest run of ring entries found consecutively in mame; (len, ring_i, mame_i)."""
    index = {}
    for i, e in enumerate(mame):
        index.setdefault(e, []).append(i)
    best = (0, 0, 0)
    n = len(ring)
    i = 0
    while i < n:
        cands = index.get(ring[i], [])
        run_best = 0
        run_at = 0
        for j in cands[:200]:
            k = 0
            while i + k < n and j + k < len(mame) and ring[i + k] == mame[j + k]:
                k += 1
            if k > run_best:
                run_best, run_at = k, j
        if run_best > best[0]:
            best = (run_best, i, run_at)
        i += max(1, run_best)
    return best


def main():
    cap = sys.argv[1] if len(sys.argv) > 1 else "snd_ring.log"
    tr = sys.argv[2] if len(sys.argv) > 2 else "dump/en3/en_writes.txt"
    mame = mame_stream(tr)
    entries, headers = ring_entries(cap)
    print(f"{cap}: {len(entries)} ring entries, {len(headers)} pass headers; MAME stream {len(mame)} writes")
    for h in headers:
        seg = [e for e in entries if h < e[0] <= h + 4200][:4096]
        if len(seg) != 4096:
            continue
        ring = [(a, d, u, l) for (_, a, d, u, l) in seg]
        n, ri, mi = longest_run(ring, mame)
        print(f"pass at line {h}: longest in-order run {n} of 4096 (ring[{ri}] = MAME write {mi})")
        # and the run from the ring's first entry (the boot sequence, if the
        # ring froze on its first 4096 writes)
        k = 0
        while k < 4096 and k < len(mame) and ring[k] == mame[k]:
            k += 1
        print(f"   from write 0: {k} identical before the first difference"
              + (f" (ring W {ring[k][0] << 1:06X} {ring[k][1]:04X} vs MAME W {mame[k][0] << 1:06X} {mame[k][1]:04X})" if k < 4096 else ""))
        if n < 4096 and n > 0:
            k = ri + n
            if k < 4096:
                a, d, u, l = ring[k]
                print(f"   first divergent ring entry: W {a << 1:06X} {d:04X} lanes {u}{l}")
                if mi + n < len(mame):
                    a2, d2, u2, l2 = mame[mi + n]
                    print(f"   MAME has there:             W {a2 << 1:06X} {d2:04X} lanes {u2}{l2}")
        break


if __name__ == "__main__":
    main()
