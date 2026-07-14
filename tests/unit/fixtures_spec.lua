-- Validates the golden fixtures in tests/fixtures/ against the schemas in
-- docs/contracts/kvp-saves.md. These run on plain Lua using dkjson (a busted
-- dependency), standing in for CfxLua's built-in `json` until the runtime
-- json_compat wrapper lands.

local json = require('dkjson')

local function load_fixture(name)
    local file = assert(io.open('tests/fixtures/' .. name, 'r'))
    local contents = file:read('a')
    file:close()
    local decoded, _, err = json.decode(contents)
    assert(decoded ~= nil, ('fixture %s failed to parse: %s'):format(name, tostring(err)))
    return decoded
end

local function keys_of(tbl)
    local keys = {}
    for key in pairs(tbl) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

describe('golden fixtures', function()
    it('vehicle_info.json has every VehicleInfo field with correct casing', function()
        local vehicle = load_fixture('vehicle_info.json')
        assert.same({
            'Category',
            'bulletProofTires',
            'colors',
            'customWheels',
            'enveffScale',
            'extras',
            'headlightColor',
            'livery',
            'model',
            'mods',
            'name',
            'neonBack',
            'neonFront',
            'neonLeft',
            'neonRight',
            'plateStyle',
            'plateText',
            'turbo',
            'tyreSmoke',
            'version',
            'wheelType',
            'windowTint',
            'xenonHeadlights',
        }, keys_of(vehicle))
        assert.same({ 'dash', 'pearlescent', 'primary', 'secondary', 'trim', 'wheels' }, keys_of(vehicle.colors))
        -- uint model hashes exceed signed-32 range; must survive decoding
        assert.equal(3078201489, math.tointeger(vehicle.model))
        -- Dictionary<int,...> keys are strings in JSON
        assert.is_true(vehicle.extras['1'])
    end)

    it('ped_info.json matches the PedInfo shape', function()
        local ped = load_fixture('ped_info.json')
        assert.same({
            'drawableVariationTextures',
            'drawableVariations',
            'isMpPed',
            'model',
            'propTextures',
            'props',
            'version',
        }, keys_of(ped))
        assert.equal(8, ped.props['0'])
        assert.equal(-1, ped.props['1'])
    end)

    it('mp_ped_data.json preserves the load-bearing PedTatttoos typo', function()
        local mp_ped = load_fixture('mp_ped_data.json')
        assert.is_table(mp_ped.PedTatttoos)
        assert.is_nil(mp_ped.PedTattoos)
        assert.same({
            'AddonTattoos',
            'BadgeTattoos',
            'HairTattoos',
            'HeadTattoos',
            'LeftArmTattoos',
            'LeftLegTattoos',
            'RightArmTattoos',
            'RightLegTattoos',
            'TorsoTattoos',
        }, keys_of(mp_ped.PedTatttoos))
    end)

    it('mp_ped_data.json uses {Key, Value} pair encoding', function()
        local mp_ped = load_fixture('mp_ped_data.json')
        local first_cloth = mp_ped.DrawableVariations.clothes['0']
        assert.same({ 'Key', 'Value' }, keys_of(first_cloth))
        assert.same({ 'Key', 'Value' }, keys_of(mp_ped.PedAppearance.HairOverlay))
        assert.same({ 'Key', 'Value' }, keys_of(mp_ped.PedTatttoos.HairTattoos[1]))
    end)

    it('mp_ped_data.json top level matches MultiplayerPedData fields', function()
        local mp_ped = load_fixture('mp_ped_data.json')
        for _, field in ipairs({
            'PedHeadBlendData',
            'DrawableVariations',
            'PropVariations',
            'FaceShapeFeatures',
            'PedAppearance',
            'PedTatttoos',
            'PedFacePaints',
            'IsMale',
            'ModelHash',
            'SaveName',
            'Version',
            'Category',
        }) do
            assert.is_not_nil(mp_ped[field] ~= nil and true or nil, ('missing field: %s'):format(field))
        end
    end)

    it('weapon_loadout.json is a ValidWeapon array with serialized read-only props', function()
        local loadout = load_fixture('weapon_loadout.json')
        assert.equal(2, #loadout)
        for _, weapon in ipairs(loadout) do
            for _, field in ipairs({
                'Hash',
                'Name',
                'Components',
                'Perm',
                'SpawnName',
                'GetMaxAmmo',
                'CurrentAmmo',
                'CurrentTint',
                'Accuracy',
                'Damage',
                'Range',
                'Speed',
            }) do
                assert.is_not_nil(weapon[field], ('missing field: %s'):format(field))
            end
            -- Perm is a numeric enum ordinal, not a name
            assert.is_number(weapon.Perm)
        end
    end)

    it('ban_record.json matches BanRecord with year-3000 perm ban encoding', function()
        local ban = load_fixture('ban_record.json')
        assert.same({ 'banReason', 'bannedBy', 'bannedUntil', 'identifiers', 'playerName', 'uuid' }, keys_of(ban))
        assert.matches('^3000%-01%-01T00:00:00$', ban.bannedUntil)
        assert.is_truthy(ban.banReason:find('\nYour ban id: ' .. ban.uuid, 1, true))
        assert.matches('^[0-9a-f%-]+$', ban.uuid)
    end)

    it('category.json matches the shared category shape', function()
        local category = load_fixture('category.json')
        assert.same({ 'Description', 'Icon', 'Name' }, keys_of(category))
        assert.is_number(category.Icon)
    end)
end)
