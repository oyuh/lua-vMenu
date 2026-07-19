-- Port of vMenu/Notification.cs: Notify (above-minimap notifications),
-- Subtitle, HelpMessage, and the CommonErrors message templates. All colour
-- prefixes and wording are part of the user-visible surface, so keep them exact.

local Notification = {}

-- CommonErrors enum → template. get(name, placeholder) formats like
-- ErrorMessage.Get: the placeholder is prefixed with a space when present.
local ERROR_TEMPLATES = {
    NeedToBeTheDriver = function(_)
        return 'You need to be the driver of this vehicle.'
    end,
    NoVehicle = function(p)
        return ('You need to be inside a vehicle%s.'):format(p)
    end,
    NotAllowed = function(p)
        return ('You are not allowed to%s, sorry.'):format(p)
    end,
    InvalidModel = function(p)
        return ("This model~r~%s ~s~could not be found, are you sure it's valid?"):format(p)
    end,
    InvalidInput = function(p)
        return ('The input~r~%s ~s~is invalid or you cancelled the action, please try again.'):format(p)
    end,
    InvalidSaveName = function(p)
        return ('Saving failed because the provided save name~r~%s ~s~is invalid.'):format(p)
    end,
    SaveNameAlreadyExists = function(p)
        return ('Saving failed because the provided save name~r~%s ~s~already exists.'):format(p)
    end,
    CouldNotLoadSave = function(p)
        return ('Loading of~r~%s ~s~failed! Is the saves file corrupt?'):format(p)
    end,
    CouldNotLoad = function(p)
        return ('Could not load~r~%s~s~, sorry!'):format(p)
    end,
    PedNotFound = function(p)
        return ('The specified ped could not be found.%s'):format(p)
    end,
    PlayerNotFound = function(p)
        return ('The specified player could not be found.%s'):format(p)
    end,
    WalkingStyleNotForMale = function(p)
        return ('This walking style is not available for male peds.%s'):format(p)
    end,
    WalkingStyleNotForFemale = function(p)
        return ('This walking style is not available for female peds.%s'):format(p)
    end,
    RightAlignedNotSupported = function(p)
        return ('Right aligned menus are not supported for ultra wide aspect ratios.%s'):format(p)
    end,
}

function Notification.error_message(error_type, placeholder_value)
    local placeholder = placeholder_value ~= nil and (' ' .. placeholder_value) or ''
    local template = ERROR_TEMPLATES[error_type]
    if template then
        return template(placeholder)
    end
    return ('An unknown error occurred, sorry!%s'):format(placeholder)
end

-- Screen.StringToArray: 99-char chunks (game text components are capped).
local function string_to_array(input)
    local chunks = {}
    for i = 1, #input, 99 do
        chunks[#chunks + 1] = input:sub(i, i + 98)
    end
    return chunks
end

local function add_message_components(message)
    for _, chunk in ipairs(string_to_array(message)) do
        AddTextComponentSubstringPlayerName(chunk)
    end
end

-- ---------------------------------------------------------------------------
-- Notify
-- ---------------------------------------------------------------------------

local Notify = {}
Notification.Notify = Notify

local function default_true(value)
    if value == nil then
        return true
    end
    return value
end

function Notify.custom(message, blink, save_to_brief)
    SetNotificationTextEntry('CELL_EMAIL_BCON') -- 10x ~a~
    add_message_components(message)
    DrawNotification(default_true(blink), default_true(save_to_brief))
end

function Notify.alert(message, blink, save_to_brief)
    Notify.custom('~y~~h~Alert~h~~s~: ' .. message, blink, save_to_brief)
end

function Notify.error(message, blink, save_to_brief)
    Notify.custom('~r~~h~Error~h~~s~: ' .. message, blink, save_to_brief)
    print('[vMenu] [ERROR] ' .. message)
end

function Notify.info(message, blink, save_to_brief)
    Notify.custom('~b~~h~Info~h~~s~: ' .. message, blink, save_to_brief)
end

function Notify.success(message, blink, save_to_brief)
    Notify.custom('~g~~h~Success~h~~s~: ' .. message, blink, save_to_brief)
end

-- Alert/Error overloads taking a CommonErrors template name.
function Notify.alert_error(error_type, blink, save_to_brief, placeholder_value)
    Notify.alert(Notification.error_message(error_type, placeholder_value), blink, save_to_brief)
end

function Notify.error_template(error_type, blink, save_to_brief, placeholder_value)
    Notify.error(Notification.error_message(error_type, placeholder_value), blink, save_to_brief)
end

function Notify.custom_image(texture_dict, texture_name, message, title, subtitle, save_to_brief, icon_type)
    SetNotificationTextEntry('CELL_EMAIL_BCON')
    add_message_components(message)
    SetNotificationMessage(texture_name, texture_dict, false, icon_type or 0, title, subtitle)
    DrawNotification(false, default_true(save_to_brief))
end

-- ---------------------------------------------------------------------------
-- Subtitle
-- ---------------------------------------------------------------------------

local Subtitle = {}
Notification.Subtitle = Subtitle

function Subtitle.custom(message, duration, draw_immediately)
    BeginTextCommandPrint('CELL_EMAIL_BCON')
    add_message_components(message)
    EndTextCommandPrint(duration or 2500, default_true(draw_immediately))
end

-- Colored variants: with a prefix only the prefix is colored, otherwise the
-- whole message is.
local function prefixed(color, message, prefix)
    if prefix ~= nil then
        return color .. prefix .. ' ~s~' .. message
    end
    return color .. message
end

function Subtitle.alert(message, duration, draw_immediately, prefix)
    Subtitle.custom(prefixed('~y~', message, prefix), duration, draw_immediately)
end

function Subtitle.error(message, duration, draw_immediately, prefix)
    Subtitle.custom(prefixed('~r~', message, prefix), duration, draw_immediately)
end

function Subtitle.info(message, duration, draw_immediately, prefix)
    Subtitle.custom(prefixed('~b~', message, prefix), duration, draw_immediately)
end

function Subtitle.success(message, duration, draw_immediately, prefix)
    Subtitle.custom(prefixed('~g~', message, prefix), duration, draw_immediately)
end

-- ---------------------------------------------------------------------------
-- HelpMessage
-- ---------------------------------------------------------------------------

local HelpMessage = {}
Notification.HelpMessage = HelpMessage

HelpMessage.labels = {
    EXIT_INTERIOR_HELP_MESSAGE = {
        key = 'EXIT_INTERIOR_HELP_MESSAGE',
        text = 'Press ~INPUT_CONTEXT~ to exit the building.',
    },
}

function HelpMessage.custom(message, duration, sound)
    if IsHelpMessageBeingDisplayed() then
        ClearAllHelpMessages()
    end
    BeginTextCommandDisplayHelp('CELL_EMAIL_BCON')
    add_message_components(message)
    EndTextCommandDisplayHelp(0, false, default_true(sound), duration or 6000)
end

function HelpMessage.custom_looped(label)
    local entry = HelpMessage.labels[label]
    if entry == nil then
        return
    end
    if GetLabelText(entry.key) == 'NULL' then
        AddTextEntry(entry.key, entry.text)
    end
    DisplayHelpTextThisFrame(entry.key, true)
end

return Notification
