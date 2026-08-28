# Ray Force / Gunlock (Taito F3) — Handoff

**Date**: 2026-08-28
**Status**: Phase 2 (video) complete on hardware, sprites included. Phase 3
(sound) stages 0-3 built and on the board: the sound 68000 runs the real
driver (its chip writes match MAME's), the ES5505 is sample-exact against
the model, the volume chip and the mix drive AUDIO_L/R. **Deployed: build 28113056 (B15)**, timing met on every clock
(the first clean one since B7), every self-test row PASS.
**Sound was scrambled on every build up to B12, and the cause is found and
fixed in B13 (2026-08-28 morning, session b2): the driver READS the ES5505
and the RTL answered every read with a constant** -- see "The sound bug:
ES5505 reads" below. B12 (`28084316`) is on the board with every page row
PASS. **B13 (`28094310`, the read port + the analog stick as d-pad) is on
the board: every page row PASS, and its Audio Ring capture correlates
1.000 with MAME's own mix at ratio 1.0 (28.850 s on MAME's timeline) --
the board's sound is MAME's, sample for sample, for the first time.** The story of the night is under "Morning summary" and
"Overnight plan" below; the video work of 2026-08-27 follows after that.

**The board is at 172.17.1.164** (not .175 — that address is dead).

---

## Morning summary (written 2026-08-28 ~00:40, B7 still compiling)

What changed overnight, shortest form. Every step's numbers are in the table
below and the sections after it.

- **Video**: sprites are on hardware and stay there. Two fetches in flight,
  the playfield fetch overlapped with its unpack, a run-ahead ring of four
  sprite line buffers, and the bucket store rebuilt as a counting sort
  holding 8192 rows per frame at the same MLAB cost. Attract mode on the
  board: 0 dropped records, 0 late lines. **The ship-vanishing lead**: the
  4095-row cap (dropping the END of the sprite list = the ship) is gone; the
  `SPR REC : DROP` row will say if boss transitions still exceed 8192.
