-- ECHOES stories (client, single player / host): small environmental stories assembled from existing objects.
-- Story "locked_in": a door is found locked and, now and then, something knocks from the other side.
-- No quests, no text. The player decides whether to investigate. Instances are remembered in ModData.
-- UNTESTED (IsoDoor.setLocked and sound names unverified).

local Log, Config = Echoes.Log, Echoes.Config

local Stories = {}
Echoes.Stories = Stories

local KNOCK_RANGE = 7
local MAX_STORIES = 6

local function store()
    local s = ModData.getOrCreate("EchoesStories")
    s.list = s.list or {}
    return s.list
end

-- Called by the Director when conditions are right: locks a nearby, unseen, closed door and records the story.
function Stories.createLockedIn(player)
    local list = store()
    if #list >= MAX_STORIES then return nil end
    local cell, pnum = getCell(), player:getPlayerNum()
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), player:getZ()
    for _ = 1, 80 do
        local sq = cell:getGridSquare(px + ZombRand(-14, 15), py + ZombRand(-14, 15), pz)
        if sq and sq:getRoom() then
            local d = sq:getDoor(true) or sq:getDoor(false)
            local dx, dy = sq:getX() - px, sq:getY() - py
            if d and dx * dx + dy * dy >= 49 and not sq:isCouldSee(pnum)
                and not d:IsOpen() and not d:isLocked() and not d:isBarricaded() then
                d:setLocked(true)
                list[#list + 1] = { kind = "locked_in", x = sq:getX(), y = sq:getY(), z = sq:getZ(), knocks = 0 }
                Log.info("story created: locked_in at " .. sq:getX() .. "," .. sq:getY())
                return sq
            end
        end
    end
    return nil
end

-- Occasional knocking when the player is close to an existing story door.
local function update(player)
    local list = store()
    local px, py = player:getX(), player:getY()
    for _, s in ipairs(list) do
        if s.kind == "locked_in" and s.knocks < 12 and math.abs(s.z - player:getZ()) < 1 then
            local dx, dy = s.x - px, s.y - py
            if dx * dx + dy * dy <= KNOCK_RANGE * KNOCK_RANGE and ZombRandFloat(0, 1) < 0.12 then
                local sq = getCell():getGridSquare(s.x, s.y, s.z)
                if sq then
                    local names = Echoes.Sounds.resolve("knock", {}, { "knock" }, { "zombie" })
                    local f = Echoes.Acoustics.factor(sq, player, { maxDist = 12 })
                    if f > 0.05 and Echoes.Sounds.playAt(s.x + 0.5, s.y + 0.5, s.z, names, 0.7 * f, 0.05) then
                        s.knocks = s.knocks + 1
                    end
                end
                return
            end
        end
    end
end

Stories.kind = { id = "story_locked_in", weight = 0.25, ambiguous = true, run = Stories.createLockedIn }

function Stories.available()
    if isClient() or not Config.isEnabled("Stories") then return {} end
    return { Stories.kind }
end

Events.EveryOneMinute.Add(function()
    if not Config.isEnabled("Stories") then return end
    local player = getPlayer()
    if not player or player:isDead() then return end
    Echoes.safe("Stories.update", update, player)
end)
