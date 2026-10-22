-- ECHOES timer (client): run a function after a delay in real milliseconds.
-- The OnTick handler is registered only while something is pending (no idle per-frame cost).

require "Echoes/Core"

local Timer = {}
Echoes.Timer = Timer

local pending, ticking = {}, false

local nextDue = math.huge -- earliest due time among pending timers: onTick does nothing before it

local function onTick()
    if #pending == 0 then
        Events.OnTick.Remove(onTick)
        ticking = false
        nextDue = math.huge
        return
    end
    local t = getTimestampMs()
    if t < nextDue then return end -- nothing due: no allocation, no scan
    local due, rest = {}, {}
    for _, e in ipairs(pending) do
        if t >= e.at then due[#due + 1] = e else rest[#rest + 1] = e end
    end
    pending = rest
    nextDue = math.huge
    for _, e in ipairs(rest) do if e.at < nextDue then nextDue = e.at end end
    table.sort(due, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
    for _, e in ipairs(due) do Echoes.safe("Timer", e.fn) end -- oldest first, even after a long frame hitch
end

local seq = 0
function Timer.after(ms, fn)
    seq = seq + 1
    local at = getTimestampMs() + ms
    pending[#pending + 1] = { at = at, fn = fn, seq = seq }
    if at < nextDue then nextDue = at end
    if not ticking then
        ticking = true
        Events.OnTick.Add(onTick)
    end
end

function Timer.clear()
    pending = {}
end

-- (No OnGameStart clear: handler order between modules is not guaranteed, and a clear could wipe timers another
-- module started in its own OnGameStart. Modules that run self-rescheduling chains use a generation token instead.)