- **Sound, from nothing to a sample-exact sampler**: the MAME oracle
  (`tools/oracle_en_dump.lua`), an exact Python model of the ES5505
  (`tools/es5505_model.py`, correlation 0.95-0.99 with MAME's own mix), the
  sound 68000 board (`rf_sound_main.sv` -- the real program runs: 1387 chip
  writes identical to MAME from reset, 1775 in a row in the steady state),
  the ES5510's host port (`rf_es5510_host.sv`), the ES5505 in RTL
  (`rf_es5505.sv`, **sample-exact against the model over 1.15 M samples**),
  the MB87078 volume chip, and the audio path to AUDIO_L/R. B6 built it but
  failed timing on a divider of mine; B7 (compiling) has the fixes.
- **BRAM**: the 64 KB sound RAM fits because pivot RAM (the pixel layer,
  which Ray Force only clears) is a stub; the page counts non-zero writes to
  it so the assumption is checked every run.
- **Pause** works (J1 button). **Gunlock / Ray Force (Japan)** MRAs written.
  NVRAM is a design note (needs one MiSTer-side fact, see "Missing parts").

**Board state when you read this**: B8 (`28005854`, also in `builds/`) --
video + sound CPU + sampler + volume chip, timing met on every clock, every
page row PASS; confirmed still running at 01:40 on 08-28. It should be
making sound; no one has listened. B9 (sound-CPU Pause) was stopped
mid-compile; its sources are in the tree, one `./build.sh` away.

**Is sound working? -- what is and is not known.** Known: the driver runs
(1387 chip writes identical to MAME from reset, 1775 in a row later, ~50k
voice writes counted on the page), the sampler is sample-exact against the
model, the mix reaches AUDIO_L/R, timing is met. Not known: the real SDRAM
sample path (ch6) has only the bench's memory model behind it, the output
level is a calculation, and nothing on the page shows audio activity. The
quick objective check is a page row for {sampler overruns, queue drops,
non-zero audio samples per frame} in place of the redundant `IRQ3 ACK` row
-- a 35-minute build -- or an ear at the HDMI output. If B7 failed, the last known-good sprite core is
`Rayforce_27223342.rbf` (B4) and the last sound-CPU core `27230527` (B5),
both in `builds/` (git-ignored); `tools/rf_deploy.py --rbf builds/<file>`.
Put `Rayforce.CFG[0]` back to `08` (page mode) with `.venv/bin/python3
tools/setcfg.py 08` if the UART shows the ring instead of the page. The
ring test is `tools/snd_test.sh <rbf>`.

**To hear it**: the sound is at AUDIO_L/R with the game's own volume
control; nothing on the page proves audio, only the sim does. If it is
silent or wrong, `SND ES WR : RUN` says whether the 68000 is streaming
voice writes, and the ring test (`snd_test.sh <rbf>`) says whether it is
saying what MAME says.

## Overnight plan (2026-08-27 -> 28) -- results are appended to each step as they land

Everything below is verified in Verilator before it is built, deployed to
172.17.1.164 and read back off the self-test page over the UART. Each
bitstream is kept aside as scratch `Rayforce_<stamp>.rbf`; nothing is
committed (no commit was asked for -- the tree is left ready to review).

| # | Step | Verification | Result |
|---|------|--------------|--------|
| B2 | Two sprite fetches in flight, playfield fetch/unpack overlap, 20-bit sprite line buffer | sims 15/15; on the board: SPRLINE, MAXFETCH:BUILD | **27220158, timing met, M10K 533.** Attract mode, 4 samples: SPRLINE max 2473 clocks, 0 missed (B1: 3582 / 2 missed); longest playfield build 1823-2295 (B1: 2467) |
| B3 | Run-ahead sprite ring (NB=4) + `SPR REC : DROP` row (replaces LAST PC) + `SPRLINE : LATE` | sims 15/15, frame 3000 at latency 34 clean; board: LATE = 0 in attract, REC:DROP read | merged into B4 |
| B4 | Ring + counting-sort bucket build (no `rnext`, NREC 8192 at the same MLAB cost) + the two rows + Pause | spr-line-all, pipe-all, pipe-60, pipe-lat; overflow path exercised at NREC=2048 | **27223342, timing met, M10K 536, memory LABs 784.** Attract, 3 samples: records/frame 1294-2272, **0 dropped**; sprite lines **0 late**, longest 2338. Boss transitions need play (see morning note) |
| S0 | Sound oracle: ES5505/bank/volume write stream + wav + sound-RAM footprint from MAME; `es5505_model.py` proven against the wav | model vs wav | **Done.** `tools/oracle_en_dump.lua` (writes with machine time, `dump/en3/`), `tools/es5505_model.py` (exact port of the 5505 paths), `tools/es5505_compare.py`: correlation 0.95-0.99 with MAME's mix in every audible window, lag < 1 ms. Sound RAM working set 16.6 KB scattered; pivot RAM is never written -> its 64 M10Ks become the sound RAM (ROADMAP Phase 3) |
| S1 | `rf_sound_main.sv`: TG68K in 68000 mode, the EN map, the MB8421's other port, the DUART's timer/vector/OPR, ROM via its own prog_bus on new SDRAM ch5, the full 64 KB sound RAM (pivot RAM stubbed with a write counter), chip writes to the shared UART ring (UART Debug = Sound Ring); rows `PIVOT WR:SND PC` and `SND ES WR : RUN` replace WRITE COUNT and FRAME COUNT | No Verilator bench possible (TG68K is VHDL); lint clean with a stub. Board: `tools/rf_snd_ring_check.py` against `dump/en3/en_writes.txt` | **27230527, timing met, M10K 538, ALMs 80 %, LABs 97 %.** The sound 68000 runs the real program: **the first 435 chip writes on the board are identical to MAME's stream from write 0** (the ES5505 init, the DUART setup, the volume chip). It then loops on the ES5510 presence check: the driver stores a value through the DSP's latches (host regs 0x80/0xA0) and reads it back, and the stub only decoded 32 registers, so the select commands overwrote latch 0. A faithful host-port model (`rf_es5510_host.sv`) goes into B6. Page in page mode: `SND ES WR : RUN 62340001` (25,140 ES5505 writes, running -- the driver times out of the DSP check and streams anyway), and `PIVOT WR:SND PC 8000106A` FAIL: **the game clears pivot RAM at boot** (exactly 0x8000 word writes), which the zero stub absorbs; the row counts only non-zero writes from the next build |
| S2 | `rf_es5505.sv`: the sampler, 32 voices time-multiplexed in MAME's 20.9 forms, per-voice 8-sample line caches over new SDRAM ch6 (`rf_smp_bus.sv`); register writes applied at sample boundaries | `make -C sim es5505`: sample-exact against `es5505_model.py` over the capture | **Sample-exact: 1,150,000 samples (38.6 s, 11 s of music), 0 differences, 0 overruns, 43,600 line fetches.** Three bugs the bench found: a 64-deep write queue lost the write that started the first voice (the driver sets a voice up with ~100 writes 0.3 us apart; now 256 deep + a drop counter); the registered voice-file write lost back-to-back writes to one voice (forwarding added); a signed x unsigned product in the interpolation went unsigned (all operands signed now). Plus one bench bug: the sample clock must use MAME's INTEGER rate (15238090 // 512 = 29761 Hz), or the write boundaries drift a sample every ~30 ms. Also exact with the bench's memory latency raised to 60 cycles (the ch6 path will be slower than the bench's 20). Integration into the core is B6 |
| S3 | `rf_mb87078.sv`: the volume chip (mb87077.cpp's latch/gain-index rules, taito_en's L/R mapping, a 66-entry coefficient table folding in MAME's route gains and the 20->16-bit scaling); the ESP stays a dry sum (pump's fake mode) | lint; by ear on the board | *(written; goes into B6 with the sampler)* |
| B6 | Sampler + sample bus on ch6 + sample clock (integer rate, fractional divider of clk_sys) + volume chip -> AUDIO_L/R + `rf_es5510_host.sv` (the DSP's host port done properly, so the driver's presence check passes) | sims (es5505 exact); board: ring check should now run past the DSP init; sound by ear | **27233928: compiled but timing FAILED (-32 ns on clk_sys), ALMs 92 %, LABs 100 %.** Two causes, both mine: a 32-bit divider for the sample rate in Rayforce.sv (the -32 ns path, `active -> es_acc`; now a 32-entry constant table), and the sampler instantiating a multiplier per expression (28 DSPs + ~5000 ALMs; rewritten around ONE shared 34x18 multiplier, 17 cycles per voice, re-verified exact). Its ring test still stood (the ring does not use that path): **1387 writes identical from write 0** (B5: 435 -- the DSP host port passes the presence check) and a **1775-write identical run in the steady state** (from MAME write 127,442); the differences are DUART command-register writes whose order against the 1 kHz timer interrupt is CPU-speed dependent. Rebuilt as B7 with the divider table, the one-multiplier sampler (re-verified exact) and the pivot counter counting non-zero writes only |
| B7 | B6's content with the fixes above | ring test; page; board sound | **28001753: clk_sys +1.1 ns, clk_ram +1.4 ns; ALMs 96 %, LABs 100 %, M10K 538; the framework's HDMI PLL clock misses by 0.26 ns (TNS -2) under that pressure.** Ring: 1387 identical from reset, 1775-long identical run in the steady state. **Every page row PASS**: `PIVOT WR:SND PC 0000xxxx` (no non-zero pivot writes), `SND ES WR : RUN C27A0001` (49,786 voice writes, running), `SPR REC : DROP 0E800000` (3712 records, 0 dropped), `SPRLINE : LATE 061C0000`. **This is the core on the board now, in page mode.** Audio reaches AUDIO_L/R; nobody has heard it yet |
| B9 | The sound CPU honours Pause too (B4's Pause froze the game with the music playing on) | lint | Build `28013233` was stopped from outside ~2 min in (01:34). The sources are promoted (`rtl/rf_sound_main.sv`, `Rayforce.sv` `.pause(paused)` on the sound board), so `./build.sh` produces it; nothing else changed since B8 |
| B10 | Morning report: **sound scrambled, HDMI upside down.** (1) Rotation default flipped to CW (the F3 flipscreen already inverts the raster). (2) A sample-region BIST through the real fetch path (`rf_smp_bus` on ch6: the first 64 KB of d66-01, fold rotl1+add per LE word, expected `B86C4865` from `gunlock.zip`) and the sampler's overrun/queue-drop counters, on the `IRQ3 ACK` row as `SMP BIST:OVR:DR` -- the two hardware-only things the sim could not cover. (3) The sound CPU honours Pause. | page: the new row says whether the sampler is fed the right bytes and keeps up | **28072603 deployed: `SMP BIST:OVR:DR 48650000 PASS`** -- the sample path returns the right bytes (sum B86C4865), 0 overruns, 0 queue drops. clk_sys +2.4, clk_ram +2.0; the HDMI PLL misses by 0.33 ns (fitter variance at 86 % ALMs). So the scrambling is NOT the fetch path or timing; next is recording the audio itself over the UART (B11) |
| B11 | **Audio Ring**: UART Debug's unused "Off" slot becomes "Audio Ring" -- the first 4096 AUDIO_L samples after the sound starts, into the write ring; `tools/rf_audio_ring.py` makes a wav of it and correlates it with the model's output for the same moment. The remote ear. `tools/setcfg.py 18`, load, `rf_uart.py -t 15`, then the tool. | correlation with `dump/en3/model45.wav` | **28080709, timing met everywhere.** First capture: the board's audio at its first non-silent sample is real sampled audio (smooth ~1 kHz oscillation, peak 930 = about -31 dB, i.e. at the game's fade level), but it correlates with NOTHING in the model's 45 s (max 0.15). Either the board plays something MAME never does, or its sound starts after 45 s (the capture window ran to ~80 s after load and a boot without saved EEPROM settings changes the timeline). The ring's index was relative to its own start, so it could not say which. B12 makes the index absolute (samples since the sound CPU's release) and `dump/en4/` extends the reference to 95 s |
| B12 | Audio Ring index absolute (samples since the sound CPU's release); sound CPU honours Pause | page | **28084316: every page row PASS, HDMI PLL -0.042 ns (fitter variance), core clocks +1.7/+1.8 ns.** Deployed 09:22 by session b2 after session 5a was stopped. The full bench suite (12 targets) passes on this tree |
| B13 | **The fix for the scrambled sound: ES5505 register READS** (`rf_es5505.sv` rd_* port, `rf_sound_main.sv` stalls the 68000 until the answer), plus the left analog stick as d-pad (`Rayforce.sv` stick_dirs) | `make -C sim es5505-rw`: 1.15 M samples exact AND all 8001 of the driver's reads answered as MAME does; `make es5505` (en3) still exact; lint | **28094310, GATE PASS (HDMI PLL -0.158 ns, the framework clock's fitter variance again; core clocks +1.35/+1.82 ns), ALMs 87 %. Every page row PASS. Audio Ring: index 803387 (26.99 s after the release), NCC +1.000 at ratio 1.000 against BOTH `model95.wav` and MAME's `en_mix.wav` at 28.850 s -- the board's audio is MAME's.** Capture kept as `dump/en5/audio_ring_b13.log`. The analog stick is untested (no pad on the bench) |
| B8 | Sampler shrunk for margin: the write queue read through one port (an `A_NXT` state instead of a second read port), the record update done field by field instead of rebuilding 313 bits per case arm | `make -C sim es5505` exact (1.15 M samples) | **28005854: TIMING MET on every clock** (HDMI +0.19, clk_ram +1.46, clk_sys +1.96 ns), ALMs 86 % (B7: 96 %), sampler 1805 ALMs (B7: 5381), M10K 539. On the board, every page row PASS (`SND ES WR : RUN C27A0001`, `SPR REC : DROP 0E800000`, `SPRLINE : LATE 06610000`). **This is the core on the board, in page mode, and in `builds/`** |
| B14 | The sprite ghost (per-line span clear + frame-parity tag), NVRAM load/save on ioctl 254, the two sprite rows peak-held | `make -C sim spr-ghost` (frame 3000 then 300: 1280 stale pixels before, 0 after), all 12 benches, `pipe-lat` 0 late lines, lint | **28105535, GATE PASS (HDMI PLL -0.110 ns, the same framework clock; ALMs 88 %). On the board: every row PASS, `SPRLINE : LATE 02B80000` (longest line 696 clocks, 0 late) and `SPR REC : DROP 05B00000` (peak 1456 rows, 0 dropped) -- both now peak-held, so those zeros cover the whole run** |
| B15 | Resource work: the 56-bit debug ring 4096 -> 2048 entries (24 -> 12 M10Ks, M10K being the binding resource at 539/553) and the sprite record store 8192 -> 12288 rows per bank in MLABs, which is what the board's measured 8296-row peak overran | benches; the fit report's M10K and memory-LAB counts | **28113056: `GATE PASS: timing met` -- the FIRST fully clean build since B7. Worst slack +0.048 ns; the HDMI PLL clock that had missed by 0.04-0.16 ns in every build from B10 on is met, which says that miss was fitter congestion, not a real path. M10K 527/553 (was 539), ALMs 88 %, block memory 73 %. On the board: every page row PASS; the audio ring (2048 samples now) correlates +0.992 with `model95.wav` at ratio 1.0** |
| P | Small missing parts: Pause (in B4), gunlock/rayforcej MRAs (written), NVRAM (design note only) | build + board | Pause + MRAs done; NVRAM see "Missing parts" |

### Elevator Action Returns: first boot on the core (2026-08-28, `28133520`)

The core is now a Taito F3 core that loads a second game. Build `28133520`
carries the universal 18.5 MB SDRAM map and the per-game config byte, timing
met (+0.219 ns), and **Ray Force still passes all 21 self-test rows on it** --
including `ROM BYTES 01280000` (the padded total) and the unchanged
`ROM CHECKSUM 77E1C279`, which is the regression that mattered.

`releases/Elevator Action Returns.mra` loads on it. What the board says:

| Row | Value | Meaning |
|---|---|---|
| ROM BYTES | `01280000` PASS | the download is exactly the universal map |
| ROM CHECKSUM | `D041363D` PASS | **byte-perfect** -- matches `tools/rf_stream_sum.py` computed offline from the MRA |
| SDRAM BIST | `399D4BCA` PASS | the 68020's program ROM reads back correctly through the SDRAM path |
| SMP BIST | `F5D3....` PASS | the sample ROM fetch path returns the right bytes (`52DDF5D3` low half) |
| PLAYFIELD / SPRITE / LINE RAM / TEXT | PASS | the CPU is executing and writing video RAM |
| **IRQ2 ACK/64FRM** | `00000000` **FAIL** | **no vblank interrupt is ever acknowledged** |
| FETCH : PIX NZ, TILE NZ | 0 FAIL | so nothing is being rendered |
| SND ES WR : RUN | WAIT | the sound CPU is never released, which follows |
| PIVOT WR | `0001....` FAIL | exactly **one** non-zero pivot write -- the same single transient longword MAME shows, so the stub is behaving as measured |

So the loading half is done and proven, and the game is stuck before it
starts drawing. Everything the ROMs can prove about themselves passes; what
fails is all downstream of the CPU never taking IRQ2.

**The CPU is not the problem -- that is now measured, not assumed.**
`tools/oracle_f3writes.lua` (new: the Phase 0/1 write-stream oracle, for any
F3 game, emitting the same `WR addr data szN` lines `rf_write_compare.py`
parses) was validated by reproducing Ray Force's known hash `0x10620931`
exactly, first lines matching the original `rf_acc.tr`. Run on `elvactr` it
gives **`0x93368F3C` -- precisely what the board reports**. So the 68020 in
this core executes Elevator Action Returns' first 4096 bus writes exactly as
MAME does, and that row is now a real expectation rather than report-only.

What is left is downstream of that: no IRQ2 acknowledge ever happens. Note
that MAME's `f3_timer_control_w` (0x4C0000, where this game writes 0x278B
and Ray Force writes 0) is an explicit TODO in MAME too -- "several games
configure timer-based pseudo-hblank int5 here at POST" -- and MAME runs the
game without it, so that register is not the cause either.

**Where it actually stops (measured 2026-08-28, build `28142635`).** The
game's POST is a byte-by-byte RAM test: for every byte address it writes
FF, AA, 55, 00 and kicks the watchdog (0x4A0000) between each, so eight bus
writes per byte. MAME walks it from 0x400000 straight through 0x401D49 and
beyond without pausing.

The board gets to byte **0x4001FD and stops writing altogether**. Two ring
captures six seconds apart hold the *identical* 1025 distinct operations --
not a loop cycling through them again, the ring simply stops advancing --
so the CPU is spinning somewhere that performs no writes, i.e. on a read.
That is about 4,100 bus writes in, which is why the WRITE HASH row (frozen
at 4,096) still matches MAME: the divergence happens just past the end of
what that row can see.

Nothing is special about that address in MAME's stream -- it writes
0x4001FE, 0x4001FF, 0x400200 and carries on -- so the boundary is ours, not
the game's. Note also that MAME has issued **no** sound-reset (0xC80000) and
**no** dual-port RAM writes by this point, so the sound board is not what it
is waiting for.

Two hypotheses were tested and eliminated: the timer-control register
0x4C0000 (MAME ignores it too and runs the game), and non-deterministic
mixed-port read-during-write on the BRAMs (changed to OLD_DATA in
`28142635` -- kept, since it is strictly safer, but the symptoms did not
move at all).

**Answered (build `28150713`, timing met +0.114): the game's own POST
rejected our RAM.** The new `TRAP : MAIN PC` row reads `0001032C`, trap
flag 0. Disassembling the reconstructed program ROM there:

```
0102A0:  MOVE.B D1,(A0) / MOVE.B (A0),D2 / CMP.B D1,D2 / BEQ ok    byte pass
0102D0:  MOVE.W D1,(A0) / MOVE.W (A0),D2 / CMP.W D1,D2 / BEQ ok    word pass
010300:  MOVE.L D1,(A0) / MOVE.L (A0),D2 / CMP.L D1,D2 / BEQ ok    long pass
   mismatch -> LEA (pc+8),A2 ; JMP <error printer>
010324:  JMP (A6)    010326: BRA.S *      <- hang
010328:  JMP (A2)    01032A: BRA.S *      <- hang
01032C:  JMP (A2)    01032E: BRA.S *      <- hang   <-- the board sits HERE
010332:  "WORK RAM ERROR" "OBJECT RAM ERROR" "SCR0 RAM ERROR" ...
         "MASK RAM ERROR" "LINE SET RAM ERROR" "LINE DATA RAM ER..."
```

So the core is not hanging on a missing device and is not lost: Elevator
Action Returns' power-on self test **compared a byte it had just written,
found the wrong value, and jumped to its error handler on purpose**. The
strings sitting immediately after the handler are that test's messages.

Every failing compare in all three phases is a READ IMMEDIATELY AFTER A
WRITE TO THE SAME ADDRESS -- which is exactly the path where `rf_main`
drives `waddr` and `raddr` from the same `a[16:1]`. Changing the BRAM's
mixed-port mode from DONT_CARE to OLD_DATA did not move it, so the fault is
in WHEN the CPU samples that read-back, not in the memory's
read-during-write mode.

**Experiment 1 (build `28154550`): qualifying every CPU write with
`!clkena` -- write once, on the address-setup cycle, the way
`rf_sound_main` does it. It BROKE RAY FORCE**, in exactly the way Elevator
Action fails: IRQ2 acknowledges 0, nothing rendered, sound CPU never
released, PC parked (0x002932). Reverted; Ray Force verified back to 21/21
on `28150713`.

That is a useful negative result, and it says something precise. Removing
the write that commits at the END of the clock-enable cycle is what broke
it, so THAT is the write carrying valid address and data -- the earlier one,
at the address-setup edge, is the spurious one. `rf_sound_main`'s idiom does
not transfer: it runs a different TG68K configuration (68000 mode, its own
SPEED_DIV) whose outputs settle a cycle earlier.

It also shows what a broken CPU write path looks like from the self-test
page -- IRQ2 0, no render, CPU parked -- which is precisely Elevator Action
Returns' signature.

**Experiment 2 (build `28165741`): qualify with `clkena` instead.
Ray Force survived, 21/21. Elevator Action did not change at all** -- same
PC, same rows. So the CPU write path is exonerated. The change is kept
anyway: one write per bus cycle instead of two, on the cycle that was
already the effective one.

**And a correction that matters more than either experiment.** The write
ring FREEZES at the 4096th write (`wr_frozen = wr_count[12]`), a Phase 0/1
feature for capturing the boot stream. So "the ring stopped advancing, three
captures identical, therefore the CPU stopped writing at byte 0x4001FD" was
WRONG: the ring had simply hit its freeze, and the CPU may have run far
past that point. What the ring did prove, rigorously, is worth keeping: an
exact subsequence match puts the board's 2048 recorded ops at MAME's ops
2048..4095, **identical, op for op, lanes included**. The divergence is
somewhere after write 4096, unseen.

The ring is circular from the next build, so a capture always shows the LAST
2048 writes -- which is what tells you what a parked CPU did just before it
parked. The WRITE HASH row already covers the first 4096, so nothing is lost.

**(superseded) Experiment 2, when it was still worth running:** qualify with `clkena`
instead, so each write happens once, on the cycle that is already the
effective one, and the spurious address-setup write disappears. That is
strictly today's behaviour minus the extra write, rather than a different
write. If Ray Force survives and Elevator Action clears POST, the spurious
write was the fault; if Ray Force survives and Elevator Action still stops
at 01032C, the RAM path is exonerated and the search moves elsewhere.

**And in simulation rather than in 32-minute builds:** the failing
sequence is "write X, read X back, compare" against `rf_main`, which a
Verilator bench can drive directly in minutes. Make it red first, then fix.
Ray Force never trips this because its boot does not run this test.

**(superseded) The diagnostic was the main CPU's program counter.** `rf_main` still
computes `last_pc`, but the page row that showed it was given to
`PIVOT WR:SND PC` in B5, so nothing reports it any more. One build that puts
the main CPU's PC back on the page says immediately whether it is in a
retry loop inside the RAM test, in an exception handler, or parked on a poll
-- which is the difference between a RAM readback bug and a missing device.

**The older next step, once that is known:**
capture the board's write ring (`UART Debug = Write Ring`) and diff it
against the oracle's stream past that point. One obstacle to clear first:
setting the UART mode for this game did not take. Both MRAs declare
`<rbf>Rayforce</rbf>`, so it is not obvious whether MiSTer keys the saved
settings on the core name (`Rayforce.CFG`, which `tools/setcfg.py` writes and
which works for Ray Force) or on the MRA name (`Elevator Action Returns.CFG`);
writing either one and reloading left the UART streaming the self-test page.
Worth settling from Main_MiSTer's `user_io_create_config_name` rather than by
trial.

Note for whoever runs it: MiSTer keeps arcade settings per MRA name, so
Elevator Action Returns gets its own `/media/fat/config/Elevator Action
Returns.CFG` and starts from defaults (self test ON, TATE rotation) rather
than inheriting Ray Force's.

### Polish, input lag and the analog stick (2026-08-28, B16 `28121351`)

Three OSD options added: **Stereo Mix** (None/25/50/100 % -- `AUDIO_MIX`,
which had been tied to 0; the ES5505 pans its voices so this is a real
choice), **Flip Screen**, and **Pause When OSD Open** (holds both CPUs
through the existing `pause_eff`, so the music stops with the game).

Flip Screen drives `screen_rotate`'s `flip`, i.e. the ROTATED output. It is
deliberately not the renderer's flip: `rf_video_pipe`'s `flip` is tied high
because Ray Force sets its flipscreen bit permanently, and the sprite engine
takes its own flip from the sprite command word -- toggling the pipe's bit
would flip the playfields and pivot layer but not the sprites. So the option
applies whenever rotation is on; with Rotate = None, and on the analog raster
(which stays in raster order on purpose, for a rotated CRT cab), there is
nothing to flip.

**Input lag: there is none to remove in this core.** The path is
combinational end to end -- `hps_io`'s joystick word, OR'ed with the analog
stick decode (`joy0_in`), into `rf_main`'s `j0`, into the `always_comb`
that builds `in0_lo`/`in1_lo`/`ctrl_q`, straight to the CPU's read. Not one
pipeline stage, no per-frame sampling: the game sees a button the moment it
polls the port, so the lag is the USB poll (~1 ms) plus the game's own
polling. The lag that DOES exist is in the video path and is a choice:
`screen_rotate` writes the picture through the DDR3 framebuffer and the
scaler reads it back, which costs a frame, so **Rotate = None (or the analog
output, which never goes through the framebuffer) is the low-latency
configuration**; MiSTer's own scaler and `vsync_adjust` add the rest.

**The analog stick** (B13, in every build since) is correct by
construction and the board is set up for it: the DE10 has a *Microsoft
X-Box One pad* attached (045e:02d1, `ABS=3003f`, so the axes exist) and a
`rayforce_input_045e_02d1_v3.map` already saved. MiSTer scales axes to
-127..127 and sends **negative Y for up** (Main_MiSTer `input.cpp`,
`joy_analog`), which is exactly what `stick_dirs` assumes -- so up/down
cannot come out inverted. It ORs into the d-pad bits past 48/127 of
deflection. What no one has done is hold the stick: if it does nothing on
the cabinet, the thing to check first is MiSTer's own input map (the
analog stick has to be assigned in "Define analog joystick"), not the core
-- with the stick unassigned MiSTer never sends the axes at all.

### Sprites that never went away, and NVRAM (2026-08-28, B14 `28105535`)

**The ghost.** Reported from the cabinet: player shots leave their pixels on
the screen along the whole path. The cause is in `rf_video_spr.sv`, and the
comment that hid it said "the line buffer needs no clearing: each entry tags
the line it was written for". It tagged the LINE but not the FRAME. Bank =
line mod 4, tag = line[7:1]; within a frame that tells the 64 lines sharing
a bank apart, but line L of the next frame has the same bank AND the same
tag, so a pixel written at (L, x) and not overwritten by anything since
still read as a live sprite pixel, frame after frame. Nothing ever cleared
it -- only another sprite pixel at the same address could.

The fix is what the real chip does (and the model: it clears its
framebuffer every frame -- "sprite trails" is the F3 feature for NOT
clearing, and Ray Force never sets it): **clear the line before drawing
it**. Two details earned by measurement:

- A frame-parity bit in the tag (free: `{par, line[7:NBW]}` is still 7
  bits) is NOT sufficient on its own -- one bit only tells adjacent frames
  apart, and a pixel untouched for two frames comes back. `sim/Makefile
  spr-ghost` -- frame 3000 (198 sprites) followed by frame 300 -- failed
  with 1280 stale pixels on exactly that. It is kept as a guard for the
  window where the draw has not reached a line the mixer asks for.
- A flat 320-pixel clear per line is too expensive: it took the longest
  line from 3288 to 3608 clocks and made 254 of 256 lines late in
  `pipe-lat`. The clear is therefore a **span**: each bank remembers the
  leftmost and rightmost pixel its last occupant wrote and only that range
  is cleared. Every written pixel is still cleared before the next occupant
  draws -- full correctness, not just adjacent frames -- and the empty and
  near-empty lines that most of a frame is made of cost nothing. Measured
  after: longest line 3472/4726 clocks, **0 late lines**, all 12 benches
  identical.

**The two sprite rows are now PEAK HOLD.** A five-minute attract capture
(632 page passes) showed record drops in ONE pass and late lines in two,
which a last-frame value misses by design. `SPR REC : DROP` now reads
{highest records built, total rows dropped} and `SPRLINE : LATE` {longest
line draw, total late lines}, held since reset -- so a boss transition
cannot slip past between two UART samples. Held only from the 16th frame:
the first frames after a reset have no buckets built yet, so the mixer
legitimately outruns the draw and the counter would latch a permanent FAIL
out of the boot.

**NVRAM -- what is proven and what still needs a person at the cabinet.**
The board's MiSTer supports the channel (other cores have 128-byte files in
`/media/fat/config/nvram/`) and the deployed MRA carries the `<nvram>`
element, but no `Ray Force.nvm` exists yet, and it cannot appear until a
save is triggered: MiSTer only calls `arcade_nvm_save()` when the OSD is
opened or "Save settings" is picked, and `/dev/MiSTer_cmd` has no command
that opens the OSD (menu / osd / show_menu were all tried and ignored).
A MAME tap on the EEPROM port (0x4A0010, the byte MAME's `case 0x04` and
our `a[4:1] == 4'h9` both decode) settles what to expect: over a 40 s boot
and attract the game issues **16 READ commands and no WRITE** -- so a save
is requested only once a setting actually changes, which is correct
behaviour and also means a plain boot will never produce a .nvm.
**The end-to-end test is therefore: Service Mode on, change a setting,
exit, open the OSD once, and check that `/media/fat/config/nvram/Ray
Force.nvm` appears; then reload the core and see the setting stick.**

