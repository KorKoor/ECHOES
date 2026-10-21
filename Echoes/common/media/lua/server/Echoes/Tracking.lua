-- ECHOES tracking (server / single player): zombies that follow SCENT and pass ATTENTION to each other.
--
-- Scent: the player leaves a trail of past positions. Each point carries a strength that grows with bleeding wounds
-- and exertion, and fades with time, faster in rain and wind. A zombie with no target that comes near a fresh enough
-- trail point walks along the trail toward the newer points. It is NEVER told where the player is now: the newest
-- points (the last ~seconds) are out of reach, so it follows where you went, not where you are.
--
-- Pack alert: when a zombie is actively chasing a target it can see, idle zombies near IT drift toward IT (moans),
-- not toward the target.
--
-- Budgeted: few zombies per tick, only those near players, one shared `echoesBusy` flag per zombie. UNTESTED.

local Log, Config = Echoes.Log, Echoes.Config
local ZU = Echoes.ZombieUtil

local Tracking = {}
Echoes.Tracking = Tracking

local TRAIL_MAX = 120
local MIN_AGE_MIN = 1.0       -- game minutes: the newest points are out of reach (never reveals the current position)
local BASE_LIFE_MIN = 25      -- game minutes a scent point lasts in still, dry air
local SCAN_RADIUS = 32
local MAX_SCAN = 120
local SCENT_BUDGET = 5
local PACK_BUDGET = 4
local PACK_RADIUS = 12

local trails = {}   -- player key -> array of points {x,y,z,t,s}

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

local function record(p)
    local key = ZU.playerKey(p)
    local tr = trails[key]
    if not tr then tr = {}; trails[key] = tr end
    local x, y, z = p:getX(), p:getY(), p:getZ()
    local last = tr[#tr]
    local s = laidStrength(p)
    if last and (x - last.x) ^ 2 + (y - last.y) ^ 2 < 1.0 and last.z == z then
        last.t = nowMin(); last.s = math.max(last.s, s) -- standing still keeps one fresh point
        return
    end
    tr[#tr + 1] = { x = x, y = y, z = z, t = nowMin(), s = s }
    if #tr > TRAIL_MAX then table.remove(tr, 1) end
end

-- Remaining strength of a point, 0 when gone. Rain and wind wash scent away.
local function lifeMinutes()
    local c = getClimateManager()
    local rain, wind = 0, 0
    pcall(function() rain = c:getRainIntensity(); wind = c:getWindIntensity() end)
    return math.max(4, BASE_LIFE_MIN * (1 - 0.7 * rain) * (1 - 0.3 * wind))
end

local function strengthNow(pt, life, now)
    local age = now - pt.t
    if age < 0 then return 0, age end
    return pt.s * math.max(0, 1 - age / life) * Config.get("ScentStrength"), age
end

-- For a zombie: the nearest still-fresh point within its smelling range, then a point a few steps newer.
local function followTarget(z, tr, life, now)
    local zx, zy = z:getX(), z:getY()
    local bestI, bestD2
    for i = 1, #tr do
        local pt = tr[i]
        local s, age = strengthNow(pt, life, now)
        if s > 0.12 and age >= MIN_AGE_MIN and math.abs(pt.z - z:getZ()) < 1.0 then
            local range = 4 + 7 * s
            local dx, dy = pt.x - zx, pt.y - zy
            local d2 = dx * dx + dy * dy
            if d2 <= range * range and (not bestD2 or d2 < bestD2) then bestI, bestD2 = i, d2 end
        end
    end
    if not bestI then return nil end
    -- head toward newer points, but never to one younger than MIN_AGE_MIN
    local j = bestI
    for k = bestI + 1, math.min(#tr, bestI + 3) do
        if now - tr[k].t >= MIN_AGE_MIN then j = k else break end
    end
    if j == bestI and bestD2 < 4 then return nil end -- already standing on the point
    return tr[j]
end

local function tick()
    local players = ZU.players()
    if #players == 0 then return end
    local now = getTimestampMs()
    local wnow = nowMin()
    local life = lifeMinutes()
    local list = getCell():getZombieList()
    local n = math.min(list:size(), MAX_SCAN)
    local scentStarted, packStarted = 0, 0
    local scentOn = Config.isEnabled("Scent")
    local packOn = Config.isEnabled("PackAlert")

    for i = 0, n - 1 do
        local z = list:get(i)
        local near, owner = ZU.nearAnyPlayer(z, players, SCAN_RADIUS)
        if near then
            if scentOn and scentStarted < SCENT_BUDGET and ZU.isIdle(z, now) and ZombRandFloat(0, 1) < 0.5 then
                local tr = trails[ZU.playerKey(owner)]
                if tr then
                    local pt = followTarget(z, tr, life, wnow)
                    if pt then
                        z:pathToLocationF(pt.x, pt.y, pt.z)
                        ZU.setBusy(z, now, 4000)
                        scentStarted = scentStarted + 1
                    end
                end
            elseif packOn and packStarted < PACK_BUDGET and z:getTarget() ~= nil and z:isTargetVisible() then
                -- idle neighbours drift toward THIS zombie
                local zx, zy, zz = z:getX(), z:getY(), z:getZ()
                for k = 0, n - 1 do
                    if packStarted >= PACK_BUDGET then break end
                    local o = list:get(k)
                    if o ~= z then
                        local dx, dy = o:getX() - zx, o:getY() - zy
                        if dx * dx + dy * dy <= PACK_RADIUS * PACK_RADIUS and ZU.isIdle(o, now)
                            and ZombRandFloat(0, 1) < 0.3 then
                            o:pathToLocationF(zx, zy, zz)
                            ZU.setBusy(o, now, 6000)
                            packStarted = packStarted + 1
                        end
                    end
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
    for _, p in ipairs(ZU.players()) do
        if not p:isDead() then Echoes.safe("Tracking.record", record, p) end
    end
    Echoes.safe("Tracking.tick", tick)
end)
