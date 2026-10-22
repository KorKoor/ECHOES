-- ECHOES daze (client): the picture loses colour as fear, dizziness and tremor rise (a "tunnel of grey" feeling).
-- Mechanism: the game's own climate float DESATURATION through its admin override, exactly as the vanilla admin climate
-- panel does (getClimateFloat(0) / setEnableAdmin / setAdminValue; ISAdmPanelClimate.lua). Capped at 0.6 so the world
-- never turns monochrome. The override is ALWAYS released when the level falls back to zero, on death, on a new game
-- and after repeated errors, and a flag in the player's data makes the next load release a stuck one.
-- UNTESTED in game: whether other mods / Viewpoint's post-processing honour this float.

require "Echoes/Core"

local Log, Config = Echoes.Log, Echoes.Config

local Daze = {}
Echoes.Daze = Daze

Daze.level = 0.0
local FLOAT_DESATURATION = 0 -- index used by the game's own admin climate panel
local MAX_LEVEL = 0.6
local applied, disabled, errors, lastMs = false, false, 0, 0

local function var()
    return getClimateManager():getClimateFloat(FLOAT_DESATURATION)
end

local function release()
    if not applied then return end
    applied = false
    pcall(function() var():setEnableAdmin(false) end)
    local player = getPlayer()
    if player then Echoes.playerData(player).dazeApplied = nil end
end

local function target(player)
    local fear = Echoes.Fear and Echoes.Fear.level or 0
    local dizzy = Echoes.Dizzy and Echoes.Dizzy.level or 0
    local tremor = Echoes.Body and Echoes.Body.state.tremor or 0
    return Echoes.clamp(math.max(0.55 * fear, 0.7 * dizzy, 0.25 * tremor), 0, MAX_LEVEL)
end

local function onTick()
    if disabled then return end
    local now = getTimestampMs()
    if now - lastMs < 100 then return end -- 10 updates per real second is plenty for a slow fade
    lastMs = now
    local player = getPlayer()
    local want = 0
    if player and not player:isDead() and Config.isEnabled("Daze") then want = target(player) end
    Daze.level = Daze.level + (want - Daze.level) * 0.08
    if Daze.level < 0.01 and want == 0 then Daze.level = 0 end
    local ok, err = pcall(function()
        if Daze.level > 0 then
            local v = var()
            v:setEnableAdmin(true)
            v:setAdminValue(Daze.level)
            if not applied then
                applied = true
                if player then Echoes.playerData(player).dazeApplied = true end
                Log.debug("colour drain starts")
            end
        else
            release()
        end
    end)
    if ok then
        errors = 0
    else
        errors = errors + 1
        if errors == 1 then Log.error("colour drain failed: " .. tostring(err)) end
        if errors >= 5 then
            Log.warn("colour drain disabled after repeated errors")
            disabled = true
            release()
        end
    end
end

Events.OnGameStart.Add(function()
    Daze.level, errors, disabled, lastMs = 0, 0, false, 0
    local player = getPlayer()
    if player and Echoes.playerData(player).dazeApplied then -- a previous session left the override on
        applied = true
        release()
    else
        applied = false
    end
end)

Events.OnTick.Add(onTick)