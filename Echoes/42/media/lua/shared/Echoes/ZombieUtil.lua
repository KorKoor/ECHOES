-- ECHOES zombie helpers (shared): players list and "is this zombie free to be given a new intention".
-- Several behaviours (search, scent, pack alert) share one `echoesBusy` timestamp in the zombie's ModData so they
-- never fight over the same zombie.

require "Echoes/Core"

local ZombieUtil = {}
Echoes.ZombieUtil = ZombieUtil

function ZombieUtil.players()
    local out = {}
    if isServer() then
        local l = getOnlinePlayers()
        for i = 0, l:size() - 1 do out[#out + 1] = l:get(i) end
    else -- single player or split-screen: every local player (a missing slot returns nil)
        local n = 1
        local okN, num = pcall(getNumActivePlayers)
        if okN and type(num) == "number" and num > 0 then n = num end
        for i = 0, n - 1 do
            local p = getSpecificPlayer(i)
            if p and not p:isDead() then out[#out + 1] = p end
        end
        if #out == 0 then
            local p = getPlayer()
            if p then out[1] = p end
        end
    end
    return out
end

function ZombieUtil.playerKey(p)
    local ok, id = pcall(function() return p:getOnlineID() end)
    if ok and type(id) == "number" and id >= 0 then return "o" .. id end
    return "n" .. tostring(p:getPlayerNum())
end

-- The nearest player within `radius` of the zombie (and the squared distance), or nil.
function ZombieUtil.nearestPlayer(z, players, radius)
    local best, bestD2
    for _, p in ipairs(players) do
        local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
        local d2 = dx * dx + dy * dy
        if d2 <= radius * radius and (not bestD2 or d2 < bestD2) then best, bestD2 = p, d2 end
    end
    return best, bestD2
end

-- Zombies within `radius` of any player, nearest first, at most `limit`. Walks the whole zombie list (cheap: two
-- subtractions per zombie) so far-away zombies at the front of the list can never starve the ones next to a player.
-- The result of one scan (largest radius/limit asked for) is shared by every caller within CACHE_MS of real time, so
-- Tracking and ZombieAwareness do not each repeat the O(Z) walk and the sort.
local CACHE_MS = 400
local cache = { at = -1, radius = 0, limit = 0, found = nil }

local function scan(players, radius, limit)
    local list = getCell():getZombieList()
    local found = {}
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        local p, d2 = ZombieUtil.nearestPlayer(z, players, radius)
        if p then found[#found + 1] = { z = z, d2 = d2 } end
    end
    table.sort(found, function(a, b) return a.d2 < b.d2 end)
    while #found > limit do found[#found] = nil end
    return found
end

function ZombieUtil.nearbyZombies(players, radius, limit)
    local ok, now = pcall(getTimestampMs)
    now = ok and now or 0
    local fresh = cache.found and now - cache.at < CACHE_MS and cache.radius >= radius and cache.limit >= limit
    if not fresh then
        cache.radius, cache.limit = math.max(radius, 45), math.max(limit, 150)
        cache.found = scan(players, cache.radius, cache.limit)
        cache.at = now
    end
    local out = {}
    local r2 = radius * radius
    for _, e in ipairs(cache.found) do
        if e.d2 <= r2 then
            out[#out + 1] = e.z
            if #out >= limit then break end
        end
    end
    return out
end

function ZombieUtil.resetCache() cache.found = nil end

-- Each zombie gets stable individual traits the first time we see it, so a crowd does not behave like one animal:
--   nose    0.4..1.6  how far it smells a trail and how readily it follows it
--   persist 0..1      how many rooms it keeps searching after losing a sound
--   bold    0..1      how readily it joins another zombie's pursuit
function ZombieUtil.personality(z)
    local md = z:getModData()
    if not md.echoesP then
        md.echoesP = { nose = 0.4 + ZombRandFloat(0, 1.2), persist = ZombRandFloat(0, 1), bold = ZombRandFloat(0, 1) }
    end
    return md.echoesP
end

-- Idle = no target, not already walking to a sound, and not busy with another Echoes behaviour.
function ZombieUtil.isIdle(z, now)
    if z:getTarget() ~= nil then return false end
    if z:isRespondingToPlayerSound() or z:isMovingToPlayerSound() then return false end
    local busy = z:getModData().echoesBusy
    return busy == nil or now > busy
end

function ZombieUtil.setBusy(z, now, ms)
    z:getModData().echoesBusy = now + ms
end
