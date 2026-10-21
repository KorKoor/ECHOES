-- ECHOES phenomena (client): world-touching phenomena with a possible natural explanation.
--  * door_ajar    : a door you left closed is found slightly open (wind? someone?).
--  * light_flicker: a lit room nearby flickers; it may come back on, or stay off.
-- They change real objects, so they run only in single player or on the host, never on a pure MP client.
-- Registered into the Director through Phenomena.kinds. UNTESTED (IsoDoor / IsoLightSwitch calls unverified from Lua).

local Log = Echoes.Log

local Phenomena = {}
Echoes.Phenomena = Phenomena

local RADIUS = 14

-- Samples squares around `center` (a haunted place) when given, otherwise around the player.
local function eachNearbySquare(player, tries, fn, center)
    local cell = getCell()
    local c = center or player
    local px, py, pz = math.floor(c:getX()), math.floor(c:getY()), center and center:getZ() or player:getZ()
    for _ = 1, tries do
        local sq = cell:getGridSquare(px + ZombRand(-RADIUS, RADIUS + 1), py + ZombRand(-RADIUS, RADIUS + 1), pz)
        if sq then
            local r = fn(sq)
            if r then return r end
        end
    end
    return nil
end

local function farEnough(player, sq, minD)
    local dx, dy = sq:getX() - player:getX(), sq:getY() - player:getY()
    return dx * dx + dy * dy >= minD * minD
end

-- door_ajar -------------------------------------------------------------------------------------
local function runDoorAjar(player, near)
    local pnum = player:getPlayerNum()
    local found = eachNearbySquare(player, 80, function(sq)
        local d = sq:getDoor(true) or sq:getDoor(false)
        if d and farEnough(player, sq, 6) and not sq:isCouldSee(pnum)
            and not d:IsOpen() and not d:isLocked() and not d:isBarricaded() then
            return { sq = sq, door = d }
        end
    end, near)
    if not found then return nil end
    found.door:ToggleDoorSilent()
    -- Faint creak, quieter than a real door, scaled by acoustics.
    local names = Echoes.Sounds.resolve("doorOpen", { "DoorOpen" }, { "dooropen", "door_open" }, { "car", "vehicle", "garage" })
    local f = Echoes.Acoustics.factor(found.sq, player, { maxDist = 20 })
    if f > 0.03 then
        Echoes.Sounds.playAt(found.sq:getX() + 0.5, found.sq:getY() + 0.5, found.sq:getZ(), names, 0.35 * f, 0.08)
    end
    return found.sq
end

-- light_flicker ----------------------------------------------------------------------------------
local FLICKER_STEPS = { 0, 110, 90, 240, 100, 380, 120 } -- ms between toggles

local function findLamp(player, near)
    local pnum = player:getPlayerNum()
    return eachNearbySquare(player, 80, function(sq)
        if not farEnough(player, sq, 5) or sq:isCouldSee(pnum) then return nil end
        local objs = sq:getObjects()
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            if instanceof(o, "IsoLightSwitch") and o:isActivated() and o:canSwitchLight() then
                return { sq = sq, sw = o }
            end
        end
    end, near)
end

local function runFlicker(player, near)
    local lamp = findLamp(player, near)
    if not lamp then return nil end
    local sw = lamp.sw
    local state = true
    local t = 0
    for _, gap in ipairs(FLICKER_STEPS) do
        t = t + gap
        Echoes.Timer.after(t, function()
            state = not state
            sw:setActivated(state)
        end)
    end
    -- After the last toggle (state is now false): usually come back on, sometimes stay dark.
    local staysOff = ZombRandFloat(0, 1) < 0.35
    Echoes.Timer.after(t + 450, function() sw:setActivated(not staysOff) end)
    return lamp.sq
end

-- Kinds consumed by the Director. `run(player)` returns the source square on success, nil otherwise.
Phenomena.kinds = {
    { id = "door_ajar", weight = 0.6, ambiguous = true, theme = "door", usesPlace = true, run = runDoorAjar },
    { id = "light_flicker", weight = 0.5, ambiguous = true, theme = "light", usesPlace = true, run = runFlicker },
}

function Phenomena.available()
    if isClient() then return {} end -- multiplayer client: world changes must be server-authoritative
    return Phenomena.kinds
end
