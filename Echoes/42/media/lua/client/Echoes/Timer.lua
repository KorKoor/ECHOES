-- ECHOES timer (client): run a function after a delay in real milliseconds.
-- The OnTick handler is registered only while something is pending (no idle per-frame cost).

require "Echoes/Core"

local Timer = {}
Echoes.Timer = Timer

local pending, ticking = {}, false

local function onTick()
    if #pending == 0 then
        Events.OnTick.Remove(onTick)
        ticking = false
        return
    end
    local t = getTimestampMs()
    for i = #pending, 1, -1 do
        local e = pending[i]
        if e and t >= e.at then
            table.remove(pending, i)
            Echoes.safe("Timer", e.fn)
        end
    end
end

function Timer.after(ms, fn)
    pending[#pending + 1] = { at = getTimestampMs() + ms, fn = fn }
    if not ticking then
        ticking = true
        Events.OnTick.Add(onTick)
    end
end

function Timer.clear()
    pending = {}
end

Events.OnGameStart.Add(Timer.clear)
