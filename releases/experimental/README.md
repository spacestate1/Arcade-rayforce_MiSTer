# Experimental — runs and renders exactly, but not finished

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
