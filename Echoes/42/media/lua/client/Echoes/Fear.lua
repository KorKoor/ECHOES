-- ECHOES fear (client): how scared the character is right now (0..1), expressed through the body, not a bar.
-- Inputs: zombies the game says you can see / are chasing you, low health, the slow psychological pressure at night,
-- and short "shocks" from unexplained events. Outputs: a heartbeat that speeds up with fear and a pulse the screen
-- overlay can use. It does NOT touch PANIC/STRESS or any vanilla stat. UNTESTED.

require "Echoes/Core"

local Log, Config = Echoes.Log, Echoes.Config

local Fear = {}
Echoes.Fear = Fear

Fear.level = 0.0
Fear.lastBeat = 0       -- ms timestamp of the last heartbeat (for visual pulse)
local shockValue = 0.0
local beating = false
local chainGen = 0

-- Called by the Director when something unexplained happens.
function Fear.shock(v)
    shockValue = Echoes.clamp(shockValue + (v or 0.2), 0, 1)
end

local function compute(player)
    local stats = player:getStats()
    local visible, chasing = 0, 0
    pcall(function() visible = stats:getNumVisibleZombies() end)
    pcall(function() chasing = stats:getNumChasingZombies() end)
    local vis = Echoes.clamp(visible / 6, 0, 1)
    local chase = Echoes.clamp(chasing / 4, 0, 1)

    local low = 0
    local ok, hp = pcall(function() return player:getBodyDamage():getOverallBodyHealth() end)
    if ok and type(hp) == "number" then low = Echoes.clamp((60 - hp) / 60, 0, 1) end

    local night = Echoes.clamp(getClimateManager():getNightStrength(), 0, 1)
    local pressure = Echoes.Psyche and Echoes.Psyche.pressure or 0

    local raw = 0.40 * vis + 0.30 * chase + 0.15 * pressure * (0.5 + 0.5 * night) + 0.15 * low + shockValue
    Fear.level = Echoes.clamp(Fear.level + (raw - Fear.level) * 0.5, 0, 1)
    shockValue = shockValue * 0.6
end

local function beat(gen)
    if gen ~= chainGen then return end -- stale chain from a previous game
    local player = getPlayer()
    if not Config.isEnabled("Fear") or Fear.level < 0.3 or not player or player:isDead() then
        beating = false -- also stops the chain when the player dies
        return
    end
    Echoes.safe("Fear.beat", function() -- a failure here must not kill the chain
        local names = Echoes.Sounds.resolve("heartbeat", {}, { "heartbeat", "heart_beat", "heartbeats" }, {})
        Echoes.Sounds.playAt(player:getX(), player:getY(), player:getZ(), names, 0.15 + 0.45 * Fear.level, 0.02, false, true)
        Fear.lastBeat = getTimestampMs()
    end)
    Echoes.Timer.after(math.floor(1150 - 650 * Fear.level), function() beat(gen) end)
end

Events.OnGameStart.Add(function()
    Fear.level = 0.0
    Fear.lastBeat = 0
    shockValue = 0.0
    beating = false
    chainGen = chainGen + 1
end)

Events.EveryOneMinute.Add(function()
    if not Config.isEnabled("Fear") then Fear.level = 0; return end
    local player = getPlayer()
    if not player or player:isDead() then return end
    Echoes.safe("Fear.compute", compute, player)
    if Fear.level >= 0.35 and not beating then
        beating = true
        Log.debug(string.format("fear %.2f: heartbeat starts", Fear.level))
        beat(chainGen)
    end
end)
