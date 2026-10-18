-- Port of vMenu.Enhanced.Menus/WeaponLoadoutsMenu.cs.

local Localization = require('shared.localization')
local Gate = require('client.framework.gate')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')
local Notifications = require('client.framework.notifications')
local Input = require('client.framework.input')
local Loadouts = require('client.menus.weapons.loadouts')

local PERMISSION = 'vMenu.Enhanced.Menus.WeaponLoadouts.'
local MAX_NAME_LENGTH = 30

local function ask_name(prompt_key, initial)
    local typed = Input.get_text({
        title = Localization.key(prompt_key),
        max_length = MAX_NAME_LENGTH,
        initial_value = initial,
    })
    if typed == nil or typed:match('^%s*$') then
        return nil
    end
    return typed:match('^%s*(.-)%s*$')
end

-- True when it saved.
local function report(outcome, name, success_key)
    if outcome == Loadouts.SAVED then
        Notifications.success(Localization.key(success_key, { name = name }))
        return true
    elseif outcome == Loadouts.NAME_TAKEN then
        Notifications.error(Localization.key('weaponloadouts.save.nametaken', { name = name }))
        return false
    end
    Notifications.error(Localization.key('weaponloadouts.save.failed'))
    return false
end

return Registry.definition({
    audit_name = 'WeaponLoadoutsMenu',
    title_key = 'weaponloadouts.title',
    subtitle_key = 'weaponloadouts.subtitle',
    description_key = 'weaponloadouts.link.desc',
    permission = PERMISSION .. 'Menu',
    build = function(menu)
        local selected
        local list_menu, detail_menu

        local function tick_if_default(name)
            return Loadouts.is_default(name) and 'TICK' or 'NONE'
        end

        local function fill_list()
            list_menu.builder:clear_entries()
            local loadouts = Loadouts.all()
            if #loadouts == 0 then
                list_menu.builder:add(Entries.button({
                    text = Localization.key('weaponloadouts.empty'),
                    description = Localization.key('weaponloadouts.empty.desc'),
                }))
                return
            end
            for _, loadout in ipairs(loadouts) do
                list_menu.builder:add(Entries.button({
                    text = loadout.name,
                    description = Localization.key('weaponloadouts.loadout.desc', { name = loadout.name }),
                    label = Localization.key('weaponloadouts.loadout.count', { count = tostring(#loadout.weapons) }),
                    read_left_icon = function()
                        return tick_if_default(loadout.name)
                    end,
                    on_selected = function()
                        selected = loadout
                        detail_menu.open()
                    end,
                }))
            end
        end

        detail_menu = menu:add_detached_menu(
            Localization.from(function()
                return selected and selected.name or ''
            end),
            Localization.key('weaponloadouts.manage.title'),
            function(detail)
                detail:add(Entries.button({
                    text = Localization.key('weaponloadouts.equip'),
                    description = Localization.key('weaponloadouts.equip.desc'),
                    gate = PERMISSION .. 'Equip',
                    on_selected_async = function()
                        local loadout = selected
                        if not loadout then
                            return
                        end
                        local _, skipped = Loadouts.apply(loadout, false, false)
                        if skipped > 0 then
                            Notifications.warning(
                                Localization.key(
                                    'weaponloadouts.equipped.skipped',
                                    { name = loadout.name, count = tostring(skipped) }
                                )
                            )
                            return
                        end
                        Notifications.success(Localization.key('weaponloadouts.equipped', { name = loadout.name }))
                    end,
                }))
                detail:add(Entries.button({
                    text = Localization.key('weaponloadouts.rename'),
                    description = Localization.key('weaponloadouts.rename.desc'),
                    gate = PERMISSION .. 'Manage',
                    on_selected_async = function()
                        local loadout = selected
                        local new_name = loadout and ask_name('weaponloadouts.rename.prompt', loadout.name)
                        if not new_name or new_name == loadout.name then
                            return
                        end
                        if not Loadouts.rename(loadout, new_name) then
                            Notifications.error(Localization.key('weaponloadouts.save.nametaken', { name = new_name }))
                            return
                        end
                        Notifications.success(Localization.key('weaponloadouts.renamed', { name = new_name }))
                        detail_menu.refresh()
                    end,
                }))
                detail:add(Entries.button({
                    text = Localization.key('weaponloadouts.clone'),
                    description = Localization.key('weaponloadouts.clone.desc'),
                    gate = PERMISSION .. 'Save',
                    on_selected_async = function()
                        local loadout = selected
                        local new_name = loadout and ask_name('weaponloadouts.clone.prompt', loadout.name)
                        if not new_name then
                            return
                        end
                        if not Loadouts.duplicate(loadout, new_name) then
                            Notifications.error(Localization.key('weaponloadouts.save.nametaken', { name = new_name }))
                            return
                        end
                        Notifications.success(Localization.key('weaponloadouts.cloned', { name = new_name }))
                    end,
                }))
                detail:add(Entries.button({
                    text = Localization.key('weaponloadouts.setdefault'),
                    description = Localization.key('weaponloadouts.setdefault.desc'),
                    gate = PERMISSION .. 'Manage',
                    read_left_icon = function()
                        return selected and tick_if_default(selected.name) or 'NONE'
                    end,
                    on_selected = function()
                        if not selected then
                            return
                        end
                        Loadouts.set_default(selected.name)
                        Notifications.success(
                            Localization.key('weaponloadouts.setdefault.done', { name = selected.name })
                        )
                        detail_menu.refresh()
                    end,
                }))
                detail:add(Entries.confirm_button({
                    text = Localization.key('weaponloadouts.replace'),
                    description = Localization.key('weaponloadouts.replace.desc'),
                    gate = PERMISSION .. 'Save',
                    on_confirmed = function()
                        if not selected then
                            return
                        end
                        local captured = Loadouts.capture(selected.name)
                        if #captured.weapons == 0 then
                            Notifications.error(Localization.key('weaponloadouts.save.nothingheld'))
                            return
                        end
                        if report(Loadouts.save(captured, true), selected.name, 'weaponloadouts.replaced') then
                            selected = captured
                        end
                    end,
                }))
                detail:add(Entries.confirm_button({
                    text = Localization.key('weaponloadouts.delete'),
                    description = Localization.key('weaponloadouts.delete.desc'),
                    gate = PERMISSION .. 'Manage',
                    on_confirmed = function()
                        if not selected then
                            return
                        end
                        Loadouts.delete(selected.name)
                        Notifications.success(Localization.key('weaponloadouts.deleted', { name = selected.name }))
                        selected = nil
                        list_menu.open()
                    end,
                }))
            end,
            Gate.when(function()
                return selected ~= nil
            end)
        )
        list_menu = menu:add_detached_menu(
            Localization.key('weaponloadouts.title'),
            Localization.key('weaponloadouts.manage.subtitle'),
            function() end
        )
        list_menu.builder:on_opened(fill_list)

        menu:add(Entries.button({
            text = Localization.key('weaponloadouts.save'),
            description = Localization.key('weaponloadouts.save.desc'),
            gate = PERMISSION .. 'Save',
            on_selected_async = function()
                local captured = Loadouts.capture('')
                if #captured.weapons == 0 then
                    Notifications.error(Localization.key('weaponloadouts.save.nothingheld'))
                    return
                end
                local name = ask_name('weaponloadouts.save.prompt')
                if not name then
                    return
                end
                captured.name = name
                report(Loadouts.save(captured, false), name, 'weaponloadouts.saved')
            end,
        }))
        menu:add(Entries.button({
            text = Localization.key('weaponloadouts.manage'),
            description = Localization.key('weaponloadouts.manage.desc'),
            label = '→',
            on_selected = function()
                list_menu.open()
            end,
        }))
        menu:add(Entries.checkbox({
            text = Localization.key('weaponloadouts.onrespawn'),
            description = Localization.key('weaponloadouts.onrespawn.desc'),
            gate = PERMISSION .. 'EquipOnRespawn',
            read_state = Loadouts.restore_on_respawn,
            on_changed = function(args)
                Loadouts.set_restore_on_respawn(args.checked)
            end,
        }))
        menu:add(Entries.checkbox({
            text = Localization.key('weaponloadouts.onpedchange'),
            description = Localization.key('weaponloadouts.onpedchange.desc'),
            gate = PERMISSION .. 'KeepOnPedChange',
            read_state = Loadouts.keep_on_ped_change,
            on_changed = function(args)
                Loadouts.set_keep_on_ped_change(args.checked)
            end,
        }))
    end,
})
