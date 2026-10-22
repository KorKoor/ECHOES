-- EchoesProbe: diagnostic spike. Every check is wrapped in pcall; results go to console.txt
-- with the prefix "[EchoesProbe]". Nothing here changes gameplay except one test sound.
-- Run: load a save with the mod enabled, wait ~5 s after spawn, then read console.txt.

local TAG = "[EchoesProbe] "

local function log(msg)
    print(TAG .. tostring(msg))
end

local function check(name, fn)
    local ok, res = pcall(fn)
    if ok then
        log("OK   " .. name .. " -> " .. tostring(res))
    else
        log("FAIL " .. name .. " -> " .. tostring(res))
    end
end

local function runProbe()
    local player = getPlayer()
    if not player then
        log("no player yet")
        return
    end

    log("game version: " .. tostring(getCore():getVersion()))
    log("multiplayer: isClient=" .. tostring(isClient()) .. " isServer=" .. tostring(isServer()))

    -- 1. Mod detection (Viewpoint is optional for ECHOES)
    check("getActivatedMods", function()
        local mods = getActivatedMods()
        return "Viewpoint=" .. tostring(mods:contains("Viewpoint"))
            .. " ZombieBuddy=" .. tostring(mods:contains("ZombieBuddy"))
    end)

    -- 2. Stats: B42 uses the CharacterStat registry
    check("CharacterStat global", function() return tostring(CharacterStat) end)
    check("stats:get(SANITY)", function()
        return tostring(player:getStats():get(CharacterStat.SANITY))
    end)
    check("stats:get(STRESS)", function()
        return tostring(player:getStats():get(CharacterStat.STRESS))
    end)
    check("stats:get(PANIC)", function()
        return tostring(player:getStats():get(CharacterStat.PANIC))
    end)

    -- 3. Positional emitter; play a vanilla sound (change name if it does not exist)
    check("getFreeEmitter+playSound", function()
        local sq = player:getCurrentSquare()
        local em = getWorld():getFreeEmitter(sq:getX() + 6, sq:getY(), sq:getZ())
        return tostring(em:playSound("DoorClose"))
    end)

    -- 4. World sound manager (do NOT attract zombies: radius 1, volume 1)
    check("getWorldSoundManager", function() return tostring(getWorldSoundManager()) end)
    check("WorldSoundManager.addSound", function()
        local sq = player:getCurrentSquare()
        getWorldSoundManager():addSound(player, sq:getX(), sq:getY(), sq:getZ(), 1, 1)
        return "called"
    end)

    -- 5. Environment queries
    check("ClimateManager", function()
        local c = getClimateManager()
        return "night=" .. tostring(c:getNightStrength()) .. " fog=" .. tostring(c:getFogIntensity())
            .. " rain=" .. tostring(c:getRainIntensity())
    end)
    check("square:isOutside/getRoom", function()
        local sq = player:getCurrentSquare()
        return "outside=" .. tostring(sq:isOutside()) .. " room=" .. tostring(sq:getRoom())
    end)
    check("BuildingDef alarm API", function()
        local sq = player:getCurrentSquare()
        local b = sq:getBuilding()
        if not b then return "not in a building (stand inside and re-run)" end
        return "alarmed=" .. tostring(b:getDef():isAlarmed())
    end)

    -- 5b. Screen effects (SearchMode); read-only here, no override is enabled
    check("getSearchMode", function()
        local sm = getSearchMode()
        local b = sm:getBlur(0)
        return "mode=" .. tostring(sm) .. " blur=" .. tostring(b)
            .. " desat=" .. tostring(sm:getDesat(0)) .. " darkness=" .. tostring(sm:getDarkness(0))
            .. " enabled=" .. tostring(sm:isEnabled(0))
    end)
    check("ClimateManager.setDesaturation exists", function()
        return tostring(getClimateManager().setDesaturation ~= nil)
    end)

    -- 6. Custom event creation (for the ECHOES internal bus)
    check("LuaEventManager.AddEvent", function()
        LuaEventManager.AddEvent("EchoesProbeEvent")
        local got = false
        Events.EchoesProbeEvent.Add(function() got = true end)
        triggerEvent("EchoesProbeEvent")
        return "received=" .. tostring(got)
    end)

    -- 7. Event inventory (only if ZombieBuddy is loaded)
    check("ZombieBuddy.Events", function()
        if not ZombieBuddy or not ZombieBuddy.Events then return "ZombieBuddy not present" end
        local names = {}
        for name, _ in pairs(ZombieBuddy.Events.getAll()) do names[#names + 1] = name end
        table.sort(names)
        return #names .. " events: " .. table.concat(names, ", ")
    end)

    -- 7b. Sound inventory: which sounds does the game really have? (keyword search, first 12 per keyword)
    check("GameSounds.isKnownSound", function()
        local out = {}
        for _, n in ipairs({ "DoorClose", "DoorOpen", "FootstepsIndoor", "HouseAlarm", "ZombieFootstep" }) do
            out[#out + 1] = n .. "=" .. tostring(GameSounds.isKnownSound(n))
        end
        return table.concat(out, " ")
    end)
    check("GameSounds categories", function()
        local cats = GameSounds.getCategories()
        local names = {}
        for i = 0, cats:size() - 1 do names[#names + 1] = tostring(cats:get(i)) end
        return cats:size() .. " categories: " .. table.concat(names, ", ")
    end)
    check("GameSounds keyword search", function()
        local keys = { "breath", "pant", "exhaust", "winded", "tired", "whisper", "murmur", "footstep", "door", "alarm", "heart", "cry", "voice",
            "shuffle", "drag", "scrape", "knock", "drip", "thump", "scratch", "shot", "gunfire", "heartbeat", "cough", "shiver", "gasp" }
        local found = {}
        for _, k in ipairs(keys) do found[k] = {} end
        local cats = GameSounds.getCategories()
        for i = 0, cats:size() - 1 do
            local list = GameSounds.getSoundsInCategory(cats:get(i))
            for j = 0, list:size() - 1 do
                local name = list:get(j):getName()
                local low = string.lower(name)
                for _, k in ipairs(keys) do
                    if string.find(low, k, 1, true) and #found[k] < 12 then found[k][#found[k] + 1] = name end
                end
            end
        end
        for _, k in ipairs(keys) do log("sounds[" .. k .. "]: " .. table.concat(found[k], ", ")) end
        return "done"
    end)

    -- 7c. Objects used by the world modules
    check("ModData.getOrCreate", function() return tostring(ModData.getOrCreate("EchoesProbeData")) end)
    check("room light switches", function()
        local room = player:getCurrentSquare():getRoom()
        if not room then return "not in a room" end
        return "switches=" .. tostring(room:getLightSwitches():size()) .. " id=" .. tostring(room:getRoomDef():getID())
    end)
    check("hydro power", function() return tostring(getWorld():isHydroPowerOn()) end)
    check("thermoregulator core", function()
        return tostring(player:getBodyDamage():getThermoregulator():getCoreCelcius())
    end)
    check("endurance/fatigue ranges", function()
        local e, f = CharacterStat.ENDURANCE, CharacterStat.FATIGUE
        return "ENDURANCE " .. e:getMinimumValue() .. ".." .. e:getMaximumValue() .. "=" .. tostring(player:getStats():get(e))
            .. " FATIGUE " .. f:getMinimumValue() .. ".." .. f:getMaximumValue() .. "=" .. tostring(player:getStats():get(f))
    end)
    check("UI + context menu pieces", function()
        return "ISPanel=" .. tostring(ISPanel ~= nil) .. " ISBaseTimedAction=" .. tostring(ISBaseTimedAction ~= nil)
            .. " ISTimedActionQueue=" .. tostring(ISTimedActionQueue ~= nil) .. " luautils.walkAdj="
            .. tostring(luautils ~= nil and luautils.walkAdj ~= nil)
    end)
    check("zombie awareness API", function()
        local list = getCell():getZombieList()
        if list:size() == 0 then return "no zombie loaded (stand near one and re-run)" end
        local z = list:get(0)
        return "responding=" .. tostring(z:isRespondingToPlayerSound()) .. " movingToSound="
            .. tostring(z:isMovingToPlayerSound()) .. " target=" .. tostring(z:getTarget())
            .. " modData=" .. tostring(z:getModData())
    end)
    check("light level + forward dir", function()
        local sq = player:getCurrentSquare()
        return "light=" .. tostring(sq:getLightLevel(player:getPlayerNum())) .. " fwd="
            .. tostring(player:getForwardDirectionX()) .. "," .. tostring(player:getForwardDirectionY())
    end)
    check("vehicle API", function()
        local v = player:getVehicle()
        if not v then return "not in a vehicle (sit in one and re-run)" end
        return "speed=" .. tostring(v:getCurrentSpeedKmHour()) .. " engine=" .. tostring(v:isEngineStarted())
    end)
    check("fear/dizziness APIs", function()
        local st = player:getStats()
        local bd = player:getBodyDamage()
        return "visibleZ=" .. tostring(st:getNumVisibleZombies()) .. " chasingZ=" .. tostring(st:getNumChasingZombies())
            .. " bleedingParts=" .. tostring(bd:getNumPartsBleeding()) .. " bodyHealth=" .. tostring(bd:getOverallBodyHealth())
            .. " isTripping=" .. tostring(st:isTripping()) .. " trippingAngle=" .. tostring(st:getTrippingRotAngle())
    end)
    check("zombie target visibility", function()
        local list = getCell():getZombieList()
        if list:size() == 0 then return "no zombie loaded" end
        local z = list:get(0)
        -- note: Java instance fields are not readable from Lua since 42.15 (static ones are)
        return "isTargetVisible=" .. tostring(z:isTargetVisible())
    end)
    check("radio API", function()
        local r = getZomboidRadio()
        return "instance=" .. tostring(r) .. " randomFreq=" .. tostring(r:getRandomFrequency())
            .. " devices=" .. tostring(r:getDevices():size())
    end)
    check("running flags", function() return tostring(player:isRunning()) .. "/" .. tostring(player:isSprinting()) end)

    check("EchoesEngine (Java)", function()
        if not EchoesEngine_version then return "not loaded (optional)" end
        return "v" .. tostring(EchoesEngine_version()) .. " occlusion(self)=" .. tostring(
            EchoesEngine_occlusion(player:getX(), player:getY(), player:getZ(), player:getX() + 6, player:getY(), player:getZ()))
            .. " stats: " .. tostring(EchoesEngine_stats())
    end)

    -- 8. Events we intend to use: do the Events entries exist?
    for _, ev in ipairs({ "OnGameStart", "OnPlayerUpdate", "EveryTenMinutes", "EveryHours", "EveryOneMinute", "OnKeyPressed",
            "OnZombieUpdate", "OnTick", "OnClientCommand", "OnServerCommand", "OnWorldSound",
            "OnFillWorldObjectContextMenu", "OnPostUIDraw" }) do
        check("Events." .. ev, function() return tostring(Events[ev] ~= nil) end)
    end

    log("probe finished")
end

-- Run once, ~300 ticks after the game starts, so the player and world are ready.
local ticks, done = 0, false
local function onTick()
    if done then return end
    ticks = ticks + 1
    if ticks >= 300 then
        done = true
        Events.OnTick.Remove(onTick)
        runProbe()
    end
end

Events.OnGameStart.Add(function()
    ticks, done = 0, false
    Events.OnTick.Add(onTick)
end)
