-- ECHOES director (client): decides when an unexplained event may happen and how it is staged.
-- UNTESTED prototype. Sound names are resolved against the game's real sound list (Sounds.lua).
-- Sound kinds are only played locally by an emitter: they never attract zombies.

require "Echoes/Core"
require "Echoes/ZombieUtil"

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
    { id = "knock", weight = 0.5, needsDoor = true, volume = 0.8, ambiguous = true, theme = "knock",
      static = {}, patterns = { "knock" }, exclude = { "zombie", "locked" }, optional = true },
    { id = "door", weight = 1.0, needsDoor = true, volume = 0.85, ambiguous = true, theme = "door",
      static = { "DoorClose", "DoorOpen" }, patterns = { "door" }, exclude = { "car", "vehicle", "garage", "locked" } },
    { id = "footsteps", weight = 1.4, volume = 0.7, ambiguous = true, theme = "steps", steps = { 4, 7 }, interval = { 450, 650 },
      static = { "FootstepsIndoor" }, patterns = { "footstep", "step" }, exclude = { "zombie", "vehicle", "gun" } },
    { id = "voice", weight = 0.4, volume = 0.5, ambiguous = true, optional = true, theme = "voice",
      static = {}, patterns = { "whisper", "murmur" }, exclude = {} },
}

-- Helpers -------------------------------------------------------------------------------------
local function nowHours() return getGameTime():getWorldAgeHours() end

local function memory(player)
    return Echoes.playerData(player)
end

local function zombiesNear(player, radius)
    return #Echoes.ZombieUtil.nearbyZombies({ player }, radius, 1, true) > 0
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

local function pickKind(list, pressure, theme)
    local total = 0
    local w = {}
    for i, k in ipairs(list) do
        w[i] = k.weight * (k.ambiguous and (1.0 + pressure) or 1.0)
        if theme and (k.theme == theme or k.id == theme) then w[i] = w[i] * 4 end -- a haunted place keeps its habits
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
        local back = Echoes.atan2(player:getForwardDirectionY(), player:getForwardDirectionX()) + math.pi
        ang = back + (ZombRandFloat(0, 1) - 0.5) * (140 * math.pi / 180)
    end
    local dist = minD + ZombRand(maxD - minD + 1)
    local x = math.floor(player:getX() + math.cos(ang) * dist)
    local y = math.floor(player:getY() + math.sin(ang) * dist)
    return getCell():getGridSquare(x, y, player:getZ())
end

