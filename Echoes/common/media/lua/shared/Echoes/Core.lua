-- ECHOES core (shared): namespace, logging, configuration.
-- UNTESTED prototype: APIs marked [V] in docs/02-design.md still need in-game verification.

Echoes = Echoes or {}
Echoes.VERSION = "0.0.1"

-- Logging ---------------------------------------------------------------------------------
Echoes.Log = {}

local function isDebug()
    return SandboxVars and SandboxVars.Echoes and SandboxVars.Echoes.Debug == true
end

function Echoes.Log.error(msg) print("[Echoes][ERROR] " .. tostring(msg)) end
function Echoes.Log.warn(msg)  print("[Echoes][WARN] " .. tostring(msg)) end
function Echoes.Log.info(msg)  print("[Echoes] " .. tostring(msg)) end
function Echoes.Log.debug(msg)
    if isDebug() then print("[Echoes][DEBUG] " .. tostring(msg)) end
end

-- Configuration -----------------------------------------------------------------------------
Echoes.Config = {}

local defaults = {
    Enabled = true,
    SoundEnabled = true,
    Frequency = 1.0,
    Debug = false,
}

function Echoes.Config.get(key)
    local v = SandboxVars and SandboxVars.Echoes and SandboxVars.Echoes[key]
    if v == nil then return defaults[key] end
    return v
end

-- A module runs only if the global switch and its own switch are on.
function Echoes.Config.isEnabled(module)
    if not Echoes.Config.get("Enabled") then return false end
    if module and Echoes.Config.get(module .. "Enabled") == false then return false end
    return true
end

-- Safe call helper: a failing phenomenon must never break the game loop.
function Echoes.safe(label, fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        Echoes.Log.error(label .. ": " .. tostring(res))
        return nil
    end
    return res
end
