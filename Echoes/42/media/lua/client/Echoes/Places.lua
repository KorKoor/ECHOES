-- ECHOES places (client): remembered "charged" places, so phenomena can be tied to where things happened.
-- A place is marked when the player goes through a panic spike. Marks fade over days and stay in player ModData.
-- UNTESTED.

require "Echoes/Core"

local Places = {}
Echoes.Places = Places

local MAX_PLACES = 12
local MAX_PICK_DIST = 30 -- tiles: only places the player could perceive are chosen
local LIFETIME_HOURS = 24 * 10

local function store(player)
    return Echoes.playerData(player).places
end

local THEMES = { "steps", "door", "knock", "voice", "light" }
local MAX_STAGE = 4

function Places.escalate(place)
    if place.stage < MAX_STAGE then
        place.stage = place.stage + 1
    else -- the haunting has run its course: it settles and slowly fades
        place.stage = 2
        place.w = place.w * 0.5
    end
    place.t = getGameTime():getWorldAgeHours()
end

function Places.mark(player, weight)
    local list = store(player)
    local now = getGameTime():getWorldAgeHours()
    local x, y, z = math.floor(player:getX()), math.floor(player:getY()), player:getZ()
    for _, p in ipairs(list) do -- merge with an existing mark within 8 tiles
        if math.abs(p.x - x) < 8 and math.abs(p.y - y) < 8 and p.z == z then
            p.w = math.min(3, p.w + (weight or 1)); p.t = now
            return p
        end
    end
    list[#list + 1] = { x = x, y = y, z = z, w = weight or 1, t = now, stage = 0,
        theme = THEMES[1 + ZombRand(#THEMES)] }
    if #list > MAX_PLACES then table.remove(list, 1) end
    return list[#list]
end

-- A loaded square at a remembered place, preferring heavier and fresher marks; nil if none usable.
function Places.pick(player, minAgeHours)
    local list = store(player)
    local now = getGameTime():getWorldAgeHours()
    local total, usable = 0, {}
    for i = #list, 1, -1 do
        local p = list[i]
        local age = now - p.t
        if age > LIFETIME_HOURS then
            table.remove(list, i)
        elseif age >= (minAgeHours or 0) then
            local sq = getCell():getGridSquare(p.x, p.y, p.z)
            if sq then
                -- nearer places are far more likely: you cannot hear what happens 80 tiles away
                local dx, dy = p.x - player:getX(), p.y - player:getY()
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist <= MAX_PICK_DIST then -- beyond this nothing could be seen or heard
                    local w = p.w * (1.0 - age / LIFETIME_HOURS) / (1.0 + dist / 20)
                    usable[#usable + 1] = { sq = sq, w = w, place = p }
                    total = total + w
                end
            end
        end
    end
    if total <= 0 then return nil end
    local r = ZombRandFloat(0, total)
    for _, u in ipairs(usable) do
        r = r - u.w
        if r <= 0 then return u.sq, u.place end
    end
    return usable[#usable].sq, usable[#usable].place
end
