-- Port of vMenu.Enhanced.Menus/MpStatsMenu.cs.

local Localization = require('shared.localization')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')
local MpStats = require('client.menus.players.mp_stats')

local PERCENTAGES = {}
for index = 0, MpStats.FULL // MpStats.STEP do
    PERCENTAGES[index + 1] = ('%d%%'):format(index * MpStats.STEP)
end

-- The description, plus the server's cap when it is below 100%.
local function describe(entry)
    local text = Localization.get(entry.description_key)
    local limit = MpStats.limit_of(entry)
    if limit >= MpStats.FULL then
        return text
    end
    return Localization.resolve(
        Localization.key('playeroptions.mpstats.limited', { description = text, limit = tostring(limit) })
    )
end

return Registry.definition({
    audit_name = 'MpStatsMenu',
    title_key = 'playeroptions.mpstats',
    subtitle_key = 'playeroptions.mpstats.subtitle',
    description_key = 'playeroptions.mpstats.desc',
    permission = 'vMenu.Enhanced.Menus.PlayerOptions.MpStats',
    build = function(menu)
        for _, entry in ipairs(MpStats.ALL) do
            menu:add(Entries.list({
                text = Localization.key(entry.text_key),
                description = Localization.from(function()
                    return describe(entry)
                end),
                options = PERCENTAGES,
                read_selected_index = function()
                    return MpStats.chosen(entry) // MpStats.STEP
                end,
                on_index_changed = function(args)
                    MpStats.set_chosen(entry, args.new_index * MpStats.STEP)
                end,
            }))
        end
    end,
})
