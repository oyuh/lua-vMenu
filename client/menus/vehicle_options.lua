-- Port of vMenu/menus/VehicleOptions.cs: god mode, repair/wash, the dynamic
-- Mod Menu, colors (incl. custom RGB + paint finish statebags), neon
-- underglow, doors/windows/extras/liveries, plates, radio, and delete.
--
-- Public PascalCase fields on the instance are read by FunctionsController
-- and UserDefaults.save_settings.

local Config = require('shared.config')
local Permissions = require('shared.permissions')
local Common = require('client.common')
local VehicleCommon = require('client.vehicle_common')
local ModNames = require('client.vehicle_mod_names')
local Notification = require('client.notify')
local UserDefaults = require('client.user_defaults')
local State = require('client.state')
local VehicleData = require('client.data.vehicle_data')
local Controller = require('menu.controller')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Notify = Notification.Notify

local VehicleOptions = {}

local JUMP = 22 -- Control.Jump

-- C# menu events are multicast (+=); ours hold a single callback, so this
-- chains handlers in registration order.
local function on(menu, event, handler)
    local previous = menu[event]
    if previous == nil then
        menu[event] = handler
    else
        menu[event] = function(...)
            previous(...)
            handler(...)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Radio stations (CitizenFX.Core RadioStation enum; the int values are what
-- C# vMenu persisted to settings_vehicleDefaultRadio, so they must match)
-- ---------------------------------------------------------------------------

local RADIO_STATION_NAMES = {
    'LosSantosRockRadio',
    'NonStopPopFM',
    'RadioLosSantos',
    'ChannelX',
    'WestCoastTalkRadio',
    'RebelRadio',
    'SoulwaxFM',
    'EastLosFM',
    'WestCoastClassics',
    'BlaineCountyRadio',
    'TheBlueArk',
    'WorldWideFM',
    'FlyloFM',
    'TheLowdown',
    'RadioMirrorPark',
    'Space',
    'VinewoodBoulevardRadio',
    'SelfRadio',
    'TheLab',
    'BlondedLosSantos',
    'LosSantosUndergroundRadio',
    'RadioOff',
}
local RADIO_OFF = 255

-- enum value for each list index (0-based list; RadioOff = 255).
local function radio_value_for_index(index)
    if index == #RADIO_STATION_NAMES - 1 then
        return RADIO_OFF
    end
    return index
end

-- Game._radioNames: enum value → internal station name for SetVehRadioStation.
local RADIO_GAME_NAMES = {
    [0] = 'RADIO_01_CLASS_ROCK',
    [1] = 'RADIO_02_POP',
    [2] = 'RADIO_03_HIPHOP_NEW',
    [3] = 'RADIO_04_PUNK',
    [4] = 'RADIO_05_TALK_01',
    [5] = 'RADIO_06_COUNTRY',
    [6] = 'RADIO_07_DANCE_01',
    [7] = 'RADIO_08_MEXICAN',
    [8] = 'RADIO_09_HIPHOP_OLD',
    [9] = 'RADIO_11_TALK_02',
    [10] = 'RADIO_12_REGGAE',
    [11] = 'RADIO_13_JAZZ',
    [12] = 'RADIO_14_DANCE_02',
    [13] = 'RADIO_15_MOTOWN',
    [14] = 'RADIO_16_SILVERLAKE',
    [15] = 'RADIO_17_FUNK',
    [16] = 'RADIO_18_90S_ROCK',
    [17] = 'RADIO_19_USER',
    [18] = 'RADIO_20_THELAB',
    [19] = 'RADIO_21_DLC_XM17',
    [20] = 'RADIO_22_DLC_BATTLE_MIX1_RADIO',
}

-- Vehicle.RadioStation setter.
local function set_vehicle_radio_station(vehicle, value)
    SetVehicleRadioEnabled(vehicle, true)
    if value == RADIO_OFF then
        SetVehRadioStation(vehicle, 'OFF')
    elseif RADIO_GAME_NAMES[value] ~= nil then
        SetVehRadioStation(vehicle, RADIO_GAME_NAMES[value])
    end
end

-- ---------------------------------------------------------------------------
-- License plates (LicensePlateStyle enum values per list position)
-- ---------------------------------------------------------------------------

local PLATE_STYLE_BY_LIST_INDEX = {
    [0] = 0, -- BlueOnWhite1
    [1] = 3, -- BlueOnWhite2
    [2] = 4, -- BlueOnWhite3
    [3] = 2, -- YellowOnBlue
    [4] = 1, -- YellowOnBlack
    [5] = 5, -- NorthYankton
    [6] = 6, -- ECola
    [7] = 7, -- LasVenturas
    [8] = 8, -- LibertyCity
    [9] = 9, -- LSCarMeet
    [10] = 10, -- LSPanic
    [11] = 11, -- LSPounders
    [12] = 12, -- Sprunk
}
local LIST_INDEX_BY_PLATE_STYLE = {}
for list_index, style in pairs(PLATE_STYLE_BY_LIST_INDEX) do
    LIST_INDEX_BY_PLATE_STYLE[style] = list_index
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function get_vehicle()
    return Common.get_vehicle()
end

local function vehicle_exists(vehicle)
    return vehicle ~= 0 and DoesEntityExist(vehicle)
end

local function player_is_driver(vehicle)
    return GetPedInVehicleSeat(vehicle, -1) == PlayerPedId()
end

-- VehicleNeonLight: Left = 0, Right = 1, Front = 2, Back = 3.
local NEON_BONES = { [0] = 'neon_l', [1] = 'neon_r', [2] = 'neon_f', [3] = 'neon_b' }

local function has_neon_light(vehicle, light)
    return GetEntityBoneIndexByName(vehicle, NEON_BONES[light]) ~= -1
end

local function has_neon_lights(vehicle)
    return has_neon_light(vehicle, 0)
        or has_neon_light(vehicle, 1)
        or has_neon_light(vehicle, 2)
        or has_neon_light(vehicle, 3)
end

-- GetColorFromIndex: 0-based neon color index → r, g, b.
local function get_color_from_index(index)
    if index >= 0 and index < 13 then
        local color = VehicleData.NeonLightColors[index + 1]
        return color[1], color[2], color[3]
    end
    return 255, 255, 255
end

-- GetIndexFromColor: current neon color → list index (0 when unknown).
local function get_index_from_color()
    local vehicle = get_vehicle()
    if not vehicle_exists(vehicle) or not has_neon_lights(vehicle) then
        return 0
    end
    local r, g, b = GetVehicleNeonLightsColour(vehicle)
    if r == 255 and g == 0 and b == 255 then
        -- default value when the vehicle has no neon kit selected
        return 0
    end
    for i, color in ipairs(VehicleData.NeonLightColors) do
        if color[1] == r and color[2] == g and color[3] == b then
            return i - 1
        end
    end
    return 0
end

local function is_vehicle_too_damaged_to_change_extras(vehicle)
    local body_health = GetVehicleBodyHealth(vehicle)
    local engine_health = GetVehicleEngineHealth(vehicle)
    local allowed_body_health = Config.get_int('vmenu_allowed_body_damage_for_extra_change', 0)
    local allowed_engine_health = Config.get_int('vmenu_allowed_engine_damage_for_extra_change', 0)
    return body_health < allowed_body_health or engine_health < allowed_engine_health
end

local function is_hex(text)
    return text:match('^%x+$') ~= nil
end

local function round1(value)
    return math.floor(value * 10 + 0.5) / 10
end

-- ---------------------------------------------------------------------------
-- CreateCustomColourMenu (rgb_type: 'primaryPaint' | 'secondaryPaint' |
-- 'underglow' | 'headlight' | 'tiresmoke')
-- ---------------------------------------------------------------------------

local COLOUR_TYPES = { 'Metallic', 'Classic', 'Pearlescent', 'Matte', 'Metals', 'Chrome', 'Chameleon' }

local function create_custom_colour_menu(menu, rgb_type)
    local hex_colour = Items.MenuItem.new('Hex Color Code')
    local type_list = Items.MenuListItem.new('Paint Finish', COLOUR_TYPES, 0)

    local r, g, b = 0, 0, 0

    local function new_colour_slider(text)
        local slider = Items.MenuSliderItem.new(text, 0, 255, 128)
        slider.ShowDivider = true
        slider.BarColor = { 0, 0, 0, 155 }
        slider.BackgroundColor = { 79, 79, 79, 200 }
        return slider
    end
    local red_colour = new_colour_slider('Red Color')
    local green_colour = new_colour_slider('Green Color')
    local blue_colour = new_colour_slider('Blue Color')

    menu:AddMenuItem(hex_colour)
    menu:AddMenuItem(red_colour)
    menu:AddMenuItem(green_colour)
    menu:AddMenuItem(blue_colour)
    if rgb_type == 'primaryPaint' or rgb_type == 'secondaryPaint' then
        menu:AddMenuItem(type_list)
    end

    -- Reads the current color off the vehicle into r/g/b (assigns only when
    -- the C# branches assign, so stale values persist identically).
    local function refresh_from_vehicle(vehicle)
        if rgb_type == 'primaryPaint' then
            r, g, b = GetVehicleCustomPrimaryColour(vehicle)
        elseif rgb_type == 'secondaryPaint' then
            r, g, b = GetVehicleCustomSecondaryColour(vehicle)
        elseif rgb_type == 'underglow' then
            r, g, b = GetVehicleNeonLightsColour(vehicle)
        elseif rgb_type == 'headlight' then
            local has_custom, custom_r, custom_g, custom_b = GetVehicleXenonLightsCustomColor(vehicle)
            if has_custom then
                r, g, b = custom_r, custom_g, custom_b
            elseif IsToggleModOn(vehicle, 22) then
                local headlight = VehicleCommon.get_headlights_color_for_vehicle(vehicle)
                if headlight < 0 then
                    headlight = 0
                end
                r, g, b = get_color_from_index(headlight)
            end
        elseif rgb_type == 'tiresmoke' then
            r, g, b = GetVehicleTyreSmokeColor(vehicle)
        end
    end

    local function apply_colour(vehicle, new_r, new_g, new_b)
        if rgb_type == 'primaryPaint' then
            SetVehicleCustomPrimaryColour(vehicle, new_r, new_g, new_b)
        elseif rgb_type == 'secondaryPaint' then
            SetVehicleCustomSecondaryColour(vehicle, new_r, new_g, new_b)
        elseif rgb_type == 'underglow' then
            SetVehicleNeonLightsColour(vehicle, new_r, new_g, new_b)
        elseif rgb_type == 'headlight' then
            SetVehicleXenonLightsCustomColor(vehicle, new_r, new_g, new_b)
        elseif rgb_type == 'tiresmoke' then
            SetVehicleTyreSmokeColor(vehicle, new_r, new_g, new_b)
        end
    end

    local function set_bar_colors(new_r, new_g, new_b)
        red_colour.BarColor = { new_r, new_g, new_b, 255 }
        green_colour.BarColor = { new_r, new_g, new_b, 255 }
        blue_colour.BarColor = { new_r, new_g, new_b, 255 }
    end

    local function set_slider_values(new_r, new_g, new_b)
        red_colour.Text = ('Red Color (%d)'):format(new_r)
        red_colour.Position = new_r
        green_colour.Text = ('Green Color (%d)'):format(new_g)
        green_colour.Position = new_g
        blue_colour.Text = ('Blue Color (%d)'):format(new_b)
        blue_colour.Position = new_b
        set_bar_colors(new_r, new_g, new_b)
    end

    on(menu, 'OnMenuOpen', function(_)
        refresh_from_vehicle(get_vehicle())
        set_slider_values(r, g, b)
    end)

    on(menu, 'OnItemSelect', function(_, item, _index)
        local vehicle = get_vehicle()
        if item == hex_colour then
            local hex_value = ('%02X%02X%02X'):format(red_colour.Position, green_colour.Position, blue_colour.Position)
            local result = Common.get_user_input('Enter Color Hex', hex_value:gsub('#', ''), 6)
            if result ~= nil and result ~= '' and is_hex(result) then
                local rgb_int = tonumber(result, 16)
                local red = (rgb_int >> 16) & 255
                local green = (rgb_int >> 8) & 255
                local blue = rgb_int & 255
                apply_colour(vehicle, red, green, blue)
                set_slider_values(red, green, blue)
            end
        end
    end)

    on(menu, 'OnSliderPositionChange', function(_, slider_item, _old_position, new_position, _item_index)
        local vehicle = get_vehicle()
        refresh_from_vehicle(vehicle)

        if slider_item == red_colour then
            apply_colour(vehicle, new_position, g, b)
            red_colour.Text = ('Red Color (%d)'):format(new_position)
        elseif slider_item == green_colour then
            apply_colour(vehicle, r, new_position, b)
            green_colour.Text = ('Green Color (%d)'):format(new_position)
        elseif slider_item == blue_colour then
            apply_colour(vehicle, r, g, new_position)
            blue_colour.Text = ('Blue Color (%d)'):format(new_position)
        end
        set_bar_colors(red_colour.Position, green_colour.Position, blue_colour.Position)
    end)

    on(menu, 'OnListIndexChange', function(_, _item, _old_index, new_index, _item_index)
        local vehicle = get_vehicle()

        if rgb_type == 'primaryPaint' then
            local pearl_reset, wheel_reset = GetVehicleExtraColours(vehicle)
            SetVehicleModColor_1(vehicle, new_index, 0, 0)
            Entity(vehicle).state:set('vMenu:PrimaryPaintFinish', new_index, true)
            SetVehicleExtraColours(vehicle, pearl_reset, wheel_reset)
        elseif rgb_type == 'secondaryPaint' then
            local pearl_reset, wheel_reset = GetVehicleExtraColours(vehicle)
            SetVehicleModColor_2(vehicle, new_index, 0)
            Entity(vehicle).state:set('vMenu:SecondaryPaintFinish', new_index, true)
            SetVehicleExtraColours(vehicle, pearl_reset, wheel_reset)
        elseif rgb_type == 'underglow' then
            set_slider_values(get_color_from_index(new_index))
        elseif rgb_type == 'headlight' then
            local headlight = VehicleCommon.get_headlights_color_for_vehicle(vehicle)
            if headlight < 0 then
                headlight = 0
            end
            set_slider_values(get_color_from_index(headlight))
        elseif rgb_type == 'tiresmoke' then
            set_slider_values(GetVehicleTyreSmokeColor(vehicle))
        end
    end)
end

-- ---------------------------------------------------------------------------
-- create()
-- ---------------------------------------------------------------------------

function VehicleOptions.create()
    local self = {}

    -- Public fields (defaults from UserDefaults, like the C# properties).
    self.VehicleGodMode = UserDefaults.get_bool('vehicleGodMode')
    self.VehicleGodInvincible = UserDefaults.get_bool('vehicleGodInvincible')
    self.VehicleGodEngine = UserDefaults.get_bool('vehicleGodEngine')
    self.VehicleGodVisual = UserDefaults.get_bool('vehicleGodVisual')
    self.VehicleGodStrongWheels = UserDefaults.get_bool('vehicleGodStrongWheels')
    self.VehicleGodRamp = UserDefaults.get_bool('vehicleGodRamp')
    self.VehicleGodAutoRepair = UserDefaults.get_bool('vehicleGodAutoRepair')
    self.VehicleNeverDirty = UserDefaults.get_bool('vehicleNeverDirty')
    self.VehicleEngineAlwaysOn = UserDefaults.get_bool('vehicleEngineAlwaysOn')
    self.VehicleNoSiren = UserDefaults.get_bool('vehicleNoSiren')
    -- upstream typo preserved (UserDefaults.save_settings reads it)
    self.VehicleNoBikeHelemet = UserDefaults.get_bool('vehicleNoBikeHelmet')
    self.FlashHighbeamsOnHonk = UserDefaults.get_bool('vehicleHighbeamsOnHonk')
    self.DisablePlaneTurbulence = UserDefaults.get_bool('vehicleDisablePlaneTurbulence')
    self.DisableHelicopterTurbulence = UserDefaults.get_bool('vehicleDisableHelicopterTurbulence')
    self.AnchorBoat = UserDefaults.get_bool('vehicleAnchorBoat')
    self.VehicleBikeSeatbelt = UserDefaults.get_bool('vehicleBikeSeatbelt')
    self.VehicleInfiniteFuel = false
    self.VehicleShowHealth = false
    self.VehicleRadioOverride = UserDefaults.get_int('vehicleDefaultRadio') >= 0
    self.VehicleFrozen = false
    self.VehicleTorqueMultiplier = false
    self.VehiclePowerMultiplier = false
    self.VehicleTorqueMultiplierAmount = 2.0
    self.VehiclePowerMultiplierAmount = 2.0

    local menu = Menu.new(Common.get_safe_player_name(GetPlayerName(PlayerId())), 'Vehicle Options')

    -- vehicle god mode submenu
    local veh_god_menu = Menu.new('Vehicle Godmode', 'Vehicle Godmode Options')
    local veh_god_menu_btn = Items.MenuItem.new('God Mode Options', 'Enable or disable specific damage types.')
    veh_god_menu_btn.Label = '→→→'
    Controller.AddSubmenu(menu, veh_god_menu)

    -- checkboxes
    local vehicle_god = Items.MenuCheckboxItem.new(
        'Vehicle God Mode',
        'Makes your vehicle not take any damage. Note, you need to go into the god menu options below to select '
            .. 'what kind of damage you want to disable.',
        self.VehicleGodMode
    )
    local vehicle_never_dirty = Items.MenuCheckboxItem.new(
        'Keep Vehicle Clean',
        'This will constantly clean your car if the vehicle dirt level goes above 0. Note that this only cleans '
            .. '~o~dust~s~ or ~o~dirt~s~. This does not clean mud, snow or other ~r~damage decals~s~. Repair your '
            .. 'vehicle to remove them.',
        self.VehicleNeverDirty
    )
    local vehicle_bike_seatbelt = Items.MenuCheckboxItem.new(
        'Bike Seatbelt',
        'Prevents you from being knocked off your bike, bicyle, ATV or similar.',
        self.VehicleBikeSeatbelt
    )
    local vehicle_engine_ao = Items.MenuCheckboxItem.new(
        'Engine Always On',
        'Keeps your vehicle engine on when you exit your vehicle.',
        self.VehicleEngineAlwaysOn
    )
    local vehicle_no_turbulence = Items.MenuCheckboxItem.new(
        'Disable Plane Turbulence',
        'Disables the turbulence for all planes.',
        self.DisablePlaneTurbulence
    )
    local vehicle_no_turbulence_heli = Items.MenuCheckboxItem.new(
        'Disable Helicopter Turbulence',
        'Disables the turbulence for all helicopters.',
        self.DisableHelicopterTurbulence
    )
    local vehicle_set_anchor = Items.MenuCheckboxItem.new(
        'Anchor Boat',
        'Only works if the current vehicle is a boat and its position is valid for anchoring',
        self.AnchorBoat
    )
    local vehicle_no_siren = Items.MenuCheckboxItem.new(
        'Disable Siren',
        "Disables your vehicle's siren. Only works if your vehicle actually has a siren.",
        self.VehicleNoSiren
    )
    local vehicle_no_bike_helmet = Items.MenuCheckboxItem.new(
        'No Bike Helmet',
        'No longer auto-equip a helmet when getting on a bike or quad.',
        self.VehicleNoBikeHelemet
    )
    local vehicle_freeze =
        Items.MenuCheckboxItem.new('Freeze Vehicle', "Freeze your vehicle's position.", self.VehicleFrozen)
    local torque_enabled = Items.MenuCheckboxItem.new(
        'Enable Torque Multiplier',
        'Enables the torque multiplier selected from the list below.',
        self.VehicleTorqueMultiplier
    )
    local power_enabled = Items.MenuCheckboxItem.new(
        'Enable Power Multiplier',
        'Enables the power multiplier selected from the list below.',
        self.VehiclePowerMultiplier
    )
    local highbeams_on_honk = Items.MenuCheckboxItem.new(
        'Flash Highbeams On Honk',
        'Turn on your highbeams on your vehicle when honking your horn. Does not work during the day when you have '
            .. 'your lights turned off.',
        self.FlashHighbeamsOnHonk
    )
    local show_health = Items.MenuCheckboxItem.new(
        'Show Vehicle Health',
        'Shows the vehicle health on the screen.',
        self.VehicleShowHealth
    )
    local infinite_fuel = Items.MenuCheckboxItem.new(
        'Infinite Fuel',
        'Enables or disables infinite fuel for this vehicle, only works if FRFuel is installed.',
        self.VehicleInfiniteFuel
    )
    local vehicle_radio_override = Items.MenuCheckboxItem.new(
        'Enable Default Radio Station',
        'Enables or disables overriding default radio channel in all vehicles',
        self.VehicleRadioOverride
    )

    -- buttons
    local fix_vehicle =
        Items.MenuItem.new('Repair Vehicle', 'Repair any visual and physical damage present on your vehicle.')
    local clean_vehicle = Items.MenuItem.new('Wash Vehicle', 'Clean your vehicle.')
    local toggle_engine = Items.MenuItem.new('Toggle Engine On/Off', 'Turn your engine on/off.')
    local set_license_plate_text =
        Items.MenuItem.new('Set License Plate Text', 'Enter a custom license plate for your vehicle.')
    local mod_menu_btn = Items.MenuItem.new('Mod Menu', 'Tune and customize your vehicle here.')
    mod_menu_btn.Label = '→→→'
    local doors_menu_btn = Items.MenuItem.new('Vehicle Doors', 'Open, close, remove and restore vehicle doors here.')
    doors_menu_btn.Label = '→→→'
    local windows_menu_btn =
        Items.MenuItem.new('Vehicle Windows', 'Roll your windows up/down or remove/restore your vehicle windows here.')
    windows_menu_btn.Label = '→→→'
    local components_menu_btn = Items.MenuItem.new('Vehicle Extras', 'Add/remove vehicle components/extras.')
    components_menu_btn.Label = '→→→'
    local liveries_menu_btn = Items.MenuItem.new('Vehicle Liveries', 'Style your vehicle with fancy liveries!')
    liveries_menu_btn.Label = '→→→'
    local colors_menu_btn = Items.MenuItem.new(
        'Vehicle Colors',
        'Style your vehicle even further by giving it some ~g~Snailsome ~s~colors!'
    )
    colors_menu_btn.Label = '→→→'
    local underglow_menu_btn =
        Items.MenuItem.new('Vehicle Neon Kits', 'Make your vehicle shine with some fancy neon underglow!')
    underglow_menu_btn.Label = '→→→'
    local vehicle_invisible = Items.MenuItem.new(
        'Toggle Vehicle Visibility',
        'Makes your vehicle visible/invisible. ~r~Your vehicle will be made visible again as soon as you leave the '
            .. 'vehicle. Otherwise you would not be able to get back in.'
    )
    local flip_vehicle = Items.MenuItem.new('Flip Vehicle', 'Sets your current vehicle on all 4 wheels.')
    local vehicle_alarm = Items.MenuItem.new('Toggle Vehicle Alarm', "Starts/stops your vehicle's alarm.")
    local cycle_seats = Items.MenuItem.new('Cycle Through Vehicle Seats', 'Cycle through the available vehicle seats.')
    local vehicle_lights = Items.MenuListItem.new(
        'Vehicle Lights',
        { 'Hazard Lights', 'Left Indicator', 'Right Indicator', 'Interior Lights', 'Helicopter Spotlight' },
        0,
        'Turn vehicle lights on/off.'
    )

    local radio_index = UserDefaults.get_int('vehicleDefaultRadio')
    if radio_index == RADIO_OFF then
        radio_index = #RADIO_STATION_NAMES - 1
    elseif radio_index < 0 then
        radio_index = 0
    end
    local radio_stations = Items.MenuListItem.new(
        'Set Default Radio Station',
        RADIO_STATION_NAMES,
        radio_index,
        'Select a default radio station for all cars you spawn'
    )
    radio_stations.Enabled = self.VehicleRadioOverride

    local vehicle_tires_list = Items.MenuListItem.new(
        'Fix / Destroy Tires',
        { 'All Tires', 'Tire #1', 'Tire #2', 'Tire #3', 'Tire #4', 'Tire #5', 'Tire #6', 'Tire #7', 'Tire #8' },
        0,
        'Fix or destroy a specific vehicle tire, or all of them at once. Note, not all indexes are valid for all '
            .. 'vehicles, some might not do anything on certain vehicles.'
    )
    local destroy_engine = Items.MenuItem.new('Destroy Engine', "Destroys your vehicle's engine.")

    local delete_btn = Items.MenuItem.new('~r~Delete Vehicle', 'Delete your vehicle, this ~r~can NOT be undone~s~!')
    delete_btn.LeftIcon = Items.Icon.WARNING
    delete_btn.Label = '→→→'
    local delete_no_btn = Items.MenuItem.new('NO, CANCEL', 'NO, do NOT delete my vehicle and go back!')
    local delete_yes_btn = Items.MenuItem.new(
        '~r~YES, DELETE',
        "Yes I'm sure, delete my vehicle please, I understand that this cannot be undone."
    )
    delete_yes_btn.LeftIcon = Items.Icon.WARNING

    -- lists
    local set_dirt_level = Items.MenuListItem.new(
        'Set Dirt Level',
        { 'No Dirt', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15' },
        0,
        'Select how much dirt should be visible on your vehicle, press ~r~enter~s~ to apply the selected level.'
    )
    local set_license_plate_type = Items.MenuListItem.new('License Plate Type', {
        GetLabelText('CMOD_PLA_0'),
        GetLabelText('CMOD_PLA_1'),
        GetLabelText('CMOD_PLA_2'),
        GetLabelText('CMOD_PLA_3'),
        GetLabelText('CMOD_PLA_4'),
        GetLabelText('PROL'),
        GetLabelText('CMOD_PLA_6'),
        GetLabelText('CMOD_PLA_7'),
        GetLabelText('CMOD_PLA_8'),
        GetLabelText('CMOD_PLA_9'),
        GetLabelText('CMOD_PLA_10'),
        GetLabelText('CMOD_PLA_11'),
        GetLabelText('CMOD_PLA_12'),
    }, 0, 'Choose a license plate type and press ~r~enter ~s~to apply it to your vehicle.')
    local multiplier_values = { 'x2', 'x4', 'x8', 'x16', 'x32', 'x64', 'x128', 'x256', 'x512', 'x1024' }
    local torque_multiplier = Items.MenuListItem.new(
        'Set Engine Torque Multiplier',
        multiplier_values,
        0,
        'Set the engine torque multiplier.'
    )
    local power_multiplier =
        Items.MenuListItem.new('Set Engine Power Multiplier', multiplier_values, 0, 'Set the engine power multiplier.')
    local speed_limiter = Items.MenuListItem.new(
        'Speed Limiter',
        { 'Set', 'Reset', 'Custom Speed Limit' },
        0,
        'Set your vehicles max speed to your ~y~current speed~s~. Resetting your vehicles max speed will set the max '
            .. 'speed of your current vehicle back to default. Only your current vehicle is affected by this option.'
    )

    -- submenus
    local mod_menu = Menu.new('Mod Menu', 'Vehicle Mods')
    mod_menu:AddInstructionalButton(JUMP, 'Toggle Vehicle Doors')
    mod_menu:AddButtonPressHandler(JUMP, 'JUST_PRESSED', function(_, _control)
        local vehicle = get_vehicle()
        if vehicle_exists(vehicle) and not IsEntityDead(vehicle) and player_is_driver(vehicle) then
            local open = GetVehicleDoorAngleRatio(vehicle, 0) < 0.1
            if open then
                for door = 0, 7 do
                    SetVehicleDoorOpen(vehicle, door, false, false)
                end
            else
                SetVehicleDoorsShut(vehicle, false)
            end
        end
    end, false)
    local doors_menu = Menu.new('Vehicle Doors', 'Vehicle Doors Management')
    local windows_menu = Menu.new('Vehicle Windows', 'Vehicle Windows Management')
    local components_menu = Menu.new('Vehicle Extras', 'Vehicle Extras/Components')
    local liveries_menu = Menu.new('Vehicle Liveries', 'Vehicle Liveries')
    local colors_menu = Menu.new('Vehicle Colors', 'Vehicle Colors')
    local delete_confirm_menu = Menu.new('Confirm Action', 'Delete Vehicle, Are You Sure?')
    local underglow_menu = Menu.new('Vehicle Neon Kits', 'Vehicle Neon Underglow Options')

    Controller.AddSubmenu(menu, mod_menu)
    Controller.AddSubmenu(menu, doors_menu)
    Controller.AddSubmenu(menu, windows_menu)
    Controller.AddSubmenu(menu, components_menu)
    Controller.AddSubmenu(menu, liveries_menu)
    Controller.AddSubmenu(menu, colors_menu)
    Controller.AddSubmenu(menu, delete_confirm_menu)
    Controller.AddSubmenu(menu, underglow_menu)

    self.VehicleModMenu = mod_menu
    self.VehicleDoorsMenu = doors_menu
    self.VehicleWindowsMenu = windows_menu
    self.VehicleComponentsMenu = components_menu
    self.VehicleLiveriesMenu = liveries_menu
    self.VehicleColorsMenu = colors_menu
    self.DeleteConfirmMenu = delete_confirm_menu
    self.VehicleUnderglowMenu = underglow_menu

    -- item → extra id for the components menu (rebuilt per open)
    local vehicle_extras_map = {}

    -- add items to the menu (based on permissions)
    if Permissions.is_allowed('VOGod') then
        menu:AddMenuItem(vehicle_god)
        menu:AddMenuItem(veh_god_menu_btn)
        Controller.BindMenuItem(menu, veh_god_menu, veh_god_menu_btn)

        local god_invincible = Items.MenuCheckboxItem.new(
            'Invincible',
            'Makes the car invincible. Includes fire damage, explosion damage, collision damage and more.',
            self.VehicleGodInvincible
        )
        local god_engine = Items.MenuCheckboxItem.new(
            'Engine Damage',
            'Disables your engine from taking any damage.',
            self.VehicleGodEngine
        )
        local god_visual = Items.MenuCheckboxItem.new(
            'Visual Damage',
            'This prevents scratches and other damage decals from being applied to your vehicle. It does not '
                .. 'prevent (body) deformation damage.',
            self.VehicleGodVisual
        )
        local god_strong_wheels = Items.MenuCheckboxItem.new(
            'Strong Wheels',
            'Disables your wheels from being deformed and causing reduced handling. This does not make tires '
                .. 'bulletproof.',
            self.VehicleGodStrongWheels
        )
        local god_ramp = Items.MenuCheckboxItem.new(
            'Ramp Damage',
            'Disables vehicles such as the Ramp Buggy from taking damage when using the ramp.',
            self.VehicleGodRamp
        )
        local god_auto_repair = Items.MenuCheckboxItem.new(
            '~r~Auto Repair',
            "Automatically repairs your vehicle when it has ANY type of damage. It's recommended to keep this "
                .. 'turned off to prevent glitchyness.',
            self.VehicleGodAutoRepair
        )

        veh_god_menu:AddMenuItem(god_invincible)
        veh_god_menu:AddMenuItem(god_engine)
        veh_god_menu:AddMenuItem(god_visual)
        veh_god_menu:AddMenuItem(god_strong_wheels)
        veh_god_menu:AddMenuItem(god_ramp)
        veh_god_menu:AddMenuItem(god_auto_repair)

        veh_god_menu.OnCheckboxChange = function(_, item, _index, checked)
            if item == god_invincible then
                self.VehicleGodInvincible = checked
            elseif item == god_engine then
                self.VehicleGodEngine = checked
            elseif item == god_visual then
                self.VehicleGodVisual = checked
            elseif item == god_strong_wheels then
                self.VehicleGodStrongWheels = checked
            elseif item == god_ramp then
                self.VehicleGodRamp = checked
            elseif item == god_auto_repair then
                self.VehicleGodAutoRepair = checked
            end
        end
    end
    if Permissions.is_allowed('VORepair') then
        menu:AddMenuItem(fix_vehicle)
    end
    if Permissions.is_allowed('VOKeepClean') then
        menu:AddMenuItem(vehicle_never_dirty)
    end
    if Permissions.is_allowed('VOWash') then
        menu:AddMenuItem(clean_vehicle)
        menu:AddMenuItem(set_dirt_level)
    end
    if Permissions.is_allowed('VOMod') then
        menu:AddMenuItem(mod_menu_btn)
    end
    if Permissions.is_allowed('VOColors') then
        menu:AddMenuItem(colors_menu_btn)
    end
    if Permissions.is_allowed('VOUnderglow') then
        menu:AddMenuItem(underglow_menu_btn)
        Controller.BindMenuItem(menu, underglow_menu, underglow_menu_btn)
    end
    if Permissions.is_allowed('VOLiveries') then
        menu:AddMenuItem(liveries_menu_btn)
    end
    if Permissions.is_allowed('VOComponents') then
        menu:AddMenuItem(components_menu_btn)
    end
    if Permissions.is_allowed('VOEngine') then
        menu:AddMenuItem(toggle_engine)
    end
    if Permissions.is_allowed('VOChangePlate') then
        menu:AddMenuItem(set_license_plate_text)
        menu:AddMenuItem(set_license_plate_type)
    end
    if Permissions.is_allowed('VODoors') then
        menu:AddMenuItem(doors_menu_btn)
    end
    if Permissions.is_allowed('VOWindows') then
        menu:AddMenuItem(windows_menu_btn)
    end
    if Permissions.is_allowed('VOBikeSeatbelt') then
        menu:AddMenuItem(vehicle_bike_seatbelt)
    end
    if Permissions.is_allowed('VOSpeedLimiter') then
        menu:AddMenuItem(speed_limiter)
    end
    if Permissions.is_allowed('VOTorqueMultiplier') then
        menu:AddMenuItem(torque_enabled)
        menu:AddMenuItem(torque_multiplier)
    end
    if Permissions.is_allowed('VOPowerMultiplier') then
        menu:AddMenuItem(power_enabled)
        menu:AddMenuItem(power_multiplier)
    end
    if Permissions.is_allowed('VODisableTurbulence') then
        menu:AddMenuItem(vehicle_no_turbulence)
        menu:AddMenuItem(vehicle_no_turbulence_heli)
    end
    if Permissions.is_allowed('VOAnchorBoat') then
        menu:AddMenuItem(vehicle_set_anchor)
    end
    if Permissions.is_allowed('VOFlip') then
        menu:AddMenuItem(flip_vehicle)
    end
    if Permissions.is_allowed('VOAlarm') then
        menu:AddMenuItem(vehicle_alarm)
    end
    if Permissions.is_allowed('VOCycleSeats') then
        menu:AddMenuItem(cycle_seats)
    end
    if Permissions.is_allowed('VOLights') then
        menu:AddMenuItem(vehicle_lights)
    end
    if Permissions.is_allowed('VOFixOrDestroyTires') then
        menu:AddMenuItem(vehicle_tires_list)
    end
    if Permissions.is_allowed('VODestroyEngine') then
        menu:AddMenuItem(destroy_engine)
    end
    if Permissions.is_allowed('VOFreeze') then
        menu:AddMenuItem(vehicle_freeze)
    end
    if Permissions.is_allowed('VOInvisible') then
        menu:AddMenuItem(vehicle_invisible)
    end
    if Permissions.is_allowed('VOEngineAlwaysOn') then
        menu:AddMenuItem(vehicle_engine_ao)
    end
    if Permissions.is_allowed('VOInfiniteFuel') then
        menu:AddMenuItem(infinite_fuel)
    end
    -- always allowed
    menu:AddMenuItem(show_health)
    menu:AddMenuItem(vehicle_radio_override)
    menu:AddMenuItem(radio_stations)

    if Permissions.is_allowed('VONoSiren') and not Config.get_bool('vmenu_use_els_compatibility_mode') then
        menu:AddMenuItem(vehicle_no_siren)
    end
    if Permissions.is_allowed('VONoHelmet') then
        menu:AddMenuItem(vehicle_no_bike_helmet)
    end
    if Permissions.is_allowed('VOFlashHighbeamsOnHonk') then
        menu:AddMenuItem(highbeams_on_honk)
    end
    if Permissions.is_allowed('VODelete') then
        menu:AddMenuItem(delete_btn)
    end

    -- delete confirm submenu
    delete_confirm_menu:AddMenuItem(delete_no_btn)
    delete_confirm_menu:AddMenuItem(delete_yes_btn)
    delete_confirm_menu.OnItemSelect = function(_, item, _index)
        if item == delete_no_btn then
            delete_confirm_menu:GoBack()
        else
            VehicleCommon.delete_vehicle()
            delete_confirm_menu:GoBack()
        end
    end

    -- bind submenus to their buttons
    Controller.BindMenuItem(menu, mod_menu, mod_menu_btn)
    Controller.BindMenuItem(menu, doors_menu, doors_menu_btn)
    Controller.BindMenuItem(menu, windows_menu, windows_menu_btn)
    Controller.BindMenuItem(menu, components_menu, components_menu_btn)
    Controller.BindMenuItem(menu, liveries_menu, liveries_menu_btn)
    Controller.BindMenuItem(menu, colors_menu, colors_menu_btn)
    Controller.BindMenuItem(menu, delete_confirm_menu, delete_btn)

    -- main button presses
    on(menu, 'OnItemSelect', function(_, item, _index)
        if item == delete_btn then
            -- reset so "no"/"cancel" is always selected by default
            delete_confirm_menu:RefreshIndex()
        end
        local vehicle = get_vehicle()
        if vehicle_exists(vehicle) then
            if player_is_driver(vehicle) then
                if item == fix_vehicle then
                    SetVehicleFixed(vehicle)
                elseif item == clean_vehicle then
                    SetVehicleDirtLevel(vehicle, 0.0)
                elseif item == flip_vehicle then
                    SetVehicleOnGroundProperly(vehicle)
                elseif item == vehicle_alarm then
                    VehicleCommon.toggle_vehicle_alarm(vehicle)
                elseif item == toggle_engine then
                    SetVehicleEngineOn(vehicle, not GetIsVehicleEngineRunning(vehicle), false, true)
                elseif item == set_license_plate_text then
                    Common.set_license_plate_custom_text()
                elseif item == vehicle_invisible then
                    if IsEntityVisible(vehicle) then
                        -- preserve the visibility of everyone inside
                        local visible_peds = {}
                        for seat = -1, GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) - 2 do
                            local occupant = GetPedInVehicleSeat(vehicle, seat)
                            if occupant ~= 0 then
                                visible_peds[#visible_peds + 1] = {
                                    ped = occupant,
                                    visible = IsEntityVisible(occupant),
                                }
                            end
                        end
                        SetEntityVisible(vehicle, false, false)
                        for _, entry in ipairs(visible_peds) do
                            SetEntityVisible(entry.ped, entry.visible, false)
                        end
                    else
                        SetEntityVisible(vehicle, true, false)
                    end
                elseif item == destroy_engine then
                    SetVehicleEngineHealth(vehicle, -4000)
                end
            elseif item ~= cycle_seats then
                Notify.error('You have to be the driver of a vehicle to access this menu!', true, false)
            end
            if item == cycle_seats then
                Common.cycle_through_seats()
            end
        end
    end)

    -- checkbox changes
    menu.OnCheckboxChange = function(_, item, _index, checked)
        local vehicle = get_vehicle()

        if item == vehicle_god then
            self.VehicleGodMode = checked
        elseif item == vehicle_freeze then
            self.VehicleFrozen = checked
            if not checked and vehicle_exists(vehicle) then
                FreezeEntityPosition(vehicle, false)
            end
        elseif item == torque_enabled then
            self.VehicleTorqueMultiplier = checked
        elseif item == power_enabled then
            self.VehiclePowerMultiplier = checked
            if vehicle_exists(vehicle) then
                SetVehicleEnginePowerMultiplier(vehicle, checked and self.VehiclePowerMultiplierAmount or 1.0)
            end
        elseif item == vehicle_engine_ao then
            self.VehicleEngineAlwaysOn = checked
        elseif item == show_health then
            self.VehicleShowHealth = checked
        elseif item == vehicle_radio_override then
            local starter_channel = 0 -- LosSantosRockRadio
            self.VehicleRadioOverride = checked
            UserDefaults.set_int('vehicleDefaultRadio', checked and starter_channel or -1)
            radio_stations.ListIndex = starter_channel
            radio_stations.Enabled = checked
        elseif item == vehicle_no_siren then
            self.VehicleNoSiren = checked
            if vehicle_exists(vehicle) then
                -- Vehicle.IsSirenSilent (mismapped FiveM native name)
                DisableVehicleImpactExplosionActivation(vehicle, checked)
            end
        elseif item == vehicle_no_bike_helmet then
            self.VehicleNoBikeHelemet = checked
        elseif item == highbeams_on_honk then
            self.FlashHighbeamsOnHonk = checked
        elseif item == vehicle_no_turbulence then
            self.DisablePlaneTurbulence = checked
            if vehicle_exists(vehicle) and IsThisModelAPlane(GetEntityModel(vehicle)) then
                SetPlaneTurbulenceMultiplier(vehicle, self.DisablePlaneTurbulence and 0.0 or 1.0)
            end
        elseif item == vehicle_no_turbulence_heli then
            self.DisableHelicopterTurbulence = checked
            if vehicle_exists(vehicle) and IsThisModelAHeli(GetEntityModel(vehicle)) then
                SetHeliTurbulenceScalar(vehicle, self.DisableHelicopterTurbulence and 0.0 or 1.0)
            end
        elseif item == vehicle_set_anchor then
            self.AnchorBoat = checked
            if vehicle_exists(vehicle) and IsThisModelABoat(GetEntityModel(vehicle)) and CanAnchorBoatHere(vehicle) then
                SetBoatAnchor(vehicle, self.AnchorBoat)
                SetBoatFrozenWhenAnchored(vehicle, self.AnchorBoat)
                SetForcedBoatLocationWhenAnchored(vehicle, self.AnchorBoat)
            end
        elseif item == vehicle_never_dirty then
            self.VehicleNeverDirty = checked
        elseif item == vehicle_bike_seatbelt then
            self.VehicleBikeSeatbelt = checked
        elseif item == infinite_fuel then
            self.VehicleInfiniteFuel = checked
            TriggerEvent('vMenu:InfiniteFuelToggled', checked)
        end
    end

    -- list changes
    menu.OnListIndexChange = function(_, item, _old_index, new_index, _item_index)
        local vehicle = get_vehicle()
        local veh_exists = vehicle_exists(vehicle)

        if veh_exists then
            if item == torque_multiplier then
                self.VehicleTorqueMultiplierAmount = tonumber((multiplier_values[new_index + 1]:gsub('x', ''))) + 0.0
            elseif item == power_multiplier then
                self.VehiclePowerMultiplierAmount = tonumber((multiplier_values[new_index + 1]:gsub('x', ''))) + 0.0
                if self.VehiclePowerMultiplier then
                    SetVehicleEnginePowerMultiplier(vehicle, self.VehiclePowerMultiplierAmount)
                end
            elseif item == set_license_plate_type then
                local style = PLATE_STYLE_BY_LIST_INDEX[new_index]
                if style ~= nil then
                    SetVehicleNumberPlateTextIndex(vehicle, style)
                end
            end
        end

        if item == radio_stations then
            local new_station = radio_value_for_index(new_index)
            if veh_exists and DoesPlayerVehHaveRadio() then
                set_vehicle_radio_station(vehicle, new_station)
            end
            UserDefaults.set_int('vehicleDefaultRadio', new_station)
        end
    end

    -- list item selections
    menu.OnListItemSelect = function(_, item, list_index, _item_index)
        if item == set_dirt_level then
            if IsPedInAnyVehicle(PlayerPedId(), false) then
                SetVehicleDirtLevel(get_vehicle(), list_index + 0.0)
            else
                Notify.error(Notification.error_message('NoVehicle'))
            end
        elseif item == vehicle_lights then
            if IsPedInAnyVehicle(PlayerPedId(), false) then
                local vehicle = get_vehicle()
                -- flags system; % 4 → 0 = none, 1 = left, 2 = right, 3 = both
                local state = GetVehicleIndicatorLights(vehicle) % 4
                if list_index == 0 then -- hazard lights
                    if state ~= 3 then
                        SetVehicleIndicatorLights(vehicle, 1, true)
                        SetVehicleIndicatorLights(vehicle, 0, true)
                    else
                        SetVehicleIndicatorLights(vehicle, 1, false)
                        SetVehicleIndicatorLights(vehicle, 0, false)
                    end
                elseif list_index == 1 then -- left indicator
                    if state ~= 1 then
                        SetVehicleIndicatorLights(vehicle, 1, true)
                        SetVehicleIndicatorLights(vehicle, 0, false)
                    else
                        SetVehicleIndicatorLights(vehicle, 1, false)
                        SetVehicleIndicatorLights(vehicle, 0, false)
                    end
                elseif list_index == 2 then -- right indicator
                    if state ~= 2 then
                        SetVehicleIndicatorLights(vehicle, 1, false)
                        SetVehicleIndicatorLights(vehicle, 0, true)
                    else
                        SetVehicleIndicatorLights(vehicle, 1, false)
                        SetVehicleIndicatorLights(vehicle, 0, false)
                    end
                elseif list_index == 3 then -- interior lights
                    SetVehicleInteriorlight(vehicle, not IsVehicleInteriorLightOn(vehicle))
                elseif list_index == 4 then -- helicopter spotlight
                    SetVehicleSearchlight(vehicle, not IsVehicleSearchlightOn(vehicle), true)
                end
            else
                Notify.error(Notification.error_message('NoVehicle'))
            end
        elseif item == speed_limiter then
            if IsPedInAnyVehicle(PlayerPedId(), false) then
                local vehicle = get_vehicle()
                if vehicle_exists(vehicle) then
                    if list_index == 0 then -- set
                        SetEntityMaxSpeed(vehicle, 500.01)
                        SetEntityMaxSpeed(vehicle, GetEntitySpeed(vehicle))
                        if ShouldUseMetricMeasurements() then
                            Notify.info(
                                ('Vehicle speed is now limited to ~b~%s KPH~s~.'):format(
                                    round1(GetEntitySpeed(vehicle) * 3.6)
                                )
                            )
                        else
                            Notify.info(
                                ('Vehicle speed is now limited to ~b~%s MPH~s~.'):format(
                                    round1(GetEntitySpeed(vehicle) * 2.237)
                                )
                            )
                        end
                    elseif list_index == 1 then -- reset
                        SetEntityMaxSpeed(vehicle, 500.01) -- default max speed seemingly for all vehicles
                        Notify.info('Vehicle speed is now no longer limited.')
                    elseif list_index == 2 then -- custom speed
                        local input_speed = Common.get_user_input('Enter a speed (in meters/sec)', '20.0', 5)
                        if input_speed ~= nil and input_speed ~= '' then
                            local out_float = tonumber(input_speed)
                            if out_float ~= nil then
                                SetEntityMaxSpeed(vehicle, 500.01)
                                Wait(0)
                                SetEntityMaxSpeed(vehicle, out_float + 0.01)
                                if ShouldUseMetricMeasurements() then
                                    Notify.info(
                                        ('Vehicle speed is now limited to ~b~%s KPH~s~.'):format(
                                            round1(out_float * 3.6)
                                        )
                                    )
                                else
                                    Notify.info(
                                        ('Vehicle speed is now limited to ~b~%s MPH~s~.'):format(
                                            round1(out_float * 2.237)
                                        )
                                    )
                                end
                            else
                                Notify.error(
                                    'This is not a valid number. Please enter a valid speed in meters per second.'
                                )
                            end
                        else
                            Notify.error(Notification.error_message('InvalidInput'))
                        end
                    end
                end
            end
        elseif item == vehicle_tires_list then
            local vehicle = get_vehicle()
            if vehicle_exists(vehicle) then
                if player_is_driver(vehicle) then
                    if list_index == 0 then
                        if IsVehicleTyreBurst(vehicle, 0, false) then
                            for tire = 0, 7 do
                                SetVehicleTyreFixed(vehicle, tire)
                            end
                            Notify.success('All vehicle tyres have been fixed.')
                        else
                            for tire = 0, 7 do
                                SetVehicleTyreBurst(vehicle, tire, false, 1.0)
                            end
                            Notify.success('All vehicle tyres have been destroyed.')
                        end
                    else
                        local tire = list_index - 1
                        if IsVehicleTyreBurst(vehicle, tire, false) then
                            SetVehicleTyreFixed(vehicle, tire)
                            Notify.success(('Vehicle tyre #%d has been fixed.'):format(list_index))
                        else
                            SetVehicleTyreBurst(vehicle, tire, false, 1.0)
                            Notify.success(('Vehicle tyre #%d has been destroyed.'):format(list_index))
                        end
                    end
                else
                    Notify.error(Notification.error_message('NeedToBeTheDriver'))
                end
            else
                Notify.error(Notification.error_message('NoVehicle'))
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Vehicle Colors submenu
    -- -----------------------------------------------------------------------

    local customize_color_menu = Menu.new('Vehicle Colors', 'Customize Colors')
    Controller.AddSubmenu(colors_menu, customize_color_menu)

    local colors_customization_btn = Items.MenuItem.new('Customize Colors')
    colors_customization_btn.Label = '→→→'
    colors_menu:AddMenuItem(colors_customization_btn)
    Controller.BindMenuItem(colors_menu, customize_color_menu, colors_customization_btn)

    local primary_colors_menu = Menu.new('Vehicle Colors', 'Primary Colors')
    Controller.AddSubmenu(customize_color_menu, primary_colors_menu)
    local primary_colors_btn = Items.MenuItem.new('Primary Color')
    primary_colors_btn.Label = '→→→'
    customize_color_menu:AddMenuItem(primary_colors_btn)
    Controller.BindMenuItem(customize_color_menu, primary_colors_menu, primary_colors_btn)

    local secondary_colors_menu = Menu.new('Vehicle Colors', 'Secondary Colors')
    Controller.AddSubmenu(customize_color_menu, secondary_colors_menu)
    local secondary_colors_btn = Items.MenuItem.new('Secondary Color')
    secondary_colors_btn.Label = '→→→'
    customize_color_menu:AddMenuItem(secondary_colors_btn)
    Controller.BindMenuItem(customize_color_menu, secondary_colors_menu, secondary_colors_btn)

    local preset_colors_btn = Items.MenuListItem.new('Preset Colors', {}, 0)
    customize_color_menu:AddMenuItem(preset_colors_btn)

    local chrome_btn = Items.MenuItem.new('Chrome')
    customize_color_menu:AddMenuItem(chrome_btn)

    -- color label lists ("{label} (i/count)")
    local using_chameleon = Config.get_bool('vmenu_using_chameleon_colours')
    local function color_labels(list)
        local labels = {}
        for i, color in ipairs(list) do
            labels[#labels + 1] = ('%s (%d/%d)'):format(GetLabelText(color.label), i, #list)
        end
        return labels
    end
    local classic = color_labels(VehicleData.ClassicColors)
    local matte = color_labels(VehicleData.MatteColors)
    local metals = color_labels(VehicleData.MetalColors)
    local util = color_labels(VehicleData.UtilColors)
    local worn = color_labels(VehicleData.WornColors)
    local chameleon = using_chameleon and color_labels(VehicleData.ChameleonColors) or {}
    local wheel_colors = { 'Default Alloy' }
    for _, label in ipairs(classic) do
        wheel_colors[#wheel_colors + 1] = label
    end

    local wheel_colors_list = Items.MenuListItem.new('Wheel Color', wheel_colors, 0)
    local dash_color_list = Items.MenuListItem.new('Dashboard Color', classic, 0)
    local int_color_list = Items.MenuListItem.new('Interior / Trim Color', classic, 0)
    local vehicle_enveff_scale = Items.MenuSliderItem.new(
        'Vehicle Enveff Scale',
        0,
        20,
        10,
        "This works on certain vehicles only, like the besra for example. It 'fades' certain paint layers."
    )
    vehicle_enveff_scale.ShowDivider = true

    colors_menu:AddMenuItem(vehicle_enveff_scale)

    colors_menu.OnSliderPositionChange = function(_, slider_item, _old_position, new_position, _item_index)
        local vehicle = get_vehicle()
        if vehicle_exists(vehicle) and player_is_driver(vehicle) and not IsEntityDead(vehicle) then
            if slider_item == vehicle_enveff_scale then
                SetVehicleEnveffScale(vehicle, new_position / 20)
            end
        else
            Notify.error('You need to be the driver of a driveable vehicle to change this slider.')
        end
    end

    colors_menu:AddMenuItem(dash_color_list)
    colors_menu:AddMenuItem(int_color_list)
    colors_menu:AddMenuItem(wheel_colors_list)

    local function handle_list_index_changes(sender, list_item, _old_index, new_index, item_index)
        local vehicle = get_vehicle()
        if vehicle_exists(vehicle) and not IsEntityDead(vehicle) and player_is_driver(vehicle) then
            local primary_color, secondary_color = GetVehicleColours(vehicle)
            local pearl_color, wheel_color = GetVehicleExtraColours(vehicle)

            if sender == primary_colors_menu then
                if item_index == 2 then
                    pearl_color = VehicleData.ClassicColors[new_index + 1].id
                else
                    pearl_color = 0
                end

                if item_index == 0 or item_index == 1 or item_index == 2 then
                    primary_color = VehicleData.ClassicColors[new_index + 1].id
                elseif item_index == 3 then
                    primary_color = VehicleData.MatteColors[new_index + 1].id
                elseif item_index == 4 then
                    primary_color = VehicleData.MetalColors[new_index + 1].id
                elseif item_index == 5 then
                    primary_color = VehicleData.UtilColors[new_index + 1].id
                elseif item_index == 6 then
                    primary_color = VehicleData.WornColors[new_index + 1].id
                end

                if using_chameleon and item_index == 7 then
                    primary_color = VehicleData.ChameleonColors[new_index + 1].id
                    secondary_color = VehicleData.ChameleonColors[new_index + 1].id
                    SetVehicleModKit(vehicle, 0)
                end

                ClearVehicleCustomPrimaryColour(vehicle)
                Entity(vehicle).state:set('vMenu:PrimaryPaintFinish', nil, true)
                SetVehicleColours(vehicle, primary_color, secondary_color)
            elseif sender == secondary_colors_menu then
                if item_index == 0 or item_index == 1 then
                    pearl_color = VehicleData.ClassicColors[new_index + 1].id
                elseif item_index == 2 or item_index == 3 then
                    secondary_color = VehicleData.ClassicColors[new_index + 1].id
                elseif item_index == 4 then
                    secondary_color = VehicleData.MatteColors[new_index + 1].id
                elseif item_index == 5 then
                    secondary_color = VehicleData.MetalColors[new_index + 1].id
                elseif item_index == 6 then
                    secondary_color = VehicleData.UtilColors[new_index + 1].id
                elseif item_index == 7 then
                    secondary_color = VehicleData.WornColors[new_index + 1].id
                end

                ClearVehicleCustomSecondaryColour(vehicle)
                Entity(vehicle).state:set('vMenu:SecondaryPaintFinish', nil, true)
                SetVehicleColours(vehicle, primary_color, secondary_color)
            elseif sender == colors_menu then
                if list_item == wheel_colors_list then
                    if new_index == 0 then
                        wheel_color = 156 -- default alloy color
                    else
                        wheel_color = VehicleData.ClassicColors[new_index].id
                    end
                elseif list_item == dash_color_list then
                    -- native names are mixed up (backwards compatibility);
                    -- this is really "set dashboard colour"
                    SetVehicleInteriorColour(vehicle, VehicleData.ClassicColors[new_index + 1].id)
                elseif list_item == int_color_list then
                    -- and this is really "set interior colour"
                    SetVehicleDashboardColour(vehicle, VehicleData.ClassicColors[new_index + 1].id)
                end
            end

            SetVehicleExtraColours(vehicle, pearl_color, wheel_color)
        else
            Notify.error('You need to be the driver of a vehicle in order to change the vehicle colors.')
        end
    end

    colors_menu.OnListIndexChange = handle_list_index_changes

    for i = 0, 1 do
        local custom_colour = Items.MenuItem.new('Custom RGB')
        custom_colour.Label = '→→→'
        local pearlescent_list = Items.MenuListItem.new('Pearlescent', classic, 0)
        local classic_list = Items.MenuListItem.new('Classic', classic, 0)
        local metallic_list = Items.MenuListItem.new('Metallic', classic, 0)
        local matte_list = Items.MenuListItem.new('Matte', matte, 0)
        local metal_list = Items.MenuListItem.new('Metals', metals, 0)
        local util_list = Items.MenuListItem.new('Util', util, 0)
        local worn_list = Items.MenuListItem.new('Worn', worn, 0)

        if i == 0 then
            local custom_colour_menu_primary = Menu.new('Custom Colour', 'Custom Vehicle Colour')
            primary_colors_menu:AddMenuItem(custom_colour)
            primary_colors_menu:AddMenuItem(classic_list)
            primary_colors_menu:AddMenuItem(metallic_list)
            primary_colors_menu:AddMenuItem(matte_list)
            primary_colors_menu:AddMenuItem(metal_list)
            primary_colors_menu:AddMenuItem(util_list)
            primary_colors_menu:AddMenuItem(worn_list)
            Controller.AddSubmenu(primary_colors_menu, custom_colour_menu_primary)
            Controller.BindMenuItem(primary_colors_menu, custom_colour_menu_primary, custom_colour)

            if using_chameleon then
                local chameleon_list = Items.MenuListItem.new('Chameleon', chameleon, 0)
                primary_colors_menu:AddMenuItem(chameleon_list)
            end

            create_custom_colour_menu(custom_colour_menu_primary, 'primaryPaint')
            primary_colors_menu.OnListIndexChange = handle_list_index_changes
        else
            local custom_colour_menu_secondary = Menu.new('Custom Colour', 'Custom Vehicle Colour')
            secondary_colors_menu:AddMenuItem(custom_colour)
            secondary_colors_menu:AddMenuItem(pearlescent_list)
            secondary_colors_menu:AddMenuItem(classic_list)
            secondary_colors_menu:AddMenuItem(metallic_list)
            secondary_colors_menu:AddMenuItem(matte_list)
            secondary_colors_menu:AddMenuItem(metal_list)
            secondary_colors_menu:AddMenuItem(util_list)
            secondary_colors_menu:AddMenuItem(worn_list)
            Controller.AddSubmenu(secondary_colors_menu, custom_colour_menu_secondary)
            Controller.BindMenuItem(secondary_colors_menu, custom_colour_menu_secondary, custom_colour)

            create_custom_colour_menu(custom_colour_menu_secondary, 'secondaryPaint')
            secondary_colors_menu.OnListIndexChange = handle_list_index_changes
        end
    end

    customize_color_menu.OnMenuOpen = function(_)
        local vehicle = get_vehicle()
        local num_veh_colors = GetNumberOfVehicleColours(vehicle)

        if num_veh_colors == 0 then
            preset_colors_btn.Enabled = false
            preset_colors_btn.ListItems = { 'No Preset Colors' }
            preset_colors_btn.ListIndex = 0
            return
        end

        preset_colors_btn.Enabled = true
        local color_options = {}
        for i = 1, num_veh_colors do
            color_options[#color_options + 1] = ('Preset Color #%d'):format(i)
        end

        local current_color = GetVehicleColourCombination(vehicle)
        preset_colors_btn.ListItems = color_options
        preset_colors_btn.ListIndex = current_color < 0 and 0 or current_color
    end

    customize_color_menu.OnItemSelect = function(_, item, _index)
        local vehicle = get_vehicle()
        if vehicle_exists(vehicle) and not IsEntityDead(vehicle) and player_is_driver(vehicle) then
            if item == chrome_btn then
                SetVehicleColours(vehicle, 120, 120) -- chrome is index 120
            end
        else
            Notify.error('You need to be the driver of a driveable vehicle to change this.')
        end
    end

    local function change_vehicle_preset_color(index)
        local vehicle = get_vehicle()
        if vehicle_exists(vehicle) and not IsEntityDead(vehicle) and player_is_driver(vehicle) then
            SetVehicleColourCombination(vehicle, index)
        else
            Notify.error('You need to be the driver of a driveable vehicle to change this.')
        end
    end
    customize_color_menu.OnListItemSelect = function(_, _item, selected_index, _item_index)
        change_vehicle_preset_color(selected_index)
    end
    customize_color_menu.OnListIndexChange = function(_, _item, _old_index, new_index, _item_index)
        change_vehicle_preset_color(new_index)
    end

    -- -----------------------------------------------------------------------
    -- Vehicle Doors submenu
    -- -----------------------------------------------------------------------

    local open_all = Items.MenuItem.new('Open All Doors', 'Open all vehicle doors.')
    local close_all = Items.MenuItem.new('Close All Doors', 'Close all vehicle doors.')
    local door_items = {
        Items.MenuItem.new('Left Front Door', 'Open/close the left front door.'),
        Items.MenuItem.new('Right Front Door', 'Open/close the right front door.'),
        Items.MenuItem.new('Left Rear Door', 'Open/close the left rear door.'),
        Items.MenuItem.new('Right Rear Door', 'Open/close the right rear door.'),
        Items.MenuItem.new('Hood', 'Open/close the hood.'),
        Items.MenuItem.new('Trunk', 'Open/close the trunk.'),
        Items.MenuItem.new(
            'Extra 1',
            'Open/close the extra door (#1). Note this door is not present on most vehicles.'
        ),
        Items.MenuItem.new(
            'Extra 2',
            'Open/close the extra door (#2). Note this door is not present on most vehicles.'
        ),
    }
    local bomb_bay = Items.MenuItem.new('Bomb Bay', 'Open/close the bomb bay. Only available on some planes.')
    local remove_door_list = Items.MenuListItem.new(
        'Remove Door',
        { 'Front Left', 'Front Right', 'Rear Left', 'Rear Right', 'Hood', 'Trunk', 'Extra 1', 'Extra 2' },
        0,
        'Remove a specific vehicle door completely.'
    )
    local delete_doors = Items.MenuCheckboxItem.new(
        'Delete Removed Doors',
        'When enabled, doors that you remove using the list above will be deleted from the world. If disabled, then '
            .. 'the doors will just fall on the ground.',
        false
    )

    for _, item in ipairs(door_items) do
        doors_menu:AddMenuItem(item)
    end
    doors_menu:AddMenuItem(bomb_bay)
    doors_menu:AddMenuItem(open_all)
    doors_menu:AddMenuItem(close_all)
    doors_menu:AddMenuItem(remove_door_list)
    doors_menu:AddMenuItem(delete_doors)

    doors_menu.OnListItemSelect = function(_, item, selected_index, _item_index)
        local vehicle = get_vehicle()
        if vehicle_exists(vehicle) then
            if player_is_driver(vehicle) then
                if item == remove_door_list then
                    SetVehicleDoorBroken(vehicle, selected_index, delete_doors.Checked)
                end
            else
                Notify.error(Notification.error_message('NeedToBeTheDriver'))
            end
        else
            Notify.error(Notification.error_message('NoVehicle'))
        end
    end

    doors_menu.OnItemSelect = function(_, item, index)
        local vehicle = get_vehicle()
        if vehicle_exists(vehicle) and not IsEntityDead(vehicle) and player_is_driver(vehicle) then
            local has_bomb_bay = Citizen.InvokeNative(0x6D6AF961B72728AE, vehicle) -- Vehicle.HasBombBay
            if index < 8 then
                local open = GetVehicleDoorAngleRatio(vehicle, index) > 0.1
                if open then
                    SetVehicleDoorShut(vehicle, index, false)
                else
                    SetVehicleDoorOpen(vehicle, index, false, false)
                end
            elseif item == open_all then
                for door = 0, 7 do
                    SetVehicleDoorOpen(vehicle, door, false, false)
                end
                if has_bomb_bay then
                    OpenBombBayDoors(vehicle)
                end
            elseif item == close_all then
                SetVehicleDoorsShut(vehicle, false)
                if has_bomb_bay then
                    CloseBombBayDoors(vehicle)
                end
            elseif item == bomb_bay and has_bomb_bay then
                if AreBombBayDoorsOpen(vehicle) then
                    CloseBombBayDoors(vehicle)
                else
                    OpenBombBayDoors(vehicle)
                end
            end
        else
            Notify.alert(Notification.error_message('NoVehicle', 'to open/close a vehicle door'))
        end
    end

    -- -----------------------------------------------------------------------
    -- Vehicle Windows submenu
    -- -----------------------------------------------------------------------

    local fwu = Items.MenuItem.new('~y~↑~s~ Roll Front Windows Up', 'Roll both front windows up.')
    local fwd = Items.MenuItem.new('~o~↓~s~ Roll Front Windows Down', 'Roll both front windows down.')
    local rwu = Items.MenuItem.new('~y~↑~s~ Roll Rear Windows Up', 'Roll both rear windows up.')
    local rwd = Items.MenuItem.new('~o~↓~s~ Roll Rear Windows Down', 'Roll both rear windows down.')
    windows_menu:AddMenuItem(fwu)
    windows_menu:AddMenuItem(fwd)
    windows_menu:AddMenuItem(rwu)
    windows_menu:AddMenuItem(rwd)
    windows_menu.OnItemSelect = function(_, item, _index)
        local vehicle = get_vehicle()
        if vehicle_exists(vehicle) and not IsEntityDead(vehicle) then
            if item == fwu then
                RollUpWindow(vehicle, 0)
                RollUpWindow(vehicle, 1)
            elseif item == fwd then
                RollDownWindow(vehicle, 0)
                RollDownWindow(vehicle, 1)
            elseif item == rwu then
                RollUpWindow(vehicle, 2)
                RollUpWindow(vehicle, 3)
            elseif item == rwd then
                RollDownWindow(vehicle, 2)
                RollDownWindow(vehicle, 3)
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Vehicle Liveries submenu (rebuilt when the button is selected)
    -- -----------------------------------------------------------------------

    on(menu, 'OnItemSelect', function(_, item, _index)
        if item ~= liveries_menu_btn then
            return
        end
        local vehicle = get_vehicle()
        if vehicle_exists(vehicle) and not IsEntityDead(vehicle) then
            if player_is_driver(vehicle) then
                liveries_menu:ClearMenuItems()
                SetVehicleModKit(vehicle, 0)
                local livery_count = GetVehicleLiveryCount(vehicle)

                if livery_count > 0 then
                    local livery_list = {}
                    for i = 0, livery_count - 1 do
                        local livery = GetLiveryName(vehicle, i)
                        livery = GetLabelText(livery) ~= 'NULL' and GetLabelText(livery) or ('Livery #%d'):format(i)
                        livery_list[#livery_list + 1] = livery
                    end
                    local livery_list_item = Items.MenuListItem.new(
                        'Set Livery',
                        livery_list,
                        GetVehicleLivery(vehicle),
                        'Choose a livery for this vehicle.'
                    )
                    liveries_menu:AddMenuItem(livery_list_item)
                    liveries_menu.OnListIndexChange = function(_menu, list_item, _old_index, new_index, _item_index)
                        if list_item == livery_list_item then
                            SetVehicleLivery(get_vehicle(), new_index)
                        end
                    end
                    liveries_menu:RefreshIndex()
                else
                    Notify.error('This vehicle does not have any liveries.')
                    liveries_menu:CloseMenu()
                    menu:OpenMenu()
                    local back_btn = Items.MenuItem.new('No Liveries Available :(', 'Click me to go back.')
                    back_btn.Label = 'Go Back'
                    liveries_menu:AddMenuItem(back_btn)
                    liveries_menu.OnItemSelect = function(_menu, item2, _index2)
                        if item2 == back_btn then
                            liveries_menu:GoBack()
                        end
                    end
                    liveries_menu:RefreshIndex()
                end
            else
                Notify.error('You have to be the driver of a vehicle to access this menu.')
            end
        else
            Notify.error('You have to be the driver of a vehicle to access this menu.')
        end
    end)

    -- -----------------------------------------------------------------------
    -- Vehicle Mod submenu (dynamic; rebuilt by update_mods)
    -- -----------------------------------------------------------------------

    local update_mods -- forward declaration (wheel type changes re-enter it)

    on(menu, 'OnItemSelect', function(_, item, _index)
        if item == mod_menu_btn then
            if IsPedInAnyVehicle(PlayerPedId(), false) then
                update_mods()
            else
                mod_menu:CloseMenu()
                menu:OpenMenu()
            end
        end
    end)

    -- -----------------------------------------------------------------------
    -- Vehicle Components (extras) submenu
    -- -----------------------------------------------------------------------

    on(menu, 'OnItemSelect', function(_, item, _index)
        if item ~= components_menu_btn then
            return
        end
        -- empty the menu in case there were leftover buttons from another vehicle
        if components_menu:Size() > 0 then
            components_menu:ClearMenuItems()
            vehicle_extras_map = {}
            components_menu:RefreshIndex()
        end

        local vehicle = get_vehicle()
        if vehicle_exists(vehicle) and not IsEntityDead(vehicle) and player_is_driver(vehicle) then
            local extra_labels = State.vehicle_extras[GetEntityModel(vehicle)] or {}

            for extra = 0, 13 do
                if DoesExtraExist(vehicle, extra) then
                    -- extras.json arrives string-keyed (C# Dictionary<int,string>)
                    local extra_label = extra_labels[tostring(extra)]
                        or extra_labels[extra]
                        or ('Extra #%d'):format(extra)
                    local extra_checkbox =
                        Items.MenuCheckboxItem.new(extra_label, tostring(extra), IsVehicleExtraTurnedOn(vehicle, extra))
                    components_menu:AddMenuItem(extra_checkbox)
                    vehicle_extras_map[extra_checkbox] = extra
                end
            end

            if next(vehicle_extras_map) ~= nil then
                local back_btn = Items.MenuItem.new('Go Back', 'Go back to the Vehicle Options menu.')
                components_menu:AddMenuItem(back_btn)
                components_menu.OnItemSelect = function(_menu, _item, _index2)
                    components_menu:GoBack()
                end
            else
                local back_btn = Items.MenuItem.new('No Extras Available :(', 'Go back to the Vehicle Options menu.')
                back_btn.Label = 'Go Back'
                components_menu:AddMenuItem(back_btn)
                components_menu.OnItemSelect = function(_menu, _item, _index2)
                    components_menu:GoBack()
                end
            end
            components_menu:RefreshIndex()
        end
    end)

    -- disable all extra options if the vehicle is too damaged
    components_menu.OnMenuOpen = function(m)
        local check_damage = Config.get_bool('vmenu_prevent_extras_when_damaged')
            and not Permissions.is_allowed('VOBypassExtraDamage')
        local vehicle = get_vehicle()
        if not check_damage or not vehicle_exists(vehicle) then
            return
        end

        local menu_items = {}
        for _, item in ipairs(m:GetMenuItems()) do
            menu_items[#menu_items + 1] = item
        end
        local is_too_damaged = is_vehicle_too_damaged_to_change_extras(vehicle)

        m:ClearMenuItems()

        local has_spacer = false
        for _, item in ipairs(menu_items) do
            if item.Text:find('too damaged', 1, true) then
                has_spacer = true
            end
        end
        if is_too_damaged and not has_spacer then
            table.insert(
                menu_items,
                1,
                Common.get_spacer_menu_item(
                    'Vehicle too damaged!',
                    'Vehicle is too damaged to change extras, repair it first!'
                )
            )
        end

        for _, item in ipairs(menu_items) do
            local skip = false
            if item.Text:find('too damaged', 1, true) then
                if not is_too_damaged then
                    skip = true
                end
            elseif item.Text ~= 'Go Back' then
                item.Enabled = not is_too_damaged
            end
            if not skip then
                m:AddMenuItem(item)
            end
        end

        m:RefreshIndex()
    end

    components_menu.OnCheckboxChange = function(_, item, _index, checked)
        local extra = vehicle_extras_map[item]
        if extra == nil then
            return
        end
        local vehicle = get_vehicle()
        if not vehicle_exists(vehicle) then
            Notify.error(Notification.error_message('NoVehicle'))
            return
        end

        local check_damage = Config.get_bool('vmenu_prevent_extras_when_damaged')
            and not Permissions.is_allowed('VOBypassExtraDamage')
        if check_damage and is_vehicle_too_damaged_to_change_extras(vehicle) then
            Notify.alert('Vehicle is too damaged to change extra, repair it first!', true, false)
            components_menu:GoBack()
            return
        end

        -- Vehicle.ToggleExtra(extra, toggle) → SetVehicleExtra(veh, extra, !toggle)
        SetVehicleExtra(vehicle, extra, not checked)
    end

    -- -----------------------------------------------------------------------
    -- Underglow submenu
    -- -----------------------------------------------------------------------

    local underglow_front = Items.MenuCheckboxItem.new(
        'Enable Front Light',
        'Enable or disable the underglow on the front side of the vehicle. Note not all vehicles have lights.',
        false
    )
    local underglow_back = Items.MenuCheckboxItem.new(
        'Enable Rear Light',
        'Enable or disable the underglow on the left side of the vehicle. Note not all vehicles have lights.',
        false
    )
    local underglow_left = Items.MenuCheckboxItem.new(
        'Enable Left Light',
        'Enable or disable the underglow on the right side of the vehicle. Note not all vehicles have lights.',
        false
    )
    local underglow_right = Items.MenuCheckboxItem.new(
        'Enable Right Light',
        'Enable or disable the underglow on the back side of the vehicle. Note not all vehicles have lights.',
        false
    )
    local underglow_colors_list = {}
    for i = 0, 12 do
        underglow_colors_list[#underglow_colors_list + 1] = GetLabelText(('CMOD_NEONCOL_%d'):format(i))
    end
    local underglow_color = Items.MenuListItem.new(
        GetLabelText('CMOD_NEON_1'),
        underglow_colors_list,
        0,
        'Select the color of the neon underglow.'
    )

    underglow_menu:AddMenuItem(underglow_front)
    underglow_menu:AddMenuItem(underglow_back)
    underglow_menu:AddMenuItem(underglow_left)
    underglow_menu:AddMenuItem(underglow_right)
    underglow_menu:AddMenuItem(underglow_color)

    create_custom_colour_menu(underglow_menu, 'underglow')

    local underglow_checkboxes = { underglow_front, underglow_back, underglow_left, underglow_right }
    on(menu, 'OnItemSelect', function(_, item, _index)
        -- reset checkbox state when opening the underglow menu
        if item ~= underglow_menu_btn then
            return
        end
        local vehicle = get_vehicle()
        if vehicle ~= 0 and has_neon_lights(vehicle) then
            underglow_front.Checked = has_neon_light(vehicle, 2) and IsVehicleNeonLightEnabled(vehicle, 2)
            underglow_back.Checked = has_neon_light(vehicle, 3) and IsVehicleNeonLightEnabled(vehicle, 3)
            underglow_left.Checked = has_neon_light(vehicle, 0) and IsVehicleNeonLightEnabled(vehicle, 0)
            underglow_right.Checked = has_neon_light(vehicle, 1) and IsVehicleNeonLightEnabled(vehicle, 1)
            for _, checkbox in ipairs(underglow_checkboxes) do
                checkbox.Enabled = true
                checkbox.LeftIcon = Items.Icon.NONE
            end
        else
            for _, checkbox in ipairs(underglow_checkboxes) do
                checkbox.Checked = false
                checkbox.Enabled = false
                checkbox.LeftIcon = Items.Icon.LOCK
            end
        end
        underglow_color.ListIndex = get_index_from_color()
    end)

    underglow_menu.OnCheckboxChange = function(_, item, _index, checked)
        if IsPedInAnyVehicle(PlayerPedId(), false) then
            local vehicle = get_vehicle()
            if has_neon_lights(vehicle) then
                SetVehicleNeonLightsColour(vehicle, get_color_from_index(underglow_color.ListIndex))
                if item == underglow_left then
                    SetVehicleNeonLightEnabled(vehicle, 0, has_neon_light(vehicle, 0) and checked)
                elseif item == underglow_right then
                    SetVehicleNeonLightEnabled(vehicle, 1, has_neon_light(vehicle, 1) and checked)
                elseif item == underglow_back then
                    SetVehicleNeonLightEnabled(vehicle, 3, has_neon_light(vehicle, 3) and checked)
                elseif item == underglow_front then
                    SetVehicleNeonLightEnabled(vehicle, 2, has_neon_light(vehicle, 2) and checked)
                end
            end
        end
    end

    on(underglow_menu, 'OnListIndexChange', function(_, item, _old_index, new_index, _item_index)
        if item == underglow_color then
            if IsPedInAnyVehicle(PlayerPedId(), false) then
                local vehicle = get_vehicle()
                if has_neon_lights(vehicle) then
                    SetVehicleNeonLightsColour(vehicle, get_color_from_index(new_index))
                end
            end
        end
    end)

    -- refresh the license plate type when the menu opens
    on(menu, 'OnMenuOpen', function(m)
        for _, item in ipairs(m:GetMenuItems()) do
            local vehicle = Common.get_vehicle(true)
            if item == set_license_plate_type and vehicle_exists(vehicle) then
                local list_index = LIST_INDEX_BY_PLATE_STYLE[GetVehicleNumberPlateTextIndex(vehicle)]
                if list_index ~= nil then
                    item.ListIndex = list_index
                end
            end
        end
    end)

    -- -----------------------------------------------------------------------
    -- UpdateMods (rebuilds the Mod Menu for the current vehicle)
    -- -----------------------------------------------------------------------

    update_mods = function(selected_index)
        selected_index = selected_index or 0
        if mod_menu:Size() > 0 then
            mod_menu:ClearMenuItems(selected_index ~= 0)
        end

        local vehicle = get_vehicle()
        if not vehicle_exists(vehicle) or IsEntityDead(vehicle) then
            if selected_index == 0 then
                mod_menu:RefreshIndex()
            end
            return
        end

        SetVehicleModKit(vehicle, 0)

        -- dynamic (vehicle-specific) mods
        for _, mod in ipairs(VehicleCommon.get_all_vehicle_mods(vehicle)) do
            local type_name = ModNames.localized_mod_type_name(vehicle, mod.mod_type)
            local modlist = {}
            local mod_count = GetNumVehicleMods(vehicle, mod.mod_type)
            modlist[#modlist + 1] = ('Stock %s [1/%d]'):format(type_name, mod_count + 1)
            for x = 0, mod_count - 1 do
                local current_item = ('[%d/%d]'):format(2 + x, mod_count + 1)
                local mod_name = ModNames.get_localized_mod_name(vehicle, mod.mod_type, x)
                if mod_name ~= '' then
                    modlist[#modlist + 1] = ('%s %s'):format(Common.to_proper_string(mod_name), current_item)
                else
                    modlist[#modlist + 1] = ('%s #%d %s'):format(type_name, x, current_item)
                end
            end

            local curr_index = GetVehicleMod(vehicle, mod.mod_type) + 1
            local mod_type_list_item = Items.MenuListItem.new(
                type_name,
                modlist,
                curr_index,
                ('Choose a ~y~%s~s~ upgrade, it will be automatically applied to your vehicle.'):format(type_name)
            )
            mod_type_list_item.ItemData = mod.mod_type
            mod_menu:AddMenuItem(mod_type_list_item)
        end

        -- wheel types
        local wheel_type_index = GetVehicleWheelType(vehicle)
        if wheel_type_index < 0 then
            wheel_type_index = 0
        elseif wheel_type_index > 12 then
            wheel_type_index = 12
        end
        local vehicle_wheel_type = Items.MenuListItem.new('Wheel Type', {
            'Sports', -- 0
            'Muscle', -- 1
            'Lowrider', -- 2
            'SUV', -- 3
            'Offroad', -- 4
            'Tuner', -- 5
            'Bike Wheels', -- 6
            'High End', -- 7
            "Benny's (1)", -- 8
            "Benny's (2)", -- 9
            'Open Wheel', -- 10
            'Street', -- 11
            'Track', -- 12
        }, wheel_type_index, 'Choose a ~y~wheel type~s~ for your vehicle.')
        local model = GetEntityModel(vehicle)
        if
            not IsThisModelABoat(model)
            and not IsThisModelAHeli(model)
            and not IsThisModelAPlane(model)
            and not IsThisModelABicycle(model)
            and not IsThisModelATrain(model)
        then
            mod_menu:AddMenuItem(vehicle_wheel_type)
        end

        -- headlights submenu
        local headlights_button = Items.MenuItem.new('Headlights')
        local headlights_menu = Menu.new('Headlights', 'headlights')
        local xenon_headlights = Items.MenuCheckboxItem.new(
            'Xenon Headlights',
            'Enable or disable ~b~xenon ~s~headlights.',
            IsToggleModOn(vehicle, 22)
        )
        headlights_menu:AddMenuItem(xenon_headlights)
        local current_headlight_color = VehicleCommon.get_headlights_color_for_vehicle(vehicle)
        if current_headlight_color < 0 or current_headlight_color > 12 then
            current_headlight_color = 13
        end
        local headlight_color = Items.MenuListItem.new(
            'Headlight Color',
            {
                'White',
                'Blue',
                'Electric Blue',
                'Mint Green',
                'Lime Green',
                'Yellow',
                'Golden Shower',
                'Orange',
                'Red',
                'Pony Pink',
                'Hot Pink',
                'Purple',
                'Blacklight',
                'Default Xenon',
            },
            current_headlight_color,
            'New in the Arena Wars GTA V update: Colored headlights. Note you must enable Xenon Headlights first.'
        )
        headlights_menu:AddMenuItem(headlight_color)
        headlights_menu.OnCheckboxChange = function(_, item2, _index2, checked)
            if item2 == xenon_headlights then
                ToggleVehicleMod(get_vehicle(), 22, checked)
            end
        end
        on(headlights_menu, 'OnListIndexChange', function(_, item2, _old_index, new_index, _item_index)
            local veh = get_vehicle()
            if item2 == headlight_color then
                if new_index == 13 then -- default
                    VehicleCommon.set_headlights_color_for_vehicle(veh, 255)
                elseif new_index > -1 and new_index < 13 then
                    ClearVehicleXenonLightsCustomColor(veh)
                    VehicleCommon.set_headlights_color_for_vehicle(veh, new_index)
                end
            end
        end)
        Controller.AddSubmenu(mod_menu, headlights_menu)
        Controller.BindMenuItem(mod_menu, headlights_menu, headlights_button)
        mod_menu:AddMenuItem(headlights_button)
        create_custom_colour_menu(headlights_menu, 'headlight')

        -- option checkboxes
        local toggle_custom_wheels = Items.MenuCheckboxItem.new(
            'Toggle Custom Wheels',
            'Press this to add or remove ~y~custom~s~ wheels.',
            GetVehicleModVariation(vehicle, 23)
        )
        local turbo = Items.MenuCheckboxItem.new(
            'Turbo',
            'Enable or disable the ~y~turbo~s~ for this vehicle.',
            IsToggleModOn(vehicle, 18)
        )
        local bullet_proof_tires = Items.MenuCheckboxItem.new(
            'Bullet Proof Tires',
            'Enable or disable ~y~bullet proof tires~s~ for this vehicle.',
            not GetVehicleTyresCanBurst(vehicle)
        )

        mod_menu:AddMenuItem(toggle_custom_wheels)
        mod_menu:AddMenuItem(turbo)
        mod_menu:AddMenuItem(bullet_proof_tires)

        local is_low_grip_available = GetGameBuildNumber() >= 2372
        local low_grip_tires = Items.MenuCheckboxItem.new(
            'Low Grip Tires',
            'Enable or disable ~y~low grip tires~s~ for this vehicle.',
            is_low_grip_available and GetDriftTyresEnabled(vehicle) or false
        )
        if is_low_grip_available then
            mod_menu:AddMenuItem(low_grip_tires)
        end

        -- tire smoke submenu
        local tire_smoke_button = Items.MenuItem.new('Tire Smoke')
        local tire_smoke_menu = Menu.new('Tire Smoke', 'Tire Smoke')
        local tire_smokes = {
            'Red',
            'Orange',
            'Yellow',
            'Gold',
            'Light Green',
            'Dark Green',
            'Light Blue',
            'Dark Blue',
            'Purple',
            'Pink',
            'Black',
        }
        local tire_smoke_colors = {
            ['Red'] = { 244, 65, 65 },
            ['Orange'] = { 244, 167, 66 },
            ['Yellow'] = { 244, 217, 65 },
            ['Gold'] = { 181, 120, 0 },
            ['Light Green'] = { 158, 255, 84 },
            ['Dark Green'] = { 44, 94, 5 },
            ['Light Blue'] = { 65, 211, 244 },
            ['Dark Blue'] = { 24, 54, 163 },
            ['Purple'] = { 108, 24, 192 },
            ['Pink'] = { 192, 24, 172 },
            ['Black'] = { 1, 1, 1 },
        }
        local smoke_r, smoke_g, smoke_b = GetVehicleTyreSmokeColor(vehicle)
        local smoke_index = 0
        for i, name in ipairs(tire_smokes) do
            local color = tire_smoke_colors[name]
            if color[1] == smoke_r and color[2] == smoke_g and color[3] == smoke_b then
                smoke_index = i - 1
                break
            end
        end

        local tire_smoke = Items.MenuListItem.new(
            'Tire Smoke Color',
            tire_smokes,
            smoke_index,
            'Choose a ~y~tire smoke color~s~ for your vehicle.'
        )
        tire_smoke_menu:AddMenuItem(tire_smoke)

        local tire_smoke_enabled = Items.MenuCheckboxItem.new(
            'Tire Smoke',
            'Enable or disable ~y~tire smoke~s~ for your vehicle. ~h~~r~Important:~s~ When disabling tire smoke, '
                .. "you'll need to drive around before it takes affect.",
            IsToggleModOn(vehicle, 20)
        )
        tire_smoke_menu:AddMenuItem(tire_smoke_enabled)

        tire_smoke_menu.OnCheckboxChange = function(_, item2, _index2, checked)
            local veh = get_vehicle()
            if item2 == tire_smoke_enabled then
                if checked then
                    ToggleVehicleMod(veh, 20, true)
                    local color = tire_smoke_colors[tire_smokes[tire_smoke.ListIndex + 1]]
                    SetVehicleTyreSmokeColor(veh, color[1], color[2], color[3])
                else
                    SetVehicleTyreSmokeColor(veh, 255, 255, 255)
                    ToggleVehicleMod(veh, 20, false)
                    RemoveVehicleMod(veh, 20)
                end
            end
        end
        on(tire_smoke_menu, 'OnListIndexChange', function(_, item2, _old_index, new_index, _item_index)
            local veh = get_vehicle()
            SetVehicleModKit(veh, 0)
            if item2 == tire_smoke then
                local color = tire_smoke_colors[tire_smokes[new_index + 1]]
                SetVehicleTyreSmokeColor(veh, color[1], color[2], color[3])
            end
        end)

        Controller.AddSubmenu(mod_menu, tire_smoke_menu)
        Controller.BindMenuItem(mod_menu, tire_smoke_menu, tire_smoke_button)
        mod_menu:AddMenuItem(tire_smoke_button)
        create_custom_colour_menu(tire_smoke_menu, 'tiresmoke')

        -- window tint
        local current_tint = GetVehicleWindowTint(vehicle)
        if current_tint == -1 then
            current_tint = 4 -- stock
        end
        -- convert the tint value to its position in the list below
        local tint_value_to_list_index = { [0] = 1, [1] = 5, [2] = 4, [3] = 3, [4] = 0, [5] = 2, [6] = 6 }
        current_tint = tint_value_to_list_index[current_tint] or current_tint

        local window_tint = Items.MenuListItem.new('Window Tint', {
            'Stock [1/7]',
            'None [2/7]',
            'Limo [3/7]',
            'Light Smoke [4/7]',
            'Dark Smoke [5/7]',
            'Pure Black [6/7]',
            'Green [7/7]',
        }, current_tint, 'Apply tint to your windows.')
        mod_menu:AddMenuItem(window_tint)

        -- checkbox changes (replaces the previous build's handler)
        mod_menu.OnCheckboxChange = function(_, item2, _index2, checked)
            local veh = get_vehicle()
            if item2 == turbo then
                ToggleVehicleMod(veh, 18, checked)
            elseif item2 == bullet_proof_tires then
                SetVehicleTyresCanBurst(veh, not checked)
            elseif item2 == low_grip_tires then
                SetDriftTyresEnabled(veh, checked)
            elseif item2 == toggle_custom_wheels then
                SetVehicleMod(veh, 23, GetVehicleMod(veh, 23), not GetVehicleModVariation(veh, 23))
                -- on a motorcycle, also change the back wheels
                if IsThisModelABike(GetEntityModel(veh)) then
                    SetVehicleMod(veh, 24, GetVehicleMod(veh, 24), GetVehicleModVariation(veh, 23))
                end
            end
        end

        -- list selections (replaces the previous build's handler)
        mod_menu.OnListIndexChange = function(_, item2, old_index, new_index, item_index)
            local veh = get_vehicle()
            SetVehicleModKit(veh, 0)

            if type(item2.ItemData) == 'number' then
                -- dynamically generated mod list
                local selected_upgrade = item2.ListIndex - 1
                local custom_wheels = GetVehicleModVariation(veh, 23)
                SetVehicleMod(veh, item2.ItemData, selected_upgrade, custom_wheels)
            elseif item2 == vehicle_wheel_type then
                local vehicle_class = GetVehicleClass(veh)
                local veh_model = GetEntityModel(veh)
                local is_bike = IsThisModelABike(veh_model)
                local is_bike_or_open_wheel = (new_index == 6 and is_bike) or (new_index == 10 and vehicle_class == 22)
                local is_not_bike_nor_open_wheel = new_index ~= 6
                    and not is_bike
                    and new_index ~= 10
                    and vehicle_class ~= 22
                if not (is_bike_or_open_wheel or is_not_bike_nor_open_wheel) then
                    if not is_bike and vehicle_class ~= 22 then
                        -- go past the index if it's not a bike
                        if new_index > old_index then
                            item2.ListIndex = item2.ListIndex + 1
                        else
                            item2.ListIndex = item2.ListIndex - 1
                        end
                    else
                        item2.ListIndex = is_bike and 6 or 10
                    end
                end

                SetVehicleWheelType(veh, item2.ListIndex)
                local custom_wheels = GetVehicleModVariation(veh, 23)
                SetVehicleMod(veh, 23, -1, custom_wheels)
                if is_bike then
                    SetVehicleMod(veh, 24, -1, custom_wheels)
                end

                -- refresh so the available wheels list updates, keeping the view
                update_mods(item_index)
            elseif item2 == window_tint then
                -- list position → tint value
                local list_index_to_tint_value = { [0] = 4, [1] = 0, [2] = 5, [3] = 3, [4] = 2, [5] = 1, [6] = 6 }
                SetVehicleWindowTint(veh, list_index_to_tint_value[new_index] or 4)
            end
        end

        if selected_index == 0 then
            mod_menu:RefreshIndex()
        end
    end
    self.update_mods = update_mods

    self.menu = menu
    return self
end

return VehicleOptions
