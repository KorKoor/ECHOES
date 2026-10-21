-- ECHOES body (client): reads the character's physical state and expresses it through sound.
-- No HUD, no new bars. UNTESTED: stat ranges and sound names are unverified.
-- Limits: Lua cannot shake the camera or hands; those effects need Viewpoint/Java and are not faked here.

require "Echoes/Core"

local Log, Config = Echoes.Log, Echoes.Config

local Body = {}
Echoes.Body = Body

Body.state = { winded = false, tremor = 0, cold = false, hearing = 1.0, baseHearing = 1.0, recovery = 0, deaf = 0 }

local lastRunHours = -1000

local function coldCore(player)
    local ok, core = pcall(function()
        return player:getBodyDamage():getThermoregulator():getCoreCelcius()
    end)
    if ok and type(core) == "number" then return core end
    return nil
end

-- Temporary deafness after a loud noise you made yourself without ear protection (needs the Java engine, which
-- watches WorldSoundManager.addSound). Lasts 30 s, stronger for louder noises, fading linearly.
local DEAF_MS = 30000

function Body.deafness()
    if not EchoesEngine_msSinceLoud then return 0 end
    local ok, ms = pcall(EchoesEngine_msSinceLoud)
    if not ok or type(ms) ~= "number" or ms < 0 or ms > DEAF_MS then return 0 end
    local okr, radius = pcall(EchoesEngine_lastLoudRadius)
    radius = (okr and type(radius) == "number") and radius or 40
    return Echoes.clamp((radius - 30) / 70, 0.3, 1.0) * (1.0 - ms / DEAF_MS)
end

-- Current hearing multiplier 0.1..1 for sounds from the world: panic and breathlessness (sampled each game minute)
-- and deafness after a loud noise (evaluated NOW, because its 30 s window is real time, not game time).
function Body.hearingNow()
    if not Echoes.Config.isEnabled("Body") then return 1.0 end
    local st = Body.state
    return Echoes.clamp(st.baseHearing - 0.6 * Body.deafness(), 0.1, 1.0)
end

local function update(player)
    local st = Body.state
    local now = getGameTime():getWorldAgeHours()
    local running = false
    pcall(function() running = player:isRunning() or player:isSprinting() end)
    if running then lastRunHours = now end

    local endurance = Echoes.statNorm(player, "ENDURANCE") -- assumed 1 = fresh [V]
    local fatigue = Echoes.statNorm(player, "FATIGUE") or 0 -- assumed 1 = exhausted [V]
    local panic = Echoes.statNorm(player, "PANIC") or 0
    local stress = Echoes.statNorm(player, "STRESS") or 0
    local core = coldCore(player)

    st.winded = endurance ~= nil and endurance < 0.4
    st.cold = core ~= nil and core < 36.0
    local shiver = core and Echoes.clamp((36.5 - core) / 2.0, 0, 1) or 0
    st.tremor = Echoes.clamp(0.4 * panic + 0.25 * stress + 0.2 * fatigue + 0.3 * shiver, 0, 1)
    -- Moderately dulled perception of ECHOES sounds when panicking or out of breath.
    st.baseHearing = Echoes.clamp(1.0 - 0.12 * panic - (st.winded and 0.08 or 0), 0.1, 1.0)
    st.deaf = Body.deafness()
    st.hearing = Body.hearingNow()
    -- Gradual recovery: minutes since the last run, capped at 30 game minutes.
    st.recovery = Echoes.clamp((now - lastRunHours) * 60 / 30, 0, 1)

    -- Heavy breathing while winded, loud right after effort, fading as the body recovers.
    if st.winded and ZombRandFloat(0, 1) < 0.7 * (1.0 - 0.6 * st.recovery) then
        local names = Echoes.Sounds.resolve("breath", {}, { "breath" }, { "zombie", "gas", "mask" })
        local vol = Echoes.clamp(0.25 + (0.4 - endurance) * 1.2, 0.2, 0.7)
        local x, y, z = player:getX(), player:getY(), player:getZ()
        local played = Echoes.Sounds.playAt(x, y, z, names, vol, 0.05, false, true)
        if played then Log.debug("breathing: " .. played .. " vol " .. string.format("%.2f", vol)) end
    end
end

-- Ringing in the ears while deaf: checked every 1.5 s of REAL time (not game time) by a self-rescheduling timer.
local watchGen = 0
function Body.startEarWatch()
    watchGen = watchGen + 1
    local gen = watchGen
    local function watch()
        if gen ~= watchGen then return end -- a newer game started its own watcher
        local player = getPlayer()
        if not player or player:isDead() or not Echoes.Config.isEnabled("Body") then return end
        local deaf = Body.deafness()
        if deaf > 0.05 then
            local ring = Echoes.Sounds.resolve("ringing", {}, { "tinnitus", "ringing", "earring" }, { "phone", "door", "bell", "alarm" })
            Echoes.Sounds.playAt(player:getX(), player:getY(), player:getZ(), ring, 0.15 + 0.35 * deaf, 0.01, false, true)
        end
        Echoes.Timer.after(1500, watch)
    end
    Echoes.Timer.after(1500, watch)
end

Events.OnGameStart.Add(function()
    lastRunHours = -1000
    Body.state = { winded = false, tremor = 0, cold = false, hearing = 1.0, baseHearing = 1.0, recovery = 0, deaf = 0 }
    Body.startEarWatch()
end)

Events.EveryOneMinute.Add(function()
    if not Config.isEnabled("Body") then return end
    local player = getPlayer()
    if not player or player:isDead() then return end
    Echoes.safe("Body.update", update, player)
end)
