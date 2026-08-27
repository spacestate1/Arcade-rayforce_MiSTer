#!/usr/bin/env python3
"""Generate rtl/rf_font8x8.sv -- the 8x8 text font for the core self-test page.

Source is a stock PSF2 console font (cp850-8x8), whose glyphs for 0x20-0x5F are
plain ASCII. Only that 64-character range is emitted: uppercase, digits and the
punctuation the self-test page uses. That is 512 bytes, one M10K.

The output is checked in, so the build does not depend on this script or on the
host having kbd fonts installed. Re-run it only if the font needs to change:

    python3 tools/make_font.py

Glyph rows are stored MSB-left, matching PSF, so the renderer selects a pixel
with bits[7 - x].
"""

import argparse
import gzip
import struct
import sys
from pathlib import Path

DEFAULT_PSF = "/usr/share/kbd/consolefonts/cp850-8x8.psfu.gz"
FIRST_CHAR = 0x20
LAST_CHAR = 0x5F


def read_psf(path):
    raw = Path(path).read_bytes()
    if path.endswith(".gz"):
        raw = gzip.decompress(Path(path).read_bytes())

    if raw[:4] == bytes([0x72, 0xB5, 0x4A, 0x86]):
        _ver, hdr, _flags, length, charsize, height, width = struct.unpack(
            "<7I", raw[4:32]
        )
        if (width, height) != (8, 8):
            sys.exit(f"{path}: need an 8x8 font, got {width}x{height}")
        return [raw[hdr + i * charsize : hdr + (i + 1) * charsize] for i in range(length)]

    if raw[0] == 0x36 and raw[1] == 0x04:
        charsize = raw[3]
        if charsize != 8:
            sys.exit(f"{path}: need an 8x8 font, got 8x{charsize}")
        count = 512 if (raw[2] & 0x01) else 256
        return [raw[4 + i * 8 : 4 + (i + 1) * 8] for i in range(count)]

    sys.exit(f"{path}: not a PSF1 or PSF2 font")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--psf", default=DEFAULT_PSF)
    ap.add_argument("-o", "--out", default="rtl/rf_font8x8.sv")
    ap.add_argument("--show", action="store_true", help="print the glyphs as ASCII art")
    args = ap.parse_args()

    glyphs = read_psf(args.psf)
    if len(glyphs) <= LAST_CHAR:
        sys.exit(f"{args.psf}: only {len(glyphs)} glyphs, need at least {LAST_CHAR + 1}")

    wanted = [glyphs[c] for c in range(FIRST_CHAR, LAST_CHAR + 1)]

    if args.show:
        for i, g in enumerate(wanted):
            print(f"--- {chr(FIRST_CHAR + i)!r} (0x{FIRST_CHAR + i:02x})")
            for b in g:
                print("".join("#" if b & (0x80 >> x) else "." for x in range(8)))

    lines = []
    lines.append("//" + "=" * 74)
    lines.append("//  Ray Force - 8x8 text font for the core self-test page")
    lines.append("//")
    lines.append("//  GENERATED FILE -- do not edit by hand.")
    lines.append(f"//  Produced by tools/make_font.py from {args.psf}")
    lines.append("//")
    lines.append("//  Covers ASCII 0x20-0x5F (space, punctuation, digits, uppercase), which")
    lines.append("//  is everything the self-test page prints. Address is {code, row} where")
    lines.append("//  code = ascii - 0x20. Rows are MSB-left, so pixel x is bits[7 - x].")
    lines.append("//" + "=" * 74)
    lines.append("")
    lines.append("module rf_font8x8 (")
    lines.append("    input  logic       clk,")
    lines.append("    input  logic [5:0] code,   // ascii - 0x20")
    lines.append("    input  logic [2:0] row,")
    lines.append("    output logic [7:0] bits")
    lines.append(");")
    lines.append("")
    lines.append("    logic [7:0] rom [0:511];")
    lines.append("")
    lines.append("    initial begin")
    for i, g in enumerate(wanted):
        ch = chr(FIRST_CHAR + i)
        label = "space" if ch == " " else ch
        vals = ", ".join(f"8'h{b:02X}" for b in g)
        lines.append(f"        // 0x{FIRST_CHAR + i:02X} {label}")
        for r, b in enumerate(g):
            lines.append(f"        rom[{i * 8 + r:3d}] = 8'h{b:02X};")
        del vals
    lines.append("    end")
    lines.append("")
    lines.append("    always_ff @(posedge clk) bits <= rom[{code, row}];")
    lines.append("")
    lines.append("endmodule")
    lines.append("")

    out = Path(args.out)
    out.write_text("\n".join(lines))
    print(f"wrote {out} ({LAST_CHAR - FIRST_CHAR + 1} glyphs, 512 bytes)")


if __name__ == "__main__":
    main()
