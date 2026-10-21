-- ECHOES engine bridge (shared: client, single player and dedicated server): talks to the optional Java layer (EchoesEngine, needs ZombieBuddy).
-- When the Java layer is absent every function here is a harmless no-op and the Lua fallbacks are used.
-- UNTESTED: the EchoesEngine_* globals are exposed by the Java mod at load time.

require "Echoes/Core"

local Log, Config = Echoes.Log, Echoes.Config

local Engine = {}
Echoes.Engine = Engine

local present = nil

function Engine.available()
    if present == nil then present = (EchoesEngine_version ~= nil) end
    return present
end

function Engine.version()
    return Engine.available() and EchoesEngine_version() or nil
end

-- Sound transmission factor 0..1 between two squares, from the same model the zombies use. nil if no engine.
function Engine.occlusion(a, b)
    if not Engine.available() then return nil end
    local ok, v = pcall(EchoesEngine_occlusion, a:getX(), a:getY(), a:getZ(), b:getX(), b:getY(), b:getZ())
    if ok and type(v) == "number" then return v end
    return nil
end

function Engine.stats()
    return Engine.available() and EchoesEngine_stats() or nil
end

-- Push the sandbox settings into the Java options.
function Engine.apply()
    if not Engine.available() then return end
    local on = Config.isEnabled("EngineHearing")
    EchoesEngine_set("hearingOcclusion", on and 1 or 0)
    EchoesEngine_set("weatherHearing", on and 1 or 0)
    EchoesEngine_set("strength", Config.get("EngineStrength"))
    EchoesEngine_set("noise", Config.isEnabled("EngineNoise") and 1 or 0)
    EchoesEngine_set("noiseStrength", Config.get("EngineNoiseStrength"))
    EchoesEngine_set("stealth", Config.isEnabled("EngineStealth") and 1 or 0)
    EchoesEngine_set("stealthStrength", Config.get("EngineStealthStrength"))
    -- per-player lighting data exists only where a player is simulated locally, not on a dedicated server
    EchoesEngine_set("stealthLight", isServer() and 0 or 1)
    Log.info("engine v" .. tostring(EchoesEngine_version()) .. " hearing=" .. tostring(on)
        .. " strength=" .. tostring(Config.get("EngineStrength")))
end

Events.OnGameStart.Add(function()
    present = nil
    if Engine.available() then Echoes.safe("Engine.apply", Engine.apply)
    else Log.info("Java engine not present (optional). Lua fallbacks in use.") end
end)

-- A dedicated server has no OnGameStart for the world: the Java patches run THERE (getSoundAttract, spotted), so the
-- settings must be pushed there too.
if Events.OnServerStarted then
    Events.OnServerStarted.Add(function()
        present = nil
        if Engine.available() then Echoes.safe("Engine.apply(server)", Engine.apply) end
    end)
end

Events.EveryHours.Add(function()
    if Engine.available() and Config.get("Debug") then Log.debug("engine stats: " .. tostring(Engine.stats())) end
end)
