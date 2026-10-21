-- ECHOES vehicle senses (client): what you can still perceive from the driver's seat.
--  * Cabin muffling and engine masking lower the volume of ECHOES sounds you hear while driving.
--  * Blind-spot cue: a real zombie close behind/beside the vehicle gives a faint thud/scrape.
-- Not implemented (no verified API): mirrors, rain on glass, dirt on windows. UNTESTED.

require "Echoes/Core"

local Log, Config = Echoes.Log, Echoes.Config

local VehicleSense = {}
Echoes.VehicleSense = VehicleSense

local lastCue = 0

-- 1.0 on foot. In a vehicle: cabin dulls sound, engine noise masks more the faster you go.
function VehicleSense.cabinFactor(player)
    if not Config.isEnabled("Vehicle") then return 1.0 end
    local v = player:getVehicle()
    if not v then return 1.0 end
    local ok, speed = pcall(function() return math.abs(v:getCurrentSpeedKmHour()) end)
    speed = (ok and type(speed) == "number") and speed or 0
    return Echoes.clamp(0.7 - math.min(0.4, speed / 150), 0.25, 1.0)
end

local function update(player)
    local v = player:getVehicle()
    if not v then return end
    local now = getTimestampMs()
    if now - lastCue < 8000 then return end

    local fx, fy = player:getForwardDirectionX(), player:getForwardDirectionY()
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        local dx, dy = z:getX() - px, z:getY() - py
        local d2 = dx * dx + dy * dy
        if d2 <= 20 and math.abs(z:getZ() - pz) < 1.0 and d2 > 0.01 then
            local d = math.sqrt(d2)
            local cos = (dx * fx + dy * fy) / d
            if cos < -0.35 then -- more than ~110 degrees behind the driver's heading
                local names = Echoes.Sounds.resolve("blindSpot", {}, { "thump", "scratch", "bang" }, { "gun", "door" })
                if Echoes.Sounds.playAt(z:getX(), z:getY(), z:getZ(), names, 0.45, 0.06) then
                    lastCue = now
                    Log.debug("blind-spot cue")
                end
                return
            end
        end
    end
end

Events.EveryOneMinute.Add(function()
    if not Config.isEnabled("Vehicle") then return end
    if not Echoes.throttle("VehicleSense", 1500) then return end
    local player = getPlayer()
    if not player or player:isDead() then return end
    Echoes.safe("VehicleSense.update", update, player)
end)
