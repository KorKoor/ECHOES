-- ECHOES mind (client): the character's inner life. Every character gets its own temperament (courage, talkativeness,
-- gloom) and a memory (kills, wounds, startles). From those and the live signals (fear, pressure, trauma) it derives an
-- emotional state (calm / dread / fear / panic / numb) and speaks short lines with the vanilla IsoPlayer:Say.
--   * Lines are translated texts IGUI_Echoes_Mind_<kind>[_<sub>]_<n>; how many variants exist is discovered by probing,
--     so adding a line is just adding a text. A kind with a sub ("startle", sub = "footsteps") falls back to the plain kind.
--   * A startle may be followed a moment later by a second line: self-reassurance for the brave, a spiral for the shaken.
--   * Reactions: unexplained phenomena, unseen zombies, kills and kill streaks, wounds, thunder and rain, entering a
--     vehicle, dusk and dawn, survival milestones, radio and alarms, bleeding, tiredness, loneliness, relief after a chase.
--   * Memory of places: near a spot where something unexplained happened before, it remembers ("not here again").
--   * Refuge: long enough in one quiet room and the character settles (lines, a little calm). Nightmares while asleep
--     when traumatised. Weather and body feel: fog, cold.
--   * Interactions (right-click): "Breathe deeply" lowers ECHOES fear; "Reflect" says where you stand (days, kills,
--     mood) and settles you a little. Neither works with a zombie close by.
-- It changes no vanilla stat. UNTESTED in game: Say output, the context options, the timed actions, event arguments
-- (handlers ignore them, so a different shape cannot break anything).

require "Echoes/Core"

local Log, Config = Echoes.Log, Echoes.Config

local Mind = {}
Echoes.Mind = Mind

Mind.state = "calm"

local BASE_GAP_MS = 40000     -- minimum real time between two lines (scaled by talkativeness)
local URGENT_GAP_MS = 6000    -- pain and sudden shocks may speak sooner
local KIND_GAP_MS = 200000    -- the same kind is not repeated within this time
local lastAny, lastKind, prevFear = 0, {}, 0
local killTimes = {}
local lastStartleHours = -1000
local refuge = { room = nil, since = 0 }

-- Temperament and memory -------------------------------------------------------------------------------------
local function memory(player)
    local d = Echoes.playerData(player)
    if not d.mind then
        d.mind = {
            courage = ZombRandFloat(0.15, 0.95), chatty = ZombRandFloat(0.5, 1.5), gloom = ZombRandFloat(0.0, 0.8),
            kills = 0, wounds = 0, startles = 0, milestone = 0,
        }
    end
    return d.mind
end

-- Translations --------------------------------------------------------------------------------------------
local counts = {}
local function variants(prefix)
    if counts[prefix] ~= nil then return counts[prefix] end
    local n = 0
    for i = 1, 12 do
        local key = prefix .. "_" .. i
        local t = getText(key)
        if type(t) == "string" and t ~= key and t ~= "" then n = i else break end
    end
    counts[prefix] = n
    return n
end

local function pick(kind, sub)
    local base = "IGUI_Echoes_Mind_" .. kind
    local prefix = base
    if sub and variants(base .. "_" .. sub) > 0 then prefix = base .. "_" .. sub end
    local n = variants(prefix)
    if n == 0 then return nil end
    return prefix .. "_" .. (1 + ZombRand(n))
end

local function say(player, key, a, b, c)
    local text = getText(key, a, b, c)
    if type(text) ~= "string" or text == key or text == "" then return false end
    return (pcall(function() player:Say(text) end))
end

-- Speaking -------------------------------------------------------------------------------------------------
-- opts: sub (variant group), urgent (short gap), follow = kind spoken 3-5 s later, a/b/c (text arguments).
function Mind.react(kind, chance, opts)
    if not Config.isEnabled("Mind") then return false end
    opts = opts or {}
    local player = getPlayer()
    if not player or player:isDead() then return false end
    local mem = memory(player)
    local now = getTimestampMs()
    local gap = opts.urgent and URGENT_GAP_MS or (BASE_GAP_MS / mem.chatty)
    if now - lastAny < gap or now - (lastKind[kind] or -KIND_GAP_MS) < KIND_GAP_MS then return false end
    if ZombRandFloat(0, 1) > (chance or 1.0) * (0.6 + 0.5 * mem.chatty) then return false end
    local key = pick(kind, opts.sub)
    if not key or not say(player, key, opts.a, opts.b, opts.c) then return false end
    lastAny, lastKind[kind] = now, now
    Echoes.count("mind." .. kind)
    if opts.follow then
        Echoes.Timer.after(3000 + ZombRand(2000), function()
            local p = getPlayer()
            local k2 = pick(opts.follow)
            if p and not p:isDead() and k2 then say(p, k2) end
        end)
    end
    return true
