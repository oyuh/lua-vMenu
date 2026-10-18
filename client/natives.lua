-- The part of upstream's vMenu.Legacy.BrokenNatives/NativeFixer.Natives.cs this
-- port needs: natives FiveM Legacy's native database lacks or declares with
-- fewer arguments, called by hash so one call works on both platforms.

local Natives = {}

local function truthy(hash, ...)
    local args = table.pack(...)
    args.n = args.n + 1
    args[args.n] = Citizen.ResultAsInteger()
    return Citizen.InvokeNative(hash, table.unpack(args, 1, args.n)) ~= 0
end

function Natives.is_ped_doing_a_beast_jump(ped)
    return truthy(0x451D05012CCEC234, ped)
end

function Natives.is_ped_landing(ped)
    return truthy(0x412F1364FA066CFB, ped)
end

function Natives.set_beast_jump_this_frame(player)
    Citizen.InvokeNative(0x438822C279B73B93, player)
end

-- Legacy's database drops the third argument, which picks the players to load it for.
function Natives.request_script_audio_bank(bank, over_network, player_bits)
    return truthy(0x2F844A8B08D76685, bank, over_network, player_bits)
end

function Natives.set_ped_move_rate_in_water_override(ped, rate)
    Citizen.InvokeNative(0x0B3E35AC043707D9, ped, rate + 0.0)
end

-- R*'s own snow switches. Cfx's older snow natives break weather transitions.
function Natives.force_global_snow_fx(on)
    Citizen.InvokeNative(0x6E9EF3A33C8899F8, on)
end

function Natives.use_snow_foot_vfx_when_unsheltered(on)
    Citizen.InvokeNative(0xAEEDAD1420C65CC0, on)
end

function Natives.use_snow_wheel_vfx_when_unsheltered(on)
    Citizen.InvokeNative(0x4CC7F0FEA5283FE0, on)
end

function Natives.foot_vfx_set_override_ice_with_snow(on)
    Citizen.InvokeNative(0xA342A3763B3AFB6C, on)
end

-- Legacy's database drops the height range upstream passes.
function Natives.set_vehicle_on_ground_properly(vehicle, range)
    return truthy(0x49733E92263139D1, vehicle, range + 0.0)
end

-- The water surface height straight down from x, y, z, or nil when there is none.
function Natives.test_vertical_probe_against_all_water(x, y, z)
    local result, height = Citizen.InvokeNative(
        0x8974647ED222EA5F,
        x + 0.0,
        y + 0.0,
        z + 0.0,
        0,
        Citizen.PointerValueFloat(),
        Citizen.ResultAsInteger()
    )
    return result == 1 and height or nil
end

-- Legacy's database takes no argument for where the editor was opened from.
function Natives.activate_rockstar_editor(opened_from)
    Citizen.InvokeNative(0x49DA8145672B2725, opened_from)
end

-- The game writes five bars into a struct with one 8 byte slot each. A Lua
-- string over 40 bytes is never shared, so the native can fill this one.
local function hud_stats(hash, item)
    local buffer = string.rep(string.char(0), 64)
    if not truthy(hash, item, buffer) then
        return nil
    end
    local damage, speed, capacity, accuracy, range = string.unpack('<i4 xxxx i4 xxxx i4 xxxx i4 xxxx i4', buffer)
    return { damage = damage, speed = speed, capacity = capacity, accuracy = accuracy, range = range }
end

function Natives.weapon_hud_stats(weapon_hash)
    return hud_stats(0xD92C739EE34C9EBA, weapon_hash)
end

-- A component's bars are signed: a suppressor takes damage away.
function Natives.weapon_component_hud_stats(component_hash)
    return hud_stats(0xB3CAF387AE12E9F8, component_hash)
end

-- Legacy's database drops the last argument, which skips the ground check.
function Natives.create_vehicle(hash, x, y, z, heading, networked, script_host, ignore_ground)
    return Citizen.InvokeNative(
        0xAF35D0D2583051B0,
        hash,
        x + 0.0,
        y + 0.0,
        z + 0.0,
        heading + 0.0,
        networked,
        script_host,
        ignore_ground,
        Citizen.ResultAsInteger()
    )
end

return Natives
