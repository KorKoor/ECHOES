-- ECHOES zombie helpers (shared): players list and "is this zombie free to be given a new intention".
-- Several behaviours (search, scent, pack alert) share one `echoesBusy` timestamp in the zombie's ModData so they
-- never fight over the same zombie.

local ZombieUtil = {}
Echoes.ZombieUtil = ZombieUtil

function ZombieUtil.players()
    local out = {}
    if isServer() then
        local l = getOnlinePlayers()
        for i = 0, l:size() - 1 do out[#out + 1] = l:get(i) end
    else
        local p = getPlayer()
        if p then out[1] = p end
    end
    return out
end

function ZombieUtil.playerKey(p)
    local ok, id = pcall(function() return p:getOnlineID() end)
    if ok and type(id) == "number" and id >= 0 then return "o" .. id end
    return "n" .. tostring(p:getPlayerNum())
end

function ZombieUtil.nearAnyPlayer(z, players, radius)
    for _, p in ipairs(players) do
        local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
        if dx * dx + dy * dy <= radius * radius then return true, p end
    end
    return false
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