end

-- Speaks a line right away, ignoring the gaps: used by actions the player chose themself.
function Mind.speak(kind, opts)
    opts = opts or {}
    local player = getPlayer()
    if not player or player:isDead() then return false end
    local key = pick(kind, opts.sub)
    if not key then return false end
    Echoes.count("mind." .. kind)
    return say(player, key, opts.a, opts.b, opts.c)
end

-- A startle: the brave steady themself, the shaken spiral.
function Mind.startle(id)
    local mem = getPlayer() and memory(getPlayer())
    if not mem then return end
    mem.startles = mem.startles + 1
    lastStartleHours = getGameTime():getWorldAgeHours()
    local follow = (ZombRandFloat(0, 1) < mem.courage) and "reassure" or "spiral"
    if ZombRandFloat(0, 1) > 0.5 then follow = nil end
    Mind.react("startle", 0.7, { sub = id, follow = follow, urgent = true })
end

-- Emotional state --------------------------------------------------------------------------------------------
local function classify(player, mem)
    local fear = Echoes.Fear and Echoes.Fear.level or 0
    local pressure = Echoes.Psyche and Echoes.Psyche.pressure or 0
    local trauma = Echoes.Psyche and Echoes.Psyche.trauma(player) or 0
    if fear >= 0.7 - 0.15 * mem.courage then return "panic" end
    if fear >= 0.4 then return "fear" end
    if Mind.angerUntil and getTimestampMs() < Mind.angerUntil then return "anger" end
    if trauma >= 0.7 and fear < 0.3 then return "numb" end
    if pressure >= 0.45 - 0.1 * mem.gloom then return "dread" end
    return "calm"
end

local function update(player)
    local mem = memory(player)
    local fear = Echoes.Fear and Echoes.Fear.level or 0
    local state = classify(player, mem)
    Mind.state = state
    if prevFear >= 0.5 and fear < 0.2 then Mind.react("relief", 0.8) end
    prevFear = fear
    local sq = player:getCurrentSquare()
    local indoors = sq and not sq:isOutside()
    if state == "dread" and indoors then Mind.react("dread", 0.25 + 0.2 * mem.gloom) end
    if state == "numb" then Mind.react("numb", 0.2) end
    local okh, hp = pcall(function() return player:getBodyDamage():getOverallBodyHealth() end)
    local okb, bleeding = pcall(function() return player:getBodyDamage():getNumPartsBleeding() end)
    if okh and okb and type(hp) == "number" and bleeding > 0 and hp < 55 then Mind.react("hurt", 0.4) end
    local fatigue = Echoes.statNorm(player, "FATIGUE")
    local endurance = Echoes.statNorm(player, "ENDURANCE")
    if (fatigue and fatigue > 0.8) or (endurance and endurance < 0.15) then Mind.react("tired", 0.2) end
    if state == "calm" and fear < 0.1 and mem.gloom > 0.5 and ZombRandFloat(0, 1) < 0.03 then Mind.react("hope", 0.5) end
    if Echoes.Body and Echoes.Body.state.cold then Mind.react("cold", 0.25) end
    if state == "anger" then Mind.react("anger", 0.4) end
    local hunger, thirst = Echoes.statNorm(player, "HUNGER"), Echoes.statNorm(player, "THIRST")
    if hunger and hunger > 0.6 then Mind.react("hungry", 0.2) end
    if thirst and thirst > 0.6 then Mind.react("thirsty", 0.25) end
    local okc, core = pcall(function() return player:getBodyDamage():getThermoregulator():getCoreCelcius() end)
    if okc and type(core) == "number" and core > 37.6 then Mind.react("heat", 0.25) end
    local okw, wind = pcall(function() return getClimateManager():getWindIntensity() end)
    if okw and type(wind) == "number" and wind > 0.6 then Mind.react("wind", 0.15) end
    if state == "calm" and fear < 0.1 and ZombRandFloat(0, 1) < 0.02 then Mind.react("nostalgia", 0.5) end
    if player:isAsleep() then
        local trauma = Echoes.Psyche and Echoes.Psyche.trauma(player) or 0
        if (trauma >= 0.3 or mem.gloom > 0.6) and ZombRandFloat(0, 1) < 0.15 then
            Mind.react("nightmare", 1.0, { urgent = true })
        end
        return
    end
    Mind.places(player, mem)
    Mind.refuge(player, mem)
