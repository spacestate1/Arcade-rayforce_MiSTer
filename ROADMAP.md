# Ray Force / Gunlock (Taito F3) — Implementation Roadmap

**Status**: Phase 2 in progress. The real F3 main board (rf_main.sv) replaces
the CPU spike and builds with timing met; the video chipset is modelled in
Python and reproduces MAME's frames pixel-for-pixel.
**Goal**: Full playable Ray Force / Gunlock on MiSTer, matching MAME 0.288 behaviour.

---

## Phase 0: Skeleton & CPU Validation (complete)

**Done**
- MRA → HPS → ioctl download path proven (checksum on screen)
- F3 video timing: 320×224 visible, 432×262 total, ~58.94 Hz
- TG68K.C 020-mode spike running the real boot ROM
- Explicit BRAMs (fixes Quartus inference crash)
- Write-stream capture + UART dump
- **Write hash `0x10620931` matches MAME's `rf_acc.tr` exactly**

**Exit criteria**
- [x] Write-stream hash matches MAME's `rf_acc.tr` for first 4096 writes
- [x] Deployed to MiSTer, screen shows expected values
- [~] Build passes timing (slack -1.683 ns — known issue, design works on hardware)

---

## Phase 1: SDRAM Integration (complete, 2026-08-25)

**Hardware**
- [x] SDRAM controller (`rf_sdram.sv` instantiated, ch3 active, ch1/2/4 parked)
- [x] `rf_prog_bus.sv` integrated (line cache + wait-state engine in the spike);
      download via direct loader FSM (prog_bus FIFO bypassed — dead during
      real streams on Propcycle)
- [x] PLL: `clk_ram` 97.12 MHz + `clk_sys` 53.42 MHz off one 1068 MHz VCO
- [x] SDC: async clock groups + TG68K kernel multicycle — **timing passes**
      (worst slack +0.298 ns, was −1.683 ns)

**Memory map (SDRAM offsets, from MRA)**
```
0x000000  maincpu   1 MB    4-way byte interleave
0x100000  audiocpu  512 KB  16-bit interleave
0x180000  sprites   2 MB    16-bit interleave
0x380000  sprites_hi 1 MB
0x480000  tilemap   2 MB    LOAD32_WORD pair
0x680000  tilemap_hi 1 MB
0x780000  ensoniq   4 MB    2x 2 MB
```

**Software**
- [x] `tools/rf_stream_sum.py` prints the expected 1 MB readback-BIST sum
- [ ] `tools/rf_write_compare.py` pass-alignment (workaround documented in
      HANDOFF.md — anchor at a `===` header)

**Exit criteria**
- [x] ROM loads into SDRAM, checksum matches (1 MB BIST `0xD53D7C04` ✅)
- [x] CPU fetches from SDRAM (line cache serves the whole boot window;
      write hash `0x10620931` ✅, UART ring IDENTICAL for 4096 ops ✅)
- [x] Full maincpu region (past 0x40000) verified — via the 1 MB BIST; the
      spike itself parks at ~0x4060 waiting for a vblank IRQ (IPL tied off)

---

## Phase 2: Video Chips

### 2a: Real main board (RTL complete, hardware validation pending)

The gate nobody can skip: with the spike's fake memory map the boot code ran
to its vblank wait at ~0x4060 and stopped, so no video RAM ever held real
data. Nothing in the pixel pipeline can be developed, let alone diffed against
MAME, until the program is running its frame loop.

- [x] `rtl/rf_main.sv` — the full taito_f3.cpp map: 128 KB main RAM, 32 KB
      palette, 64 KB sprite RAM, 48 KB playfield RAM, 8 KB text, 8 KB char,
      64 KB line RAM, 64 KB pivot RAM, 2 KB sound dual-port RAM, video
      control at 0x660000, control port at 0x4A0000
- [x] Interrupts: level 2 on vblank, level 3 at 10000 68020 cycles (625 us)
      after it. Both autovectored; the handler fetch at VBR+0x68 / VBR+0x6C is
      used as the acknowledge, since TG68K.C exposes no IACK strobe