**NVRAM.** The 93C46 settings EEPROM now loads and saves through MiSTer's
ioctl index 254. The MRAs declare `<nvram index="254" size="128"/>` (the
form Main_MiSTer's `mra_loader.cpp` parses: `nvram_idx` from index,
`nvram_size` from size); Main sends the 128 bytes after the ROM regions,
from `config/nvram/<mra>.nvm` if it exists and the MRA's default
otherwise, and reads them back when the core raises `ioctl_upload_req` and
the user opens the OSD or picks "Save settings" (`menu.cpp`:
`arcade_nvm_save` on `MENU_SAVE_CHECK`, and on the Save settings item).
`rf_eeprom_93c46` gained a load port, a readback port and a `wrote` pulse;
the top level holds the save request from the first game write until the
upload finishes, so a later write asks again. **The array is no longer
cleared on reset** -- it could not be: the load arrives while the core is
held in reset by the download, so a reset clear would wipe exactly the
data being loaded. It powers up erased instead.

**On "DIP switches in the OSD": the F3 board has none.** There is no DIP
bank on the PCB and none in `taito_f3.cpp`; every setting (difficulty,
lives, region notice, free play, the sound test) lives in the game's own
service menu, reached with the cabinet TEST switch -- which is the OSD's
**Service Mode** toggle -- and is stored in the 93C46. So the OSD entry
that makes those settings reachable is already there, and NVRAM is what
makes them stick between sessions; there is nothing further to add without
inventing switches the hardware does not have.

