-- ECHOES debug (client): F7 prints a status report to console.txt (works without the Debug option; the periodic report needs it).
-- Everything in one place so a single log line block shows the state of every module and the cost of each.

require "Echoes/Core"

local Config = Echoes.Config

local function report()
    local log = Echoes.Log.info
    local player = getPlayer()
    log("==== status v" .. Echoes.VERSION .. " ====")
    if not player then log("no player"); return end
    local function f(v) return v and string.format("%.2f", v) or "n/a" end
    log("pressure=" .. f(Echoes.Psyche and Echoes.Psyche.pressure) .. " fear=" .. f(Echoes.Fear and Echoes.Fear.level)
        .. " dizzy=" .. f(Echoes.Dizzy and Echoes.Dizzy.level)
        .. " trauma=" .. f(Echoes.Psyche and Echoes.Psyche.trauma(player)))
    if Echoes.Body then
        local b = Echoes.Body.state
        log("body: winded=" .. tostring(b.winded) .. " cold=" .. tostring(b.cold) .. " tremor=" .. f(b.tremor)
            .. " hearing=" .. f(b.hearing) .. " recovery=" .. f(b.recovery))
    end
    local md = player:getModData().Echoes
    if md then
        log("phenomena logged: " .. #md.log .. ", places: " .. (md.places and #md.places or 0))
        for _, p in ipairs(md.places or {}) do
            log(string.format("  place %d,%d theme=%s stage=%d weight=%.1f", p.x, p.y, tostring(p.theme), p.stage or 0, p.w))
        end
    end
    log(Echoes.Mind and Echoes.Mind.summary(player) or "mind: absent")
    local function v(k) local n = Echoes.statNorm(player, k); return n and string.format("%.2f", n) or "n/a" end
    log("vanilla emotions: stress=" .. v("STRESS") .. " panic=" .. v("PANIC") .. " anger=" .. v("ANGER")
        .. " unhappiness=" .. v("UNHAPPINESS") .. " boredom=" .. v("BOREDOM") .. " pain=" .. v("PAIN") .. " sanity=" .. v("SANITY"))
    local keys = {}
    for k in pairs(Echoes.Counters) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. Echoes.Counters[k] end
    log("events: " .. (#parts > 0 and table.concat(parts, " ") or "none yet"))
    log("engine: " .. tostring(Echoes.Engine and Echoes.Engine.available() and Echoes.Engine.stats() or "absent"))
    log("---- cost per module (millisecond resolution) ----")
    for _, line in ipairs(Echoes.Perf.report()) do log(line) end
    log("==== end status ====")
end

Echoes.report = report

Events.OnKeyPressed.Add(function(key)
    if key == Keyboard.KEY_F7 then Echoes.safe("report", report) end
end)

-- Every in-game 6 hours, with Debug on, drop the cost table in the log so long sessions leave evidence.
Events.EveryHours.Add(function()
    if Config.get("Debug") and getGameTime():getHour() % 6 == 0 then Echoes.safe("report", report) end
end)
