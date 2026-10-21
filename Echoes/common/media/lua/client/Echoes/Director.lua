-- ECHOES director (client): decides when an unexplained event may happen and how it is staged.
-- UNTESTED prototype. Sound names are resolved against the game's real sound list (Sounds.lua).
-- Sound kinds are only played locally by an emitter: they never attract zombies.

local Log, Config = Echoes.Log, Echoes.Config

local Director = {}
Echoes.Director = Director

local MIN_DIST, MAX_DIST = 6, 14
local BASE_CHANCE = 0.06            -- per evaluation (every in-game 10 minutes), before modifiers
local GLOBAL_COOLDOWN_HOURS = 3.0   -- minimum in-game hours between any two phenomena
local ZOMBIE_CLEAR_RADIUS = 14
local CALLBACK_CHANCE = 0.30        -- chance a later sound returns to a remembered place
local CALLBACK_WINDOW_HOURS = 36

-- Sound kinds. `static` names are tried first (if the game knows them); `patterns` is the fallback search.
Director.kinds = {
    { id = "door", weight = 1.0, needsDoor = true, volume = 0.85, ambiguous = true,
      static = { "DoorClose", "DoorOpen" }, patterns = { "door" }, exclude = { "car", "vehicle", "garage", "locked" } },
    { id = "footsteps", weight = 1.4, volume = 0.7, ambiguous = true, steps = { 4, 7 }, interval = { 450, 650 },
      static = { "FootstepsIndoor" }, patterns = { "footstep", "step" }, exclude = { "zombie", "vehicle", "gun" } },
    { id = "voice", weight = 0.4, volume = 0.5, ambiguous = true, optional = true,
      static = {}, patterns = { "whisper", "murmur" }, exclude = {} },
}

-- Helpers -------------------------------------------------------------------------------------
local function nowHours() return getGameTime():getWorldAgeHours() end

local function memory(player)
    local md = player:getModData()
    md.Echoes = md.Echoes or { last = -1000, log = {} }
    return md.Echoes
end

local function zombiesNear(player, radius)
    local list = getCell():getZombieList()
    local px, py = player:getX(), player:getY()
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        local dx, dy = z:getX() - px, z:getY() - py
        if dx * dx + dy * dy <= radius * radius then return true end
    end
    return false
end

local function candidates(kind)
    return Echoes.Sounds.resolve(kind.id, kind.static, kind.patterns, kind.exclude)
end

