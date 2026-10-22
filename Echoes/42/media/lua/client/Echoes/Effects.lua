-- ECHOES effects switch (client, single player): F6 turns every screen effect (colour drain, dizziness, vignette) on or
-- off for this character, whatever the world's saved sandbox values say. Default ON in single player, because the
-- sandbox options of a world made before these effects existed stay at their old "off" and would hide them.
-- In multiplayer nothing is overridden: the server's sandbox decides.

require "Echoes/Core"

local Log = Echoes.Log

local Effects = {}
Echoes.Effects = Effects

local KEYS = { "VisualEnabled", "DizzinessEnabled", "DazeEnabled", "PhysicalEnabled", "FeelEnabled", "ArmedZombiesEnabled", "TacticsEnabled", "BrainEnabled", "LearnEnabled" }

local function set(on)
    for _, k in ipairs(KEYS) do Echoes.Config.override[k] = on end
    if on and Echoes.Visual then Echoes.Visual.ensure() end
end

local function currentChoice(player)
    local d = Echoes.playerData(player)
    if d.effects == nil then return true end
    return d.effects
end

-- Before the first game starts (so Visual creates its overlay) and again once the player exists.
if not isClient() then set(true) end

Events.OnGameStart.Add(function()
    if isClient() then return end
    local player = getPlayer()
    set(player and currentChoice(player) or true)
end)

Events.OnKeyPressed.Add(function(key)
    if key ~= Keyboard.KEY_F6 or isClient() then return end
    local player = getPlayer()
    if not player then return end
    local d = Echoes.playerData(player)
    d.effects = not currentChoice(player)
    set(d.effects)
    Echoes.count("effects." .. (d.effects and "on" or "off"))
    Log.info("screen effects " .. (d.effects and "ON" or "OFF") .. " (F6)")
    if player.Say then pcall(function() player:Say(d.effects and "Efectos: ON" or "Efectos: OFF") end) end
end)