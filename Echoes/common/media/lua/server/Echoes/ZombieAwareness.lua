-- ECHOES zombie awareness (server / single player): a zombie that investigated a noise and found nothing
-- keeps searching nearby rooms instead of freezing. It never receives the player's position: each zombie is only
-- sent to a random indoor square near where it already is. Work is budgeted per tick. UNTESTED:
-- isRespondingToPlayerSound / isMovingToPlayerSound / pathToLocationF are present in the 42.20 Javadoc.

local Log, Config = Echoes.Log, Echoes.Config

local ZombieAwareness = {}
Echoes.ZombieAwareness = ZombieAwareness

local SCAN_RADIUS = 45        -- only zombies this close to a player are considered
local MAX_SCAN = 400          -- zombies inspected per tick
local BUDGET = 6              -- new searches started per tick
local LOST_WINDOW_MS = 12000  -- how long after hearing a sound a search may begin
local COOLDOWN_MS = 90000     -- per zombie
local MAX_HOPS = 3

local function playerList()
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

local function nearAnyPlayer(z, players)
    for _, p in ipairs(players) do
        local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
        if dx * dx + dy * dy <= SCAN_RADIUS * SCAN_RADIUS then return true end
    end
    return false
end

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
    local players = playerList()
    if #players == 0 then return end
    local list = getCell():getZombieList()
    local n = math.min(list:size(), MAX_SCAN)
    local now = getTimestampMs()
    local started = 0

    for i = 0, n - 1 do
        local z = list:get(i)
        if nearAnyPlayer(z, players) then
            local md = z:getModData()
            local responding = z:isRespondingToPlayerSound() or z:isMovingToPlayerSound()
            if responding then
                md.echoesHeard = now
                md.echoesHops = 0
            elseif md.echoesHeard and z:getTarget() == nil and started < BUDGET
                and (md.echoesBusy == nil or now > md.echoesBusy)
                and (now - md.echoesHeard) <= LOST_WINDOW_MS
                and (not md.echoesSearched
                    or ((now - md.echoesSearched) > 8000
                        and ((md.echoesHops or 0) < 1 + math.floor(Echoes.ZombieUtil.personality(z).persist * MAX_HOPS)
                            or (now - md.echoesSearched) > COOLDOWN_MS))) then
                local sq = pickSearchSquare(z)
                if sq then
                    z:pathToLocationF(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ())
                    md.echoesSearched = now
                    md.echoesBusy = now + 5000
                    md.echoesHops = (md.echoesHops or 0) + 1
                    md.echoesHeard = now -- allow a short chain of room-to-room hops
                    started = started + 1
                end
            end
        end
    end
    if started > 0 then Log.debug("zombie searches started: " .. started) end
end

Events.EveryOneMinute.Add(function()
    if isClient() or not Config.isEnabled("AI") then return end
    Echoes.safe("ZombieAwareness.tick", tick)
end)
