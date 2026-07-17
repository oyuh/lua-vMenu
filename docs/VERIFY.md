# In-game verification checklist

Everything in this repo is spec-tested against a mocked CfxLua runtime (275 specs), and the
compatibility contracts are verified against golden fixtures captured from C# vMenu. The items
below are the ones that can only be confirmed on a real FiveM server, side-by-side with the
pinned upstream build (`49e53065`). Check them off during the first live deployment.

## Visuals & input (menu framework, from the M3 checklist)

- [ ] Menu visuals match C# MenuAPI side-by-side: header banner sprite metrics, subtitle bar,
      gradient background, item spacing, overflow scroll bar, description box, color/opacity
      panels, weapon/vehicle stats panels (`/vmenu_demo` behind
      `experimental_features_enabled '1'` shows every item type)
- [ ] `MenuSliderItem` bar/background colors match (menu/items.lua defaults)
- [ ] Control ids marked "verify" in menu/process.lua behave on keyboard AND controller
      (navigation, hold-to-scroll acceleration, back/select, menu toggle)
- [ ] Right-aligned menu refuses `Right` on ultra-wide aspect ratios like upstream
      (Controller.SetMenuAlignment guard)

## Save compatibility (the drop-in promise)

- [ ] A C#-created saved vehicle spawns visually identical (mods, colors incl. paint finish,
      neon, plate, extras, liveries) and re-saves without diffing
- [ ] A C#-created saved ped and MP character load pixel-identical (head blend, overlays,
      face shape, tattoos, clothes, props)
- [ ] Weapon loadouts equip with correct components/tints/ammo; "restore on respawn" works
- [ ] Keybinds survive: players who bound MenuToggle/NoClip in C# vMenu keep their keys

## Native-mapping risks (single points to sanity-check)

- [ ] Helmet visor toggle: the alternate prop variant is resolved by matching combination
      hashes (client/functions_controller/creator_camera.lua `get_alt_prop_variation`) instead
      of C#'s unsafe struct native — confirm visor_up/visor_down picks the right prop
- [ ] `DrawNotificationWithButton` (gamepad recording notifications) — confirm the native name
      resolves; if not, the gamepad recording flow needs the correct thefeed native
- [ ] `SetVehicleDoorBreakable` (vehicle god: door breakability) — confirm the native name
- [ ] Radio station list: `Set Default Radio Station` switches to the right station for every
      entry (client/menus/vehicle_options.lua RADIO_GAME_NAMES vs the game's internal order)
- [ ] Weapon stats panels currently show zeroed accuracy/damage/range/speed
      (`GetWeaponHudStats` is a struct native; client/weapons.lua get_hud_stats) — wire the
      struct read or accept the cosmetic gap
- [ ] MP creator camera framing/interpolation matches upstream for every submenu, including
      the reverse (walk-around) flip and the watch-viewing pose

## Multiplayer-only behavior

- [ ] Player blips + overhead names against other clients (decorator sync)
- [ ] Clothing glow animation sync across clients (clothing_animation_type decorator)
- [ ] Spectate, summon, kick, ban/tempban flows against a second player
- [ ] OneSync Infinity player list paths (vMenu:RequestPlayerList / ReceivePlayerList)
- [ ] Weather/time sync convergence with multiple clients and dynamic weather on

## Performance

- [ ] resmon ~0.00ms with the menu closed and features off (matches upstream's idle profile;
      menu ticks early-out per frame, noclip/entity-spawner threads only exist while active)
- [ ] No hitch when opening the dynamic Mod Menu or the MP character editor
