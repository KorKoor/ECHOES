-- ECHOES radio signals (server / single player): a distant survivor transmits on a hidden frequency.
-- The player has to find it by sweeping the dial of a powered radio. The story advances slowly across the game:
-- eight short messages, then silence. Messages are garbled more when the weather is bad. Everything goes through
-- the game's own radio system (ZomboidRadio.SendTransmission); nothing is spawned, no map markers are added.
-- UNTESTED: SendTransmission semantics (source range, `codes`, signal strength scale) are unverified.

require "Echoes/Core"
require "Echoes/ZombieUtil"

local Log, Config = Echoes.Log, Echoes.Config

local RadioSignals = {}
Echoes.RadioSignals = RadioSignals

local STORY_LINES = 8
local REPEATS = 3                 -- the same message is sent this many game minutes in a row
local SOURCE_MIN, SOURCE_MAX = 40, 90

local function state()
    return ModData.getOrCreate("EchoesRadio")
end

local function players()
    return Echoes.ZombieUtil.players()
end

local function frequency(st)
    if not st.freq then
        local ok, f = pcall(function() return getZomboidRadio():getRandomFrequency() end)
        st.freq = (ok and type(f) == "number") and f or (91000 + ZombRand(8000))
        Log.info("survivor radio frequency chosen: " .. tostring(st.freq))
    end
    return st.freq
end

-- 0..1: how badly the signal is degraded right now (storms, rain, night static).
local function interference()
    local c = getClimateManager()
    local rain, wind, fog = 0, 0, 0
    pcall(function() rain = c:getRainIntensity(); wind = c:getWindIntensity(); fog = c:getFogIntensity() end)
    return Echoes.clamp(0.5 * rain + 0.2 * wind + 0.1 * fog, 0, 1)
end

-- The survivors stay put during one broadcast: all repeats of a message come from the same place.
local function send(st, text)
    local radio = getZomboidRadio()
    local sx, sy = st.sx, st.sy
    local noise = interference()
    if noise > 0.05 then
        local ok, scrambled = pcall(function() return radio:scrambleString(text, math.floor(10 + 60 * noise), true, nil) end)
        if ok and type(scrambled) == "string" then text = scrambled end
    end
    local strength = math.floor(80 - 40 * noise)
    -- (sourceX, sourceY, channel, msg, guid, codes, r, g, b, signalStrength, isTV)
    radio:SendTransmission(sx, sy, frequency(st), text, "echoes-survivor", "", 0.85, 0.85, 0.55, strength, false)
    return true
end

-- One message is sent per game minute while a broadcast is pending (REPEATS minutes in a row).
local function minuteTick()
    if isClient() or not Config.isEnabled("Radio") then return end
    local st = state()
    if not st.pending or st.pending <= 0 or not st.current then return end
    local text = getText("IGUI_Echoes_Radio_" .. tostring(st.current))
    if Echoes.safe("RadioSignals.send", send, st, text) then
        st.fails = 0
        st.pending = st.pending - 1
        if st.pending == 0 then Log.debug("survivor transmission finished (message " .. st.current .. ")") end
    else
        st.fails = (st.fails or 0) + 1
        if st.fails >= 3 then -- the radio API does not behave as assumed: do not lose this message, try again later
            Log.warn("survivor transmission failed 3 times; message " .. st.current .. " will be retried")
            st.line = st.current
            st.pending = 0
            st.fails = 0
        end
    end
end

local function hourly()
    if isClient() or not Config.isEnabled("Radio") then return end
    local st = state()
    st.line = st.line or 1                                        -- next message to broadcast
    if st.pending and st.pending > 0 then return end
    if st.line > STORY_LINES then return end                     -- the story is over: silence
    local ps = players()
    if #ps == 0 then return end
    local night = getClimateManager():getNightStrength() > 0.5
    local chance = 0.04 * Config.get("Frequency") * (night and 1.8 or 1.0)
    if ZombRandFloat(0, 1) > chance then return end
    local p = ps[1 + ZombRand(#ps)]
    local ang = ZombRand(360) * math.pi / 180
    local dist = SOURCE_MIN + ZombRand(SOURCE_MAX - SOURCE_MIN + 1)
    st.sx = math.floor(p:getX() + math.cos(ang) * dist)
    st.sy = math.floor(p:getY() + math.sin(ang) * dist)
    st.current = st.line
    st.line = st.line + 1
    st.pending = REPEATS
    Log.info("survivor transmission begins: message " .. st.current .. " on " .. tostring(frequency(st)))
end

Events.EveryHours.Add(function() Echoes.safe("RadioSignals.hourly", hourly) end)
Events.EveryOneMinute.Add(function() Echoes.safe("RadioSignals.minute", minuteTick) end)
