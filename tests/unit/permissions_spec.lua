-- Specs for shared/permissions.lua against PermissionsManager.cs semantics.
-- Contract: docs/contracts/permissions.md

local Permissions = require('shared.permissions')

describe('shared/permissions', function()
    describe('permission list', function()
        it('contains all 297 upstream permissions', function()
            assert.equal(297, #Permissions.list)
        end)

        it('has no duplicates', function()
            local seen = {}
            for _, name in ipairs(Permissions.list) do
                assert.is_nil(seen[name], ('duplicate permission: %s'):format(name))
                seen[name] = true
            end
        end)

        it('starts with the five global permissions in upstream order', function()
            assert.same(
                { 'Everything', 'DontKickMe', 'DontBanMe', 'NoClip', 'Staff' },
                { table.unpack(Permissions.list, 1, 5) }
            )
        end)
    end)

    describe('ace_name (GetAceName)', function()
        it('expands the 13 category prefixes', function()
            assert.equal('vMenu.OnlinePlayers.Kick', Permissions.ace_name('OPKick'))
            assert.equal('vMenu.PlayerOptions.God', Permissions.ace_name('POGod'))
            assert.equal('vMenu.VehicleOptions.God', Permissions.ace_name('VOGod'))
            assert.equal('vMenu.VehicleSpawner.OpenWheel', Permissions.ace_name('VSOpenWheel'))
            assert.equal('vMenu.SavedVehicles.Spawn', Permissions.ace_name('SVSpawn'))
            assert.equal('vMenu.PersonalVehicle.ExclusiveDriver', Permissions.ace_name('PVExclusiveDriver'))
            assert.equal('vMenu.PlayerAppearance.AddonPeds', Permissions.ace_name('PAAddonPeds'))
            assert.equal('vMenu.TimeOptions.SetTime', Permissions.ace_name('TOSetTime'))
            assert.equal('vMenu.WeatherOptions.Dynamic', Permissions.ace_name('WODynamic'))
            assert.equal('vMenu.WeaponOptions.Pistol', Permissions.ace_name('WPPistol'))
            assert.equal('vMenu.WeaponLoadouts.Equip', Permissions.ace_name('WLEquip'))
            assert.equal('vMenu.MiscSettings.ClearArea', Permissions.ace_name('MSClearArea'))
            assert.equal('vMenu.VoiceChat.StaffChannel', Permissions.ace_name('VCStaffChannel'))
        end)

        it('leaves global permissions unexpanded', function()
            assert.equal('vMenu.Everything', Permissions.ace_name('Everything'))
            assert.equal('vMenu.Staff', Permissions.ace_name('Staff'))
            assert.equal('vMenu.NoClip', Permissions.ace_name('NoClip'))
            assert.equal('vMenu.DontKickMe', Permissions.ace_name('DontKickMe'))
            assert.equal('vMenu.DontBanMe', Permissions.ace_name('DontBanMe'))
        end)
    end)

    describe('supplementary_ace_name', function()
        it('expands the whitelist categories', function()
            assert.equal('vMenu.VehicleSpawner.WhitelistedModels.All', Permissions.supplementary_ace_name('VWAll'))
            assert.equal('vMenu.PlayerAppearance.WhitelistedModels.All', Permissions.supplementary_ace_name('PWAll'))
            assert.equal('vMenu.WeaponOptions.WhitelistedModels.All', Permissions.supplementary_ace_name('WWAll'))
        end)

        it('expands per-model whitelist permissions', function()
            assert.equal('vMenu.VehicleSpawner.WhitelistedModels.adder', Permissions.supplementary_ace_name('VWadder'))
        end)
    end)

    describe('parents (GetPermissionAndParentPermissions)', function()
        it('implies category members from Everything and <XX>All', function()
            assert.same({ 'Everything', 'OPKick', 'OPAll' }, Permissions.parents('OPKick'))
            assert.same({ 'Everything', 'WPPistol', 'WPAll' }, Permissions.parents('WPPistol'))
        end)

        it('does NOT imply <XX>Menu from <XX>All (upstream quirk)', function()
            assert.same({ 'Everything', 'VSMenu' }, Permissions.parents('VSMenu'))
        end)

        it('does not add a parent to <XX>All itself', function()
            assert.same({ 'Everything', 'OPAll' }, Permissions.parents('OPAll'))
        end)

        it('treats globals as only implied by Everything', function()
            assert.same({ 'Everything', 'NoClip' }, Permissions.parents('NoClip'))
            assert.same({ 'Everything', 'Everything' }, Permissions.parents('Everything'))
        end)
    end)

    describe('supplementary_parents', function()
        it('implies the Menu suffix too (only All is excluded)', function()
            assert.same({ 'Everything', 'VWadder', 'VWAll' }, Permissions.supplementary_parents('VWadder'))
            assert.same({ 'Everything', 'VWAll' }, Permissions.supplementary_parents('VWAll'))
        end)
    end)

    describe('denied_without_permission_system', function()
        it('matches the upstream denylist exactly', function()
            assert.same({
                'Everything',
                'OPAll',
                'OPKick',
                'OPKill',
                'OPPermBan',
                'OPTempBan',
                'OPUnban',
                'OPIdentifiers',
                'OPViewBannedPlayers',
            }, Permissions.denied_without_permission_system)
        end)
    end)
end)