- [x] `rtl/rf_eeprom_93c46.sv` — the settings EEPROM, so the boot path that
      reads it cannot mislead later debugging
- [x] Inputs wired (2 players, start/coin/service, Service Mode OSD toggle)
- [x] Raster timing corrected to the f3_224a visarea: 224 lines starting at
      line 31 of a 262-line frame, with vcnt as the line-RAM index
- [x] Builds, timing MET (worst setup slack +0.61 ns); 518/553 RAM blocks
- [x] **Hardware validated** on the DE10-Nano (172.17.1.164): every Phase 1
      proof still passes, write hash unchanged at `10620931`, frame counter
      at 59.0 Hz with IRQ2 and IRQ3 acknowledged exactly once per frame, all
      video-RAM write counters saturated, palette panel showing the game's
      real colours
- [x] Self-test page (`rf_selftest.sv`) with the same page streamed over the
      UART (`rf_uart_log.sv`), both OSD-selectable; all 15 checks PASS on
      hardware, verified on screen and over /dev/ttyS1

**BRAM is now the binding constraint: 518 / 553 blocks (94%).** That is a
*sprite* problem, not a playfield one -- see 2c. The playfield, pivot and
mixer path needs line buffers (~10-15 blocks), which fits in what is free.

### 2b: Video model (complete)

Before writing renderer RTL, the chipset is modelled in Python and checked
against MAME's own output. The F3 makes all 256 scanlines independently
configurable for scroll, zoom, priority, clipping, blending and palette
offset; that is too much state to get right by writing Verilog and looking at
a TV.

- [x] `tools/oracle_f3dump.lua` — dumps all seven video RAMs, the playfield
      control registers, the four gfx ROM regions and MAME's rendered frame,
      all at one emulated instant
- [x] `tools/f3_gfx.py` — tile decoding for all five gfx layouts
- [x] `tools/f3_render.py` — port of read_line_ram, get_pf_scroll, calc_clip,
      mix_line, render_line, get_sprite_info, f3_drawgfx
- [x] `tools/f3_regress.py` — renders every dumped frame and fails on any
      pixel that differs
- [x] **15/15 frames pixel-identical to MAME** across boot, Taito logo, title
      and attract gameplay

Two findings the RTL has to honour:

1. **Ray Force runs with flipscreen ON.** Its graphics are stored flipped in
   ROM and the program sets the flipscreen bit to display them correctly, so
   every tilemap is mirrored in both axes and the line-RAM index runs
   backwards (255 - screen_y).
2. **Char RAM and pivot RAM are read byte-swapped.** They are big-endian u16
   shares, but the gfx decoder takes `reinterpret_cast<u8 *>` of them, so the
   two bytes of every word swap relative to the CPU's view. Against the
   memory image the CPU wrote, pixel 0 is the low nibble of byte 3 and pixel 7
   the high nibble of byte 0. Getting this wrong scrambles pixel pairs inside
   every character while leaving the text correctly positioned — it reads as
   a font problem, not a byte-order problem.

### 2c: Renderer RTL (next)

| Block | Function | Reference |
|---|---|---|
| `rf_video_line.sv` | line RAM decode, one line ahead of the raster | `read_line_ram` in f3_render.py |
| `rf_video_pf.sv` | 4 playfields: scroll, rowscroll, colscroll, zoom | `PlayfieldInf` |
| `rf_video_pivot.sv` | text/pixel layer from char + pivot RAM | `PivotInf` |
| `rf_video_mix.sv` | priority sort, clipping, the blending circuit | `mix_line` / `render_line` |
| `rf_video_spr.sv` | sprite list walk + framebuffer | `SpriteEngine` |

**Sub-tasks, in order**

