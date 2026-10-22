-- Smoke test with a mocked Project Zomboid API (NOT a game test). Run through tests/run_mock.py (needs `lupa`).
-- Globals set by the runner: SEED (random seed), BASE (repo root), MODE ("engine" default, or "noengine" to exercise
-- the Lua fallbacks used when the Java layer is absent). Lines containing "[ERROR]" make the run fail, and so do the
-- ASSERT lines at the end: the mock proves the code RUNS and reaches its main paths, never that the game accepts it.
MODE = MODE or "engine"

-- ---------------------------------------------------------------- events
local handlers = {}
local function eventObject(name)
  local ev = {}
  function ev.Add(f) handlers[name] = handlers[name] or {}; table.insert(handlers[name], f) end
  function ev.Remove(f)
    for i, g in ipairs(handlers[name] or {}) do if g == f then table.remove(handlers[name], i); return end end
  end
  return ev
end
Events = setmetatable({}, { __index = function(t, k) local ev = eventObject(k); rawset(t, k, ev); return ev end })
gh = 24 * 30
tms = 0
local function fire(k, ...)
  if k == 'EveryOneMinute' then gh = gh + 1/60; tms = tms + 3000 end
  local copy = {}
  for i, f in ipairs(handlers[k] or {}) do copy[i] = f end
  for _, f in ipairs(copy) do f(...) end
end
local function ticks(n, ms) for _ = 1, n do tms = tms + (ms or 200); fire('OnTick') end end

require = function() return true end
Keyboard = { KEY_F6 = 64, KEY_F9 = 67, KEY_F8 = 66, KEY_F10 = 68, KEY_F7 = 65 }
SandboxVars = { Echoes = { Debug = true, Frequency = 4, DizzinessEnabled = true, VisualEnabled = true,
  ApparitionsEnabled = true, EngineNoiseEnabled = true, EngineStealthEnabled = true } }
math.randomseed(tonumber(SEED) or 1)
function ZombRand(a, b) if b then return math.random(a, b - 1) end return math.random(0, a - 1) end
function ZombRandFloat(a, b) return a + math.random() * (b - a) end
function instanceof(o, c) return o.class == c end

