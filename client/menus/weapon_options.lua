-- Port of vMenu.Enhanced.Menus/WeaponOptionsMenu.cs. The categories come from
-- the server's config/weapons.json; every weapon opens one shared detail menu
-- with its ammo, tint and components.

local Localization = require('shared.localization')
local Permissions = require('client.permissions')
local Gate = require('client.framework.gate')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')
local Notifications = require('client.framework.notifications')
local Input = require('client.framework.input')
local Ticks = require('menu.ticks')
local Catalog = require('client.menus.weapons.catalog')
local Inventory = require('client.menus.weapons.inventory')
local Features = require('client.menus.weapons.features')

local PERMISSION = 'vMenu.Enhanced.Menus.WeaponOptions.'
local WATCH_MS = 250
local MAX_AMMO_INPUT = 10
local MAX_NAME_INPUT = 40

local function count_text(key, count)
    return Localization.key(key, { count = tostring(count) })
end

local function set_all_ammo()
    local typed = Input.get_text({
        title = Localization.key('weaponoptions.setallammo.prompt'),
        max_length = MAX_AMMO_INPUT,
        initial_value = '100',
    })
    if typed == nil or typed:match('^%s*$') then
        return
    end
    local ammo = math.tointeger(tonumber(typed:match('^%s*(.-)%s*$')))
    if not ammo or ammo < 0 then
        Notifications.error(Localization.key('weaponoptions.setallammo.invalid'))
        return
    end
    Notifications.success(count_text('weaponoptions.setallammo.done', Inventory.set_all_ammo(ammo)))
end

local function suggestions()
    local list = {}
    for _, category in ipairs(Catalog.categories()) do
        for _, weapon in ipairs(category.weapons) do
            if Permissions.can_use_weapon(weapon.spawn_name, category.name) and Catalog.is_valid(weapon.spawn_name) then
                list[#list + 1] = {
                    value = weapon.spawn_name,
                    label = Catalog.weapon_name(weapon),
                    detail = category.name,
                }
            end
        end
    end
    return list
end

local function spawn_by_name()
    local typed = Input.get_text({
        title = Localization.key('weaponoptions.byname.prompt'),
        max_length = MAX_NAME_INPUT,
        suggestions = suggestions(),
    })
    if typed == nil or typed:match('^%s*$') then
        return
    end
    local spawn_name = typed:match('^%s*(.-)%s*$'):lower()
    local hash = GetHashKey(spawn_name)
    if not IsWeaponValid(hash) then
        Notifications.error(Localization.key('weaponoptions.byname.invalid', { weapon = spawn_name }))
        return
    end
    local known, category = Catalog.find(spawn_name)
    if known and not Permissions.can_use_weapon(known.spawn_name, category) then
        Notifications.warning(Localization.key('weaponoptions.byname.denied', { weapon = spawn_name }))
        return
    end
    Inventory.give(hash)
end

local function build_parachute_menu(menu)
    menu:add(Entries.button({
        text = Localization.key('weaponoptions.parachute.primary'),
        description = Localization.key('weaponoptions.parachute.primary.desc'),
        on_selected = function()
            local added = Features.toggle_primary()
            Notifications.success(
                Localization.key(
                    added and 'weaponoptions.parachute.primary.added' or 'weaponoptions.parachute.primary.removed'
                )
            )
        end,
    }))
    menu:add(Entries.button({
        text = Localization.key('weaponoptions.parachute.reserve'),
        description = Localization.key('weaponoptions.parachute.reserve.desc'),
        on_selected = function()
            Features.enable_reserve()
            Notifications.success(Localization.key('weaponoptions.parachute.reserve.added'))
        end,
    }))
    menu:add(Entries.checkbox({
        text = Localization.key('weaponoptions.parachute.autoequip'),
        description = Localization.key('weaponoptions.parachute.autoequip.desc'),
        read_state = Features.auto_equip,
        on_changed = function(args)
            Features.set_auto_equip(args.checked)
        end,
    }))
    menu:add(Entries.checkbox({
        text = Localization.key('weaponoptions.parachute.unlimited'),
        description = Localization.key('weaponoptions.parachute.unlimited.desc'),
        read_state = Features.unlimited_parachutes,
        on_changed = function(args)
            Features.set_unlimited_parachutes(args.checked)
        end,
    }))
    menu:add(Entries.list({
        text = Localization.key('weaponoptions.parachute.smoke'),
        description = Localization.key('weaponoptions.parachute.smoke.desc'),
        options = Features.smoke_names(),
        on_selected_async = function(args)
            Notifications.info(Localization.key('weaponoptions.parachute.smoke.changing'))
            Features.set_smoke_color(args.selected_index + 1)
        end,
    }))
    menu:add(Entries.list({
        text = Localization.key('weaponoptions.parachute.primarystyle'),
        description = Localization.key('weaponoptions.parachute.primarystyle.desc'),
        options = Features.style_names(),
        on_index_changed = function(args)
            Features.set_primary_style(args.new_index)
        end,
    }))
    menu:add(Entries.list({
        text = Localization.key('weaponoptions.parachute.reservestyle'),
        description = Localization.key('weaponoptions.parachute.reservestyle.desc'),
        options = Features.style_names(),
        on_index_changed = function(args)
            Features.set_reserve_style(args.new_index)
        end,
    }))