### The sound bug: ES5505 reads (2026-08-28, session b2)

The board's B11 audio-ring capture was compared with MAME properly:
`tools/rf_audio_match.py` correlates the 138 ms capture at EVERY lag over the
whole 95 s of `model95.wav` and `en_mix.wav`, with a +-1 octave playback-rate
scan (a planted slice of the model is found at NCC 1.000; noise tops out at
0.09). The board's audio matched nothing (0.26, a transient), and its
waveform is voice-like for 17 ms then broadband hash (roughness 1.3-1.7
against a maximum of 0.69 anywhere in the model). Latency was excluded (the
bench with 20-79 cycle random fetch latency stays exact), so was byte order
(the BIST sum is the natural LE fold).

The cause, from a MAME read tap on the sound 68000 (`tools/oracle_en_reads.lua`
-> `dump/en4/en_reads.txt`; `oracle_en_dump.lua` now logs reads as `ESR`
lines too): **the driver reads the ES5505**. At boot it parks voice 10 (CR
fc06 = stopped, FC 0x40, K1/K2 ffff), steps ACC one byte at a time, writes
7fff to O1(n-1) on the high page and reads O1 back (page 0x2a, offset 0x0c,
~77 reads a frame from 2.4 s to 4 s) -- and what comes back is the game's
**sound table**, read out of the first bytes of d66-01: a 2-byte pointer and
a 12-character name per entry ("COIN", "EXTEND", "POWER UP", "LASER VOC",
"LOCK LASER", "P-BOMB", ...). MAME implements this as a special case
(`reg_read_high` O1 on a stopped voice returns the raw sample word at the
accumulator and stores it as o1n1 -- "the Taito F3 games extract raw data
from the sound ROMs"). While music plays the driver also polls the control
register's STOP bits on voices 21-31 (~750 reads in 11 s) and LVOL/RVOL now
and then. `rf_sound_main.sv` answered every one of those reads with `F000`,
so the board built its sound table from 0xF0 bytes and everything it played
afterwards was wrong. The write-stream ring check could not see it: the
reader loop's writes do not depend on what it reads, so the stream stays
identical to MAME's until the table is used at the first sound (28.8 s
after MAME's reset), past every window that was compared.

The fix (B13): `rf_es5505.sv` gets a host read port (`rd_req/rd_reg ->
rd_data/rd_valid`) answered from the live record of the page's voice --
`reg_read_low/high/test` including ACT/IRQV/PAGE, and the stopped-voice O1
case fetched through the voice's line cache (a miss goes to the sample bus,
idle at that point) and stored as o1n1. Two supporting changes: the write
queue is now applied whenever the sequencer is idle, not only at the tick
(same ordering -- every sample up to now is done, the next is not -- but a
read that follows a write sees it, which the page-then-read and
accumulator-then-read sequences need), and the reset sweep of the voice
file is an explicit flag (`sweeping`) because the old "vf_we still high"
test would restart the sweep after any idle-time record write and copy it
into every higher voice. `rf_sound_main.sv` holds the 68000 (no clkena)
until `rd_valid`, drops the request for one cycle after every CPU step so
back-to-back reads are distinct, and acknowledges IRQV only after the
vector has been delivered. The model applies the same O1 side effect on
`ESR` events, so the bench stays exact: `make -C sim es5505-rw`
(`dump/en5/`, 45 s with reads) = 1,150,000 samples, 0 differences, 8001
host reads, 0 wrong; `make es5505` on en3 still exact.