local played = {}
local function list(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end

-- ---------------------------------------------------------------- world
local lampOf = function(sqr)
  return { class = "IsoLightSwitch", on = true,
    isActivated = function(self) return self.on end, canSwitchLight = function() return true end,
    setActivated = function(self, v) self.on = v; played[#played+1] = "lamp=" .. tostring(v) end,
    getSquare = function() return sqr end, getModData = function(self) self.md = self.md or {}; return self.md end }
end

local cache = {}
local cell = {}
local function makeDoor(sqr, ox)
  local d = { class = "IsoDoor", open = false, locked = false }
  function d:IsOpen() return self.open end
  function d:isOpen() return self.open end
  function d:isLocked() return self.locked end
  function d:isBarricaded() return false end
  function d:setLocked(v) self.locked = v; played[#played+1] = "LOCK=" .. tostring(v) end
  function d:ToggleDoorSilent() self.open = not self.open; played[#played+1] = "TOGGLE" end
  function d:getSquare() return sqr end
  function d:getOppositeSquare() return cell:getGridSquare(sqr:getX() + ox, sqr:getY(), sqr:getZ()) end
  return d
end

local function newSquare(x, y, z)
  local s = { x = x, y = y, z = z }
  function s:getX() return x end function s:getY() return y end function s:getZ() return z end
  function s:isOutside() return x < -50 end
  function s:isCouldSee() return false end function s:isFree() return true end
  function s:isBlockedTo() return false end
  function s:getLightLevel() return 0.2 end
  function s:haveBloodFloor() return (x + y) % 5 == 0 end
  function s:getModData() return {} end
  if x % 5 == 0 and y % 3 == 0 then s.doorObj = makeDoor(s, 1) end
  function s:getDoor(north) if north then return self.doorObj end return nil end
  function s:getBuildingDef() return { isHasBeenVisited = function() return x % 2 == 1 end } end
  local lamps = (x % 7 == 0) and { lampOf(s) } or {}
  function s:getObjects() return list(lamps) end
  function s:getRoom()
    if x % 2 ~= 0 then return nil end
    local sqr = self
    return { hasLightSwitches = function() return #lamps > 0 end,
      getRoomDef = function() return { getID = function() return x * 1000 + y end } end,
      getLightSwitches = function() return list(lamps) end,
      getRandomFreeSquare = function() return sqr end }
  end
  return s
end
function cell:getGridSquare(x, y, z)
  local k = x .. "," .. y .. "," .. z
  if not cache[k] then cache[k] = newSquare(x, y, z) end
  return cache[k]
end

-- one zombie that can be made to hear, lose, chase...
zmd = {}; zresp = true; ztarget = nil
local zombie = { getX = function() return 106.5 end, getY = function() return 100.5 end, getZ = function() return 0 end,
  getCurrentSquare = function() return cell:getGridSquare(106, 100, 0) end, getModData = function() return zmd end,
  isRespondingToPlayerSound = function() return zresp end, isMovingToPlayerSound = function() return false end,
  getTarget = function() return ztarget end, isTargetVisible = function() return ztarget ~= nil end,
  pathToLocationF = function(_, x, y) played[#played+1] = "PATH@" .. math.floor(x) .. "," .. math.floor(y) end }
local extra = {}
for i = 1, 6 do
  local zz = { x = 108 + i, y = 104 + i, md = {} }
  extra[i] = { pos = zz, getX = function() return zz.x end, getY = function() return zz.y end, getZ = function() return 0 end,
    getCurrentSquare = function() return cell:getGridSquare(zz.x, zz.y, 0) end, getModData = function() return zz.md end,
    isRespondingToPlayerSound = function() return false end, isMovingToPlayerSound = function() return false end,
    getTarget = function() return nil end, isTargetVisible = function() return false end,
    pathToLocationF = function(_, x, y) played[#played+1] = "PATH@" .. math.floor(x) .. "," .. math.floor(y) end }
end
function cell:getZombieList()
  local all = { zombie }
  for _, z in ipairs(extra) do all[#all+1] = z end
  return list(all)
end

-- ---------------------------------------------------------------- player
local md = {}
local trip = {}
local stats = { get = function(_, s) return s.v end, getNumVisibleZombies = function() return 3 end,
  getNumChasingZombies = function() return 1 end,
  setTripping = function(_, v) trip.on = v end, setTrippingRotAngle = function(_, a) trip.angle = a end }
CharacterStat = {}
for _, n in ipairs({ "ENDURANCE","FATIGUE","STRESS","PANIC","SANITY","WETNESS" }) do
  CharacterStat[n] = { v = 0.3, getMinimumValue = function() return 0 end, getMaximumValue = function() return 1 end } end
local vehicle = { getCurrentSpeedKmHour = function() return 60 end }
local inVehicle = false
local px = 100.5
local player = { getX = function() return px end, getY = function() return 100.5 end, getZ = function() return 0 end,
  getCurrentSquare = function() return cell:getGridSquare(math.floor(px), 100, 0) end, getModData = function() return md end,
  isDead = function() return false end, getVehicle = function() if inVehicle then return vehicle end return nil end,
  isAsleep = function() return false end, getPlayerNum = function() return 0 end,
  getForwardDirectionX = function() return 1 end, getForwardDirectionY = function() return 0 end, getStats = function() return stats end,
  isRunning = function() return true end, isSprinting = function() return false end,
  getBodyDamage = function() return { getNumPartsBleeding = function() return 2 end, getOverallBodyHealth = function() return 40 end,
    getThermoregulator = function() return { getCoreCelcius = function() return 35.5 end } end } end }
function getPlayer() return player end
function getSpecificPlayer(i) if i == 0 then return player end return nil end
function getOnlinePlayers() return list({ player }) end
function getCell() return cell end
function getGameTime() return { getWorldAgeHours = function() return gh end, getHour = function() return 6 end } end
function getClimateManager() return { getNightStrength = function() return 0.9 end, getRainIntensity = function() return 0.5 end,
  getWindIntensity = function() return 0.2 end, getFogIntensity = function() return 0 end,
  getClimateFloat = function() return { setEnableAdmin = function() end, setAdminValue = function() end } end } end
function getWorld() return { getFreeEmitter = function(_, x, y, z) return { playSound = function(_, n) played[#played+1] = n; return 1 end,
  setVolume = function(_, h, v) played[#played+1] = string.format("vol=%.2f", v) end, setPitch = function() end } end,
  isHydroPowerOn = function() return true end } end
function getActivatedMods() return { contains = function() return false end } end
function getTimestampMs() return tms end
function getCore() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
GameSounds = { isKnownSound = function(n) return n ~= "FootstepsIndoor" end,
  getSound = function(n) return { isLooped = function() return n == "LoopedHum" end } end,
  getCategories = function() return list({ "c" }) end,
  getSoundsInCategory = function()
    local function gs(name, looped) return { getName = function() return name end, isLooped = function() return looped end } end
    return list({ gs("Footstep_Wood"), gs("BreathHeavy"), gs("HouseAlarm"), gs("KnockKnock"), gs("Heartbeat1"),
      gs("AlarmLoop", true), gs("WaterDrip"), gs("ZombieShuffle"), gs("Tinnitus") }) end }
local store = {}
ModData = { getOrCreate = function(k) store[k] = store[k] or {}; return store[k] end }
isClient = function() return false end
isServer = function() return false end
function getWorldSoundManager() return { addSound = function(_, _, x, y) played[#played+1] = "LURE@" .. x .. "," .. y end } end
function sendServerCommand() end
function getText(k) return "TEXT:" .. k end
local radioLog = {}
function getZomboidRadio() return { getRandomFrequency = function() return 93200 end,
  scrambleString = function(_, t) return t .. "~" end,
  SendTransmission = function(_, sx, sy, ch, msg) radioLog[#radioLog+1] = ch .. ":" .. msg end } end

-- ---------------------------------------------------------------- UI stubs (ISPanel overlay, timed action, menu)
local panels, drawn = {}, 0
ISPanel = {}
function ISPanel:derive(name) local c = setmetatable({ Type = name }, { __index = self }); c.__index = c; return c end
function ISPanel:new(x, y, w, h)
  local o = setmetatable({ w = w, h = h }, self); self.__index = self; panels[#panels+1] = o; return o end
function ISPanel:initialise() end function ISPanel:instantiate() self.javaObject = { setConsumeMouseEvents = function() end } end
function ISPanel:addToUIManager() end function ISPanel:removeFromUIManager() self.removed = true end
function ISPanel:setVisible() end
function ISPanel:getWidth() return self.w end function ISPanel:getHeight() return self.h end
function ISPanel:setWidth(v) self.w = v end function ISPanel:setHeight(v) self.h = v end
function ISPanel:drawRect() drawn = drawn + 1 end

ISBaseTimedAction = {}
function ISBaseTimedAction:derive(name) local c = setmetatable({ Type = name }, { __index = self }); c.__index = c; return c end
function ISBaseTimedAction.new(self, character) local o = setmetatable({ character = character }, self); self.__index = self; return o end
function ISBaseTimedAction.stop() end
function ISBaseTimedAction.perform() end
local queued = {}
ISTimedActionQueue = { add = function(a) queued[#queued+1] = a end }

-- ---------------------------------------------------------------- Java engine stubs
if MODE == "engine" then
  EchoesEngine_version = function() return "0.4.0" end
  EchoesEngine_set = function(k, v) played[#played+1] = "SET:" .. k .. "=" .. tostring(v) end
  EchoesEngine_stats = function() return "stats" end
  EchoesEngine_occlusion = function() return 0.55 end
  EchoesEngine_msSinceLoud = function() return 5000 end
  EchoesEngine_lastLoudRadius = function() return 80 end
end

local files = { "shared/Echoes/Core.lua", "shared/Echoes/WorldEvents.lua", "client/Echoes/Timer.lua", "client/Echoes/Sounds.lua",
  "shared/Echoes/Engine.lua", "shared/Echoes/ZombieUtil.lua", "client/Echoes/Weather.lua", "client/Echoes/Acoustics.lua",
  "client/Echoes/Body.lua", "client/Echoes/Psyche.lua", "client/Echoes/Phenomena.lua", "client/Echoes/Places.lua",
  "client/Echoes/Stories.lua", "client/Echoes/Senses.lua", "client/Echoes/VehicleSense.lua", "client/Echoes/Interaction.lua",
  "client/Echoes/Visual.lua", "client/Echoes/Director.lua", "client/Echoes/RoomDecay.lua", "client/Echoes/Fear.lua",
  "client/Echoes/Dizzy.lua", "client/Echoes/Effects.lua", "client/Echoes/Mind.lua", "client/Echoes/Daze.lua", "server/Echoes/ZombieAwareness.lua", "server/Echoes/Tracking.lua",
  "server/Echoes/RadioSignals.lua", "client/Echoes/Debug.lua" }
for _, f in ipairs(files) do dofile((BASE or ".") .. "/Echoes/42/media/lua/" .. f) end

-- ---------------------------------------------------------------- scenario
local failures = {}
local function check(cond, msg) if not cond then failures[#failures+1] = msg; print("[ERROR] ASSERT FAILED: " .. msg) end end
local function count(prefix) local n = 0 for _, p in ipairs(played) do if string.sub(p, 1, #prefix) == prefix then n = n + 1 end end return n end

fire("OnGameStart")
fire("EveryOneMinute"); fire("EveryTenMinutes"); fire("EveryHours")
zresp = true; fire("EveryOneMinute")                      -- a zombie hears something...
zresp = false; fire("EveryOneMinute")                      -- ...then loses it: it must start a search
check(count("PATH@") >= 1, "a zombie that lost a sound starts a search")

Echoes.Places.mark(player, 1)
Echoes.Interaction.listen(player, cell:getGridSquare(104, 100, 0).doorObj or makeDoor(cell:getGridSquare(104, 100, 0), 1))
Echoes.Stories.createLockedIn(player)

-- context menu "Listen at the door": needs the player next to a closed door
local menuDoor = makeDoor(cell:getGridSquare(100, 100, 0), 1)
local options = {}
local ctx = { addOption = function(_, label, target, fn) options[#options+1] = { label = label, target = target, fn = fn } end }
fire("OnFillWorldObjectContextMenu", 0, ctx, { menuDoor }, false)
check(#options == 1, "the 'Listen at the door' option appears next to a closed door")
if options[1] then options[1].fn(options[1].target); check(#queued == 1, "choosing it queues the timed action")
  if queued[1] then queued[1]:perform() end end

-- scent: walk a trail so there is something to follow
for step = 1, 12 do px = 100.5 + step * 2; fire("EveryOneMinute") end
px = 100.5

-- pack alert: one zombie chases, the others are idle
ztarget = {}; fire("EveryOneMinute"); ztarget = nil

-- driving: blind-spot cue path and cabin muffling
inVehicle = true
for _ = 1, 3 do fire("EveryOneMinute") end
inVehicle = false

-- dizziness demo, then the per-frame handler
fire("OnKeyPressed", 66)
ticks(3, 300)

-- visual overlay: every panel draws; apparition via the Director
for _, p in ipairs(panels) do for _ = 1, 3 do tms = tms + 100; p:render() end end
check(#panels >= 1 and drawn > 0, "the overlay panel was created and drew rectangles")

for _ = 1, 8 do Echoes.Director.evaluate(true) end
ticks(40, 200)

-- long run: radio story, alarms, decay of unobserved rooms
for _ = 1, 400 do fire("EveryHours"); for _ = 1, 4 do fire("EveryOneMinute") end end
check(#radioLog >= 3, "the survivor radio story transmitted")

-- haunted places escalate
local pl = Echoes.Places.mark(player, 1); pl.theme = "door"
zombie.getX = function() return 300 end
for _, z in ipairs(extra) do z.pos.x = 400 end
for _ = 1, 80 do gh = gh + 5; Echoes.Director.evaluate(true) end
check(count("DoorOpen") + count("DoorClose") + count("TOGGLE") >= 1, "door phenomena happen")
fire("OnKeyPressed", 65)

check(count("LOCK=") >= 0, "(story lock is optional)")
check(Echoes.Perf and next(Echoes.Perf.stats) ~= nil, "Perf accounting records calls")
local errs = 0
for _, st in pairs(Echoes.Perf.stats) do errs = errs + st.errors end
check(errs == 0, "no module reported errors through Echoes.safe")
print("MODE", MODE, "PLAYED", #played, "RADIO", #radioLog, "DRAWN", drawn, "FAILURES", #failures)
