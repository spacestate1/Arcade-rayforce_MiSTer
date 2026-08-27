# RayForce / Gunlock (Taito F3) — phase-0 research

Started 2026-08-09, following the playbook that shipped the Raiden II core:
verify the ROMs first, make MAME the oracle before writing any RTL, model
each chip from the MAME source and diff the RTL against it, and put a
self-test on hardware from day one.

## What is already proven (measured, not assumed)

- `gunlock`, `rayforce`, `rayforcej` romsets all verify **good** against
  MAME 0.288 (`mame -verifyroms`, this machine, 2026-08-09).
- The oracle runs: `mame rayforce` boots headless at 666% speed here, so
  every trace/tap/screenshot technique from the Raiden project is available.
- The set is merged: parent `gunlock`, and each region variant differs by
  exactly one 256 KB program ROM at ic35 (`d66-24` World, `d66-25` US,
  `d66-20` Japan).
- Reference sources fetched from the `mame0288` tag into `reference/mame/`:
  `taito_f3.cpp` (300 KB driver), `taito_f3_v.cpp` (51 KB video),
  `taito_f3.h`, `taito_en.{cpp,h}` (sound board), `es5506.{cpp,h}`
  (ES5505 sampler), `es5510.{cpp,h}` (DSP), `esqpump.cpp`.

## Hardware inventory (from taito_f3.cpp, machine config `f3_224a`)

| part | detail |
|---|---|
| main CPU | **MC68EC020** @ F3_MAIN_CLK (16 MHz), vblank interrupt 2 |
| video | TC0630FDP + TC0650FDA + TC0660FCM customs |
| screen | 26.686 MHz / 4 = 6.6715 MHz pixel clock, **432×262 total, 320×208-224 visible, 58.94 Hz**, ROT90 (TATE) for this game |
| sound | separate board `taito_en`: **68000** + **ES5505** sampler + **ES5510** DSP + MB87078 volume + 2× MB8421 dual-port RAM |
| game init | `init_gunlock`: just `m_game=GUNLOCK; tile_decode();` — **no protection beyond tile decode**. No COP-class chip anywhere. |

## Main CPU memory map (f3_map — it is small)

```
000000-1FFFFF  ROM (1 MB used)
300000-30007F  sound bankswitch w
400000-41FFFF  main RAM 128 KB (mirror +0x20000)
440000-447FFF  palette RAM 32 KB, 24-bit writes
4A0000-4A001F  control r/w
4C0000-4C0003  timer control
600000-60FFFF  sprite RAM 64 KB
610000-61BFFF  playfield RAM 48 KB
61C000-61DFFF  text RAM 8 KB
61E000-61FFFF  char RAM 8 KB
620000-62FFFF  line RAM 64 KB       <- the per-scanline effect engine
630000-63FFFF  pivot RAM 64 KB
660000-66001F  video control
C00000-C007FF  dual-port RAM to sound 68000 (MB8421)
C80000/C80100  sound resets
```

## ROM layout (gunlock, ~10 MB total — SDRAM is not a constraint)

```
maincpu    1 MB   4x 256KB ROM_LOAD32_BYTE (same 4-way interleave as Raiden DX's MRA)
sprites    2 MB   2x 1MB ROM_LOAD16_BYTE  + 1 MB "sprites_hi" plane
tilemap    2 MB   2x 1MB ROM_LOAD32_WORD  + 1 MB "tilemap_hi" plane
audiocpu 512 KB   2x 256KB at offset 0x100000
ensoniq    8 MB   region, 4 MB populated (2x 2MB)
```

## Risk table, hardest first

1. **68EC020 CPU core.** The single make-or-break. No proven open FPGA
   68020 exists: fx68k is 68000-only; TG68K.C claims 020 mode and ships in
   Minimig-AGA but its 020 support is the reason the announced F3 core
   (ika-musume, Dec 2022, unreleased) stalled. Mitigation is the Raiden
   method: run TG68K.C in 020 mode against MAME **instruction-level traces**
   from day one — the oracle finds the broken instructions before the game
   does, and fixing a bounded list of defects in TG68K.C is a very
   different project from writing a 68020.
2. **Line RAM video.** 64 KB of per-scanline control — each line can change
   scroll, priority, alpha, clipping per playfield. taito_f3_v.cpp is 51 KB
   and this is most of it. The good news: it is pure state-in, pixels-out,
   which is exactly what the pixel-diff oracle method is best at.
3. **ES5510 DSP.** Real DSP with downloadable microcode; MAME's own header
   says its emulation "is not perfect". Phase plan: implement the ES5505
   sampler faithfully (it carries all sample playback; scope comparable to
   the YM2151+2xOKI block from Raiden) and **stub the ES5510** (dry signal
   pass-through) first — many F3 games use it only for reverb/chorus.
4. **BRAM budget.** VRAMs sum to ~290 KB + 128 KB main RAM + palette 32 KB.
   Raiden II uses 52% of the DE10-Nano's 690 KB. Main RAM and possibly
   pivot RAM must live in SDRAM; the rest fits. Needs an early paper
   budget before the video design is fixed.
5. **Tile/sprite decode.** `tile_decode()` rearranges GFX at load time —
   the ROM loader must reproduce it (same class of problem as Raiden's
   sprite decryption, much simpler function).

## What is genuinely easier than Raiden II

- No protection chip. The Seibu COP was the Raiden project's main risk;
  F3 has nothing like it.
- One platform, many games: get gunlock running and Elevator Action
  Returns, Puzzle Bobble 2-4, Darius Gaiden etc. are MRA-plus-testing away.
- The merged set means one MRA family with per-region variants.

## Playbook mapping (Raiden step -> F3 step)

| Raiden II step | F3 equivalent | status |
|---|---|---|
| verify romset | done for all three sets | **done** |
| MAME as oracle | mame 0.288 boots rayforce headless | **done** |
| reference sources vendored | reference/mame/ | **done** |
| bus/trace oracles (lua taps) | same technique, 68020 PC/bus traces | next |
| CPU choice + fetch harness | TG68K.C 020 mode vs MAME traces | next |
| chip models from MAME first | TC0630FDP line-RAM renderer in Python | after CPU go/no-go |
| self-test page + UART stream | port raiden2_diag/selftest wholesale | with first RTL |
| SDRAM map + MRA | 4-way interleave known from DX work | with first RTL |

## Immediate next actions

1. **CPU go/no-go spike** (the only question that can kill the project):
   pull TG68K.C, build a Verilator bench that boots the gunlock program
   ROM against a MAME-generated PC trace, and count divergences. Everything
   else waits on this answer.
2. Lua oracle: dump 68020 PC + bus writes per frame (port of
   oracle_copwr.lua technique).
3. Paper BRAM budget for the video chain.

## Phase 0 results (2026-08-25)

**CPU spike: VALIDATED.** TG68K.C in 020 mode runs the real boot ROM and
produces the identical architectural write stream as MAME for the first 4096
writes. The write hash `0x10620931` matches `tools/rf_write_compare.py`
exactly. The project can proceed.

**Build**: the Quartus 17.0 `quartus_map` crash from inferred byte-sliced
arrays is fixed by explicit `altsyncram` instances (the Propcycle `pc_bram`
pattern). The build passes with a timing warning (slack -1.683 ns, Fmax
~49 MHz vs target 53.372 MHz) — the TG68K 020-mode critical path is known
and will be addressed in Phase 1.

**Deployment**: the core loads via `/dev/MiSTer_cmd` and shows the diagnostic
screen on hardware. See `HANDOFF.md` for the build/deploy/validate commands.
```
