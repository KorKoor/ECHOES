-- ECHOES mind (client): the character's emotional state and inner voice, plus one interaction ("breathe deeply").
-- Emotional state (calm / dread / fear / panic / numb) is derived from the signals ECHOES already has: fear, pressure,
-- trauma. The inner voice is a short line spoken with the vanilla IsoPlayer:Say, rate-limited so it never spams, picked
-- from translated texts (IGUI_Echoes_Mind_<kind>_<n>). Other modules call Mind.react(kind) when something happens.
-- It changes no vanilla stat. "Breathe deeply" (right-click, only with no zombie near) lowers ECHOES' own fear.
-- UNTESTED in game: Say output, the context option and the timed action.

require "Echoes/Core"

local Log, Config = Echoes.Log, Echoes.Config

local Mind = {}
Echoes.Mind = Mind

Mind.state = "calm"

-- How many texts exist per kind (IGUI_Echoes_Mind_<kind>_1 .. _n).
local COUNTS = { startle = 4, cue = 3, relief = 3, hurt = 3, dread = 3, numb = 2, door = 3, calm = 2 }
local GAP_MS = 45000          -- minimum real time between any two lines
local KIND_GAP_MS = 240000    -- the same kind is not repeated within this time
local lastAny, lastKind, prevFear = 0, {}, 0

local function say(player, kind)
    local n = COUNTS[kind]
    if not n then return false end
    local key = "IGUI_Echoes_Mind_" .. kind .. "_" .. (1 + ZombRand(n))
    local text = getText(key)
    if type(text) ~= "string" or text == key or text == "" then return false end
    local ok = pcall(function() player:Say(text) end)
    return ok
end

-- chance: probability the line is spoken at all (1 = always when the gaps allow it).
function Mind.react(kind, chance)
    if not Config.isEnabled("Mind") then return false end
    local player = getPlayer()
    if not player or player:isDead() then return false end
    local now = getTimestampMs()
    if now - lastAny < GAP_MS or now - (lastKind[kind] or -KIND_GAP_MS) < KIND_GAP_MS then return false end
    if ZombRandFloat(0, 1) > (chance or 1.0) then return false end
    if say(player, kind) then
        lastAny, lastKind[kind] = now, now
        Echoes.count("mind." .. kind)
        return true
    end
    return false
end

local function classify(player)
    local fear = Echoes.Fear and Echoes.Fear.level or 0
    local pressure = Echoes.Psyche and Echoes.Psyche.pressure or 0
    local trauma = Echoes.Psyche and Echoes.Psyche.trauma(player) or 0
    if fear >= 0.7 then return "panic" end
    if fear >= 0.4 then return "fear" end
    if trauma >= 0.7 and fear < 0.3 then return "numb" end
    if pressure >= 0.45 then return "dread" end
    return "calm"
end

local function update(player)
    local fear = Echoes.Fear and Echoes.Fear.level or 0
    local state = classify(player)
    Mind.state = state
    if prevFear >= 0.5 and fear < 0.2 then Mind.react("relief", 0.8) end -- the threat is gone
    prevFear = fear
    if state == "dread" then
        local sq = player:getCurrentSquare()
        if sq and not sq:isOutside() then Mind.react("dread", 0.25) end
    elseif state == "numb" then
        Mind.react("numb", 0.2)
    end
    local okh, hp = pcall(function() return player:getBodyDamage():getOverallBodyHealth() end)
    local okb, bleeding = pcall(function() return player:getBodyDamage():getNumPartsBleeding() end)
    if okh and okb and type(hp) == "number" and bleeding > 0 and hp < 55 then Mind.react("hurt", 0.4) end
end

Events.EveryOneMinute.Add(function()
    if not Config.isEnabled("Mind") then Mind.state = "calm"; return end
    local player = getPlayer()
    if not player or player:isDead() then return end
    Echoes.safe("Mind.update", update, player)
end)

-- Breathe deeply ------------------------------------------------------------------------------------
local function defineAction()
    if ISEchoesBreathe then return true end
    pcall(require, "TimedActions/ISBaseTimedAction")
    pcall(require, "TimedActions/ISTimedActionQueue")
    if not ISBaseTimedAction then return false end
    ISEchoesBreathe = ISBaseTimedAction:derive("ISEchoesBreathe")
    function ISEchoesBreathe:isValid() return self.character ~= nil and not self.character:isDead() end
    function ISEchoesBreathe:update() end
    function ISEchoesBreathe:start() end
    function ISEchoesBreathe:stop() ISBaseTimedAction.stop(self) end
    function ISEchoesBreathe:perform()
        ISBaseTimedAction.perform(self)
        Echoes.safe("Mind.breathe", function()
            if Echoes.Fear and Echoes.Fear.calm then Echoes.Fear.calm(0.3) end
            Echoes.count("mind.breathe")
            Mind.react("calm", 1.0)
        end)
    end
    function ISEchoesBreathe:new(character)
        local o = ISBaseTimedAction.new(self, character)
        o.character = character
        o.stopOnWalk = true
        o.stopOnRun = true
        o.maxTime = 200
        return o
    end
    return true
end

local function needsCalm(player)
    local fear = Echoes.Fear and Echoes.Fear.level or 0
    local tremor = Echoes.Body and Echoes.Body.state.tremor or 0
    return fear >= 0.15 or tremor >= 0.2
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if not Config.isEnabled("Mind") then return end
    if not context or type(context.addOption) ~= "function" then return end
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() or player:getVehicle() then return end
    if not needsCalm(player) then return end
    if #Echoes.ZombieUtil.nearbyZombies({ player }, 12, 1) > 0 then return end -- not with a zombie close by
    if test then return true end
    if not defineAction() then return end
    context:addOption(getText("ContextMenu_Echoes_BreatheDeep"), player, function(p)
        ISTimedActionQueue.add(ISEchoesBreathe:new(p))
    end)
end

Events.OnFillWorldObjectContextMenu.Add(function(...) return Echoes.safe("Mind.menu", onFillWorldObjectContextMenu, ...) end)