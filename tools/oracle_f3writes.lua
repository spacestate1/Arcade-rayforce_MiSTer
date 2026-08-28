-- Taito F3 main-CPU write-stream oracle (Phase 0/1 method, for any F3 game).
--
-- Emits exactly the lines tools/rf_write_compare.py parses out of MAME's
-- debugger watchpoint log:
--
--     WR AAAAAAAA DDDDDDDD sz{8,16,32}
--
-- so a new game gets the same go/no-go the 68020 spike got: expand to the
-- 16-bit bus operations TG68K performs, fold the hash, and compare with the
-- board's WRITE HASH row (or diff the board's write ring against it).
--
-- The 68020's program space is 32 bits wide, so a tap reports a longword
-- offset and a byte mask; this turns that back into the architectural
-- address and size.
--
--   F3WR_OUT=x.tr F3WR_LIMIT=20000 SDL_VIDEODRIVER=dummy \
--   mame elvactr -rompath ... -video none -sound none -nothrottle -norotate \
--        -autoboot_script tools/oracle_f3writes.lua -seconds_to_run 20
--
-- Validate it on a game whose answer is known before trusting it on one
-- whose is not: Ray Force's first 4096 bus writes hash to 0x10620931.
if _G.F3WR then return end
_G.F3WR = {}
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local f  = io.open(os.getenv("F3WR_OUT") or "f3_writes.tr", "w")
local limit = tonumber(os.getenv("F3WR_LIMIT") or "40000")
local n = 0

-- mask -> {byte offset, shift, size}; anything else is an unaligned access
-- and is written out verbatim as sz32 so the comparer can flag it
local M = {
    [0xFFFFFFFF] = {0, 0,  32},
    [0xFFFF0000] = {0, 16, 16},
    [0x0000FFFF] = {2, 0,  16},
    [0xFF000000] = {0, 24, 8},
    [0x00FF0000] = {1, 16, 8},
    [0x0000FF00] = {2, 8,  8},
    [0x000000FF] = {3, 0,  8},
}

table.insert(_G.F3WR, sp:install_write_tap(0x000000, 0xFFFFFF, "wr", function(offset, data, mask)
    if n >= limit then return end
    local m = M[mask]
    if m then
        f:write(string.format("WR %08X %08X sz%d\n", offset + m[1], (data >> m[2]) & ((1 << m[3]) - 1), m[3]))
    else
        f:write(string.format("WR %08X %08X sz32   ; mask %08X\n", offset, data, mask))
    end
    n = n + 1
    if n % 4096 == 0 then f:flush() end
end))

table.insert(_G.F3WR, emu.add_machine_stop_notifier(function()
    f:write(string.format("=== %d writes\n", n)); f:close()
end))
