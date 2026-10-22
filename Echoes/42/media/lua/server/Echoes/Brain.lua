-- ECHOES brain (server / single player): a coordination layer that makes the horde act on what it has actually learned.
-- This is a planner, not reasoning: shared beliefs + utility-scored goals + squad bookkeeping, and every decision is
-- recorded with its reason (F7 prints the last ones) so its behaviour can be inspected and tuned.
--
--   Beliefs   One "board" per player: where ANY zombie last saw them (position, time, whether they went indoors) and a
--             confidence that decays over ~90 s. Nothing here is omniscient: it is only updated when a zombie that is
--             hunting the player really has line of sight (the same isCouldSee test the game uses).
--   Goals     For the zombies that currently have no target but a recent belief: INVESTIGATE the last sighting, then SWEEP
--             one of 8 sectors around it. For hunters: PRESS (keep chasing), FLANK (bold ones, with 3+ hunters) or CORDON
--             (when the player went indoors, cover the building's other doors while the rest press the main one).
--   Squad     Sweep sectors are assigned so no two zombies take the same one, and visited sectors are remembered for 3 minutes.
--   Budget    At most 6 decisions per second, round-robin, so a crowd costs a fixed amount.
-- Uses only calls already seen working in game: getTarget, isCouldSee, pathToLocationF, getGridSquare, doorSquares.
-- UNTESTED: whether the horde keeps the commitments (a path set by pathToLocationF can be replaced by the game's own
-- targeting), and the thresholds.

require "Echoes/Core"
require "Echoes/ZombieUtil"

local Log, Config = Echoes.Log, Echoes.Config
local ZU = Echoes.ZombieUtil

local Brain = {}
Echoes.Brain = Brain

local TICK_MS = 1000
local BUDGET = 6
local BELIEF_MS = 90000
local SECTOR_MEMORY_MS = 180000
local COMMIT_MS = 5000
local lastTick, cursor = 0, 0
local boards = {}
local decisions = { press = 0, flank = 0, cordon = 0, investigate = 0, sweep = 0 }
local recent = {}

local function note(kind, why)
    decisions[kind] = (decisions[kind] or 0) + 1
    Echoes.count("brain." .. kind)
    recent[#recent + 1] = kind .. ": " .. why
    if #recent > 5 then table.remove(recent, 1) end
end

local function board(p)
    local k = ZU.playerKey(p)
    boards[k] = boards[k] or { t = -1e9, x = 0, y = 0, z = 0, indoors = false, sectors = {}, doors = nil, doorsAt = -1e9 }
    return boards[k]
end

local function confidence(b, now)
    return Echoes.clamp(1.0 - (now - b.t) / BELIEF_MS, 0, 1)
end

-- Beliefs ----------------------------------------------------------------------------------------------------
local function seeing(p, zombies, now)
    local b = board(p)
    for _, z in ipairs(zombies) do
        if z:getTarget() == p then
            local zsq = z:getCurrentSquare()
            if zsq and zsq:isCouldSee(p:getPlayerNum()) then
                local sq = p:getCurrentSquare()
                b.t, b.x, b.y, b.z = now, p:getX(), p:getY(), p:getZ()
                b.indoors = (sq ~= nil and sq:getRoom() ~= nil)
                return b
            end
        end
    end
    return b
end

-- Goals --------------------------------------------------------------------------------------------------------
local SECTOR_ANGLES = {}
for i = 0, 7 do SECTOR_ANGLES[i + 1] = i * math.pi / 4 end

local function freeSquareNear(x, y, z)
    local cell = getCell()
    for _, r in ipairs({ 0, 1, 2 }) do
        for dx = -r, r do
            for dy = -r, r do
                local sq = cell:getGridSquare(math.floor(x) + dx, math.floor(y) + dy, math.floor(z))
                if sq and sq:isFree(false) then return sq end
            end
        end
    end
    return nil
end

-- Picks the next sweep sector around the last sighting that nobody took in the last 3 minutes.
local function nextSector(b, now)
    local start = 1 + ZombRand(8)
    for i = 0, 7 do
        local idx = 1 + (start - 1 + i) % 8
        if now - (b.sectors[idx] or -1e9) > SECTOR_MEMORY_MS then
            b.sectors[idx] = now
            local d = 9 + ZombRand(6)
            local sq = freeSquareNear(b.x + math.cos(SECTOR_ANGLES[idx]) * d, b.y + math.sin(SECTOR_ANGLES[idx]) * d, b.z)
            if sq then return sq, idx end
        end
    end
    return nil
end

local function goTo(z, sq, now)
    pcall(function() z:pathToLocationF(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ()) end)
    ZU.setBusy(z, now, COMMIT_MS)
end

-- The building's doors other than the one nearest the player, cached for 5 s (the scan is a few hundred squares).
local function exitDoors(p, b, now)
    if b.doors and now - b.doorsAt < 5000 then return b.doors end
    local all = Echoes.doorSquares(math.floor(b.x), math.floor(b.y), math.floor(b.z), 15)
    table.sort(all, function(a, c)
        local da = (a:getX() - b.x) ^ 2 + (a:getY() - b.y) ^ 2
        local dc = (c:getX() - b.x) ^ 2 + (c:getY() - b.y) ^ 2
        return da < dc
    end)
    table.remove(all, 1) -- the nearest door is the main entrance: the rest press it
    b.doors, b.doorsAt = all, now
    return all
end

local function decide(z, p, b, conf, hunters, now)
    local md = z:getModData()
    if md.echoesBusy and now <= md.echoesBusy then return end
    local pers = ZU.personality(z)
    local gunner = md.echoesRole == "gunner"
    if z:getTarget() == p then
        local d = math.sqrt((z:getX() - p:getX()) ^ 2 + (z:getY() - p:getY()) ^ 2)
        -- CORDON: the player is indoors; a bold hunter that is not already close covers another exit.
        if b.indoors and not gunner and pers.bold > 0.5 and d > 6 and d < 25 then
            local doors = exitDoors(p, b, now)
            if #doors > 0 then
                local sq = doors[1 + ZombRand(#doors)]
                goTo(z, sq, now)
                note("cordon", string.format("hunter %.0f tiles away covers a door at %d,%d (player indoors)", d, sq:getX(), sq:getY()))
                if Echoes.Mind and p == getPlayer() then Echoes.Mind.react("plan", 0.5) end
                return
            end
        end
        -- FLANK: with 3+ hunters, bold ones at a distance cut in from the side.
        if hunters >= 3 and not gunner and pers.bold > 0.6 and d >= 8 and d <= 20 then
            local ang = math.atan2(z:getY() - p:getY(), z:getX() - p:getX()) + ((ZombRand(2) == 0) and 1.2 or -1.2)
            local sq = freeSquareNear(p:getX() + math.cos(ang) * 6, p:getY() + math.sin(ang) * 6, p:getZ())
            if sq then
                goTo(z, sq, now)
                note("flank", string.format("bold hunter at %.0f tiles cuts in from the side (%d hunters)", d, hunters))
                return
            end
        end
        decisions.press = decisions.press + 1 -- default: keep chasing, no command needed
        return
    end
    -- No target but a recent belief: investigate, then sweep.
    if conf > 0.1 and ZU.isIdle(z, now) then
        local dl = math.sqrt((z:getX() - b.x) ^ 2 + (z:getY() - b.y) ^ 2)
        if dl > 6 then
            local sq = freeSquareNear(b.x, b.y, b.z)
            if sq then
                goTo(z, sq, now)
                note("investigate", string.format("lost the target, goes to the last sighting %.0f tiles away (confidence %.2f)", dl, conf))
            end
        else
            local sq, idx = nextSector(b, now)
            if sq then
                goTo(z, sq, now)
                note("sweep", string.format("at the last sighting, sweeps sector %d", idx))
            end
        end
    end
end

-- Loop ---------------------------------------------------------------------------------------------------------
local function tick()
    if isClient() then return end
    local now = getTimestampMs()
    if now - lastTick < TICK_MS then return end
    lastTick = now
    local players = ZU.players()
    for _, p in ipairs(players) do
        local zs = ZU.nearbyZombies({ p }, 40, 60)
        local b = seeing(p, zs, now)
        local conf = confidence(b, now)
        local hunters = 0
        for _, z in ipairs(zs) do if z:getTarget() == p then hunters = hunters + 1 end end
        -- Round-robin over the crowd with a fixed budget.
        local n = #zs
        if n > 0 then
            for i = 1, math.min(BUDGET, n) do
                cursor = (cursor % n) + 1
                decide(zs[cursor], p, b, conf, hunters, now)
            end
        end
    end
end

Events.OnTick.Add(function() if Config.isEnabled("Brain") then Echoes.safe("Brain.tick", tick) end end)
Events.OnGameStart.Add(function() lastTick, cursor, boards, recent = 0, 0, {}, {}; decisions = { press = 0, flank = 0, cordon = 0, investigate = 0, sweep = 0 } end)

function Brain.summary(player)
    local b = boards[ZU.playerKey(player)]
    local now = getTimestampMs()
    local belief = b and b.t > -1e8 and string.format("last seen %.0fs ago conf=%.2f indoors=%s", (now - b.t) / 1000, confidence(b, now), tostring(b.indoors)) or "no sighting yet"
    return "brain: " .. belief .. string.format(" | press=%d flank=%d cordon=%d investigate=%d sweep=%d", decisions.press, decisions.flank, decisions.cordon, decisions.investigate, decisions.sweep)
end

function Brain.recent() return recent end