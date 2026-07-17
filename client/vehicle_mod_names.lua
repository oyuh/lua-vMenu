-- Port of CitizenFX.Core's VehicleMod localized-name lookups
-- (LocalizedModTypeName / GetLocalizedModName). vMenu's dynamic Mod Menu
-- relies on these for its list labels, so the GXT-entry logic is preserved
-- exactly — including the per-model special cases and the horn name table.

local ModNames = {}

-- VehicleModType (only named where the C# switch needs them).
local MOD = {
    Engine = 11,
    Brakes = 12,
    Transmission = 13,
    Horns = 14,
    Suspension = 15,
    Armor = 16,
    FrontWheel = 23,
    RearWheel = 24,
    TrimDesign = 27,
    AirFilter = 40,
    Struts = 41,
    ArchCover = 42,
    Aerials = 43,
    Trim = 44,
    Tank = 45,
    Windows = 46,
    Livery = 48,
}

-- Fallback when no GXT entry is loaded: C# uses ModType.ToString().
local MOD_TYPE_NAMES = {
    [0] = 'Spoilers',
    [1] = 'FrontBumper',
    [2] = 'RearBumper',
    [3] = 'SideSkirt',
    [4] = 'Exhaust',
    [5] = 'Frame',
    [6] = 'Grille',
    [7] = 'Hood',
    [8] = 'Fender',
    [9] = 'RightFender',
    [10] = 'Roof',
    [11] = 'Engine',
    [12] = 'Brakes',
    [13] = 'Transmission',
    [14] = 'Horns',
    [15] = 'Suspension',
    [16] = 'Armor',
    [17] = 'Nitrous',
    [18] = 'Turbo',
    [19] = 'Subwoofer',
    [20] = 'TireSmoke',
    [21] = 'Hydraulics',
    [22] = 'XenonHeadlights',
    [23] = 'FrontWheel',
    [24] = 'RearWheel',
    [25] = 'PlateHolder',
    [26] = 'VanityPlates',
    [27] = 'TrimDesign',
    [28] = 'Ornaments',
    [29] = 'Dashboard',
    [30] = 'DialDesign',
    [31] = 'DoorSpeakers',
    [32] = 'Seats',
    [33] = 'SteeringWheels',
    [34] = 'ColumnShifterLevers',
    [35] = 'Plaques',
    [36] = 'Speakers',
    [37] = 'Trunk',
    [38] = 'Hydraulics',
    [39] = 'EngineBlock',
    [40] = 'AirFilter',
    [41] = 'Struts',
    [42] = 'ArchCover',
    [43] = 'Aerials',
    [44] = 'Trim',
    [45] = 'Tank',
    [46] = 'Windows',
    [47] = 'Unk47',
    [48] = 'Livery',
}

-- Straightforward LocalizedModTypeName cases: [mod type] = GXT label.
local MOD_TYPE_GXT = {
    [MOD.Armor] = 'CMOD_MOD_ARM',
    [MOD.Brakes] = 'CMOD_MOD_BRA',
    [MOD.Engine] = 'CMOD_MOD_ENG',
    [MOD.Suspension] = 'CMOD_MOD_SUS',
    [MOD.Transmission] = 'CMOD_MOD_TRN',
    [MOD.Horns] = 'CMOD_MOD_HRN',
    [MOD.RearWheel] = 'CMOD_WHE0_1',
    [25] = 'CMM_MOD_S0',
    [26] = 'CMM_MOD_S1',
    [28] = 'CMM_MOD_S3',
    [29] = 'CMM_MOD_S4',
    [30] = 'CMM_MOD_S5',
    [31] = 'CMM_MOD_S6',
    [32] = 'CMM_MOD_S7',
    [33] = 'CMM_MOD_S8',
    [34] = 'CMM_MOD_S9',
    [35] = 'CMM_MOD_S10',
    [36] = 'CMM_MOD_S11',
    [37] = 'CMM_MOD_S12',
    [38] = 'CMM_MOD_S13',
    [39] = 'CMM_MOD_S14',
    [MOD.Livery] = 'CMM_MOD_S23',
}

-- VehicleMod._hornNames: [mod index] = { gxt entry, fallback text }.
local HORN_NAMES = {
    [-1] = { 'CMOD_HRN_0', 'Stock Horn' },
    [0] = { 'CMOD_HRN_TRK', 'Truck Horn' },
    [1] = { 'CMOD_HRN_COP', 'Cop Horn' },
    [2] = { 'CMOD_HRN_CLO', 'Clown Horn' },
    [3] = { 'CMOD_HRN_MUS1', 'Musical Horn 1' },
    [4] = { 'CMOD_HRN_MUS2', 'Musical Horn 2' },
    [5] = { 'CMOD_HRN_MUS3', 'Musical Horn 3' },
    [6] = { 'CMOD_HRN_MUS4', 'Musical Horn 4' },
    [7] = { 'CMOD_HRN_MUS5', 'Musical Horn 5' },
    [8] = { 'CMOD_HRN_SAD', 'Sad Trombone' },
    [9] = { 'HORN_CLAS1', 'Classical Horn 1' },
    [10] = { 'HORN_CLAS2', 'Classical Horn 2' },
    [11] = { 'HORN_CLAS3', 'Classical Horn 3' },
    [12] = { 'HORN_CLAS4', 'Classical Horn 4' },
    [13] = { 'HORN_CLAS5', 'Classical Horn 5' },
    [14] = { 'HORN_CLAS6', 'Classical Horn 6' },
    [15] = { 'HORN_CLAS7', 'Classical Horn 7' },
    [16] = { 'HORN_CNOTE_C0', 'Scale Do' },
    [17] = { 'HORN_CNOTE_D0', 'Scale Re' },
    [18] = { 'HORN_CNOTE_E0', 'Scale Mi' },
    [19] = { 'HORN_CNOTE_F0', 'Scale Fa' },
    [20] = { 'HORN_CNOTE_G0', 'Scale Sol' },
    [21] = { 'HORN_CNOTE_A0', 'Scale La' },
    [22] = { 'HORN_CNOTE_B0', 'Scale Ti' },
    [23] = { 'HORN_CNOTE_C1', 'Scale Do (High)' },
    [24] = { 'HORN_HIPS1', 'Jazz Horn 1' },
    [25] = { 'HORN_HIPS2', 'Jazz Horn 2' },
    [26] = { 'HORN_HIPS3', 'Jazz Horn 3' },
    [27] = { 'HORN_HIPS4', 'Jazz Horn Loop' },
    [28] = { 'HORN_INDI_1', 'Star Spangled Banner 1' },
    [29] = { 'HORN_INDI_2', 'Star Spangled Banner 2' },
    [30] = { 'HORN_INDI_3', 'Star Spangled Banner 3' },
    [31] = { 'HORN_INDI_4', 'Star Spangled Banner 4' },
    [32] = { 'HORN_LUXE2', 'Classical Horn Loop 1' },
    [33] = { 'HORN_LUXE1', 'Classical Horn 8' },
    [34] = { 'HORN_LUXE3', 'Classical Horn Loop 2' },
    [35] = { 'HORN_LUXE2', 'Classical Horn Loop 1' },
    [36] = { 'HORN_LUXE1', 'Classical Horn 8' },
    [37] = { 'HORN_LUXE3', 'Classical Horn Loop 2' },
    [38] = { 'HORN_HWEEN1', 'Halloween Loop 1' },
    [39] = { 'HORN_HWEEN1', 'Halloween Loop 1' },
    [40] = { 'HORN_HWEEN2', 'Halloween Loop 2' },
    [41] = { 'HORN_HWEEN2', 'Halloween Loop 2' },
    [42] = { 'HORN_LOWRDER1', 'San Andreas Loop' },
    [43] = { 'HORN_LOWRDER1', 'San Andreas Loop' },
    [44] = { 'HORN_LOWRDER2', 'Liberty City Loop' },
    [45] = { 'HORN_LOWRDER2', 'Liberty City Loop' },
    [46] = { 'HORN_XM15_1', 'Festive Loop 1' },
    [47] = { 'HORN_XM15_2', 'Festive Loop 2' },
    [48] = { 'HORN_XM15_3', 'Festive Loop 3' },
}

local function ensure_text_loaded()
    if not HasThisAdditionalTextLoaded('mod_mnu', 10) then
        ClearAdditionalText(10, true)
        RequestAdditionalText('mod_mnu', 10)
    end
end

local function model_is(vehicle, name)
    return GetEntityModel(vehicle) == GetHashKey(name)
end

-- VehicleMod.LocalizedModTypeName.
function ModNames.localized_mod_type_name(vehicle, mod_type)
    ensure_text_loaded()
    local cur
    local simple = MOD_TYPE_GXT[mod_type]
    if simple ~= nil then
        cur = GetLabelText(simple)
    elseif mod_type == MOD.FrontWheel then
        local model = GetEntityModel(vehicle)
        if not IsThisModelABike(model) and IsThisModelABicycle(model) then
            cur = GetLabelText('CMOD_MOD_WHEM')
            if cur == '' then
                return 'Wheels'
            end
        else
            cur = GetLabelText('CMOD_WHE0_0')
        end
    elseif mod_type == MOD.TrimDesign then
        cur = GetLabelText(model_is(vehicle, 'sultanrs') and 'CMM_MOD_S2b' or 'CMM_MOD_S2')
    elseif mod_type == MOD.AirFilter then
        cur = GetLabelText(model_is(vehicle, 'sultanrs') and 'CMM_MOD_S15b' or 'CMM_MOD_S15')
    elseif mod_type == MOD.Struts then
        cur = GetLabelText(
            (model_is(vehicle, 'sultanrs') or model_is(vehicle, 'banshee2')) and 'CMM_MOD_S16b' or 'CMM_MOD_S16'
        )
    elseif mod_type == MOD.ArchCover then
        cur = GetLabelText(model_is(vehicle, 'sultanrs') and 'CMM_MOD_S17b' or 'CMM_MOD_S17')
    elseif mod_type == MOD.Aerials then
        if model_is(vehicle, 'sultanrs') then
            cur = GetLabelText('CMM_MOD_S18b')
        elseif model_is(vehicle, 'btype3') then
            cur = GetLabelText('CMM_MOD_S18c')
        else
            cur = GetLabelText('CMM_MOD_S18')
        end
    elseif mod_type == MOD.Trim then
        if model_is(vehicle, 'sultanrs') then
            cur = GetLabelText('CMM_MOD_S19b')
        elseif model_is(vehicle, 'btype3') then
            cur = GetLabelText('CMM_MOD_S19c')
        elseif model_is(vehicle, 'virgo2') then
            cur = GetLabelText('CMM_MOD_S19d')
        else
            cur = GetLabelText('CMM_MOD_S19')
        end
    elseif mod_type == MOD.Tank then
        cur = GetLabelText(model_is(vehicle, 'slamvan3') and 'CMM_MOD_S27' or 'CMM_MOD_S20')
    elseif mod_type == MOD.Windows then
        cur = GetLabelText(model_is(vehicle, 'btype3') and 'CMM_MOD_S21b' or 'CMM_MOD_S21')
    elseif mod_type == 47 then
        cur = GetLabelText(model_is(vehicle, 'slamvan3') and 'SLVAN3_RDOOR' or 'CMM_MOD_S22')
    else
        cur = GetModSlotName(vehicle, mod_type)
        if DoesTextLabelExist(cur) then
            cur = GetLabelText(cur)
        end
    end
    -- Some GetLabelText / GetModSlotName paths return nil in-game (unknown mod
    -- types), not just an empty string. Fall back to a name either way so
    -- callers that concatenate the result never hit a nil.
    if cur == nil or cur == '' then
        cur = MOD_TYPE_NAMES[mod_type] or tostring(mod_type)
    end
    return cur
end

-- VehicleMod.GetLocalizedModName(index).
function ModNames.get_localized_mod_name(vehicle, mod_type, index)
    local mod_count = GetNumVehicleMods(vehicle, mod_type)
    if mod_count == 0 then
        return ''
    end
    if index < -1 or index >= mod_count then
        return ''
    end
    ensure_text_loaded()

    if mod_type == MOD.Horns then
        local horn = HORN_NAMES[index]
        if horn ~= nil then
            if DoesTextLabelExist(horn[1]) then
                return GetLabelText(horn[1])
            end
            return horn[2]
        end
        return ''
    end

    if mod_type == MOD.FrontWheel or mod_type == MOD.RearWheel then
        if index == -1 then
            local model = GetEntityModel(vehicle)
            if not IsThisModelABike(model) and IsThisModelABicycle(model) then
                return GetLabelText('CMOD_WHE_0')
            end
            return GetLabelText('CMOD_WHE_B_0')
        end
        if index >= mod_count // 2 then
            return GetLabelText('CHROME') .. ' ' .. GetLabelText(GetModTextLabel(vehicle, mod_type, index))
        end
        return GetLabelText(GetModTextLabel(vehicle, mod_type, index))
    end

    if mod_type == MOD.Armor then
        return GetLabelText('CMOD_ARM_' .. tostring(index + 1))
    elseif mod_type == MOD.Brakes then
        return GetLabelText('CMOD_BRA_' .. tostring(index + 1))
    elseif mod_type == MOD.Engine then
        if index == -1 then
            -- No "no engine part" label in-game; C# reuses the armor one.
            return GetLabelText('CMOD_ARM_0')
        end
        return GetLabelText('CMOD_ENG_' .. tostring(index + 2))
    elseif mod_type == MOD.Suspension then
        return GetLabelText('CMOD_SUS_' .. tostring(index + 1))
    elseif mod_type == MOD.Transmission then
        return GetLabelText('CMOD_GBX_' .. tostring(index + 1))
    end

    if index > -1 then
        local cur = GetModTextLabel(vehicle, mod_type, index)
        if DoesTextLabelExist(cur) then
            cur = GetLabelText(cur)
            if cur == '' or cur == 'NULL' then
                return ModNames.localized_mod_type_name(vehicle, mod_type) .. ' ' .. tostring(index + 1)
            end
            return cur
        end
        return ModNames.localized_mod_type_name(vehicle, mod_type) .. ' ' .. tostring(index + 1)
    end

    if mod_type == MOD.Struts then
        if model_is(vehicle, 'banshee') or model_is(vehicle, 'banshee2') or model_is(vehicle, 'sultanrs') then
            return GetLabelText('CMOD_COL5_41')
        end
    end
    return GetLabelText('CMOD_DEF_0')
end

return ModNames
