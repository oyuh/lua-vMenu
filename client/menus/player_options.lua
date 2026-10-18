-- Port of vMenu.Enhanced.Menus/PlayerOptionsMenu.cs.

local Localization = require('shared.localization')
local DamagePacks = require('shared.data.ped_damage_packs')
local Scenarios = require('shared.data.ped_scenarios')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')
local Toggles = require('client.menus.players.toggles')
local Jump = require('client.menus.players.jump')
local MoveSpeed = require('client.menus.players.move_speed')
local Actions = require('client.menus.players.actions')

local PERMISSION = 'vMenu.Enhanced.Menus.PlayerOptions.'

local function group(text, description)
    return Entries.separator({ text = text, description = description })
end

-- A checkbox for one of client/menus/players/toggles.lua.
local function toggle(feature, text, description, permission)
    return Entries.checkbox({
        text = text,
        description = description,
        gate = PERMISSION .. permission,
        read_state = function()
            return feature:enabled()
        end,
        on_changed = function(args)
            feature:set_enabled(args.checked)
        end,
    })
end

local function speed_entries(menu, speed, permission, toggle_text, toggle_description, rate_text, rate_description)
    menu:add(Entries.checkbox({
        text = toggle_text,
        description = toggle_description,
        gate = PERMISSION .. permission,
        read_state = function()
            return speed:enabled()
        end,
        on_changed = function(args)
            speed:set_enabled(args.checked)
        end,
    }))
    local rates = {}
    for index, rate in ipairs(speed.speeds) do
        rates[index] = ('%.1fx'):format(rate)
    end
    menu:add(Entries.list({
        text = rate_text,
        description = rate_description,
        gate = PERMISSION .. permission,
        options = rates,
        read_selected_index = function()
            return speed:index() - 1
        end,
        on_index_changed = function(args)
            speed:set_index(args.new_index + 1)
        end,
    }))
end

local WANTED_LEVELS = { Localization.key('playeroptions.setwanted.none') }
for stars = 1, 5 do
    WANTED_LEVELS[stars + 1] = tostring(stars)
end

