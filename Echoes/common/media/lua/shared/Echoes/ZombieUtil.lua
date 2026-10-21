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
