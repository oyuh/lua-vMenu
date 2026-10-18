-- Port of vMenu.Enhanced.MenuFramework/UserInput.cs (with InputPrompt and
-- InputSuggestion): the text box on ui/input.js. Asking waits for the answer,
-- so call it from a thread, such as an entry's *_async handler.
--
-- A prompt is a table: { title, max_length, initial_value, suggestions,
-- suggest_when_empty, description }, where title and description are menu
-- text and suggestions are { value, label, icon, detail }.

local Log = require('shared.log')
local Json = require('shared.json_compat')
local Localization = require('shared.localization')
local Locks = require('client.framework.locks')

local Input = {}

local SUBMIT_CALLBACK = 'vMenuPromptSubmit'
local CANCEL_CALLBACK = 'vMenuPromptCancel'
local READY_CALLBACK = 'vMenuPromptReady'
local CLOSE_MESSAGE = '{"type":"close"}'
local READY_TIMEOUT_MS = 3000
-- The page's first callback of a session takes seconds; later ones are immediate.
local FIRST_READY_TIMEOUT_MS = 15000
-- What the page falls back to when a prompt declares no limit.
local DEFAULT_MAX_LENGTH = 255

local callbacks_registered = false
local handshaken = false
local open = false
local pending -- { done = bool, answer = string|nil }
local ready = false
local max_length = DEFAULT_MAX_LENGTH

-- The page's maxLength is a DOM attribute, so anything with the developer
-- tools open can post past it. Cut here so no prompt answers with more than
-- it asked for. Counted in characters, never cutting one in half.
local function capped(text)
    local length = utf8.len(text)
    if not length then
        Log.error('[Input] An answer was not valid UTF-8, so it was dropped.')
        return ''
    end
    if length <= max_length then
        return text
    end
    Log.warning(
        ('[Input] An answer of %d characters was cut to the %d the prompt asked for.'):format(length, max_length)
    )
    return text:sub(1, utf8.offset(text, max_length + 1) - 1)
end

local function register_callbacks()
    if callbacks_registered then
        return
    end
    callbacks_registered = true
    RegisterNUICallback(SUBMIT_CALLBACK, function(body, reply)
        pcall(reply, 'ok')
        if pending and not pending.done then
            pending.done = true
            pending.answer = capped(type(body) == 'string' and body or '')
        end
    end)
    RegisterNUICallback(CANCEL_CALLBACK, function(_, reply)
        pcall(reply, 'ok')
        if pending and not pending.done then
            pending.done = true
        end
    end)
    RegisterNUICallback(READY_CALLBACK, function(_, reply)
        pcall(reply, 'ok')
        handshaken = true
        ready = true
    end)
end

local function open_message(prompt)
    local rows = {}
    for index, suggestion in ipairs(prompt.suggestions or {}) do
        -- Single letter keys: a spawner sends thousands of these at once.
        rows[index] = {
            v = suggestion.value,
            l = suggestion.label,
            i = suggestion.icon or '',
            d = suggestion.detail or '',
        }
    end
    return Json.encode({
        type = 'open',
        title = Localization.resolve(prompt.title),
        description = Localization.resolve(prompt.description),
        value = prompt.initial_value or '',
        maxLength = prompt.max_length or 0,
        placeholder = Localization.get('framework.input.placeholder'),
        hint = Localization.get('framework.input.hint'),
        noMatches = Localization.get('framework.input.nomatches'),
        suggestWhenEmpty = prompt.suggest_when_empty == true,
        suggestions = rows,
    })
end

local function ask(prompt)
    pending = { done = false }
    ready = false
    max_length = (prompt.max_length or 0) > 0 and prompt.max_length or DEFAULT_MAX_LENGTH

    SendNuiMessage(open_message(prompt))
    SetNuiFocus(true, true)

    local timeout = handshaken and READY_TIMEOUT_MS or FIRST_READY_TIMEOUT_MS
    local started = GetGameTimer()
    while not ready do
        if GetGameTimer() - started > timeout then
            Log.error(
                ('[Input] The prompt did not answer within %dms. Is ui/index.html part of the resource?'):format(
                    timeout
                )
            )
            pending = nil
            return nil
        end
        Wait(0)
    end
    while not pending.done do
        Wait(0)
    end
    local answer = pending.answer
    pending = nil
    return answer
end

-- Asks every prompt in turn. Returns a list of answers, or nil when the
-- player canceled any of them or another prompt was already open.
function Input.get_texts(prompts)
    if #prompts == 0 or open then
        return nil
    end
    register_callbacks()
    open = true
    Locks.take_buttons()
    local answers = {}
    local ok, err = pcall(function()
        for index, prompt in ipairs(prompts) do
            local answer = ask(prompt)
            if answer == nil then
                answers = nil
                return
            end
            answers[index] = answer
        end
    end)
    open = false
    SetNuiFocus(false, false)
    SendNuiMessage(CLOSE_MESSAGE)
    Locks.release_buttons()
    if not ok then
        error(err, 0)
    end
    return answers
end

-- One prompt. Returns the text, or nil when canceled.
function Input.get_text(prompt)
    local answers = Input.get_texts({ prompt })
    return answers and answers[1]
end

return Input
