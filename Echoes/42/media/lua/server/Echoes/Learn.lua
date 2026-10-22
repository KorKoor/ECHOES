-- ECHOES learn (server / single player): the horde learns how THIS player behaves and uses it to cut them off.
--   What it observes (only while zombies are actually hunting the player, sampled twice a second):
--     * the direction they flee in (8 compass bins) and which direction tends to follow which (a Markov table),
--     * how fast they flee, and
--     * whether, once chased, they tend to run indoors.
--   What it predicts: from where a zombie last SAW the player (never their live position) it projects forward along the
--     learned habit: Learn.predict(player, fromX, fromY, ageMs) -> x, y, confidence, bin.
--   How it stays fair and honest: every prediction it acts on is scored later against where the player really was (a hit is
--     within 7 tiles); confidence = experience x measured accuracy x how strong the habit is, so a player who changes their
--     habits sees it fall; counts decay slowly so old habits fade. Everything is in the player's own ModData (it is
--     remembered between sessions) and F7 prints it.
-- UNTESTED in game: whether the habits it finds are stable enough to be useful, and the accuracy it reaches.

require "Echoes/Core"
require "Echoes/ZombieUtil"

local Log, Config = Echoes.Log, Echoes.Config
local ZU = Echoes.ZombieUtil

local Learn = {}
Echoes.Learn = Learn

local SAMPLE_MS = 500
local BINS = 8
local rt = {} -- runtime (not saved): last position, last bin, chase bookkeeping, pending expectations

local function binAngle(b) return (b - 1) * math.pi / 4 end
local function angleBin(a)
    local b = math.floor((a % (2 * math.pi)) / (math.pi / 4) + 0.5) % BINS
    return b + 1
end

local function model(p)
    local d = Echoes.playerData(p)
    if not d.learn then
        local trans = {}
        for i = 1, BINS do trans[i] = {}; for j = 1, BINS do trans[i][j] = 0 end end
        local flight = {}
        for i = 1, BINS do flight[i] = 0 end
        d.learn = { n = 0, trans = trans, flight = flight, hid = 0, total = 0, speed = 4.0, acc = 0.5, preds = 0, hits = 0 }
    end
    return d.learn
end

local function state(p)
    local k = ZU.playerKey(p)
    rt[k] = rt[k] or { expect = {}, chased = false, chasedAt = 0, calmAt = 0 }
    return rt[k]
end

local function argmax(t)
    local best, bv, sum = nil, 0, 0
    for i = 1, BINS do
        sum = sum + t[i]
        if t[i] > bv then best, bv = i, t[i] end
    end
    return best, bv, sum
end

-- Observing -----------------------------------------------------------------------------------------------------
function Learn.sample(p, hunters, now)
    if not Config.isEnabled("Learn") then return end
    local s = state(p)
    if s.t and now - s.t < SAMPLE_MS then return end
    local m = model(p)
    local x, y = p:getX(), p:getY()
    local sq = p:getCurrentSquare()
    local indoors = sq ~= nil and sq:getRoom() ~= nil

    -- Score expectations that have come due.
    for i = #s.expect, 1, -1 do
        local e = s.expect[i]
        if now >= e.at then
            local hit = ((x - e.x) ^ 2 + (y - e.y) ^ 2) <= 49
            m.preds = m.preds + 1
            if hit then m.hits = m.hits + 1 end
            m.acc = m.acc * 0.9 + 0.1 * (hit and 1 or 0)
            table.remove(s.expect, i)
        end
    end

    if s.t and s.x then
        local dt = (now - s.t) / 1000
        local dx, dy = x - s.x, y - s.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if hunters > 0 and dist > 0.5 then
            local bin = angleBin(math.atan2(dy, dx))
            m.flight[bin] = m.flight[bin] + 1
            if s.bin then m.trans[s.bin][bin] = m.trans[s.bin][bin] + 1 end
            s.bin = bin
            m.speed = m.speed * 0.95 + 0.05 * (dist / dt)
            m.n = m.n + 1
            if m.n % 200 == 0 then -- old habits fade
                for i = 1, BINS do
                    m.flight[i] = m.flight[i] * 0.98
                    for j = 1, BINS do m.trans[i][j] = m.trans[i][j] * 0.98 end
                end
            end
        end
    end

    -- Chase bookkeeping: did they run indoors this time?
    if hunters > 0 then
        if not s.chased then s.chased, s.chasedAt, s.startedOutdoors, s.wentIndoors = true, now, not indoors, false end
        if indoors and s.startedOutdoors then s.wentIndoors = true end
        s.calmAt = now
    elseif s.chased and now - s.calmAt > 8000 then
        if now - s.chasedAt > 5000 then
            m.total = m.total + 1
            if s.wentIndoors then m.hid = m.hid + 1 end
        end
        s.chased, s.bin = false, nil
    end
    s.t, s.x, s.y = now, x, y
end

-- Predicting ---------------------------------------------------------------------------------------------------
function Learn.hideProb(p)
    local m = model(p)
    if m.total < 3 then return 0 end
    return m.hid / m.total
end

-- Where the player probably is `ageMs` after being at (fromX, fromY); nil if there is not enough experience.
function Learn.predict(p, fromX, fromY, ageMs)
    if not Config.isEnabled("Learn") then return nil end
    local m, s = model(p), state(p)
    if m.n < 20 then return nil end
    local bin, bv, sum
    if s.bin then bin, bv, sum = argmax(m.trans[s.bin]) end
    if not bin or sum < 5 then bin, bv, sum = argmax(m.flight) end
    if not bin or sum < 5 then return nil end
    local strength = bv / sum -- 1/8 = no habit, 1 = always the same way
    local conf = Echoes.clamp(m.n / 80, 0, 1) * (0.3 + 0.7 * m.acc) * Echoes.clamp((strength - 0.125) / 0.5, 0, 1)
    local d = m.speed * math.min(ageMs or 0, 15000) / 1000
    return fromX + math.cos(binAngle(bin)) * d, fromY + math.sin(binAngle(bin)) * d, conf, bin
end

-- Registers a prediction the horde acted on, to be scored when its time comes.
function Learn.expect(p, x, y, atMs)
    local s = state(p)
    if #s.expect < 8 then s.expect[#s.expect + 1] = { x = x, y = y, at = atMs } end
end

function Learn.summary(p)
    local m = model(p)
    local bin, bv, sum = argmax(m.flight)
    local habit = bin and sum > 0 and string.format("flees toward bin %d (%.0f%% of %d samples)", bin, 100 * bv / sum, m.n) or "no flight habit yet"
    return string.format("learn: %s | indoors %.0f%% of %d chases | speed %.1f t/s | predictions %d hits %d accuracy %.2f",
        habit, 100 * Learn.hideProb(p), m.total, m.speed, m.preds, m.hits, m.acc)
end

Events.OnGameStart.Add(function() rt = {} end)