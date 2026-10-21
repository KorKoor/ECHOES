-- ECHOES tracking (server / single player): zombies that follow SCENT, smell BLOOD and pass ATTENTION to each other.
--
-- Scent: each player leaves a trail of past positions. A point's strength grows with bleeding wounds and exertion
-- and fades with time, much faster in rain and wind. A zombie with no target that comes near a fresh enough point
-- walks along the trail toward newer points. It is never told where the player IS: points younger than
-- MIN_AGE_MIN game minutes (about 12 real seconds at the default day length) are out of reach, so it follows where
-- you went, arriving behind you. A player who stands still does not refresh a point; a new one is laid only every
-- STILL_REFRESH_MIN minutes and then ages like any other.
--
-- Blood: a keen-nosed idle zombie may walk to a nearby square with blood on the floor; each square is "used up"
-- for BLOOD_COOLDOWN_MIN minutes so zombies do not loop on old stains.
--
-- Pack alert: when a zombie is chasing a target it can see, idle neighbours drift toward THAT ZOMBIE (its moans),
-- not toward the target. Boldness (per-zombie personality) decides who joins.
--
-- Budgeted: few zombies per pass, nearest first, rate-limited in real time, one shared `echoesBusy` flag per
-- zombie. Memory is pruned. UNTESTED.

require "Echoes/Core"
require "Echoes/ZombieUtil"

local Log, Config = Echoes.Log, Echoes.Config
local ZU = Echoes.ZombieUtil

local Tracking = {}
Echoes.Tracking = Tracking

local TRAIL_MAX = 120
local MIN_AGE_MIN = 5.0          -- game minutes: newer trail points are out of reach
local SAFE_DIST = 7.0             -- tiles: trail points this close to the player right now are never followed
local STILL_REFRESH_MIN = 10.0   -- a standing player lays a new point only this often
local BASE_LIFE_MIN = 25         -- game minutes a scent point lasts in still, dry air
local TRAIL_FORGET_MIN = 90      -- a trail whose newest point is older than this is dropped
local BLOOD_COOLDOWN_MIN = 20
local SCAN_RADIUS = 32
local MAX_CANDIDATES = 120
local SCENT_BUDGET = 5
local PACK_BUDGET = 4
local PACK_RADIUS = 12
local MIN_INTERVAL_MS = 1500     -- real-time rate limit

local trails = {}      -- player key -> array of points {x,y,z,t,s}
local bloodUsed = {}   -- "x,y,z" -> game minute until which the stain is ignored

local function nowMin() return getGameTime():getWorldAgeHours() * 60 end

-- Strength of the scent a player lays down right now (0..1).
local function laidStrength(p)
    local s = 0.25
    local ok, parts = pcall(function() return p:getBodyDamage():getNumPartsBleeding() end)
    if ok and type(parts) == "number" then s = s + math.min(0.45, 0.15 * parts) end
    local running = false
    pcall(function() running = p:isRunning() or p:isSprinting() end)
    if running then s = s + 0.15 end
    local wet = Echoes.statNorm(p, "WETNESS")
    if wet then s = s + 0.05 * wet end
    return Echoes.clamp(s, 0, 1)
end

