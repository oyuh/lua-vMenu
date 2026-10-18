-- Port of vMenu.Enhanced.Menus/TeleportMenu.cs. Categories and their
-- locations live on the server; staff with Manage add and remove them for
-- everybody through server actions.

local Localization = require('shared.localization')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')
local Notifications = require('client.framework.notifications')
local Input = require('client.framework.input')
local UserDefaults = require('client.user_defaults')
local Actions = require('client.actions')
local Teleport = require('client.menus.players.teleport')
local Locations = require('client.menus.teleport.locations')
local Targets = require('client.menus.teleport.targets')

local PERMISSION = 'vMenu.Enhanced.Menus.TeleportMenu.'
local MANAGE = PERMISSION .. 'Manage'
local TEXT_LENGTH = 50

local function report_saved(status)
    if status == Actions.OK then
        Notifications.success(Localization.key('teleportmenu.saved'))
        return
    end
    local key = 'teleportmenu.save.failed'
    if status == Actions.DENIED then
        key = 'teleportmenu.save.denied'
    elseif status == Actions.REFUSED then
        key = 'teleportmenu.save.nametaken'
    elseif status == Actions.NOT_FOUND then
        key = 'teleportmenu.save.categorygone'
    end
    Notifications.error(Localization.key(key))
end

local function report_deleted(status)
    if status == Actions.OK then
        Notifications.success(Localization.key('teleportmenu.deleted'))
        return
    end
    local key = 'teleportmenu.delete.failed'
    if status == Actions.DENIED then
        key = 'teleportmenu.delete.denied'
    elseif status == Actions.NOT_FOUND then
        key = 'teleportmenu.delete.gone'
    end
    Notifications.error(Localization.key(key))
end

local function ask_name_and_description(name_key, description_key)
    return Input.get_texts({
        { title = Localization.key(name_key), max_length = TEXT_LENGTH },
        { title = Localization.key(description_key), max_length = TEXT_LENGTH },
    })
end

-- Two decimals is all upstream keeps.
local function coord(value)
    local text = ('%.2f'):format(value):gsub('0+$', ''):gsub('%.$', '')
    return text
end

local function placeholder(text_key, description_key)
    return Entries.button({ text = Localization.key(text_key), description = Localization.key(description_key) })
end

-- A confirm list that deletes the picked one of items.
local function delete_row(items, text_key, description_key, confirm_key, delete)
    local names = {}
    for index, item in ipairs(items) do
        names[index] = item.name
    end
    local picked = 1
    return Entries.confirm_list({
        text = Localization.key(text_key),
        description = Localization.key(description_key),
        confirmation_description = Localization.key(confirm_key, {
            name = Localization.from(function()
                return names[picked] or ''
            end),
        }),
        options = names,
        gate = MANAGE,
        on_index_changed = function(args)
            picked = args.new_index + 1
        end,
        on_confirmed_async = function(args)
            local name = names[args.selected_index + 1]
            if name then
                delete(name)
            end
        end,
    })
end

-- Swaps a detached menu's rows, keeping the cursor where it was if asked.
local function fill(detached, rows, keep_index)
    local menu = detached.menu
    local was, offset = menu.CurrentIndex, menu.ViewIndexOffset
    detached.builder:clear_entries()
    detached.builder:add_range(rows)
    local keep = keep_index and was < #menu:GetMenuItems()
    menu:RefreshIndex(keep and was or 0, keep and offset or 0)
end

local function find_category(name)
    for _, category in ipairs(Locations.categories()) do
        if category.name:lower() == name:lower() then
            return category
        end
    end
    return nil
end