-- All kinds currently usable (sound kinds need at least one resolvable sound).
local function availableKinds()
    local out = {}
    for _, k in ipairs(Director.kinds) do
        if #candidates(k) > 0 then out[#out + 1] = k
        elseif not k.optional then Log.debug("no sound for kind " .. k.id) end
    end
    if Config.isEnabled("Phenomena") and Echoes.Phenomena then
        for _, k in ipairs(Echoes.Phenomena.available()) do out[#out + 1] = k end
    end
    if Echoes.Stories then for _, k in ipairs(Echoes.Stories.available()) do out[#out + 1] = k end end
    if Echoes.Visual then for _, k in ipairs(Echoes.Visual.available()) do out[#out + 1] = k end end
    return out
end

local function pickKind(list, pressure)
    local total = 0
    local w = {}
    for i, k in ipairs(list) do
        w[i] = k.weight * (k.ambiguous and (1.0 + pressure) or 1.0)
        total = total + w[i]
    end
    local r = ZombRandFloat(0, total)
    for i, k in ipairs(list) do
        r = r - w[i]
        if r <= 0 then return k end
    end
    return list[#list]
end

-- Square selection ----------------------------------------------------------------------------
local function ringSquare(player, minD, maxD, behind)
    local ang = ZombRand(360) * math.pi / 180
    if behind then -- "a noise behind you": within 70 degrees of the direction opposite to where you face
        local back = math.atan2(player:getForwardDirectionY(), player:getForwardDirectionX()) + math.pi
        ang = back + (ZombRandFloat(0, 1) - 0.5) * (140 * math.pi / 180)
    end
    local dist = minD + ZombRand(maxD - minD + 1)
    local x = math.floor(player:getX() + math.cos(ang) * dist)
    local y = math.floor(player:getY() + math.sin(ang) * dist)
    return getCell():getGridSquare(x, y, player:getZ())
end

-- A square that holds a door, so a door sound always has a physical source. Prefers unseen ones.
local function findDoorSquare(player)
    local cell, pnum = getCell(), player:getPlayerNum()
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), player:getZ()
    local best
    for _ = 1, 60 do
        local sq = cell:getGridSquare(px + ZombRand(-MAX_DIST, MAX_DIST + 1),
            py + ZombRand(-MAX_DIST, MAX_DIST + 1), pz)
        if sq and (sq:getDoor(true) or sq:getDoor(false)) then
            local dx, dy = sq:getX() - px, sq:getY() - py
            local d2 = dx * dx + dy * dy
            if d2 >= MIN_DIST * MIN_DIST and d2 <= MAX_DIST * MAX_DIST then
                if not sq:isCouldSee(pnum) then return sq end
                best = best or sq
            end
        end
    end
    return best
end

local function findWalkableSquare(player, behind)
    local pnum = player:getPlayerNum()
    local best
    for _ = 1, 10 do
        local sq = ringSquare(player, MIN_DIST, MAX_DIST, behind)
        if sq and sq:isFree(false) then
            if not sq:isCouldSee(pnum) then return sq end
            best = best or sq
        end
    end
    return best
end

-- Remembered place: a place where something happened to the player (Places) or a past phenomenon.
local function callbackSquare(mem, player)
    local place = Echoes.Places and Echoes.Places.pick(player, GLOBAL_COOLDOWN_HOURS)
    if place and ZombRandFloat(0, 1) < 0.5 then return place end
    local t = nowHours()
    for i = #mem.log, 1, -1 do
        local e = mem.log[i]
        if e.sq and t - e.t <= CALLBACK_WINDOW_HOURS and t - e.t > GLOBAL_COOLDOWN_HOURS then
            local sq = getCell():getGridSquare(e.x, e.y, e.z or 0)
            if sq then return sq end
        end
    end
    return nil
end

-- Staged playback -----------------------------------------------------------------------------
local function playKindAt(kind, sq, player)
    local f = Echoes.Acoustics.factor(sq, player, { maxDist = 26 })
    if f <= 0.02 then return nil end
    return Echoes.Sounds.playAt(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ(), candidates(kind), kind.volume * f, 0.06,
        kind.ambiguous)
end

local function stageFootsteps(kind, startSq, player)
    local ang = ZombRand(360) * math.pi / 180
    local n = kind.steps[1] + ZombRand(kind.steps[2] - kind.steps[1] + 1)
    local cell = getCell()
    local x0, y0, z = startSq:getX() + 0.5, startSq:getY() + 0.5, startSq:getZ()
    local delay, placed = 0, 0
    for k = 0, n - 1 do
        local sq = cell:getGridSquare(math.floor(x0 + math.cos(ang) * 0.9 * k),
            math.floor(y0 + math.sin(ang) * 0.9 * k), z)
        if not sq or not sq:isFree(false) then break end
        Echoes.Timer.after(delay, function()
            local p = getPlayer()
            if p then playKindAt(kind, sq, p) end
        end)
        delay = delay + kind.interval[1] + ZombRand(kind.interval[2] - kind.interval[1] + 1)
        placed = placed + 1
    end
    return placed
end

-- Evaluation ------------------------------------------------------------------------------------
local function suitable(player)
    local sq = player:getCurrentSquare()
    if not sq then return false end
    local indoor = not sq:isOutside()
    local night = getClimateManager():getNightStrength() > 0.5
    if not (night or indoor) then return false end
    if player:isDead() or player:getVehicle() or player:isAsleep() then return false end
    if zombiesNear(player, ZOMBIE_CLEAR_RADIUS) then return false end
    return true, indoor, night
end

-- force=true skips chance and cooldown (debug only).
function Director.evaluate(force)
    if not Config.isEnabled() then return end
    local player = getPlayer()
    if not player then return end

    local mem = memory(player)
    local t = nowHours()
    if not force and (t - mem.last) < GLOBAL_COOLDOWN_HOURS then return end

    local ok, indoor, night = suitable(player)
    if not ok then Log.debug("conditions not suitable"); return end

    local pressure = Echoes.Psyche and Echoes.Psyche.pressure or 0
    local chance = BASE_CHANCE * Config.get("Frequency") * (1.0 + pressure)
    if indoor and night then chance = chance * 1.5 end
    if not force and ZombRandFloat(0, 1) > chance then return end

    local kinds = availableKinds()
    -- Sound kinds respect their own switch; custom kinds are gated in availableKinds().
    if not Config.isEnabled("Sound") then
        local filtered = {}
        for _, k in ipairs(kinds) do if k.run then filtered[#filtered + 1] = k end end
        kinds = filtered
    end
    if #kinds == 0 then Log.debug("no phenomenon available"); return end

    local kind = pickKind(kinds, pressure)
    local sq, remembered

    if kind.run then
        sq = kind.run(player)
        if not sq then Log.debug("could not stage " .. kind.id); return end
    else
        remembered = (ZombRandFloat(0, 1) < CALLBACK_CHANCE) and callbackSquare(mem, player) or nil
        local behind = (not kind.needsDoor) and ZombRandFloat(0, 1) < (0.25 + 0.35 * pressure)
        sq = remembered or (kind.needsDoor and findDoorSquare(player) or findWalkableSquare(player, behind))
        if not sq then Log.debug("no source square for " .. kind.id); return end
        if kind.steps then
            if stageFootsteps(kind, sq, player) == 0 then Log.debug("no walkable path"); return end
        elseif not playKindAt(kind, sq, player) then
            Log.debug("sound inaudible or could not be played: " .. kind.id)
            return
        end
    end

    if kind.ambiguous and Echoes.Fear then Echoes.Fear.shock(0.12 + 0.2 * pressure) end

    mem.last = t
    mem.log[#mem.log + 1] = { id = kind.id, sq = not kind.run, x = sq:getX(), y = sq:getY(), z = sq:getZ(), t = t,
        callback = remembered ~= nil }
    if #mem.log > 20 then table.remove(mem.log, 1) end
    Log.info("phenomenon fired: " .. kind.id .. " at " .. sq:getX() .. "," .. sq:getY()
        .. (remembered and " (callback)" or "") .. string.format(" pressure=%.2f", pressure))
end

Events.EveryTenMinutes.Add(function() Echoes.safe("Director.evaluate", Director.evaluate, false) end)

-- Debug: F9 forces a phenomenon when Echoes.Debug is enabled.
Events.OnKeyPressed.Add(function(key)
    if key == Keyboard.KEY_F9 and Config.get("Debug") then
        Echoes.safe("Director.force", Director.evaluate, true)
    end
end)

Events.OnGameStart.Add(function()
    Log.info("v" .. Echoes.VERSION .. " started. Viewpoint=" .. tostring(getActivatedMods():contains("Viewpoint")))
end)
