-- Port of vMenu.Enhanced.Data/Configuration/ConfigCatalog.cs and Settings/*.cs: every
-- setting vMenu knows, in the order and grouping of the generated configuration.cfg.example.
-- Converted from upstream's generated file at the pinned release; port later changes by hand.
-- server_only settings are written with 'set' (never replicated) because they hold secrets.

return {
    {
        title = 'Languages',
        settings = {
            {
                name = 'vMenu.Enhanced.Languages',
                type = 'string',
                default = 'nl,de,es,fr',
                description = "The languages players can pick, as a comma separated list of file names without .json, in picker order. Each code needs a matching language/<code>.json. To add one, copy language/example.json to language/<code>.json, translate it, and list the code here. Don't include 'en' (English is built in and always available), nor use 'example' (a template file that is rewritten on every vMenu update).",
            },
        },
    },
    {
        title = 'About',
        settings = {
            {
                name = 'vMenu.Enhanced.DocumentationUrl',
                type = 'string',
                default = 'https://docs.vespura.com/vmenu/enhanced',
                description = "The documentation link shown in the About menu. Change this if you'd like to have your own server documentation listed here.",
            },
            {
                name = 'vMenu.Enhanced.DiscordUrl',
                type = 'string',
                default = 'https://discord.gg/fivem',
                description = 'The Discord invite link shown in the About menu.',
            },
        },
    },
    {
        title = 'Updates',
        settings = {
            {
                name = 'vMenu.Enhanced.Updates.CheckMode',
                type = 'string',
                default = 'prerelease',
                description = "Configures the automatic version checks vMenu performs. Can be set to 'off', 'prerelease' or 'stable'.",
            },
        },
    },
    {
        title = 'Key Bindings',
        settings = {
            {
                name = 'vMenu.Enhanced.KeyBindings.MenuToggleKey',
                type = 'string',
                default = 'M',
                description = 'The default key that opens and closes the menu. Use a key name from https://docs.fivem.net/docs/game-references/input-mapper-parameter-ids/keyboard/. This is only the default key: players can rebind it themselves under Settings, Key Bindings',
            },
            {
                name = 'vMenu.Enhanced.KeyBindings.NoClipToggleKey',
                type = 'string',
                default = 'F2',
                description = 'The default key that turns noclip on and off. Use a key name from https://docs.fivem.net/docs/game-references/input-mapper-parameter-ids/keyboard/. This is only the default key: players can rebind it themselves under Settings, Key Bindings',
            },
            {
                name = 'vMenu.Enhanced.KeyBindings.TeleportKey',
                type = 'string',
                default = 'F10',
                description = "The default key that runs the 'teleport action' (see teleportation menu in-game) Use a key name from https://docs.fivem.net/docs/game-references/input-mapper-parameter-ids/keyboard/. This is only the default key: players can rebind it themselves under Settings, Key Bindings",
            },
        },
    },
    {
        title = 'Menu Appearance',
        settings = {
            {
                name = 'vMenu.Enhanced.MenuAppearance.Skin',
                type = 'string',
                default = 'default',
                description = "Choose a default theme: 'default', 'dark', 'cartoon' or 'gta'. You can also choose any plugin-added theme here.",
            },
            {
                name = 'vMenu.Enhanced.MenuAppearance.TitleAlignment',
                type = 'string',
                default = 'left',
                description = "Where the title sits on the banner: 'left', 'center' or 'right'.",
            },
            {
                name = 'vMenu.Enhanced.MenuAppearance.HeaderGlare',
                type = 'bool',
                default = true,
                description = "Enables or disables the Globe in the menu header and the glare effect, like GTA Online's interaction menu.",
            },
        },
    },
    {
        title = 'Gameplay',
        settings = {
            {
                name = 'vMenu.Enhanced.Gameplay.PvpMode',
                type = 'int',
                default = 1,
                description = '0 = vMenu does not touch PVP, 1 = PVP Enabled, 2 = PVP Disabled.',
            },
        },
    },
    {
        title = 'Admin',
        settings = {
            {
                name = 'vMenu.Enhanced.Admin.ClearAreaRadius',
                type = 'int',
                default = 100,
                description = 'How far around a player, in metres, the Clear Area button reaches.',
            },
            {
                name = 'vMenu.Enhanced.Admin.ClosestPlayerRange',
                type = 'int',
                default = 3,
                description = 'How far away, in metres, the freeze and grab buttons will find a nearby player.',
            },
            {
                name = 'vMenu.Enhanced.Admin.ScheduledAnnouncements',
                type = 'bool',
                default = true,
                description = 'Turns the announcement schedule in config/announcements.json on or off.',
            },
            {
                name = 'vMenu.Enhanced.Admin.AnnouncementSeconds',
                type = 'int',
                default = 20,
                description = 'How long an announcement stays on screen, in seconds.',
            },
        },
    },
    {
        title = 'Staff Alerts',
        settings = {
            {
                name = 'vMenu.Enhanced.StaffAlerts.Enabled',
                type = 'bool',
                default = true,
                description = "Allows players to alert staff via the 'Alert staff' button in the misc settings.",
            },
            {
                name = 'vMenu.Enhanced.StaffAlerts.CooldownSeconds',
                type = 'int',
                default = 60,
                description = 'How long one player has to wait between sending multiple alerts, in seconds. This is to prevent spam.',
            },
            {
                name = 'vMenu.Enhanced.StaffAlerts.ExpireSeconds',
                type = 'int',
                default = 300,
                description = 'This is how long an alert will stay active before it is discarded in seconds.',
            },
            {
                name = 'vMenu.Enhanced.StaffAlerts.DisplaySeconds',
                type = 'int',
                default = 30,
                description = 'How long an alert stays visible on screen in seconds. You can always see all active alerts in the staff alerts menu.',
            },
        },
    },
    {
        title = 'Online Players',
        settings = {
            {
                name = 'vMenu.Enhanced.OnlinePlayers.ActionLimit',
                type = 'int',
                default = 8,
                description = 'How many things one player may do to other players from the online players menu within the time window below.',
            },
            {
                name = 'vMenu.Enhanced.OnlinePlayers.ActionLimitSeconds',
                type = 'int',
                default = 10,
                description = 'The length of the window the allowance above is counted over, in seconds. With the defaults, a player gets 8 actions per 10 seconds.',
            },
            {
                name = 'vMenu.Enhanced.OnlinePlayers.MatchRoutingBucket',
                type = 'bool',
                default = true,
                description = "Whether teleporting to a player, teleporting into their vehicle, and summoning a player should also move somebody into the other player's routing bucket. Routing buckets are separate worlds or dimensions (usually used for interiors).",
            },
        },
    },
    {
        title = 'Join and Leave',
        settings = {
            {
                name = 'vMenu.Enhanced.JoinLeave.LogToConsole',
                type = 'bool',
                default = true,
                description = 'Logs player connections to the server console.',
            },
        },
    },
    {
        title = 'Webhook Logging',
        settings = {
            {
                name = 'vMenu.Enhanced.Logging.Enabled',
                type = 'bool',
                default = false,
                description = 'Enables or disables all the webhooks, regardless of what you configured below.',
            },
            {
                name = 'vMenu.Enhanced.Logging.Webhook.Events',
                type = 'string',
                default = '',
                server_only = true,
                description = "A Discord webhook URL for server events. Use 'set' instead of 'setr' to keep your webhook URL secure.",
            },
            {
                name = 'vMenu.Enhanced.Logging.Webhook.Actions',
                type = 'string',
                default = '',
                server_only = true,
                description = "A Discord webhook URL for what players do to themselves. Chatty on a busy server, so give it its own channel. Use 'set' instead of 'setr' to keep your webhook URL secure.",
            },
            {
                name = 'vMenu.Enhanced.Logging.Webhook.Staff',
                type = 'string',
                default = '',
                server_only = true,
                description = "A Discord webhook URL for what players do to each other, including attempts refused for lack of permission. Use 'set' instead of 'setr' to keep your webhook URL secure.",
            },
            {
                name = 'vMenu.Enhanced.Logging.Webhook.Security',
                type = 'string',
                default = '',
                server_only = true,
                description = "A Discord webhook URL when possible cheating is detected. If you leave this empty, the events will be sent to the staff webhook instead. Use 'set' instead of 'setr' to keep your webhook URL secure.",
            },
            {
                name = 'vMenu.Enhanced.Logging.Webhook.Generic',
                type = 'string',
                default = '',
                server_only = true,
                description = "A URL that receives the same lines as plain JSON instead of Discord messages, for your own tooling. If it uses HTTPS, the certificate must be valid and trusted. Use 'set' instead of 'setr' to keep your webhook URL secure.",
            },
            {
                name = 'vMenu.Enhanced.Logging.FlushSeconds',
                type = 'int',
                default = 4,
                description = 'How often vMenu sends what it has collected, in seconds. Lines are batched instead of sent one at a time, since Discord throttles you for posting too fast. Values outside 1 to 60 are clamped to that range.',
            },
            {
                name = 'vMenu.Enhanced.Logging.QueueLimit',
                type = 'int',
                default = 500,
                description = "How many lines vMenu holds per webhook while waiting to send. Past this the oldest are dropped, and the next message through says how many. Stops an unresponsive webhook eating your server's memory.",
            },
            {
                name = 'vMenu.Enhanced.Logging.MenuActionLimit',
                type = 'int',
                default = 30,
                description = "(Rate limiting) How many menu actions one player may log per window. These are reported by the player's own game, so this stops a modified client filling your channel. Set to 0 to turn the limit off, not recommended.",
            },
            {
                name = 'vMenu.Enhanced.Logging.MenuActionLimitSeconds',
                type = 'int',
                default = 10,
                description = 'How long the menu action window above lasts, in seconds.',
            },
            {
                name = 'vMenu.Enhanced.Logging.SecurityLimit',
                type = 'int',
                default = 10,
                description = 'How many security lines one player may log per window. A modified client can try thousands of things a second, and this stops that filling your channel. The next line through says how many were left out. Set to 0 to turn the limit off, not recommended.',
            },
            {
                name = 'vMenu.Enhanced.Logging.SecurityLimitSeconds',
                type = 'int',
                default = 60,
                description = 'How long the security window above lasts, in seconds.',
            },
        },
    },
    {
        title = 'Player Stats',
        settings = {
            {
                name = 'vMenu.Enhanced.PlayerOptions.MaxShooting',
                type = 'int',
                default = 100,
                description = 'Max shooting ability stat value, as a percentage. A player can still pick a higher number but vMenu will only apply it up to the limits configured here.',
            },
            {
                name = 'vMenu.Enhanced.PlayerOptions.MaxStrength',
                type = 'int',
                default = 100,
                description = 'Max strength stat value, as a percentage. A player can still pick a higher number but vMenu will only apply it up to the limits configured here.',
            },
            {
                name = 'vMenu.Enhanced.PlayerOptions.MaxStamina',
                type = 'int',
                default = 100,
                description = 'Max stamina stat value, as a percentage. A player can still pick a higher number but vMenu will only apply it up to the limits configured here.',
            },
            {
                name = 'vMenu.Enhanced.PlayerOptions.MaxStealth',
                type = 'int',
                default = 100,
                description = 'Max stealth ability stat value, as a percentage. A player can still pick a higher number but vMenu will only apply it up to the limits configured here.',
            },
            {
                name = 'vMenu.Enhanced.PlayerOptions.MaxFlying',
                type = 'int',
                default = 100,
                description = 'Max flying ability stat value, as a percentage. A player can still pick a higher number but vMenu will only apply it up to the limits configured here.',
            },
            {
                name = 'vMenu.Enhanced.PlayerOptions.MaxDriving',
                type = 'int',
                default = 100,
                description = 'Max driving ability stat value, as a percentage. A player can still pick a higher number but vMenu will only apply it up to the limits configured here.',
            },
            {
                name = 'vMenu.Enhanced.PlayerOptions.MaxLungCapacity',
                type = 'int',
                default = 100,
                description = 'Max lung capacity stat value, as a percentage. A player can still pick a higher number but vMenu will only apply it up to the limits configured here.',
            },
        },
    },
    {
        title = 'Vehicle Options',
        settings = {
            {
                name = 'vMenu.Enhanced.VehicleOptions.DeleteVehicleDistance',
                type = 'float',
                default = 5.0,
                description = 'Distance in meters how far away the /dv command (and menu delete vehicle action) reaches for cars in front of the player.',
            },
            {
                name = 'vMenu.Enhanced.VehicleOptions.DeleteVehicleCommand',
                type = 'bool',
                default = true,
                description = 'Enables or disables the /dv command from vMenu. Uses the same permission as the delete vehicle option inside the vehicle options menu.',
            },
            {
                name = 'vMenu.Enhanced.VehicleOptions.RepairVehicleCommand',
                type = 'bool',
                default = true,
                description = 'Enables the /fixveh command to quickly repair a vehicle. Uses the same permission as the fix vehicle option inside the vehicle options menu.',
            },
            {
                name = 'vMenu.Enhanced.VehicleOptions.WashVehicleCommand',
                type = 'bool',
                default = true,
                description = 'Enables the /washveh command to quickly clean a vehicle. Uses the same permission as the clean vehicle option inside the vehicle options menu.',
            },
            {
                name = 'vMenu.Enhanced.VehicleOptions.ClearGodModeOnExit',
                type = 'bool',
                default = true,
                description = 'When set to true, it disables vehicle god mode for a vehicle as soon as the driver leaves the car (if they had vehicle god mode enabled).',
            },
        },
    },
    {
        title = 'Personal Vehicle',
        settings = {
            {
                name = 'vMenu.Enhanced.PersonalVehicle.ActionLimit',
                type = 'int',
                default = 8,
                description = 'Rate limit of personal vehicle remote actions within the configured time limit. Zero means no limit.',
            },
            {
                name = 'vMenu.Enhanced.PersonalVehicle.ActionLimitSeconds',
                type = 'int',
                default = 10,
                description = 'Time in seconds for the rate limit from above. With the default values that would be 8 actions within 10 seconds. Zero switches the limit off entirely.',
            },
            {
                name = 'vMenu.Enhanced.PersonalVehicle.ControlRange',
                type = 'float',
                default = 350.0,
                description = 'Leave this as 350.0 for now, this convar only exists for debugging purposes.',
            },
            {
                name = 'vMenu.Enhanced.PersonalVehicle.ControlTimeout',
                type = 'int',
                default = 1500,
                description = "Just leave this at 1500 unless you know what you're doing. Timeout for moving on to the next client to try and act on a vehicle within range. Three players are tried before giving up, so keep this under 5 seconds.",
            },
        },
    },
    {
        title = 'Vehicle Spawner',
        settings = {
            {
                name = 'vMenu.Enhanced.VehicleSpawner.OrphanMode',
                type = 'int',
                default = 1,
                description = 'What the server does to a vehicle if the player that spawned it leaves the server or crashes their game. DeleteWhenNotRelevant = 0, DeleteOnOwnerDisconnect = 1, KeepEntity = 2.',
            },
            {
                name = 'vMenu.Enhanced.VehicleSpawner.KeepSpawnedVehiclesPersistent',
                type = 'bool',
                default = false,
                description = 'Keeps a vehicle a player spawned loaded after they spawn another one with Replace Previous Vehicle turned off, instead of letting the game clean it up on its own. Turning this on means abandoned vehicles pile up until somebody deletes them.',
            },
            {
                name = 'vMenu.Enhanced.VehicleSpawner.SpawnLimitSeconds',
                type = 'int',
                default = 60,
                description = 'The stretch of time, in seconds, the three allowances below are counted over. Set this to zero to switch spawn limits off entirely.',
            },
            {
                name = 'vMenu.Enhanced.VehicleSpawner.SpawnLimitTier1',
                type = 'int',
                default = 5,
                description = 'How many vehicles a tier 1 player may spawn within the window above. Zero means no limit.',
            },
            {
                name = 'vMenu.Enhanced.VehicleSpawner.SpawnLimitTier2',
                type = 'int',
                default = 15,
                description = 'How many vehicles a tier 2 player may spawn within the window above. Zero means no limit.',
            },
            {
                name = 'vMenu.Enhanced.VehicleSpawner.SpawnLimitTier3',
                type = 'int',
                default = 0,
                description = 'How many vehicles a tier 3 player may spawn within the window above. Zero means no limit.',
            },
        },
    },
    {
        title = 'Weather Options',
        settings = {
            {
                name = 'vMenu.Enhanced.WeatherOptions.Enabled',
                type = 'bool',
                default = true,
                description = "Enables or disables vMenu's weather control and sync. Turn this off if you want another resource to control the weather.",
            },
            {
                name = 'vMenu.Enhanced.WeatherOptions.SyncClouds',
                type = 'bool',
                default = true,
                description = 'Syncs clouds with all players.',
            },
            {
                name = 'vMenu.Enhanced.WeatherOptions.TransitionSeconds',
                type = 'int',
                default = 45,
                description = 'How long, in seconds, it takes for weather to transition from one type to another when manually changing types in the menu.',
            },
        },
    },
    {
        title = 'Time Options',
        settings = {
            {
                name = 'vMenu.Enhanced.TimeOptions.Enabled',
                type = 'bool',
                default = true,
                description = "Enables vMenu time control/sync. Set this to 'false' if you have another resource controlling game time.",
            },
            {
                name = 'vMenu.Enhanced.TimeOptions.SpeedMultiplier',
                type = 'float',
                default = 1.0,
                description = 'How fast the in-game clock runs compared to how GTA normally runs it. Value must be between 0.01 and 1000.',
            },
            {
                name = 'vMenu.Enhanced.TimeOptions.Presets',
                type = 'string',
                default = '0000,0300,0600,0900,1200,1500,1800,2100',
                description = 'A list of preset times to choose from in the time options menu.',
            },
            {
                name = 'vMenu.Enhanced.TimeOptions.TransitionSeconds',
                type = 'int',
                default = 4,
                description = 'How long time transitions take. Zero instantly jumps to the desired time.',
            },
        },
    },
    {
        title = 'World API',
        settings = {
            {
                name = 'vMenu.Enhanced.WorldApi.Token',
                type = 'string',
                default = '',
                server_only = true,
                description = "A password that lets your own tools read the weather, time, date and moon phase over HTTP, so a Discord bot or a website can show what the sky is doing without guessing. Leave it empty and the endpoint is switched off and answers nobody. Set it to any long random string and callers hand it back in an X-vMenu-Token header, or a token query parameter, to be let in. Uses 'set' and not 'setr': this is a secret.",
            },
        },
    },
    {
        title = 'Integration',
        settings = {
            {
                name = 'vMenu.Enhanced.Integration.ApiKey',
                type = 'string',
                default = '',
                server_only = true,
                description = "Please read https://docs.vespura.com/vmenu/enhanced/integrations. Uses 'set' and not 'setr'! This is important to keep your API key secret!",
            },
            {
                name = 'vMenu.Enhanced.Integration.Endpoint',
                type = 'string',
                default = '',
                server_only = true,
                description = "The base URL of the external tool this server connects to, for example 'https://example.com/api'. Value can be http or https, and an IP or a domain both work. If using HTTPS, the certificate must be valid and trusted. This server makes outgoing HTTP(S) calls to this URL, and also opens a websocket derived from it, so 'https://example.com/api' becomes 'wss://example.com/api/socket' (uses 'ws' for http instead). Leave it empty and this server makes no outgoing calls at all. Please read the documentation if you're planning on using this. Uses 'set' and not 'setr'.",
            },
            {
                name = 'vMenu.Enhanced.Integration.AllowActions',
                type = 'bool',
                default = false,
                server_only = true,
                description = "If set to true, it will allow external tools that connect using the websocket to perform actions against players. For example: kill, kick, heal, etc. Uses 'set' and not 'setr'.",
            },
            {
                name = 'vMenu.Enhanced.Integration.Allowlist',
                type = 'bool',
                default = false,
                server_only = true,
                description = "Only lets in players with the 'vMenu.Enhanced.Integration.Allowlist.Bypass' permission, or players a connected integration (like SnowstormBot) allows. Uses 'set', not 'setr'.",
            },
            {
                name = 'vMenu.Enhanced.Integration.AllowlistMessage',
                type = 'string',
                default = 'You are not on the allowlist for this server.',
                server_only = true,
                description = "Customize the message someone sees if they're not on the allowlist.",
            },
            {
                name = 'vMenu.Enhanced.Integration.Queue',
                type = 'bool',
                default = false,
                server_only = true,
                description = "If set to true, connecting players are held in a join queue that a connected external tool (like SnowstormBot) manages. Unlike the allowlist, this feature does not work without an external tool managing it! The tool decides the queues, priorities and delays. This convar only turns the queue on or off. A player holding the 'vMenu.Enhanced.Integration.Queue.Bypass' permission can skip the queue if they choose to (there is a button in the join screen they can click to bypass the queue). Uses 'set' and not 'setr'.",
            },
        },
    },
    {
        title = 'Developer Features',
        settings = {
            {
                name = 'vMenu.Enhanced.DeveloperFeatures',
                type = 'bool',
                default = true,
                description = "Enables the Developer Features menu. Pretty much all features in here are generally harmless. Give them a try, and then decide if you want to have them enabled or disabled for your server. If you're unsure, turn this off on a public, production, server.",
            },
        },
    },
    {
        title = 'Debugging',
        settings = {
            {
                name = 'vMenu.Enhanced.Debugging.Client',
                type = 'bool',
                default = false,
                description = 'Enables additional console logging on the client side.',
            },
            {
                name = 'vMenu.Enhanced.Debugging.Server',
                type = 'bool',
                default = false,
                description = 'Enables additional console logging on the server side.',
            },
            {
                name = 'vMenu.Enhanced.Debugging.ExperimentalFeatures',
                type = 'bool',
                default = false,
                description = "Currently doesn't do anything, leave this as false for now.",
            },
        },
    },
}
