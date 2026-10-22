-- ECHOES interaction (client): "Listen at the door".
-- Right-click a closed door: walk up, spend a few seconds with an ear to it. Afterwards you hear faint cues from
-- the REAL zombies close behind it (position and number are true, volume is muffled by the door and walls).
-- The wait is the cost: you stand still at the door and make a little noise.
-- Peeking around corners / through windows is NOT implemented: no verified lean/camera API (see docs).
-- Uses vanilla Lua UI classes (ISBaseTimedAction, ISTimedActionQueue, luautils); all guarded. UNTESTED.

require "Echoes/Core"

local Log, Config = Echoes.Log, Echoes.Config

local Interaction = {}
Echoes.Interaction = Interaction

local RANGE = 9

-- Cues for zombies within RANGE tiles that are not in the listener's own room.
function Interaction.listen(player, door)
    local sq = door:getSquare()
    if not sq then return 0 end
    local cell = getCell()
    local list = cell:getZombieList()
    local opposite = door:getOppositeSquare()
    if not opposite then return 0 end
    -- "far" = the door's side that is not the player's side
    local px, py = player:getX(), player:getY()
    local function d2(a) local dx, dy = px - (a:getX() + 0.5), py - (a:getY() + 0.5); return dx * dx + dy * dy end
    local far, near = opposite, sq
    if d2(opposite) < d2(sq) then far, near = sq, opposite end
    local myRoom = player:getCurrentSquare() and player:getCurrentSquare():getRoom()
    local names = Echoes.Sounds.resolve("zombieCue", {}, { "shuffle", "drag", "scrape" }, { "attack", "bite", "hit" })
    local heard, delay = 0, 0
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        local dx, dy = z:getX() - sq:getX(), z:getY() - sq:getY()
        if dx * dx + dy * dy <= RANGE * RANGE and math.abs(z:getZ() - sq:getZ()) < 1.0 then
            local zsq = z:getCurrentSquare()
            local sameRoom = zsq and myRoom and zsq:getRoom() == myRoom
            -- only zombies nearer to the far side of the door than to the player's side count as "behind it"
            local zx0, zy0 = z:getX(), z:getY()
            local dFar = (zx0 - (far:getX() + 0.5)) ^ 2 + (zy0 - (far:getY() + 0.5)) ^ 2
            local dNear = (zx0 - (near:getX() + 0.5)) ^ 2 + (zy0 - (near:getY() + 0.5)) ^ 2
            if zsq and not sameRoom and dFar < dNear then
                local f = Echoes.Acoustics.factor(zsq, player, { maxDist = RANGE + 4 })
                if f > 0.05 and heard < 4 then
                    local zx, zy, zz = z:getX(), z:getY(), z:getZ()
                    Echoes.Timer.after(delay, function()
                        Echoes.Sounds.playAt(zx, zy, zz, names, 0.6 * f, 0.08)
                    end)
                    delay = delay + 700 + ZombRand(600)
                    heard = heard + 1
                end
            end
        end
    end
    -- Standing at a door is not silent: a very small noise.
    pcall(function()
        getWorldSoundManager():addSound(player, player:getX(), player:getY(), player:getZ(), 3, 2)
    end)
    if heard > 0 then -- hearing something real on the other side is unsettling
        if Echoes.Fear then Echoes.Fear.shock(0.05 * heard) end
        if Echoes.Mind then Echoes.Mind.react("door", 0.7) end
    end
    Log.debug("listen at door: " .. heard .. " cue(s)")
    return heard
end

-- Timed action ------------------------------------------------------------------------------------
-- Pattern copied from real Build 42 mods: require the vanilla class, derive, build with ISBaseTimedAction.new(self, actor).
local function defineAction()
    if ISListenAtDoor then return true end
    pcall(require, "TimedActions/ISBaseTimedAction")
    pcall(require, "TimedActions/ISTimedActionQueue")
    if not ISBaseTimedAction then return false end

    ISListenAtDoor = ISBaseTimedAction:derive("ISListenAtDoor")

    function ISListenAtDoor:isValid()
        return self.door ~= nil and not self.door:IsOpen() and self.character ~= nil and not self.character:isDead()
    end
    function ISListenAtDoor:update() pcall(function() self.character:faceThisObject(self.door) end) end
    function ISListenAtDoor:start() end
    function ISListenAtDoor:stop() ISBaseTimedAction.stop(self) end
    function ISListenAtDoor:perform()
        ISBaseTimedAction.perform(self)
        Echoes.safe("Interaction.listen", Interaction.listen, self.character, self.door)
    end
    function ISListenAtDoor:new(character, door)
        local o = ISBaseTimedAction.new(self, character)
        o.character = character
        o.door = door
        o.stopOnWalk = true
        o.stopOnRun = true
        o.maxTime = 180
        return o
    end
    return true
end

-- You must be next to the door: no walking helper is used (its B42 form is unverified).
local function nearDoor(player, door)
    local sq = door:getSquare()
    if not sq or math.floor(player:getZ()) ~= sq:getZ() then return false end
    local dx, dy = player:getX() - (sq:getX() + 0.5), player:getY() - (sq:getY() + 0.5)
    return dx * dx + dy * dy <= 6.25 -- 2.5 tiles
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if not Config.isEnabled("Interaction") then return end
    if not context or type(context.addOption) ~= "function" then return end
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then return end
    for _, obj in ipairs(type(worldObjects) == "table" and worldObjects or {}) do
        if instanceof(obj, "IsoDoor") and not obj:IsOpen() and nearDoor(player, obj) then
            if test then return true end
            if not defineAction() then return end
            context:addOption(getText("ContextMenu_Echoes_ListenAtDoor"), obj, function(door)
                ISTimedActionQueue.add(ISListenAtDoor:new(player, door))
            end)
            return
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(...) return Echoes.safe("Interaction.menu", onFillWorldObjectContextMenu, ...) end)