-- A square that holds a door, so a door sound always has a physical source. Prefers unseen ones, 6..14 tiles away.
local function findDoorSquare(player)
    local pnum = player:getPlayerNum()
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), player:getZ()
    local all = Echoes.doorSquares(px, py, pz, MAX_DIST)
    local unseen, seen = {}, {}
    for _, sq in ipairs(all) do
        local dx, dy = sq:getX() - px, sq:getY() - py
        local d2 = dx * dx + dy * dy
        if d2 >= MIN_DIST * MIN_DIST and d2 <= MAX_DIST * MAX_DIST then
            if sq:isCouldSee(pnum) then seen[#seen + 1] = sq else unseen[#unseen + 1] = sq end
        end
    end
    local pool = #unseen > 0 and unseen or seen
    if #pool == 0 then return nil end
    return pool[1 + ZombRand(#pool)]
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

-- A door within `radius` tiles of a square (for door-themed sounds at a remembered place); nil if none.
local function findDoorNear(sq, radius)
    local all = Echoes.doorSquares(sq:getX(), sq:getY(), sq:getZ(), radius)
    if #all == 0 then return nil end
    return all[1 + ZombRand(#all)]
end

-- Remembered square from a past phenomenon (haunted Places are handled in evaluate).
local function callbackSquare(mem)
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
local function playKindAt(kind, sq, player, volMult)
    local f = Echoes.Acoustics.factor(sq, player, { maxDist = 26 })
    if f <= 0.02 then return nil end
    return Echoes.Sounds.playAt(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ(), candidates(kind),
        Echoes.clamp(kind.volume * f * (volMult or 1.0), 0, 1), 0.06, kind.ambiguous)
end

local function stageFootsteps(kind, startSq, player, stage)
    stage = stage or 0
    if Echoes.Acoustics.factor(startSq, player, { maxDist = 26 }) <= 0.02 then return 0 end -- nobody would hear it
    local ang = ZombRand(360) * math.pi / 180
    if stage >= 3 then -- late stages: the steps walk toward you
        ang = Echoes.atan2(player:getY() - startSq:getY(), player:getX() - startSq:getX())
    end
    local n = kind.steps[1] + ZombRand(kind.steps[2] - kind.steps[1] + 1) + stage
    local cell = getCell()
    local x0, y0, z = startSq:getX() + 0.5, startSq:getY() + 0.5, startSq:getZ()
    local delay, placed = 0, 0
    for k = 0, n - 1 do
        local sq = cell:getGridSquare(math.floor(x0 + math.cos(ang) * 0.9 * k),
            math.floor(y0 + math.sin(ang) * 0.9 * k), z)
        if not sq or not sq:isFree(false) then break end
        Echoes.Timer.after(delay, function()
            local p = getPlayer()
            if p then playKindAt(kind, sq, p, 1.0 + 0.12 * stage) end
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
    -- Tension shortens the quiet gap: at full pressure the global cooldown is 40 % shorter (3 h -> 1.8 h).
    local pressure = Echoes.Psyche and Echoes.Psyche.pressure or 0
    if not force and (t - mem.last) < GLOBAL_COOLDOWN_HOURS * (1.0 - 0.4 * pressure) then return end

    local ok, indoor, night = suitable(player)
    if not ok then Log.debug("conditions not suitable"); return end

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

    -- Maybe return to a haunted place: it has a theme (what it does) and a stage (how far it has escalated).
    local place, placeSq
    if Echoes.Places and ZombRandFloat(0, 1) < CALLBACK_CHANCE then
        placeSq, place = Echoes.Places.pick(player, GLOBAL_COOLDOWN_HOURS)
    end
    local stage = place and place.stage or 0

    local kind = pickKind(kinds, pressure, place and place.theme)
    local sq, remembered

    local usedPlace = false
    if kind.run then
        if kind.usesPlace and placeSq then
            sq = kind.run(player, placeSq)
            if sq then
                local dx, dy = sq:getX() - placeSq:getX(), sq:getY() - placeSq:getY()
                usedPlace = dx * dx + dy * dy <= 16 * 16 -- it really happened at that place
            end
        end
        if not sq then sq = kind.run(player, nil) end -- nothing suitable at the place: act near the player instead
        if not sq then Log.debug("could not stage " .. kind.id); return end
    else
        remembered = placeSq or ((ZombRandFloat(0, 1) < CALLBACK_CHANCE) and callbackSquare(mem) or nil)
        usedPlace = placeSq ~= nil
        local behind = (not kind.needsDoor) and ZombRandFloat(0, 1) < (0.25 + 0.35 * pressure)
        if remembered and kind.needsDoor then -- a door sound needs a door: look near the remembered spot
            remembered = findDoorNear(remembered, 6) -- nil when there is none: then a door elsewhere is chosen below
        end
        sq = remembered
        if not sq then
            if kind.needsDoor then sq = findDoorSquare(player) -- a door sound needs a real door, never a random floor square
            else sq = findWalkableSquare(player, behind) end
        end
        if not sq then Log.debug("no source square for " .. kind.id); return end
        if kind.steps then
            if stageFootsteps(kind, sq, player, stage) == 0 then Log.debug("no walkable path"); return end
        elseif not playKindAt(kind, sq, player, 1.0 + 0.12 * stage) then
            Log.debug("sound inaudible or could not be played: " .. kind.id)
            return
        end
        -- Escalated places sometimes answer themselves a few seconds later, a little to the side.
        if stage > 0 and ZombRandFloat(0, 1) < 0.15 * stage and not kind.steps then
            local cell = getCell()
            Echoes.Timer.after(3000 + ZombRand(5000), function()
                local p2 = getPlayer()
                local sq2 = cell:getGridSquare(sq:getX() + ZombRand(-2, 3), sq:getY() + ZombRand(-2, 3), sq:getZ())
                if p2 and sq2 then playKindAt(kind, sq2, p2, 0.8) end
            end)
        end
    end
    if place and usedPlace and Echoes.Places then Echoes.Places.escalate(place) end -- only if the place was really used

    if kind.ambiguous and Echoes.Fear then Echoes.Fear.shock(0.12 + 0.2 * pressure) end

    mem.last = t
    mem.log[#mem.log + 1] = { id = kind.id, sq = not kind.run, x = sq:getX(), y = sq:getY(), z = sq:getZ(), t = t,
        callback = remembered ~= nil or usedPlace, theme = usedPlace and place.theme or nil, stage = usedPlace and stage or 0 }
    if #mem.log > 20 then table.remove(mem.log, 1) end
    Echoes.count("phenomenon." .. tostring(kind.id))
    Log.info("phenomenon fired: " .. kind.id .. " at " .. sq:getX() .. "," .. sq:getY()
        .. (remembered and " (callback)" or "")
        .. (usedPlace and (" place=" .. tostring(place.theme) .. "/stage" .. stage) or "")
        .. string.format(" pressure=%.2f", pressure))
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
