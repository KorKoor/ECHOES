-- ECHOES actions (client): ways to act on the character's own feelings and on the world around them, all from the
-- right-click menu (grouped in the "Mind" submenu by Mind.lua). Each is a short timed action and a spoken reaction.
--   Mind:  Hum (calms, a little noise)  /  Cry (eases trauma, a little noise)  /  Pray (calms)  /  Look at the sky
--          (outdoors at dusk, night or dawn).
--   World: Look out the window (counts the zombies you could see outside and reacts)  /  Examine a corpse.
-- Mind actions need no zombie within 12 tiles (Mind.lua checks). Uses only vanilla pieces already used elsewhere in
-- ECHOES: instanceof, ISBaseTimedAction, getWorldSoundManager():addSound, isCouldSee. UNTESTED in game.

require "Echoes/Core"
require "Echoes/ZombieUtil"

local Log, Config = Echoes.Log, Echoes.Config

local Actions = {}
Echoes.Actions = Actions

local function makeNoise(player, radius, volume)
    pcall(function() getWorldSoundManager():addSound(player, player:getX(), player:getY(), player:getZ(), radius, volume) end)
end

local function lowerTrauma(player, v)
    local d = Echoes.playerData(player)
    d.trauma = math.max(0, (d.trauma or 0) - v)
end

-- Results ----------------------------------------------------------------------------------------------------
local function humDone(player)
    if Echoes.Fear and Echoes.Fear.calm then Echoes.Fear.calm(0.25) end
    makeNoise(player, 9, 4) -- a hummed tune carries a little
    Echoes.count("act.hum")
    Echoes.Mind.speak("act_hum")
end

local function cryDone(player)
    if Echoes.Fear and Echoes.Fear.calm then Echoes.Fear.calm(0.15) end
    lowerTrauma(player, 0.06)
    makeNoise(player, 6, 3)
    Echoes.count("act.cry")
    Echoes.Mind.speak("act_cry")
end

local function prayDone(player)
    if Echoes.Fear and Echoes.Fear.calm then Echoes.Fear.calm(0.2) end
    lowerTrauma(player, 0.02)
    Echoes.count("act.pray")
    Echoes.Mind.speak("act_pray")
end

local function skyDone(player)
    if Echoes.Fear and Echoes.Fear.calm then Echoes.Fear.calm(0.08) end
    Echoes.count("act.sky")
    local rain = 0
    pcall(function() rain = getClimateManager():getRainIntensity() end)
    Echoes.Mind.speak(rain > 0.3 and "act_sky_rain" or "act_sky")
end

-- Zombies you could actually see through the window (same test the game uses for line of sight).
local function windowDone(player)
    local pnum = player:getPlayerNum()
    local seen = 0
    for _, z in ipairs(Echoes.ZombieUtil.nearbyZombies({ player }, 25, 40, true)) do
        local zsq = z:getCurrentSquare()
        if zsq and math.abs(z:getZ() - player:getZ()) < 1 and zsq:isCouldSee(pnum) then seen = seen + 1 end
    end
    Echoes.count("act.window")
    if seen == 0 then
        if Echoes.Fear and Echoes.Fear.calm then Echoes.Fear.calm(0.05) end
        Echoes.Mind.speak("act_window_none")
    elseif seen <= 3 then
        if Echoes.Fear then Echoes.Fear.shock(0.04 * seen) end
        Echoes.Mind.speak("act_window_few", { a = tostring(seen) })
    else
        if Echoes.Fear then Echoes.Fear.shock(0.15) end
        Echoes.Mind.speak("act_window_many", { a = tostring(seen) })
    end
end

local function corpseDone(player)
    if Echoes.Fear then Echoes.Fear.shock(0.1) end
    Echoes.count("act.corpse")
    Echoes.Mind.speak("act_corpse")
end

-- Menu ---------------------------------------------------------------------------------------------------------
local function isNight()
    local ok, n = pcall(function() return getClimateManager():getNightStrength() end)
    return ok and type(n) == "number" and n > 0.35
end

local function near(player, obj, range)
    local sq = obj.getSquare and obj:getSquare()
    if not sq or math.floor(player:getZ()) ~= sq:getZ() then return false end
    local dx, dy = player:getX() - (sq:getX() + 0.5), player:getY() - (sq:getY() + 0.5)
    return dx * dx + dy * dy <= range * range
end

-- Adds { textKey, actionName, target } entries for what is possible right now.
function Actions.collect(player, worldObjects, entries, context)
    local M = Echoes.Mind
    local d = Echoes.playerData(player)
    local fear = Echoes.Fear and Echoes.Fear.level or 0
    local mem = M.memory(player)
    if M.defineAction("ISEchoesHum", 160, humDone) then entries[#entries + 1] = { "ContextMenu_Echoes_Hum", "ISEchoesHum" } end
    if (d.trauma or 0) >= 0.2 or mem.gloom > 0.5 then
        if fear < 0.5 and M.defineAction("ISEchoesCry", 220, cryDone) then
            entries[#entries + 1] = { "ContextMenu_Echoes_Cry", "ISEchoesCry" }
        end
    end
    if M.defineAction("ISEchoesPray", 200, prayDone) then entries[#entries + 1] = { "ContextMenu_Echoes_Pray", "ISEchoesPray" } end
    local sq = player:getCurrentSquare()
    if sq and sq:isOutside() and isNight() and M.defineAction("ISEchoesSky", 180, skyDone) then
        entries[#entries + 1] = { "ContextMenu_Echoes_Sky", "ISEchoesSky" }
    end
    local sawWindow, sawCorpse = false, false
    for _, obj in ipairs(type(worldObjects) == "table" and worldObjects or {}) do
        if not sawWindow and instanceof(obj, "IsoWindow") and near(player, obj, 3) then
            sawWindow = true
            if M.defineAction("ISEchoesWindow", 120, windowDone) then
                entries[#entries + 1] = { "ContextMenu_Echoes_LookOut", "ISEchoesWindow" }
            end
        elseif not sawCorpse and instanceof(obj, "IsoDeadBody") and near(player, obj, 3) then
            sawCorpse = true
            if M.defineAction("ISEchoesCorpse", 100, corpseDone) then
                entries[#entries + 1] = { "ContextMenu_Echoes_Corpse", "ISEchoesCorpse" }
            end
        end
    end
end