local function record(p, wnow)
    local key = ZU.playerKey(p)
    local tr = trails[key]
    if not tr then tr = {}; trails[key] = tr end
    local x, y, z = p:getX(), p:getY(), p:getZ()
    local last = tr[#tr]
    local s = laidStrength(p)
    if last and (x - last.x) ^ 2 + (y - last.y) ^ 2 < 1.0 and last.z == z then
        if wnow - last.t < STILL_REFRESH_MIN then
            last.s = math.max(last.s, s) -- same spot: keep the old point, never make it look fresh
            return
        end
    end
    tr[#tr + 1] = { x = x, y = y, z = z, t = wnow, s = s }
    if #tr > TRAIL_MAX then table.remove(tr, 1) end
end

-- Forget trails of players that left, and expired blood stains.
local function prune(wnow)
    for key, tr in pairs(trails) do
        local newest = tr[#tr]
        if not newest or wnow - newest.t > TRAIL_FORGET_MIN then trails[key] = nil end
    end
    for k, until_ in pairs(bloodUsed) do
        if wnow > until_ then bloodUsed[k] = nil end
    end
end

-- Remaining lifetime of a point in game minutes (rain and wind wash scent away).
local function lifeMinutes()
    local c = getClimateManager()
    local rain, wind = 0, 0
    pcall(function() rain = c:getRainIntensity(); wind = c:getWindIntensity() end)
    return math.max(4, BASE_LIFE_MIN * (1 - 0.7 * rain) * (1 - 0.3 * wind))
end

-- For a zombie: the nearest still-fresh point within its smelling range, then a point a few steps newer.
local function followTarget(z, tr, life, wnow, mult, owner)
    local zx, zy, zz = z:getX(), z:getY(), z:getZ()
    local nose = ZU.personality(z).nose
    local ox, oy = owner:getX(), owner:getY()
    local bestI, bestD2
    for i = 1, #tr do
        local pt = tr[i]
        local age = wnow - pt.t
        -- scent close to where the player stands NOW is never used: that would walk zombies onto a player who is
        -- hiding or resting. They follow the trail only while it is still more than SAFE_DIST tiles from the player.
        local pdx, pdy = pt.x - ox, pt.y - oy
        if age >= MIN_AGE_MIN and math.abs(pt.z - zz) < 1.0 and pdx * pdx + pdy * pdy > SAFE_DIST * SAFE_DIST then
            local s = pt.s * math.max(0, 1 - age / life) * mult
            if s > 0.12 then
                local range = (4 + 7 * s) * nose
                local dx, dy = pt.x - zx, pt.y - zy
                local d2 = dx * dx + dy * dy
                if d2 <= range * range and (not bestD2 or d2 < bestD2) then bestI, bestD2 = i, d2 end
            end
        end
    end
    if not bestI then return nil end
    -- head toward newer points, but never to one younger than MIN_AGE_MIN
    local j = bestI
    for k = bestI + 1, math.min(#tr, bestI + 3) do
        local qdx, qdy = tr[k].x - ox, tr[k].y - oy
        if wnow - tr[k].t >= MIN_AGE_MIN and qdx * qdx + qdy * qdy > SAFE_DIST * SAFE_DIST then j = k else break end
    end
    if j == bestI and bestD2 < 4 then return nil end -- already standing on the point
    return tr[j]
end

local function bloodSquare(z, wnow)
    local cell = getCell()
    local zx, zy, zz = math.floor(z:getX()), math.floor(z:getY()), z:getZ()
    for _ = 1, 4 do
        local sq = cell:getGridSquare(zx + ZombRand(-7, 8), zy + ZombRand(-7, 8), zz)
        if sq and sq:haveBloodFloor() then
            local key = sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
            if not bloodUsed[key] or wnow > bloodUsed[key] then
                bloodUsed[key] = wnow + BLOOD_COOLDOWN_MIN
                return sq
            end
        end
    end
    return nil
end

local function tick()
    local players = ZU.players()
    if #players == 0 then return end
    local now = getTimestampMs()
    local wnow = nowMin()
    local life = lifeMinutes()
    local mult = Config.get("ScentStrength")
    local scentOn, packOn = Config.isEnabled("Scent"), Config.isEnabled("PackAlert")
    local zombies = ZU.nearbyZombies(players, SCAN_RADIUS, MAX_CANDIDATES)
    local scentStarted, packStarted = 0, 0

    -- Classify once (each isIdle / target check is several Java calls): who is chasing something it can see, and who
    -- is idle. The pack-alert pass then only walks chasers x idle zombies, not every pair of candidates.
    local idle, chasers = {}, {}
    for _, z in ipairs(zombies) do
        if z:getTarget() ~= nil then
            if packOn and z:isTargetVisible() then chasers[#chasers + 1] = z end
        elseif ZU.isIdle(z, now) then
            idle[#idle + 1] = z
        end
    end

    if scentOn then
        for _, z in ipairs(idle) do
            if scentStarted >= SCENT_BUDGET then break end
            if ZombRandFloat(0, 1) < 0.5 * math.min(1, ZU.personality(z).nose) then
                local owner = ZU.nearestPlayer(z, players, SCAN_RADIUS)
                local tr = owner and trails[ZU.playerKey(owner)]
                local pt = tr and followTarget(z, tr, life, wnow, mult, owner)
                if pt then
                    z:pathToLocationF(pt.x, pt.y, pt.z)
                    ZU.setBusy(z, now, 4000)
                    scentStarted = scentStarted + 1
                elseif ZU.personality(z).nose > 0.8 and ZombRandFloat(0, 1) < 0.15 then
                    local sq = bloodSquare(z, wnow)
                    if sq then
                        z:pathToLocationF(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ())
                        ZU.setBusy(z, now, 5000)
                            scentStarted = scentStarted + 1
                    end
                end
            end
        end
    end

    -- idle neighbours drift toward THE CHASER (its moans), not toward its target
    for _, c in ipairs(chasers) do
        if packStarted >= PACK_BUDGET then break end
        local cx, cy, cz = c:getX(), c:getY(), c:getZ()
        for _, o in ipairs(idle) do
            if packStarted >= PACK_BUDGET then break end
            if ZU.isIdle(o, now) then -- setBusy marks a zombie sent somewhere this pass
                local dx, dy = o:getX() - cx, o:getY() - cy
                if dx * dx + dy * dy <= PACK_RADIUS * PACK_RADIUS
                    and ZombRandFloat(0, 1) < 0.1 + 0.4 * ZU.personality(o).bold then
                    o:pathToLocationF(cx, cy, cz)
                    ZU.setBusy(o, now, 6000)
                    packStarted = packStarted + 1
                end
            end
        end
    end
    if scentStarted + packStarted > 0 then
        Log.debug(string.format("tracking: scent=%d pack=%d (life %.1f min)", scentStarted, packStarted, life))
    end
end

Events.EveryOneMinute.Add(function()
    if isClient() or not Config.isEnabled("AI") then return end
    local wnow = nowMin()
    for _, p in ipairs(ZU.players()) do
        if not p:isDead() then Echoes.safe("Tracking.record", record, p, wnow) end
    end
    if not Echoes.throttle("Tracking", MIN_INTERVAL_MS) then return end
    Echoes.safe("Tracking.tick", tick)
end)

Events.EveryTenMinutes.Add(function()
    if not isClient() then Echoes.safe("Tracking.prune", prune, nowMin()) end
end)

-- A different world (new game / another save) must not inherit scent or stains from the previous one.
Events.OnGameStart.Add(function()
    trails = {}
    bloodUsed = {}
    ZU.resetCache()
end)
