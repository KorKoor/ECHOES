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

    -- 8. Events we intend to use: do the Events entries exist?
    for _, ev in ipairs({ "OnGameStart", "OnPlayerUpdate", "EveryTenMinutes", "EveryHours",
            "OnZombieUpdate", "OnTick", "OnClientCommand", "OnServerCommand", "OnWorldSound" }) do
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
