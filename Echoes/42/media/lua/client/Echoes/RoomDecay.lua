-- ECHOES room decay (client, single player / host): rooms drift from "lived in" to "abandoned" as days pass.
-- Progress is a pure function of world age and a per-room hash, remembered in ModData. It is applied to ONE nearby room
-- per pass, only to rooms the player cannot see and has not been in for the last LIVED_IN_DAYS days, so lamps never go
-- off in front of the player or in their own base. Effects use existing objects only: some lamps are found off, some
-- flicker when you enter; leaky rooms drip when it rains. Players can still switch lamps on when there is power.
-- Not applied on multiplayer clients (world changes must be server-authoritative). UNTESTED.

require "Echoes/Core"

local Log, Config = Echoes.Log, Echoes.Config

local RoomDecay = {}
Echoes.RoomDecay = RoomDecay

local OFF_CHANCE = { 0.0, 0.10, 0.25, 0.45 }  -- index = stage + 1
local FLAKY_PER_STAGE = 0.12

local function stageFor(days)
    if days < 10 then return 0 end
    if days < 25 then return 1 end
    if days < 45 then return 2 end
    return 3
end

-- Deterministic pseudo-random 0..1 from two integers.
local function hash01(a, b)
    return (math.abs(a * 73856093 + b * 19349663) % 1000) / 1000
end

local lastRoomId = nil

-- Leaky rooms (stage 2+, ~30% of rooms by hash): dripping sounds while it rains, only for the room you are in.
local function maybeDrip(player, room, stage)
    if stage < 2 then return end
    local id = room:getRoomDef():getID()
    if hash01(id, 7) > 0.30 then return end
    local ok, rain = pcall(function() return getClimateManager():getRainIntensity() end)
    if not ok or type(rain) ~= "number" or rain < 0.15 then return end
    if ZombRandFloat(0, 1) > 0.5 then return end
    local names = Echoes.Sounds.resolve("drip", {}, { "drip", "droplet" }, { "blood" })
    local sq = room:getRandomFreeSquare()
    if sq and Echoes.Sounds.playAt(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ(), names, 0.3 + 0.3 * rain, 0.1) then
        Log.debug("drip in leaky room")
    end
end

local function applyToRoom(room, rec, stage)
    local switches = room:getLightSwitches()
    local changed = 0
    for i = 0, switches:size() - 1 do
        local sw = switches:get(i)
        local sq = sw:getSquare()
        local roll = hash01(sq:getX(), sq:getY() * 31 + i)
        local md = sw:getModData()
        if roll < OFF_CHANCE[stage + 1] then
            if sw:isActivated() then sw:setActivated(false); changed = changed + 1 end
        elseif roll < OFF_CHANCE[stage + 1] + FLAKY_PER_STAGE * stage then
            md.echoesFlaky = true
        end
    end
    rec.stage = stage
    Log.debug("room decay stage " .. stage .. ", lamps switched off: " .. changed)
end

local function flickerOnEntry(room)
    local switches = room:getLightSwitches()
    for i = 0, switches:size() - 1 do
        local sw = switches:get(i)
        if sw:getModData().echoesFlaky and sw:isActivated() and ZombRandFloat(0, 1) < 0.5 then
            local on = true
            for k, gap in ipairs({ 80, 160, 260, 340 }) do
                Echoes.Timer.after(gap, function() on = not on; sw:setActivated(on) end)
            end
            Echoes.Timer.after(520, function() sw:setActivated(true) end)
            return
        end
    end
end

local LIVED_IN_DAYS = 3 -- a room the player was in during the last days is "lived in": it is never decayed behind their back

local function record(id)
    local store = ModData.getOrCreate("EchoesRooms")
    local key = tostring(id)
    local rec = store[key]
    if not rec then rec = { stage = -1 }; store[key] = rec end
    return rec
end

-- Decay is applied to ONE nearby room per pass, and only to rooms the player cannot see right now and has not
-- lived in, so a lamp never turns itself off in front of the player or in their own base.
local function decayUnobserved(player, currentRoom, stage, days)
    local cell, pnum = getCell(), player:getPlayerNum()
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), player:getZ()
    for _ = 1, 6 do
        local sq = cell:getGridSquare(px + ZombRand(-25, 26), py + ZombRand(-25, 26), pz)
        local room = sq and sq:getRoom()
        if room and room ~= currentRoom and not sq:isCouldSee(pnum) and room:hasLightSwitches() then
            local rec = record(room:getRoomDef():getID())
            if rec.stage < stage then
                if rec.seen and days - rec.seen < LIVED_IN_DAYS then
                    rec.stage = stage -- lived in: keep exactly as the player keeps it
                else
                    applyToRoom(room, rec, stage)
                end
                return
            end
        end
    end
end

local function update(player)
    local sq = player:getCurrentSquare()
    local room = sq and sq:getRoom()
    local days = getGameTime():getWorldAgeHours() / 24
    local stage = stageFor(days)

    if not room then
        lastRoomId = nil
    else
        local id = room:getRoomDef():getID()
        local roomChanged = (id ~= lastRoomId)
        lastRoomId = id
        maybeDrip(player, room, stage) -- leaks do not need electricity or lamps
        if getWorld():isHydroPowerOn() and room:hasLightSwitches() then
            local rec = record(id)
            rec.seen = days                      -- the player is here now: this room is lived in
            if rec.stage < stage then rec.stage = stage end -- it stays as they see it
            if roomChanged then flickerOnEntry(room) end
        end
    end

    if stage > 0 and getWorld():isHydroPowerOn() then decayUnobserved(player, room, stage, days) end
end

-- A new game/save must not inherit "last room" from the previous one.
Events.OnGameStart.Add(function() lastRoomId = nil end)

Events.EveryOneMinute.Add(function()
    if isClient() or not Config.isEnabled("Decay") then return end
    local player = getPlayer()
    if not player or player:isDead() then return end
    Echoes.safe("RoomDecay.update", update, player)
end)
