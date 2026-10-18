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

return Natives