Also in B13: the left analog stick works as the d-pad (48/127 threshold,
OR'ed with the digital bits; `stick_dirs` in `Rayforce.sv`).

**B13 on the board (10:16)**: `tools/setcfg.py 18`, deploy, `rf_uart.py -t 40
-o ring.log`, `python3 tools/rf_audio_match.py ring.log --ref
dump/en4/model95.wav --ref dump/en4/en_mix.wav --span 0.5`: **NCC +1.000 at
ratio 1.0000 at 28.850 s in both**, the runner-up 0.26. The board's audio
IS MAME's. Still to do by ear: the whole soundtrack, not 138 ms of it; the
ring can be re-captured at any point by resetting (the index is absolute).

**For the morning**: to check the ship-vanishing lead directly, play into a
boss transition with `.venv/bin/python3 tools/rf_uart.py -t 30 -o boss.log`
running; `SPR REC : DROP` (rows dropped at the store cap) and `SPRLINE :
LATE` (lines the mixer took before the draw finished) are the two rows that
name the cause. Sprite lag is 1 frame here against MAME's 2: if sprites
visibly lead the scroll, that is the other thing to look at.

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
Aspect ratio   Original / Full Screen / [ARC1] / [ARC2]
Rotate         CCW (TATE) / CW / None         Ray Force is MAME ROT270 = CCW;
                                              rotation is through the DDR3
                                              framebuffer (scaler output only),
                                              exactly as the Raiden II core
Scandoubler Fx None / HQ2x / CRT 25% / 50% / 75%
Refresh Rate   58.9Hz Native / 60Hz           60Hz = 257-line frame (60.08 Hz)
Service Mode   Off / On                       cabinet TEST switch
Self Test      On / Off                       On = the page, Off = game video
UART Debug     Self Test / Off / Write Ring
```

F3 boards have no DIP switches: game settings are the service menu (Service
Mode + the EEPROM). Button remapping is MiSTer's own "Define buttons", driven
by the J1 list, which matches the MRA's `<buttons>`: Shot, Bomb, Start, Coin,
Service, Pause (Pause is named but not implemented yet).

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

### The bench RAM model was wrong -- and the RTL was tuned to it (2026-08-27)

The first hardware build of the video pipeline showed a black screen while
the self-test page reported the pipeline running flat out (256 lines mixed
and built per frame, ~10k tile fetches, 81920 line-buffer writes). Running
the pipe under real raster timing in Verilator was pixel-perfect. That
contradiction pointed at the one thing the benches modelled in C++ rather
than in RTL: the video RAMs.

The C++ model answered with `mem[current address]` in the same cycle -- a
zero-latency RAM. The real BRAM (and rf_bram's own Verilator model) registers
the address and answers the cycle AFTER. Two modules had been written for the
real timing, "failed" the bench, and were then changed to satisfy it: the
playfield builder's attribute/code latch and row scan, and the mixer's
palette sampling. With the bench model corrected the sim reproduced the
hardware (4001/71680 pixels), the RTL was put back to real timing, and every
bench is green again under the correct model.

Rules that come out of this:
- a bench memory model must implement the documented BRAM contract (address
  registered, data the cycle after) -- or better, instantiate rf_bram's
  Verilator model instead of writing a C++ one. Follow-up: move the video
  RAMs into the sim wrappers so the benches use the real model.
- when correct-looking RTL fails a bench, suspect the bench before changing
  the RTL. The attribute latch was right the first time.
- the self-test page's per-frame video counters (MIX:BUILD, FETCH:LBUF,
  MAXFETCH:BUILD) are what made this diagnosable in one round trip instead
  of several. Real SDRAM tile-fetch latency measured 23 clocks against the
  sim's 12; longest build 1663 of 3456.

### Second session, 2026-08-27 evening: deployed, still black, instrumented

The 12:52 build (stamp `27123634`, the one with the BRAM-latency fix) had
been compiled but **never uploaded** -- the board was still on the 12:30
bitstream. The MiSTer process was also hung: `/dev/MiSTer_cmd` had two
writers blocked on it (one a stray `load_core` of an unrelated core's MRA
from other tooling) and pid 527 sat at 100% CPU without draining the FIFO,
so neither the UART capture nor a screenshot returned anything.

**Restarting a hung MiSTer process** (there is no respawn; inittab starts it
once at sysinit):

```sh
kill -9 <stuck writer pids>; killall MiSTer; sleep 2
cd /media/fat && setsid nohup /media/fat/MiSTer >/dev/null 2>&1 </dev/null &
```

(paramiko's exec channel times out on the detached start; check with a fresh
connection -- `ps | grep '[/]media/fat/MiSTer'` and a new inode on
`/dev/MiSTer_cmd`.)

Deployed 27123634: **every check on the page passes**, including the video
counters -- `MIX : BUILD 01000100`, longest SDRAM tile fetch 0x17 = 23 clocks,
longest build 0x099A = 2458 of 3456. The game video is **still black**
(`/media/fat/config/Rayforce.CFG` = `08`, i.e. Self Test Off, so the black
screenshot is game video, not the page).

Two things follow from that:

1. The bench-latency fix was right but **could not have been the black
   screen's cause**: with the wrong latency the sim matched 4001/71680 pixels
   -- wrong colours, not black. The black screen has a different cause and
   it has been there since the first video build.
2. The self-test rows prove the decoder and builder are reading line RAM and
   playfield RAM correctly on hardware -- 10888 tile fetches per frame against
   the sim's 10892 for the same attract frame. What they do NOT prove is the
   content of those fetches, or anything downstream of the mixer.

Ruled out by reading, this session: `rf_bram_tdp` port B is 1-cycle
unregistered like the bench; `rayforce_video`'s counters are the bench's
verbatim; the MRA stream offsets match `rf_gfx_bus` BASE_LO/BASE_HI and the
loader writes the stream flat; the palette word order is the 68020's (the
oracle dumps shares with `read_u8` in CPU byte order); Quartus reports no
latch, stuck-at or removed-register warning in the video path. Never verified
on hardware: **the SDRAM contents above 0x480000** (the BIST reads back only
the 1 MB maincpu region) and the mixer -> line buffer -> output path with
real data.

So the page now says which it is. Two rows changed/added, values latched per
frame:

```
FETCH : PIX NZ    {tile fetches, output pixels that are not black}   PASS if pixels != 0
TILE NZ:PF:PAL    {fetches whose 16 pixels were not all zero,
                   OR of playfield samples[7:0], OR of palette reads[7:0]}
                                                                     PASS if all three != 0
```

Reading them (sim reference for frame 1800: `2A8C58F7` and `2A8C9FFF`):

| TILE NZ | PF | PAL | PIX NZ | it is                                             |
|---------|----|-----|--------|---------------------------------------------------|
| 0       | -  | -   | -      | SDRAM tile data reads as zero: contents or channel |
| >0      | 0  | -   | -      | the 6bpp unpack into the playfield line buffers    |
| >0      | >0 | 0   | -      | the palette port                                   |
| >0      | >0 | >0  | 0      | the mixer                                         |
| >0      | >0 | >0  | >0     | line-buffer readout or the output mux -- the       |
|         |    |     |        | pixels were made and lost on the way out           |

Also in this build: the OSD video options above (aspect, rotate via
`screen_rotate`, scandoubler fx, 60 Hz), and `rate_60` threaded into
`rayforce_video` (V_TOTAL 257, vsync at lines 1-3) and `rf_video_pipe` (the
lookahead wrap uses V_TOTAL-2/-1 in both cases). `make -C sim pipe pipe-60`
runs the pipe at both frame lengths: 71680/71680 pixels identical either way.

### The text layer -- `rtl/rf_video_pivot.sv` (2026-08-27, evening)

Built while the diagnostic build was compiling, because it needs no SDRAM
and its RAM ports (text, char, pivot) were already brought out of rf_main.
Per line, after the decoder finishes (the same `pf_go` the playfield builder
starts on): a 64-word scan of the text-RAM row for MAME's row-usage skip,
then one pixel per clock -- source x (mosaic hold, scroll, flipscreen) ->
text-RAM tile word -> char-RAM (or pivot-RAM) word -> nibble -> line buffer.
Double-banked; the mixer reads it at `smp_x` from the bank it is composing
and takes `pv_used` from the same bank. ~390 clocks per line, concurrent with
the playfield build.

Verified: **15/15 dumped frames pixel-identical to the model through the
whole pipe** (`make -C sim pipe-all`, now with `F3_ONLY=pv,pf0..3`), at both
frame lengths. The one bug found on the way: the model's `x_index` takes the
RASTER x, so the scroll register carries a +46 -- without it the text sat 46
px off, which the bench caught on the first run.

Coverage caveat, stated rather than hidden: every dumped frame drives the
VRAM (tilemap) source with mosaic off. The pixel-layer source (with its
borrowed-palette row hack) and the mosaic hold follow the model line by line
but have no dump exercising them.

`Rayforce.sv` now feeds the pipe the three RAM ports; only sprite RAM is
still parked. Not yet through Quartus at the time of writing -- that is the
build after the diagnostic one.

### The picture is up (2026-08-27, build 27162801)

Deployed the playfields + text build to the board (172.17.1.164). Result, on
screen and over the UART:

- The **notice screen** renders -- the US "FOR USE IN THE UNITED STATES OF
  AMERICA, CANADA, AND MEXICO ONLY" warning, correct text, correctly
  oriented for the rotated cabinet.
- **Attract-mode gameplay** renders: the terrain playfields (rivers,
  mountains, clouds) scrolling frame to frame, full colour, with the text
  HUD over them -- INSERT COIN, 1UP, HI SCORE, the score digits, CREDIT,
  LASER. Two shots 5 s apart show the playfields scrolled, i.e. it is live,
  not a static frame.

Every self-test row passes, including the new diagnostics:

```
TEXT AND CHAR   0000EBAB  PASS
MIX : BUILD     01000100  PASS
FETCH : PIX NZ  3E1BFFFF  PASS    <- 15899 tile fetches, output non-black
                                     pixels saturated (was 00000000 = black)
MAXFETCH:BUILD  00170C23  PASS    <- longest fetch 23 clks, longest build
                                     3107 of 3456 -- 349 clocks of margin,
                                     the tightest number on the page now
TILE NZ:PF:PAL  3E1B9FFF  PASS
```

**What the black screen actually was.** Not the BRAM-latency bug (that gave
wrong colours, not black) and not anything downstream of the mixer. The only
build ever deployed before this was the playfields-only pipe, and the first
thing the program draws is the text-only notice screen -- so there was
genuinely nothing for the playfields to show. The diagnostic rows added this
session would have said so in one read (PIX NZ = 0 with TILE NZ > 0), but the
text layer answered it first by making the picture appear. Lesson: before
calling a black screen a pipeline fault, check what the program is actually
drawing on that frame.

`MAXFETCH:BUILD` is now the row to watch: longest build 3107/3456. The pivot
build runs concurrently but the number crept up (2458 -> 3107) because both
share the cpu clock; sprites will add more. If it reaches 3456 the pipeline
overruns the line and the design needs the lookahead widened to two lines or
the build sped up.

### The whole video pipeline is verified in sim, sprites included (2026-08-27)

**`make -C sim pipe-all` -- every dumped frame, 71680/71680 visible pixels
identical to the model (= MAME), through playfields + pivot/text + sprites**,
at both frame lengths, including the 198-sprite frame 3000. The complete F3
video chipset now exists in RTL and matches the oracle end to end. What is
left is hardware integration (Rayforce.sv wiring, the SDRAM channel share,
the BRAM-fit decision) and a build -- not new pixel logic.

The sprite engine (`rf_video_spr`) is wired into `rf_video_pipe`: prepass on
frame_start into one of two bucket banks while the draw reads the other
(1-frame lag; MAME's is 2, tune on hardware), drawing the same build line as
the playfields, sampled by the mixer at smp_x for the line it composes. The
draw is FETCH-PIPELINED -- the next record's tile row is prefetched while the
current record draws -- which was necessary: frame 3000 puts ~114 sprite-rows
on one line, and fetch-then-draw (~43 clk/record) overran the 3456-clk line
budget and dropped the line; pipelined (~24 clk/record) it fits. The roadmap's
"max 43/line, no framebuffer needed" measurement was from a lighter capture;
114/line is real, and the per-line design only holds for it with the prefetch.

### Sprites: all three RTL blocks done and verified (2026-08-27)

Building the sprite engine in the same verify-each-stage way as the
playfields. Two of the three RTL pieces are done and byte-exact against the
model:

- `rtl/rf_video_spr_list.sv` -- the list walker (get_sprite_info): the Axis
  position/zoom state machine, bank switch, jump command, multi-block sprites
  and the two-level scroll globals. Streams the drawable sprite list.
  **Every dumped frame's list is byte-identical to the model**
  (`make -C sim spr-all`), including the 198-sprite frame 3000. Two width
  bugs found and fixed by the bench: 10-bit list counters made the 1024-entry
  limit compare as >= 0 (walk stopped after entry 0), and the sprite RAM read
  needed the registered-address BRAM model in the bench (same trap as the
  pipe benches).
- `rtl/rf_spr_gfx_bus.sv` -- sprite tile-row fetch, cloned from rf_gfx_bus
  with the sprite regions and sprite_hi packing. **584/584 rows byte-exact**
  (`make -C sim spr-gfx`).

The third block, `rtl/rf_video_spr.sv`, is now written and verified too:
**every dumped frame's sprite line buffer and per-line row-usage is
pixel-identical to the model's framebuffer** (`make -C sim spr-line-all`),
through the 198-sprite frame 3000, with zoom. It walks the list into a
per-line bucket of row-records (a sprite spread over the lines it covers via
the dy8 accumulator), then per line fetches and lays down each record with
the dx8 accumulator; the line buffer tags each pixel with its line so it
never needs clearing. The subtle bug the bench caught: when zoom crushes
several source rows onto one screen line they OVERLAY (a later row fills the
earlier one's transparent gaps) -- a "first row per line wins" shortcut drops
those, so every row is emitted, in reverse-row order, and drawn with
overwrite to reproduce the model's forward-row/reverse-list write-if-empty.

What is left for sprites is INTEGRATION, and the two decisions still land
there:

**1. Zoom is required.** The measurement in "The sprite framebuffer question"
below said no framebuffer is needed, and that still holds -- but it did NOT
say sprites don't zoom. They do, heavily: frame 1799 has scale-16 sprites
(16 source rows crushed to one line), frame 3000 mixes 107/114/144/174 and
even anisotropic 64x256. So the builder cannot assume full-size 16x16; it has
to reproduce the model's dy8/dx8 accumulators (source row per screen line,
source pixel per screen pixel, with the zoom-out dedup rule that the LAST
source pixel mapping to a screen pixel wins in x and the FIRST source row
wins in y).

**2. BRAM is the wall.** The current build is 530/553 blocks (96%); only 23
are free. A zoom-correct line builder wants to expand each sprite into its
per-screen-line row-records and bucket them by line -- and a busy frame
(frame 3000, ~198 sprites, many full-size) produces ~2000-2500 such records.
At ~56 bits each that is 13-16 RAM blocks for the record store alone, plus
the next-pointer store and the line buffers -- right at or over the 23 free.

So the builder either:
  (a) fits economically into 23 blocks with a hard record cap, DROPPING
      sprites on the busiest frames (a visible quality loss, logged not
      silent); or
  (b) waits for the main-RAM-to-SDRAM migration (frees the 128 blocks main
      RAM occupies) that the roadmap always flagged as maybe-needed for
      sprites -- a bigger change, but then sprites have all the room they
      need and this stops being a corner to design around.

This is the point the roadmap predicted ("main RAM has to move to SDRAM
before sprites can be built" -- though the framebuffer-free design pushed
that back, the record store brings it back for busy frames). It is a real
architecture call, so it is the user's to make rather than something to
quietly commit to.

### Sprite hardware integration (2026-08-27, late evening)

The sprite engine met Quartus. All sims re-run green AFTER every change
below: `spr-line-all` 15/15, `pipe-all` 15/15 (frame 3000's 198 sprites
included), `pipe-60` -- all 71680/71680 pixels identical to the model.

- `Rayforce.sv` -- the sprite RAM B port is wired to the pipe (was parked at
  `15'd0`), and the vpipe instantiation caught up with the pipe's real port
  list (the tree was mid-integration: it still connected the retired
  `sp_color`/`sp_used` tie-offs and would not have compiled).
- `rtl/rf_spr_ch_share.sv` (new) -- the two sprite gfx planes share ch4, the
  only free SDRAM channel. Grant-and-hold mux with a served-mask: a plane's
  request LEVEL outlives its completion by the CDC crossing, and without the
  mask the arbiter re-grants an already-served plane, double-toggling the
  completion and desyncing rf_spr_gfx_bus's edge detector for good.
- `sim/pipe_top.sv` (new) wraps the pipe with rf_spr_ch_share and pipe_tb
  drives ONE shared sprite channel, so the arbiter and the serialised fetch
  latency are covered by the whole pipe regression instead of meeting
  hardware untested. The sprite draw now starts at the top of the raster
  line (spr_start at div 2, new in rf_video_pipe) instead of after the line
  decoder: it has no decode dependency, and the doubled fetch latency of the
  shared channel makes the extra margin worth having on hardware, where ch4
  is the lowest-priority channel. (Whether the old pf_go start would also
  have passed was not re-tested; the early start costs nothing.)
- `rf_video_spr.sv` hardware mapping -- slist/rec/rnext are MLABs,
  head/tail stay registers (frame_start clears a bank in one cycle). Three
  Quartus lessons, each learned from a failed map:
  1. N separately-sliced reads of one array (`rec[rb][fc][53:36]` etc.)
     defeat memory inference entirely ("can't infer memory", then synthesis
     dies under ~500k of flip-flops). One full-word read wire, sliced after,
     is the pattern it accepts.
  2. Inferred RAM needs defined read-during-write behaviour; the async-read
     MLAB has none, so `ramstyle = "MLAB, no_rw_check"` is required. Safe
     here: slist is written and read in different prepass states, and
     rec/rnext writes (bank wb) never share an address with reads (bank rb).
  3. An MLAB has ONE write port. The bucket append wrote rnext twice in a
     cycle (the new record's null link and the old tail's link); the link
     write moved to a new P_LINK state. The first version of that split
     dropped the explicit `pst <= P_EXP1` from the advance path, parked the
     FSM in P_LINK, and silently stopped appending records -- spr-line-all
     caught it immediately. When a "stay in state" idiom moves to a
     different state, "stay" has to be written out.
- The `.qsf` was also missing rf_video_pivot/rf_video_spr_list/
  rf_spr_gfx_bus/rf_video_spr (only rf_video_pipe had been added) -- the
  deployed text-layer build predates the pipe module, which is why that was
  not caught earlier.
- `build.sh` -- the build scope now runs under `choom -n 1000`, so if the
  machine is short of RAM the OOM killer picks the build and not whatever
  else is running (this systemd predates `-p OOMScoreAdjust`).

The BRAM wall the roadmap worried about did not materialise: the sprite
stores cost zero M10Ks (all MLAB), so main RAM can stay in BRAM for now.

### Sprite / SDRAM review: fit and latency (2026-08-27, night)

A review of how the sprite engine and the SDRAM path would meet the
hardware, before the first sprite build. Two findings, both measured rather
than argued, and both addressed.

**1. The sprite draw overran dense lines at real SDRAM latency -- silently.**
The pipe bench's channel model answers 14 ram clocks after a request, with
no contention. The board measured the tile fetch at 23 clk_sys busy against
the bench's 12. Frame 3000 (198 sprites, 3144 row-records, four lines with
114 records) at higher bench latencies:

