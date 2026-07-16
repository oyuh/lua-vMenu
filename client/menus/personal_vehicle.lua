-- Port of vMenu/menus/PersonalVehicle.cs: mark a vehicle as personal and
-- control it remotely (engine, lights, stance, doors, horn, alarm, blip,
-- exclusive driver).

local Permissions = require('shared.permissions')
local Common = require('client.common')
local VehicleCommon = require('client.vehicle_common')
local Notification = require('client.notify')
local UserDefaults = require('client.user_defaults')
local Controller = require('menu.controller')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Notify = Notification.Notify

local PersonalVehicle = {}

local PERSONAL_VEHICLE_BLIP_SPRITE = 225 -- BlipSprite.PersonalVehicleCar

function PersonalVehicle.create()
    local self = {}
    self.EnableVehicleBlip = UserDefaults.get_bool('pvEnableVehicleBlip')
    self.CurrentPersonalVehicle = nil

    local menu = Menu.new(Common.get_safe_player_name(GetPlayerName(PlayerId())), 'Personal Vehicle Options')

    local set_vehicle = Items.MenuItem.new(
        'Set Vehicle',
        'Sets your current vehicle as your personal vehicle. If you already have a personal vehicle set then '
            .. 'this will override your selection.'
    )
    set_vehicle.Label = 'Current Vehicle: None'
    local toggle_engine = Items.MenuItem.new(
        'Toggle Engine',
        "Toggles the engine on or off, even when you're not inside of the vehicle. This does not work if "
            .. 'someone else is currently using your vehicle.'
    )
    local toggle_lights = Items.MenuListItem.new(
        'Set Vehicle Lights',
        { 'Force On', 'Force Off', 'Reset' },
        0,
        'This will enable or disable your vehicle headlights, the engine of your vehicle needs to be running '
            .. 'for this to work.'
    )
    local toggle_stance = Items.MenuListItem.new(
        'Vehicle Stance',
        { 'Default', 'Lowered' },
        0,
        'Select stance for your Personal Vehicle.'
    )
    local kick_all_passengers =
        Items.MenuItem.new('Kick Passengers', 'This will remove all passengers from your personal vehicle.')
    local lock_doors = Items.MenuItem.new(
        'Lock Vehicle Doors',
        'This will lock all your vehicle doors for all players. Anyone already inside will always be able to '
            .. 'leave the vehicle, even if the doors are locked.'
    )
    local unlock_doors =
        Items.MenuItem.new('Unlock Vehicle Doors', 'This will unlock all your vehicle doors for all players.')
    local doors_menu_btn = Items.MenuItem.new('Vehicle Doors', 'Open, close, remove and restore vehicle doors here.')
    doors_menu_btn.Label = '→→→'
    local sound_horn = Items.MenuItem.new('Sound Horn', 'Sounds the horn of the vehicle.')
    local toggle_alarm = Items.MenuItem.new(
        'Toggle Alarm Sound',
        'Toggles the vehicle alarm sound on or off. This does not set an alarm. It only toggles the current '
            .. 'sounding status of the alarm.'
    )
    local enable_blip = Items.MenuCheckboxItem.new(
        'Add Blip For Personal Vehicle',
        'Enables or disables the blip that gets added when you mark a vehicle as your personal vehicle.',
        self.EnableVehicleBlip
    )
    enable_blip.CheckboxStyle = Items.MenuCheckboxItem.Style.Cross
    local exclusive_driver = Items.MenuCheckboxItem.new(
        'Exclusive Driver',
        'If enabled, then you will be the only one that can enter the drivers seat. Other players will not be '
            .. 'able to drive the car. They can still be passengers.',
        false
    )
    exclusive_driver.CheckboxStyle = Items.MenuCheckboxItem.Style.Cross

    local doors_menu = Menu.new('Vehicle Doors', 'Vehicle Doors Management')
    Controller.AddSubmenu(menu, doors_menu)
    Controller.BindMenuItem(menu, doors_menu, doors_menu_btn)
    self.VehicleDoorsMenu = doors_menu

    menu:AddMenuItem(set_vehicle)
    if Permissions.is_allowed('PVToggleEngine') then
        menu:AddMenuItem(toggle_engine)
    end
    if Permissions.is_allowed('PVToggleLights') then
        menu:AddMenuItem(toggle_lights)
    end
    if Permissions.is_allowed('PVToggleStance') then
        menu:AddMenuItem(toggle_stance)
    end
    if Permissions.is_allowed('PVKickPassengers') then
        menu:AddMenuItem(kick_all_passengers)
    end
    if Permissions.is_allowed('PVLockDoors') then
        menu:AddMenuItem(lock_doors)
        menu:AddMenuItem(unlock_doors)
    end
    if Permissions.is_allowed('PVDoors') then
        menu:AddMenuItem(doors_menu_btn)
    end
    if Permissions.is_allowed('PVSoundHorn') then
        menu:AddMenuItem(sound_horn)
    end
    if Permissions.is_allowed('PVToggleAlarm') then
        menu:AddMenuItem(toggle_alarm)
    end
    if Permissions.is_allowed('PVAddBlip') then
        menu:AddMenuItem(enable_blip)
    end
    if Permissions.is_allowed('PVExclusiveDriver') then
        menu:AddMenuItem(exclusive_driver)
    end

    local function vehicle_valid()
        return self.CurrentPersonalVehicle ~= nil and DoesEntityExist(self.CurrentPersonalVehicle)
    end

    local function ensure_control()
        if not NetworkHasControlOfEntity(self.CurrentPersonalVehicle) then
            if not NetworkRequestControlOfEntity(self.CurrentPersonalVehicle) then
                Notify.error(
                    "You currently can't control this vehicle. Is someone else currently driving your car? "
                        .. 'Please try again after making sure other players are not controlling your vehicle.'
                )
                return false
            end
        end
        return true
    end

    local NO_VEHICLE_MESSAGE = 'You have not yet selected a personal vehicle, or your vehicle has been deleted. '
        .. 'Set a personal vehicle before you can use these options.'

    local function attach_personal_blip(vehicle)
        local blip = GetBlipFromEntity(vehicle)
        if not DoesBlipExist(blip) then
            blip = AddBlipForEntity(vehicle)
        end
        SetBlipSprite(blip, PERSONAL_VEHICLE_BLIP_SPRITE)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Personal Vehicle')
        EndTextCommandSetBlipName(blip)
    end

    menu.OnListItemSelect = function(_, item, item_index, _index)
        if vehicle_valid() then
            if not ensure_control() then
                return
            end
            local vehicle = self.CurrentPersonalVehicle
            if item == toggle_lights then
                VehicleCommon.press_key_fob(vehicle)
                if item_index == 0 then
                    SetVehicleLights(vehicle, 3)
                elseif item_index == 1 then
                    SetVehicleLights(vehicle, 1)
                else
                    SetVehicleLights(vehicle, 0)
                end
            elseif item == toggle_stance then
                VehicleCommon.press_key_fob(vehicle)
                SetReduceDriftVehicleSuspension(vehicle, item_index == 1)
            end
        else
            Notify.error(NO_VEHICLE_MESSAGE)
        end
    end

    menu.OnCheckboxChange = function(_, item, _index, checked)
        if item == enable_blip then
            self.EnableVehicleBlip = checked
            if checked then
                if vehicle_valid() then
                    attach_personal_blip(self.CurrentPersonalVehicle)
                else
                    Notify.error(NO_VEHICLE_MESSAGE)
                end
            elseif vehicle_valid() then
                local blip = GetBlipFromEntity(self.CurrentPersonalVehicle)
                if DoesBlipExist(blip) then
                    RemoveBlip(blip)
                end
            end
        elseif item == exclusive_driver then
            if vehicle_valid() then
                if NetworkRequestControlOfEntity(self.CurrentPersonalVehicle) then
                    -- SetVehicleExclusiveDriver + _2 variant.
                    SetVehicleExclusiveDriver(self.CurrentPersonalVehicle, checked)
                    SetVehicleExclusiveDriver_2(self.CurrentPersonalVehicle, checked and PlayerPedId() or 0, 1)
                else
                    item.Checked = not checked
                    Notify.error(
                        "You currently can't control this vehicle. Is someone else currently driving your car? "
                            .. 'Please try again after making sure other players are not controlling your vehicle.'
                    )
                end
            end
        end
    end

    menu.OnItemSelect = function(_, item, _index)
        if item == set_vehicle then
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                local vehicle = Common.get_vehicle()
                if vehicle ~= 0 and DoesEntityExist(vehicle) then
                    if GetPedInVehicleSeat(vehicle, -1) == ped then
                        self.CurrentPersonalVehicle = vehicle
                        SetVehicleHasBeenOwnedByPlayer(vehicle, true)
                        SetEntityAsMissionEntity(vehicle, true, false)
                        if self.EnableVehicleBlip and Permissions.is_allowed('PVAddBlip') then
                            attach_personal_blip(vehicle)
                        end
                        local display = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
                        local name = GetLabelText(display)
                        if name == nil or name == '' or name:lower() == 'null' then
                            name = display
                        end
                        item.Label = ('Current Vehicle: %s'):format(name)
                    else
                        Notify.error(Notification.error_message('NeedToBeTheDriver'))
                    end
                else
                    Notify.error(Notification.error_message('NoVehicle'))
                end
            else
                Notify.error(Notification.error_message('NoVehicle'))
            end
        elseif vehicle_valid() then
            local vehicle = self.CurrentPersonalVehicle
            if item == kick_all_passengers then
                local has_other_players = false
                for seat = -1, 14 do
                    local occupant = GetPedInVehicleSeat(vehicle, seat)
                    if occupant ~= 0 and occupant ~= PlayerPedId() and IsPedAPlayer(occupant) then
                        has_other_players = true
                        break
                    end
                end
                if has_other_players then
                    TriggerServerEvent('vMenu:GetOutOfCar', NetworkGetNetworkIdFromEntity(vehicle))
                else
                    Notify.info('There are no other players in your vehicle that need to be kicked out.')
                end
            else
                if not ensure_control() then
                    return
                end
                if item == toggle_engine then
                    VehicleCommon.press_key_fob(vehicle)
                    SetVehicleEngineOn(vehicle, not GetIsVehicleEngineRunning(vehicle), true, true)
                elseif item == lock_doors or item == unlock_doors then
                    VehicleCommon.press_key_fob(vehicle)
                    VehicleCommon.lock_or_unlock_doors(vehicle, item == lock_doors)
                elseif item == sound_horn then
                    VehicleCommon.press_key_fob(vehicle)
                    VehicleCommon.sound_horn(vehicle)
                elseif item == toggle_alarm then
                    VehicleCommon.press_key_fob(vehicle)
                    VehicleCommon.toggle_vehicle_alarm(vehicle)
                end
            end
        else
            Notify.error(NO_VEHICLE_MESSAGE)
        end
    end

    -- Doors submenu.
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
        { 'Front Left', 'Front Right', 'Rear Left', 'Rear Right', 'Hood', 'Trunk', 'Extra 1', 'Extra 2', 'Bomb Bay' },
        0,
        'Remove a specific vehicle door completely.'
    )
    local delete_doors = Items.MenuCheckboxItem.new(
        'Delete Removed Doors',
        'When enabled, doors that you remove using the list above will be deleted from the world. If disabled, '
            .. 'then the doors will just fall on the ground.',
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

    doors_menu.OnListItemSelect = function(_, item, index, _item_index)
        if vehicle_valid() then
            if not ensure_control() then
                return
            end
            if item == remove_door_list then
                VehicleCommon.press_key_fob(self.CurrentPersonalVehicle)
                SetVehicleDoorBroken(self.CurrentPersonalVehicle, index, delete_doors.Checked)
            end
        end
    end

    doors_menu.OnItemSelect = function(_, item, index)
        local vehicle = self.CurrentPersonalVehicle
        if vehicle_valid() and not IsEntityDead(vehicle) then
            if not ensure_control() then
                return
            end
            if index < 8 then
                local open = GetVehicleDoorAngleRatio(vehicle, index) > 0.1
                VehicleCommon.press_key_fob(vehicle)
                if open then
                    SetVehicleDoorShut(vehicle, index, false)
                else
                    SetVehicleDoorOpen(vehicle, index, false, false)
                end
            elseif item == open_all then
                VehicleCommon.press_key_fob(vehicle)
                for door = 0, 7 do
                    SetVehicleDoorOpen(vehicle, door, false, false)
                end
            elseif item == close_all then
                VehicleCommon.press_key_fob(vehicle)
                for door = 0, 7 do
                    SetVehicleDoorShut(vehicle, door, false)
                end
            -- Vehicle.HasBombBay (unnamed native, hash from CitizenFX.Core).
            elseif item == bomb_bay and Citizen.InvokeNative(0x6D6AF961B72728AE, vehicle) then
                VehicleCommon.press_key_fob(vehicle)
                if AreBombBayDoorsOpen(vehicle) then
                    CloseBombBayDoors(vehicle)
                else
                    OpenBombBayDoors(vehicle)
                end
            else
                Notify.error(NO_VEHICLE_MESSAGE)
            end
        end
    end

    self.menu = menu
    return self
end

return PersonalVehicle
