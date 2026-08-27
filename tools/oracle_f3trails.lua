-- Does Ray Force ever use sprite trails?
--
-- The answer decides the sprite architecture. MAME keeps a full-screen sprite
-- framebuffer because the F3 can skip clearing it between frames ("trails",
-- special command word 5 bit 1). A framebuffer is ~160 BRAM blocks, which the
-- DE10-Nano does not have spare; without trails, sprites can render per
-- scanline into a line buffer instead and the problem disappears.
--
-- 30 frames of attract mode said "never set", but that proves very little, so
-- this drives the inputs to get into a real game and watches every frame.
--
-- It walks the sprite list the same way get_sprite_info() does -- following
-- bank switches and jump commands -- rather than scanning sprite RAM flat,
-- because a command word only counts if the list actually reaches it.
--
-- usage:
--   F3T_SECONDS=240 mame rayforce -rompath . -video none -sound none \
--       -nothrottle -autoboot_script tools/oracle_f3trails.lua -seconds_to_run 240

_G.F3T_KEEP = _G.F3T_KEEP or {}

local spr = manager.machine.memory.shares[":spriteram"]
local ports = manager.machine.ioport.ports

local function field(tag, mask)
    local p = ports[tag]
    if not p then return nil end
    for _, f in pairs(p.fields) do
        if f.mask == mask then return f end
    end
    return nil
end

-- IN.0: bit 12 START1, bits 0/1 P1 buttons.  IN.1: bits 0-3 P1 joystick.
-- EEPROMIN bit 4 COIN1.  All active low; set_value(1) presses.
local f_coin  = field(":EEPROMIN", 0x10)
local f_start = field(":IN.0", 0x00001000)
local f_shot  = field(":IN.0", 0x00000001)
local f_bomb  = field(":IN.0", 0x00000002)
local f_up    = field(":IN.1", 0x00000001)
local f_down  = field(":IN.1", 0x00000002)
local f_left  = field(":IN.1", 0x00000004)
local f_right = field(":IN.1", 0x00000008)

-- Input driving is OFF unless F3T_PLAY is set. The first run of this script
-- drove the inputs unconditionally and reported zero sprites for 17k frames:
-- set_value() on these fields does not mean what "press" meant here, so every
-- control was effectively jammed and the game never ran. A result from a
-- wedged game is worse than no result, so the default is hands-off attract.
local PLAY = os.getenv("F3T_PLAY")

local function press(f, on)
    if PLAY and f then f:set_value(on and 1 or 0) end
end

local n = 0
local trails_frames = 0
local first_trail = nil
local max_sprites = 0
local planes_seen, banks_seen, cmds_seen = {}, {}, {}
local bank = false

table.insert(_G.F3T_KEEP, emu.add_machine_frame_notifier(function()
    n = n + 1

    -- Coin at frame 120, start at 180, then hold shot and sweep left/right so
    -- the ship actually plays rather than sitting in one column dying.
    press(f_coin,  n >= 120 and n < 130)
    press(f_start, n >= 180 and n < 190)
    press(f_shot,  n > 200 and (n % 4) < 2)
    press(f_bomb,  n > 200 and (n % 240) < 3)
    local phase = (n // 90) % 4
    press(f_left,  n > 200 and phase == 1)
    press(f_right, n > 200 and phase == 3)
    press(f_up,    n > 200 and phase == 0)
    press(f_down,  n > 200 and phase == 2)

    -- Walk the list exactly as get_sprite_info does.
    local offs, total, count = 0, 0, 0
    local trail_here = false
    while offs < 0x400 and total < 0x400 do
        total = total + 1
        local base = (bank and 0x4000 or 0) + offs * 8
        local w3 = spr:read_u16(2 * (base + 3))
        local w5 = spr:read_u16(2 * (base + 5))
        local w6 = spr:read_u16(2 * (base + 6))
        local w0 = spr:read_u16(2 * (base + 0))

        if (w3 & 0x8000) ~= 0 then                 -- special command
            cmds_seen[w5] = (cmds_seen[w5] or 0) + 1
            planes_seen[(w5 >> 8) & 3] = true
            if (w5 & 0x0002) ~= 0 then trail_here = true end
            bank = (w5 & 1) ~= 0
            banks_seen[bank and 1 or 0] = true
        end

        local nxt = offs + 1
        if (w6 & 0x8000) ~= 0 then
            local t = w6 & 0x3FF
            if t == offs then break end
            nxt = t
        end
        if w0 ~= 0 then count = count + 1 end
        offs = nxt
    end

    if count > max_sprites then max_sprites = count end
    if trail_here then
        trails_frames = trails_frames + 1
        if not first_trail then
            first_trail = n
            print(string.format("TRAILS SET at frame %d", n))
            io.stdout:flush()
        end
    end

    if n % 1800 == 0 then
        print(string.format("frame %6d  trails_frames=%d  max_sprites=%d",
                            n, trails_frames, max_sprites))
        io.stdout:flush()
    end
end))

table.insert(_G.F3T_KEEP, emu.add_machine_stop_notifier(function()
    print("=== F3 SPRITE TRAILS REPORT ===")
    print(string.format("frames scanned    : %d", n))
    print(string.format("frames with trails: %d", trails_frames))
    print(string.format("first trail frame : %s", tostring(first_trail)))
    print(string.format("max sprites/frame : %d", max_sprites))
    local p = {}
    for k in pairs(planes_seen) do p[#p+1] = k end
    table.sort(p)
    print("extra_planes seen : " .. table.concat(p, ","))
    local b = {}
    for k in pairs(banks_seen) do b[#b+1] = k end
    table.sort(b)
    print("banks seen        : " .. table.concat(b, ","))
    print("command words seen:")
    local keys = {}
    for k in pairs(cmds_seen) do keys[#keys+1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        print(string.format("   %04x  x%d%s", k, cmds_seen[k],
              ((k & 2) ~= 0) and "   <-- TRAILS" or ""))
    end
    io.stdout:flush()
end))
