-- Measure what an F3 game needs that this core does not have: pivot/pixel
-- layer writes (the core stubs that RAM and puts the sound RAM in its BRAM),
-- sprite "trails" usage, and the extend bit.
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local f = io.open(os.getenv("PROBE_OUT") or "probe.txt", "w")
local frame = 0
local pivot_w, pivot_nz, pivot_pages = 0, 0, {}
local text_w, char_w, spr_w = 0, 0, 0
local trails = 0
_G.PK = _G.PK or {}
table.insert(_G.PK, sp:install_write_tap(0x630000, 0x63ffff, "pivot", function(off, data, mask)
    pivot_w = pivot_w + 1
    if (data & mask) ~= 0 then
        pivot_nz = pivot_nz + 1
        pivot_pages[(off >> 8) & 0xff] = 1
    end
end))
table.insert(_G.PK, sp:install_write_tap(0x61c000, 0x61dfff, "text", function() text_w = text_w + 1 end))
table.insert(_G.PK, sp:install_write_tap(0x61e000, 0x61ffff, "char", function() char_w = char_w + 1 end))
-- sprite RAM: the trails bit is bit 15 of the control word in each 16-byte entry
table.insert(_G.PK, sp:install_write_tap(0x600000, 0x60ffff, "spr", function(off, data, mask)
    spr_w = spr_w + 1
    if (off & 0xf) == 6 and (data & 0x8000) ~= 0 then trails = trails + 1 end
end))
table.insert(_G.PK, emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if frame % 600 == 0 then
        local n = 0; for _ in pairs(pivot_pages) do n = n + 1 end
        print(string.format("frame %d: pivot writes %d (non-zero %d, %d/256 pages), text %d char %d spr %d, trails-bit writes %d",
              frame, pivot_w, pivot_nz, n, text_w, char_w, spr_w, trails))
        io.stdout:flush()
    end
end))
table.insert(_G.PK, emu.add_machine_stop_notifier(function()
    local n = 0; for _ in pairs(pivot_pages) do n = n + 1 end
    f:write(string.format("=== %d frames: pivot writes %d, non-zero %d, pages %d/256; text %d char %d spr %d; trails %d\n",
            frame, pivot_w, pivot_nz, n, text_w, char_w, spr_w, trails))
    f:close()
end))