end

-- Memory of places --------------------------------------------------------------------------------------------
function Mind.places(player, mem)
    local places = Echoes.playerData(player).places
    if not places or #places == 0 then return end
    local px, py = player:getX(), player:getY()
    local best, bd = nil, 144 -- within 12 tiles
    for _, pl in ipairs(places) do
        local dx, dy = pl.x - px, pl.y - py
        local d = dx * dx + dy * dy
        if d < bd and (pl.w or 0) >= 1.0 then best, bd = pl, d end
    end
    if best then Mind.react("place", 0.45, { sub = best.theme }) end
end

-- Refuge: the same room for ~20 game minutes with nothing startling it ---------------------------------------
function Mind.memory(player) return memory(player) end

function Mind.refuge(player, mem)
    local sq = player:getCurrentSquare()
    local room = sq and sq:getRoom()
    local now = getGameTime():getWorldAgeHours()
    if not room then refuge.room = nil; return end
    if refuge.room ~= room then refuge.room, refuge.since = room, now; return end
    if now - refuge.since >= 0.35 and now - lastStartleHours >= 0.5 then
        if #Echoes.ZombieUtil.nearbyZombies({ player }, 15, 1) == 0 then
            if Echoes.Fear and Echoes.Fear.calm then Echoes.Fear.calm(0.03) end
            Mind.react("refuge", 0.35)
        end
    end
end

Events.EveryOneMinute.Add(function()
    if not Config.isEnabled("Mind") then Mind.state = "calm"; return end
    local player = getPlayer()
    if not player or player:isDead() then return end
    Echoes.safe("Mind.update", update, player)
end)

-- World and body events -------------------------------------------------------------------------------------
local MILESTONES = { 3, 7, 14, 30, 60, 100 }

Events.EveryHours.Add(function()
    if not Config.isEnabled("Mind") then return end
    Echoes.safe("Mind.hours", function()
        local player = getPlayer()
        if not player or player:isDead() then return end
        local mem = memory(player)
        local hour = getGameTime():getHour()
        local days = math.floor(getGameTime():getWorldAgeHours() / 24)
        if hour == 6 then Mind.react("dawn", 0.7) end
        if hour == 19 then Mind.react("dusk", 0.5) end
        if hour == 8 then
            for _, m in ipairs(MILESTONES) do
                if days >= m and mem.milestone < m then
                    mem.milestone = m
                    Mind.react("milestone", 1.0, { a = tostring(m) })
                    break
                end
            end
        end
        local okf, fog = pcall(function() return getClimateManager():getFogIntensity() end)
        if okf and type(fog) == "number" and fog > 0.4 then Mind.react("fog", 0.3) end
        local sq = player:getCurrentSquare()
        if hour >= 22 and sq and not sq:isOutside() and (Echoes.Psyche and Echoes.Psyche.pressure or 0) > 0.3 then
            Mind.react("alone", 0.3 + 0.2 * mem.gloom)
        end
    end)
end)

