-- ECHOES dizziness (client): vertigo after exhaustion, blood loss, deep cold or no sleep.
-- Mechanism: the game's own "tripping" screen rotation (Stats.setTripping / setTrippingRotAngle, present in the
-- 42.20 Javadoc), driven by a slow sine. The unit of the angle is NOT verified (radians assumed), and what else the
-- game does while "tripping" is unknown, so this is OFF by default (Sandbox: Dizziness).
-- Test: press F8 with Debug on for a 6 s demo; see docs/03-test-plan.md. If the screen does not rotate (e.g. under
-- Viewpoint's own camera) there is nothing to see and nothing is broken. UNTESTED.

local Log, Config = Echoes.Log, Echoes.Config

local Dizzy = {}
Echoes.Dizzy = Dizzy

Dizzy.level = 0.0       -- 0..1, readable by other modules (overlay)
local active = false
local demoUntil = 0

local function cause(player)
    local d = 0
    local endurance = Echoes.statNorm(player, "ENDURANCE")
    if endurance and endurance < 0.2 then
        local recovery = Echoes.Body and Echoes.Body.state.recovery or 0
        d = math.max(d, Echoes.clamp((0.2 - endurance) / 0.2, 0, 1) * (1 - 0.7 * recovery))
    end
    local ok, core = pcall(function() return player:getBodyDamage():getThermoregulator():getCoreCelcius() end)
    if ok and type(core) == "number" and core < 35.5 then d = math.max(d, Echoes.clamp((35.5 - core) / 2.5, 0, 1)) end
    local okh, hp = pcall(function() return player:getBodyDamage():getOverallBodyHealth() end)
    local okb, bleeding = pcall(function() return player:getBodyDamage():getNumPartsBleeding() end)
    if okh and okb and type(hp) == "number" and bleeding > 0 and hp < 50 then
        d = math.max(d, 0.8 * Echoes.clamp((50 - hp) / 50, 0, 1))
    end
    local fatigue = Echoes.statNorm(player, "FATIGUE")
    if fatigue and fatigue > 0.9 then d = math.max(d, math.min(0.5, (fatigue - 0.9) * 5)) end
    return d
end

local function onTick()
    local player = getPlayer()
    if not player then return end
    local t = getTimestampMs() / 1000
    local scale = Config.get("DizzinessScale")
    local amp = (0.02 + 0.07 * Dizzy.level) * scale
    if demoUntil > getTimestampMs() then amp = 0.15 end
    local angle = amp * math.sin(t * 2 * math.pi * 0.30) + 0.4 * amp * math.sin(t * 2 * math.pi * 0.17)
    local stats = player:getStats()
    stats:setTripping(true)
    stats:setTrippingRotAngle(angle)
end

local function stop()
    if not active then return end
    active = false
    Events.OnTick.Remove(onTick)
    local player = getPlayer()
    if player then
        local stats = player:getStats()
        pcall(function() stats:setTrippingRotAngle(0); stats:setTripping(false) end)
    end
    Log.debug("dizziness ends")
end

local function update(player)
    local target = cause(player)
    Dizzy.level = Dizzy.level + (target - Dizzy.level) * 0.4
    local demo = demoUntil > getTimestampMs()
    local wanted = demo or (Config.isEnabled("Dizziness") and Dizzy.level > 0.08)
    if demo then Dizzy.level = math.max(Dizzy.level, 1.0) end
    if wanted and not active then
        active = true
        Events.OnTick.Add(onTick)
        Log.debug(string.format("dizziness starts (level %.2f)", Dizzy.level))
    elseif not wanted then
        stop()
    end
end

Events.EveryOneMinute.Add(function()
    local player = getPlayer()
    if not player or player:isDead() then stop(); return end
    if not Config.isEnabled("Dizziness") and demoUntil < getTimestampMs() then
        Dizzy.level = 0; stop(); return
    end
    Echoes.safe("Dizzy.update", update, player)
end)

-- Debug demo, independent of the sandbox switch: F8 = 6 seconds of strong rotation.
Events.OnKeyPressed.Add(function(key)
    if key == Keyboard.KEY_F8 and Config.get("Debug") then
        demoUntil = getTimestampMs() + 6000
        local player = getPlayer()
        if player then Echoes.safe("Dizzy.demo", update, player) end
        Log.info("dizziness demo for 6 s (watch for screen rotation)")
        Echoes.Timer.after(6500, function()
            local p = getPlayer()
            if p then Echoes.safe("Dizzy.demoEnd", update, p) end
        end)
    end
end)
