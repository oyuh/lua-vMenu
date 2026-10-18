-- Port of vMenu.Enhanced.MenuFramework/MenuRegistry.cs: builds the menu tree
-- from definitions, and refreshes every menu when permissions, settings or the
-- language change.
--
-- A definition is a table:
--   title, subtitle                  menu text (Registry.definition fills them
--                                    from title_key and subtitle_key)
--   link_text, link_description,     the row that opens it from its parent;
--   link_label, link_behaviour       link_text defaults to title, label to '→'
--   gate                             gates that row, and so the menu
--   default_gate_behaviour           'lock' or 'hide' for its entries
--   prepare()                        optional, runs before build and may Wait
--   build(builder)                   declares the entries (builder is a host)

local Log = require('shared.log')
local Config = require('shared.config')
local Localization = require('shared.localization')
local Permissions = require('client.permissions')
local Gate = require('client.framework.gate')
local Host = require('client.framework.host')
local Entries = require('client.framework.entries')
local Controller = require('menu.controller')
local Menu = require('menu.menu')
local Ticks = require('menu.ticks')

local Registry = {}

-- Settings that cannot change what any menu shows, so they skip the refresh.
local IGNORED_SETTINGS = {
    -- Read once before the menus are built.
    'vMenu.Enhanced.Languages',
    -- Key mappings are registered at startup, so a change needs a restart.
    'vMenu.Enhanced.KeyBindings.MenuToggleKey',
    'vMenu.Enhanced.KeyBindings.NoClipToggleKey',
    'vMenu.Enhanced.KeyBindings.TeleportKey',
}

local hosts = {}
local hosts_by_menu = {}
local root
local built = false

local resolve = Localization.resolve

