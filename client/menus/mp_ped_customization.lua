-- Port of vMenu/menus/MpPedCustomization.cs: the MP character creator/editor
-- (inheritance head blends, appearance overlays, face shape, tattoos,
-- clothing, props), saved characters with categories, and the mp_ped_<name>
-- KVP save flow. C#-saved characters must load pixel-identical
-- (docs/contracts/kvp-saves.md, fixture: tests/fixtures/mp_ped_data.json).

local Config = require('shared.config')
local Json = require('shared.json_compat')
local Common = require('client.common')
local Notification = require('client.notify')
local Storage = require('client.storage')
local Weapons = require('client.weapons')
local MpPedData = require('client.mp_ped_data')
local Tattoos = require('client.tattoos')
local State = require('client.state')
local Controller = require('menu.controller')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Notify = Notification.Notify
local Subtitle = Notification.Subtitle

local MpPedCustomization = {}

local TEMP_LOADOUT_NAME = 'vmenu_temp_weapons_loadout_before_respawn'

-- C# menu events are multicast (+=); ours hold a single callback.
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

-- Random.Next(n): 0 .. n-1 (0 when n <= 0, like C#'s Next(0)).
local function rand_next(n)
    if n == nil or n <= 0 then
        return 0
    end
    return math.random(0, n - 1)
end

-- MenuItem.Icon names ordered by enum value (Enum.GetNames order).
local ICON_NAMES = {}
for name, value in pairs(Items.Icon) do
    ICON_NAMES[value + 1] = name
end

local FACIAL_EXPRESSIONS = {
    'mood_Normal_1',
    'mood_Happy_1',
    'mood_Angry_1',
    'mood_Aiming_1',
    'mood_Injured_1',
    'mood_stressed_1',
    'mood_smug_1',
    'mood_sulk_1',
}

-- Head blend parent lists ({ id, label prefix }; insertion order matters).
local BLEND_HEADS_NAMES = {
    { 0, 'Male_' },
    { 2, 'Special_Male_' },
    { 1, 'Female_' },
    { 3, 'Special_Female_' },
}

-- faceFeaturesValuesList: slider position (0-20) → feature value.
local FACE_FEATURE_VALUES = {}
for i = 0, 20 do
    FACE_FEATURE_VALUES[i + 1] = -1.0 + (i * 0.1)
end

-- hairOverlays: hair style index → { collection, overlay } facial decoration.
local HAIR_OVERLAYS = {
    [0] = { 'multiplayer_overlays', 'FM_M_Hair_001_a' },
    [1] = { 'multiplayer_overlays', 'FM_M_Hair_001_z' },
    [2] = { 'multiplayer_overlays', 'FM_M_Hair_001_z' },
    [3] = { 'multiplayer_overlays', 'FM_M_Hair_003_a' },
    [4] = { 'multiplayer_overlays', 'FM_M_Hair_001_z' },
    [5] = { 'multiplayer_overlays', 'FM_M_Hair_001_z' },
    [6] = { 'multiplayer_overlays', 'FM_M_Hair_001_z' },
    [7] = { 'multiplayer_overlays', 'FM_M_Hair_001_z' },
    [8] = { 'multiplayer_overlays', 'FM_M_Hair_008_a' },
    [9] = { 'multiplayer_overlays', 'FM_M_Hair_001_z' },
    [10] = { 'multiplayer_overlays', 'FM_M_Hair_001_z' },
    [11] = { 'multiplayer_overlays', 'FM_M_Hair_001_z' },
    [12] = { 'multiplayer_overlays', 'FM_M_Hair_001_z' },
    [13] = { 'multiplayer_overlays', 'FM_M_Hair_001_z' },
    [14] = { 'multiplayer_overlays', 'FM_M_Hair_long_a' },
    [15] = { 'multiplayer_overlays', 'FM_M_Hair_long_a' },
    [16] = { 'multiplayer_overlays', 'FM_M_Hair_001_z' },
    [17] = { 'multiplayer_overlays', 'FM_M_Hair_001_a' },
    [18] = { 'mpbusiness_overlays', 'FM_Bus_M_Hair_000_a' },
    [19] = { 'mpbusiness_overlays', 'FM_Bus_M_Hair_001_a' },
    [20] = { 'mphipster_overlays', 'FM_Hip_M_Hair_000_a' },
    [21] = { 'mphipster_overlays', 'FM_Hip_M_Hair_001_a' },
    [22] = { 'multiplayer_overlays', 'FM_M_Hair_001_a' },
}

-- Tattoo zone → { character list field, tattoos collection key }.
local TATTOO_ZONES = {
    [0] = { 'HairTattoos', 'HAIR' },
    [1] = { 'HeadTattoos', 'HEAD' },
    [2] = { 'TorsoTattoos', 'TORSO' },
    [3] = { 'LeftArmTattoos', 'LEFT_ARM' },
    [4] = { 'RightArmTattoos', 'RIGHT_ARM' },
    [5] = { 'LeftLegTattoos', 'LEFT_LEG' },
    [6] = { 'RightLegTattoos', 'RIGHT_LEG' },
    [7] = { 'BadgeTattoos', 'BADGES' },
    [8] = { 'AddonTattoos', 'ADDONS' },
}

local function kvp_equal(a, b)
    return a.Key == b.Key and a.Value == b.Value
end

local function list_contains(list, kvp)
    for _, entry in ipairs(list) do
        if kvp_equal(entry, kvp) then
            return true
        end
    end
    return false
end

local function list_remove(list, kvp)
    for i, entry in ipairs(list) do
        if kvp_equal(entry, kvp) then
            table.remove(list, i)
            return
        end
    end
end

function MpPedCustomization.create()
    local self = {}

    local player_name = Common.get_safe_player_name(GetPlayerName(PlayerId()))
    local menu = Menu.new(player_name, 'MP Ped Customization')
    local create_character_menu = Menu.new('Create Character', 'Create A New Character')
    local saved_characters_menu = Menu.new('vMenu', 'Manage Saved Characters')
    local saved_characters_category_menu = Menu.new('Category', 'I get updated at runtime!')
    local inheritance_menu = Menu.new('vMenu', 'Character Inheritance Options')
    local appearance_menu = Menu.new('vMenu', 'Character Appearance Options')
    local face_shape_menu = Menu.new('vMenu', 'Character Face Shape Options')
    local tattoos_menu = Menu.new('vMenu', 'Character Tattoo Options')
    local clothes_menu = Menu.new('vMenu', 'Character Clothing Options')
    local props_menu = Menu.new('vMenu', 'Character Props Options')
    local manage_saved_character_menu = Menu.new('vMenu', 'Manage MP Character')

    local create_male_btn = Items.MenuItem.new('Create Male Character', 'Create a new male character.')
    create_male_btn.Label = '→→→'
    local create_female_btn = Items.MenuItem.new('Create Female Character', 'Create a new female character.')
    create_female_btn.Label = '→→→'
    local edit_ped_btn = Items.MenuItem.new(
        'Edit Saved Character',
        'This allows you to edit everything about your saved character. The changes will be saved to this '
            .. "character's save file entry once you hit the save button."
    )

    local set_category_btn =
        Items.MenuListItem.new('Set Character Category', {}, 0, "Sets this character's category. Select to save.")
    local category_btn = Items.MenuListItem.new('Character Category', {}, 0, "Sets this character's category.")

    -- editor state
    local selected_saved_character_manage_name = ''
    local is_editing_ped = false
    local current_character = MpPedData.new()
    local current_category = { Name = '', Description = '', Icon = 0 }
    local clone = 0

    local parent_one, parent_one_skin = 0, 0
    local parent_two, parent_two_skin = 0, 0
    local shape_mix_value, skin_mix_value = 0.0, 0.0
    local shape_face_values = {}
    local appearance_values = {} -- [0..11] = { style, color, opacity }
    local hair_selection = 0
    local hair_color_selection = 0
    local hair_highlight_color_selection = 0
    local eye_color_selection = 0
    local facial_expression_selection = 0

    -- C# reads the live head blend struct back with GetHeadBlendData(); that
    -- struct native has no plain Lua counterpart, so the last values set via
    -- SetPedHeadBlendData are tracked here instead (identical for everything
    -- the creator itself does).
    local current_head_blend = {
        FirstFaceShape = 0,
        SecondFaceShape = 0,
        ThirdFaceShape = 0,
        FirstSkinTone = 0,
        SecondSkinTone = 0,
        ThirdSkinTone = 0,
        ParentFaceShapePercent = 0.0,
        ParentSkinTonePercent = 0.0,
        ParentThirdUnkPercent = 0.0,
        IsParentInheritance = false,
    }

    local function set_head_blend()
        SetPedHeadBlendData(
            PlayerPedId(),
            parent_one,
            parent_two,
            0,
            parent_one_skin,
            parent_two_skin,
            0,
            shape_mix_value,
            skin_mix_value,
            0.0,
            false
        )
        current_head_blend = {
            FirstFaceShape = parent_one,
            SecondFaceShape = parent_two,
            ThirdFaceShape = 0,
            FirstSkinTone = parent_one_skin,
            SecondSkinTone = parent_two_skin,
            ThirdSkinTone = 0,
            ParentFaceShapePercent = shape_mix_value,
            ParentSkinTonePercent = skin_mix_value,
            ParentThirdUnkPercent = 0.0,
            IsParentInheritance = false,
        }
    end

    local function change_player_hair(new_hair_index)
        local ped = PlayerPedId()
        ClearPedFacialDecorations(ped)
        current_character.PedAppearance.HairOverlay = MpPedData.kvp('', '')

        if new_hair_index >= GetNumberOfPedDrawableVariations(ped, 2) then
            SetPedComponentVariation(ped, 2, 0, 0, 0)
            current_character.PedAppearance.hairStyle = 0
        else
            SetPedComponentVariation(ped, 2, new_hair_index, 0, 0)
            current_character.PedAppearance.hairStyle = new_hair_index
            local overlay = HAIR_OVERLAYS[new_hair_index]
            if overlay ~= nil then
                SetPedFacialDecoration(ped, GetHashKey(overlay[1]), GetHashKey(overlay[2]))
                current_character.PedAppearance.HairOverlay = MpPedData.kvp(overlay[1], overlay[2])
            end
        end

        hair_selection = new_hair_index
    end

    local function change_player_hair_color(color, highlight)
        SetPedHairColor(PlayerPedId(), color, highlight)
        current_character.PedAppearance.hairColor = color
        current_character.PedAppearance.hairHighlightColor = highlight
        hair_color_selection = color
        hair_highlight_color_selection = highlight
    end

    local function change_player_eye_color(color)
        SetPedEyeColor(PlayerPedId(), color)
        current_character.PedAppearance.eyeColor = color
        eye_color_selection = color
    end

    local function set_player_clothing()
        local ped = PlayerPedId()
        SetPedComponentVariation(ped, 3, 15, 0, 0)
        current_character.DrawableVariations.clothes['3'] = MpPedData.kvp(15, 0)

        if current_character.IsMale then
            SetPedComponentVariation(ped, 8, 15, 0, 0)
            current_character.DrawableVariations.clothes['8'] = MpPedData.kvp(15, 0)
            SetPedComponentVariation(ped, 11, 15, 0, 0)
            current_character.DrawableVariations.clothes['11'] = MpPedData.kvp(15, 0)

            local pants_color = rand_next(GetNumberOfPedTextureVariations(ped, 4, 61))
            SetPedComponentVariation(ped, 4, 61, pants_color, 0)
            current_character.DrawableVariations.clothes['4'] = MpPedData.kvp(61, pants_color)

            SetPedComponentVariation(ped, 6, 34, 0, 0)
            current_character.DrawableVariations.clothes['6'] = MpPedData.kvp(34, 0)
        else
            SetPedComponentVariation(ped, 8, 14, 0, 0)
            SetPedComponentVariation(ped, 8, 14, 0, 0)
            current_character.DrawableVariations.clothes['8'] = MpPedData.kvp(14, 0)

            local bra_color = rand_next(GetNumberOfPedTextureVariations(ped, 4, 17))
            SetPedComponentVariation(ped, 4, 17, bra_color, 0)
            current_character.DrawableVariations.clothes['4'] = MpPedData.kvp(17, bra_color)

            SetPedComponentVariation(ped, 11, 18, bra_color, 0)
            current_character.DrawableVariations.clothes['11'] = MpPedData.kvp(18, bra_color)

            SetPedComponentVariation(ped, 6, 35, 0, 0)
            current_character.DrawableVariations.clothes['6'] = MpPedData.kvp(35, 0)
        end
    end

    -- DefaultPlayerColors: reset overlay colors so defaults aren't green.
    local function default_player_colors()
        set_head_blend()
        local ped = PlayerPedId()
        local color_indexes = { [1] = 1, [2] = 1, [8] = 2, [10] = 1 }
        for i = 0, 11 do
            local color_index = color_indexes[i]
            if color_index ~= nil then
                SetPedHeadOverlay(ped, i, 0, 0.0)
                SetPedHeadOverlayColor(ped, i, color_index, 0, 0)
            end
        end
    end

    -- KVP-backed category/character listings.
    local function get_all_category_names()
        local categories = {}
        local handle = StartFindKvp('mp_character_category_')
        while true do
            local found = FindKvp(handle)
            if found == nil or found == '' then
                break
            end
            categories[#categories + 1] = found:sub(23)
        end
        EndFindKvp(handle)
        table.insert(categories, 1, 'Create New')
        table.insert(categories, 2, 'Uncategorized')
        return categories
    end

    local function get_category_icons(category_names)
        local icons = {}
        for _, name in ipairs(category_names) do
            local record = Storage.get_saved_mp_character_category_data('mp_character_category_' .. name)
            icons[#icons + 1] = record.Icon or 0
        end
        return icons
    end

    local function get_all_mp_character_names()
        local names = {}
        local handle = StartFindKvp('mp_ped_')
        while true do
            local found = FindKvp(handle)
            if found == nil or found == '' then
                break
            end
            names[#names + 1] = found:sub(8)
        end
        EndFindKvp(handle)
        return names
    end

    -- AppySavedDataToPed (typo theirs): applies a MultiplayerPedData record.
    local function apply_saved_data_to_ped(character, ped_handle)
        -- head blend
        local blend = character.PedHeadBlendData or {}
        SetPedHeadBlendData(
            ped_handle,
            blend.FirstFaceShape or 0,
            blend.SecondFaceShape or 0,
            blend.ThirdFaceShape or 0,
            blend.FirstSkinTone or 0,
            blend.SecondSkinTone or 0,
            blend.ThirdSkinTone or 0,
            blend.ParentFaceShapePercent or 0.0,
            blend.ParentSkinTonePercent or 0.0,
            0.0,
            blend.IsParentInheritance == true
        )
        while not HasPedHeadBlendFinished(ped_handle) do
            Wait(0)
        end

        -- appearance
        local app = character.PedAppearance or {}
        SetPedComponentVariation(ped_handle, 2, app.hairStyle or 0, 0, 0)
        SetPedHairColor(ped_handle, app.hairColor or 0, app.hairHighlightColor or 0)
        local overlay = app.HairOverlay
        if
            overlay ~= nil
            and overlay.Key ~= nil
            and overlay.Key ~= ''
            and overlay.Value ~= nil
            and overlay.Value ~= ''
        then
            SetPedFacialDecoration(ped_handle, GetHashKey(overlay.Key), GetHashKey(overlay.Value))
        end
        SetPedHeadOverlay(ped_handle, 0, app.blemishesStyle or 0, app.blemishesOpacity or 0.0)
        SetPedHeadOverlay(ped_handle, 1, app.beardStyle or 0, app.beardOpacity or 0.0)
        SetPedHeadOverlayColor(ped_handle, 1, 1, app.beardColor or 0, app.beardColor or 0)
        SetPedHeadOverlay(ped_handle, 2, app.eyebrowsStyle or 0, app.eyebrowsOpacity or 0.0)
        SetPedHeadOverlayColor(ped_handle, 2, 1, app.eyebrowsColor or 0, app.eyebrowsColor or 0)
        SetPedHeadOverlay(ped_handle, 3, app.ageingStyle or 0, app.ageingOpacity or 0.0)
        SetPedHeadOverlay(ped_handle, 4, app.makeupStyle or 0, app.makeupOpacity or 0.0)
        SetPedHeadOverlayColor(ped_handle, 4, 2, app.makeupColor or 0, app.makeupColor or 0)
        SetPedHeadOverlay(ped_handle, 5, app.blushStyle or 0, app.blushOpacity or 0.0)
        SetPedHeadOverlayColor(ped_handle, 5, 2, app.blushColor or 0, app.blushColor or 0)
        SetPedHeadOverlay(ped_handle, 6, app.complexionStyle or 0, app.complexionOpacity or 0.0)
        SetPedHeadOverlay(ped_handle, 7, app.sunDamageStyle or 0, app.sunDamageOpacity or 0.0)
        SetPedHeadOverlay(ped_handle, 8, app.lipstickStyle or 0, app.lipstickOpacity or 0.0)
        SetPedHeadOverlayColor(ped_handle, 8, 2, app.lipstickColor or 0, app.lipstickColor or 0)
        SetPedHeadOverlay(ped_handle, 9, app.molesFrecklesStyle or 0, app.molesFrecklesOpacity or 0.0)
        SetPedHeadOverlay(ped_handle, 10, app.chestHairStyle or 0, app.chestHairOpacity or 0.0)
        SetPedHeadOverlayColor(ped_handle, 10, 1, app.chestHairColor or 0, app.chestHairColor or 0)
        SetPedHeadOverlay(ped_handle, 11, app.bodyBlemishesStyle or 0, app.bodyBlemishesOpacity or 0.0)
        SetPedEyeColor(ped_handle, app.eyeColor or 0)

        -- face shape
        for i = 0, 18 do
            SetPedFaceFeature(ped_handle, i, 0.0)
        end
        character.FaceShapeFeatures = character.FaceShapeFeatures or {}
        if character.FaceShapeFeatures.features ~= nil then
            for feature, value in pairs(character.FaceShapeFeatures.features) do
                SetPedFaceFeature(ped_handle, math.tointeger(tonumber(feature)), value)
            end
        else
            character.FaceShapeFeatures.features = {}
        end

        -- clothing
        local clothes = (character.DrawableVariations or {}).clothes
        if clothes ~= nil then
            for component, drawable in pairs(clothes) do
                SetPedComponentVariation(
                    ped_handle,
                    math.tointeger(tonumber(component)),
                    drawable.Key,
                    drawable.Value,
                    0
                )
            end
        end

        -- props
        local props = (character.PropVariations or {}).props
        if props ~= nil then
            for prop, variation in pairs(props) do
                if variation.Key > -1 then
                    local texture_index = variation.Value > -1 and variation.Value or 0
                    SetPedPropIndex(ped_handle, math.tointeger(tonumber(prop)), variation.Key, texture_index, true)
                end
            end
        end

        -- tattoos
        character.PedTatttoos = character.PedTatttoos or MpPedData.new_ped_tattoos()
        local tattoos = character.PedTatttoos
        for _, zone in pairs(TATTOO_ZONES) do
            tattoos[zone[1]] = tattoos[zone[1]] or {}
        end
        for _, zone in pairs(TATTOO_ZONES) do
            for _, tattoo in ipairs(tattoos[zone[1]]) do
                AddPedDecorationFromHashes(ped_handle, GetHashKey(tattoo.Key), GetHashKey(tattoo.Value))
            end
        end
    end
    self.apply_saved_data_to_ped = apply_saved_data_to_ped

    -- SpawnSavedPed: spawns from current_character (set it first!). The
    -- restore_weapons parameter is unused upstream too; the temp loadout is
    -- always restored.
    local function spawn_saved_ped(_restore_weapons)
        if (current_character.Version or 0) < 1 then
            return
        end
        if IsModelInCdimage(current_character.ModelHash) then
            if not HasModelLoaded(current_character.ModelHash) then
                RequestModel(current_character.ModelHash)
                while not HasModelLoaded(current_character.ModelHash) do
                    Wait(0)
                end
            end
            local ped = PlayerPedId()
            local max_health = GetPedMaxHealth(ped)
            local max_armour = GetPlayerMaxArmour(PlayerId())
            local health = GetEntityHealth(ped)
            local armour = GetPedArmour(ped)

            Weapons.save_weapon_loadout(TEMP_LOADOUT_NAME)
            SetPlayerModel(PlayerId(), current_character.ModelHash)
            Weapons.spawn_weapon_loadout(TEMP_LOADOUT_NAME, false, true, true)

            ped = PlayerPedId()
            SetPlayerMaxArmour(PlayerId(), max_armour)
            SetPedMaxHealth(ped, max_health)
            SetEntityHealth(ped, health)
            SetPedArmour(ped, armour)

            ClearPedDecorations(ped)
            ClearPedFacialDecorations(ped)
            SetPedDefaultComponentVariation(ped)
            SetPedHairColor(ped, 0, 0)
            SetPedEyeColor(ped, 0)
            ClearAllPedProps(ped)

            apply_saved_data_to_ped(current_character, ped)
        end

        SetFacialIdleAnimOverride(PlayerPedId(), current_character.FacialExpression or FACIAL_EXPRESSIONS[1], nil)
    end

    -- SpawnThisCharacter: used by the respawn-as-default-character flow too.
    function self.spawn_this_character(name, restore_weapons)
        current_character = Storage.get_saved_mp_character_data(name)
        spawn_saved_ped(restore_weapons)
    end

    -- SavePed: serialize current_character; asks for a name on first save.
    local function save_current_character()
        current_character.PedHeadBlendData = current_head_blend
        if is_editing_ped then
            if Storage.save_json_data(current_character.SaveName, Json.encode(current_character), true) then
                Notify.success('Your character was saved successfully.')
                return true
            end
            Notify.error('Your character could not be saved. Reason unknown. :(')
            return false
        end

        local name = Common.get_user_input('Enter a save name.', nil, 30)
        if name == nil or name == '' then
            Notify.error(Notification.error_message('InvalidInput'))
            return false
        end
        current_character.SaveName = 'mp_ped_' .. name
        if Storage.save_json_data('mp_ped_' .. name, Json.encode(current_character), false) then
            Notify.success(('Your character (~g~<C>%s</C>~s~) has been saved.'):format(name))
            return true
        end
        Notify.error(('Saving failed, most likely because this name (~y~<C>%s</C>~s~) is already in use.'):format(name))
        return false
    end

    -- -----------------------------------------------------------------------
    -- Style lists (sizes read from the game once, like the C# constructor)
    -- -----------------------------------------------------------------------

    local overlay_colors_list = {}
    for i = 1, GetNumHairColors() do
        overlay_colors_list[#overlay_colors_list + 1] = ('Color #%d'):format(i)
    end
    local overlay_style_lists = {} -- [overlay id 0..11] = style list
    for overlay_id = 0, 11 do
        local styles = {}
        for i = 1, GetNumHeadOverlayValues(overlay_id) do
            styles[#styles + 1] = ('Style #%d'):format(i)
        end
        overlay_style_lists[overlay_id] = styles
    end

    -- -----------------------------------------------------------------------
    -- Main menu
    -- -----------------------------------------------------------------------

    local saved_characters_btn =
        Items.MenuItem.new('Saved Characters', 'Spawn, edit or delete your existing saved multiplayer characters.')
    saved_characters_btn.Label = '→→→'

    Controller.AddMenu(create_character_menu)
    Controller.AddMenu(saved_characters_menu)
    Controller.AddMenu(saved_characters_category_menu)
    Controller.AddMenu(inheritance_menu)
    Controller.AddMenu(appearance_menu)
    Controller.AddMenu(face_shape_menu)
    Controller.AddMenu(tattoos_menu)
    Controller.AddMenu(clothes_menu)
    Controller.AddMenu(props_menu)

    menu:AddMenuItem(create_male_btn)
    Controller.BindMenuItem(menu, create_character_menu, create_male_btn)
    menu:AddMenuItem(create_female_btn)
    Controller.BindMenuItem(menu, create_character_menu, create_female_btn)
    menu:AddMenuItem(saved_characters_btn)
    Controller.BindMenuItem(menu, saved_characters_menu, saved_characters_btn)

    menu:RefreshIndex()

    -- camera control hints (the camera itself runs in FunctionsController)
    local MOVE_LR, PHONE_EXTRA, PARACHUTE_BRAKE_LEFT, PARACHUTE_BRAKE_RIGHT = 30, 179, 152, 153
    for _, editor_menu in ipairs({
        create_character_menu,
        inheritance_menu,
        appearance_menu,
        face_shape_menu,
        tattoos_menu,
        clothes_menu,
        props_menu,
    }) do
        editor_menu:AddInstructionalButton(MOVE_LR, 'Turn Head')
        editor_menu:AddInstructionalButton(PHONE_EXTRA, 'Turn Character')
        editor_menu:AddInstructionalButton(PARACHUTE_BRAKE_RIGHT, 'Turn Camera Right')
        editor_menu:AddInstructionalButton(PARACHUTE_BRAKE_LEFT, 'Turn Camera Left')
    end

    local randomize_button = Items.MenuItem.new('Randomize Character', 'Randomize character appearance.')
    local inheritance_button = Items.MenuItem.new('Character Inheritance', 'Character inheritance options.')
    local appearance_button = Items.MenuItem.new('Character Appearance', 'Character appearance options.')
    local face_button = Items.MenuItem.new('Character Face Shape Options', 'Character face shape options.')
    local tattoos_button = Items.MenuItem.new('Character Tattoo Options', 'Character tattoo options.')
    local clothes_button = Items.MenuItem.new('Character Clothes', 'Character clothes.')
    local props_button = Items.MenuItem.new('Character Props', 'Character props.')
    local save_button = Items.MenuItem.new('Save Character', 'Save your character.')
    local exit_no_save = Items.MenuItem.new('Exit Without Saving', 'Are you sure? All unsaved work will be lost.')
    local face_expression_list = Items.MenuListItem.new(
        'Facial Expression',
        { 'Normal', 'Happy', 'Angry', 'Aiming', 'Injured', 'Stressed', 'Smug', 'Sulk' },
        0,
        'Set a facial expression that will be used whenever your ped is idling.'
    )

    inheritance_button.Label = '→→→'
    appearance_button.Label = '→→→'
    face_button.Label = '→→→'
    tattoos_button.Label = '→→→'
    clothes_button.Label = '→→→'
    props_button.Label = '→→→'

    create_character_menu:AddMenuItem(randomize_button)
    create_character_menu:AddMenuItem(inheritance_button)
    create_character_menu:AddMenuItem(appearance_button)
    create_character_menu:AddMenuItem(face_button)
    create_character_menu:AddMenuItem(tattoos_button)
    create_character_menu:AddMenuItem(clothes_button)
    create_character_menu:AddMenuItem(props_button)
    create_character_menu:AddMenuItem(face_expression_list)
    create_character_menu:AddMenuItem(category_btn)
    create_character_menu:AddMenuItem(save_button)
    create_character_menu:AddMenuItem(exit_no_save)

    Controller.BindMenuItem(create_character_menu, inheritance_menu, inheritance_button)
    Controller.BindMenuItem(create_character_menu, appearance_menu, appearance_button)
    Controller.BindMenuItem(create_character_menu, face_shape_menu, face_button)
    Controller.BindMenuItem(create_character_menu, tattoos_menu, tattoos_button)
    Controller.BindMenuItem(create_character_menu, clothes_menu, clothes_button)
    Controller.BindMenuItem(create_character_menu, props_menu, props_button)

    -- -----------------------------------------------------------------------
    -- Inheritance
    -- -----------------------------------------------------------------------

    -- skin names exclude addon faces; parent names include them
    local skin_names = {}
    local parent_names = {}
    for _, blend_head in ipairs(BLEND_HEADS_NAMES) do
        local list_id, list_name = blend_head[1], blend_head[2]
        local is_male = list_name:find('Male', 1, true) ~= nil
        for i = 0, GetNumParentPedsOfType(list_id) - 1 do
            local label = GetLabelText(('%s%d'):format(list_name, i))
            if label == nil or label:gsub('%s', '') == '' or label == 'NULL' then
                label = tostring(i)
            end
            label = label .. (is_male and ' (Male)' or ' (Female)')
            skin_names[#skin_names + 1] = label
            parent_names[#parent_names + 1] = label
        end
    end
    for _, face in ipairs(State.extra_blendable_faces) do
        parent_names[#parent_names + 1] = face
    end

    local inheritance_parent_one = Items.MenuListItem.new('Parent #1', parent_names, 0, 'Select first parent.')
    local inheritance_parent_one_skin =
        Items.MenuListItem.new('Parent #1 Skin', skin_names, 0, "Select first parent's skin texture.")
    local inheritance_parent_two = Items.MenuListItem.new('Parent #2', parent_names, 0, 'Select second parent.')
    local inheritance_parent_two_skin =
        Items.MenuListItem.new('Parent #2 Skin', skin_names, 0, "Select first parent's skin texture.")
    local inheritance_shape_mix = Items.MenuSliderItem.new(
        'Head Shape Mix',
        0,
        10,
        5,
        'Select how much of your head shape should be inherited from each parent. All the way on the left is '
            .. 'Parent #1, all the way on the right is Parent #2.'
    )
    inheritance_shape_mix.ShowDivider = true
    inheritance_shape_mix.ItemData = 'shape_mix'
    local inheritance_skin_mix = Items.MenuSliderItem.new(
        'Body Skin Mix',
        0,
        10,
        5,
        'Select how much of your body skin tone should be inherited from each parent. All the way on the left is '
            .. 'Parent #1, all the way on the right is Parent #2.'
    )
    inheritance_skin_mix.ShowDivider = true
    inheritance_skin_mix.ItemData = 'skin_mix'

    inheritance_menu:AddMenuItem(inheritance_parent_one)
    inheritance_menu:AddMenuItem(inheritance_parent_one_skin)
    inheritance_menu:AddMenuItem(inheritance_parent_two)
    inheritance_menu:AddMenuItem(inheritance_parent_two_skin)
    inheritance_menu:AddMenuItem(inheritance_shape_mix)
    inheritance_menu:AddMenuItem(inheritance_skin_mix)

    inheritance_menu.OnListIndexChange = function(_, _item, _old_index, _new_index, _item_index)
        parent_one = inheritance_parent_one.ListIndex
        parent_one_skin = inheritance_parent_one_skin.ListIndex
        parent_two = inheritance_parent_two.ListIndex
        parent_two_skin = inheritance_parent_two_skin.ListIndex
        set_head_blend()
    end

    inheritance_menu.OnSliderPositionChange = function(_, item, _old_position, new_position, _item_index)
        if item.ItemData == 'shape_mix' then
            shape_mix_value = new_position / 10
        elseif item.ItemData == 'skin_mix' then
            skin_mix_value = new_position / 10
        end
        set_head_blend()
    end

    -- -----------------------------------------------------------------------
    -- Appearance handlers
    -- -----------------------------------------------------------------------

    -- overlay id + whether it has a color (with the color slot type) per the
    -- style item's position in the appearance menu.
    local APPEARANCE_STYLE_ITEMS = {
        [3] = { overlay = 0, field = 'blemishes' },
        [5] = { overlay = 1, field = 'beard' },
        [8] = { overlay = 2, field = 'eyebrows' },
        [11] = { overlay = 3, field = 'ageing' },
        [13] = { overlay = 4, field = 'makeup' },
        [16] = { overlay = 5, field = 'blush' },
        [19] = { overlay = 6, field = 'complexion' },
        [21] = { overlay = 7, field = 'sunDamage' },
        [23] = { overlay = 8, field = 'lipstick' },
        [26] = { overlay = 9, field = 'molesFreckles' },
        [28] = { overlay = 10, field = 'chestHair' },
        [31] = { overlay = 11, field = 'bodyBlemishes' },
    }
    local APPEARANCE_COLOR_ITEMS = {
        [7] = { overlay = 1, color_type = 1, field = 'beard' },
        [10] = { overlay = 2, color_type = 1, field = 'eyebrows' },
        [15] = { overlay = 4, color_type = 2, field = 'makeup' },
        [18] = { overlay = 5, color_type = 2, field = 'blush' },
        [25] = { overlay = 8, color_type = 2, field = 'lipstick' },
        [30] = { overlay = 10, color_type = 1, field = 'chestHair' },
    }
    local APPEARANCE_OPACITY_ITEMS = {
        [4] = { overlay = 0, field = 'blemishes' },
        [6] = { overlay = 1, field = 'beard' },
        [9] = { overlay = 2, field = 'eyebrows' },
        [12] = { overlay = 3, field = 'ageing' },
        [14] = { overlay = 4, field = 'makeup' },
        [17] = { overlay = 5, field = 'blush' },
        [20] = { overlay = 6, field = 'complexion' },
        [22] = { overlay = 7, field = 'sunDamage' },
        [24] = { overlay = 8, field = 'lipstick' },
        [27] = { overlay = 9, field = 'molesFreckles' },
        [29] = { overlay = 10, field = 'chestHair' },
        [32] = { overlay = 11, field = 'bodyBlemishes' },
    }

    local function list_index_at(target_menu, item_index)
        local item = target_menu:GetMenuItems()[item_index + 1]
        if item ~= nil and item.ListItems ~= nil then
            return item.ListIndex
        end
        return nil
    end

    local function set_appearance_style(field, overlay_id, selection, opacity)
        SetPedHeadOverlay(PlayerPedId(), overlay_id, selection, opacity)
        current_character.PedAppearance[field .. 'Style'] = selection
        current_character.PedAppearance[field .. 'Opacity'] = opacity
    end

    on(appearance_menu, 'OnListIndexChange', function(changed_menu, _item, _old_index, new_index, item_index)
        if item_index == 0 then -- hair style
            change_player_hair(new_index)
        elseif item_index == 1 or item_index == 2 then -- hair colors
            local hair_color = list_index_at(changed_menu, 1)
            local hair_highlight_color = list_index_at(changed_menu, 2)
            change_player_hair_color(hair_color, hair_highlight_color)
        elseif item_index == 33 then -- eye color
            change_player_eye_color(list_index_at(changed_menu, item_index))
        else
            local style = APPEARANCE_STYLE_ITEMS[item_index]
            local color = APPEARANCE_COLOR_ITEMS[item_index]
            if style ~= nil then
                -- the opacity item sits right after the style item
                local opacity_index = list_index_at(changed_menu, item_index + 1)
                    or list_index_at(changed_menu, item_index)
                    or 9
                local opacity = ((opacity_index + 1) / 10) - 0.1
                set_appearance_style(style.field, style.overlay, new_index, opacity)
            elseif color ~= nil then
                SetPedHeadOverlayColor(PlayerPedId(), color.overlay, color.color_type, new_index, new_index)
                current_character.PedAppearance[color.field .. 'Color'] = new_index
            end
        end
    end)

    -- second upstream handler: the opacity lists (item after the style item)
    on(appearance_menu, 'OnListIndexChange', function(changed_menu, _item, _old_index, new_index, item_index)
        if item_index > 2 and item_index < 33 then
            local opacity_item = APPEARANCE_OPACITY_ITEMS[item_index]
            if opacity_item ~= nil then
                local selection = list_index_at(changed_menu, item_index - 1)
                local opacity = ((new_index + 1) / 10) - 0.1
                set_appearance_style(opacity_item.field, opacity_item.overlay, selection, opacity)
            end
        end
    end)

    -- -----------------------------------------------------------------------
    -- Clothes
    -- -----------------------------------------------------------------------

    local clothes_description = 'Select a drawable using the arrow keys and press ~o~enter~s~ to cycle through all '
        .. 'available textures.'

    local function clothing_component_for(item_index)
        local component_index = item_index + 1
        if item_index > 0 then
            component_index = component_index + 1
        end
        return component_index
    end

    local function change_clothing_list_item(item_index, new_selection_index, list_item)
        local ped = PlayerPedId()
        local component_index = clothing_component_for(item_index)
        SetPedComponentVariation(ped, component_index, new_selection_index, 0, 0)
        local max_textures = GetNumberOfPedTextureVariations(ped, component_index, new_selection_index)
        current_character.DrawableVariations.clothes[tostring(component_index)] = MpPedData.kvp(new_selection_index, 0)
        list_item.Description = ('%s Currently selected texture: #%d (of %d).'):format(
            clothes_description,
            1,
            max_textures
        )
    end

    clothes_menu.OnListIndexChange = function(_, list_item, _old_index, new_index, real_index)
        change_clothing_list_item(real_index, new_index, list_item)
    end

    clothes_menu.OnListItemSelect = function(_, list_item, list_index, real_index)
        if IsControlPressed(0, 36) then -- Duck: direct ID input
            local user_input = Common.get_user_input('Enter Drawable ID', nil, 5)
            local drawable_id = math.tointeger(tonumber(user_input or ''))
            if
                user_input == nil
                or user_input == ''
                or drawable_id == nil
                or drawable_id < 0
                or drawable_id > list_item:ItemsCount()
            then
                Notify.error('Invalid input')
                return
            end
            list_item.ListIndex = drawable_id
            change_clothing_list_item(real_index, drawable_id, list_item)
            return
        end

        local ped = PlayerPedId()
        local component_index = clothing_component_for(real_index)
        local texture_index = GetPedTextureVariation(ped, component_index)
        local new_texture_index = GetNumberOfPedTextureVariations(ped, component_index, list_index) - 1
                    < texture_index + 1
                and 0
            or texture_index + 1
        SetPedComponentVariation(ped, component_index, list_index, new_texture_index, 0)
        local max_textures = GetNumberOfPedTextureVariations(ped, component_index, list_index)
        current_character.DrawableVariations.clothes[tostring(component_index)] =
            MpPedData.kvp(list_index, new_texture_index)
        list_item.Description = ('%s Currently selected texture: #%d (of %d).'):format(
            clothes_description,
            new_texture_index + 1,
            max_textures
        )
    end

    -- -----------------------------------------------------------------------
    -- Props
    -- -----------------------------------------------------------------------

    local props_description = 'Select a prop using the arrow keys and press ~o~enter~s~ to cycle through all '
        .. 'available textures.'

    local function prop_index_for(item_index)
        if item_index == 3 then
            return 6
        elseif item_index == 4 then
            return 7
        end
        return item_index
    end

    local function change_prop_list_item(item_index, new_selection_index, list_item)
        local ped = PlayerPedId()
        local prop_index = prop_index_for(item_index)
        if new_selection_index >= GetNumberOfPedPropDrawableVariations(ped, prop_index) then
            SetPedPropIndex(ped, prop_index, -1, -1, false)
            ClearPedProp(ped, prop_index)
            current_character.PropVariations.props[tostring(prop_index)] = MpPedData.kvp(-1, -1)
            list_item.Description = props_description
        else
            SetPedPropIndex(ped, prop_index, new_selection_index, 0, true)
            current_character.PropVariations.props[tostring(prop_index)] = MpPedData.kvp(new_selection_index, 0)
            if GetPedPropIndex(ped, prop_index) == -1 then
                list_item.Description = props_description
            else
                local max_prop_textures = GetNumberOfPedPropTextureVariations(ped, prop_index, new_selection_index)
                list_item.Description = ('%s Currently selected texture: #%d (of %d).'):format(
                    props_description,
                    1,
                    max_prop_textures
                )
            end
        end
    end

    props_menu.OnListIndexChange = function(_, list_item, _old_index, new_index, real_index)
        change_prop_list_item(real_index, new_index, list_item)
    end

    props_menu.OnListItemSelect = function(_, list_item, list_index, real_index)
        if IsControlPressed(0, 36) then -- Duck: direct ID input
            local user_input = Common.get_user_input('Enter Prop ID', nil, 5)
            local drawable_id = math.tointeger(tonumber(user_input or ''))
            if
                user_input == nil
                or user_input == ''
                or drawable_id == nil
                or drawable_id < -1
                or drawable_id > list_item:ItemsCount()
            then
                Notify.error('Invalid input')
                return
            end
            list_item.ListIndex = drawable_id
            if drawable_id == -1 then
                ClearPedProp(PlayerPedId(), real_index)
                return
            end
            change_prop_list_item(real_index, drawable_id, list_item)
            return
        end

        local ped = PlayerPedId()
        local prop_index = prop_index_for(real_index)
        local texture_index = GetPedPropTextureIndex(ped, prop_index)
        local new_texture_index = GetNumberOfPedPropTextureVariations(ped, prop_index, list_index) - 1
                    < texture_index + 1
                and 0
            or texture_index + 1
        if texture_index >= GetNumberOfPedPropDrawableVariations(ped, prop_index) then
            SetPedPropIndex(ped, prop_index, -1, -1, false)
            ClearPedProp(ped, prop_index)
            current_character.PropVariations.props[tostring(prop_index)] = MpPedData.kvp(-1, -1)
            list_item.Description = props_description
        else
            SetPedPropIndex(ped, prop_index, list_index, new_texture_index, true)
            current_character.PropVariations.props[tostring(prop_index)] = MpPedData.kvp(list_index, new_texture_index)
            if GetPedPropIndex(ped, prop_index) == -1 then
                list_item.Description = props_description
            else
                local max_prop_textures = GetNumberOfPedPropTextureVariations(ped, prop_index, list_index)
                list_item.Description = ('%s Currently selected texture: #%d (of %d).'):format(
                    props_description,
                    new_texture_index + 1,
                    max_prop_textures
                )
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Face shape sliders
    -- -----------------------------------------------------------------------

    local FACE_FEATURE_NAMES = {
        'Nose Width', -- 0
        'Noes Peak Height', -- 1 (typo theirs)
        'Nose Peak Length', -- 2
        'Nose Bone Height', -- 3
        'Nose Peak Lowering', -- 4
        'Nose Bone Twist', -- 5
        'Eyebrows Height', -- 6
        'Eyebrows Depth', -- 7
        'Cheekbones Height', -- 8
        'Cheekbones Width', -- 9
        'Cheeks Width', -- 10
        'Eyes Opening', -- 11
        'Lips Thickness', -- 12
        'Jaw Bone Width', -- 13
        'Jaw Bone Depth/Length', -- 14
        'Chin Height', -- 15
        'Chin Depth/Length', -- 16
        'Chin Width', -- 17
        'Chin Hole Size', -- 18
        'Neck Thickness', -- 19
    }

    for i = 1, 20 do
        local face_feature = Items.MenuSliderItem.new(
            FACE_FEATURE_NAMES[i],
            0,
            20,
            10,
            ('Set the %s face feature value.'):format(FACE_FEATURE_NAMES[i])
        )
        face_feature.ShowDivider = true
        face_shape_menu:AddMenuItem(face_feature)
    end

    face_shape_menu.OnSliderPositionChange = function(_, _slider_item, _old_position, new_position, item_index)
        current_character.FaceShapeFeatures.features = current_character.FaceShapeFeatures.features or {}
        local value = FACE_FEATURE_VALUES[new_position + 1]
        current_character.FaceShapeFeatures.features[tostring(item_index)] = value
        SetPedFaceFeature(PlayerPedId(), item_index, value)
    end

    -- -----------------------------------------------------------------------
    -- Tattoos
    -- -----------------------------------------------------------------------

    local function tattoo_collection()
        return current_character.IsMale and Tattoos.male or Tattoos.female
    end

    local function create_lists_if_nil()
        current_character.PedTatttoos = current_character.PedTatttoos or MpPedData.new_ped_tattoos()
        for _, zone in pairs(TATTOO_ZONES) do
            current_character.PedTatttoos[zone[1]] = current_character.PedTatttoos[zone[1]] or {}
        end
    end

    local function apply_saved_tattoos()
        -- remove all decorations, then manually re-add them all
        local ped = PlayerPedId()
        ClearPedDecorations(ped)
        for _, zone in pairs(TATTOO_ZONES) do
            for _, tattoo in ipairs(current_character.PedTatttoos[zone[1]]) do
                AddPedDecorationFromHashes(ped, GetHashKey(tattoo.Key), GetHashKey(tattoo.Value))
            end
        end

        local overlay = current_character.PedAppearance.HairOverlay
        if
            overlay ~= nil
            and overlay.Key ~= nil
            and overlay.Key ~= ''
            and overlay.Value ~= nil
            and overlay.Value ~= ''
        then
            -- reset hair value
            AddPedDecorationFromHashes(ped, GetHashKey(overlay.Key), GetHashKey(overlay.Value))
        end
    end

    tattoos_menu.OnIndexChange = function(_, _old_item, _new_item, _old_index, _new_index)
        create_lists_if_nil()
        apply_saved_tattoos()
    end

    tattoos_menu.OnListIndexChange = function(_, _item, _old_index, tattoo_index, menu_index)
        create_lists_if_nil()
        apply_saved_tattoos()
        local zone = TATTOO_ZONES[menu_index]
        if zone == nil then
            return
        end
        local tattoo = tattoo_collection()[zone[2]][tattoo_index + 1]
        if tattoo == nil then
            return
        end
        local tat = MpPedData.kvp(tattoo.collectionName, tattoo.name)
        if not list_contains(current_character.PedTatttoos[zone[1]], tat) then
            AddPedDecorationFromHashes(PlayerPedId(), GetHashKey(tat.Key), GetHashKey(tat.Value))
        end
    end

    tattoos_menu.OnListItemSelect = function(_, item, tattoo_index, menu_index)
        create_lists_if_nil()

        local is_badges_item = menu_index == 7
        if IsControlPressed(0, 36) then -- Duck: direct ID input
            local user_input =
                Common.get_user_input(('Enter %s ID'):format(is_badges_item and 'Badge' or 'Tattoo'), nil, 5)
            local drawable_id = math.tointeger(tonumber(user_input or ''))
            if
                user_input == nil
                or user_input == ''
                or drawable_id == nil
                or drawable_id < 1
                or drawable_id > item:ItemsCount()
            then
                Notify.error('Invalid input')
                return
            end
            drawable_id = drawable_id - 1
            item.ListIndex = drawable_id
            tattoo_index = drawable_id
        end

        local zone = TATTOO_ZONES[menu_index]
        if zone ~= nil then
            local tattoo = tattoo_collection()[zone[2]][tattoo_index + 1]
            if tattoo ~= nil then
                local tat = MpPedData.kvp(tattoo.collectionName, tattoo.name)
                local label = is_badges_item and 'Badge'
                    or (zone[2] == 'ADDONS' and 'Addon Tattoo')
                    or ({
                        HAIR = 'Hair Tattoo',
                        HEAD = 'Head Tattoo',
                        TORSO = 'Torso Tattoo',
                        LEFT_ARM = 'Left Arm Tattoo',
                        RIGHT_ARM = 'Right Arm Tattoo',
                        LEFT_LEG = 'Left Leg Tattoo',
                        RIGHT_LEG = 'Right Leg Tattoo',
                    })[zone[2]]
                if list_contains(current_character.PedTatttoos[zone[1]], tat) then
                    Subtitle.custom(('%s #%d has been ~r~removed~s~.'):format(label, tattoo_index + 1))
                    list_remove(current_character.PedTatttoos[zone[1]], tat)
                else
                    Subtitle.custom(('%s #%d has been ~g~added~s~.'):format(label, tattoo_index + 1))
                    table.insert(current_character.PedTatttoos[zone[1]], tat)
                end
            end
        end

        apply_saved_tattoos()
    end

    -- the only plain button in the tattoos menu is "Remove All"
    tattoos_menu.OnItemSelect = function(_, _item, _index)
        Notify.success('All tattoos have been removed.')
        current_character.PedTatttoos = MpPedData.new_ped_tattoos()
        ClearPedDecorations(PlayerPedId())
    end

    -- -----------------------------------------------------------------------
    -- MakeCreateCharacterMenu
    -- -----------------------------------------------------------------------

    local function make_create_character_menu(male, edit_ped)
        is_editing_ped = edit_ped == true
        local ped = PlayerPedId()

        if not edit_ped then
            current_character = MpPedData.new()
            current_character.DrawableVariations.clothes = {}
            current_character.PropVariations.props = {}
            current_character.PedHeadBlendData = current_head_blend
            current_character.Version = 1
            current_character.ModelHash = male and GetHashKey('mp_m_freemode_01') or GetHashKey('mp_f_freemode_01')
            current_character.IsMale = male

            shape_mix_value = 0.5
            skin_mix_value = 0.5

            set_player_clothing()
        else
            local blend = current_character.PedHeadBlendData or {}
            parent_one = blend.FirstFaceShape or 0
            parent_one_skin = blend.FirstSkinTone or 0
            parent_two = blend.SecondFaceShape or 0
            parent_two_skin = blend.SecondSkinTone or 0
            shape_mix_value = blend.ParentFaceShapePercent or 0.0
            skin_mix_value = blend.ParentSkinTonePercent or 0.0
            if shape_mix_value > 1.0 then
                shape_mix_value = 1.0
            end
            if skin_mix_value > 1.0 then
                skin_mix_value = 1.0
            end
            current_head_blend = blend
        end

        current_character.DrawableVariations.clothes = current_character.DrawableVariations.clothes or {}
        current_character.PropVariations.props = current_character.PropVariations.props or {}
        current_character.FacialExpression = current_character.FacialExpression or FACIAL_EXPRESSIONS[1]

        SetFacialIdleAnimOverride(ped, current_character.FacialExpression, nil)

        -- Upstream restores the facial expression list via ElementAt(6),
        -- which is actually the Character Props button, so the type check
        -- fails and nothing happens. Quirk preserved.
        local maybe_list = create_character_menu:GetMenuItems()[7]
        if maybe_list ~= nil and maybe_list.ListItems ~= nil then
            local index = 0
            for i, expression in ipairs(FACIAL_EXPRESSIONS) do
                if expression == current_character.FacialExpression then
                    index = i - 1
                    break
                end
            end
            maybe_list.ListIndex = index
        end

        appearance_menu:ClearMenuItems()
        tattoos_menu:ClearMenuItems()
        clothes_menu:ClearMenuItems()
        props_menu:ClearMenuItems()

        -- appearance -------------------------------------------------------
        if not edit_ped then
            hair_selection = 0
            hair_color_selection = 0
            hair_highlight_color_selection = 0
            eye_color_selection = 0
            for i = 0, 11 do
                appearance_values[i] = { 0, 0, 0.0 }
            end
        else
            local app = current_character.PedAppearance
            hair_selection = app.hairStyle or 0
            hair_color_selection = app.hairColor or 0
            hair_highlight_color_selection = app.hairHighlightColor or 0
            appearance_values[0] = { app.blemishesStyle or 0, 0, app.blemishesOpacity or 0.0 }
            appearance_values[1] = { app.beardStyle or 0, app.beardColor or 0, app.beardOpacity or 0.0 }
            appearance_values[2] = { app.eyebrowsStyle or 0, app.eyebrowsColor or 0, app.eyebrowsOpacity or 0.0 }
            appearance_values[3] = { app.ageingStyle or 0, 0, app.ageingOpacity or 0.0 }
            appearance_values[4] = { app.makeupStyle or 0, app.makeupColor or 0, app.makeupOpacity or 0.0 }
            appearance_values[5] = { app.blushStyle or 0, app.blushColor or 0, app.blushOpacity or 0.0 }
            appearance_values[6] = { app.complexionStyle or 0, 0, app.complexionOpacity or 0.0 }
            appearance_values[7] = { app.sunDamageStyle or 0, 0, app.sunDamageOpacity or 0.0 }
            appearance_values[8] = { app.lipstickStyle or 0, app.lipstickColor or 0, app.lipstickOpacity or 0.0 }
            appearance_values[9] = { app.molesFrecklesStyle or 0, 0, app.molesFrecklesOpacity or 0.0 }
            appearance_values[10] = { app.chestHairStyle or 0, app.chestHairColor or 0, app.chestHairOpacity or 0.0 }
            appearance_values[11] = { app.bodyBlemishesStyle or 0, 0, app.bodyBlemishesOpacity or 0.0 }
            eye_color_selection = app.eyeColor or 0
        end

        local opacity_list = { '0%', '10%', '20%', '30%', '40%', '50%', '60%', '70%', '80%', '90%', '100%' }

        local max_hair_styles = GetNumberOfPedDrawableVariations(ped, 2)
        local hair_styles_list = {}
        for i = 1, max_hair_styles + 1 do
            hair_styles_list[#hair_styles_list + 1] = ('Style #%d'):format(i)
        end

        local eye_color_list = {}
        for i = 1, 32 do
            eye_color_list[#eye_color_list + 1] = ('Eye Color #%d'):format(i)
        end

        local app = current_character.PedAppearance

        -- current values: saved data when editing, live ped values otherwise
        local function current_overlay_style(overlay_id, saved)
            if edit_ped then
                return saved or 0
            end
            local value = GetPedHeadOverlayValue(ped, overlay_id)
            if value ~= 255 then
                return value
            end
            return 0
        end

        local current_hair_style = edit_ped and (app.hairStyle or 0) or GetPedDrawableVariation(ped, 2)
        local current_hair_color = edit_ped and (app.hairColor or 0) or 0
        local current_hair_highlight_color = edit_ped and (app.hairHighlightColor or 0) or 0

        -- overlay id → { style, opacity, color?, color_type? } current values
        local overlay_defs = {
            [0] = { field = 'blemishes' },
            [1] = { field = 'beard', color_type = 1 },
            [2] = { field = 'eyebrows', color_type = 1 },
            [3] = { field = 'ageing' },
            [4] = { field = 'makeup', color_type = 2 },
            [5] = { field = 'blush', color_type = 2 },
            [6] = { field = 'complexion' },
            [7] = { field = 'sunDamage' },
            [8] = { field = 'lipstick', color_type = 2 },
            [9] = { field = 'molesFreckles' },
            [10] = { field = 'chestHair', color_type = 1 },
            [11] = { field = 'bodyBlemishes' },
        }
        local current = {}
        for overlay_id = 0, 11 do
            local def = overlay_defs[overlay_id]
            local style = current_overlay_style(overlay_id, app[def.field .. 'Style'])
            local overlay_opacity = edit_ped and (app[def.field .. 'Opacity'] or 0.0) or 0.0
            local color = edit_ped and (app[def.field .. 'Color'] or 0) or 0
            SetPedHeadOverlay(ped, overlay_id, style, overlay_opacity)
            if def.color_type ~= nil then
                SetPedHeadOverlayColor(ped, overlay_id, def.color_type, color, color)
            end
            current[overlay_id] = { style = style, opacity = overlay_opacity, color = color }
        end

        local current_eye_color = edit_ped and (app.eyeColor or 0) or 0
        SetPedEyeColor(ped, current_eye_color)

        local function style_item(text, overlay_id, description)
            return Items.MenuListItem.new(text, overlay_style_lists[overlay_id], current[overlay_id].style, description)
        end
        local function opacity_item(text, overlay_id, description)
            local item =
                Items.MenuListItem.new(text, opacity_list, math.floor(current[overlay_id].opacity * 10), description)
            item.ShowOpacityPanel = true
            return item
        end
        local function color_item(text, overlay_id, color_panel_type, description)
            local item = Items.MenuListItem.new(text, overlay_colors_list, current[overlay_id].color, description)
            item.ShowColorPanel = true
            item.ColorPanelColorType = color_panel_type
            return item
        end

        local hair_styles =
            Items.MenuListItem.new('Hair Style', hair_styles_list, current_hair_style, 'Select a hair style.')
        local hair_colors =
            Items.MenuListItem.new('Hair Color', overlay_colors_list, current_hair_color, 'Select a hair color.')
        hair_colors.ShowColorPanel = true
        hair_colors.ColorPanelColorType = 'Hair'
        local hair_highlight_colors = Items.MenuListItem.new(
            'Hair Highlight Color',
            overlay_colors_list,
            current_hair_highlight_color,
            'Select a hair highlight color.'
        )
        hair_highlight_colors.ShowColorPanel = true
        hair_highlight_colors.ColorPanelColorType = 'Hair'

        local blemishes_style = style_item('Blemishes Style', 0, 'Select a blemishes style.')
        local blemishes_opacity = opacity_item('Blemishes Opacity', 0, 'Select a blemishes opacity.')
        local beard_styles = style_item('Beard Style', 1, 'Select a beard/facial hair style.')
        local beard_opacity = opacity_item('Beard Opacity', 1, 'Select the opacity for your beard/facial hair.')
        local beard_color = color_item('Beard Color', 1, 'Hair', 'Select a beard color.')
        local eyebrow_style = style_item('Eyebrows Style', 2, 'Select an eyebrows style.')
        local eyebrow_opacity = opacity_item('Eyebrows Opacity', 2, 'Select the opacity for your eyebrows.')
        local eyebrow_color = color_item('Eyebrows Color', 2, 'Hair', 'Select an eyebrows color.')
        local ageing_style = style_item('Ageing Style', 3, 'Select an ageing style.')
        local ageing_opacity = opacity_item('Ageing Opacity', 3, 'Select an ageing opacity.')
        local makeup_style = style_item('Makeup Style', 4, 'Select a makeup style.')
        local makeup_opacity = opacity_item('Makeup Opacity', 4, 'Select a makeup opacity')
        local makeup_color = color_item('Makeup Color', 4, 'Makeup', 'Select a makeup color.')
        local blush_style = style_item('Blush Style', 5, 'Select a blush style.')
        local blush_opacity = opacity_item('Blush Opacity', 5, 'Select a blush opacity.')
        local blush_color = color_item('Blush Color', 5, 'Makeup', 'Select a blush color.')
        local complexion_style = style_item('Complexion Style', 6, 'Select a complexion style.')
        local complexion_opacity = opacity_item('Complexion Opacity', 6, 'Select a complexion opacity.')
        local sun_damage_style = style_item('Sun Damage Style', 7, 'Select a sun damage style.')
        local sun_damage_opacity = opacity_item('Sun Damage Opacity', 7, 'Select a sun damage opacity.')
        local lipstick_style = style_item('Lipstick Style', 8, 'Select a lipstick style.')
        local lipstick_opacity = opacity_item('Lipstick Opacity', 8, 'Select a lipstick opacity.')
        local lipstick_color = color_item('Lipstick Color', 8, 'Makeup', 'Select a lipstick color.')
        local moles_freckles_style = style_item('Moles and Freckles Style', 9, 'Select a moles and freckles style.')
        local moles_freckles_opacity =
            opacity_item('Moles and Freckles Opacity', 9, 'Select a moles and freckles opacity.')
        local chest_hair_style = style_item('Chest Hair Style', 10, 'Select a chest hair style.')
        local chest_hair_opacity = opacity_item('Chest Hair Opacity', 10, 'Select a chest hair opacity.')
        local chest_hair_color = color_item('Chest Hair Color', 10, 'Hair', 'Select a chest hair color.')
        local body_blemishes_style = style_item('Body Blemishes Style', 11, 'Select body blemishes style.')
        local body_blemishes_opacity = opacity_item('Body Blemishes Opacity', 11, 'Select body blemishes opacity.')
        local eye_color =
            Items.MenuListItem.new('Eye Colors', eye_color_list, current_eye_color, 'Select an eye/contact lens color.')

        for _, item in ipairs({
            hair_styles,
            hair_colors,
            hair_highlight_colors,
            blemishes_style,
            blemishes_opacity,
            beard_styles,
            beard_opacity,
            beard_color,
            eyebrow_style,
            eyebrow_opacity,
            eyebrow_color,
            ageing_style,
            ageing_opacity,
            makeup_style,
            makeup_opacity,
            makeup_color,
            blush_style,
            blush_opacity,
            blush_color,
            complexion_style,
            complexion_opacity,
            sun_damage_style,
            sun_damage_opacity,
            lipstick_style,
            lipstick_opacity,
            lipstick_color,
            moles_freckles_style,
            moles_freckles_opacity,
            chest_hair_style,
            chest_hair_opacity,
            chest_hair_color,
            body_blemishes_style,
            body_blemishes_opacity,
            eye_color,
        }) do
            appearance_menu:AddMenuItem(item)
        end

        if not male then
            for _, locked in ipairs({
                beard_styles,
                beard_opacity,
                beard_color,
                chest_hair_style,
                chest_hair_opacity,
                chest_hair_color,
            }) do
                locked.Enabled = false
                locked.LeftIcon = Items.Icon.LOCK
                locked.Description = 'This is not available for female characters.'
            end
        end

        -- clothes ------------------------------------------------------------
        local clothing_category_names = {
            'Unused (head)',
            'Masks',
            'Unused (hair)',
            'Upper Body',
            'Lower Body',
            'Bags & Parachutes',
            'Shoes',
            'Scarfs & Chains',
            'Shirt & Accessory',
            'Body Armor & Accessory 2',
            'Badges & Logos',
            'Shirt Overlay & Jackets',
        }
        for i = 0, 11 do
            if i ~= 0 and i ~= 2 then
                local saved_drawable = edit_ped and current_character.DrawableVariations.clothes[tostring(i)] or nil
                local current_variation_index = saved_drawable ~= nil and saved_drawable.Key
                    or GetPedDrawableVariation(ped, i)
                local current_variation_texture_index = saved_drawable ~= nil and saved_drawable.Value
                    or GetPedTextureVariation(ped, i)

                local max_drawables = GetNumberOfPedDrawableVariations(ped, i)
                local drawable_items = {}
                for x = 0, max_drawables - 1 do
                    drawable_items[#drawable_items + 1] = ('Drawable #%d (of %d)'):format(x, max_drawables)
                end

                local max_textures = GetNumberOfPedTextureVariations(ped, i, current_variation_index)
                local list_item = Items.MenuListItem.new(
                    clothing_category_names[i + 1],
                    drawable_items,
                    current_variation_index,
                    ('%s Currently selected texture: #%d (of %d).'):format(
                        clothes_description,
                        current_variation_texture_index + 1,
                        max_textures
                    )
                )
                clothes_menu:AddMenuItem(list_item)
            end
        end

        -- props ---------------------------------------------------------------
        local prop_names = { 'Hats & Helmets', 'Glasses', 'Misc Props', 'Watches', 'Bracelets' }
        for x = 0, 4 do
            local prop_id = x > 2 and x + 3 or x
            local saved_prop = edit_ped and current_character.PropVariations.props[tostring(prop_id)] or nil
            local current_prop = saved_prop ~= nil and saved_prop.Key or GetPedPropIndex(ped, prop_id)
            local current_prop_texture = saved_prop ~= nil and saved_prop.Value or GetPedPropTextureIndex(ped, prop_id)

            local props_list = {}
            local max_props = GetNumberOfPedPropDrawableVariations(ped, prop_id)
            for i = 0, max_props - 1 do
                props_list[#props_list + 1] = ('Prop #%d (of %d)'):format(i, max_props)
            end
            props_list[#props_list + 1] = 'No Prop'

            local description = props_description
            if GetPedPropIndex(ped, prop_id) ~= -1 then
                local max_prop_textures = GetNumberOfPedPropTextureVariations(ped, prop_id, current_prop)
                description = ('%s Currently selected texture: #%d (of %d).'):format(
                    props_description,
                    current_prop_texture + 1,
                    max_prop_textures
                )
            end
            local prop_list_item = Items.MenuListItem.new(prop_names[x + 1], props_list, current_prop, description)
            props_menu:AddMenuItem(prop_list_item)
        end

        -- face features --------------------------------------------------------
        for _, item in ipairs(face_shape_menu:GetMenuItems()) do
            local item_index = item:Index()
            if edit_ped then
                current_character.FaceShapeFeatures = current_character.FaceShapeFeatures or {}
                if current_character.FaceShapeFeatures.features == nil then
                    current_character.FaceShapeFeatures.features = {}
                else
                    local saved = current_character.FaceShapeFeatures.features[tostring(item_index)]
                        or current_character.FaceShapeFeatures.features[item_index]
                    if saved ~= nil then
                        item.Position = math.floor(saved * 10) + 10
                        SetPedFaceFeature(ped, item_index, saved)
                    else
                        item.Position = 10
                        SetPedFaceFeature(ped, item_index, 0.0)
                    end
                end
            else
                item.Position = 10
                SetPedFaceFeature(ped, item_index, 0.0)
            end
        end

        -- tattoos ----------------------------------------------------------------
        Tattoos.generate()
        local collection = male and Tattoos.male or Tattoos.female
        local function tattoo_list(zone_key, label)
            local list = {}
            for i = 1, #collection[zone_key] do
                list[#list + 1] = ('%s #%d (of %d)'):format(label, i, #collection[zone_key])
            end
            return list
        end

        local tat_desc = 'Cycle through to preview tattoos, press enter to toggle specific tattoo.'
        local hair_tatts = Items.MenuListItem.new('Hair Tattoos', tattoo_list('HAIR', 'Tattoo'), 0, tat_desc)
        local head_tatts = Items.MenuListItem.new('Head Tattoos', tattoo_list('HEAD', 'Tattoo'), 0, tat_desc)
        local torso_tatts = Items.MenuListItem.new('Torso Tattoos', tattoo_list('TORSO', 'Tattoo'), 0, tat_desc)
        local left_arm_tatts =
            Items.MenuListItem.new('Left Arm Tattoos', tattoo_list('LEFT_ARM', 'Tattoo'), 0, tat_desc)
        local right_arm_tatts =
            Items.MenuListItem.new('Right Arm Tattoos', tattoo_list('RIGHT_ARM', 'Tattoo'), 0, tat_desc)
        local left_leg_tatts =
            Items.MenuListItem.new('Left Leg Tattoos', tattoo_list('LEFT_LEG', 'Tattoo'), 0, tat_desc)
        local right_leg_tatts =
            Items.MenuListItem.new('Right Leg Tattoos', tattoo_list('RIGHT_LEG', 'Tattoo'), 0, tat_desc)
        local badge_tatts = Items.MenuListItem.new(
            'Badge Overlays',
            tattoo_list('BADGES', 'Badge'),
            0,
            'Cycle through to preview badges, press enter to toggle specific badge. NOTE: Badges require a shirt or '
                .. 'they will not appear!'
        )
        local addon_tatts = Items.MenuListItem.new('Addon Tattoos', tattoo_list('ADDONS', 'Addon Tattoo'), 0, tat_desc)

        tattoos_menu:AddMenuItem(hair_tatts)
        tattoos_menu:AddMenuItem(head_tatts)
        tattoos_menu:AddMenuItem(torso_tatts)
        tattoos_menu:AddMenuItem(left_arm_tatts)
        tattoos_menu:AddMenuItem(right_arm_tatts)
        tattoos_menu:AddMenuItem(left_leg_tatts)
        tattoos_menu:AddMenuItem(right_leg_tatts)
        tattoos_menu:AddMenuItem(badge_tatts)
        if #collection.ADDONS > 0 then
            tattoos_menu:AddMenuItem(addon_tatts)
        end
        tattoos_menu:AddMenuItem(
            Items.MenuItem.new(
                'Remove All Tattoos & Badges',
                'Click this if you want to remove all tattoos and start over.'
            )
        )

        -- category ----------------------------------------------------------------
        local category_names = get_all_category_names()
        table.remove(category_names, 1) -- drop "Create New"
        local category_icons = get_category_icons(category_names)

        category_btn.ItemData = { names = category_names, icons = category_icons }
        category_btn.ListItems = category_names

        if edit_ped then
            local character_category_index = 0
            for i, name in ipairs(category_names) do
                if name == current_character.Category then
                    character_category_index = i - 1
                    break
                end
            end
            category_btn.ListIndex = character_category_index
        else
            category_btn.ListIndex = 0
        end
        category_btn.RightIcon = category_icons[category_btn.ListIndex + 1]

        create_character_menu:RefreshIndex()
        appearance_menu:RefreshIndex()
        inheritance_menu:RefreshIndex()
        tattoos_menu:RefreshIndex()
    end
    self.make_create_character_menu = make_create_character_menu

    -- -----------------------------------------------------------------------
    -- Create character menu handlers
    -- -----------------------------------------------------------------------

    create_character_menu.OnListIndexChange = function(_, item, _old_index, new_index, _item_index)
        if item == face_expression_list then
            current_character.FacialExpression = FACIAL_EXPRESSIONS[new_index + 1]
            SetFacialIdleAnimOverride(PlayerPedId(), current_character.FacialExpression, nil)
        elseif
            item == category_btn
            and type(category_btn.ItemData) == 'table'
            and category_btn.ItemData.names ~= nil
        then
            current_character.Category = category_btn.ItemData.names[new_index + 1]
            category_btn.RightIcon = category_btn.ItemData.icons[new_index + 1]
        end
    end

    create_character_menu.OnItemSelect = function(_, item, _index)
        local ped = PlayerPedId()
        if item == randomize_button then
            parent_one = rand_next(#parent_names)
            parent_one_skin = rand_next(#skin_names)
            parent_two = rand_next(#parent_names)
            parent_two_skin = rand_next(#skin_names)
            skin_mix_value = math.random()
            shape_mix_value = math.random()

            set_head_blend()

            current_character.FaceShapeFeatures.features = current_character.FaceShapeFeatures.features or {}

            for i = 0, 19 do
                shape_face_values[i] = math.random(5, 14)
                SetPedFaceFeature(ped, i, FACE_FEATURE_VALUES[shape_face_values[i] + 1])
                current_character.FaceShapeFeatures.features[tostring(i)] =
                    FACE_FEATURE_VALUES[shape_face_values[i] + 1]
            end

            local body_hair = rand_next(31)

            change_player_hair(rand_next(GetNumberOfPedDrawableVariations(ped, 2)))
            change_player_hair_color(body_hair, rand_next(31))
            change_player_eye_color(rand_next(9))

            for i = 0, 11 do
                local value
                local color_index = 0
                local color_required = false
                local color = (i == 1 or i == 2 or i == 10) and body_hair or rand_next(17)
                local opacity = math.random()

                if i == 0 then
                    value = rand_next(#overlay_style_lists[0])
                    current_character.PedAppearance.blemishesStyle = value
                    current_character.PedAppearance.blemishesOpacity = opacity
                elseif i == 1 then
                    if not current_character.IsMale then
                        appearance_values[i] = { 0, 0, 0.0 }
                        goto continue
                    end
                    value = rand_next(#overlay_style_lists[1])
                    color_required = true
                    color_index = 1
                    current_character.PedAppearance.beardStyle = value
                    current_character.PedAppearance.beardColor = color
                    current_character.PedAppearance.beardOpacity = opacity
                elseif i == 2 then
                    value = rand_next(#overlay_style_lists[2])
                    color_required = true
                    color_index = 1
                    -- upstream swaps these two assignments; quirk preserved
                    current_character.PedAppearance.eyebrowsColor = value
                    current_character.PedAppearance.eyebrowsStyle = color
                    current_character.PedAppearance.eyebrowsOpacity = opacity
                elseif i == 3 then
                    value = rand_next(#overlay_style_lists[3])
                    current_character.PedAppearance.ageingStyle = value
                    current_character.PedAppearance.ageingOpacity = opacity
                elseif i == 8 then
                    if current_character.IsMale then
                        appearance_values[i] = { 0, 0, 0.0 }
                        goto continue
                    end
                    value = rand_next(6)
                    color_required = true
                    color_index = 2
                    current_character.PedAppearance.lipstickStyle = value
                    current_character.PedAppearance.lipstickColor = color
                    current_character.PedAppearance.lipstickOpacity = opacity
                elseif i == 9 then
                    value = rand_next(#overlay_style_lists[9])
                    current_character.PedAppearance.molesFrecklesStyle = value
                    current_character.PedAppearance.molesFrecklesOpacity = opacity
                elseif i == 10 then
                    if not current_character.IsMale then
                        appearance_values[i] = { 0, 0, 0.0 }
                        goto continue
                    end
                    value = rand_next(8)
                    color_required = true
                    color_index = 1
                    current_character.PedAppearance.chestHairStyle = value
                    current_character.PedAppearance.chestHairColor = color
                    current_character.PedAppearance.chestHairOpacity = opacity
                elseif i == 11 then
                    value = rand_next(#overlay_style_lists[11])
                    current_character.PedAppearance.bodyBlemishesStyle = value
                    current_character.PedAppearance.bodyBlemishesOpacity = opacity
                else
                    appearance_values[i] = { 0, 0, 0.0 }
                    goto continue
                end

                appearance_values[i] = { value, color, opacity }
                SetPedHeadOverlay(ped, i, appearance_values[i][1], appearance_values[i][3])
                if color_required then
                    SetPedHeadOverlayColor(ped, i, color_index, appearance_values[i][2], appearance_values[i][2])
                end

                ::continue::
            end

            facial_expression_selection = rand_next(#FACIAL_EXPRESSIONS)
            SetFacialIdleAnimOverride(ped, FACIAL_EXPRESSIONS[facial_expression_selection + 1], nil)
            current_character.FacialExpression = FACIAL_EXPRESSIONS[facial_expression_selection + 1]
            face_expression_list.ListIndex = facial_expression_selection

            set_player_clothing()
        elseif item == save_button then
            if save_current_character() then
                while not Controller.IsAnyMenuOpen() do
                    Wait(0)
                end
                while
                    IsControlPressed(2, 201)
                    or IsControlPressed(2, 217)
                    or IsDisabledControlPressed(2, 201)
                    or IsDisabledControlPressed(2, 217)
                do
                    Wait(0)
                end
                Wait(100)
                create_character_menu:GoBack()
            end
        elseif item == exit_no_save then
            local confirm = false
            AddTextEntry('vmenu_warning_message_first_line', 'Are you sure you want to exit the character creator?')
            AddTextEntry('vmenu_warning_message_second_line', 'You will lose all (unsaved) customization!')
            create_character_menu:CloseMenu()

            while true do
                Wait(0)
                SetWarningMessage(
                    'vmenu_warning_message_first_line',
                    20,
                    'vmenu_warning_message_second_line',
                    true,
                    0,
                    1,
                    1,
                    true,
                    0
                )
                if IsControlJustPressed(2, 201) or IsControlJustPressed(2, 217) then -- continue/accept
                    confirm = true
                    break
                elseif IsControlJustPressed(2, 202) then -- cancel
                    break
                end
            end

            if confirm then
                while
                    IsControlPressed(2, 201)
                    or IsControlPressed(2, 217)
                    or IsDisabledControlPressed(2, 201)
                    or IsDisabledControlPressed(2, 217)
                do
                    Wait(0)
                end
                Wait(100)
                menu:OpenMenu()
            else
                create_character_menu:OpenMenu()
            end
        elseif item == inheritance_button then
            -- refresh so old data is never shown
            inheritance_parent_one.ListIndex = parent_one
            inheritance_parent_one_skin.ListIndex = parent_one_skin
            inheritance_parent_two.ListIndex = parent_two
            inheritance_parent_two_skin.ListIndex = parent_two_skin
            inheritance_shape_mix.Position = math.floor(shape_mix_value * 10)
            inheritance_skin_mix.Position = math.floor(skin_mix_value * 10)
            inheritance_menu:RefreshIndex()
        elseif item == face_button then
            -- C# throws (and aborts) when shape_face_values is empty; the
            -- dict is only ever empty or fully populated by randomize
            if shape_face_values[0] ~= nil then
                local items = face_shape_menu:GetMenuItems()
                for i = 0, 19 do
                    items[i + 1].Position = shape_face_values[i]
                end
                face_shape_menu:RefreshIndex()
            end
        elseif item == appearance_button then
            local by_text = {}
            for _, list_item in ipairs(appearance_menu:GetMenuItems()) do
                if list_item.ListItems ~= nil then
                    by_text[list_item.Text] = list_item
                end
            end
            local function set_index(text, index)
                if by_text[text] ~= nil then
                    by_text[text].ListIndex = index
                end
            end

            set_index('Hair Style', hair_selection)
            set_index('Hair Color', hair_color_selection)
            set_index('Hair Highlight Color', hair_highlight_color_selection)
            local names = {
                'Blemishes',
                'Beard',
                'Eyebrows',
                'Ageing',
                'Makeup',
                'Blush',
                'Complexion',
                'Sun Damage',
                'Lipstick',
                'Moles and Freckles',
                'Chest Hair',
                'Body Blemishes',
            }
            local has_color =
                { Beard = true, Eyebrows = true, Makeup = true, Blush = true, Lipstick = true, ['Chest Hair'] = true }
            for i, name in ipairs(names) do
                local values = appearance_values[i - 1] or { 0, 0, 0.0 }
                set_index(name .. ' Style', values[1])
                set_index(name .. ' Opacity', math.floor(values[3] * 10))
                if has_color[name] then
                    set_index(name .. ' Color', values[2])
                end
            end
            set_index('Eye Colors', eye_color_selection)

            appearance_menu:RefreshIndex()
            set_head_blend()
        end
    end

    -- -----------------------------------------------------------------------
    -- Main menu handlers (start the creator)
    -- -----------------------------------------------------------------------

    local function start_creator(male)
        local model = male and GetHashKey('mp_m_freemode_01') or GetHashKey('mp_f_freemode_01')
        if not HasModelLoaded(model) then
            RequestModel(model)
            while not HasModelLoaded(model) do
                Wait(0)
            end
        end

        local ped = PlayerPedId()
        local max_health = GetPedMaxHealth(ped)
        local max_armour = GetPlayerMaxArmour(PlayerId())
        local health = GetEntityHealth(ped)
        local armour = GetPedArmour(ped)

        Weapons.save_weapon_loadout(TEMP_LOADOUT_NAME)
        SetPlayerModel(PlayerId(), model)
        Weapons.spawn_weapon_loadout(TEMP_LOADOUT_NAME, false, true, true)

        ped = PlayerPedId()
        SetPlayerMaxArmour(PlayerId(), max_armour)
        SetPedMaxHealth(ped, max_health)
        SetEntityHealth(ped, health)
        SetPedArmour(ped, armour)

        ClearPedDecorations(ped)
        ClearPedFacialDecorations(ped)
        SetPedDefaultComponentVariation(ped)
        ClearAllPedProps(ped)
        default_player_colors()

        make_create_character_menu(male, false)
    end

    local update_saved_peds_menu -- forward declaration

    menu.OnItemSelect = function(_, item, _index)
        if item == create_male_btn then
            start_creator(true)
        elseif item == create_female_btn then
            start_creator(false)
        elseif item == saved_characters_btn then
            update_saved_peds_menu()
        end
    end

    -- -----------------------------------------------------------------------
    -- Saved characters (categories + manage menu)
    -- -----------------------------------------------------------------------

    Controller.AddMenu(manage_saved_character_menu)

    local spawn_ped_btn = Items.MenuItem.new('Spawn Saved Character', 'Spawns the selected saved character.')
    local clone_ped_btn = Items.MenuItem.new(
        'Clone Saved Character',
        'This will make a clone of your saved character. It will ask you to provide a name for that character. If '
            .. 'that name is already taken the action will be canceled.'
    )
    local set_as_default_ped = Items.MenuItem.new(
        'Set As Default Character',
        "If you set this character as your default character, and you enable the 'Respawn As Default MP Character' "
            .. 'option in the Misc Settings menu, then you will be set as this character whenever you (re)spawn.'
    )
    local rename_character_btn = Items.MenuItem.new(
        'Rename Saved Character',
        'You can rename this saved character. If the name is already taken then the action will be canceled.'
    )
    local save_current_ped_as_character = Items.MenuItem.new(
        'Update Character Clothing',
        "This applies your current clothing to this saved ped. ~r~This will overwrite this saved ped's clothing.~w~ "
            .. 'Only clothing is updated, no other appearance features.'
    )
    save_current_ped_as_character.LeftIcon = Items.Icon.WARNING
    local del_ped_btn =
        Items.MenuItem.new('Delete Saved Character', 'Deletes the selected saved character. This can not be undone!')
    del_ped_btn.LeftIcon = Items.Icon.WARNING

    manage_saved_character_menu:AddMenuItem(spawn_ped_btn)
    manage_saved_character_menu:AddMenuItem(edit_ped_btn)
    manage_saved_character_menu:AddMenuItem(clone_ped_btn)
    manage_saved_character_menu:AddMenuItem(set_category_btn)
    manage_saved_character_menu:AddMenuItem(set_as_default_ped)
    manage_saved_character_menu:AddMenuItem(rename_character_btn)
    manage_saved_character_menu:AddMenuItem(save_current_ped_as_character)
    manage_saved_character_menu:AddMenuItem(del_ped_btn)

    Controller.BindMenuItem(manage_saved_character_menu, create_character_menu, edit_ped_btn)

    -- ReplacePedDataClothing: update the record with the live ped's clothes.
    local function replace_ped_data_clothing(character)
        local ped = PlayerPedId()
        character.DrawableVariations.clothes = character.DrawableVariations.clothes or {}
        character.PropVariations.props = character.PropVariations.props or {}
        for i = 0, 11 do
            character.DrawableVariations.clothes[tostring(i)] =
                MpPedData.kvp(GetPedDrawableVariation(ped, i), GetPedTextureVariation(ped, i))
        end
        for i = 0, 7 do
            character.PropVariations.props[tostring(i)] =
                MpPedData.kvp(GetPedPropIndex(ped, i), GetPedPropTextureIndex(ped, i))
        end
        return character
    end

    manage_saved_character_menu.OnItemSelect = function(_, item, _index)
        if item == edit_ped_btn then
            current_character = Storage.get_saved_mp_character_data(selected_saved_character_manage_name)
            spawn_saved_ped(true)
            make_create_character_menu(current_character.IsMale == true, true)
        elseif item == spawn_ped_btn then
            current_character = Storage.get_saved_mp_character_data(selected_saved_character_manage_name)
            spawn_saved_ped(true)
        elseif item == clone_ped_btn then
            local tmp_character = Storage.get_saved_mp_character_data('mp_ped_' .. selected_saved_character_manage_name)
            local name = Common.get_user_input(
                'Enter a name for the cloned character',
                tostring(tmp_character.SaveName or ''):sub(8),
                30
            )
            if name == nil or name == '' then
                Notify.error(Notification.error_message('InvalidSaveName'))
            else
                local existing = GetResourceKvpString('mp_ped_' .. name)
                if existing ~= nil and existing ~= '' then
                    Notify.error(Notification.error_message('SaveNameAlreadyExists'))
                else
                    tmp_character.SaveName = 'mp_ped_' .. name
                    if Storage.save_json_data('mp_ped_' .. name, Json.encode(tmp_character), false) then
                        Notify.success(
                            (
                                'Your character has been cloned. The name of the cloned character is: '
                                .. '~g~<C>%s</C>~s~.'
                            ):format(name)
                        )
                        Controller.CloseAllMenus()
                        update_saved_peds_menu()
                        saved_characters_menu:OpenMenu()
                    else
                        Notify.error(
                            'The clone could not be created, reason unknown. Does a character already exist with '
                                .. 'that name? :('
                        )
                    end
                end
            end
        elseif item == rename_character_btn then
            local tmp_character = Storage.get_saved_mp_character_data('mp_ped_' .. selected_saved_character_manage_name)
            local name =
                Common.get_user_input('Enter a new character name', tostring(tmp_character.SaveName or ''):sub(8), 30)
            if name == nil or name == '' then
                Notify.error(Notification.error_message('InvalidInput'))
            else
                local existing = GetResourceKvpString('mp_ped_' .. name)
                if existing ~= nil and existing ~= '' then
                    Notify.error(Notification.error_message('SaveNameAlreadyExists'))
                else
                    tmp_character.SaveName = 'mp_ped_' .. name
                    if Storage.save_json_data('mp_ped_' .. name, Json.encode(tmp_character), false) then
                        Storage.delete_saved_storage_item('mp_ped_' .. selected_saved_character_manage_name)
                        Notify.success(('Your character has been renamed to ~g~<C>%s</C>~s~.'):format(name))
                        update_saved_peds_menu()
                        while not Controller.IsAnyMenuOpen() do
                            Wait(0)
                        end
                        manage_saved_character_menu:GoBack()
                    else
                        Notify.error(
                            'Something went wrong while renaming your character, your old character will NOT be '
                                .. 'deleted because of this.'
                        )
                    end
                end
            end
        elseif item == save_current_ped_as_character then
            if save_current_ped_as_character.Label == 'Are you sure?' then
                save_current_ped_as_character.Label = ''
                local tmp_character =
                    Storage.get_saved_mp_character_data('mp_ped_' .. selected_saved_character_manage_name)
                tmp_character = replace_ped_data_clothing(tmp_character)
                if Storage.save_json_data(tmp_character.SaveName, Json.encode(tmp_character), true) then
                    Notify.success("This character's clothing has been updated!")
                    update_saved_peds_menu()
                else
                    Notify.error("Unable to update this character's clothing. The reason is unknown.")
                end
            else
                save_current_ped_as_character.Label = 'Are you sure?'
            end
        elseif item == del_ped_btn then
            if del_ped_btn.Label == 'Are you sure?' then
                del_ped_btn.Label = ''
                DeleteResourceKvp('mp_ped_' .. selected_saved_character_manage_name)
                Notify.success('Your saved character has been deleted.')
                manage_saved_character_menu:GoBack()
                update_saved_peds_menu()
                manage_saved_character_menu:RefreshIndex()
            else
                del_ped_btn.Label = 'Are you sure?'
            end
        elseif item == set_as_default_ped then
            Notify.success(
                ('Your character <C>%s</C> will now be used as your default character whenever you (re)spawn.'):format(
                    selected_saved_character_manage_name
                )
            )
            SetResourceKvp('vmenu_default_character', 'mp_ped_' .. selected_saved_character_manage_name)
        end

        if item ~= del_ped_btn and del_ped_btn.Label == 'Are you sure?' then
            del_ped_btn.Label = ''
        end
        if item ~= save_current_ped_as_character and save_current_ped_as_character.Label == 'Are you sure?' then
            save_current_ped_as_character.Label = ''
        end
    end

    -- category preview icon while browsing the list
    manage_saved_character_menu.OnListIndexChange = function(_, list_item, _old_index, new_index, _item_index)
        if list_item == set_category_btn and type(list_item.ItemData) == 'table' then
            list_item.RightIcon = list_item.ItemData[new_index + 1]
        end
    end

    -- category creation helper shared by two entry points
    local function create_new_category()
        local new_name = Common.get_user_input('Enter a category name.', nil, 30)
        if
            new_name == nil
            or new_name == ''
            or new_name:lower() == 'uncategorized'
            or new_name:lower() == 'create new'
        then
            Notify.error(Notification.error_message('InvalidInput'))
            return nil
        end
        local description = Common.get_user_input('Enter a category description (optional).', nil, 120)
        local new_category = { Name = new_name, Description = description or '', Icon = 0 }
        if Storage.save_json_data('mp_character_category_' .. new_name, Json.encode(new_category), false) then
            Notify.success(('Your category (~g~<C>%s</C>~s~) has been saved.'):format(new_name))
            Controller.CloseAllMenus()
            update_saved_peds_menu()
            saved_characters_category_menu:OpenMenu()
            current_category = new_category
            return new_category
        end
        Notify.error(
            ('Saving failed, most likely because this name (~y~<C>%s</C>~s~) is already in use.'):format(new_name)
        )
        return nil
    end

    -- setCategoryBtn: assign this character's category (select to save)
    manage_saved_character_menu.OnListItemSelect = function(_, list_item, list_index, _item_index)
        if list_item ~= set_category_btn then
            return
        end
        local tmp_character = Storage.get_saved_mp_character_data('mp_ped_' .. selected_saved_character_manage_name)
        local name = list_item.ListItems[list_index + 1]

        if name == 'Create New' then
            local new_category = create_new_category()
            if new_category == nil then
                return
            end
            name = new_category.Name
        end

        tmp_character.Category = name

        if Storage.save_json_data(tmp_character.SaveName, Json.encode(tmp_character), true) then
            Notify.success('Your character was saved successfully.')
        else
            Notify.error('Your character could not be saved. Reason unknown. :(')
        end

        Controller.CloseAllMenus()
        update_saved_peds_menu()
        saved_characters_menu:OpenMenu()
    end

    manage_saved_character_menu.OnMenuClose = function(_)
        for _, item in ipairs(manage_saved_character_menu:GetMenuItems()) do
            if item.Label == 'Are you sure?' then
                item.Label = ''
            end
        end
    end

    -- Load selected category (or create a new one)
    saved_characters_menu.OnItemSelect = function(_, item, _index)
        if type(item.ItemData) ~= 'table' or item.ItemData.Name == nil then
            if create_new_category() == nil then
                return
            end
        else
            current_category = item.ItemData
        end

        local is_uncategorized = current_category.Name == 'Uncategorized'

        saved_characters_category_menu.MenuTitle = current_category.Name
        saved_characters_category_menu.MenuSubtitle = ('~s~Category: ~y~%s'):format(current_category.Name)
        saved_characters_category_menu:ClearMenuItems()

        local function icon_change_callback(dynamic_item, going_left)
            local current_index = 0
            for i, name in ipairs(ICON_NAMES) do
                if name == dynamic_item.CurrentItem then
                    current_index = i - 1
                    break
                end
            end
            local new_index = going_left and current_index - 1 or current_index + 1
            if ICON_NAMES[new_index + 1] == nil then
                new_index = going_left and #ICON_NAMES - 1 or 0
            end
            dynamic_item.RightIcon = new_index
            return ICON_NAMES[new_index + 1]
        end

        local rename_btn = Items.MenuItem.new('Rename Category', 'Rename this category.')
        rename_btn.Enabled = not is_uncategorized
        local description_btn = Items.MenuItem.new('Change Category Description', "Change this category's description.")
        description_btn.Enabled = not is_uncategorized
        local icon_btn = Items.MenuDynamicListItem.new(
            'Change Category Icon',
            ICON_NAMES[(current_category.Icon or 0) + 1],
            icon_change_callback,
            "Change this category's icon. Select to save."
        )
        icon_btn.Enabled = not is_uncategorized
        icon_btn.RightIcon = current_category.Icon or 0
        local delete_btn = Items.MenuItem.new('Delete Category', 'Delete this category. This can not be undone!')
        delete_btn.RightIcon = Items.Icon.WARNING
        delete_btn.Enabled = not is_uncategorized
        local delete_chars_btn = Items.MenuCheckboxItem.new(
            'Delete All Characters',
            'If checked, when "Delete Category" is pressed, all the saved characters in this category will be '
                .. 'deleted as well. If not checked, saved characters will be moved to "Uncategorized".',
            false
        )
        delete_chars_btn.Enabled = not is_uncategorized

        saved_characters_category_menu:AddMenuItem(rename_btn)
        saved_characters_category_menu:AddMenuItem(description_btn)
        saved_characters_category_menu:AddMenuItem(icon_btn)
        saved_characters_category_menu:AddMenuItem(delete_btn)
        saved_characters_category_menu:AddMenuItem(delete_chars_btn)
        saved_characters_category_menu:AddMenuItem(Common.get_spacer_menu_item('↓ Characters ↓'))

        local names = get_all_mp_character_names()
        if #names > 0 then
            local default_char = GetResourceKvpString('vmenu_default_character') or ''
            table.sort(names, function(a, b)
                return a:lower() < b:lower()
            end)
            for _, name in ipairs(names) do
                local tmp_data = Storage.get_saved_mp_character_data('mp_ped_' .. name)
                local skip
                if tmp_data.Category == nil or tmp_data.Category == '' then
                    skip = not is_uncategorized
                else
                    skip = tmp_data.Category ~= current_category.Name
                end
                if not skip then
                    local btn =
                        Items.MenuItem.new(name, 'Click to spawn, edit, clone, rename or delete this saved character.')
                    btn.Label = '→→→'
                    btn.LeftIcon = tmp_data.IsMale and Items.Icon.MALE or Items.Icon.FEMALE
                    btn.ItemData = tmp_data.IsMale == true
                    if default_char == 'mp_ped_' .. name then
                        btn.LeftIcon = Items.Icon.TICK
                        btn.Description = btn.Description
                            .. ' ~g~This character is currently set as your default character and will be used '
                            .. 'whenever you (re)spawn.'
                    end
                    saved_characters_category_menu:AddMenuItem(btn)
                    Controller.BindMenuItem(saved_characters_category_menu, manage_saved_character_menu, btn)
                end
            end
        end
    end

    -- MP ped preview clone while browsing characters.
    local function delete_clone()
        if clone ~= 0 and DoesEntityExist(clone) then
            SetEntityAsMissionEntity(clone, false, true)
            DeleteEntity(clone)
        end
        clone = 0
    end

    -- Park a preview ped in front of the gameplay camera (screen ~0.6/0.8).
    local function place_clone_at_camera(handle)
        local world_coord, normal = GetWorldCoordFromScreenCoord(0.6, 0.8)
        local camera_rotation = GetGameplayCamRot(2)
        SetEntityCoords(
            handle,
            world_coord.x + (normal.x * 3.5),
            world_coord.y + (normal.y * 3.5),
            world_coord.z + (normal.z * 3.5),
            false,
            false,
            false,
            true
        )
        SetEntityRotation(handle, camera_rotation.x * -1, 0.0, camera_rotation.z + 180, 2, true)
        SetEntityHeading(handle, camera_rotation.z + 180)
    end

    saved_characters_category_menu.OnIndexChange = function(_, _old_item, new_item, _old_index, _new_index)
        local misc = State.menus.misc_settings
        if not Config.get_bool('vmenu_mp_ped_preview') or misc == nil or not misc.MPPedPreviews then
            return
        end

        -- only ped items carry a boolean ItemData
        if type(new_item.ItemData) ~= 'boolean' then
            delete_clone()
            return
        end

        local character = Storage.get_saved_mp_character_data(new_item.Text)
        -- Keep the current preview ped on screen while the next model streams
        -- in -- otherwise the camera preview blanks out on every switch.
        if not HasModelLoaded(character.ModelHash) then
            RequestModel(character.ModelHash)
            while not HasModelLoaded(character.ModelHash) do
                Wait(0)
            end
        end

        -- Credit to whbl for the inspiration for this feature.
        local player_ped = PlayerPedId()
        local position = GetEntityCoords(player_ped)
        local new_clone = CreatePed(
            26,
            character.ModelHash,
            position.x,
            position.y,
            position.z - 3.0,
            GetEntityHeading(player_ped),
            false,
            false
        )
        SetEntityCollision(new_clone, false, false)
        SetEntityInvincible(new_clone, true)
        SetBlockingOfNonTemporaryEvents(new_clone, true)
        FreezeEntityPosition(new_clone, true)
        -- Build the new ped hidden and off-camera: applying appearance takes a
        -- few frames (head-blend wait), and the old preview stays visible
        -- meanwhile so there's no blank frame.
        SetEntityVisible(new_clone, false, false)
        apply_saved_data_to_ped(character, new_clone)

        SetEntityCanBeDamaged(new_clone, false)
        SetPedAoBlobRendering(new_clone, false)

        -- New ped is ready: place it in front of the camera, reveal it, then
        -- drop the old one in the same frame -- a clean swap, no flicker.
        place_clone_at_camera(new_clone)
        SetEntityVisible(new_clone, true, false)
        delete_clone()
        clone = new_clone

        CreateThread(function()
            while clone == new_clone and DoesEntityExist(new_clone) do
                place_clone_at_camera(new_clone)
                ClampGameplayCamPitch(0.0, 0.0)
                Wait(0)
            end
        end)
    end

    saved_characters_category_menu.OnItemSelect = function(sender, item, index)
        if index == 0 then -- rename category
            local name = Common.get_user_input('Enter a new category name', current_category.Name, 30)
            if name == nil or name == '' or name:lower() == 'uncategorized' or name:lower() == 'create new' then
                Notify.error(Notification.error_message('InvalidInput'))
                return
            end
            local existing_record = GetResourceKvpString('mp_character_category_' .. name)
            local name_taken = existing_record ~= nil and existing_record ~= ''
            if not name_taken then
                for _, existing in ipairs(get_all_category_names()) do
                    if existing == name then
                        name_taken = true
                        break
                    end
                end
            end
            if name_taken then
                Notify.error(Notification.error_message('SaveNameAlreadyExists'))
                return
            end

            local old_name = current_category.Name
            current_category.Name = name

            if Storage.save_json_data('mp_character_category_' .. name, Json.encode(current_category), false) then
                Storage.delete_saved_storage_item('mp_character_category_' .. old_name)

                local total_count, updated_count = 0, 0
                for _, character_name in ipairs(get_all_mp_character_names()) do
                    local tmp_data = Storage.get_saved_mp_character_data('mp_ped_' .. character_name)
                    if tmp_data.Category ~= nil and tmp_data.Category ~= '' and tmp_data.Category == old_name then
                        total_count = total_count + 1
                        tmp_data.Category = name
                        if Storage.save_json_data(tmp_data.SaveName, Json.encode(tmp_data), true) then
                            updated_count = updated_count + 1
                        end
                    end
                end

                Notify.success(
                    ('Your category has been renamed to ~g~<C>%s</C>~s~. %d/%d characters updated.'):format(
                        name,
                        updated_count,
                        total_count
                    )
                )
                Controller.CloseAllMenus()
                update_saved_peds_menu()
                saved_characters_menu:OpenMenu()
            else
                Notify.error(
                    'Something went wrong while renaming your category, your old category will NOT be deleted '
                        .. 'because of this.'
                )
            end
        elseif index == 1 then -- change category description
            local description =
                Common.get_user_input('Enter a new category description', current_category.Description, 120)
            current_category.Description = description
            if
                Storage.save_json_data(
                    'mp_character_category_' .. current_category.Name,
                    Json.encode(current_category),
                    true
                )
            then
                Notify.success('Your category description has been changed.')
                Controller.CloseAllMenus()
                update_saved_peds_menu()
                saved_characters_menu:OpenMenu()
            else
                Notify.error('Something went wrong while changing your category description.')
            end
        elseif index == 3 then -- delete category
            if item.Label == 'Are you sure?' then
                local checkbox = sender:GetMenuItems()[5]
                local delete_peds = checkbox ~= nil and checkbox.Checked == true

                item.Label = ''
                DeleteResourceKvp('mp_character_category_' .. current_category.Name)

                local total_count, updated_count = 0, 0
                for _, character_name in ipairs(get_all_mp_character_names()) do
                    local tmp_data = Storage.get_saved_mp_character_data('mp_ped_' .. character_name)
                    if
                        tmp_data.Category ~= nil
                        and tmp_data.Category ~= ''
                        and tmp_data.Category == current_category.Name
                    then
                        total_count = total_count + 1
                        if delete_peds then
                            updated_count = updated_count + 1
                            -- upstream double-prefixes here; quirk preserved
                            DeleteResourceKvp('mp_ped_' .. tostring(tmp_data.SaveName))
                        else
                            tmp_data.Category = 'Uncategorized'
                            if Storage.save_json_data(tmp_data.SaveName, Json.encode(tmp_data), true) then
                                updated_count = updated_count + 1
                            end
                        end
                    end
                end

                Notify.success(
                    ('Your saved category has been deleted. %d/%d characters %s.'):format(
                        updated_count,
                        total_count,
                        delete_peds and 'deleted' or 'updated'
                    )
                )
                Controller.CloseAllMenus()
                update_saved_peds_menu()
                saved_characters_menu:OpenMenu()
            else
                item.Label = 'Are you sure?'
            end
        else -- load saved character manage menu
            local category_names = get_all_category_names()
            local category_icons = get_category_icons(category_names)
            local name_index = 0
            for i, category_name in ipairs(category_names) do
                if category_name == current_category.Name then
                    name_index = i - 1
                    break
                end
            end

            set_category_btn.ItemData = category_icons
            set_category_btn.ListItems = category_names
            set_category_btn.ListIndex = name_index == 1 and 0 or name_index
            set_category_btn.RightIcon = category_icons[set_category_btn.ListIndex + 1]
            selected_saved_character_manage_name = item.Text
            manage_saved_character_menu.MenuSubtitle = item.Text
            manage_saved_character_menu.CounterPreText = (item.LeftIcon == Items.Icon.MALE and '(Male) ' or '(Female) ')
            manage_saved_character_menu:RefreshIndex()
        end
    end

    -- change category icon (select on the dynamic list saves it)
    saved_characters_category_menu.OnDynamicListItemSelect = function(_, _item, current_item)
        local icon_index = 0
        for i, name in ipairs(ICON_NAMES) do
            if name == current_item then
                icon_index = i - 1
                break
            end
        end
        current_category.Icon = icon_index
        if
            Storage.save_json_data(
                'mp_character_category_' .. current_category.Name,
                Json.encode(current_category),
                true
            )
        then
            Notify.success(('Your category icon been changed to ~g~<C>%s</C>~s~.'):format(ICON_NAMES[icon_index + 1]))
            update_saved_peds_menu()
        else
            Notify.error('Something went wrong while changing your category icon.')
        end
    end

    saved_characters_category_menu.OnMenuClose = function(_)
        delete_clone()
    end

    -- UpdateSavedPedsMenu: rebuilds the category listing.
    update_saved_peds_menu = function()
        local categories = get_all_category_names()

        saved_characters_menu:ClearMenuItems()

        local create_category_btn = Items.MenuItem.new('Create Category', 'Create a new character category.')
        create_category_btn.Label = '→→→'
        saved_characters_menu:AddMenuItem(create_category_btn)

        saved_characters_menu:AddMenuItem(Common.get_spacer_menu_item('↓ Character Categories ↓'))

        local uncategorized = {
            Name = 'Uncategorized',
            Description = 'All saved MP Characters that have not been assigned to a category.',
            Icon = 0,
        }
        local uncategorized_btn = Items.MenuItem.new(uncategorized.Name, uncategorized.Description)
        uncategorized_btn.Label = '→→→'
        uncategorized_btn.ItemData = uncategorized
        saved_characters_menu:AddMenuItem(uncategorized_btn)
        Controller.BindMenuItem(saved_characters_menu, saved_characters_category_menu, uncategorized_btn)

        -- drop "Create New" and "Uncategorized"
        table.remove(categories, 1)
        table.remove(categories, 1)

        if #categories > 0 then
            table.sort(categories, function(a, b)
                return a:lower() < b:lower()
            end)
            for _, name in ipairs(categories) do
                local category = Storage.get_saved_mp_character_category_data('mp_character_category_' .. name)
                category.Name = category.Name or name
                category.Icon = category.Icon or 0
                local btn = Items.MenuItem.new(category.Name, category.Description or '')
                btn.Label = '→→→'
                btn.LeftIcon = category.Icon
                btn.ItemData = category
                saved_characters_menu:AddMenuItem(btn)
                Controller.BindMenuItem(saved_characters_menu, saved_characters_category_menu, btn)
            end
        end

        saved_characters_menu:RefreshIndex()
    end
    self.update_saved_peds_menu = update_saved_peds_menu

    update_saved_peds_menu()

    self.menu = menu
    self.CreateCharacterMenu = create_character_menu
    self.SavedCharactersMenu = saved_characters_menu
    self.SavedCharactersCategoryMenu = saved_characters_category_menu
    self.InheritanceMenu = inheritance_menu
    self.AppearanceMenu = appearance_menu
    self.FaceShapeMenu = face_shape_menu
    self.TattoosMenu = tattoos_menu
    self.ClothesMenu = clothes_menu
    self.PropsMenu = props_menu
    self.ManageSavedCharacterMenu = manage_saved_character_menu
    self.CreateMaleBtn = create_male_btn
    self.CreateFemaleBtn = create_female_btn
    self.EditPedBtn = edit_ped_btn
    return self
end

return MpPedCustomization
