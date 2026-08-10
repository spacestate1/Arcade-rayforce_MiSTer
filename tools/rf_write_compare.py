#!/usr/bin/env python3
"""68020 go/no-go verdict tool.

Expands MAME's watchpoint write log (WR <addr8> <data8> sz<n> lines inside
rf_acc.tr) into the 16-bit bus operations TG68K performs, mirrors
rf_cpu_spike.sv's hash fold bit-for-bit, and prints the hash after exactly
4096 bus writes -- the value the board freezes on screen row 5.

    python3 tools/rf_write_compare.py rf_acc.tr            # expected values
    python3 tools/rf_write_compare.py rf_acc.tr uart.log   # diff a board dump

Bus expansion rules (68020, big-endian, 16-bit TG68K bus):
    sz16 even       -> (addr,   data,        UDS+LDS)
    sz32 even       -> (addr,   data>>16,    UDS+LDS), (addr+2, data&FFFF, UDS+LDS)
    sz8  even       -> (addr,   byte<<8,     UDS)
    sz8  odd        -> (addr,   byte,        LDS)          [addr bit0 kept in hash]
    misaligned 16/32 -> flagged and counted; expansion for them is not
                        implemented until the boot stream actually contains one.

The hash folds RAW addr[15:0] (bit0 included), {addr[23:16], 6'b0, UDS, LDS},
then the lane-masked data -- identical to the RTL.
"""
import re, sys

TARGET = 4096


def rotl1(v):
    return ((v << 1) | (v >> 31)) & 0xFFFFFFFF


def fold(h, w):
    return (rotl1(h) + (w & 0xFFFF)) & 0xFFFFFFFF


def expand(addr, data, size):
    """Yield (addr_raw, data16_masked, uds, lds) bus ops."""
    if size == 16:
        if addr & 1:
            return None                     # misaligned, not modelled yet
        return [(addr, data & 0xFFFF, 1, 1)]
    if size == 32:
        if addr & 1:
            return None
        return [(addr, (data >> 16) & 0xFFFF, 1, 1),
                (addr + 2, data & 0xFFFF, 1, 1)]
    if size == 8:
        b = data & 0xFF
        if addr & 1:
            return [(addr, b, 0, 1)]
        return [(addr, b << 8, 1, 0)]
    return None


def mame_ops(path, limit):
    ops, skipped = [], 0
    rx = re.compile(r"^WR ([0-9A-F]{8}) ([0-9A-F]{8}) sz(\d+)")
    with open(path, errors="ignore") as fh:
        for line in fh:
            m = rx.match(line)
            if not m:
                continue
            e = expand(int(m.group(1), 16), int(m.group(2), 16),
                       int(m.group(3)))
            if e is None:
                skipped += 1
                continue
            ops.extend(e)
            if len(ops) >= limit:
                break
    return ops[:limit], skipped


def op_hash(ops):
    h = 0
    for addr, data, uds, lds in ops:
        h = fold(h, addr & 0xFFFF)
        h = fold(h, (((addr >> 16) & 0xFF) << 8) | (uds << 1) | lds)
        h = fold(h, data)
    return h


def parse_uart(path):
    """Ring entries: 'W aaaaaa dddd L'. Word address only (bit0 lost)."""
    ops = []
    rx = re.compile(r"^W ([0-9A-F]{6}) ([0-9A-F]{4}) ([0-3])")
    for line in open(path, errors="ignore"):
        m = rx.match(line)
        if m:
            ops.append((int(m.group(1), 16), int(m.group(2), 16),
                        (int(m.group(3)) >> 1) & 1, int(m.group(3)) & 1))
    return ops


def main():
    tr = sys.argv[1] if len(sys.argv) > 1 else "rf_acc.tr"
    ops, skipped = mame_ops(tr, TARGET)
    print(f"MAME ops expanded : {len(ops)} (misaligned skipped: {skipped})")
    print(f"expected wr_count : 0x{min(len(ops), TARGET):08X}")
    print(f"expected wr_hash  : 0x{op_hash(ops):08X}   <- screen row 5")

    if len(sys.argv) > 2:
        board = parse_uart(sys.argv[2])
        print(f"board ops parsed  : {len(board)}")
        n = min(len(board), len(ops))
        for i in range(n):
            ba, bd, bu, bl = board[i]
            ma, md, mu, ml = ops[i]
            if (ba, bd, bu, bl) != (ma & ~1, md, mu, ml):
                print(f"FIRST DIVERGENCE at op {i}:")
                print(f"  board: addr={ba:06X} data={bd:04X} lanes={bu}{bl}")
                print(f"  mame : addr={ma & ~1:06X} data={md:04X} lanes={mu}{ml}")
                lo = max(0, i - 3)
                for j in range(lo, min(n, i + 3)):
                    ba2, bd2, *_ = board[j]
                    ma2, md2, *_ = ops[j]
                    mark = " <-" if j == i else ""
                    print(f"   op{j}: board {ba2:06X}:{bd2:04X}  "
                          f"mame {ma2 & ~1:06X}:{md2:04X}{mark}")
                return 1
        print(f"IDENTICAL for {n} compared ops")
    return 0


if __name__ == "__main__":
    sys.exit(main())
