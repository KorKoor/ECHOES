-- ECHOES senses (client): directional audio cues and loss of reference in the dark.
--  * Cues come from the REAL position of real zombies that you cannot see, so they never lie.
--  * `uncertain()` blurs where our own sounds seem to come from at night / under pressure.
-- Nothing here reveals or hides anything beyond what the world already contains. UNTESTED.

require "Echoes/Core"

local Log, Config = Echoes.Log, Echoes.Config

local Senses = {}
Echoes.Senses = Senses

local MIN_D, MAX_D = 4, 12
local COOLDOWN_MS = 20000
local lastCue = 0

-- Positional blur in tiles: ~0.6 in daylight, up to ~3 on a dark night with high pressure.
function Senses.uncertain(x, y, z)
    if not Config.isEnabled("Senses") then return x, y, z end
    local night = Echoes.clamp(getClimateManager():getNightStrength(), 0, 1)
    local pressure = Echoes.Psyche and Echoes.Psyche.pressure or 0
    local r = 0.6 + 2.4 * night * (0.5 + 0.5 * pressure)
    return x + ZombRandFloat(-r, r), y + ZombRandFloat(-r, r), z
end

-- Nearest zombie on the same level that is within hearing range and out of sight.
local function nearestUnseen(player)
    local list = getCell():getZombieList()
    local pnum = player:getPlayerNum()
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local best, bestD2, bestSq
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        local dx, dy = z:getX() - px, z:getY() - py
        local d2 = dx * dx + dy * dy
        if d2 >= MIN_D * MIN_D and d2 <= MAX_D * MAX_D and math.abs(z:getZ() - pz) < 0.5
            and (not bestD2 or d2 < bestD2) then
            local zsq = z:getCurrentSquare()
            if zsq and not zsq:isCouldSee(pnum) then best, bestD2, bestSq = z, d2, zsq end
        end
    end
    return best, bestSq
end

local function update(player)
    if player:getVehicle() or player:isAsleep() then return end
    local now = getTimestampMs()
    if now - lastCue < COOLDOWN_MS then return end

    local z, zsq = nearestUnseen(player)
    if not z then return end
    local f = Echoes.Acoustics.factor(zsq, player, { maxDist = 16 })
    if f < 0.08 or ZombRandFloat(0, 1) > 0.35 then return end

    local names = Echoes.Sounds.resolve("zombieCue", {}, { "shuffle", "drag", "scrape" }, { "attack", "bite", "hit" })
    if Echoes.Sounds.playAt(z:getX(), z:getY(), z:getZ(), names, 0.5 * f, 0.08) then
        lastCue = now
        Log.debug(string.format("unseen zombie cue (factor %.2f)", f))
    end
end

Events.EveryOneMinute.Add(function()
    if not Config.isEnabled("Senses") then return end
    if not Echoes.throttle("Senses", 1500) then return end
    local player = getPlayer()
    if not player or player:isDead() then return end
    Echoes.safe("Senses.update", update, player)
end)
