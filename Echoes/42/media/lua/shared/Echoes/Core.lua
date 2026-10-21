-- ECHOES core (shared): namespace, logging, configuration.
-- UNTESTED prototype: APIs marked [V] in docs/02-design.md still need in-game verification.

Echoes = Echoes or {}
Echoes.VERSION = "0.6.0"

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
    PhenomenaEnabled = true,
    BodyEnabled = true,
    PsycheEnabled = true,
    TraumaEnabled = true,
    DecayEnabled = true,
    WorldEventsEnabled = true,
    RadioEnabled = true,
    SensesEnabled = true,
    InteractionEnabled = true,
    AIEnabled = true,
    VehicleEnabled = true,
    StoriesEnabled = true,
    ScentEnabled = true,
    ScentStrength = 1.0,
    PackAlertEnabled = true,
    FearEnabled = true,
    DizzinessEnabled = false,
    DizzinessScale = 1.0,
    EngineHearingEnabled = true,
    EngineStrength = 1.0,
    EngineNoiseEnabled = false,
    EngineNoiseStrength = 1.0,
    EngineStealthEnabled = false,
    EngineStealthStrength = 0.6,
    VisualEnabled = false,
    ApparitionsEnabled = false,
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
Echoes.Perf = { stats = {} }

local function nowMs()
    local ok, t = pcall(getTimestampMs)
    return ok and t or 0
end

-- Every call through safe() is counted and timed (millisecond resolution), so slow modules show up in Perf.report().
function Echoes.safe(label, fn, ...)
    local t0 = nowMs()
    local ok, res = pcall(fn, ...)
    local dt = nowMs() - t0
    local st = Echoes.Perf.stats[label]
    if not st then st = { calls = 0, ms = 0, max = 0, errors = 0 }; Echoes.Perf.stats[label] = st end
    st.calls = st.calls + 1
    st.ms = st.ms + dt
    if dt > st.max then st.max = dt end
    if not ok then
        st.errors = st.errors + 1
        Echoes.Log.error(label .. ": " .. tostring(res))
        return nil
    end
    return res
end

-- Lines "label calls=.. avgMs=.. maxMs=.. errors=..", slowest total first.
function Echoes.Perf.report()
    local rows = {}
    for label, st in pairs(Echoes.Perf.stats) do rows[#rows + 1] = { label = label, st = st } end
    table.sort(rows, function(a, b) return a.st.ms > b.st.ms end)
    local out = {}
    for _, r in ipairs(rows) do
        local st = r.st
        out[#out + 1] = string.format("%-28s calls=%d avgMs=%.2f maxMs=%d errors=%d", r.label, st.calls,
            st.calls > 0 and st.ms / st.calls or 0, st.max, st.errors)
    end
    return out
end

-- Normalised (0..1) value of a CharacterStat for a character, using the stat's own min/max.
-- Returns nil if the stat or the call is unavailable (B42 CharacterStat registry, unverified from Lua).
-- Builds before 42.13 had no CharacterStat; the old getters are tried as a fallback (value / known maximum).
local LEGACY = {
    ENDURANCE = { "getEndurance", 1 }, FATIGUE = { "getFatigue", 1 }, STRESS = { "getStress", 1 },
    PANIC = { "getPanic", 100 }, SANITY = { "getSanity", 1 },
}

function Echoes.statNorm(character, key)
    local ok, v = pcall(function()
        local stat = CharacterStat[key]
        local val = character:getStats():get(stat)
        local mn, mx = stat:getMinimumValue(), stat:getMaximumValue()
        if mx <= mn then return nil end
        return (val - mn) / (mx - mn)
    end)
    if ok and type(v) == "number" then return v end
    local legacy = LEGACY[key]
    if legacy then
        local ok2, v2 = pcall(function() return character:getStats()[legacy[1]](character:getStats()) end)
        if ok2 and type(v2) == "number" then return Echoes.clamp(v2 / legacy[2], 0, 1) end
    end
    return nil
end

function Echoes.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- atan2 that works whether the Lua flavour has math.atan2 (5.1 / Kahlua) or a two-argument math.atan (5.3+).
function Echoes.atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
end