end

return Registry.definition({
    audit_name = 'WeaponOptionsMenu',
    title_key = 'weaponoptions.title',
    subtitle_key = 'weaponoptions.subtitle',
    description_key = 'weaponoptions.link.desc',
    permission = PERMISSION .. 'Menu',
    prepare = Catalog.wait_for_first,
    build = function(menu)
        local categories = Catalog.categories()
        local selected, selected_category, selected_hash
        local last_seen = ''
        local weapon_menu

        -- What changes on the open weapon, so the menu refreshes only then.
        local function snapshot()
            if not selected then
                return ''
            end
            local hash = selected_hash
            if not Inventory.has(hash) then
                return '-'
            end
            local fitted = {}
            for index, component in ipairs(Catalog.components_for(hash)) do
                fitted[index] = Inventory.has_component(hash, GetHashKey(component.spawn_name)) and '1' or '0'
            end
            return ('%d:%d:%s'):format(Inventory.ammo(hash), Inventory.tint(hash), table.concat(fitted))
        end

        local function resync(force)
            if not selected then
                return
            end
            local seen = snapshot()
            if force or seen ~= last_seen then
                last_seen = seen
                weapon_menu.refresh()
            end
        end

        local function stats_of(hash)
            return function()
                return Inventory.weapon_stats(hash)
            end
        end

        local function build_weapon_menu(builder, hash)
            builder:add(Entries.button({
                text = Localization.from(function()
                    return Localization.get(Inventory.has(hash) and 'weaponoptions.remove' or 'weaponoptions.equip')
                end),
                description = Localization.from(function()
                    return Localization.get(
                        Inventory.has(hash) and 'weaponoptions.remove.desc' or 'weaponoptions.equip.desc'
                    )
                end),
                left_icon = 'GUN',
                gate = PERMISSION .. 'Spawn',
                weapon_stats = stats_of(hash),
                on_selected = function()
                    Inventory.toggle(hash)
                    resync(true)
                end,
            }))
            builder:add(Entries.button({
                text = Localization.key('weaponoptions.refillammo'),
                description = Localization.key('weaponoptions.refillammo.desc'),
                label = Localization.from(function()
                    return Inventory.has(hash) and tostring(Inventory.ammo(hash)) or ''
                end),
                left_icon = 'AMMO',
                weapon_stats = stats_of(hash),
                on_selected = function()
                    if not Inventory.refill(hash) then
                        Notifications.error(Localization.key('weaponoptions.notheld'))
                    end
                    resync(true)
                end,
            }))
            builder:add(Entries.list({
                text = Localization.key('weaponoptions.tints'),
                description = Localization.key('weaponoptions.tints.desc'),
                options = Inventory.tint_options(Inventory.tint_count(hash)),
                gate = PERMISSION .. 'Modify',
                weapon_stats = stats_of(hash),
                read_selected_index = function()
                    return Inventory.tint(hash)
                end,
                on_index_changed = function(args)
                    if not Inventory.has(hash) then
                        Notifications.error(Localization.key('weaponoptions.notheld'))
                        return
                    end
                    Inventory.set_tint(hash, args.new_index)
                end,
            }))
            for _, component in ipairs(Catalog.components_for(hash)) do
                local component_hash = GetHashKey(component.spawn_name)
                builder:add(Entries.button({
                    text = Localization.from(function()
                        return Catalog.resolve_name(component.label, component.spawn_name)
                    end),
                    description = Localization.key('weaponoptions.component.desc'),
                    gate = PERMISSION .. 'Modify',
                    weapon_stats = stats_of(hash),
                    weapon_component_stats = function()
                        return Inventory.component_stats(component_hash)
                    end,
                    read_left_icon = function()
                        return Inventory.has_component(hash, component_hash) and 'TICK' or 'NONE'
                    end,
                    on_selected = function()
                        if not Inventory.has(hash) then
                            Notifications.error(Localization.key('weaponoptions.notheld'))
                            return
                        end
                        Inventory.toggle_component(hash, component_hash)
                        resync(true)
                    end,
                }))
            end
        end

        local function open_weapon(weapon, category_name, hash)
            selected, selected_category, selected_hash = weapon, category_name, hash
            last_seen = snapshot()
            weapon_menu.builder:clear_entries()
            build_weapon_menu(weapon_menu.builder, hash)
            weapon_menu.open()
        end

        menu:add(Entries.button({
            text = Localization.key('weaponoptions.getall'),
            description = Localization.key('weaponoptions.getall.desc'),
            gate = PERMISSION .. 'GetAll',
            on_selected = function()
                Notifications.success(count_text('weaponoptions.getall.done', Inventory.give_all()))
            end,
        }))
        menu:add(Entries.button({
            text = Localization.key('weaponoptions.removeall'),
            description = Localization.key('weaponoptions.removeall.desc'),
            gate = PERMISSION .. 'RemoveAll',
            on_selected = function()
                Inventory.remove_all()
                Notifications.success(Localization.key('weaponoptions.removeall.done'))
            end,
        }))
        menu:add(Entries.checkbox({
            text = Localization.key('weaponoptions.unlimitedammo'),
            description = Localization.key('weaponoptions.unlimitedammo.desc'),
            gate = PERMISSION .. 'UnlimitedAmmo',
            read_state = Features.unlimited_ammo,
            on_changed = function(args)
                Features.set_unlimited_ammo(args.checked)
            end,
        }))
        menu:add(Entries.checkbox({
            text = Localization.key('weaponoptions.noreload'),
            description = Localization.key('weaponoptions.noreload.desc'),
            gate = PERMISSION .. 'NoReload',
            read_state = Features.no_reload,
            on_changed = function(args)
                Features.set_no_reload(args.checked)
            end,
        }))
        menu:add(Entries.button({
            text = Localization.key('weaponoptions.setallammo'),
            description = Localization.key('weaponoptions.setallammo.desc'),
            gate = PERMISSION .. 'SetAllAmmo',
            on_selected_async = set_all_ammo,
        }))
        menu:add(Entries.button({
            text = Localization.key('weaponoptions.refillall'),
            description = Localization.key('weaponoptions.refillall.desc'),
            gate = PERMISSION .. 'SetAllAmmo',
            on_selected = function()
                Notifications.success(count_text('weaponoptions.refillall.done', Inventory.refill_all()))
            end,
        }))
        menu:add(Entries.button({
            text = Localization.key('weaponoptions.byname'),
            description = Localization.key('weaponoptions.byname.desc'),
            gate = PERMISSION .. 'SpawnByName',
            on_selected_async = spawn_by_name,
        }))
        menu:add(Entries.submenu({
            text = Localization.key('weaponoptions.parachute'),
            description = Localization.key('weaponoptions.parachute.desc'),
            menu_title = Localization.key('weaponoptions.title'),
            menu_subtitle = Localization.key('weaponoptions.parachute.subtitle'),
            gate = PERMISSION .. 'Parachute',
            build = build_parachute_menu,
        }))

        weapon_menu = menu:add_detached_menu(
            Localization.from(function()
                return selected and Catalog.weapon_name(selected) or ''
            end),
            Localization.key('weaponoptions.weapon.subtitle'),
            function() end,
            Gate.when(function()
                return selected ~= nil and Permissions.can_use_weapon(selected.spawn_name, selected_category)
            end)
        )
        Ticks.register('Weapons.OpenWeaponMenu', function()
            resync(false)
        end, {
            rate = WATCH_MS,
            condition = function()
                return weapon_menu.menu.Visible == true
            end,
        })
        weapon_menu.builder:on_opened(Ticks.reevaluate)
        weapon_menu.builder:on_closed(Ticks.reevaluate)

        if #categories > 0 then
            menu:add(Entries.separator({
                text = Localization.key('weaponoptions.group.categories'),
                description = Localization.key('weaponoptions.group.categories.desc'),
            }))
        else
            menu:add(Entries.button({
                text = Localization.key('weaponoptions.empty'),
                description = Localization.key('weaponoptions.empty.desc'),
            }))
        end
        for _, category in ipairs(categories) do
            local name = category.name
            menu:add(Entries.submenu({
                text = name,
                description = Localization.key('weaponoptions.category.desc', { category = name }),
                menu_title = name,
                menu_subtitle = Localization.key('weaponoptions.category.subtitle'),
                gate = Gate.when(function()
                    return Permissions.can_use_weapon_category(name)
                end),
                build = function(category_menu)
                    for _, weapon in ipairs(category.weapons) do
                        local hash = GetHashKey(weapon.spawn_name)
                        local display = Localization.from(function()
                            return Catalog.weapon_name(weapon)
                        end)
                        category_menu:add(Entries.button({
                            text = display,
                            description = Localization.key('weaponoptions.weapon.desc', { weapon = display }),
                            left_icon = 'GUN',
                            gate = Gate.when(function()
                                return Catalog.is_valid(weapon.spawn_name)
                                    and Permissions.can_use_weapon(weapon.spawn_name, name)
                            end),
                            read_behaviour = function()
                                return not Catalog.is_valid(weapon.spawn_name) and 'lock' or nil
                            end,
                            read_locked_description = function()
                                if Catalog.is_valid(weapon.spawn_name) then
                                    return nil
                                end
                                return Localization.key('weaponoptions.weapon.invalid', { weapon = weapon.spawn_name })
                            end,
                            weapon_stats = stats_of(hash),
                            on_selected = function()
                                open_weapon(weapon, name, hash)
                            end,
                        }))
                    end
                end,
            }))
        end
        Catalog.on_changed(Registry.refresh_all)
    end,
})
