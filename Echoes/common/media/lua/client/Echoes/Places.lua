-- ECHOES places (client): remembered "charged" places, so phenomena can be tied to where things happened.
-- A place is marked when the player goes through a panic spike. Marks fade over days and stay in player ModData.
-- UNTESTED.

local Places = {}
Echoes.Places = Places

local MAX_PLACES = 12
local LIFETIME_HOURS = 24 * 10

local function store(player)
    local md = player:getModData()
    md.Echoes = md.Echoes or { last = -1000, log = {} }
    md.Echoes.places = md.Echoes.places or {}
    return md.Echoes.places
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
    list[#list + 1] = { x = x, y = y, z = z, w = weight or 1, t = now }
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
                local w = p.w * (1.0 - age / LIFETIME_HOURS)
                usable[#usable + 1] = { sq = sq, w = w }
                total = total + w
            end
        end
    end
    if total <= 0 then return nil end
    local r = ZombRandFloat(0, total)
    for _, u in ipairs(usable) do
        r = r - u.w
        if r <= 0 then return u.sq end
    end
    return usable[#usable].sq
end
