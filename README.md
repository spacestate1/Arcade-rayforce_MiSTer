# Taito F3 System for MiSTer

An FPGA recreation of the **Taito F3 System** arcade board (1992–1998) for the
MiSTer FPGA platform.

The F3 chipset in this core — the 68020 main board, the four playfields with
their line-RAM raster effects, the sprite engine, the priority mixer, and the
Taito EN sound board — is written against MAME and verified against it frame by
frame and sample by sample, so it is not tied to one game. **The game it runs
today is Ray Force** (Taito, 1994 — *Gunlock* in Europe, *Layer Section* in
Japan), in all three regional versions. What a second game needs is measured
and listed under [Other F3 games](#other-f3-games) rather than guessed at.

## Status

| Game | State | Where it stands |
|---|---|---|
| **Ray Force** (US) | **~90 %** | Plays with sound. Every self-test row passes on hardware; video pixel-identical to MAME, audio sample-exact. Held back from "done" by the sprite overrun in busy scenes (Known problems #1), the ES5510 stub, and the fact that nobody has played it start to finish. |
| **Gunlock** (World) | **~85 %** | Same board and the same ROMs bar one program chip, so everything above should apply — but the MRA has never been loaded on a board. Untested, not unlikely. |
| **Ray Force** (Japan) | **~85 %** | As Gunlock. |
| *Elevator Action Returns* | **~80 %** | **Runs** — boots, plays, sprites and playfields draw, sound CPU streaming, one vblank ack per frame. All ten sampled frames match MAME pixel for pixel across the full 232-line visarea, five of them dumped after the fixes as an out-of-sample check. Still in `releases/experimental/`: the pivot layer is a mirror, ten frames of attract and character select are not a playthrough, and its sound has never been correlated. |

Percentages are judgement, not arithmetic; the rows either side of them are
the evidence.


**The game boots, plays at full speed, and has sound.** On a DE10-Nano every
row of the core's built-in self test passes, and the picture and the audio
have both been checked against MAME rather than by eye:

- **Video: 15 consecutive frames pixel-identical to MAME**, end to end
  (playfields, line-RAM raster effects, the text/pivot layer, sprites with
  zoom, and the priority mixer), plus 30 frames / 4.0 M pixels on the
  playfield builder and 7,680 lines through the line-RAM decoder.
- **Sound: the ES5505 sampler is sample-exact against a bit-accurate model of
  MAME over 1,150,000 samples**, and the sound 68000 runs the real driver —
  its first 1,387 chip writes from reset are identical to MAME's.
- **On hardware**: the core's own audio capture (see *Audio Ring* below)
  **correlates 1.000 with MAME's mix** at the same instant of the same track.

The released build (`releases/Rayforce_20260828.rbf`, build stamp
**28165741**) passes every self-test row on a DE10-Nano. It is built from the
tree at commit `be6737c`; the handful of commits after that are diagnostic
and documentation changes that have not been compiled into a bitstream.
Verify what you downloaded with `python3 tools/check_files.py`.

**The bitstream and the MRAs must come from the same release.** The SDRAM
region layout changed when the core became a general F3 core, so an older
bitstream with these MRAs (or the reverse) fails the `ROM BYTES` self-test
row and shows wrong graphics.

## What the core covers

| Part of the arcade board | State |
|---|---|
| 68020 main CPU (TG68K.C in 020 mode) | Working — the full `f3_map` memory map |
| Video: 4 playfields + line-RAM effects | Working, pixel-identical to MAME |
| Video: sprites (list walker, zoom, priority) | Working, pixel-identical to MAME |
| Video: text layer | Working |
| Video: pivot / pixel layer | **Stubbed** — Ray Force only ever clears it (checked every run by a self-test row) |
| Sound: 68000 + MB8421 dual-port RAM | Working — runs the real driver |
| Sound: ES5505 "OTIS" sampler, 32 voices | Working, sample-exact vs the model |
| Sound: ES5510 "ESP" DSP | **Host port only** — the presence check passes, the DSP itself is a dry pass-through |
| Sound: MB87078 volume chip | Working — the game's own fades and level |
| 93C46 settings EEPROM + NVRAM save | Working (see *Saving settings*) |
| SDRAM, ROM loading | Working — 12 MB, verified by an on-core checksum every load |

> **If you are running v1.1:** it boots into the diagnostic page instead of
> the game. MiSTer's status word powers up at 0 and the OSD's `Self Test`
> option had `On` as its first entry, so a fresh load got the self test.
> Turn **Self Test** to `Off` in the OSD, or use a build after this note --
> the default is fixed and a released core now boots to the game.

## Known problems

1. **Sprites can be missing or partial in busy scenes — boss transitions,
   heavy attract moments.** This is the most visible defect in the core and
   it is measured, not suspected. The sprite engine draws each screen line
   into a ring of line buffers running ahead of the mixer; when a line's draw
   misses its deadline the mixer composes that line anyway, with whatever
   sprites had arrived. The core counts both, and leaving it in attract for a
   couple of minutes shows:

   ```
   before (ring of 4)  SPRLINE : LATE  3EFA182E   6190 late lines
   after  (ring of 8)  SPRLINE : LATE  3D7703CE    974 late lines
                       (longest line ~15700 clocks; the budget is 3456)
   ```

   **Mostly fixed, not entirely.** Deepening the run-ahead ring from 4 line
   buffers to 8 removed 86 % of it, measured on the same attract sequence
   second by second: the burst that used to add 4,770 late lines at t=56 s is
   now zero, and the total falls from 6,190 to 974.

   What is left is not a buffering problem and no ring depth will fix it. A
   ring of 8 banks 7 spare lines plus the line's own budget -- 27,648 clocks,
   comfortably more than the 15,722 the worst single line needs -- so any one
   heavy line is now covered. The residual is *runs* of consecutive heavy
   lines, where the draw is simply too slow in aggregate: thirty lines
   needing ~8,000 clocks each is 240,000 against the 103,680 those thirty
   lines are allotted. That is a fetch-bandwidth ceiling in the sprite
   graphics path, and the structural answer is to fetch faster -- more
   outstanding SDRAM requests, or moving sprite graphics to DDR3 where they
   would not contend with the playfields at all.

   Note what is NOT wrong: `SPR REC : DROP` stays at zero, so the sprite list
   and the record store are keeping up — every sprite row the frame asked for
   was built. It is the per-line **fetch and draw** that misses its deadline,
   which points at SDRAM contention rather than at capacity.

   You will see this as sprites flickering or vanishing for a frame where a
   lot is on screen at once. It has been present in every build so far
   (including the first release), and it went unnoticed because those
   counters only arrived recently and every earlier reading was taken
   seconds after a core load, when they are still zero. The Verilator bench
   that models a hardware-like fetch turnaround (`make -C sim pipe-lat`)
   reports **zero** late lines, so the bench's latency model is optimistic
   and wants recalibrating against these numbers before anything is changed.

2. **The ES5510 DSP is not emulated**, only its host port. Measured impact:
   the dry sampler mix correlates **0.95–0.99** with MAME's full output across
   the whole soundtrack, so what the DSP adds is at most a faint residual. If
   something sounds thin against MAME, this is why.
3. **Sprites lag the playfields by one frame; MAME uses two.** Visible, if at
   all, as sprites leading the scroll by a frame.
4. **NVRAM only saves when you open the OSD.** That is MiSTer's design, not
   the core's — see *Saving settings*.
5. **Untested on hardware**: the *Gunlock* and *Ray Force (Japan)* MRAs, the
   60 Hz refresh option, and the analog stick. All three are built and
   believed correct; none has been exercised on a board.
6. The pivot/pixel layer stub is the one thing that ties this core to Ray
   Force — see [Other F3 games](#other-f3-games).

## What is verified, and what is not

The core is checked against MAME, so it is worth being precise about which
parts of MAME that covers. Measured over **7,680 line-configurations across
30 dumped frames** of Ray Force:

| F3 feature | Ray Force uses it | State here |
|---|---|---|
| Line zoom (per-line X/Y scale) | **Heavily** — 7,485 of 30,720 playfield-lines at a scale other than 1:1 | Verified: the 15 pixel-identical frames include it |
| Blending modes 1 and 2 | **Rarely** — 120 of 30,720 playfield-lines (0.4 %) | Exercised but thinly. The likeliest place for an unnoticed difference |
| Column scroll, per-line priority, palette offset | Constantly | Verified |
| Mosaic | **Never** (`x_sample_enable` false on every line) | Implemented, follows the model, but has no dump coverage |
| Clip planes | **Never** (no plane ever set) | Implemented; MAME's several-inverted-planes case is deliberately not reproduced |
| Pivot / pixel layer | Only cleared, never drawn | Stubbed, and a self-test row counts non-zero writes every run |
| Sprite trails | Never | Not implemented |

### Two Ray Force-specific gaps, from MAME's own notes

Searching MAME's source and issue history for this game rather than for the
board turns up two things that matter here, both confirmed against our dumps:

**1. The palette-add effect is implemented but never verified.** MAME's PR
#10943 ("line ram palette add effect") names **"rayforce stage 5 intro"** as
a place it is used. This core implements it (`pf_pal_add`, the line-RAM
0x9000 section), but **every one of the 30,720 playfield-lines in the dumped
frames has `pal_add = 0`** — the dumps are boot, title and attract, and
stage 5 is deep in a play session. So the code is there, follows the model,
and has never been compared against MAME on a frame that actually uses it.
Dumping a stage 5 intro frame and running `make -C sim mix-all` against it is
the single most valuable verification left for this game.

**2. An unknown palette bit that MAME names Gunlock for.** In the 0x6400
effect field, MAME comments `x8xx = ??? seems to affect the palette of a
single layer(??) (gunlock)` and notes `gunlock:78` — and its code logs
"unknown effect bits set" for anything that is not 0x70, i.e. **for Gunlock's
0x78**. MAME does not emulate it (`palette interpretation [unimplemented]`).
Our dumps only ever show `0x00` (7,650 lines) and the benign `0x70` (30
lines), so the scene that sets 0x78 is not covered here either. This core
latches the field and, like MAME, acts on none of it — so we match MAME, and
both may differ from the real board in whatever scene sets that bit.

Neither is a defect against MAME. Both are places where "pixel-identical to
MAME" is a narrower claim than it sounds.

The MAME source this was written against is **current**: `taito_f3_v.cpp` and
`taito_f3.h` are byte-identical to MAME master as of this release, including
the April 2024 video rewrite, and `taito_f3.cpp` differs only in API
tidy-ups and manufacturer strings — nothing behavioural, and nothing that
touches Gunlock/Ray Force.

Uncertainties inherited from MAME, which no amount of diffing against it can
resolve, all flagged in its own source: `0x0800` marking the VRAM layer
opaque and `0x2000` enabling "garbage pixels" are both marked *unemulated*;
the priority-conflict behaviour where "the second layer can reset part of the
state" is described as a hardware feature-or-bug; and the timer register at
`0x4C0000` that configures a pseudo-hblank interrupt is a TODO. Ray Force
writes 0 to that last one, so it costs nothing here.

## How to use it

1. Copy `releases/Rayforce_20260828.rbf` to `/media/fat/_Arcade/cores/` on the
   MiSTer SD card.
2. Copy the `.mra` you want from `releases/` to `/media/fat/_Arcade/`.
   (`releases/experimental/` is work in progress and does not boot — see the
   README in there.)
3. Put the MAME ROM zip in `/media/fat/games/mame/`. The MRAs accept
   `rayforce.zip` or `gunlock.zip` — parts are matched **by CRC**, so the
   layout inside the zip does not matter.
4. Pick the game from the MiSTer arcade menu.

| MRA | Region | Differs by |
|---|---|---|
| `Ray Force.mra` | US | `d66-25.ic35` |
| `Gunlock.mra` | World / Europe | `d66-24.ic35` |
| `Ray Force (Japan).mra` | Japan | `d66-20.ic35` |

All three share every other ROM; the region changes the title and the notice
screen.

## Controls

| Gamepad | Action |
|---|---|
| D-pad **or left analog stick** | Move |
| A | Shot |
| B | Bomb (lock-on laser) |
| R | Start |
| L | Insert coin |
| Select | Service |
| Start | Pause |

The left analog stick works alongside the d-pad — it sets a direction past
about 38 % of full deflection. If it does nothing, check MiSTer's own input
mapping first: the stick has to be assigned under *Define analog joystick*, or
MiSTer never sends the axes to any core.

Input latency in the core is zero-added: the joystick word reaches the CPU's
port read through combinational logic only, with no pipeline stage and no
per-frame sampling. The one frame of latency that does exist is MiSTer's
rotation framebuffer — see below.

## Video options

**Rotate** — the cabinet monitor is vertical. **CW (TATE)** is the default and
is the right way up; CCW is upside down for this game, because Ray Force runs
with the F3 flipscreen bit permanently set and the raster the core produces is
already inverted. **None** leaves the picture in raster order.

Rotation goes through MiSTer's DDR3 framebuffer, which costs **one frame of
latency**. `Rotate = None`, and the analog VGA output (which stays in raster
order deliberately, for a physically rotated CRT), avoid it.

**Flip Screen** — 180° on the rotated output. Unlike some cores this is *not*
done in the core's raster: Ray Force's own flipscreen bit is already set and
the sprite engine takes its flip from the sprite command word, so flipping the
renderer would turn the playfields over and leave the sprites upright. It
therefore applies when rotation is on, and does nothing with `Rotate = None`.

**Aspect ratio**, **Scandoubler Fx** (None / HQ2x / CRT 25 % / 50 % / 75 %) and
**Stereo Mix** (None / 25 % / 50 % / 100 %) are the usual MiSTer options. The
ES5505 pans its voices, so Stereo Mix is a real choice on headphones.

**Refresh Rate** — native is 262 lines at **58.94 Hz**, which nearly every
15 kHz display holds. The **60Hz** option trims the frame to 257 lines; the
game paces itself off the vblank interrupt, so it then runs ~1.8 % fast. Leave
it on native unless your display needs it. *(Verified in simulation; never
watched on a real display.)*

**Pause When OSD Open** — freezes both CPUs while the menu is up, so the music
stops with the game.

## The arcade board's own service menu

**The F3 board has no DIP switches.** There is no DIP bank on the PCB and none
in MAME's driver: difficulty, lives, coinage, free play and screen flip all
live in the game's own service menu and are stored in the 93C46 EEPROM.

Turn on **Service Mode** in the OSD (it is the cabinet TEST switch) and reset
to reach it.

## Saving settings

The MRAs declare `<nvram index="254" size="128"/>`, so MiSTer loads
`/media/fat/config/nvram/<mra name>.nvm` into the EEPROM after the ROMs and
writes it back out again when asked.

MiSTer only performs that write-back **when you open the OSD** (or pick *Save
settings*). So the sequence is: change what you want in Service Mode, leave it,
**open the OSD once**, and the file appears. The game itself only writes the
EEPROM when a setting actually changes — during a normal boot and attract it
only reads it — so a `.nvm` will not appear until you have changed something.

## Built-in self test

The core carries a 28-row self-test page covering the ROM load and checksum,
the SDRAM, the CPU write stream, every video RAM, the interrupt rates, the
video pipeline's per-frame counters, the sprite engine's record and timing
margins, and the sound board. It is **on by default** (`Self Test` in the OSD)
and the same page is streamed over the DE10-Nano's UART, which is how the core
is tested without anyone watching a monitor:

```sh
python3 tools/rf_uart.py -t 12          # the page, over the serial port
```

`UART Debug` switches that port between the page, the CPU write ring, the
sound-chip write ring, and the **Audio Ring** — a capture of the core's own
audio output, which `tools/rf_audio_match.py` correlates against MAME's mix.
That is how "the sound is right" was established without an ear in the room.

## Building it yourself

Quartus Prime Lite **17.0.2** (the version the MiSTer framework targets).

```sh
./build.sh          # ~32 minutes; writes output_files/Rayforce.rbf
```

`build.sh` runs the compile under a systemd scope with a memory cap so a
runaway fitter cannot take the machine down, prints a phase/progress line, and
gates on both a produced bitstream and the timing report.

The Verilator benches are the core's real regression suite and need no FPGA:

```sh
make -C sim line-all pf-all mix-all      # video, against MAME's own frames
make -C sim spr-all spr-line-all spr-ghost
make -C sim pipe pipe-60 pipe-lat        # the raster pipeline under load
make -C sim es5505 es5505-rw             # the sampler, incl. host reads
```

They compare against reference data produced from MAME by the Lua oracles in
`tools/`; regenerate that data with `tools/oracle_f3dump.lua` (video) and
`tools/oracle_en_dump.lua` (sound). The dumps are not in the repository — they
are hundreds of megabytes — and neither are the MAME source files the core was
written against.

## Other F3 games

The F3 library is **35 distinct games across 100 ROM sets**, and they differ
from each other by remarkably little. From MAME's driver:

- **Four machine configurations** (`f3`, `f3_224a`, `f3_224b`, `f3_224c`) that
  differ *only* in where the visible raster starts and how tall it is — 232
  lines from line 24, or 224 from 31, 32 or 24.
- **Two per-game video quirks**: `extend` (0/1, the playfield RAM layout) and
  `sprite_lag` (0, 1 or 2 frames).
- **Orientation**: ROT0, ROT90 or ROT270.
- **ROM footprint from 9.8 MB (Arkanoid Returns) to 49 MB (Kirameki Star
  Road)**, which is what decides how many games a given SDRAM module can hold.
  Ray Force is 11.5 MB as this core loads it.

**Elevator Action Returns runs** — it boots, plays, and draws sprites and
playfields, with the sound CPU streaming and one vblank acknowledge per
frame. All ten sampled frames match MAME pixel for pixel across the
full 232-line visarea (`make -C sim ear-pipe-all`, 74,240 pixels each). It
stays in `releases/experimental/` because ten frames of attract and
character select are not a playthrough, the pivot layer is still a mirror
rather than real RAM, and its sound has never been correlated the way Ray
Force's was.

Getting there turned up a pattern worth naming: **every one of its rendering
defects was a Ray Force dimension frozen into the RTL as a constant.** The
board is one chipset running 35 games, so anything sized from a ROM region or
a visarea has to be a parameter.

- **Graphics codes were 14 bits.** That is exactly right for Ray Force, whose
  sprite and tile regions hold 16,384 elements each — and wrong for Elevator
  Action, whose regions are 4 MB and hold 32,768. MAME builds a 17-bit sprite
  code and uses all 16 bits of the tile word. The visible symptom was oddly
  specific: on the character-select screen every panel, bar and glyph was
  perfect while the three portraits drew as scattered fragments of in-game
  sprites, because 60 of the 72 over-limit sprites in that frame *were* the
  portraits.
- **The sprite cull window was hardcoded twice**, in the list walker and
  again in the row expander, to Ray Force's 224 lines from line 31. Elevator
  Action shows 232 from line 24, so every sprite row on the 8 lines outside
  that window was silently dropped. Both now follow the `vis_mode` the game
  config byte already carried.
- **The bench never looked.** `sim/pipe_tb.cpp` compared Ray Force's window
  whatever game it was handed, so those 8 lines went unchecked — widening it
  is what exposed the cull bug at all. A bench with one game's dimensions
  baked in cannot fail on the lines it never reads.

Two things also had to be built for it, and both are instructive about why Ray
Force never needed them:

- **Real pivot (pixel-layer) RAM.** Ray Force only ever *clears* that RAM, so
  a read-as-zero stub survived — and its 64 KB of block RAM was spent on the
  sound board instead. Elevator Action's power-on self test writes
  `FF/AA/55/00` to every RAM and reads each location straight back; a stub
  cannot pass that. It now has 8 KB mirrored across the 64 KB window, because
  64 KB is 51 M10Ks and about 20 were free. The mirror passes because the test
  verifies each location immediately after writing it.
- **The watchdog.** Elevator Action's boot deliberately parks at a `BRA.S *`
  with interrupts masked and waits for the TC0640FIO watchdog to reboot the
  board — traced in MAME, it sits there about two seconds, resets, re-runs its
  self test and carries on. This core ignored writes to `0x4A0000` entirely,
  so it hung there forever. Ray Force never depends on that path.

Both failures were silent hangs rather than error messages, and the game's own
error handler is generic enough to point at the wrong RAM, which is why this
took a while. The full trail is in `HANDOFF.md`.

So most of what a *compatible* second game needs is four small parameters,
which belong in the MRA rather than in the RTL. That is now true: the config
byte carries them, and `vis_mode` reaches both the raster crop and the sprite
cull.

**"Compatible" is doing real work in that sentence, though.** Counting
MAME's own `f3_config_table` (33 games):

| Still hardwired here | How many games it blocks |
|---|---|
| `extend` is tied to 1 | **15 of 33** are `extend = 0` |
| sprite lag is tied to 1 | 7 games want 2, 3 want 0 — including **both games this core ships** |
| pivot layer is an 8 KB mirror | every game that actually draws on it |
| 18.5 MB SDRAM map | Kaiser Knuckle and Kirameki Star Road are 48-49 MB |

Config bits [2] and [4:3] are reserved for the first two and are not read
yet. `extend` is the awkward one: it is hardcoded in the Python model
(`EXTEND = True`) as well as in the RTL, so there is no verified oracle for
the non-extend path — that work starts before any RTL does. And the sprite
lag row is not hypothetical future work: MAME says lag 2 for both Gunlock and
Elevator Action, the engine does 1, and the benches hide it because they hand
the sprite RAM over from frame-2 themselves.

So the architecture generalises; the coverage does not yet. The remaining
architectural item is still the biggest one:

**The pivot (pixel) layer has to come back.** Ray Force never draws it — it
only clears it, which this core proves on every run with a self-test row — so
the layer's 64 KB of block RAM was spent on the sound board's RAM instead.
That is the exception, not the rule: measured over 2,319 frames, **Elevator
Action Returns writes the pivot RAM 131,072 times, 98,304 of them non-zero,
touching all 256 pages**. Holding both that and the sound RAM needs 128 KB of
block RAM, and the device is at 95 % of its M10K blocks, so one of them — or
the 128 KB main RAM, the largest single block — has to move to SDRAM behind a
cache. `rtl/rf_video_pivot.sv` itself is already written and verified.

Encouragingly, the same measurement says **no F3 game examined uses sprite
"trails"**, so the one sprite feature this core omits costs nothing.

## Credits and licence

- **MAME** — the reference for every part of this core. The video, sound and
  protection behaviour was ported from and checked against MAME's `taito_f3`
  and `taito_en` drivers and its ES5505/ES5510 devices.
- **TG68K.C** by Tobias Gubener — the 68000/68020 CPU core.
- The **MiSTer** framework and its `sys/` files.

Licensed under the **GNU General Public License v3** — see [LICENSE](LICENSE).
