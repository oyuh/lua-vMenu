-- Port of vMenu.Enhanced.Plugins/PluginHost.cs: the client half of upstream's
-- plugin protocol (version 3). A plugin is another resource built on
-- upstream's plugin API; it talks to vMenu over local events carrying JSON,
-- and the sender is always GetInvokingResource(), which a payload cannot spoof.
--
-- Payloads are read case-insensitively like upstream's System.Text.Json: each
-- one is rewritten to the protocol's camelCase names once, here, and the rest
-- of client/plugins reads plain fields.

local Log = require('shared.log')
local Json = require('shared.json_compat')
local Config = require('shared.config')
local Platform = require('shared.platform')
local Localization = require('shared.localization')
local PermissionPath = require('shared.permission_path')
local Controller = require('menu.controller')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')
local Arbiter = require('client.framework.arbiter')
local Skin = require('client.framework.skin')
local Notifications = require('client.framework.notifications')
local Input = require('client.framework.input')
local State = require('client.plugins.state')
local Validation = require('client.plugins.validation')
local Factory = require('client.plugins.entry_factory')
local UpdateOps = require('client.plugins.update_ops')

local PluginHost = {}

local PROTOCOL_VERSION = 3
local MAX_STANDALONE_MENUS = 50
local MIN_NOTIFY_DURATION_MS = 5000
local MAX_NOTIFY_DURATION_MS = 30000
local MAX_PROMPT_LENGTH = 500
local DEFAULT_PROMPT_LENGTH = 60
local MAX_THEMES_PER_RESOURCE = 25
local MAX_PARENT_DEPTH = 32
local PREFIX = 'vMenu.Enhanced:Plugins'
local PERMISSION_PREFIX = 'vMenu.Enhanced.Plugins'

local plugins = {} -- lowercased resource -> state
local pending = {} -- lowercased resource -> { resource, json }
local last_payload = {} -- lowercased resource -> json
local listened_convars = {}
local plugins_builder
local handlers_registered = false
local ready = false
local prompt_busy = false

local is_text = State.is_text

local function event_for(resource, suffix)
    return ('%s:%s:%s'):format(PREFIX, resource, suffix)
end

-- Payloads ---------------------------------------------------------------------------

-- Every property name in the protocol's contracts.
local FIELDS = {
    -- RegisterRequest, SettingNode
    'protocolVersion',
    'displayName',
    'descriptionKey',
    'translations',
    'settings',
    'menu',
    'standaloneMenus',
    'playerActions',
    'name',
    'type',
    'default',
    'description',
    -- MenuNode, ItemNode, KeyNode, GateNode, TextRef
    'id',
    'title',
    'subtitle',
    'events',
    'items',
    'keys',
    'text',
    'label',
    'lockedDescription',
    'gate',
    'behaviour',
    'leftIcon',
    'rightIcon',
    'visible',
    'enabled',
    'log',
    'checked',
    'checkStyle',
    'options',
    'selectedIndex',
    'min',
    'max',
    'position',
    'showDivider',
    'value',
    'confirmationDescription',
    'defaultKey',
    'defaultButton',
    'shadowedControl',
    'permission',
    'setting',
    'all',
    'any',
    'key',
    'args',
    -- UpdateBatch, UpdateOp
    'ops',
    'op',
    'itemId',
    'menuId',
    'keyId',
    'textValue',
    'flag',
    'index',
    'itemIds',
    'beforeItemId',
    'language',
    'entries',
    'priority',
    'doNotClose',
    'requestId',
    -- PromptRequest, NotifyRequest, themes
    'prompts',
    'maxLength',
    'initial',
    'suggestions',
    'style',
    'durationMs',
    'theme',
    'themes',
    'css',
    'banner',
}

local CANONICAL = {}
for _, name in ipairs(FIELDS) do
    CANONICAL[name:lower()] = name
end

-- Dictionaries whose keys are the plugin's own (translation keys), left as sent.
local OPAQUE = { translations = true, entries = true }

