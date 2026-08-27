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

**BRAM is now the binding constraint: 518 / 553 blocks (94%).** Main RAM alone
is 128 blocks. The sprite framebuffer below needs ~160. Main RAM has to move
to SDRAM before sprites can be built.

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

**Sub-tasks**
- [ ] Move main RAM to SDRAM to free 128 BRAM blocks
- [ ] Tilemap gfx fetch from SDRAM (ch1/ch2) with the 4bpp + 2bpp plane pair
- [ ] `rf_video_line.sv`, `rf_video_pf.sv`, `rf_video_mix.sv` — playfields first
- [ ] `rf_video_pivot.sv` — text/pixel layer (no SDRAM needed, both RAMs are BRAM)
- [ ] `rf_video_spr.sv` — sprites and the framebuffer
- [ ] Verilator bench: load a VRAM dump, render, diff against the same frame
      the Python model is checked against

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
