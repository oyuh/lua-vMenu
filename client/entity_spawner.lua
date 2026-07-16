-- Port of vMenu/EntitySpawner.cs: spawn an entity by model name and place it
-- with the camera (raycast follows where the player looks; roll keys rotate
-- it). fill_menu() builds the Entity Spawner submenu items that upstream
-- keeps in MiscSettings.cs.

local Common = require('client.common')
local Notification = require('client.notify')
local Items = require('menu.items')

local Notify = Notification.Notify

local EntitySpawner = {}

EntitySpawner.Active = false
EntitySpawner.CurrentEntity = nil -- entity handle (nil when not placing)

local ROTATE_SPEED = 20.0
local RAY_DISTANCE = 25.0

-- Control ids (CitizenFX.Core Control enum).
local VEHICLE_FLY_ROLL_LEFT_ONLY = 108
local VEHICLE_FLY_ROLL_RIGHT_ONLY = 109

local scaleform = 0

local function draw_buttons()
    BeginScaleformMovieMethod(scaleform, 'CLEAR_ALL')
    EndScaleformMovieMethod()

    BeginScaleformMovieMethod(scaleform, 'SET_DATA_SLOT')
    ScaleformMovieMethodAddParamInt(0)
    PushScaleformMovieMethodParameterString('~INPUT_VEH_FLY_ROLL_LR~')
    PushScaleformMovieMethodParameterString('Rotate Object')
    EndScaleformMovieMethod()

    BeginScaleformMovieMethod(scaleform, 'DRAW_INSTRUCTIONAL_BUTTONS')
    ScaleformMovieMethodAddParamInt(0)
    EndScaleformMovieMethod()

    DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255, 0)
end

-- Rotation vector (degrees) → direction vector.
local function rotation_to_direction(rotation)
    local adj_x = math.pi / 180 * rotation.x
    local adj_z = math.pi / 180 * rotation.z
    return -math.sin(adj_z) * math.abs(math.cos(adj_x)), math.cos(adj_z) * math.abs(math.cos(adj_x)), math.sin(adj_x)
end

-- Raycast from the gameplay camera; the destination when nothing is hit.
local function get_coords_player_is_looking_at()
    local cam_rotation = GetGameplayCamRot(0)
    local cam_coords = GetGameplayCamCoord()
    local dir_x, dir_y, dir_z = rotation_to_direction(cam_rotation)

    local dest = vector3(
        cam_coords.x + (dir_x * RAY_DISTANCE),
        cam_coords.y + (dir_y * RAY_DISTANCE),
        cam_coords.z + (dir_z * RAY_DISTANCE)
    )

    -- World.Raycast(camCoords, dest, IntersectOptions.Everything, PlayerPed)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        cam_coords.x,
        cam_coords.y,
        cam_coords.z,
        dest.x,
        dest.y,
        dest.z,
        -1,
        PlayerPedId(),
        7
    )
    local _, hit, hit_position = GetShapeTestResult(ray)
    if hit then
        return hit_position
    end
    return dest
end

-- The placement tick: runs while Active, previews the entity at the raycast
-- position and resets its state after every frame.
local function move_handler()
    scaleform = RequestScaleformMovie('INSTRUCTIONAL_BUTTONS')
    while not HasScaleformMovieLoaded(scaleform) do
        Wait(0)
    end
    DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 0, 0)

    local heading_offset = 0.0
    while EntitySpawner.Active do
        local entity = EntitySpawner.CurrentEntity
        if entity == nil or not DoesEntityExist(entity) then
            EntitySpawner.Active = false
            EntitySpawner.CurrentEntity = nil
            break
        end

        draw_buttons()

        FreezeEntityPosition(entity, true)
        SetEntityInvincible(entity, true)
        SetEntityCollision(entity, false, false)
        SetEntityAlpha(entity, 102, 0) -- 255 * 0.4
        SetEntityHeading(entity, (GetGameplayCamRot(0).z + heading_offset) % 360.0)

        local new_position = get_coords_player_is_looking_at()
        SetEntityCoords(entity, new_position.x, new_position.y, new_position.z, false, false, false, true)
        if GetEntityHeightAboveGround(entity) < 3.0 then
            if IsModelAVehicle(GetEntityModel(entity)) then
                SetVehicleOnGroundProperly(entity)
            else
                PlaceObjectOnGroundProperly(entity)
            end
        end

        -- Controls
        if IsControlPressed(0, VEHICLE_FLY_ROLL_LEFT_ONLY) then
            heading_offset = heading_offset + ROTATE_SPEED * GetFrameTime()
        elseif IsControlPressed(0, VEHICLE_FLY_ROLL_RIGHT_ONLY) then
            heading_offset = heading_offset - ROTATE_SPEED * GetFrameTime()
        end

        Wait(0)

        FreezeEntityPosition(entity, false)
        SetEntityInvincible(entity, false)
        SetEntityCollision(entity, true, true)
        ResetEntityAlpha(entity)
    end

    if scaleform ~= 0 then
        SetScaleformMovieAsNoLongerNeeded(scaleform)
        scaleform = 0
    end
