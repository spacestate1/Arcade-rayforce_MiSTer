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

The most recent build meets timing on every clock.

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

## Known problems

1. **The ES5510 DSP is not emulated**, only its host port. Measured impact:
   the dry sampler mix correlates **0.95–0.99** with MAME's full output across
   the whole soundtrack, so what the DSP adds is at most a faint residual. If
   something sounds thin against MAME, this is why.
2. **Sprites lag the playfields by one frame; MAME uses two.** Visible, if at
   all, as sprites leading the scroll by a frame.
3. **NVRAM only saves when you open the OSD.** That is MiSTer's design, not
   the core's — see *Saving settings*.
4. **Untested on hardware**: the *Gunlock* and *Ray Force (Japan)* MRAs, the
   60 Hz refresh option, and the analog stick. All three are built and
   believed correct; none has been exercised on a board.
5. The pivot/pixel layer stub is the one thing that ties this core to Ray
   Force — see [Other F3 games](#other-f3-games).

## How to use it

1. Copy `releases/Rayforce_<date>.rbf` to `/media/fat/_Arcade/cores/` on the
   MiSTer SD card.
2. Copy the `.mra` you want from `releases/` to `/media/fat/_Arcade/`.
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

So most of what a second game needs is four small parameters, which belong in
the MRA rather than in the RTL. The real work is one architectural item:

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
