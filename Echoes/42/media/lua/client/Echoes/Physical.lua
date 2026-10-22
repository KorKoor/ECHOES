-- ECHOES physical (client): the body is not a machine. Running on empty legs, dizzy or terrified can make you stumble or
-- fall, and charging into a closed door at a sprint hurts and is heard.
-- Mechanism (verified in the game's own files): the vanilla "bumped" animation set, driven exactly as the game's debug
-- menu does it (DebugContextMenu.lua): setBumpType("stagger") + the animation variables BumpDone / BumpFall /
-- BumpFallType ("pushedFront" / "pushedBehind"). A light stagger plays bumpStagger*, a fall plays walkBumpFall*.
-- Door collisions read IsoMovingObject.isCollidedWithDoor (present in the 42.21 class, checked with javap).
-- Guarded: never in a vehicle, asleep or at rest; 45 s between incidents; the variables are always reset afterwards.
-- UNTESTED in game: how the stagger / fall look and whether Viewpoint's camera follows them.

require "Echoes/Core"

local Log, Config = Echoes.Log, Echoes.Config

local Physical = {}
Echoes.Physical = Physical

local CHECK_MS = 1000
local COOLDOWN_MS = 45000
local DOOR_COOLDOWN_MS = 4000
local lastCheck, nextIncident, nextDoor = 0, 0, 0

local function noise(player, radius, volume)
    pcall(function() getWorldSoundManager():addSound(player, player:getX(), player:getY(), player:getZ(), radius, volume) end)
end

-- Plays the vanilla stagger (fall=false) or fall (fall=true) animation.
function Physical.bump(player, fall)
    local kind = (ZombRand(2) == 0) and "pushedFront" or "pushedBehind"
    local ok = pcall(function()
        player:setBumpType("stagger")
        player:setVariable("BumpDone", false)
        player:setVariable("BumpFall", fall and true or false)
        player:setVariable("BumpFallType", kind)
    end)
    if not ok then return false end
    Echoes.Timer.after(fall and 6000 or 3500, function() -- never leave the fall flag set for the next real bump
        local p = getPlayer()
        if p then pcall(function() p:setVariable("BumpFall", false) end) end
    end)
    return true
end

local function risk(player)
    local endurance = Echoes.statNorm(player, "ENDURANCE")
    local dizzy = Echoes.Dizzy and Echoes.Dizzy.level or 0
    local fear = Echoes.Fear and Echoes.Fear.level or 0
    local r = 0
    if endurance and endurance < 0.12 then r = r + 0.07 * (1 - endurance / 0.12) end
    if dizzy > 0.4 then r = r + 0.05 * (dizzy - 0.4) / 0.6 end
    if endurance and endurance < 0.35 and fear > 0.8 then r = r + 0.03 * (fear - 0.8) / 0.2 end
    return r, endurance
end

local function check()
    if not Config.isEnabled("Physical") then return end
    local player = getPlayer()
    if not player or player:isDead() or player:isAsleep() or player:getVehicle() then return end
    local now = getTimestampMs()
    local running = false
    pcall(function() running = player:isRunning() or player:isSprinting() end)
    if not running then return end

    -- Charging into a closed door at a sprint.
    local hitDoor = false
    pcall(function() hitDoor = player:isCollidedWithDoor() end)
    if hitDoor and now >= nextDoor then
        nextDoor = now + DOOR_COOLDOWN_MS
        noise(player, 12, 8)
        if Echoes.Fear then Echoes.Fear.shock(0.05) end
        Echoes.count("physical.doorbump")
        if Echoes.Mind then Echoes.Mind.react("bump", 0.8, { urgent = true }) end
    end

    if now < nextIncident then return end
    local r, endurance = risk(player)
    if r <= 0 or ZombRandFloat(0, 1) > r then return end
    local fall = (endurance and endurance < 0.05) or ZombRandFloat(0, 1) < 0.3
    if Physical.bump(player, fall) then
        nextIncident = now + COOLDOWN_MS
        noise(player, fall and 14 or 8, fall and 10 or 5)
        Echoes.count(fall and "physical.fall" or "physical.stagger")
        if Echoes.Mind then Echoes.Mind.react(fall and "fall" or "stumble", 1.0, { urgent = true }) end
        Log.debug(string.format("%s (risk %.3f)", fall and "fall" or "stagger", r))
    end
end

Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now - lastCheck < CHECK_MS then return end
    lastCheck = now
    Echoes.safe("Physical.check", check)
end)

Events.OnGameStart.Add(function() lastCheck, nextIncident, nextDoor = 0, 0, 0 end)