end

-- SpawnEntity: model is a name or hash; coords is where it first appears.
function EntitySpawner.spawn_entity(model, coords)
    if type(model) == 'string' then
        model = GetHashKey(model)
    end

    if not IsModelValid(model) then
        Notify.error(Notification.error_message('InvalidInput'))
        return
    end

    if EntitySpawner.CurrentEntity ~= nil then
        Notify.error('One entity is currently being processed.')
        return
    end

    local ped = PlayerPedId()
    local handle
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(1)
    end
    if IsModelAPed(model) then
        handle = CreatePed(4, model, coords.x, coords.y, coords.z, GetEntityHeading(ped), true, true)
    elseif IsModelAVehicle(model) then
        handle = Common.spawn_vehicle(model, {
            spawn_inside = false,
            replace_previous = false,
            x = coords.x,
            y = coords.y,
            z = coords.z,
            heading = GetEntityHeading(ped),
        })
    else
        handle = CreateObject(model, coords.x, coords.y, coords.z, true, true, true)
    end

    if handle == nil or handle == 0 or not DoesEntityExist(handle) then
        EntitySpawner.CurrentEntity = nil
        Notify.error('Failed to create entity')
        return
    end
    EntitySpawner.CurrentEntity = handle

    SetEntityAsMissionEntity(handle, true, true) -- prevent despawning

    EntitySpawner.Active = true
    CreateThread(move_handler)
end

-- FinishPlacement: confirms the current location; with duplicate=true it
-- immediately starts placing a copy of the same model.
function EntitySpawner.finish_placement(duplicate)
    if duplicate then
        local entity = EntitySpawner.CurrentEntity
        local hash = GetEntityModel(entity)
        local position = GetEntityCoords(entity)
        EntitySpawner.CurrentEntity = nil
        Wait(1) -- mandatory: let the placement tick release the old entity
        EntitySpawner.spawn_entity(hash, position)
    else
        EntitySpawner.Active = false
        EntitySpawner.CurrentEntity = nil
    end
end

-- The Entity Spawner submenu items (upstream builds these in MiscSettings.cs).
function EntitySpawner.fill_menu(menu)
    local spawn_new_entity = Items.MenuItem.new(
        'Spawn New Entity',
        'Spawns entity into the world and lets you set its position and rotation'
    )
    local confirm_entity_position =
        Items.MenuItem.new('Confirm Entity Position', 'Stops placing entity and sets it at it current location.')
    local confirm_and_duplicate = Items.MenuItem.new(
        'Confirm Entity Position And Duplicate',
        'Stops placing entity and sets it at it current location and creates new one to place.'
    )
    local cancel_entity = Items.MenuItem.new('Cancel', 'Deletes current entity and cancels its placement')

    menu:AddMenuItem(spawn_new_entity)
    menu:AddMenuItem(confirm_entity_position)
    menu:AddMenuItem(confirm_and_duplicate)
    menu:AddMenuItem(cancel_entity)

    menu.OnItemSelect = function(_, item, _index)
        if item == spawn_new_entity then
            if EntitySpawner.CurrentEntity ~= nil or EntitySpawner.Active then
                Notify.error('You are already placing one entity, set its location or cancel and try again!')
                return
            end

            local result = Common.get_user_input('Enter model name')
            if result == nil or result == '' then
                Notify.error(Notification.error_message('InvalidInput'))
            end
            -- upstream quirk: the spawn still runs after the empty-input error
            EntitySpawner.spawn_entity(result or '', GetEntityCoords(PlayerPedId()))
        elseif item == confirm_entity_position or item == confirm_and_duplicate then
            if EntitySpawner.CurrentEntity ~= nil then
                EntitySpawner.finish_placement(item == confirm_and_duplicate)
            else
                Notify.error('No entity to confirm position for!')
            end
        elseif item == cancel_entity then
            if EntitySpawner.CurrentEntity ~= nil then
                -- Entity.Delete()
                local entity = EntitySpawner.CurrentEntity
                SetEntityAsMissionEntity(entity, false, true)
                DeleteEntity(entity)
            else
                Notify.error('No entity to cancel!')
            end
        end
    end
end

return EntitySpawner
