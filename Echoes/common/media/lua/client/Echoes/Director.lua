-- ECHOES director (client): decides when an unexplained sound may happen.
-- UNTESTED prototype. Sound names and several API calls are unverified ([V] in docs/02-design.md).
-- No zombie-attracting world sound is created: the sound is only played locally by an emitter.

local Log, Config = Echoes.Log, Echoes.Config

local Director = {}
Echoes.Director = Director

-- Candidate vanilla sound names, tried in random order until one plays. [V] names may not exist.
Director.soundCandidates = { "DoorClose", "DoorOpen", "ZombieSurprisedPlayer", "FootstepsIndoor" }

local MIN_DIST, MAX_DIST = 6, 12
local BASE_CHANCE = 0.06          -- per evaluation (every in-game 10 minutes), before Frequency
local GLOBAL_COOLDOWN_HOURS = 3.0 -- minimum in-game hours between any two phenomena
local ZOMBIE_CLEAR_RADIUS = 12

local function nowHours()
    return getGameTime():getWorldAgeHours()
end

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

-- Builds the evaluation context; returns nil when conditions are not suitable.
local function buildContext(player)
    local sq = player:getCurrentSquare()
    if not sq then return nil end
    local indoor = not sq:isOutside()
    local night = getClimateManager():getNightStrength() > 0.5
    return { player = player, square = sq, indoor = indoor, night = night }
end

local function canFire(ctx)
    if not (ctx.night or ctx.indoor) then return false end
    if ctx.player:isDead() or ctx.player:getVehicle() then return false end
    if zombiesNear(ctx.player, ZOMBIE_CLEAR_RADIUS) then return false end
    return true
end

-- Picks a square 6..12 tiles away, preferring one the player cannot currently see.
local function pickSquare(ctx)
    local p = ctx.player
    local cell = getCell()
    local pnum = p:getPlayerNum()
    local fallback
    for _ = 1, 8 do
        local ang = ZombRand(360) * math.pi / 180
        local dist = MIN_DIST + ZombRand(MAX_DIST - MIN_DIST + 1)
        local x = math.floor(p:getX() + math.cos(ang) * dist)
        local y = math.floor(p:getY() + math.sin(ang) * dist)
        local sq = cell:getGridSquare(x, y, p:getZ())
        if sq then
            if not sq:isCouldSee(pnum) then return sq end
            fallback = fallback or sq
        end
    end
    return fallback
end

local function playAt(sq)
    local em = getWorld():getFreeEmitter(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ())
    if not em then return nil end
    local order = {}
    for i, n in ipairs(Director.soundCandidates) do order[i] = n end
    for i = #order, 2, -1 do -- shuffle
        local j = 1 + ZombRand(i)
        order[i], order[j] = order[j], order[i]
    end
    for _, name in ipairs(order) do
        local ok = pcall(function() em:playSound(name) end)
        if ok then return name end
        Log.debug("playSound failed for " .. name)
    end
    return nil
end

-- force=true skips chance and cooldown (debug only).
function Director.evaluate(force)
    if not Config.isEnabled("Sound") then return end
    local player = getPlayer()
    if not player then return end

    local mem = memory(player)
    local t = nowHours()
    if not force and (t - mem.last) < GLOBAL_COOLDOWN_HOURS then return end

    local ctx = buildContext(player)
    if not ctx or not canFire(ctx) then Log.debug("conditions not suitable"); return end

    local chance = BASE_CHANCE * Config.get("Frequency") * sanityFactor(player)
    if ctx.indoor and ctx.night then chance = chance * 1.5 end
    if not force and ZombRandFloat(0, 1) > chance then return end

    local sq = pickSquare(ctx)
    if not sq then Log.debug("no square found"); return end

    local name = playAt(sq)
    if not name then Log.warn("no candidate sound could be played"); return end

    mem.last = t
    mem.log[#mem.log + 1] = { id = "Sound", sound = name, x = sq:getX(), y = sq:getY(), t = t }
    if #mem.log > 20 then table.remove(mem.log, 1) end
    Log.info("phenomenon fired: " .. name .. " at " .. sq:getX() .. "," .. sq:getY())
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