| bench latency | one fetch in flight (as built) | two in flight (this session) |
|---|---|---|
| 14 | 71680/71680 | 71680/71680 |
| 20 | 164 px wrong, lines 114-117 | 71680/71680 |
| 34 | 253 px wrong, 2 lines lost | 203 px wrong, 2 lines lost |

and frame 2400 (a routine 147-sprite frame, 74 records/line) at 34: 2 lines
lost as built, identical with two in flight. The single-slot draw cost the
whole SDRAM round trip per record (two bursts on the lowest-priority
channel plus the CDC both ways, ~30 clk); 114 x 30 > 3456. Worse, the
overrun was invisible: `rf_video_spr` samples `line_start` only when idle,
so a late line simply eats the next line's start and that line gets no
sprites, and nothing counted it.

Done about it:
- **`SPRLINE : MISS`** row on the self-test page (it replaced the UART note
  row -- the page is exactly 28 rows): {longest sprite line draw in clocks,
  line starts missed because the draw was still busy}. PASS = none missed
  and the longest under 3456. This is the number that calibrates the bench.
  The bench had to step through one more `frame_end` before printing its
  diagnostics: it was printing frame 2's, whose bucket bank the prepass had
  not filled yet (the one-frame lag), so `sprmax` always read 1.
- **Two fetches in flight** (`rf_video_spr`, build 2 of the night): two
  `rf_spr_gfx_bus` instances take alternate records, a two-slot queue hands
  them to the draw in issue order (the overwrite semantics depend on that
  order), and `rf_spr_ch_share` arbitrates four planes with a rotating
  priority in the order A.lo, A.hi, B.lo, B.hi -- a record's two planes go
  back to back and the older record's planes before the younger's. With the
  channel kept busy the 17-clock draw is the bound: 114 x 17 = 1938.