return Registry.definition({
    audit_name = 'TeleportMenu',
    title_key = 'teleportmenu.title',
    subtitle_key = 'teleportmenu.link.subtitle',
    description_key = 'teleportmenu.link.desc',
    permission = PERMISSION .. 'Menu',
    build = function(menu)
        local selected, built_for
        local category_menu, location_menu

        local function rebuild_locations(keep_index)
            local rows = {}
            for _, location in ipairs(selected and selected.locations or {}) do
                rows[#rows + 1] = Entries.button({
                    text = location.name,
                    description = location.description,
                    on_selected_async = function()
                        Teleport.to_coords(location.x, location.y, location.z, location.heading)
                    end,
                })
            end
            if #rows == 0 then
                rows[1] = placeholder('teleportmenu.categories.nolocations', 'teleportmenu.categories.nolocations.desc')
            end
            rows[#rows + 1] = Entries.button({
                text = Localization.key('teleportmenu.categories.position'),
                description = Localization.key('teleportmenu.categories.position.desc'),
                gate = MANAGE,
                on_selected_async = function()
                    local category = selected
                    if not category then
                        return
                    end
                    local answers = ask_name_and_description(
                        'teleportmenu.categories.add.position.name',
                        'teleportmenu.categories.add.position.desc'
                    )
                    if not answers then
                        return
                    end
                    local ped = PlayerPedId()
                    local position = GetEntityCoords(ped, false)
                    report_saved(
                        Actions.invoke(
                            'TeleportMenu.AddLocation',
                            category.name,
                            answers[1],
                            answers[2],
                            coord(position.x),
                            coord(position.y),
                            coord(position.z),
                            coord(GetEntityHeading(ped))
                        )
                    )
                end,
            })
            if selected and #selected.locations > 0 then
                local category = selected
                rows[#rows + 1] = delete_row(
                    category.locations,
                    'teleportmenu.categories.position.delete',
                    'teleportmenu.categories.position.delete.desc',
                    'teleportmenu.categories.position.delete.confirm',
                    function(name)
                        report_deleted(Actions.invoke('TeleportMenu.RemoveLocation', category.name, name))
                    end
                )
            end
            fill(location_menu, rows, keep_index)
        end

        local function rebuild_categories()
            local rows = {}
            for _, category in ipairs(Locations.categories()) do
                rows[#rows + 1] = Entries.button({
                    text = category.name,
                    description = category.description,
                    on_selected = function()
                        selected = category
                        location_menu.open()
                    end,
                })
            end
            if #rows == 0 then
                rows[1] = placeholder('teleportmenu.categories.none', 'teleportmenu.categories.none.desc')
            end
            rows[#rows + 1] = Entries.button({
                text = Localization.key('teleportmenu.categories.create'),
                description = Localization.key('teleportmenu.categories.create.desc'),
                gate = MANAGE,
                on_selected_async = function()
                    local answers = ask_name_and_description(
                        'teleportmenu.categories.add.category.name',
                        'teleportmenu.categories.add.category.desc'
                    )
                    if answers then
                        report_saved(Actions.invoke('TeleportMenu.AddCategory', answers[1], answers[2]))
                    end
                end,
            })
            if #Locations.categories() > 0 then
                rows[#rows + 1] = delete_row(
                    Locations.categories(),
                    'teleportmenu.categories.delete',
                    'teleportmenu.categories.delete.desc',
                    'teleportmenu.categories.delete.confirm',
                    function(name)
                        report_deleted(Actions.invoke('TeleportMenu.RemoveCategory', name))
                    end
                )
            end
            fill(category_menu, rows, true)
        end

        menu:add(Entries.button({
            text = Localization.key('teleportmenu.tptowp'),
            description = Localization.key('teleportmenu.tptowp.desc'),
            gate = PERMISSION .. 'Waypoint',
            on_selected_async = Targets.to_waypoint,
        }))
        menu:add(Entries.button({
            text = Localization.key('teleportmenu.tptocoords'),
            description = Localization.key('teleportmenu.tptocoords.desc'),
            gate = PERMISSION .. 'Coords',
            on_selected_async = Targets.to_typed_coords,
        }))

        location_menu = menu:add_detached_menu(
            Localization.from(function()
                return selected and selected.name or ''
            end),
            Localization.from(function()
                return selected and selected.description or ''
            end),
            function() end
        )
        location_menu.builder:on_opened(function()
            if built_for ~= selected then
                built_for = selected
                rebuild_locations(false)
            end
        end)
        category_menu = menu:add_detached_menu(
            Localization.key('teleportmenu.categories'),
            Localization.key('teleportmenu.categories'),
            function() end
        )
        Locations.on_changed(function()
            selected = selected and find_category(selected.name) or nil
            built_for = selected
            rebuild_categories()
            rebuild_locations(true)
        end)
        rebuild_categories()

        menu:add(Entries.button({
            text = Localization.key('teleportmenu.categories'),
            description = Localization.key('teleportmenu.categories.desc'),
            gate = PERMISSION .. 'Category',
            on_selected = function()
                category_menu.open()
            end,
        }))
        menu:add(Entries.list({
            text = Localization.key('teleportmenu.key.action'),
            description = Localization.key('teleportmenu.key.action.desc'),
            options = {
                Localization.key('teleportmenu.key.action.disabled'),
                Localization.key('teleportmenu.key.action.waypoint'),
                Localization.key('teleportmenu.key.action.coords'),
            },
            read_selected_index = function()
                return UserDefaults.get('teleportKeyAction')
            end,
            on_index_changed = function(args)
                UserDefaults.set('teleportKeyAction', args.new_index)
            end,
        }))
    end,
})
