-- ECHOES physical (client): the body is not a machine. Collisions, falls and impacts now cost something and are felt.
-- Everything is read from the game's own state (all methods confirmed with javap on the 42.21 classes):
--   * on foot: IsoMovingObject.isCollidedThisFrame / getCollidedObject / isCollidedWithDoor / isCollidedWithVehicle,
--     IsoGameCharacter.isBumped / getBumpedChr, isFalling
--   * in a vehicle: BaseVehicle.getCurrentSpeedKmHour (a sudden drop is a crash)
-- Reactions use the vanilla "bumped" animation set exactly as the game's debug menu drives it (setBumpType("stagger") +
-- BumpDone / BumpFall / BumpFallType) plus noise (WorldSoundManager.addSound), the emotional stats (Echoes.feel) and Mind lines.
--   Door at a sprint / tree / fence, crate or window / scraping a wall / on-foot vehicle hit / crash in a vehicle /
--   hard landing after a fall / a zombie barging into you / stumbles and falls from exhaustion, dizziness or terror.
-- Guarded: not asleep; each kind has its own cooldown; the fall flag is always reset. UNTESTED in game: how it all looks,
-- the thresholds (crash 10 km/h in 0.1 s, landing 0.6 s airborne) and whether Viewpoint's camera follows the animations.

require "Echoes/Core"

local Log, Config = Echoes.Log, Echoes.Config

local Physical = {}
Echoes.Physical = Physical

local POLL_MS = 100
local RISK_MS = 1000
local lastPoll, lastRisk, nextIncident = 0, 0, 0
local cd = {}
local st = { falling = false, fallStart = 0, speed = 0, bumped = false }

local function ready(key, now, gap)
    if now < (cd[key] or 0) then return false end
    cd[key] = now + gap
    return true
end

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

-- One incident: counts it, makes noise, scares a little and lets Mind comment (which also moves the emotional stats).
local function incident(player, name, o)
    Echoes.count("physical." .. name)
    noise(player, o.radius or 8, o.volume or 5)
    if o.shock and Echoes.Fear then Echoes.Fear.shock(o.shock) end
    if o.bump ~= nil then Physical.bump(player, o.bump == "fall") end
    if Echoes.Mind then Echoes.Mind.react(o.line or name, 1.0, { urgent = true }) end
    Log.debug("physical " .. name)
end

-- On foot ------------------------------------------------------------------------------------------------------
local function classify(obj)
    if not obj then return "wall" end
    if instanceof(obj, "IsoTree") then return "tree" end
    if instanceof(obj, "IsoThumpable") or instanceof(obj, "IsoWindow") or instanceof(obj, "IsoWindowFrame") then return "fence" end
    return "wall"
end

local function onFoot(player, now, running)
    local hit, door, veh, obj = false, false, false, nil
    pcall(function()
        hit = player:isCollidedThisFrame()
        door = player:isCollidedWithDoor()
        veh = player:isCollidedWithVehicle()
        if hit then obj = player:getCollidedObject() end
    end)

    if veh and ready("vehicle", now, 6000) then
        incident(player, "hit_vehicle", { radius = 14, volume = 10, shock = 0.3, bump = "fall" })
    elseif door and running and ready("door", now, 4000) then
        incident(player, "doorbump", { radius = 12, volume = 8, shock = 0.05, line = "bump" })
    elseif hit and running then
        local kind = classify(obj)
        if kind == "tree" and ready("tree", now, 5000) then
            incident(player, "hit_tree", { radius = 8, volume = 6, shock = 0.06, bump = (ZombRandFloat(0, 1) < 0.6) and "stagger" or nil })
        elseif kind == "fence" and ready("fence", now, 5000) then
            incident(player, "hit_fence", { radius = 7, volume = 5, shock = 0.04, bump = (ZombRandFloat(0, 1) < 0.4) and "stagger" or nil })
        elseif kind == "wall" and ready("scrape", now, 7000) and ZombRandFloat(0, 1) < 0.3 then
            incident(player, "scrape", { radius = 4, volume = 3 })
        end
    end

    -- Hard landing: measure the time in the air ourselves (the engine's fall-speed scale is not documented).
    local falling = false
    pcall(function() falling = player:isFalling() end)
    if falling and not st.falling then st.fallStart = now end
    if (not falling) and st.falling and now - st.fallStart >= 600 and ready("landing", now, 3000) then
        incident(player, "landing", { radius = 10, volume = 7, shock = 0.1, bump = "stagger" })
    end
    st.falling = falling

    -- A zombie barging into you (the game already staggers you; this is the fright).
    local bumped = false
    pcall(function() bumped = player:isBumped() end)
    if bumped and not st.bumped and ready("contact", now, 4000) then
        local chr
        pcall(function() chr = player:getBumpedChr() end)
        if chr and instanceof(chr, "IsoZombie") then
            incident(player, "contact", { radius = 0, volume = 0, shock = 0.12 })
        end
    end
    st.bumped = bumped
end

-- In a vehicle -------------------------------------------------------------------------------------------------
local function inVehicle(player, now, vehicle)
    local speed = 0
    pcall(function() speed = math.abs(vehicle:getCurrentSpeedKmHour()) end)
    if st.speed - speed >= 10 and ready("crash", now, 8000) then -- 10 km/h lost within one poll (0.1 s)
        incident(player, "crash", { radius = 22, volume = 14, shock = 0.4 })
    end
    st.speed = speed
end

-- Exhaustion, dizziness, terror ---------------------------------------------------------------------------------
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

local function stumbleCheck(player, now)
    if now < nextIncident then return end
    local r, endurance = risk(player)
    if r <= 0 or ZombRandFloat(0, 1) > r then return end
    local fall = (endurance and endurance < 0.05) or ZombRandFloat(0, 1) < 0.3
    nextIncident = now + 45000
    incident(player, fall and "fall" or "stagger", { radius = fall and 14 or 8, volume = fall and 10 or 5,
        bump = fall and "fall" or "stagger", line = fall and "fall" or "stumble" })
end

local function tick()
    if not Config.isEnabled("Physical") then return end
    local player = getPlayer()
    if not player or player:isDead() or player:isAsleep() then return end
    local now = getTimestampMs()
    local vehicle = player:getVehicle()
    if vehicle then
        inVehicle(player, now, vehicle)
        return
    end
    st.speed = 0
    local running = false
    pcall(function() running = player:isRunning() or player:isSprinting() end)
    onFoot(player, now, running)
    if running and now - lastRisk >= RISK_MS then
        lastRisk = now
        stumbleCheck(player, now)
    end
end

Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now - lastPoll < POLL_MS then return end
    lastPoll = now
    Echoes.safe("Physical.tick", tick)
end)

Events.OnGameStart.Add(function()
    lastPoll, lastRisk, nextIncident = 0, 0, 0
    cd = {}
    st = { falling = false, fallStart = 0, speed = 0, bumped = false }
end)