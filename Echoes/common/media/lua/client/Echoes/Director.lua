-- ECHOES director (client): decides when an unexplained sound may happen and how it is staged.
-- UNTESTED prototype. Sound names and several API calls are unverified ([V] in docs/02-design.md).
-- No zombie-attracting world sound is created: sounds are only played locally by an emitter.

local Log, Config = Echoes.Log, Echoes.Config

local Director = {}
Echoes.Director = Director

local MIN_DIST, MAX_DIST = 6, 14
local BASE_CHANCE = 0.06            -- per evaluation (every in-game 10 minutes), before Frequency
local GLOBAL_COOLDOWN_HOURS = 3.0   -- minimum in-game hours between any two phenomena
local ZOMBIE_CLEAR_RADIUS = 14
local CALLBACK_CHANCE = 0.30        -- chance a later phenomenon returns to a remembered place
local CALLBACK_WINDOW_HOURS = 36

-- Sound kinds. Names are candidates tried in random order until one plays. [V] names may not exist.
Director.kinds = {
    {
        id = "door", weight = 1.0, needsDoor = true, volume = 0.85,
        sounds = { "DoorClose", "DoorOpen" },
    },
    {
        id = "footsteps", weight = 1.4, needsWalkable = true, volume = 0.7,
        sounds = { "FootstepsIndoor", "ZombieFootstep" }, steps = { 4, 7 }, interval = { 450, 650 },
    },
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

local function sanityFactor(player)
    -- Lower sanity makes phenomena slightly more likely. Never penalises the player mechanically.
    local ok, v = pcall(function() return player:getStats():get(CharacterStat.SANITY) end)
    if not ok or type(v) ~= "number" then return 1.0 end
    return 1.0 + (1.0 - v) * 0.5 -- assumes SANITY in 0..1 (1 = healthy) [V]
end

local function pickKind(list)
    local total = 0
    for _, k in ipairs(list) do total = total + k.weight end
    local r = ZombRandFloat(0, total)
    for _, k in ipairs(list) do
        r = r - k.weight
        if r <= 0 then return k end
    end
    return list[#list]
end

local function shuffled(t)
    local o = {}
    for i, v in ipairs(t) do o[i] = v end
    for i = #o, 2, -1 do
        local j = 1 + ZombRand(i)
        o[i], o[j] = o[j], o[i]
    end
    return o
end

-- Plays the first working candidate at the square with the given volume factor. Returns name or nil.
local function playAt(sq, sounds, volume)
    local em = getWorld():getFreeEmitter(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ())
    if not em then return nil end
    for _, name in ipairs(shuffled(sounds)) do
        local ok, handle = pcall(function() return em:playSound(name) end)
        if ok then
            if handle and handle ~= 0 then
                pcall(function() em:setVolume(handle, volume) end)
                pcall(function() em:setPitch(handle, 0.94 + ZombRandFloat(0, 0.12)) end)
            end
            return name
        end
        Log.debug("playSound failed for " .. name)
    end
    return nil
end

-- Square selection ----------------------------------------------------------------------------
local function ringSquare(player, minD, maxD)
    local ang = ZombRand(360) * math.pi / 180
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

local function findWalkableSquare(player)
    local pnum = player:getPlayerNum()
    local best
    for _ = 1, 10 do
        local sq = ringSquare(player, MIN_DIST, MAX_DIST)
        if sq and sq:isFree(false) then
            if not sq:isCouldSee(pnum) then return sq end
            best = best or sq
        end
    end
    return best
end

-- Remembered place from a previous phenomenon (recent, still loaded). "The same place again."
local function callbackSquare(mem)
    local t = nowHours()
    for i = #mem.log, 1, -1 do
        local e = mem.log[i]
        if t - e.t <= CALLBACK_WINDOW_HOURS and t - e.t > GLOBAL_COOLDOWN_HOURS then
            local sq = getCell():getGridSquare(e.x, e.y, e.z or 0)
            if sq then return sq end
        end
    end
    return nil
end

-- Staged playback ------------------------------------------------------------------------------
-- A tiny queue so footsteps can be spread over time. The tick handler is registered only while
-- the queue is non-empty, so there is no per-frame cost otherwise.
local queue, ticking = {}, false

local function onTick()
    local player = getPlayer()
    if not player or #queue == 0 then
        Events.OnTick.Remove(onTick)
        ticking = false
        queue = {}
        return
    end
    local t = getTimestampMs()
    for i = #queue, 1, -1 do
        local e = queue[i]
        if t >= e.at then
            table.remove(queue, i)
            local f = Echoes.Acoustics.factor(e.sq, player, { maxDist = 24 })
            if f > 0.02 then Echoes.safe("staged play", playAt, e.sq, e.sounds, e.volume * f) end
        end
    end
end

local function schedule(entry)
    queue[#queue + 1] = entry
    if not ticking then
        ticking = true
        Events.OnTick.Add(onTick)
    end
end

local function stageFootsteps(kind, startSq, player)
    local ang = ZombRand(360) * math.pi / 180
    local n = kind.steps[1] + ZombRand(kind.steps[2] - kind.steps[1] + 1)
    local at = getTimestampMs()
    local cell = getCell()
    local x0, y0, z = startSq:getX() + 0.5, startSq:getY() + 0.5, startSq:getZ()
    local placed = 0
    for k = 0, n - 1 do
        local sq = cell:getGridSquare(math.floor(x0 + math.cos(ang) * 0.9 * k),
            math.floor(y0 + math.sin(ang) * 0.9 * k), z)
        if not sq or not sq:isFree(false) then break end
        schedule({ at = at, sq = sq, sounds = kind.sounds, volume = kind.volume })
        at = at + kind.interval[1] + ZombRand(kind.interval[2] - kind.interval[1] + 1)
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
    if player:isDead() or player:getVehicle() then return false end
    if zombiesNear(player, ZOMBIE_CLEAR_RADIUS) then return false end
    return true, indoor, night
end

-- force=true skips chance and cooldown (debug only).
function Director.evaluate(force)
    if not Config.isEnabled("Sound") then return end
    local player = getPlayer()
    if not player then return end

    local mem = memory(player)
    local t = nowHours()
    if not force and (t - mem.last) < GLOBAL_COOLDOWN_HOURS then return end

    local ok, indoor, night = suitable(player)
    if not ok then Log.debug("conditions not suitable"); return end

    local chance = BASE_CHANCE * Config.get("Frequency") * sanityFactor(player)
    if indoor and night then chance = chance * 1.5 end
    if not force and ZombRandFloat(0, 1) > chance then return end

    -- Prefer returning to a remembered place now and then; otherwise pick a fresh source.
    local remembered = (ZombRandFloat(0, 1) < CALLBACK_CHANCE) and callbackSquare(mem) or nil
    local kind = pickKind(Director.kinds)
    local sq = remembered
    if not sq then
        sq = kind.needsDoor and findDoorSquare(player) or findWalkableSquare(player)
    end
    if not sq then Log.debug("no source square for " .. kind.id); return end

    if kind.id == "footsteps" then
        if stageFootsteps(kind, sq, player) == 0 then Log.debug("no walkable path"); return end
    else
        local f = Echoes.Acoustics.factor(sq, player, { maxDist = 26 })
        if f <= 0.02 then Log.debug("sound inaudible (factor " .. f .. ")"); return end
        if not playAt(sq, kind.sounds, kind.volume * f) then
            Log.warn("no candidate sound could be played")
            return
        end
    end

    mem.last = t
    mem.log[#mem.log + 1] = { id = kind.id, x = sq:getX(), y = sq:getY(), z = sq:getZ(), t = t,
        callback = remembered ~= nil }
    if #mem.log > 20 then table.remove(mem.log, 1) end
    Log.info("phenomenon fired: " .. kind.id .. " at " .. sq:getX() .. "," .. sq:getY()
        .. (remembered and " (callback)" or ""))
end

Events.EveryTenMinutes.Add(function() Echoes.safe("Director.evaluate", Director.evaluate, false) end)

-- Debug: F9 forces a phenomenon when Echoes.Debug is enabled.
Events.OnKeyPressed.Add(function(key)
    if key == Keyboard.KEY_F9 and Config.get("Debug") then
        Echoes.safe("Director.force", Director.evaluate, true)
    end
end)

Events.OnGameStart.Add(function()
    queue = {}
    Log.info("v" .. Echoes.VERSION .. " started. Viewpoint=" .. tostring(getActivatedMods():contains("Viewpoint")))
end)
