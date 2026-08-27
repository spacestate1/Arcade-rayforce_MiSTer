# Ray Force / Gunlock (Taito F3) — Handoff

**Date**: 2026-08-27
**Status**: Phase 2 underway. The real F3 main board is running the game's
frame loop **on hardware** — every Phase 1 proof still passes and the
interrupt handshake is exact. The video chipset is modelled in Python and
reproduces MAME's frames pixel-for-pixel. Next is renderer RTL.

**The board is at 172.17.1.164** (not .175 — that address is dead).

---

## What was done (2026-08-27)

### The real main board — `rtl/rf_main.sv` (replaces `rf_cpu_spike.sv`)

The spike answered its question (TG68K.C in 020 mode executes this program
correctly, write hash `0x10620931`) with a deliberately fake memory map:
everything outside ROM/RAM/palette read back zero and no interrupt was ever
delivered, so the boot code ran to its vblank wait at ~0x4060 and stopped.
No video RAM ever held real data, so no part of the pixel pipeline could be
developed or diffed. That is why Phase 2 starts with the map, not with pixels.

`rf_main.sv` is the whole `f3_map` from taito_f3.cpp:

```
000000-0FFFFF  ROM 1 MB, SDRAM via rf_prog_bus (unchanged from Phase 1)
100000-1FFFFF  rest of the ROM window, unpopulated -> 0x0000
300000-30007F  sound bankswitch (ignored)
400000-41FFFF  main RAM 128 KB, mirrored at 420000
440000-447FFF  palette 32 KB = 8192 x 24-bit
4A0000-4A001F  control: inputs, coin counters, EEPROM, watchdog
4C0000-4C0003  timer control (ignored)
600000-60FFFF  sprite RAM 64 KB
610000-617FFF  playfield RAM, tilemap window (4 x 0x2000, extend mode)
618000-61BFFF  playfield RAM, upper half
61C000-61DFFF  text RAM 8 KB
61E000-61FFFF  char RAM 8 KB
620000-62FFFF  line RAM 64 KB
630000-63FFFF  pivot RAM 64 KB
660000-66001F  video control (playfield/pivot scroll, extend bit)
C00000-C007FF  sound dual-port RAM
C80000/C80100  sound reset (ignored)
```

Every video RAM is a true dual-port BRAM: the CPU owns port A, the renderer
gets port B, already brought out of the module so the pixel pipeline can be
dropped in without touching `rf_main.sv` again.

**Interrupts.** Level 2 on vblank, level 3 at 10000 68020 cycles (625 us,
33358 clk_sys ticks) after it — taito_f3.cpp comments that the vblank handler
waits for int3, so it has to be delivered or the game hangs in vblank. Both
are autovectored (68EC020 AVEC). TG68K.C exposes no IACK strobe, so the
handler-address fetch at VBR+0x68 / VBR+0x6C is used as the acknowledge: it
is the one bus cycle that can only mean "the exception is being taken".
`irq2_cnt` / `irq3_cnt` are on the diagnostic screen so a missed acknowledge
shows as a counter running away from the frame count, not as a mystery hang.

**Other pieces**
- `rtl/rf_eeprom_93c46.sv` — the settings EEPROM (93C46, 16-bit org). Written
  properly rather than stubbed: the boot code reads it before drawing
  anything, and a stub that answers wrong sends the program down its "bad
  settings" path, which looks exactly like a broken CPU or video chip.
  Contents are volatile — hooking it to hps_io nvram is a Phase 4 item.
- Inputs: 2 players, start/coin/service, plus a **Service Mode** OSD toggle
  (`O[2]`) wired to the cabinet TEST switch. The F3 test menu is a useful
  early video target.
- `rtl/rayforce_video.sv` — raster timing corrected. gunlock uses `f3_224a`:
  `set_visarea(46, 365, 31, 254)`, so the 224 visible lines start at line 31
  of a 262-line frame, and `vcnt` is itself the line-RAM index. The old build
  had lines 24..247. The diagnostic page now shows eleven readouts (the
  Phase 1 proofs plus frame count, IRQ acknowledges and per-region write
  counters) and a live dump of all 8192 palette entries.

