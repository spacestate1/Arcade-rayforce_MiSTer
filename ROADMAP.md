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
   **None of rf_gfx_bus / rf_video_line / rf_video_pf / rf_video_mix has
   been through Quartus yet** -- they are in the QSF but not instantiated in
   Rayforce.sv. Wire the pipeline in (a raster-driven controller that
   decodes line N+1, builds N+1 and mixes N against the beam) and build
   BEFORE adding pivot and sprites, so that whatever Quartus 17 objects to
   in the new code -- packed structs, generate stages, signed arithmetic --
   is found while the pile is small. That build also re-measures the
   per-line cost against the real SDRAM controller.

3. - [ ] `rf_video_pivot.sv` -- text/pixel layer. Needs no SDRAM at all;
         char RAM and pivot RAM are already BRAM with a port B waiting.
4. - [~] Verilator bench -- `sim/`, started. `make -C sim gfx` covers the
         tile fetch; extend it to load a VRAM dump into the renderer and diff
         whole frames against the model. `F3_ONLY=` in f3_render.py renders a
         matching layer subset, so a half-built renderer can be compared
         before it is finished.
5. - [ ] `rf_video_spr.sv` -- per-line bucket pre-pass, active set, line
         buffer. No framebuffer: see the measurement below.

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

**Hardware**

| Chip | Function | MAME source |
|---|---|---|
| `68000` | Audio CPU | `taito_en.cpp` |
| `ES5505` | Sample playback | `es5506.cpp` |
| `ES5510` | DSP (reverb/chorus) | `es5510.cpp` |
| `MB87078` | Volume control | `taito_en.cpp` |
| `MB8421` | Dual-port RAM | `taito_en.cpp` |

**Sub-tasks**
- [ ] `rf_audio_68000.sv` — audio CPU (second TG68K instance)
- [ ] `rf_es5505.sv` — sampler (faithful implementation)
- [ ] `rf_es5510.sv` — DSP stub first (dry pass-through), then real
- [ ] `rf_mb87078.sv` — volume control
- [ ] `rf_taito_en.sv` — sound board glue

**Exit criteria**
- [ ] Music plays (ES5505 samples)
- [ ] Sound effects play
- [ ] ES5510 stub doesn't break audio (dry pass-through)

---

## Phase 4: Integration & Polish

**Hardware**
- [ ] Full memory map decode (`rf_main.sv`)
- [ ] Interrupt controller (vblank, timer)
- [ ] Input handling (joystick, buttons)
- [ ] NVRAM (EEPROM save/load)

**Software**
- [ ] Update MRA for all region variants (gunlock, rayforce, rayforcej)
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
