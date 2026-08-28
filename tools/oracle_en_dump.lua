-- Taito F3 sound-board oracle (Phase 3, stage 0).
--
-- Taps everything the sound 68000 says to the Ensoniq board -- ES5505
-- registers, sample bank select, MB87078 volume, ES5510 host port -- as a
-- stream stamped with the frame number, in the order written. That stream
-- is the spec the RTL sound board is checked against, the way the main
-- CPU's write stream proved the 68020 in Phase 1: if the FPGA's 68000 runs
-- the sound program correctly it writes the same things in the same order.
--
-- Also: which 256-byte pages of the 64 KB sound RAM are ever written (the
-- BRAM decision in ROADMAP.md Phase 3 hangs on that number), and both sides
-- of the MB8421 dual-port RAM, i.e. the command protocol between the CPUs.
--
-- Run with -wavwrite for the mixed output the ES5505 model is proven against.
--
-- usage:
--   ENDUMP_DIR=dump mame rayforce -rompath . -video none -sound none \
--        -nothrottle -norotate -autoboot_script tools/oracle_en_dump.lua \
--        -seconds_to_run 60 -wavwrite dump/en_mix.wav

_G.ENDUMP_KEEP = _G.ENDUMP_KEEP or {}

local dir = os.getenv("ENDUMP_DIR") or "dump"
local f   = io.open(dir .. "/en_writes.txt", "w")
local frame = 0
local nwrites = 0
local pages = {}          -- sound RAM pages touched (256 bytes each)
for i = 0, 255 do pages[i] = 0 end

local snd = manager.machine.devices[":taito_en:audiocpu"].spaces["program"]
-- emulated time in seconds (attotime), for placing writes against samples
local function machine_time()
    local ok, t = pcall(function() return manager.machine.time end)
    if not ok or t == nil then return 0 end
    local ok2, d = pcall(function() return t.seconds + t.attoseconds / 1e18 end)
    if ok2 then return d end
    return 0
end
local cpu = manager.machine.devices[":maincpu"].spaces["program"]

local function tap(space, lo, hi, name, tagname)
    table.insert(_G.ENDUMP_KEEP, space:install_write_tap(lo, hi, tagname,
        function(offset, data, mask)
            f:write(string.format("%d %s %06x %04x %04x %.7f\n", frame, name, offset, data, mask, machine_time()))
            nwrites = nwrites + 1
        end))
end

-- the chips, as the sound CPU sees them (16-bit space, mask = byte lanes)
tap(snd, 0x200000, 0x20001f, "ES", "en_es5505")
-- ES5505 READS too (the driver reads the chip: it parks a voice and reads
-- sample bytes back through a filter register -- session b2's finding), in
-- the same stream with the same time stamps, tagged ESR
table.insert(_G.ENDUMP_KEEP, snd:install_read_tap(0x200000, 0x20001f, "en_es5505_r",
    function(offset, data, mask)
        f:write(string.format("%d ESR %06x %04x %04x %.7f\n", frame, offset, data, mask, machine_time()))
    end))
tap(snd, 0x300000, 0x30003f, "BK", "en_bank")
tap(snd, 0x340000, 0x340003, "VL", "en_volume")
tap(snd, 0x260000, 0x2601ff, "DSP", "en_es5510")
tap(snd, 0x280000, 0x28001f, "DU",  "en_duart")      -- the timer is the driver's heartbeat
-- the dual-port RAM, both sides (sound side is the high byte lane)
tap(snd, 0x140000, 0x140fff, "DPS", "en_dpram_snd")
-- 32-bit main CPU side: one access can carry up to 4 bytes
table.insert(_G.ENDUMP_KEEP, cpu:install_write_tap(0xc00000, 0xc007ff, "en_dpram_main",
    function(offset, data, mask)
        f:write(string.format("%d DPM %06x %08x %08x\n", frame, offset, data, mask))
        nwrites = nwrites + 1
    end))
-- sound reset from the main CPU
table.insert(_G.ENDUMP_KEEP, cpu:install_write_tap(0xc80000, 0xc80103, "en_reset",
    function(offset, data, mask)
        f:write(string.format("%d RST %06x %08x %08x\n", frame, offset, data, mask))
    end))
-- sound RAM footprint (the mirror at FF0000 is the same RAM): pages READ,
-- and pages written after boot -- the boot clear touches all 64 KB, which
-- says nothing about the working set a smaller RAM would have to hold
local BOOT = 300
local pages_r = {}
for i = 0, 255 do pages_r[i] = 0 end
local function wtap(offset) if frame > BOOT then pages[(offset >> 8) & 0xff] = 1 end end
local function rtap(offset) if frame > BOOT then pages_r[(offset >> 8) & 0xff] = 1 end end
table.insert(_G.ENDUMP_KEEP, snd:install_write_tap(0x000000, 0x03ffff, "en_ram_lo",
    function(offset, data, mask) wtap(offset) end))
table.insert(_G.ENDUMP_KEEP, snd:install_write_tap(0xff0000, 0xffffff, "en_ram_hi",
    function(offset, data, mask) wtap(offset) end))
table.insert(_G.ENDUMP_KEEP, snd:install_read_tap(0x000000, 0x03ffff, "en_ram_lo_r",
    function(offset, data, mask) rtap(offset) end))
table.insert(_G.ENDUMP_KEEP, snd:install_read_tap(0xff0000, 0xffffff, "en_ram_hi_r",
    function(offset, data, mask) rtap(offset) end))

table.insert(_G.ENDUMP_KEEP, emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if frame % 600 == 0 then
        local n = 0
        for i = 0, 255 do n = n + pages[i] end
        print(string.format("frame %d: %d writes, %d/256 sound RAM pages touched", frame, nwrites, n))
        io.stdout:flush(); f:flush()
    end
end))

table.insert(_G.ENDUMP_KEEP, emu.add_machine_stop_notifier(function()
    local n = 0
    local nr = 0
    local pf = io.open(dir .. "/en_ram_pages.txt", "w")
    for i = 0, 255 do
        n = n + pages[i]; nr = nr + pages_r[i]
        if pages[i] == 1 or pages_r[i] == 1 then
            pf:write(string.format("%02x %s%s\n", i, pages_r[i] == 1 and "r" or "-", pages[i] == 1 and "w" or "-"))
        end
    end
    pf:close()
    print(string.format("=== EN DUMP: %d frames, %d writes, sound RAM pages after frame %d: %d read, %d written (of 256 x 256 B) ===",
                        frame, nwrites, BOOT, nr, n))
    f:close()
end))
