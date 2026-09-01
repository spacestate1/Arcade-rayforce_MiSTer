# Experimental

Games that run on this core but have not earned the evidence the Ray Force
set has. Each section says what state its game is actually in.

| MRA | ROM zip | State |
|---|---|---|
| Elevator Action Returns | `elvactr.zip` | Plays; video verified against MAME, sound never correlated |
| Bubble Bobble II | `bublbob2.zip` | Plays on hardware; not frame-verified |
| Bubble Memories | `bubblem.zip` | MRA written, never loaded |
| Puzzle Bobble 2 | `pbobble2.zip` | Needs `extend=0`; see below |

All four are horizontal games (MAME ROT0) on a core whose main title is
vertical, so set **Rotate to None** in the OSD for any of them.

## Elevator Action Returns.mra

**It runs, and its picture now matches MAME pixel for pixel.** The game
boots, plays, and draws sprites and playfields; the sound CPU streams to the
ES5505 and the main CPU takes one vblank interrupt per frame. Everything the
ROMs can prove about themselves passes: download size, checksum, SDRAM
readback and the sample-fetch path all match values computed offline from the
MRA, and the 68020's write stream matches MAME's exactly for the first 4096
bus writes.

Measured against MAME frame by frame, over the **full 232-line visarea**:

    make -C sim ear-pipe-all        # playfields + pivot + sprites + mixer
    make -C sim ear-mix-all         # the mixer, sprites/pivot fed from the model
    make -C sim ear-spr-line-all    # the sprite line buffer

    ear-pipe-all      10/10 frames identical   (742,400 pixels)
    ear-mix-all       10/10 frames identical
    ear-spr-line-all   9/10; frame 4200 has 0 pixel diffs, 8 used-flag diffs

Five of those ten frames (3000, 3600, 4200, 4800, 5400) were dumped from MAME
*after* the fixes and never used to develop them, so they are an out-of-sample
check. Ray Force is unaffected: 19/19 on both of its equivalents.

It is still here rather than in `releases/` because:

- **Ten frames are not a game.** They cover attract and the character select,
  not a playthrough. Nothing has been checked past ~90 seconds of emulated
  time, and nothing has been played to the end of a stage on hardware.
- **The pivot (pixel) layer is a mirror, not real RAM** — 8 KB repeated
  across the 64 KB window. It passes this game's power-on RAM test because
  that test reads each location straight back after writing it, and the game
  does not otherwise keep data there, but it is not the real chip.
- **Sound has not been correlated** the way Ray Force's was (which measured
  1.000 against MAME's own mix). The path runs; its accuracy is unmeasured.

Note the model needs `F3_VIS=f3` and the benches need the matching window and
flip: this game's visible raster is the base f3 one, 232 lines from line 24,
where Ray Force uses 224 from line 31, and this game never sets flipscreen
while Ray Force sets it permanently. The `ear-*` targets pass all of that for
you.

### Set Rotate to None

This is a **horizontal** game (MAME ROT0) on a core whose other title is
vertical, so set Rotate to None in the OSD.

See "Elevator Action Returns" in `HANDOFF.md` for how it got here, including
the three defects that turned out to be Ray Force's dimensions frozen into
the RTL as constants.

---

## Bubble Bobble II.mra

**Runs on hardware** (2026-08-31), and it needed no RTL change at all: an MRA
and a config byte, which is what the universal F3 map and the game-config
byte were built for. Title screen, character select, cutscenes and play all
draw correctly.

It shares more with Ray Force than Elevator Action Returns does. MAME runs it
on `f3_224a`, the same 224-lines-from-31 crop Ray Force uses, and the same
playfield `extend` setting, so its config byte's visarea field is Ray Force's
own value. Its ROM shape is Ray Force's too, padding included.

**Not frame-verified.** The reference model is exact on only 3 of 10 dumped
frames for this game, so there is nothing trustworthy yet to check the RTL
against. The gap is in the sprite block/multi path, which these games set on
roughly 97 % of sprites where Ray Force sets it on 2 %. Close the model first;
see `PREP-BUBBLE.md`.

Horizontal game: set Rotate to None.

## Bubble Memories.mra

**Untested.** The MRA is written and assembles to the same 18.5 MB stream as
every other set, and all ten self-test expectations are measured, but it has
never been loaded on a board.

Its one structural novelty is that it has **no `sprites_hi` ROM** at all
(MAME declares the region `EMPTY_SPRITE_HIDATA`), so its sprites are 4bpp
where every other set here is 6bpp. That looked like the risk and is not: the
reference model renders three of its frames pixel-identical to MAME with that
region all zeros.

Horizontal game: set Rotate to None.

## Puzzle Bobble 2.mra

The first **`extend=0`** game here: eight 32x32 playfields instead of four
64x32, which changes playfield addressing rather than a size somewhere. The
config byte asks for it with bit [2] set (`0x87`). Note that bit's sense is
inverted against MAME's "extend" naming, because every MRA written before it
went live carries 0 there and every one of those games is extend=1.

This is the Japanese set (`pbobble2j`), not the parent. MAME's parent
`pbobble2` runs `init_pbobbl2p`, which patches the program ROM at
0x40090/0x40094 to NOP a branch its own comment calls "protection check?? or
some kind of checksum fail?". No such patch can exist here, and real hardware
presumably ran the ROM as dumped, so the unpatched set is the honest target.

It also has no `sprites_hi`, but it does have `tilemap_hi`.

Horizontal game: set Rotate to None.