1. - [x] SDRAM gfx **read** path -- `rtl/rf_gfx_bus.sv`. One 16-pixel 6bpp
         tile row per request, both planes fetched in parallel on two
         channels (the board reads them in parallel too; MAME's tile_decode
         merge pass is an emulator convenience, not hardware). A row of low
         data is exactly one aligned 4-word burst, so nothing is discarded.
         CDC copied from `rf_prog_bus`, which is proven on hardware.
         **584/584 tile rows verified in Verilator against `f3_gfx.py`**
         (`make -C sim gfx`), including 200 pseudo-random codes across the
         whole 16384-tile space. 11-12 cpu clocks per fetch, so a full line
         of four playfields costs ~1000 of the 3456 clocks available.
2. - [~] The big one, split three ways:
     - [x] `rf_video_line.sv` -- the per-scanline effect decoder. Walks the
           eight line-set sections and their subsections, honouring the latch
           semantics (a value not re-latched on a line keeps the previous
           line's, which is how a game sets one zoom for a whole playfield).
           **30/30 dumped frames, 7680 lines, byte-identical to the model**
           (`make -C sim line-all`). Mean 112 / worst 151 clocks per line of the
           3456 available.
     - [x] `rf_video_pf.sv` -- the four playfields, one line at a time:
           scroll, row scroll, column scroll, x/y zoom, flipscreen, per-tile
           flips, the 6bpp pen mask, MAME's row-usage skip (a row of all-0
           codes draws nothing even though tile 0 is opaque -- a visible
           behaviour, reproduced), and mosaic sample-and-hold on the read
           side. Source-indexed 512-entry line buffers, double-banked, read
           by an x_scale accumulator so the mixer sees all four playfields
           per pixel with no multiply.
           **30/30 dumped frames, every compared pixel identical to the
           model** (`make -C sim pf-all`), plus mosaic forced on (`pf-mosaic`)
           because Ray Force never uses it. Decode+build: mean ~1700-2000 /
           worst 2315 clocks per line of 3456, against a behavioural SDRAM
           with ~8 cpu-clock latency -- real controller latency will be
           higher, so this is the number to re-measure on hardware.
     - [x] `rf_video_mix.sv` -- priority sort, clipping, the blending
           circuit. Nine layers (4 playfields, 4 sprite groups, pivot)
           stable-sorted by priority per line from MAME's base order -- the
           tie order matters, Ray Force has equal-priority layers on most
           lines -- then a nine-stage pipeline, one layer per stage, one
           pixel per four clocks (the palette port is 16-bit and an RGB pair
           is four reads). Latches its own copy of the line decode at line
           start. **END TO END: 15/15 frames, 1,075,200 visible pixels
           identical to MAME** through real line decode + playfield build +
           SDRAM tile fetch + mixer (`make -C sim mix-all`), with sprites and
           pivot fed from the model as stand-ins for their unbuilt RTL.
           1307 clocks per line, concurrent with the next line's build.
           Clip planes: implemented per pixel, equal to MAME for any single
           plane and all-normal combinations; MAME's duplicate-range quirk
           for several inverted planes is not reproduced. Ray Force never
           enables a clip plane, so that path has NO dump coverage.
   - [x] `rf_video_pipe.sv` -- the raster-driven controller: decodes and
         builds line T+2, mixes T+1, while the beam reads T out of a
         double-banked output buffer. Through Quartus and on the board with
         every self-test counter passing (longest real SDRAM fetch 23
         clocks, longest build 2458 of 3456) -- but the game video is still
         black; see HANDOFF.md "Second session" for the instrumented build
         that localises it.

3. - [x] `rf_video_pivot.sv` -- text/pixel layer (2026-08-27). One line at
         a time on its own three RAM ports (text, char, pivot), concurrent
         with the playfield build: a 64-word text-row usage scan, then one
         pixel per clock through a text-RAM -> char/pivot-RAM pipeline into a
         double-banked line buffer the mixer reads at smp_x. Both sources
         (the 512x512 VRAM tilemap and the 512x256 pixel bitmap with its
         borrowed-palette hack), flipscreen, per-tile flips, scroll, mosaic.
         **15/15 dumped frames pixel-identical to the model through the
         whole pipe** (`make -C sim pipe-all`). Coverage caveat: every
         dumped frame uses the VRAM mode with mosaic off; the pixel-layer
         and mosaic paths follow the model but have no dump exercising them.
         ~390 clocks per line.
