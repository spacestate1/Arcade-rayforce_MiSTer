# Experimental — runs, but not accurate yet

## Elevator Action Returns.mra

**It runs.** The game boots, plays, and draws sprites and playfields; the
sound CPU streams to the ES5505 and the main CPU takes one vblank interrupt
per frame. Everything the ROMs can prove about themselves passes: download
size, checksum, SDRAM readback and the sample-fetch path all match values
computed offline from the MRA, and the 68020's write stream matches MAME's
exactly for the first 4096 bus writes.

It is here rather than in `releases/` because it is **not accurate yet**.
Measured against MAME frame by frame:

    make -C sim ear-mix-all

    frame   600: 67434/74240 pixels identical   (91 %)
    frame   900: 65371/74240                    (88 %)
    frame  1200:   269/74240                    (badly wrong)
    frame  1800: 60444/74240                    (81 %)
    frame  2400:   276/74240                    (badly wrong)

Two frames being near-zero rather than slightly off suggests something global
to those frames -- a background or palette difference -- rather than scattered
sprite errors. That is the next thing to chase, and the bench above is set up
for it. Note the model needs `F3_VIS=f3`: this game's visible raster is the
base f3 one, 232 lines from line 24, where Ray Force uses 224 from line 31.

See "Elevator Action Returns" in `HANDOFF.md` for how it got here.
