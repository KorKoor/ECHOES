-- ECHOES zombie awareness (server / single player): a zombie that investigated a noise and found nothing
-- keeps searching nearby rooms instead of freezing. It never receives the player's position: each zombie is only
-- sent to a random indoor square near where it already is. Work is budgeted per pass and rate-limited in real time
-- (the periodic game event fires far more often per real second when sleeping or at high game speed).
-- Per-zombie persistence (Echoes.ZombieUtil.personality) decides how many rooms it keeps searching.
-- UNTESTED: isRespondingToPlayerSound / isMovingToPlayerSound / pathToLocationF are present in the 42.20 Javadoc.

require "Echoes/Core"
require "Echoes/ZombieUtil"

local Log, Config = Echoes.Log, Echoes.Config
local ZU = Echoes.ZombieUtil

local ZombieAwareness = {}
Echoes.ZombieAwareness = ZombieAwareness

local SCAN_RADIUS = 45        -- only zombies this close to a player are considered
local MAX_CANDIDATES = 150    -- nearest-first cap on zombies inspected per pass
local BUDGET = 6              -- new searches started per pass
-- The pass runs once per game minute, so these windows are in GAME minutes: they stay coherent whatever the sandbox day
-- length or game speed (real-time windows broke at long day lengths, where a game minute lasts many real seconds).
local LOST_WINDOW_MIN = 3.0   -- how long after hearing a sound a search may begin
local HOP_GAP_MIN = 0.9       -- minimum time between two search hops of the same zombie (one pass apart)
local MAX_HOPS = 3            -- extra hops a fully persistent zombie may make (everyone gets at least 1)
local MIN_INTERVAL_MS = 1500  -- real-time rate limit

-- A walkable indoor square 4..10 tiles from the zombie.
local function pickSearchSquare(z)
    local cell = getCell()
    local zx, zy, zz = math.floor(z:getX()), math.floor(z:getY()), z:getZ()
    for _ = 1, 8 do
        local ang = ZombRand(360) * math.pi / 180
        local dist = 4 + ZombRand(7)
        local sq = cell:getGridSquare(math.floor(zx + math.cos(ang) * dist), math.floor(zy + math.sin(ang) * dist), zz)
        if sq and sq:getRoom() and sq:isFree(false) then return sq end
    end
    return nil
end

local function tick()
    local players = ZU.players()
    if #players == 0 then return end
    local now = getTimestampMs()
    local wnow = getGameTime():getWorldAgeHours() * 60
    local started = 0

    for _, z in ipairs(ZU.nearbyZombies(players, SCAN_RADIUS, MAX_CANDIDATES)) do
        local md = z:getModData()
        if z:isRespondingToPlayerSound() or z:isMovingToPlayerSound() then
            md.echoesHeard = wnow
            md.echoesHops = 0
        elseif md.echoesHeard and started < BUDGET and ZU.isIdle(z, now)
            and (wnow - md.echoesHeard) <= LOST_WINDOW_MIN
            and (not md.echoesSearched or (wnow - md.echoesSearched) >= HOP_GAP_MIN)
            and (md.echoesHops or 0) < 1 + math.floor(ZU.personality(z).persist * MAX_HOPS) then
            local sq = pickSearchSquare(z)
            if sq then
                z:pathToLocationF(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ())
                md.echoesSearched = wnow
                md.echoesHops = (md.echoesHops or 0) + 1
                md.echoesHeard = wnow -- keeps the window open for the next hop of the chain
                ZU.setBusy(z, now, 5000)
                started = started + 1
            end
        end
    end
    if started > 0 then Log.debug("zombie searches started: " .. started) end
end

Events.EveryOneMinute.Add(function()
    if isClient() or not Config.isEnabled("AI") then return end
    if not Echoes.throttle("ZombieAwareness", MIN_INTERVAL_MS) then return end
    Echoes.safe("ZombieAwareness.tick", tick)
end)

Events.OnGameStart.Add(function() ZU.resetCache() end)