- `make -C sim pipe-lat` -- frame 3000 at latency 24 as a gate, 34 printed
  for information. Note what the bench's latency IS: through `ch_share`
  only one burst is ever outstanding, so `lat` is the per-burst OCCUPANCY of
  the shared channel, i.e. it stands for the controller's turnaround, not
  the fetch's round trip. Traced through `rf_sdram`'s states that turnaround
  is ~14 ram clocks idle (sync 2, ACTIVE, WAIT, READ, CAS 3 + burst 4, and
  the IDLE_5..1 spacing overlaps the next request's sync), more with the
  playfield channels contending. So 34 is pessimistic and the 114-record
  line cannot fit 228 x 34 whatever the queue depth; the page row settles
  where the board really is.

**2. The BRAM wall had moved into the MLABs, at 97 %.** "Sprite stores cost
zero M10Ks" was true; here is where they went (an MLAB is 32 x 20 bits):
`rec` 2 x 3328 x 54 = 624 MLABs, `rnext` 208, `slist` 128 -- 960 of the 985
MLAB-capable LABs, which is why the fitter died at 4096 records and 3328 was
chosen (6 % over the measured peak of 3144). And `head`/`tail` were 12288
flip-flops behind three 512:1 muxes, purely so `frame_start` could clear
them in one cycle. Done about it, all in `rf_video_spr`:
- A record is now `{sprite index, source row}` = 14 bits; the per-sprite
  fields (x, x scale, code, colour, flipx) that every one of a sprite's 16
  rows used to carry are stored once and looked up at draw time. The list
  is split by consumer: `sl_y` (ty, y scale, flipy) is read only by the
  expand in the same prepass that wrote it -- single bank; `sl_d` is read by
  the draw a frame later -- double banked. Neither needs a second read port.
- `head`/`tail`: `hvalid` is one bit per line per bank in registers (the
  one-cycle clear is now 256 bits), `head` is an `rf_bram` read by the draw
  with the BRAM's one-cycle latency, `tail` an MLAB read only by the
  prepass. Neither needs clearing because `hvalid` gates every read.
- The draw's record lookup is two deep (`rec` -> `sidx_r` -> `sl_d`), so the
  prefetch waits until it settles (`fc_ok`); a `P_RD` state reads `tail`
  the cycle BEFORE `P_EXP1` writes it, because an async-read MLAB with
  `no_rw_check` has no defined same-cycle same-address read-during-write and
  the RTL must never do one.
- NREC back to 4096 (30 % over the measured peak instead of 6 %). MLABs:
  `rec` 256 + `rnext` 256 + `sl_y` 64 + `sl_d` 192 + `tail` 16 = ~780 (80 %)
  against 960 (97 %) before, and ~12k flip-flops and their muxes gone.
  Fallback if the fitter still objects: NREC 3328 gives ~690.

Also fixed from the review: `rf_spr_ch_share` sampled the cpu-domain
request levels raw in the ram domain and used them the same cycle -- the
one new crossing without the two-flop synchroniser every other one has
(the controller's own channel requests included); and `video_rotated` was
generated by `screen_rotate` but never connected to `hps_io`, so the OSD
would have drawn unrotated over the TATE picture.

Left alone, deliberately: the SDRAM controller. One outstanding op, ~8 ram
clocks per 8-byte burst with auto-precharge, no bank interleave -- half the
raw bandwidth, but the worst line's aggregate (120 playfield + 228 sprite +
CPU + ~13 refresh bursts) is ~70 % of what it can do. Latency, not
bandwidth, was the problem, and that is fixed on the client side.

**Quartus lesson (a map crash):** `logic [255:0] hvalid [0:1]` with
`hvalid[wb][ex_dyb] <= 1'b1` -- a bit write into an element of an UNPACKED
array -- makes Verific treat it as a partial RAM write and quartus_map dies
with `Internal Error: Sub-system: VRFX ... AssignRam`. Declared PACKED
(`logic [1:0][255:0]`) it is a bit-select of a register vector and maps
fine. Same rule as the MLAB one: an unpacked array is a memory to Quartus,
and only whole-element reads and writes are safe on it.

All sims green after every step: `spr-line-all` 15/15, `pipe-all` 15/15,
`pipe-60`, at both the one- and two-slot draw.

### Build 27212838 on hardware: sprites up, and the overrun measured

The first sprite build (slim records, hvalid/head/tail, ch_share sync,
video_rotated, SPRLINE row; ONE fetch in flight). Fit: timing met (clk_sys
+2.69 ns, clk_ram +1.69 ns), **M10K 534/553, memory LABs 784** (the 960
estimate for the old layout, and ~780 predicted for this one), total LABs
3918/4191 (93 %) -- the async-read MLAB muxes are ALMs too, and that 93 % is
the number to watch when the sound board arrives. 30-minute compile.

On the board (172.17.1.164), read over the UART during attract mode:

```
FETCH : PIX NZ  350471A6  PASS
MAXFETCH:BUILD  001709A3  PASS     <- 23-clock fetch, longest build 2467
TILE NZ:PF:PAL  34FE9FFF  PASS
SPRLINE : MISS  0DFE0002  FAIL     <- longest sprite line 3582 clocks,
                                      2 line starts missed
```

**Sprites render** -- the ship, asteroids, the enemy fleet, the ITEM marker,
the lock-on instruction panel (screenshots/s2_20260828_020409-screen.png) --
and the overrun predicted in sim happens in ordinary attract play. The
number calibrates the bench: 3582/2 matches frame 2400 at bench latency
32-34 (`0E85 0002`), i.e. the shared sprite channel's real per-burst
turnaround is ~30 ram clocks, not the ~14 an idle controller would give.
ch4 is the lowest-priority channel and the CPU's line-cache misses (ch3)
and the playfield bursts (ch1/ch2) go in front of it.

Two consequences:
- Build 2 (two fetches in flight + the playfield fetch/unpack overlap +
  the 20-bit sprite line buffer) will bring a dense line down to ~2 x
  turnaround per record, ~26-35 clocks, channel-bound: it should pass the
  attract frames but may still miss on frame-3000-class lines (114
  records). The row will say.
- The robust fix is to stop paying per line at all: let the sprite draw run
  AHEAD of the raster into a ring of line buffers (4-8 banks, ~5 M10Ks for
  8 x 320 x 20 bits) instead of one line per line_start. The buckets are
  ready for the whole frame, sprites cost ~10 % of the frame on average
  (3144 records x ~30 clocks = ~95k of 885k clocks), and only local density
  matters -- a ring of N absorbs N-1 consecutive dense lines. That is
  independent of any SDRAM tuning and does not touch the verified draw.
  Raising ch4 above ch3 in rf_sdram is the cheap alternative, at the cost
  of CPU stalls on dense lines.

The two "FAIL"s in the text-only samples (notice screen: MAXFETCH:BUILD
`00000111`, TILE NZ `0000`) are the known text-only-frame artefact, not
faults; the rows assume a frame with playfields.

### The run-ahead sprite ring (build 3), and Phase 3 queued

`rf_video_spr` no longer draws one line per raster line. From frame_start
it draws lines 0..255 in order, as fast as the fetches allow, into a ring
of NB=4 line buffers (4 x 512 x 20 bits = 4 M10Ks), held back only by the
mixer's line: the draw may be up to NB-1 lines ahead, in 8-bit modular
arithmetic so the frame wrap needs no special case. `lines_done` comes out
to `rf_video_pipe`, whose SPRLINE row now counts *lines the mixer started
before the draw had finished them* (the number that matters) alongside the
longest single line. The buckets are ready for the whole frame and sprites
cost ~10 % of it on average, so only local density matters; NB=4 absorbs
three consecutive dense lines and is a one-line change to widen.

Verified: `spr-line-all` 15/15, `pipe-all` 15/15, `pipe-60`; frame 3000 at
bench latency 34 -- which lost two lines with one fetch in flight and still
lost them with two -- passes with a 4542-clock line and 0 late; frame 2400
at 34 passes. Latency 50 (pessimistic beyond anything measured) still shows
7 late lines: that is the point at which the average, not the peak, no
longer fits, and nothing per-line fixes that.

The bench drives it as the mixer would: `rd_line` is the mixer's line and
the bench waits for `lines_done` to pass it before reading a line back.

Phase 3 (sound) is written up in ROADMAP.md as a staged plan with its two
walls (the 64 KB sound RAM vs ~18 free M10Ks; two more SDRAM streams with
all four channels taken) and an oracle-first order, the same shape that
worked for video.

### Missing parts, listed (2026-08-28, for after sound)

Things the core does not do yet, with what each needs. None is blocked on
a design decision except NVRAM's MiSTer-side detail.

- **Pause** -- done in B4: the J1 "Pause" button toggles a hold on the main
  CPU's clock enable (`rf_main` `pause`); video keeps running. The sound
  CPU is not paused (it does not exist in B4); when it does, pause should
  hold it too or the music keeps playing over a frozen game.
- **Region variants** -- `releases/Gunlock.mra` and `releases/Ray Force
  (Japan).mra` written (ic35 d66-24 / d66-20, CRCs from taito_f3.cpp).
  Untested on the board; the notice screen differs per region.
- **NVRAM (EEPROM save/load)** -- the 93C46 contents are in registers in
  `rf_eeprom_93c46` (64 x 16). The MRA already declares `<rom index="254"
  type="nvram">`, so MiSTer sends 128 bytes on ioctl index 254 at load
  (the .nv file if one exists, else the MRA's default `FF FF`): the LOAD
  side is a 64-word write port on the EEPROM taken from `ioctl_wr` with
  `ioctl_index == 254`. The SAVE side is `hps_io`'s `ioctl_upload` /
  `ioctl_rd` / `ioctl_din` path, which needs the core to answer reads of
  the same 128 bytes, and needs to be told how MiSTer main triggers the
  upload for arcade cores (OSD "Save settings" vs. `ioctl_upload_req` from
  the core on a write) -- check a core that saves NVRAM (Arcade-Raiden2's
  MRA uses index 254 for DIPs only, load-only). Not built until that is
  confirmed; a wrong guess costs a 35-minute build to learn nothing.
- **Sprite lag** -- the RTL draws sprites one frame after the CPU wrote
  them, MAME two (`sprite_lag` in the gunlock config). Visible only as
  sprites leading the scroll by a frame, if at all; a triple-banked bucket
  store would match MAME at ~+256 MLABs, or the prepass could be started a
  frame later from a snapshot. Decide from what the eye says on the board.
- **Sprite trails** (`trails` bit in the list, unread in the RTL): Ray Force
  never sets it (measured in Phase 2). Other F3 games do.
- **Pivot RAM / pixel layer** -- stubbed from B5 on (Ray Force never writes
  it; `PIVOT WR:SND PC` counts writes so the assumption is checked every
  run). Any other F3 game on this core needs it back, and then the sound
  RAM needs the SDRAM route.
- **60 Hz refresh option** -- verified in sim at 257 lines, never watched on
  the board.
- **Mosaic** and the pixel-layer source of the text layer -- follow the
  model line by line but no dump exercises them.
- **EEPROM defaults** -- volatile until NVRAM lands: the game rewrites its
  settings on every boot after the "bad settings" path.

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
