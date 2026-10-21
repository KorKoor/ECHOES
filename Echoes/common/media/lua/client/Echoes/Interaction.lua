-- ECHOES interaction (client): "Listen at the door".
-- Right-click a closed door: walk up, spend a few seconds with an ear to it. Afterwards you hear faint cues from
-- the REAL zombies close behind it (position and number are true, volume is muffled by the door and walls).
-- The wait is the cost: you stand still at the door and make a little noise.
-- Peeking around corners / through windows is NOT implemented: no verified lean/camera API (see docs).
-- Uses vanilla Lua UI classes (ISBaseTimedAction, ISTimedActionQueue, luautils); all guarded. UNTESTED.

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
    local myRoom = player:getCurrentSquare() and player:getCurrentSquare():getRoom()
    local names = Echoes.Sounds.resolve("zombieCue", {}, { "shuffle", "drag", "scrape" }, { "attack", "bite", "hit" })
    local heard, delay = 0, 0
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        local dx, dy = z:getX() - sq:getX(), z:getY() - sq:getY()
        if dx * dx + dy * dy <= RANGE * RANGE and math.abs(z:getZ() - sq:getZ()) < 1.0 then
            local zsq = z:getCurrentSquare()
            local sameRoom = zsq and myRoom and zsq:getRoom() == myRoom
            if zsq and not sameRoom then
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
    Log.debug("listen at door: " .. heard .. " cue(s)")
    return heard
end

-- Timed action ------------------------------------------------------------------------------------
local function defineAction()
    if ISListenAtDoor or not ISBaseTimedAction then return end
    ISListenAtDoor = ISBaseTimedAction:derive("ISListenAtDoor")

    function ISListenAtDoor:isValid() return self.door ~= nil and not self.door:IsOpen() end
    function ISListenAtDoor:update() pcall(function() self.character:faceThisObject(self.door) end) end
    function ISListenAtDoor:start() end
    function ISListenAtDoor:stop() ISBaseTimedAction.stop(self) end
    function ISListenAtDoor:perform()
        ISBaseTimedAction.perform(self)
        Echoes.safe("Interaction.listen", Interaction.listen, self.character, self.door)
    end
    function ISListenAtDoor:new(character, door)
        local o = {}
        setmetatable(o, self)
        self.__index = self
        o.character = character
        o.door = door
        o.stopOnWalk = true
        o.stopOnRun = true
        o.maxTime = 180
        return o
    end
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test or not Config.isEnabled("Interaction") then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    for _, obj in ipairs(worldobjects) do
        if instanceof(obj, "IsoDoor") and not obj:IsOpen() then
            defineAction()
            if not ISListenAtDoor then return end
            local label = getText("ContextMenu_Echoes_ListenAtDoor")
            context:addOption(label, worldobjects, function()
                local sq = obj:getSquare()
                if luautils and luautils.walkAdj and sq then
                    if not luautils.walkAdj(player, sq) then return end
                end
                ISTimedActionQueue.add(ISListenAtDoor:new(player, obj))
            end)
            return
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(...) Echoes.safe("Interaction.menu", onFillWorldObjectContextMenu, ...) end)
