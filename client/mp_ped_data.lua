-- Port of vMenu/MpPedDataManager.cs: the MultiplayerPedData record shape.
-- C# defines these as structs; here they're constructors that produce tables
-- with the exact Newtonsoft field names from docs/contracts/kvp-saves.md
-- (golden fixture: tests/fixtures/mp_ped_data.json). MpPedCustomization
-- fills these in before saving under the mp_ped_<name> KVP.
--
-- The PedTatttoos triple-t typo is load-bearing: upstream marks the field
-- "DO NOT RENAME - 7+ years of existing saved data will stop working".

local MpPedData = {}

-- KeyValuePair<K,V> → { Key = k, Value = v }.
function MpPedData.kvp(key, value)
    return { Key = key, Value = value }
end

function MpPedData.new_ped_appearance()
    return {
        hairStyle = 0,
        hairColor = 0,
        hairHighlightColor = 0,
        HairOverlay = nil, -- KeyValuePair<string,string>

        blemishesStyle = 0, -- 0 blemishes
        blemishesOpacity = 0.0,

        beardStyle = 0, -- 1 beard
        beardColor = 0,
        beardOpacity = 0.0,

        eyebrowsStyle = 0, -- 2 eyebrows
        eyebrowsColor = 0,
        eyebrowsOpacity = 0.0,

        ageingStyle = 0, -- 3 ageing
        ageingOpacity = 0.0,

        makeupStyle = 0, -- 4 makeup
        makeupColor = 0,
        makeupOpacity = 0.0,

        blushStyle = 0, -- 5 blush
        blushColor = 0,
        blushOpacity = 0.0,

        complexionStyle = 0, -- 6 complexion
        complexionOpacity = 0.0,

        sunDamageStyle = 0, -- 7 sun damage
        sunDamageOpacity = 0.0,

        lipstickStyle = 0, -- 8 lipstick
        lipstickColor = 0,
        lipstickOpacity = 0.0,

        molesFrecklesStyle = 0, -- 9 moles / freckles
        molesFrecklesOpacity = 0.0,

        chestHairStyle = 0, -- 10 chest hair
        chestHairColor = 0,
        chestHairOpacity = 0.0,

        bodyBlemishesStyle = 0, -- 11 body blemishes
        bodyBlemishesOpacity = 0.0,

        eyeColor = 0,
    }
end

function MpPedData.new_ped_tattoos()
    return {
        HairTattoos = {},
        TorsoTattoos = {},
        HeadTattoos = {},
        LeftArmTattoos = {},
        RightArmTattoos = {},
        LeftLegTattoos = {},
        RightLegTattoos = {},
        BadgeTattoos = {},
        AddonTattoos = {},
    }
end

-- MultiplayerPedData: the full record. Dictionary-backed members start as
-- empty maps (C# code always assigns them before serializing).
function MpPedData.new()
    return {
        PedHeadBlendData = {
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
        },
        DrawableVariations = { clothes = {} }, -- [component id string] = {Key=drawable, Value=texture}
        PropVariations = { props = {} }, -- [prop id string] = {Key=prop, Value=texture}
        FaceShapeFeatures = { features = {} }, -- [feature id string] = float
        PedAppearance = MpPedData.new_ped_appearance(),
        PedTatttoos = MpPedData.new_ped_tattoos(),
        PedFacePaints = {},
        IsMale = false,
        ModelHash = 0,
        SaveName = nil,
        Version = 0,
        WalkingStyle = nil,
        FacialExpression = nil,
        Category = nil,
    }
end

return MpPedData
