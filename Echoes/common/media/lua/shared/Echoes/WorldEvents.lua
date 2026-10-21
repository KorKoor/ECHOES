-- ECHOES world events (shared): distant alarms that keep sounding for hours and pull zombies toward them.
-- Authority: the lure runs where the world is simulated (single player, host or dedicated server), never on a
-- pure MP client. Zombies are only given a noise to investigate (WorldSoundManager.addSound); the engine's own
-- hearing rules decide who reacts, so nobody learns the player's position. Clients only play a faint, directional
-- sound. UNTESTED: addSound semantics (radius/volume) and OnServerCommand signature are unverified.

local Log, Config = Echoes.Log, Echoes.Config

local WorldEvents = {}
Echoes.WorldEvents = WorldEvents

local ALARM_RADIUS = 70
local ALARM_VOLUME = 50
local HEAR_RANGE = 120

local function players()
    local out = {}
    if isServer() then
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    else
        local p = getPlayer()
        if p then out[1] = p end
    end
    return out
end

-- Faint alarm heard from the direction of (x, y). Client side only.
local function playDistant(x, y)
    if not Echoes.Sounds or not Echoes.Acoustics then return end
    local p = getPlayer()
    if not p then return end
    local dx, dy = x - p:getX(), y - p:getY()
    local d = math.sqrt(dx * dx + dy * dy)
    if d > HEAR_RANGE or d < 1 then return end
    local near = 12 -- put the emitter close to the player, along the bearing of the real source
    local ex, ey = p:getX() + dx / d * near, p:getY() + dy / d * near
    local names = Echoes.Sounds.resolve("alarm", { "HouseAlarm" }, { "alarm" }, { "clock", "smoke", "fire" })
    local f = (1.0 - d / HEAR_RANGE)
    f = f * f * 0.5 * Echoes.Weather.hearingMultiplier(p:getCurrentSquare())
    if f > 0.02 then Echoes.Sounds.playAt(ex, ey, p:getZ(), names, f, 0.03) end
end

local function lure(x, y)
    local ok, err = pcall(function() getWorldSoundManager():addSound(nil, x, y, 0, ALARM_RADIUS, ALARM_VOLUME) end)
    if not ok then Log.warn("addSound failed: " .. tostring(err)) end
end

local function announce(x, y)
    if isServer() then
        sendServerCommand("Echoes", "DistantAlarm", { x = x, y = y })
    else
        playDistant(x, y)
    end
end

-- Signs of human activity: a lamp in a distant, unseen building is found lit at night, and goes dark again hours
-- later. Only lamps that already exist and have power are touched. Remembered in ModData between sessions.
local function findLampNear(player, minD, maxD)
    local cell = getCell()
    for _ = 1, 40 do
        local ang = ZombRand(360) * math.pi / 180
        local dist = minD + ZombRand(maxD - minD + 1)
        local sq = cell:getGridSquare(math.floor(player:getX() + math.cos(ang) * dist),
            math.floor(player:getY() + math.sin(ang) * dist), 0)
        if sq and sq:getRoom() then
            local objs = sq:getObjects()
            for i = 0, objs:size() - 1 do
                local o = objs:get(i)
                if instanceof(o, "IsoLightSwitch") and not o:isActivated() and o:canSwitchLight() then
                    return sq, o
                end
            end
        end
    end
    return nil
end

local function updateActivityLights(state, ps, night)
    state.lights = state.lights or {}
    local nowH = getGameTime():getWorldAgeHours()
    for i = #state.lights, 1, -1 do -- turn expired lamps off again (when their square is loaded)
        local l = state.lights[i]
        if nowH >= l.off then
            local sq = getCell():getGridSquare(l.x, l.y, l.z)
            if sq then
                local objs = sq:getObjects()
                for k = 0, objs:size() - 1 do
                    local o = objs:get(k)
                    if instanceof(o, "IsoLightSwitch") then o:setActivated(false) end
                end
                table.remove(state.lights, i)
            end
        end
    end
    if not night or #state.lights >= 3 then return end
    if ZombRandFloat(0, 1) > 0.05 * Config.get("Frequency") then return end
    local p = ps[1 + ZombRand(#ps)]
    local sq, lamp = findLampNear(p, 22, 45)
    if sq and getWorld():isHydroPowerOn() then
        lamp:setActivated(true)
        state.lights[#state.lights + 1] = { x = sq:getX(), y = sq:getY(), z = sq:getZ(), off = nowH + 2 + ZombRand(5) }
        Log.info(string.format("activity light at %d,%d", sq:getX(), sq:getY()))
    end
end

-- A faint gunshot far away: a reason to wonder, nothing more (no lure).
local function playDistantShot()
    if not Echoes.Sounds then return end
    local p = getPlayer()
    if not p then return end
    local ang = ZombRand(360) * math.pi / 180
    local names = Echoes.Sounds.resolve("distantShot", {}, { "shot", "gunfire" }, { "reload", "empty", "dry", "shotgun_pump" })
    local f = 0.18 * Echoes.Weather.hearingMultiplier(p:getCurrentSquare())
    Echoes.Sounds.playAt(p:getX() + math.cos(ang) * 14, p:getY() + math.sin(ang) * 14, p:getZ(), names, f, 0.03)
end

local function hourly()
    if isClient() or not Config.isEnabled("WorldEvents") then return end
    local ps = players()
    if #ps == 0 then return end

    local state = ModData.getOrCreate("EchoesWorld")
    local nightNow = getClimateManager():getNightStrength() > 0.5
    updateActivityLights(state, ps, nightNow)
    if ZombRandFloat(0, 1) < 0.02 * Config.get("Frequency") then
        if isServer() then sendServerCommand("Echoes", "DistantShot", {}) else playDistantShot() end
    end
    if state.alarm then
        lure(state.alarm.x, state.alarm.y)
        announce(state.alarm.x, state.alarm.y)
        state.alarm.left = state.alarm.left - 1
        if state.alarm.left <= 0 then state.alarm = nil end
        return
    end

    local night = getClimateManager():getNightStrength() > 0.5
    local chance = 0.03 * Config.get("Frequency") * (night and 1.8 or 1.0)
    if ZombRandFloat(0, 1) > chance then return end

    local p = ps[1 + ZombRand(#ps)]
    local ang = ZombRand(360) * math.pi / 180
    local dist = 60 + ZombRand(41)
    state.alarm = {
        x = math.floor(p:getX() + math.cos(ang) * dist),
        y = math.floor(p:getY() + math.sin(ang) * dist),
        left = 2 + ZombRand(4),
    }
    Log.info(string.format("distant alarm started at %d,%d for %d h", state.alarm.x, state.alarm.y, state.alarm.left))
end

Events.EveryHours.Add(function() Echoes.safe("WorldEvents.hourly", hourly) end)

-- Client: a server tells us where an alarm is sounding.
if Events.OnServerCommand then
    Events.OnServerCommand.Add(function(module, command, args)
        if module == "Echoes" and command == "DistantAlarm" and args then
            Echoes.safe("playDistant", playDistant, args.x, args.y)
        elseif module == "Echoes" and command == "DistantShot" then
            Echoes.safe("playDistantShot", playDistantShot)
        end
    end)
end
