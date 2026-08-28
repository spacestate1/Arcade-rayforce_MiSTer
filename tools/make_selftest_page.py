#!/usr/bin/env python3
"""Generate rtl/rf_selftest_page.sv -- the static text of the core self-test page.

The page is 40x28 characters over the 320x224 raster. This script emits the
label ROM plus the layout constants, so rf_selftest.sv and rf_uart_log.sv
cannot drift from each other or from the page: both read this ROM and overlay
the same value and status fields at the same columns.

Character codes are ascii-0x20, matching rf_font8x8.sv.

    python3 tools/make_selftest_page.py
"""
from pathlib import Path

COLS, ROWS = 40, 28
VAL_C0, VAL_W = 16, 8       # eight hex digits
ST_C0, ST_W = 26, 4         # PASS / FAIL / WAIT / BUSY

# (text, has_value, has_status). The check index of a value row is its position
# in the value-row list; rf_selftest.sv selects on the row number directly, so
# the two only have to agree on the row numbers below.
PAGE = [
    ("RAY FORCE / GUNLOCK   TAITO F3 CORE", 0, 0),
    ("SELF TEST",                           0, 0),
    ("-- LOAD AND FETCH -------------------", 0, 0),
    ("ROM BYTES",                           1, 1),
    ("ROM CHECKSUM",                        1, 1),
    ("SDRAM BIST",                          1, 1),
    ("-- CPU AND MEMORY MAP ---------------", 0, 0),
    ("PIVOT WR:SND PC",                     1, 1),   # {pivot RAM writes (must stay 0), sound CPU PC}
    ("WRITE HASH",                          1, 1),
    ("FETCH IN RANGE",                      1, 1),
    ("SPR REC : DROP",                      1, 1),   # {records built last prepass, rows dropped at the cap}
    ("-- INTERRUPTS -----------------------", 0, 0),
    ("SND ES WR : RUN",                     1, 1),   # {sound CPU ES5505 writes, running}
    ("IRQ2 ACK/64FRM",                      1, 1),
    ("SMP BIST:OVR:DR",                     1, 1),   # {sample-region BIST sum[15:0], sampler overruns, queue drops}
    ("-- VIDEO RAM WRITES -----------------", 0, 0),
    ("PALETTE",                             1, 1),
    ("PLAYFIELD",                           1, 1),
    ("SPRITE",                              1, 1),
    ("LINE RAM",                            1, 1),
    ("TEXT AND CHAR",                       1, 1),
    ("-- VIDEO PIPELINE / FRAME -----------", 0, 0),
    ("MIX : BUILD",                         1, 1),
    ("FETCH : PIX NZ",                      1, 1),
    ("MAXFETCH:BUILD",                      1, 1),
    ("TILE NZ:PF:PAL",                      1, 1),
    ("BUILD",                               1, 0),
    ("SPRLINE : LATE",                      1, 1),   # {longest sprite line draw, lines the mixer started before the draw finished them}
]

assert len(PAGE) == ROWS, f"{len(PAGE)} rows, expected {ROWS}"


def main():
    val_mask = 0
    st_mask = 0
    cells = []
    for r, (text, has_val, has_st) in enumerate(PAGE):
        if has_val:
            val_mask |= 1 << r
        if has_st:
            st_mask |= 1 << r
        if has_val and len(text) > VAL_C0:
            raise SystemExit(f"row {r} label runs into the value field: {text!r}")
        if len(text) > COLS:
            raise SystemExit(f"row {r} is {len(text)} chars, max {COLS}: {text!r}")
        padded = text.ljust(COLS)
        for c, ch in enumerate(padded):
            code = ord(ch) - 0x20
            if not 0 <= code < 64:
                raise SystemExit(f"row {r} col {c}: {ch!r} is outside the font")
            cells.append(code)

    out = []
    out.append("//" + "=" * 74)
    out.append("//  Ray Force - static text of the core self-test page")
    out.append("//")
    out.append("//  GENERATED FILE -- do not edit by hand.")
    out.append("//  Produced by tools/make_selftest_page.py")
    out.append("//")
    out.append(f"//  {COLS}x{ROWS} characters over the 320x224 raster. Two read ports: the")
    out.append("//  pixel renderer (rf_selftest) uses one, the UART logger (rf_uart_log)")
    out.append("//  uses the other, so what goes out the serial port is character-for-")
    out.append("//  character what is on the screen.")
    out.append("//" + "=" * 74)
    out.append("")
    out.append("package rf_selftest_pkg;")
    out.append(f"    localparam int ST_COLS  = {COLS};")
    out.append(f"    localparam int ST_ROWS  = {ROWS};")
    out.append(f"    localparam int ST_VAL_C0 = {VAL_C0};")
    out.append(f"    localparam int ST_VAL_W  = {VAL_W};")
    out.append(f"    localparam int ST_ST_C0  = {ST_C0};")
    out.append(f"    localparam int ST_ST_W   = {ST_W};")
    out.append("    // bit r set = row r prints a value / a status word")
    out.append(f"    localparam logic [{ROWS-1}:0] ST_VAL_ROWS = {ROWS}'h{val_mask:07X};")
    out.append(f"    localparam logic [{ROWS-1}:0] ST_ST_ROWS  = {ROWS}'h{st_mask:07X};")
    out.append("endpackage")
    out.append("")
    out.append("module rf_selftest_page (")
    out.append("    input  logic        clk,")
    out.append("    input  logic [10:0] a_addr,   // row * ST_COLS + col")
    out.append("    output logic  [5:0] a_char,")
    out.append("    input  logic [10:0] b_addr,")
    out.append("    output logic  [5:0] b_char")
    out.append(");")
    out.append("")
    out.append(f"    logic [5:0] rom [0:{len(cells)-1}];")
    out.append("")
    out.append("    initial begin")
    for r, (text, _, _) in enumerate(PAGE):
        out.append(f"        // row {r:2d}: {text!r}")
        base = r * COLS
        for c in range(COLS):
            out.append(f"        rom[{base + c:4d}] = 6'd{cells[base + c]:2d};")
    out.append("    end")
    out.append("")
    out.append("    always_ff @(posedge clk) begin")
    out.append("        a_char <= rom[a_addr];")
    out.append("        b_char <= rom[b_addr];")
    out.append("    end")
    out.append("")
    out.append("endmodule")
    out.append("")

    p = Path("rtl/rf_selftest_page.sv")
    p.write_text("\n".join(out))
    print(f"wrote {p} ({ROWS}x{COLS} = {len(cells)} cells)")
    print(f"  value rows 0x{val_mask:07X}, status rows 0x{st_mask:07X}")


if __name__ == "__main__":
    main()