**Build**: timing MET. Worst setup slack +0.660 ns, clk_sys +3.688 ns,
clk_ram +2.376 ns, all TNS 0.000. 31% ALMs, 39 DSPs.

**BRAM is now the binding constraint: 514 / 553 blocks (93%).** Main RAM is
128 of those and the sprite framebuffer will need ~160, so main RAM has to
move to SDRAM before sprites can be built.

### The video oracle and model (`tools/`)

The F3 makes all 256 scanlines independently configurable for scroll, zoom,
priority, clipping, blending and palette offset. That is too much state to
get right by writing Verilog and looking at a TV, so the chipset is modelled
in software first and checked against MAME's own output.

- `tools/oracle_f3dump.lua` — dumps all seven video RAMs, the playfield
  control registers (captured with a write tap, since 0x660000 is write-only),
  the four gfx ROM regions, and MAME's rendered frame as raw ARGB, all at one
  emulated instant. The snapshot is forced inside the same callback so the
  picture cannot drift a frame from the bytes it belongs to.
- `tools/f3_gfx.py` — decoding for all five gfx layouts.
- `tools/f3_render.py` — port of `read_line_ram`, `get_pf_scroll`,
  `calc_clip`, `mix_line`, `render_line`, `get_sprite_info`, `f3_drawgfx`.
- `tools/f3_regress.py` — renders every dumped frame, fails on any differing
  pixel.

**Result: 15/15 frames pixel-identical to MAME**, across boot, the Taito
logo, the title screen and attract-mode gameplay.

Two findings the RTL has to honour:

1. **Ray Force runs with flipscreen ON.** Its graphics are stored flipped in
   ROM and the program sets the flipscreen bit to display them correctly. Every
   tilemap is mirrored in both axes, the line-RAM index runs backwards
   (255 - screen_y), and `get_pf_scroll` takes its flipscreen branch — whose
   two x adjustments (320<<6 and (512+192)<<6) sum to exactly 65536 and so
   cancel in s16.
2. **Char RAM and pivot RAM are read byte-swapped.** They are big-endian u16
   shares, but `video_start()` hands them to the gfx decoder as
   `reinterpret_cast<u8 *>`, which swaps the two bytes of every word relative
   to the 68020's view. Against the memory image the CPU wrote, pixel 0 is the
   low nibble of byte 3 and pixel 7 the high nibble of byte 0. Getting this
   wrong scrambles pixel pairs inside every character while leaving the text
   correctly positioned on screen — it reads as a font problem, not a byte
   order problem. This is the one bug that cost real time today.

---

### Self-test page and UART debug (new)

A labelled 40x28 pass/fail page instead of a screen of bare hex, and the same
page character-for-character out of the UART. Same idea as the Raiden II core.

- `rtl/rf_selftest.sv` — value/status mux and the pixel renderer. Expected
  values (`00B80000`, `77E1C279`, `D53D7C04`, `00001000`, `10620931`, 64
  acks per 64 frames) are constants in the RTL, so the board says PASS or
  FAIL by itself instead of handing back a number to compare by eye.
- `rtl/rf_selftest_page.sv` — generated by `tools/make_selftest_page.py`;
  static text plus the layout constants both consumers read.
- `rtl/rf_font8x8.sv` — generated by `tools/make_font.py` from a stock
  cp850-8x8 console font, ASCII 0x20-0x5F.
- `rtl/rf_uart_log.sv` — walks rf_selftest's **second character port**, so
  the serial output is the page by construction rather than by two pieces of
  formatting code kept in step. One row per frame; the whole page repeats
  about twice a second, comfortably inside 115200 baud.

OSD options:

```
Service Mode   Off / On                       cabinet TEST switch
Self Test      On / Off                       On = the page, Off = game video
UART Debug     Self Test / Off / Write Ring
```

UART Debug defaults to **Self Test**, i.e. on: the OSD cannot be driven
remotely, and a debug channel that has to be switched on by hand at the
cabinet is not much of a debug channel. `Write Ring` is the Phase 0/1 oracle.
The two producers are muxed onto UART_TXD and the unselected one is held in
reset so the line idles high.