local function track(host)
    hosts[#hosts + 1] = host
    hosts_by_menu[host.menu] = host
    return host
end

local function remove_value(list, value)
    for index = #list, 1, -1 do
        if list[index] == value then
            table.remove(list, index)
            return
        end
    end
end

-- Fills a definition's text and gate from keys, like the C# [VMenu] attribute:
-- title_key, subtitle_key, description_key, permission, link_label ('→').
function Registry.definition(definition)
    if definition.title_key and definition.title == nil then
        definition.title = Localization.key(definition.title_key)
    end
    if definition.subtitle_key and definition.subtitle == nil then
        definition.subtitle = Localization.key(definition.subtitle_key)
    end
    if definition.description_key and definition.link_description == nil then
        definition.link_description = Localization.key(definition.description_key)
    end
    if definition.permission and definition.gate == nil then
        definition.gate = Gate.permission(definition.permission)
    end
    if definition.link_label == nil then
        definition.link_label = '→'
    end
    return definition
end

local function create_child(parent, submenu, link_item)
    local definition = submenu.definition
    if definition == nil and submenu.build == nil then
        Log.error(
            ("[Menu] Submenu '%s' declares neither a definition nor a build, so it opens nothing."):format(
                resolve(submenu.text)
            )
        )
        return nil
    end
    local title = definition and definition.title or submenu:menu_title()
    local subtitle = definition and definition.subtitle or submenu.menu_subtitle
    local child_menu = Menu.new(resolve(title), Host.resolve_subtitle(title, subtitle))
    Controller.BindMenuItem(parent.menu, child_menu, link_item)
    local child = track(
        Host.new(
            child_menu,
            parent,
            submenu:effective_gate(),
            title,
            subtitle,
            definition and definition.default_gate_behaviour,
            definition and definition.audit_name or parent.audit_name
        )
    )
    parent.children[#parent.children + 1] = child
    if definition then
        definition.build(child)
    else
        submenu.build(child)
    end
    -- Added to, not replacing, whatever the menu itself set during build.
    if submenu.on_opened then
        child:on_opened(submenu.on_opened)
    end
    if submenu.on_opened_async then
        child:on_opened_async(submenu.on_opened_async)
    end
    submenu.child = child
    return child
end

-- Indexed, because a build may append to its own list while child menus
-- underneath it are still being created. Runs in a thread: prepare may Wait.
local function materialise_tree(host, wait_for_prepare)
    local index = 1
    while index <= #host.entries do
        local entry = host.entries[index]
        local item = host:materialise(entry)
        if entry.kind == 'submenu' then
            local definition = entry.definition
            local ready = true
            if definition and definition.prepare then
                if wait_for_prepare then
                    definition.prepare()
                else
                    -- Nowhere to wait from once the parent is live.
                    Log.error(
                        ('[Menu] %s needs preparation, so it cannot be added after its parent menu was built.'):format(
                            tostring(definition.audit_name or resolve(definition.title))
                        )
                    )
                    ready = false
                end
            end
            local child = ready and create_child(host, entry, item)
            if child then
                materialise_tree(child, wait_for_prepare)
            end
        end
        index = index + 1
    end
    host:attach()
end

-- For an entry added once its menu is live.
function Registry.materialise_late(host, entry, position)
    local item = host:materialise(entry, position)
    if entry.kind ~= 'submenu' then
        return nil
    end
    if entry.definition and entry.definition.prepare then
        Log.error('[Menu] A submenu that needs preparation cannot be added after its parent menu was built.')
        return nil
    end
    local child = create_child(host, entry, item)
    if child then
        materialise_tree(child, false)
    end
    return child
end

function Registry.refresh_branch(host)
    host:refresh_with(true)
    host:apply_pending_filter()
    for _, child in ipairs(host.children) do
        Registry.refresh_branch(child)
    end
end

local function drop(host)
    for _, child in ipairs(table.move(host.children, 1, #host.children, 1, {})) do
        drop(child)
    end
    host.children = {}
    host:dispose()
    -- MenuAPI keeps a menu registered until it is removed.
    Controller.RemoveMenu(host.menu)
    remove_value(hosts, host)
    hosts_by_menu[host.menu] = nil
end

function Registry.untrack(host)
    if host.parent then
        remove_value(host.parent.children, host)
    end
    drop(host)
end

function Registry.remove(host)
    host:clear_entries()
    Registry.untrack(host)
end

-- A menu that is not the framework's has no gate to fail.
function Registry.can_open(menu)
    local host = hosts_by_menu[menu]
    return host == nil or host:is_reachable()
end

-- Walks the framework's own parent links, not Menu.ParentMenu: MenuAPI
-- re-parents a child to whatever menu was open when its link was selected.
function Registry.back_out_if_unreachable()
    local open = Controller.GetCurrentMenu()
    local host = open and hosts_by_menu[open]
    if not host or host:is_reachable() then
        return
    end
    local target = host.parent
    while target and not target:is_reachable() do
        target = target.parent
    end
    Controller.CloseAllMenus()
    if target then
        target.menu:OpenMenu()
    end
end

function Registry.refresh_all()
    for _, host in ipairs(hosts) do
        host:refresh()
    end
    Registry.back_out_if_unreachable()
end

-- Only the skin's banner changes, so this skips the full refresh.
function Registry.apply_banner(image)
    for _, host in ipairs(hosts) do
        host.menu.HeaderImage = image
    end
end

function Registry.refresh(menu)
    local host = hosts_by_menu[menu]
    if host then
        host:refresh()
    end
end

function Registry.host_for(menu)
    return hosts_by_menu[menu]
end

function Registry.main_menu()
    return root and root.menu or nil
end

function Registry.create_detached(parent, title, subtitle, gate, build, default_behaviour)
    local menu = Menu.new(resolve(title), Host.resolve_subtitle(title, subtitle))
    Controller.AddSubmenu(parent.menu, menu)
    local child = track(Host.new(menu, parent, gate, title, subtitle, default_behaviour, parent.audit_name))
    parent.children[#parent.children + 1] = child
    build(child)
    -- The parent has no entry for it, so it materialises itself here.
    materialise_tree(child, false)

    local detached = { menu = menu, builder = child }
    function detached.refresh()
        child:refresh()
    end
    function detached.open()
        -- Re-resolved here: what a detached menu says depends on what the
        -- caller just picked, long after the last gating pass.
        child:refresh()
        local current = Controller.GetCurrentMenu()
        if current and current ~= menu then
            Controller.AddSubmenu(current, menu)
            current:CloseMenu()
        end
        menu:OpenMenu()
    end
    function detached.remove()
        Registry.remove(child)
    end
    return detached
end

-- A top level menu outside the main tree, such as a plugin's standalone menu.
function Registry.create_standalone(title, subtitle, build, audit_name)
    local menu = Menu.new(resolve(title), Host.resolve_subtitle(title, subtitle))
    Controller.AddMenu(menu)
    local host = track(Host.new(menu, nil, Gate.ALWAYS, title, subtitle, nil, audit_name))
    build(host)
    materialise_tree(host, false)
    -- Nothing else gates it before it opens: the arbiter opens it directly.
    Registry.refresh_branch(host)
    return {
        menu = menu,
        builder = host,
        remove = function()
            Registry.remove(host)
        end,
    }
end

local function disable_shadowed_controls()
    local open = Controller.GetCurrentMenu()
    local host = open and hosts_by_menu[open]
    if not host then
        return
    end
    for _, key in ipairs(host.keys) do
        if key.shadowed_control then
            DisableControlAction(0, key.shadowed_control, true)
        end
    end
end

-- Builds the main menu and everything under it. Call once, from a thread:
-- definitions' prepare may Wait.
function Registry.build(definitions)
    if built then
        Log.error('[Menu] Registry.build was called twice; the second call is ignored.')
        return
    end
    built = true

    local title = Localization.key('mainmenu.title')
    local subtitle = Localization.key('mainmenu.subtitle')
    local main = Menu.new(resolve(title), Host.resolve_subtitle(title, subtitle))
    Controller.AddMenu(main)
    Controller.MainMenu = main
    root = track(Host.new(main, nil, Gate.ALWAYS, title, subtitle, nil, 'MainMenu'))
    for _, definition in ipairs(definitions) do
        if definition.title == nil then
            Log.error(('[Menu] %s has no title.'):format(tostring(definition.audit_name)))
        end
        -- A submenu entry, so the link, its gate and its menu go through the
        -- same path as every nested submenu.
        root.entries[#root.entries + 1] = Entries.submenu_for(definition)
    end
    materialise_tree(root, true)

    Permissions.on_changed(Registry.refresh_all)
    Config.watch_except(IGNORED_SETTINGS, Registry.refresh_all)
    Localization.on_changed(Registry.refresh_all)
    Ticks.register('Menu.ShadowedControls', disable_shadowed_controls, { condition = Controller.IsAnyMenuOpen })

    -- Items start enabled, so without this everything looks unlocked until
    -- the first permission set lands.
    Registry.refresh_all()
    Log.debug(('[Menu] Built %d menu(s).'):format(#hosts))
end

return Registry