-- keep_keys: the table's keys are the plugin's own names (args), its values are not.
local function canonical(value, keep_keys)
    if type(value) ~= 'table' then
        return value
    end
    local out = {}
    for key, field in pairs(value) do
        if type(key) ~= 'string' or keep_keys then
            out[key] = canonical(field)
        else
            local name = CANONICAL[key:lower()] or key
            if OPAQUE[name] then
                out[name] = field
            else
                out[name] = canonical(field, name == 'args')
            end
        end
    end
    return out
end

local function decode(json)
    local value = Json.decode(json)
    if type(value) ~= 'table' then
        return nil
    end
    return canonical(value)
end

-- Replies ----------------------------------------------------------------------------

local function add(list, message, ...)
    list[#list + 1] = message:format(...)
end

local function new_report()
    return { accepted = true, errors = {}, warnings = {} }
end

local function refused(reason)
    return { accepted = false, errors = { reason }, warnings = {} }
end

-- By hand: an empty Lua table could encode as {}, which the plugin APIs'
-- typed lists refuse.
local function encode_report(report)
    return ('{"accepted":%s,"protocolVersion":%d,"errors":%s,"warnings":%s}'):format(
        report.accepted and 'true' or 'false',
        PROTOCOL_VERSION,
        Json.string_array(report.errors),
        Json.string_array(report.warnings)
    )
end

local function reply(resource, report)
    TriggerEvent(event_for(resource, 'RegisterResult'), encode_report(report))
end

local function theme_list()
    local themes = {}
    for _, choice in ipairs(Skin.choices()) do
        themes[#themes + 1] = Json.encode({ id = choice.id, name = choice.name })
    end
    return ('{"themes":[%s],"current":%s,"configured":%s,"overridden":%s}'):format(
        table.concat(themes, ','),
        Json.encode(Skin.current_id()),
        Json.encode(Skin.configured_id()),
        Skin.is_overridden() and 'true' or 'false'
    )
end

local function send_themes(resource)
    TriggerEvent(event_for(resource, 'Themes'), theme_list())
end

local function broadcast_themes()
    if next(plugins) == nil then
        return
    end
    local json = theme_list()
    for _, state in pairs(plugins) do
        TriggerEvent(event_for(state.resource, 'Themes'), json)
    end
end

local function sender()
    local resource = GetInvokingResource()
    if resource == nil or resource == '' or resource == GetCurrentResourceName() then
        Log.warning('[Plugins] Ignored a plugin event without an invoking resource.')
        return nil
    end
    return resource
end

-- The Plugins menu -------------------------------------------------------------------

local function refresh_main_menu()
    local main = Registry.main_menu()
    if main then
        Registry.refresh(main)
    end
    Registry.back_out_if_unreachable()
end

local function row_description(state)
    local text = Localization.get('plugins.row.desc'):gsub('{resource}', function()
        return state.resource
    end)
    if state.description_ref then
        text = text .. '~n~' .. state:resolve(state.description_ref)
    end
    return text
end

local function create_row(state, root)
    return Entries.submenu({
        text = Localization.from(function()
            return state:display_name_text()
        end),
        description = Localization.from(function()
            return row_description(state)
        end),
        menu_title = Localization.from(function()
            return root.title ~= nil and state:resolve(root.title) or state:display_name_text()
        end),
        menu_subtitle = Factory.live(state, function()
            return root.subtitle
        end),
        build = function(builder)
            Factory.build_menu(state, root, builder)
        end,
    })
end

-- 0-based: before the first row whose resource sorts after this one.
local function row_index(builder, state)
    local name = state.resource:lower()
    for index, entry in ipairs(builder.entries) do
        for _, other in pairs(plugins) do
            if other.row == entry and other.resource:lower() > name then
                return index - 1
            end
        end
    end
    return #builder.entries
end

local function place_row(state, previous)
    local builder = plugins_builder
    if not builder then
        return
    end
    builder:update(function()
        if previous and previous.row then
            builder:remove(previous.row)
            previous.row = nil
        end
        local root = state.root_menu
        if not (root and #root.items > 0) then
            return
        end
        state.row = create_row(state, root)
        builder:insert(row_index(builder, state), state.row)
    end)
end

function PluginHost.materialise_row(state)
    if state.row == nil then
        place_row(state, nil)
    end
end

function PluginHost.refresh_row(state)
    if state.row and plugins_builder then
        plugins_builder:refresh()
    end
end

function PluginHost.attach_plugins_menu(builder)
    plugins_builder = builder
end

function PluginHost.count()
    local count = 0
    for _ in pairs(plugins) do
        count = count + 1
    end
    return count
end

-- Standalone menus -------------------------------------------------------------------

local function build_standalone(state, standalone)
    local node = standalone.node
    standalone.menu = Registry.create_standalone(
        Localization.from(function()
            return node.title ~= nil and state:resolve(node.title) or state:display_name_text()
        end),
        Factory.live(state, function()
            return node.subtitle
        end),
        function(builder)
            Factory.build_menu(state, node, builder)
        end,
        'PluginsMenu'
    )
end

local function remove_standalone(state)
    for _, standalone in ipairs(state.standalone) do
        if standalone.menu then
            standalone.menu.remove()
            standalone.menu = nil
        end
    end
end

function PluginHost.add_standalone(state, menu, report)
    if #state.standalone >= MAX_STANDALONE_MENUS then
        add(
            report.warnings,
            "Standalone menu '%s' was skipped: a plugin may declare at most %d.",
            tostring(menu.id),
            MAX_STANDALONE_MENUS
        )
        return
    end
    if not is_text(menu.id) or state.menus_by_id[menu.id] then
        add(report.warnings, "Standalone menu '%s' was skipped: its id is empty or already used.", tostring(menu.id))
        return
    end
    if not Validation.index_late_menu_tree(state, menu, report) then
        return
    end
    local standalone = { node = menu }
    state.standalone[#state.standalone + 1] = standalone
    build_standalone(state, standalone)
end

local function index_standalone(state, menus, report)
    if type(menus) ~= 'table' or #menus == 0 then
        return true
    end
    if #menus > MAX_STANDALONE_MENUS then
        add(
            report.errors,
            'A plugin may declare at most %d standalone menus, this one declared %d.',
            MAX_STANDALONE_MENUS,
            #menus
        )
        return false
    end
    for _, menu in ipairs(menus) do
        if not Validation.index_menu_tree(state, menu, report) then
            return false
        end
        state.standalone[#state.standalone + 1] = { node = menu }
    end
    return true
end

-- Menu events from the arbiter -------------------------------------------------------

local function find(menu)
    for _, state in pairs(plugins) do
        local menu_id = state:menu_id_of(menu)
        if menu_id then
            return menu_id, state
        end
    end
    return nil
end

local function emit_menu_callback(menu, kind, subscription)
    local menu_id, state = find(menu)
    local node = menu_id and state.menus_by_id[menu_id]
    if node and Factory.wants(node.events, subscription) then
        state:emit({ type = kind, menuId = menu_id })
    end
end

local function on_replacing(menu)
    local current = menu
    for _ = 1, MAX_PARENT_DEPTH do
        if current == nil then
            return
        end
        emit_menu_callback(current, 'menuReplaced', 'replaced')
        current = current.ParentMenu
    end
end

local function close_if_inside(state)
    local open = Controller.GetCurrentMenu()
    if open and state:menu_id_of(open) then
        Arbiter.release_for(state.resource)
        Controller.CloseAllMenus()
    end
end

-- Registration -----------------------------------------------------------------------

local function copy_translations(state, request, report)
    if type(request.translations) ~= 'table' or next(request.translations) == nil then
        return true
    end
    for language, entries in pairs(request.translations) do
        if type(language) == 'string' and type(entries) == 'table' then
            local copy = {}
            for key, text in pairs(entries) do
                copy[key] = text
            end
            state.translations[language:match('^%s*(.-)%s*$'):lower()] = copy
        end
    end
    if state.translations.en then
        return true
    end
    report.accepted = false
    report.errors[#report.errors + 1] =
        "Translations were provided without an 'en' table. English is the required fallback."
    return false
end

-- Only bool settings can gate a row, so only those are read on the client.
local function track_settings(state, nodes, report)
    if type(nodes) ~= 'table' then
        return
    end
    for _, node in ipairs(nodes) do
        local name = type(node) == 'table' and node.name
        if type(name) ~= 'string' or not Config.is_valid_segment(name) then
            add(
                report.warnings,
                "Setting '%s' was skipped: names may only contain letters, digits and underscores.",
                tostring(name)
            )
        elseif (node.type or 'bool') == 'bool' then
            local convar = PERMISSION_PREFIX .. '.' .. state.id .. '.' .. name
            state.bool_settings[name:lower()] = {
                convar = convar,
                default = type(node.default) == 'string' and node.default:lower() == 'true',
            }
            if not listened_convars[convar:lower()] and Platform.has('AddConvarChangeListener') then
                listened_convars[convar:lower()] = true
                AddConvarChangeListener(convar, function()
                    Registry.refresh_all()
                end)
            end
        end
    end
end

local function register(resource, json)
    local key = resource:lower()
    if last_payload[key] == json and plugins[key] then
        reply(resource, new_report())
        send_themes(resource)
        return
    end
    local request = decode(json)
    if not request then
        reply(resource, refused('The registration payload did not parse.'))
        return
    end
    local version = tonumber(request.protocolVersion) or PROTOCOL_VERSION
    if version > PROTOCOL_VERSION then
        reply(
            resource,
            refused(
                ('The plugin speaks protocol %d but this vMenu only knows %d. '):format(version, PROTOCOL_VERSION)
                    .. 'Update vMenu or use an older plugin API package.'
            )
        )
        return
    end
    local id = PermissionPath.plugin_id(resource)
    if id == '' then
        reply(resource, refused(("The resource name '%s' cannot be turned into a usable identity."):format(resource)))
        return
    end
    for _, other in pairs(plugins) do
        if other.id:lower() == id:lower() and other.resource:lower() ~= key then
            reply(
                resource,
                refused(
                    ("The identity '%s' is already taken by resource '%s'. Rename one of the two resources."):format(
                        id,
                        other.resource
                    )
                )
            )
            return
        end
    end

    local report = new_report()
    local state = State.new(resource, id)
    if not copy_translations(state, request, report) then
        reply(resource, report)
        return
    end
    state.display_name = request.displayName
    state.description_ref = is_text(request.descriptionKey) and { key = request.descriptionKey } or nil
    if request.menu ~= nil and not Validation.index_menu_tree(state, request.menu, report) then
        report.accepted = false
        reply(resource, report)
        return
    end
    if not index_standalone(state, request.standaloneMenus, report) then
        report.accepted = false
        reply(resource, report)
        return
    end
    track_settings(state, request.settings, report)
    state.root_menu = request.menu
    for _, action in ipairs(type(request.playerActions) == 'table' and request.playerActions or {}) do
        if type(action) == 'table' and Validation.index_player_action(state, action, report) then
            state.player_actions[#state.player_actions + 1] = action
        end
    end

    local replaced = plugins[key]
    if replaced then
        close_if_inside(replaced)
        remove_standalone(replaced)
    end
    plugins[key] = state
    last_payload[key] = json
    place_row(state, replaced)
    for _, standalone in ipairs(state.standalone) do
        build_standalone(state, standalone)
    end
    if not replaced then
        if PluginHost.count() == 1 then
            refresh_main_menu()
        end
        Log.info(("[Plugins] Registered '%s'."):format(resource))
    else
        Log.debug(("[Plugins] '%s' re-registered."):format(resource))
    end
    reply(resource, report)
    send_themes(resource)
end

local function apply_registration(resource, json)
    local ok, err = pcall(register, resource, json)
    if not ok then
        Log.error(("[Plugins] Registration from '%s' failed: %s"):format(resource, tostring(err)))
        reply(resource, refused('vMenu hit an internal error: ' .. tostring(err)))
    end
end

local function teardown(resource)
    local key = resource:lower()
    pending[key] = nil
    last_payload[key] = nil
    local state = plugins[key]
    if not state then
        return
    end
    plugins[key] = nil
    close_if_inside(state)
    remove_standalone(state)
    Log.info(("[Plugins] '%s' unregistered, removing its menus."):format(resource))
    if plugins_builder and state.row then
        plugins_builder:remove(state.row)
    end
    state.row = nil
    if next(plugins) == nil then
        refresh_main_menu()
    end
end

-- Event handlers ---------------------------------------------------------------------

local function on_probe()
    local resource = ready and sender()
    if resource then
        TriggerEvent(event_for(resource, 'Ready'), PROTOCOL_VERSION)
    end
end

local function on_register(json)
    local resource = sender()
    if not resource then
        return
    end
    if not ready then
        pending[resource:lower()] = { resource = resource, json = json }
        return
    end
    apply_registration(resource, json)
end

local function on_unregister()
    local resource = sender()
    if resource then
        teardown(resource)
    end
end

local function on_resource_stop(stopped)
    local themes = Skin.remove_custom_from(stopped)
    if themes > 0 then
        Log.info(("[Plugins] '%s' stopped, dropping %d theme(s) it provided."):format(stopped, themes))
    end
    local key = stopped:lower()
    if plugins[key] or pending[key] then
        teardown(stopped)
    end
end

local function registered_sender(what)
    local resource = sender()
    if not resource then
        return nil
    end
    local state = plugins[resource:lower()]
    if not state then
        Log.warning(("[Plugins] '%s' %s but is not registered."):format(resource, what))
    end
    return resource, state
end

local function on_update(json)
    local resource, state = registered_sender('sent an update')
    if not state then
        return
    end
    local batch = decode(json)
    if not batch then
        Log.warning(("[Plugins] An update from '%s' did not parse."):format(resource))
        return
    end
    local ok, err = pcall(UpdateOps.apply, state, batch)
    if not ok then
        Log.error(("[Plugins] An update from '%s' failed: %s"):format(resource, tostring(err)))
    end
end

local NOTIFY_STYLES = { success = true, warning = true, error = true, info = true }

local function on_notify(json)
    local resource, state = registered_sender('sent a notification (use the vmenu:notify event instead)')
    local request = state and decode(json)
    if not request then
        return
    end
    local wanted = math.tointeger(request.durationMs)
    local duration = (wanted and wanted > 0) and wanted or Notifications.DEFAULT_DURATION_MS
    duration = math.max(MIN_NOTIFY_DURATION_MS, math.min(MAX_NOTIFY_DURATION_MS, duration))
    local style = type(request.style) == 'string' and request.style:lower() or 'info'
    Notifications.show(NOTIFY_STYLES[style] and style or 'info', state:resolve(request.text), duration, resource)
end

local function reply_prompt(resource, result)
    local answers = result.answers and (',"answers":' .. Json.string_array(result.answers)) or ''
    TriggerEvent(
        event_for(resource, 'PromptResult'),
        ('{"requestId":%d,"cancelled":%s,"busy":%s%s}'):format(
            result.request_id,
            result.cancelled and 'true' or 'false',
            result.busy and 'true' or 'false',
            answers
        )
    )
end

local function ask(resource, state, request)
    local prompts = {}
    for index, prompt in ipairs(request.prompts) do
        local suggestions
        if type(prompt.suggestions) == 'table' then
            suggestions = {}
            for at, suggestion in ipairs(prompt.suggestions) do
                local value = tostring(suggestion.value or '')
                suggestions[at] = {
                    value = value,
                    label = is_text(suggestion.description) and suggestion.description or value,
                }
            end
        end
        prompts[index] = {
            title = Factory.text_for(state, prompt.title),
            max_length = math.max(
                1,
                math.min(MAX_PROMPT_LENGTH, math.tointeger(prompt.maxLength) or DEFAULT_PROMPT_LENGTH)
            ),
            initial_value = prompt.initial ~= nil and tostring(prompt.initial) or '',
            suggestions = suggestions,
        }
    end
    local answers = Input.get_texts(prompts)
    reply_prompt(resource, { request_id = request.requestId, cancelled = answers == nil, answers = answers })
end

local function on_prompt(json)
    local resource = sender()
    if not resource then
        return
    end
    local request = decode(json)
    if not request or type(request.prompts) ~= 'table' or #request.prompts == 0 then
        Log.warning(("[Plugins] A prompt from '%s' did not parse, so it cannot be answered."):format(resource))
        return
    end
    request.requestId = math.tointeger(request.requestId) or 0
    local state = plugins[resource:lower()]
    if not state then
        Log.warning(("[Plugins] '%s' asked for input but is not registered."):format(resource))
        reply_prompt(resource, { request_id = request.requestId, cancelled = true })
        return
    end
    if prompt_busy then
        reply_prompt(resource, { request_id = request.requestId, cancelled = true, busy = true })
        return
    end
    prompt_busy = true
    -- Input.get_texts waits for the player, so it needs its own thread.
    CreateThread(function()
        local ok, err = pcall(ask, resource, state, request)
        if not ok then
            Log.error(("[Plugins] A prompt for '%s' failed: %s"):format(resource, tostring(err)))
            reply_prompt(resource, { request_id = request.requestId, cancelled = true })
        end
        prompt_busy = false
    end)
end

local function on_set_theme(json)
    local resource, state = registered_sender('asked for a theme')
    if not state then
        return
    end
    local request = decode(json)
    if not request then
        Log.warning(("[Plugins] A theme request from '%s' did not parse."):format(resource))
        return
    end
    if not is_text(request.theme) then
        Skin.clear_override()
        return
    end
    if Skin.apply_override(request.theme) then
        return
    end
    Log.warning(
        ("[Plugins] '%s' asked for theme '%s', which vMenu does not know about."):format(resource, request.theme)
    )
    send_themes(resource)
end

local function reply_themes(resource, report)
    TriggerEvent(event_for(resource, 'ThemesRegistered'), encode_report(report))
end

local function on_register_themes(json)
    local resource = sender()
    if not resource then
        return
    end
    local request = decode(json)
    if not request then
        Log.warning(("[Plugins] The themes from '%s' did not parse."):format(resource))
        reply_themes(resource, refused('The theme payload did not parse. It has to be JSON.'))
        return
    end
    Skin.remove_custom_from(resource)
    local report = new_report()
    local themes = type(request.themes) == 'table' and request.themes or {}
    local accepted = 0
    for _, theme in ipairs(themes) do
        if accepted >= MAX_THEMES_PER_RESOURCE then
            add(report.warnings, 'Only the first %d themes were taken, the rest were skipped.', MAX_THEMES_PER_RESOURCE)
            break
        end
        local ok, err, warning = Skin.register_custom(resource, theme.id, theme.name, theme.css, theme.banner)
        if ok then
            accepted = accepted + 1
            if warning then
                report.warnings[#report.warnings + 1] = warning
                Log.warning(
                    ("[Plugins] The banner of theme '%s' from '%s': %s"):format(tostring(theme.id), resource, warning)
                )
            end
        else
            report.warnings[#report.warnings + 1] = err
            Log.warning(("[Plugins] A theme from '%s' was skipped: %s"):format(resource, err))
        end
    end
    if accepted == 0 and #themes > 0 then
        report.accepted = false
    end
    Log.info(("[Plugins] '%s' provided %d theme(s)."):format(resource, accepted))
    reply_themes(resource, report)
    Skin.refresh()
end

-- Setup ------------------------------------------------------------------------------

function PluginHost.register_events()
    if handlers_registered then
        return
    end
    handlers_registered = true
    AddEventHandler(PREFIX .. ':Probe', on_probe)
    AddEventHandler(PREFIX .. ':Register', on_register)
    AddEventHandler(PREFIX .. ':Unregister', on_unregister)
    AddEventHandler(PREFIX .. ':Update', on_update)
    AddEventHandler(PREFIX .. ':Notify', on_notify)
    AddEventHandler(PREFIX .. ':Prompt', on_prompt)
    AddEventHandler(PREFIX .. ':SetTheme', on_set_theme)
    AddEventHandler(PREFIX .. ':RegisterThemes', on_register_themes)
    AddEventHandler('onResourceStop', on_resource_stop)
    Skin.on_changed(broadcast_themes)
    Arbiter.owner_of = function(menu)
        local _, state = find(menu)
        return state and state.resource or nil
    end
    Arbiter.on_replacing(on_replacing)
    Arbiter.on_force_closed(function(menu)
        emit_menu_callback(menu, 'menuForceClosed', 'forceClosed')
    end)
end

-- After the menus are built: applies what arrived early, then tells every
-- plugin that vMenu is ready for them.
function PluginHost.announce_ready()
    ready = true
    local early = pending
    pending = {}
    for _, registration in pairs(early) do
        apply_registration(registration.resource, registration.json)
    end
    TriggerEvent(PREFIX .. ':Ready', PROTOCOL_VERSION)
end

return PluginHost
