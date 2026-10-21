-- ECHOES psyche (client): a slow "pressure" value (0..1) built from real, existing signals.
-- It only raises how often ambiguous phenomena occur. It never damages, blinds or hinders the player,
-- and it does not label anyone as violent or "insane". All of it can be switched off in the sandbox.
-- UNTESTED.

local Log, Config = Echoes.Log, Echoes.Config

local Psyche = {}
Echoes.Psyche = Psyche

Psyche.pressure = 0.0

local function data(player)
    local md = player:getModData()
    md.Echoes = md.Echoes or { last = -1000, log = {} }
    md.Echoes.trauma = md.Echoes.trauma or 0
    return md.Echoes
end

function Psyche.trauma(player)
    return data(player).trauma
end

-- Recomputed every ten game minutes.
local function compute(player)
    local fatigue = Echoes.statNorm(player, "FATIGUE") or 0
    local stress = Echoes.statNorm(player, "STRESS") or 0
    local sanity = Echoes.statNorm(player, "SANITY")
    local lowSanity = sanity and (1.0 - sanity) or 0

    -- Isolation ramps over two weeks of survival and is not reset in single player (nobody else around).
    local days = getGameTime():getWorldAgeHours() / 24
    local isolation = Echoes.clamp(days / 14, 0, 1)

    local sq = player:getCurrentSquare()
    local dark = Echoes.clamp(getClimateManager():getNightStrength(), 0, 1) * ((sq and sq:isOutside()) and 1.0 or 0.6)
    local weather = Echoes.Weather.exposure(player)
    local trauma = Config.isEnabled("Trauma") and data(player).trauma or 0

    local p = 0.25 * fatigue + 0.20 * stress + 0.15 * isolation + 0.10 * dark
        + 0.10 * weather + 0.20 * lowSanity + 0.20 * trauma
    Psyche.pressure = Echoes.clamp(p, 0, 1)
    Log.debug(string.format("pressure %.2f (fat %.2f str %.2f iso %.2f dark %.2f wx %.2f san %.2f tr %.2f)",
        Psyche.pressure, fatigue, stress, isolation, dark, weather, lowSanity, trauma))
end

-- Traumatic experiences: a panic spike leaves a mark that fades slowly (about 4 game days).
local function updateTrauma(player)
    if not Config.isEnabled("Trauma") then return end
    local d = data(player)
    local panic = Echoes.statNorm(player, "PANIC") or 0
    if panic > 0.8 then
        d.trauma = math.min(1.0, d.trauma + 0.03)
        if Echoes.Places then Echoes.Places.mark(player, 0.5) end
    end
end

Events.EveryOneMinute.Add(function()
    local player = getPlayer()
    if not player or not Config.isEnabled("Psyche") then return end
    Echoes.safe("Psyche.trauma", updateTrauma, player)
end)

Events.EveryHours.Add(function()
    local player = getPlayer()
    if not player then return end
    local d = data(player)
    d.trauma = math.max(0, d.trauma - 0.01)
end)

Events.EveryTenMinutes.Add(function()
    local player = getPlayer()
    if not player or not Config.isEnabled("Psyche") then Psyche.pressure = 0; return end
    Echoes.safe("Psyche.compute", compute, player)
end)