Read it on the board with:

```sh
stty -F /dev/ttyS1 115200 raw -echo
cat /dev/ttyS1
```

Both were verified in Verilator before the build: the rendered page is
pixel-exact against a bitmap computed independently from the two ROMs, and
the decoded serial stream is the page verbatim.

---

## Outstanding

### Hardware result (2026-08-27, board at 172.17.1.164)

The main board runs the game and **every self-test check passes**, read both
off the screen and off the UART:

```
ROM BYTES       00B80000  PASS
ROM CHECKSUM    77E1C279  PASS
SDRAM BIST      D53D7C04  PASS
WRITE COUNT     00001000  PASS
WRITE HASH      10620931  PASS   <- unchanged by the much larger memory map,
                                    which is the point: the first 4096 writes
                                    are boot clear loops that finish long
                                    before the first vblank
FETCH IN RANGE  00000000  PASS
LAST PC         00000AAE          <- the main loop, no longer parked at the
                                     0x4060 vblank wait
FRAME COUNT     00000BA5
IRQ2 ACK/64FRM  00400A2A  PASS   <- 0x40 = 64 acknowledges per 64 frames
IRQ3 ACK/64FRM  00400A2A  PASS
PALETTE         0000FFFF  PASS
PLAYFIELD       0000FFFF  PASS
SPRITE          0000FFFF  PASS
LINE RAM        0000FFFF  PASS
TEXT AND CHAR   0000FFFF  PASS
BUILD           27093739
```

Measured separately from two screenshots 12 s apart: frame_cnt +708,
irq2_cnt +708, irq3_cnt +708 -- 59.0 Hz with the acknowledges exactly in
lockstep, and `frame_cnt - irq2_cnt` a **constant** 380 (380 frames of boot
before the game enables interrupts, then every vblank acknowledged 1:1). The
vector-fetch acknowledge scheme works.

The palette panel (Self Test = Off) fills with the game's real colours and
changes between frames.

**Fit**: timing met, worst setup slack +0.613 ns. 32% ALMs,
**518 / 553 RAM blocks (94%)**.

### Review notes (2026-08-27, end of session)

A pass over everything written today, looking for defects rather than style.
Six found, all fixed and re-verified in Verilator:

- **93C46 READ was missing the dummy bit.** The chip emits a 0 on the clock
  after the last address bit, THEN the 16 data bits. Without it the word
  arrived one bit early and read back rotated. Caught by review, not by
  hardware -- the game boots either way because it rewrites defaults over
  corrupt settings. `make -C sim eeprom` now checks EWEN/WRITE/READ/idle.
- **rf_selftest port B** evaluated the value mux on the unregistered row
  while the field masks used the registered one -- a one-cycle skew that
  rf_uart_log's wait states happened to hide.
- **rf_video_line** spent a 3-cycle read on every subsection whether or not
  anything was latched. Now skipped: mean 151 -> 112 clocks/line.
- **rf_gfx_bus** silently dropped a request arriving while busy. Now has a
  `busy` output and says so on the port; `pix` validity is documented.
- **Diagnostic page** panel frame was drawn from the look-ahead x, one
  pixel left of the panel. Cosmetic; page is superseded by the self-test.
- **IRQ acknowledge limitation named in the RTL**: any data read of
  VBR+0x68/0x6C while an IRQ is pending counts as an ack. That happens once,
  in the boot ROM checksum with interrupts masked, and is where the constant
  380-frame `frame_cnt - irq2_cnt` offset comes from. Not a gameplay issue
  (hardware shows exactly one ack per frame) but it is now written down.

Reviewed and left alone, deliberately: the control-port and EEPROM byte-lane
decode (checked against `f3_control_w` case by case), the read-mux timing
(identical to the validated spike), the BRAM read-during-write modes, and
`f3_render.py`'s s16 wraparound in the sprite axis (matches MAME).

### Known issues carried forward

- ~~UART compare needs manual pass alignment.~~ Fixed: `tools/rf_ring_check.py`
  anchors on a `===` pass header, so the workaround is a script rather than a
  snippet to copy out of this file.
