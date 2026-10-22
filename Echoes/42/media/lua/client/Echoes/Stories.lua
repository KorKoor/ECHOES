-- ECHOES stories (client, single player / host): small environmental stories assembled from existing objects.
-- Story "locked_in": a door is found locked and, now and then, something knocks from the other side.
-- No quests, no text. The player decides whether to investigate. Instances are remembered in ModData.
-- UNTESTED (IsoDoor.setLocked and sound names unverified).

require "Echoes/Core"

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

-- Called by the Director when conditions are right: locks a nearby, unseen, closed INTERIOR door of a building the
-- player has never been inside (so never their base or a room they have already looted), and records the story.
function Stories.createLockedIn(player)
    local list = store()
    if #list >= MAX_STORIES then return nil end
    local pnum = player:getPlayerNum()
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), player:getZ()
    local mySq = player:getCurrentSquare()
    local myBuilding = mySq and mySq:getBuildingDef()
    local candidates = Echoes.doorSquares(px, py, pz, 14, function(sq, d)
        local dx, dy = sq:getX() - px, sq:getY() - py
        if dx * dx + dy * dy < 49 or sq:isCouldSee(pnum) then return false end
        if d:IsOpen() or d:isLocked() or d:isBarricaded() or not Echoes.isInteriorDoor(d) then return false end
        local bd = sq:getBuildingDef()
        return bd ~= nil and bd ~= myBuilding and not bd:isHasBeenVisited()
    end)
    if #candidates == 0 then return nil end
    local sq = candidates[1 + ZombRand(#candidates)]
    Echoes.doorAt(sq):setLocked(true)
    list[#list + 1] = { kind = "locked_in", x = sq:getX(), y = sq:getY(), z = sq:getZ(), knocks = 0 }
    Log.info("story created: locked_in at " .. sq:getX() .. "," .. sq:getY())
    return sq
end

-- The door of a story, if its square is loaded.
local function storyDoor(s)
    local sq = getCell():getGridSquare(s.x, s.y, s.z)
    if not sq then return nil, false end
    return Echoes.doorAt(sq), true
end

-- Housekeeping runs even when Stories is switched off, so a door this module locked is never left locked forever:
-- stories whose door was unlocked/opened/removed are dropped, and finished or disabled ones are unlocked.
local function update(player, active)
    local list = store()
    local px, py = player:getX(), player:getY()
    for i = #list, 1, -1 do
        local s = list[i]
        local door, loaded = storyDoor(s)
        if loaded then
            if not door or not door:isLocked() or door:IsOpen() then
                table.remove(list, i)
            elseif s.knocks >= 12 or not active then
                pcall(function() door:setLocked(false) end)
                table.remove(list, i)
            end
        end
    end
    if not active then return end
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
    if #store() >= MAX_STORIES then return {} end
    return { Stories.kind }
end

Events.EveryOneMinute.Add(function()
    if isClient() then return end -- world changes (locked doors) belong to the host / server
    local player = getPlayer()
    if not player or player:isDead() then return end
    Echoes.safe("Stories.update", update, player, Config.isEnabled("Stories"))
end)