Events.OnZombieDead.Add(function(zombie)
    if not Config.isEnabled("Mind") then return end
    Echoes.safe("Mind.kill", function()
        local player = getPlayer()
        if not player or player:isDead() or not zombie then return end
        local dx, dy = zombie:getX() - player:getX(), zombie:getY() - player:getY()
        if dx * dx + dy * dy > 16 then return end -- not close enough to have been yours
        local mem = memory(player)
        mem.kills = mem.kills + 1
        local now = getTimestampMs()
        killTimes[#killTimes + 1] = now
        while #killTimes > 0 and now - killTimes[1] > 60000 do table.remove(killTimes, 1) end
        if #killTimes >= 4 then Mind.react("killstreak", 0.8) else Mind.react("kill", 0.12) end
        if mem.kills % 25 == 0 then Mind.react("guilt", 1.0, { urgent = true, a = tostring(mem.kills) }) end
    end)
end)

Events.OnPlayerGetDamage.Add(function()
    if not Config.isEnabled("Mind") then return end
    Echoes.safe("Mind.pain", function()
        local player = getPlayer()
        if not player or player:isDead() then return end
        local mem = memory(player)
        mem.wounds = mem.wounds + 1
        if Echoes.Fear then Echoes.Fear.shock(0.06) end
        Mind.angerUntil = getTimestampMs() + 90000
        Mind.react("pain", 0.5, { urgent = true })
    end)
end)

Events.OnThunderEvent.Add(function() Echoes.safe("Mind.thunder", Mind.react, "thunder", 0.3) end)
Events.OnRainStart.Add(function() Echoes.safe("Mind.rain", Mind.react, "rain", 0.3) end)
Events.OnEnterVehicle.Add(function() Echoes.safe("Mind.vehicle", Mind.react, "vehicle", 0.25) end)

-- Interactions ------------------------------------------------------------------------------------------------
function Mind.defineAction(name, maxTime, done)
    if _G[name] then return true end
    pcall(require, "TimedActions/ISBaseTimedAction")
    pcall(require, "TimedActions/ISTimedActionQueue")
    if not ISBaseTimedAction then return false end
    local cls = ISBaseTimedAction:derive(name)
    _G[name] = cls
    function cls:isValid() return self.character ~= nil and not self.character:isDead() end
    function cls:update() end
    function cls:start() end
    function cls:stop() ISBaseTimedAction.stop(self) end
    function cls:perform()
        ISBaseTimedAction.perform(self)
        Echoes.safe("Mind." .. name, done, self.character, self.target)
    end
    function cls:new(character, target)
        local o = ISBaseTimedAction.new(self, character)
        o.character = character
        o.target = target
        o.stopOnWalk = true
        o.stopOnRun = true
        o.maxTime = maxTime
        return o
    end
    return true
end

local function breatheDone()
    if Echoes.Fear and Echoes.Fear.calm then Echoes.Fear.calm(0.3) end
    Echoes.count("mind.breathe")
    Mind.react("calm", 1.0, { urgent = true })
end

local function reflectDone(player)
    local mem = memory(player)
    local days = math.floor(getGameTime():getWorldAgeHours() / 24)
    if Echoes.Fear and Echoes.Fear.calm then Echoes.Fear.calm(0.1) end
    Echoes.count("mind.reflect")
    local k = pick("reflect_" .. Mind.state)
    local line = pick("reflect")
    if line then say(player, line, tostring(days), tostring(mem.kills), tostring(mem.wounds)) end
    if k then
        Echoes.Timer.after(3500, function()
            local p = getPlayer()
            if p and not p:isDead() then say(p, k) end
        end)
    end
end

local function wantsCalm()
    local fear = Echoes.Fear and Echoes.Fear.level or 0
    local tremor = Echoes.Body and Echoes.Body.state.tremor or 0
    return fear >= 0.15 or tremor >= 0.2
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if not Config.isEnabled("Mind") then return end
    if not context or type(context.addOption) ~= "function" then return end
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() or player:getVehicle() then return end
    if #Echoes.ZombieUtil.nearbyZombies({ player }, 12, 1) > 0 then return end -- not with a zombie close by
    if test then return true end
    local entries = {}
    if wantsCalm() and Mind.defineAction("ISEchoesBreathe", 200, breatheDone) then
        entries[#entries + 1] = { "ContextMenu_Echoes_BreatheDeep", "ISEchoesBreathe" }
    end
    if Mind.defineAction("ISEchoesReflect", 260, reflectDone) then
        entries[#entries + 1] = { "ContextMenu_Echoes_Reflect", "ISEchoesReflect" }
    end
    if Echoes.Actions then Echoes.Actions.collect(player, worldObjects, entries, context) end
    if #entries == 0 then return end
    -- Several choices go into a "Mind" submenu so the right-click menu does not fill up.
    local menu = context
    if #entries >= 2 then
        local ok, sub = pcall(function()
            local opt = context:addOption(getText("ContextMenu_Echoes_Mind"), nil, nil)
            local s = ISContextMenu:getNew(context)
            context:addSubMenu(opt, s)
            return s
        end)
        if ok and sub then menu = sub end
    end
    for _, e in ipairs(entries) do
        menu:addOption(getText(e[1]), player, function(p)
            ISTimedActionQueue.add(_G[e[2]]:new(p, e[3]))
        end)
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(...) return Echoes.safe("Mind.menu", onFillWorldObjectContextMenu, ...) end)

-- For the F7 report.
function Mind.summary(player)
    local m = memory(player)
    return string.format("mind=%s courage=%.2f chatty=%.2f gloom=%.2f kills=%d wounds=%d startles=%d",
        Mind.state, m.courage, m.chatty, m.gloom, m.kills, m.wounds, m.startles)
end