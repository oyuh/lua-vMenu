-- Specs for the menu framework (client/framework/*) on top of the MenuAPI
-- port: gating, live refresh on permission and language changes, confirm
-- rows, and submenus keeping their definition's permission.

local CfxMock = require('tests.mocks.cfx')

local MODULES = {
    'shared.log',
    'shared.platform',
    'shared.json_compat',
    'shared.config',
    'shared.localization',
    'shared.permission_path',
    'client.permissions',
    'menu.frame_state',
    'menu.ticks',
    'menu.icons',
    'menu.sprites',
    'menu.nui',
    'menu.class',
    'menu.sounds',
    'menu.items',
    'menu.menu',
    'menu.input',
    'menu.controller',
    'client.framework.gate',
    'client.framework.entries',
    'client.framework.skin',
    'client.framework.host',
    'client.framework.registry',
}

describe('menu framework', function()
    local cfx, Entries, Registry, Permissions, Localization, Controller

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced' }):install()
        for _, name in ipairs(MODULES) do
            package.loaded[name] = nil
        end
        Entries = require('client.framework.entries')
        Registry = require('client.framework.registry')
        Permissions = require('client.permissions')
        Localization = require('shared.localization')
        Controller = require('menu.controller')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    local function build(entries, definition_fields)
        local definition = Registry.definition({
            title = 'Test',
            audit_name = 'Test',
            build = function(builder)
                for _, entry in ipairs(entries) do
                    builder:add(entry)
                end
            end,
        })
        for key, value in pairs(definition_fields or {}) do
            definition[key] = value
        end
        Registry.build({ definition })
        local link = Registry.main_menu():GetMenuItems()[1]
        return Controller.bound_menu(link), link
    end

    it('locks a denied row with the restricted text, and hides one that asks to be hidden', function()
        Permissions.apply({})
        local locked = Entries.button({ text = 'Locked', description = 'Normal', gate = 'vMenu.Enhanced.NoClip' })
        local hidden = Entries.button({ text = 'Hidden', gate = 'vMenu.Enhanced.Staff', behaviour = 'hide' })
        local open = Entries.button({ text = 'Open' })
        local menu = build({ locked, hidden, open })

        assert.is_false(locked.item.Enabled)
        assert.are.equal('LOCK', locked.item.LeftIcon)
        assert.are.equal(Localization.get('framework.restricted'), locked.item.Description)
        local shown = {}
        for _, item in ipairs(menu:GetMenuItems()) do
            shown[#shown + 1] = item.Text
        end
        assert.same({ 'Locked', 'Open' }, shown)
    end)

    it('unlocks and reveals rows as soon as the permissions change', function()
        Permissions.apply({})
        local locked = Entries.button({ text = 'Locked', description = 'Normal', gate = 'vMenu.Enhanced.NoClip' })
        local hidden = Entries.button({ text = 'Hidden', gate = 'vMenu.Enhanced.Staff', behaviour = 'hide' })
        local menu = build({ locked, hidden })

        Permissions.apply({ 'vMenu.Enhanced.NoClip', 'vMenu.Enhanced.Staff' })
        assert.is_true(locked.item.Enabled)
        assert.are.equal('NONE', locked.item.LeftIcon)
        assert.are.equal('Normal', locked.item.Description)
        assert.are.equal(2, menu:Size())
    end)

    it('shows the empty notice when every row is hidden', function()
        Permissions.apply({})
        local menu = build({ Entries.button({ text = 'Hidden', gate = 'vMenu.Enhanced.Staff', behaviour = 'hide' }) })
        assert.are.equal(1, menu:Size())
        assert.are.equal(Localization.get('framework.emptymenu'), menu:GetMenuItems()[1].Text)
    end)

    it('relabels every row when the language changes', function()
        Permissions.apply({ 'vMenu.Enhanced.Everything' })
        Localization.register('nl', 'Nederlands', { ['framework.emptymenu'] = 'Geen rechten' })
        local entry = Entries.button({ text = Localization.key('framework.emptymenu') })
        build({ entry })
        assert.are.equal('No Permissions', entry.item.Text)

        Localization.set_language('nl')
        assert.are.equal('Geen rechten', entry.item.Text)
    end)

    it('runs a confirm row on the second press only', function()
        Permissions.apply({ 'vMenu.Enhanced.Everything' })
        local confirmed = 0
        local entry = Entries.confirm_button({
            text = 'Delete',
            description = 'Deletes it',
            on_confirmed = function()
                confirmed = confirmed + 1
            end,
        })
        local menu = build({ entry })
        menu:OpenMenu()

        menu:SelectItem(entry.item)
        assert.are.equal(0, confirmed)
        assert.are.equal(Localization.get('framework.confirm'), entry.item.Description)
        menu:SelectItem(entry.item)
        assert.are.equal(1, confirmed)
        assert.are.equal('Deletes it', entry.item.Description)
    end)

    it("keeps a submenu's own permission on the row that opens it", function()
        Permissions.apply({})
        local _, link = build({ Entries.button({ text = 'Inside' }) }, { gate = 'vMenu.Enhanced.Staff' })
        assert.is_false(link.Enabled)
        assert.are.equal('LOCK', link.LeftIcon)

        Permissions.apply({ 'vMenu.Enhanced.Staff' })
        assert.is_true(link.Enabled)
    end)
end)