4. - [~] Verilator bench -- `sim/`, started. `make -C sim gfx` covers the
         tile fetch; extend it to load a VRAM dump into the renderer and diff
         whole frames against the model. `F3_ONLY=` in f3_render.py renders a
         matching layer subset, so a half-built renderer can be compared
         before it is finished.
5. - [~] Sprites, split into verified stages like the playfields were:
     - [x] `rf_video_spr_list.sv` -- the list walker (get_sprite_info): the
           Axis position/zoom state machine, bank switch, jump, multi-block
           and per-axis scroll globals. Streams the drawable sprite list.
           **Every dumped frame's list is byte-identical to the model**
           (`make -C sim spr-all`), including the 198-sprite busy frame.
     - [x] `rf_spr_gfx_bus.sv` -- sprite tile-row fetch. Same two-plane,
           one-row-per-request shape as rf_gfx_bus; the only changes are the
           region bases (sprites 0x180000, sprites_hi 0x380000) and the
           sprite_hi bit packing (bit4/bit5 stored as adjacent pairs).
           **584/584 rows byte-identical to the decoder** (`make -C sim
           spr-gfx`), 11-12 cpu clocks per fetch.
     - [x] `rf_video_spr.sv` -- the per-line builder (2026-08-27). Vblank
           prepass walks the list and EXPANDS each sprite over the screen
           lines it covers (dy8 accumulator), bucketing per-line row-records;
           per line it walks the bucket, fetches each sprite row and lays it
           down with the dx8 accumulator (x zoom + dedup, flipx, pen mask,
           colour base) into a double-banked, tag-per-pixel line buffer the
           mixer samples. Zoom-correct including the vertical overlay (several
           source rows crushed onto one line combine write-if-empty).
           **Every dumped frame's line buffer + row-usage is pixel-identical
           to the model's framebuffer** (`make -C sim spr-line-all`), through
           the 198-sprite frame 3000. Two truncation bugs found by the bench
           (a 12-bit record-count limit that compared as < 0, like the
           walker's) and one real algorithm bug (the vertical-overlay dedup).
     - [x] Wired into `rf_video_pipe` and verified end to end: prepass into
           a double-banked bucket store (1-frame lag), fetch-pipelined draw
           (prefetch the next record's row while drawing the current, needed
           to fit ~114 sprite-rows/line inside the clock budget), mixer fed
           sp_color/sp_used. **`make -C sim pipe-all`: every frame 71680/71680
           identical to the model through playfields + pivot + sprites.**
       Remaining for sprites (all hardware-integration, no new pixel logic):
       Rayforce.sv wiring (sprite RAM port + the two gfx planes sharing the
       one free SDRAM channel), the BRAM-fit decision, then a build.

**The sprite framebuffer question -- answered by measurement**

MAME keeps a full-screen sprite framebuffer because the F3 supports sprite
trails (don't clear it between frames). That is ~160 BRAM blocks, which the
DE10-Nano does not have spare, and it is the only reason main RAM ever looked
like it had to move to SDRAM.

`tools/oracle_f3trails.lua` walks the sprite list the same way
get_sprite_info() does -- following bank switches and jump commands -- once
per frame, over 8842 frames of attract:

```
frames with trails    : 0
command words ever set: 2100, 2101   (differ only in the bank bit)
sprite list entries   : up to 812 per frame
extra planes          : 1  (5bpp)
banks                 : both, alternating every frame
```

Ray Force issues exactly two sprite command words for its entire run and the
trails bit (word 5 bit 1) is never among them. And from the VRAM dumps:

```
sprites actually drawn : up to 230 per frame (mean 54)
MAX SPRITES ON ONE LINE: 43
```

So the framebuffer is write-once/read-once-per-line, and the per-line load is
in the tens. The intended design is therefore **no framebuffer at all**:

- one pre-pass per frame over the 812 list entries (~6.5k clocks, and vblank
  is ~103k) building a per-line "sprites starting here" bucket. A sprite
  starts on exactly one line, so this is a linked list -- head per line plus
  one next-pointer per sprite, a couple of blocks -- not a per-line array.
- an active set maintained incrementally as the raster advances, drawn into a
  double-buffered sprite line buffer.
- 43 sprites x 16 px = ~700 pixel writes per line against 3456 clocks, so
  there is roughly 5x headroom even if gameplay is far busier than attract.

Estimated cost ~15-20 blocks against the 35 free, so **sprites need neither a
framebuffer nor SDRAM nor the main-RAM migration**.

Two things to get right when building it:

- **Draw order is priority.** draw_sprites walks the list backwards and
  writes only where the buffer is still empty, so later list entries win. An
  active set ordered by start line does NOT preserve that -- keep the list
  index and order the draw by it.
- 43/line is attract mode. The design above has no hard per-line cap, only a
  time budget, so a busier scene degrades into timing headroom rather than
  dropped sprites. Keep it that way.

**SDRAM channels are spoken for.** ch1/ch2 carry the two tile planes, ch3 is
the CPU. Sprites also need two planes (sprites + sprites_hi) and only ch4 is
left, so sprites either take both fetches sequentially on ch4 or share
ch1/ch2 with the tiles under an arbiter (tiles build during one part of the
line, sprites another). Decide when building rf_video_spr; the tile budget
above leaves ~1100 clocks a line unspoken for.

**Exit criteria**
- [ ] The Verilator bench matches the model (and therefore MAME) on all
      regression frames
- [ ] Title screen and attract mode correct on hardware

---

## Phase 3: Sound

**Hardware** (taito_en.cpp -- the Ensoniq "EN" sound board, shared by every F3 game)

| Chip | Function | Clock | MAME source |
|---|---|---|---|
| `68000` | Audio CPU | 30.47618 / 2 = 15.238 MHz | `taito_en.cpp` (map at `en_sound_map`) |
| `ES5505` | 32-voice sampler, 4 outputs, 16-bit samples from 4 MB ROM | 15.238 MHz; output rate 30.47618 MHz / (2·16·32) = 29.76 kHz | `es5506.cpp` (2134 lines; the 5505 half) |
| `ES5510` | DSP (reverb/chorus), external delay DRAM | 10 MHz | `es5510.cpp` (1288 lines) |
| `MC68681` | DUART -- only its timer matters: it is the sound CPU's periodic interrupt (vector read at 0xFFFFFD) | 4 MHz | `taito_en.cpp` |
| `MB87078` | Volume control, gain table on the ES5505 outputs | -- | `taito_en.cpp` |
| `MB8421` | 2 KB dual-port RAM to the main 68020 | -- | already in `rf_main.sv` (`sel_dpram`, C00000-C007FF) |

**Sound 68000 memory map** (`en_sound_map`)

```
000000-00FFFF  RAM 64 KB ("osram"), mirrored x4 and again at FF0000
140000-140FFF  MB8421 dual-port RAM, high byte lane
200000-20001F  ES5505 registers
260000-2601FF  ES5510 host port, low byte lane
280000-28001F  MC68681 DUART, low byte lane
300000-30003F  ES5505 sample bank select
340000-340003  MB87078 volume, high byte lane
C00000-C1FFFF  ROM bank 1  \
C20000-C3FFFF  ROM bank 2   } 512 KB audiocpu ROM (d66-22/23), banked
C40000-C7FFFF  ROM bank 3  /  (bank 1 is switched by the main CPU at 300000
                               on Kirameki only; fixed on Ray Force)
FFFFFD         DUART interrupt vector
```

The main CPU side is already there: the dual-port RAM at C00000, the sound
reset pair at C80000/C80100 (asserted at boot -- the sound CPU starts held
in reset and the game releases it), the bank register at 300000 (ignored:
Ray Force does not bank).

**Everything the board needs is already in SDRAM.** The MRA streams the
audio CPU ROM at 0x100000 (512 KB, right after the 1 MB maincpu) and the
Ensoniq samples at 0x780000 (2 x 2 MB, plain); ROM BYTES 00B80000 on the
self-test page is the whole 11.5 MB image including them. Sample format:
MAME loads each ROM `LOAD16_BYTE` into an erased 8 MB big-endian region, so
the ES5505 sees 16-bit words whose HIGH byte is the ROM byte and whose low
byte is 0 -- 8-bit samples, word i = SDRAM byte 0x780000 + i (d66-01 for
i < 2M, d66-02 after). Each voice has its own 2-bit bank register
(0x300000 + 2v, `<< 20` words), so sample word address = bank << 20 | the
20-bit accumulator integer.

**Stage 0 numbers (attract mode, 60 s):** 2,535 ES5505 register writes per
frame (the driver refreshes every voice continuously), ~130 MB87078 volume
writes per frame, DUART/ES5510 traffic small; `dump/en_writes.txt` (frame,
tag, address, data, lanes, machine time) and `dump/en_mix.wav` (48 kHz
stereo, MAME's mix) are the references.

**The two walls, stated up front**

1. *BRAM.* The sound CPU's 64 KB RAM is 52 M10Ks and the video build has
   ~17 free. **Measured (Stage 0, 2026-08-27):** the sound program's
   working set after boot is ~16.6 KB in 11 scattered ranges (65 of 256
   pages read), so a plain smaller RAM does not fit it either. **Resolved
   another way: pivot RAM.** The 64 KB pixel-layer RAM at 630000 is 64
   M10Ks and is all zero in every one of the 30 dumped frames -- Ray Force
   never writes the pixel layer. Shrinking it to a stub (reads return 0,
   plus a write counter on the self-test page so the assumption is checked
   on hardware every run) frees the full 64 KB for the sound RAM with ~29
   blocks to spare. Other F3 games that use the pixel layer would need it
   back; this core is Ray Force's for now.
2. *SDRAM channels.* All four are taken (ch1/ch2 playfields, ch3 CPU, ch4
   sprites). The sound board needs two more streams: the 68000's program
   fetch (a line cache like `rf_prog_bus`) and the ES5505's sample reads --
   32 voices x 29.76 kHz x 2 samples (interpolation) ~ 1.9 M reads/s. Per
   voice the next address is predictable (accumulator + step), so a 4-word
   burst per voice serves several output samples for all but the highest
   pitches; occupancy is ~10-15 %, not a bandwidth problem, but it is a
   channel. Options: add ch5/ch6 to `rf_sdram` (the controller's channel
   logic is regular; the fixed-priority scan just grows), or arbitrate the
   sound CPU onto ch3 with the main CPU and the samples onto ch4 with the
   sprites (`rf_spr_ch_share` already does this shape). Adding channels is
   cleaner; the sprite work showed how sensitive ch4's latency is.

**Stages -- each verified before the next, the way the video was**

- [x] **Stage 0: oracle** (2026-08-27: `oracle_en_dump.lua`, `es5505_model.py`, `es5505_compare.py`; model vs MAME mix correlation 0.95-0.99). Extend `tools/oracle_f3dump.lua` (or a sibling)
      to tap the sound side in MAME: the sound CPU's writes to the ES5505
      (`0x200000-1F`), the bank and volume registers, as a stream with
      frame stamps -- the same write-stream idea that proved the 68020 in
      Phase 1 -- plus MAME's mixed output (`-wavwrite`) for the end-to-end
      check, and a footprint map of the 64 KB sound RAM (which pages are
      ever touched). Port `generate_samples()` for the ES5505 to Python
      (`tools/es5505_model.py`) and prove it against the wav, so the RTL
      has an exact model to diff against, as `f3_render.py` was for video.
- [x] **Stage 1 done (2026-08-28, build 27230527/28001753: 1387 chip writes identical to MAME from reset, 1775-long identical run in the steady state). `rf_sound_main.sv`** -- second TG68K.C in 68000 mode, the
      map above, ROM through a `rf_prog_bus` line cache, the sound RAM per
      the wall-1 decision, the MB8421's other port (bring it out of
      `rf_main`), the DUART reduced to its timer + interrupt vector, the
      reset pair wired from `rf_main`. ES5505/ES5510/MB87078 register
      writes go to a write ring on the UART. **Exit: the register write
      stream matches MAME's** (`rf_ring_check.py`), i.e. the sound program
      runs and talks to the chips it thinks it has.
- [x] **Stage 2 RTL done, integration pending (2026-08-28: sample-exact vs the model over 1.15 M samples). `rf_es5505.sv`** -- 32 voices time-multiplexed on one
      datapath (one voice per clock slot, 32 slots per output sample, as
      the chip does): accumulator/step, loop modes (forward, reverse,
      bidirectional, stop), the transwave/loop-end flags, 4-channel
      output with per-voice left/right volume, volume ramps, the per-voice
      IRQ. Samples over the new SDRAM channel with a per-voice 4-word
      prefetch line. **Exit: sample-exact against `es5505_model.py`** on
      captured register streams (`make -C sim es5505`), then the mixed
      output against MAME's wav within DAC tolerance.
- [x] **Stage 3 written (2026-08-28, in build 28001753; not yet heard). `rf_mb87078.sv`** (a gain table on the four outputs) and
      the **ES5510 stub** (dry pass-through with the host port answering,
      so the driver does not hang on it). **Exit: music and effects on the
      board through AUDIO_L/R** (the framework resamples from 29.76 kHz).
- [ ] **Stage 4: real ES5510** -- only if a game needs it audibly; Ray
      Force uses it for reverb. Its delay memory is external DRAM in
      hardware; here it would be another SDRAM stream.

**Exit criteria**
- [x] Sound program runs: register write stream identical to MAME (Stage 1)
- [x] ES5505 sample-exact against the model (Stage 2)
- [x] Music and sound effects play on the board (2026-08-28, B13 28094310: the Audio Ring capture correlates 1.000 with MAME's mix; by-ear playthrough still pending. B12 was scrambled: the driver reads the ES5505 (its sound table comes out of the sample ROM through O1 reads on a stopped voice) and the RTL answered reads with a constant; B13 adds the read port, exact in the bench incl. all 8001 reads -- see HANDOFF "The sound bug: ES5505 reads")
- [ ] ES5510 stub does not break audio (dry pass-through)

---

## Phase 4: Integration & Polish

**Hardware**
- [ ] Full memory map decode (`rf_main.sv`)
- [ ] Interrupt controller (vblank, timer)
- [ ] Input handling (joystick, buttons)
- [x] NVRAM (EEPROM save/load) -- 2026-08-28 B14: MRA `<nvram index="254" size="128"/>`, load on ioctl 254 after the ROMs, save on ioctl_upload_req when the game writes the 93C46 (F3 has no DIP switches: every setting is in the service menu and this EEPROM)

**Software**
- [x] Update MRA for all region variants (gunlock, rayforce, rayforcej) -- written, Gunlock/Japan not yet loaded on the board
- [ ] Self-test page (port from Raiden II `raiden2_diag/selftest`)
- [ ] UART debug streaming (port from Raiden II)

**Testing**
- [ ] All three region variants boot and play
- [ ] Save/load works
- [ ] Long playtest (30+ minutes) without crashes

**Exit criteria**
- [ ] Game is playable start to finish
- [ ] No visual or audio glitches
- [ ] Save/load works
- [ ] All three region variants work

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| TG68K.C 020 mode broken | Medium | High | Write-stream spike validates it early; fix TG68K.C if needed |
| Line RAM too complex | High | High | Start with simple case; pixel-diff against MAME |
| BRAM overflow | Medium | Medium | Main RAM and pivot RAM in SDRAM; monitor fit report |
| ES5510 too complex | High | Low | Stub it; most F3 games only use it for reverb |
| Timing closure fails | Low | Medium | Different seed; pipeline critical path; reduce clock |

---

## Timeline Estimate

| Phase | Effort | Dependencies |
|---|---|---|
| Phase 0 | 1 week | None |
| Phase 1 (SDRAM) | 1 week | Phase 0 complete |
| Phase 2 (Video) | 4-6 weeks | Phase 1 complete, MAME reference |
| Phase 3 (Sound) | 2-3 weeks | Phase 2 complete |
| Phase 4 (Integration) | 1-2 weeks | Phase 3 complete |

**Total**: ~9-13 weeks to playable.

---

## References

- `RESEARCH.md` — phase-0 research notes
- `reference/mame/taito_f3.cpp` — MAME driver (memory map, init)
- `reference/mame/taito_f3_v.cpp` — MAME video (the big one)
- `reference/mame/es5506.cpp` — ES5505 sampler
- `reference/mame/es5510.cpp` — ES5510 DSP
- `Arcade_propcycle_MiSTer/` — Propcycle core (CPU subsystem, BRAM, SDRAM)
- `Arcade-Raiden2_MiSTer/` — Raiden II core (self-test, UART debug)


---

## Appendix: what a second F3 game would cost (measured 2026-08-28)

**Elevator Action Returns** (`elvactr`, E02) is the obvious candidate -- same
Taito F3 board, and MAME's per-game video config is *identical* to Gunlock's
(`{ EACTION2, extend 1, sprite_lag 2 }`, `taito_f3_v.cpp`). A MAME probe over
2,319 frames (`tools/f3_probe.lua` pattern) says what actually differs:

| Thing | Ray Force | Elevator Action Returns |
|---|---|---|
| Pivot / pixel layer | **never written** (the core stubs it and spends its 64 KB of BRAM on the sound RAM) | **131,072 writes, 98,304 non-zero, all 256 pages** -- fully used |
| Sprite trails | never set | **never set** (so the RTL's omission is fine for both) |
| Video config | extend 1, lag 2 | extend 1, lag 2 -- same |
| Visible raster | `f3_224a`: 224 lines from line 31 | base `f3`: **232 lines from line 24** |
| Orientation | ROT90 (TATE) | **ROT0** (horizontal) |
| maincpu ROM | 1 MB | **2 MB** |
| sprites / sprites_hi | 2 MB / 1 MB | **4 MB / 2 MB** |
| tilemap / tilemap_hi | 2 MB / 1 MB | **4 MB / 2 MB** |
| Ensoniq samples | 4 MB | 4 MB (same layout) |
| Total download | 11.5 MB | **18.5 MB** |

So the work, in order of size:

1. **Restore the pivot/pixel layer.** `rtl/rf_video_pivot.sv` already exists and
   is correct; what is gone is its 64 KB of RAM. Holding both it and the 64 KB
   sound RAM needs 128 KB of BRAM and M10K is at 527/553 (95 %), so one of them
   has to move to SDRAM behind a cache -- or main RAM (128 KB, ~102 M10Ks, the
   single biggest block) does.
2. **Re-map SDRAM for 18.5 MB** and parameterise the region bases that are
   currently constants in `rf_prog_bus`, `rf_gfx_bus`, `rf_spr_gfx_bus` and
   `rf_smp_bus` (e.g. `rf_smp_bus`'s `BASE = 26'h3C0000`).
3. **Parameterise the raster** (224/31 vs 232/24) and the 2 MB program ROM
   decode.
4. **Per-game orientation**: the OSD's rotation default is one value today.

None of it is research -- it is all known work. But it is a Taito F3 *multi-game*
core, which is a different project from a Ray Force core, and step 1 alone is
an architectural change to how the BRAM budget is spent.
