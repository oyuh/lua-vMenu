-- Ports of vMenu.Enhanced.Menus/Players/PlayerSuperJump.cs and
-- PlayerBeastMode.cs. Beast mode is super jump with GTA Online's beast leap
-- and sounds on top, so it needs super jump on and switches it on with it.

local Permissions = require('client.permissions')
local UserDefaults = require('client.user_defaults')
local Ticks = require('menu.ticks')

local Jump = {}

local PERMISSION = 'vMenu.Enhanced.Menus.PlayerOptions.SuperJump'
local DISABLE_PARACHUTING = 217
local DISABLE_PLAYER_VAULTING = 47
local SOUND_BANK = 'DLC_APARTMENT/APT_BEAST'
local SOUND_SET = 'APT_BvS_Soundset'
local AUDIO_SCENE = 'GTAO_BvS_Gameplay_Scene'
local ALL_PLAYERS = -1
local SOUND_RANGE = 60
local SPRINT_INTENSITY = 1.0
local RUN_INTENSITY = 0.7

local function allowed()
    return Permissions.is_allowed(PERMISSION)
end

function Jump.super_enabled()
    return UserDefaults.get('playerSuperJump') == true and allowed()
end

function Jump.beast_enabled()
    return UserDefaults.get('playerBeastMode') == true and Jump.super_enabled()
end

function Jump.set_super(on)
    if on and not allowed() then
        return
    end
    UserDefaults.set('playerSuperJump', on)
    if not on then
        UserDefaults.set('playerBeastMode', false)
    end
    Ticks.reevaluate()
end

function Jump.set_beast(on)
    if on and not allowed() then
        return
    end
    UserDefaults.set('playerBeastMode', on)
    if on then
        Jump.set_super(true)
    end
    Ticks.reevaluate()
end

-- Beast mode sounds ------------------------------------------------------------------

local beast = {
    bank_requested = false,
    bank_loaded = false,
    jump_played = false,
    land_played = false,
    was_attacking = false,
    sprint_sound = -1,
}

local function play(name, ped)
    PlaySoundFromEntity(-1, name, ped, SOUND_SET, true, SOUND_RANGE)
end

local function play_jump_sounds(ped)
    if not IsPedDoingABeastJump(ped) then
        beast.jump_played, beast.land_played = false, false
        return
    end
    local landing = IsPedLanding(ped)
    if not beast.jump_played and not landing and not IsPedClimbing(ped) then
        play('Beast_Jump', ped)
        beast.jump_played = true
    end
    if not beast.land_played and landing and not IsEntityInAir(ped) then
        play('Beast_Jump_Land', ped)
        beast.land_played = true
    end
end

local function play_attack_sound(ped)
    local attacking = IsPedPerformingMeleeAction(ped)
    if attacking and not beast.was_attacking then
        play('Beast_Attack', ped)
    end
    beast.was_attacking = attacking
end

local function stop_sprint_sound()
    if beast.sprint_sound ~= -1 then
        StopSound(beast.sprint_sound)
    end
end

local function play_sprint_sound(ped)
    local airborne = IsPedJumping(ped) or IsPedLanding(ped) or IsEntityInAir(ped)
    local sprinting = IsPedSprinting(ped)
    if IsPedInjured(ped) or airborne or not (sprinting or IsPedRunning(ped)) then
        stop_sprint_sound()
        return
    end
    if beast.sprint_sound == -1 then
        beast.sprint_sound = GetSoundId()
    end
    if HasSoundFinished(beast.sprint_sound) then
        PlaySoundFromEntity(beast.sprint_sound, 'Beast_Sprint_Loop', ped, SOUND_SET, false, 0)
    end
    SetVariableOnSound(beast.sprint_sound, 'Intensity', sprinting and SPRINT_INTENSITY or RUN_INTENSITY)
end

local function silence()
    stop_sprint_sound()
    if beast.sprint_sound ~= -1 then
        ReleaseSoundId(beast.sprint_sound)
        beast.sprint_sound = -1
    end
    if IsAudioSceneActive(AUDIO_SCENE) then
        StopAudioScene(AUDIO_SCENE)
    end
    if beast.bank_requested then
        ReleaseNamedScriptAudioBank(SOUND_BANK)
        beast.bank_requested, beast.bank_loaded = false, false
    end
    beast.jump_played, beast.land_played, beast.was_attacking = false, false, false
end

local function beast_frame()
    local ped = PlayerPedId()
    SetBeastJumpThisFrame(PlayerId())
    SetPedResetFlag(ped, DISABLE_PLAYER_VAULTING, true)
    if not beast.bank_loaded then
        beast.bank_requested = true
        beast.bank_loaded = RequestScriptAudioBank(SOUND_BANK, true, ALL_PLAYERS)
        return
    end
    if not IsAudioSceneActive(AUDIO_SCENE) then
        StartAudioScene(AUDIO_SCENE)
    end
    play_jump_sounds(ped)
    play_attack_sound(ped)
    play_sprint_sound(ped)
end

function Jump.init()
    Ticks.register('Player.SuperJump', function()
        SetSuperJumpThisFrame(PlayerId())
        SetPedResetFlag(PlayerPedId(), DISABLE_PARACHUTING, true)
    end, { condition = Jump.super_enabled })
    Ticks.register('Player.BeastMode', beast_frame, { condition = Jump.beast_enabled, on_stopped = silence })
    AddEventHandler('onResourceStop', function(stopped)
        if stopped == GetCurrentResourceName() then
            silence()
        end
    end)
end

return Jump