- **prog_bus line cache across re-download.** The loader bypasses prog_bus, so
  its line cache is not invalidated by a download. Only matters if the ROM is
  re-downloaded without a core reset; the menu Reset pulses `bus_reset` and
  clears it.
- **MiSTer_cmd FIFO.** If `/dev/MiSTer_cmd` stops working (deleted inode),
  kill and restart the MiSTer process.

---

## How to run the video oracle

```sh
# dump three consecutive frames (sprite_lag is 2, so a frame can only be
# reproduced when its two predecessors were dumped too), plus the gfx regions
F3DUMP_REGIONS=1 F3DUMP_FRAMES=1798,1799,1800 F3DUMP_DIR=dump \
  mame rayforce -rompath . -video none -sound none -nothrottle -norotate \
       -autoboot_script tools/oracle_f3dump.lua -seconds_to_run 32

python3 tools/f3_render.py dump 1800 --compare   # one frame
python3 tools/f3_regress.py dump                 # every dumped frame

F3_ONLY=pv python3 tools/f3_render.py dump 1800  # render one layer only --
                                                 # how a partially built RTL
                                                 # renderer gets compared
```

Use the system `python3` (it has numpy and PIL); the `.venv` is only for
paramiko.

---

## How to build

```sh
cd /storage01/code/c_things/raiden-mister/Arcade-rayforce_MiSTer
./build.sh
```

## How to deploy

```sh
./build.sh                                  # writes output_files/Rayforce.rbf
.venv/bin/python3 tools/rf_deploy.py        # upload, load_core, screenshot
```

The board is **172.17.1.164**. Plain `ssh` key auth fails on it -- the tools
use paramiko with the password, which works. The MRA's `<rbf>Rayforce</rbf>`
matches any `cores/Rayforce*.rbf` and MiSTer takes the last by name, so the
upload is timestamped and sorts newest-last.

## How to validate

Everything the old hex page reported is now on the self-test page, labelled,
with the expected values checked in RTL. Read it either way:

```sh
.venv/bin/python3 tools/rf_deploy.py         # screenshot -> screenshots/
.venv/bin/python3 tools/rf_uart.py -t 10     # the same page over the UART
```

A good run looks like:

```
ROM BYTES       00B80000  PASS
ROM CHECKSUM    77E1C279  PASS
SDRAM BIST      D53D7C04  PASS
WRITE COUNT     00001000  PASS
WRITE HASH      10620931  PASS
FETCH IN RANGE  00000000  PASS
LAST PC         0000064C
FRAME COUNT     0000xxxx
IRQ2 ACK/64FRM  0040xxxx  PASS     <- the 0040 is the acknowledge RATE: 64
IRQ3 ACK/64FRM  0040xxxx  PASS        acks per 64 frames, i.e. exactly one
PALETTE         0000FFFF  PASS        per frame. A raw counter cannot tell
PLAYFIELD       0000xxxx  PASS        that apart from double-acknowledging
SPRITE          0000FFFF  PASS        half the frames.
LINE RAM        0000FFFF  PASS
TEXT AND CHAR   0000xxxx  PASS
BUILD           ddhhmmss           <- ddhhmmss of the compile. If this is not
                                      the build you just made, the board is
                                      running a stale core.
```

`WAIT` means a check has not started, `BUSY` means it is in progress (the ROM
download, or the CPU still working through the boot writes). Anything still
`BUSY` a few seconds after load is a real failure.

### Write-stream oracle (Phase 0/1)

Set **UART Debug** to `Write Ring` in the OSD, capture, and compare against
MAME's `rf_acc.tr`. `rf_write_compare.py` compares from the first parsed op
and a capture almost always starts mid-pass, so anchor at a `===` header:

```sh
.venv/bin/python3 tools/rf_uart.py -t 12 -o rf_uart.log
.venv/bin/python3 tools/rf_ring_check.py rf_uart.log
```

## How to screenshot

```sh
# On the MiSTer: echo "screenshot" > /dev/MiSTer_cmd
# then pull /media/fat/screenshots/rayforce/*.png
```
