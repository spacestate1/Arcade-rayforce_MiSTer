-- Taito F3 sound-board read oracle (Phase 3): everything the sound 68000
-- READS from the Ensoniq board -- ES5505 registers (200000-20001F), the
-- sample-bank registers, the MB87078 and the ES5510 host port -- with the
-- ES5505 page in force and the frame number. oracle_en_dump.lua is the
-- write side; this is the other half, and it is not optional: the driver
-- reads its sound table (pointer + 12-char name per entry, "COIN",
-- "EXTEND", ...) out of the first bytes of d66-01 THROUGH the ES5505, by
-- parking voice 10 (FC 0x40, K1/K2 ffff, CR fc06), stepping ACC one byte
-- at a time, writing 7fff to O1(n-1) on the high page as a sentinel and
-- polling that register (page 0x2a, offset 0x0c) until the chip has
-- fetched the byte. ~77 reads a frame for the whole run, and ~750 reads of
-- the control register (STOP bits) on voices 23-31 while music plays. An
-- RTL that answers reads with a constant feeds the driver a table of 0xF0
-- bytes and every sound it plays afterwards is wrong (2026-08-28).
--
-- usage:
--   ENDUMP_DIR=dump/en4 SDL_VIDEODRIVER=dummy mame rayforce -rompath . \
--        -video none -sound none -nothrottle -norotate \
--        -autoboot_script tools/oracle_en_reads.lua -seconds_to_run 40
--   -> $ENDUMP_DIR/en_reads.txt: "TAG offset value mask pgNN fFRAME"
--
-- Time is the frame count: manager.machine.time is not safe inside a
-- memory tap (MAME aborts).
local dir = os.getenv("ENDUMP_DIR") or "."
local f = io.open(dir .. "/en_reads.txt", "w")
local snd = manager.machine.devices[":taito_en:audiocpu"].spaces["program"]
local n, frame, page = 0, 0, 0
_G.RT_KEEP = _G.RT_KEEP or {}
local function tap(name, lo, hi)
    table.insert(_G.RT_KEEP, snd:install_read_tap(lo, hi, name, function(offset, data, mask)
        n = n + 1
        if n <= 2000000 then f:write(string.format("%s %06x %04x %04x pg%02x f%d\n", name, offset, data, mask, page, frame)) end
    end))
end
tap("ES", 0x200000, 0x20001f)
tap("BK", 0x300000, 0x30003f)
tap("VOL", 0x340000, 0x340003)
tap("ESP", 0x260000, 0x26000f)
table.insert(_G.RT_KEEP, snd:install_write_tap(0x20001e, 0x20001f, "PG", function(offset, data, mask)
    if offset == 0x20001e then
        if (mask & 0x00ff) ~= 0 then page = data & 0x7f else page = (data >> 8) & 0x7f end
    end
end))
table.insert(_G.RT_KEEP, emu.add_machine_frame_notifier(function() frame = frame + 1; f:flush() end))
table.insert(_G.RT_KEEP, emu.add_machine_stop_notifier(function() f:write(string.format("=== %d reads, %d frames\n", n, frame)); f:close() end))
