-- ECHOES weather (client): derived readings from the game's own climate. No new weather system.
-- UNTESTED. Uses ClimateManager getters present in the 42.20 Javadoc.

require "Echoes/Core"

local Weather = {}
Echoes.Weather = Weather

local function clim() return getClimateManager() end

-- Multiplier (0..1) for how well quiet sounds carry to the listener.
-- Rain and wind mask sound mainly for listeners outdoors; a roof dulls it indoors.
function Weather.hearingMultiplier(listenerSquare)
    local ok, mult = pcall(function()
        local c = clim()
        local rain = c:getRainIntensity()
        local wind = c:getWindIntensity()
        local outdoors = listenerSquare and listenerSquare:isOutside()
        local mask = outdoors and (0.5 * rain + 0.2 * wind) or (0.2 * rain + 0.05 * wind)
        return 1.0 - Echoes.clamp(mask, 0, 0.7)
    end)
    return ok and mult or 1.0
end

-- 0..1 "exposure": cold core temperature, wet clothes and bad weather outdoors.
-- Feeds the psychological pressure model; it never changes vanilla survival mechanics.
function Weather.exposure(player)
    local sq = player:getCurrentSquare()
    local outdoors = sq and sq:isOutside()
    local score = 0
    local ok, core = pcall(function()
        return player:getBodyDamage():getThermoregulator():getCoreCelcius()
    end)
    if ok and type(core) == "number" and core < 36.5 then
        score = score + Echoes.clamp((36.5 - core) / 2.0, 0, 0.6) -- 34.5 C or lower = max
    end
    local wet = Echoes.statNorm(player, "WETNESS")
    if wet then score = score + 0.3 * wet end
    if outdoors then
        local ok2, rain = pcall(function() return clim():getRainIntensity() end)
        if ok2 and type(rain) == "number" then score = score + 0.2 * rain end
    end
    return Echoes.clamp(score, 0, 1)
end
