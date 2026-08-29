# Experimental — not working yet

Nothing in here boots. It is kept in the repository because the work is real
and measured, not because it is usable.

## Elevator Action Returns.mra

The same Taito F3 board, and everything up to actually running is verified:
the ROMs load byte-perfect (download size, checksum, SDRAM readback and the
sample-fetch path all match values computed offline from the MRA), and the
68020 executes the game's first 4096 bus writes identically to MAME, byte
lanes included.

It then stops in the game's own power-on self test — parked in its
`WORK RAM ERROR` handler at PC 0x01032C — so no picture is drawn and the
sound CPU is never released. Loading it gives a black screen.

See "Elevator Action Returns" in `HANDOFF.md` for the full trail, including
the two candidate causes already tested on hardware and eliminated.
