-- ECHOES acoustics (client): rough sound-propagation model between a source square and the player.
-- It does not change what the engine plays; it only decides the volume we ask the emitter for.
-- UNTESTED. Relies on IsoGridSquare.isBlockedTo / isOutside (present in the 42.20 Javadoc), unverified from Lua.

local Acoustics = {}
Echoes.Acoustics = Acoustics

local WALL_LOSS = 0.20      -- loss per blocking edge crossed (wall, closed door, window)
local LEVEL_LOSS = 0.30     -- loss per floor of height difference
local EXTERIOR_LOSS = 0.15  -- sound crossing the building envelope
local MAX_STEPS = 40

-- Squares along a straight line (Bresenham), endpoints included.
local function line(x0, y0, x1, y1)
    local pts = {}
    local dx, dy = math.abs(x1 - x0), math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx - dy
    local x, y = x0, y0
    for _ = 1, MAX_STEPS do
        pts[#pts + 1] = { x, y }
        if x == x1 and y == y1 then break end
        local e2 = 2 * err
        if e2 > -dy then err = err - dy; x = x + sx end
        if e2 < dx then err = err + dx; y = y + sy end
    end
    return pts
end

-- Number of blocking edges between two squares on the same level (nil if unknown).
function Acoustics.barriers(fromSq, toSq)
    local cell = getCell()
    local z = toSq:getZ()
    local pts = line(fromSq:getX(), fromSq:getY(), toSq:getX(), toSq:getY())
    local count = 0
    local prev = cell:getGridSquare(pts[1][1], pts[1][2], z)
    for i = 2, #pts do
        local cur = cell:getGridSquare(pts[i][1], pts[i][2], z)
        if prev and cur then
            if prev:isBlockedTo(cur) then count = count + 1 end
        elseif cur == nil and prev ~= nil then
            count = count + 0.5 -- unloaded/empty square: assume partial obstruction
        end
        prev = cur
    end
    return count
end

-- Returns a volume factor 0..1 for a sound at srcSq heard by `player`.
-- opts.maxDist: distance at which the sound fades to silence (default 22).
function Acoustics.factor(srcSq, player, opts)
    opts = opts or {}
    local plSq = player:getCurrentSquare()
    if not plSq or not srcSq then return 1.0 end

    local dx, dy = srcSq:getX() - plSq:getX(), srcSq:getY() - plSq:getY()
    local dist = math.sqrt(dx * dx + dy * dy)
    local maxDist = opts.maxDist or 22
    if dist >= maxDist then return 0.0 end
    local f = 1.0 - (dist / maxDist)
    f = f * f -- gentler near, steeper far

    -- With the Java engine, use the exact model zombies use (walls, doors, floors, envelope): the player and the
    -- zombies then agree about what is muffled. Without it, fall back to the Lua estimate.
    local engineFactor = Echoes.Engine and Echoes.Engine.occlusion(srcSq, plSq)
    if engineFactor then
        f = f * engineFactor
    else
        local ok, barriers = pcall(Acoustics.barriers, srcSq, plSq)
        if ok and barriers then f = f * math.max(0, 1.0 - WALL_LOSS * barriers) end

        local dz = math.abs(srcSq:getZ() - plSq:getZ())
        f = f * math.max(0, 1.0 - LEVEL_LOSS * dz)

        if srcSq:isOutside() ~= plSq:isOutside() then f = f * (1.0 - EXTERIOR_LOSS) end
    end

    -- Rain and wind mask quiet sounds; panic or breathlessness dulls the listener a little.
    if Echoes.Weather then f = f * Echoes.Weather.hearingMultiplier(plSq) end
    if Echoes.Body and Echoes.Config.isEnabled("Body") then f = f * Echoes.Body.state.hearing end
    if Echoes.VehicleSense then f = f * Echoes.VehicleSense.cabinFactor(player) end

    return math.max(0.0, math.min(1.0, f))
end