local ARMOR_TIERS = { Localization.key('playeroptions.setarmor.none') }
for tier = 1, Actions.ARMOR_TIERS do
    ARMOR_TIERS[tier + 1] = ('%d%%'):format(tier * 100 // Actions.ARMOR_TIERS)
end

local SCENARIO_NAMES = {}
for index, scenario in ipairs(Scenarios) do
    SCENARIO_NAMES[index] = scenario[1]
end

return Registry.definition({
    audit_name = 'PlayerOptionsMenu',
    title_key = 'playeroptions.title',
    subtitle_key = 'playeroptions.subtitle',
    description_key = 'playeroptions.link.desc',
    permission = PERMISSION .. 'Menu',
    build = function(menu)
        menu:add(
            group(
                Localization.key('playeroptions.group.protection'),
                Localization.key('playeroptions.group.protection.desc')
            )
        )
        menu:add(
            toggle(
                Toggles.god_mode,
                Localization.key('playeroptions.godmode'),
                Localization.key('playeroptions.godmode.desc'),
                'Godmode'
            )
        )
        menu:add(
            toggle(
                Toggles.invisible,
                Localization.key('playeroptions.invisible'),
                Localization.key('playeroptions.invisible.desc'),
                'Invisible'
            )
        )
        menu:add(
            toggle(
                Toggles.no_ragdoll,
                Localization.key('playeroptions.noragdoll'),
                Localization.key('playeroptions.noragdoll.desc'),
                'NoRagdoll'
            )
        )
        menu:add(
            toggle(
                Toggles.stay_in_vehicle,
                Localization.key('playeroptions.stayinvehicle'),
                Localization.key('playeroptions.stayinvehicle.desc'),
                'StayInVehicle'
            )
        )
        menu:add(
            toggle(
                Toggles.freeze,
                Localization.key('playeroptions.freeze'),
                Localization.key('playeroptions.freeze.desc'),
                'Freeze'
            )
        )
        menu:add(
            toggle(
                Toggles.everyone_ignores,
                Localization.key('playeroptions.everyoneignores'),
                Localization.key('playeroptions.everyoneignores.desc'),
                'Ignored'
            )
        )

        menu:add(
            group(
                Localization.key('playeroptions.group.movement'),
                Localization.key('playeroptions.group.movement.desc')
            )
        )
        menu:add(Entries.checkbox({
            text = Localization.key('playeroptions.superjump'),
            description = Localization.key('playeroptions.superjump.desc'),
            gate = PERMISSION .. 'SuperJump',
            read_state = Jump.super_enabled,
            on_changed = function(args)
                Jump.set_super(args.checked)
                -- Turning super jump off also turns beast mode off.
                menu:refresh()
            end,
        }))
        menu:add(Entries.checkbox({
            text = Localization.key('playeroptions.beastmode'),
            description = Localization.key('playeroptions.beastmode.desc'),
            gate = PERMISSION .. 'SuperJump',
            read_state = Jump.beast_enabled,
            on_changed = function(args)
                Jump.set_beast(args.checked)
                menu:refresh()
            end,
        }))
        menu:add(
            toggle(
                Toggles.fast_run,
                Localization.key('playeroptions.fastrun'),
                Localization.key('playeroptions.fastrun.desc'),
                'FastRun'
            )
        )
        menu:add(
            toggle(
                Toggles.fast_swim,
                Localization.key('playeroptions.fastswim'),
                Localization.key('playeroptions.fastswim.desc'),
                'FastSwim'
            )
        )
        menu:add(
            toggle(
                Toggles.unlimited_oxygen,
                Localization.key('playeroptions.unlimitedoxygen'),
                Localization.key('playeroptions.unlimitedoxygen.desc'),
                'UnlimitedOxygen'
            )
        )
        speed_entries(
            menu,
            MoveSpeed.walk,
            'MoveSpeed',
            Localization.key('playeroptions.movespeed'),
            Localization.key('playeroptions.movespeed.desc'),
            Localization.key('playeroptions.movespeed.rate'),
            Localization.key('playeroptions.movespeed.rate.desc')
        )
        speed_entries(
            menu,
            MoveSpeed.swim,
            'SwimSpeed',
            Localization.key('playeroptions.swimspeed'),
            Localization.key('playeroptions.swimspeed.desc'),
            Localization.key('playeroptions.swimspeed.rate'),
            Localization.key('playeroptions.swimspeed.rate.desc')
        )
        menu:add(Entries.submenu_for(require('client.menus.intoxication')))

        menu:add(
            group(Localization.key('playeroptions.group.wanted'), Localization.key('playeroptions.group.wanted.desc'))
        )
        menu:add(
            toggle(
                Toggles.never_wanted,
                Localization.key('playeroptions.neverwanted'),
                Localization.key('playeroptions.neverwanted.desc'),
                'NeverWanted'
            )
        )
        menu:add(Entries.list({
            text = Localization.key('playeroptions.setwanted'),
            description = Localization.key('playeroptions.setwanted.desc'),
            gate = PERMISSION .. 'SetWanted',
            options = WANTED_LEVELS,
            read_selected_index = Actions.wanted_level,
            on_selected = function(args)
                Actions.set_wanted_level(args.selected_index)
            end,
        }))

        menu:add(
            group(Localization.key('playeroptions.group.health'), Localization.key('playeroptions.group.health.desc'))
        )
        menu:add(Entries.button({
            text = Localization.key('playeroptions.healplayer'),
            description = Localization.key('playeroptions.healplayer.desc'),
            gate = PERMISSION .. 'MaxHealth',
            on_selected = Actions.heal,
        }))
        menu:add(Entries.list({
            text = Localization.key('playeroptions.setarmor'),
            description = Localization.key('playeroptions.setarmor.desc'),
            gate = PERMISSION .. 'MaxArmor',
            options = ARMOR_TIERS,
            read_selected_index = Actions.armor_tier,
            on_selected = function(args)
                Actions.set_armor_tier(args.selected_index)
            end,
        }))
        menu:add(Entries.confirm_button({
            text = Localization.key('playeroptions.suicide'),
            description = Localization.key('playeroptions.suicide.desc'),
            confirmation_description = Localization.key('playeroptions.suicide.confirm'),
            gate = PERMISSION .. 'Suicide',
            on_confirmed = Actions.commit_suicide,
        }))

        menu:add(
            group(
                Localization.key('playeroptions.group.appearance'),
                Localization.key('playeroptions.group.appearance.desc')
            )
        )
        menu:add(
            toggle(
                Toggles.no_helmet,
                Localization.key('playeroptions.nohelmet'),
                Localization.key('playeroptions.nohelmet.desc'),
                'NoHelmet'
            )
        )
        menu:add(Entries.button({
            text = Localization.key('playeroptions.clearblood'),
            description = Localization.key('playeroptions.clearblood.desc'),
            gate = PERMISSION .. 'ClearBlood',
            on_selected = Actions.clear_blood,
        }))
        menu:add(Entries.list({
            text = Localization.key('playeroptions.setblood'),
            description = Localization.key('playeroptions.setblood.desc'),
            gate = PERMISSION .. 'SetBlood',
            options = DamagePacks,
            on_selected = function(args)
                Actions.apply_damage_pack(args.selected_index + 1)
            end,
        }))
        menu:add(Entries.button({
            text = Localization.key('playeroptions.cleanplayer'),
            description = Localization.key('playeroptions.cleanplayer.desc'),
            gate = PERMISSION .. 'CleanPlayer',
            on_selected = Actions.clean_clothes,
        }))
        menu:add(Entries.button({
            text = Localization.key('playeroptions.dryplayer'),
            description = Localization.key('playeroptions.dryplayer.desc'),
            gate = PERMISSION .. 'DryPlayer',
            on_selected = Actions.dry_clothes,
        }))
        menu:add(Entries.button({
            text = Localization.key('playeroptions.wetplayer'),
            description = Localization.key('playeroptions.wetplayer.desc'),
            gate = PERMISSION .. 'WetPlayer',
            on_selected = Actions.wet_clothes,
        }))

        menu:add(
            group(Localization.key('playeroptions.group.stats'), Localization.key('playeroptions.group.stats.desc'))
        )
        menu:add(Entries.submenu({
            text = Localization.key('playeroptions.mpstats'),
            description = Localization.key('playeroptions.mpstats.desc'),
            locked_description = Localization.key('playeroptions.mpstats.locked'),
            menu_subtitle = Localization.key('playeroptions.mpstats.subtitle'),
            definition = require('client.menus.mp_stats'),
        }))

        menu:add(
            group(
                Localization.key('playeroptions.group.scenarios'),
                Localization.key('playeroptions.group.scenarios.desc')
            )
        )
        menu:add(Entries.list({
            text = Localization.key('playeroptions.scenarios'),
            description = Localization.key('playeroptions.scenarios.desc'),
            gate = PERMISSION .. 'Scenarios',
            options = SCENARIO_NAMES,
            on_selected = function(args)
                Actions.play_scenario(args.selected_index + 1)
            end,
        }))
        menu:add(Entries.button({
            text = Localization.key('playeroptions.stopscenario'),
            description = Localization.key('playeroptions.stopscenario.desc'),
            gate = PERMISSION .. 'Scenarios',
            on_selected = Actions.force_stop_scenario,
        }))
    end,
})
