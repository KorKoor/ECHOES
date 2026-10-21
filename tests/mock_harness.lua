-- Smoke test with a mocked PZ API (NOT a game test). Run from repo root: lua tests/mock_harness.lua (paths below are absolute; adjust).
local handlers = {}
Events = setmetatable({}, { __index = function(t, k)
  local ev = { Add = function(f) handlers[k] = handlers[k] or {}; table.insert(handlers[k], f) end,
               Remove = function(f) end }
  rawset(t, k, ev); return ev end })
local function fire(k, ...) for _, f in ipairs(handlers[k] or {}) do f(...) end end
Keyboard = { KEY_F9 = 67 }
SandboxVars = { Echoes = { Debug = true, Frequency = 4 } }
math.randomseed(1)
function ZombRand(a, b) if b then return math.random(a, b - 1) end return math.random(0, a - 1) end
function ZombRandFloat(a, b) return a + math.random() * (b - a) end
function instanceof(o, c) return o.class == c end
local played = {}
local function list(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end
local function sq(x, y, z, o) o = o or {}
  local s = { x = x, y = y, z = z, objs = o.objs or {} }
  function s:getX() return x end function s:getY() return y end function s:getZ() return z end
  function s:isOutside() return o.outside or false end
  function s:isCouldSee() return false end function s:isFree() return true end
  function s:isBlockedTo() return false end
  function s:getDoor(n) return o.door and n and o.door or nil end
  function s:getObjects() return list(self.objs) end
  function s:getRoom() if x % 2 ~= 0 then return nil end
    return { hasLightSwitches=function() return true end, getRoomDef=function() return { getID=function() return 42 end } end,
      getLightSwitches=function() return list({ setmetatable({ getSquare=function() return s end, getModData=function() return {} end }, { __index = lamp }) }) end,
      getRandomFreeSquare=function() return s end } end
  function s:getModData() return {} end
  return s end
local door = { IsOpen = function() return false end, isLocked = function() return false end,
  isBarricaded = function() return false end, setLocked = function(_, v) played[#played+1]="LOCK="..tostring(v) end, ToggleDoorSilent = function() played[#played+1]="TOGGLE" end }
local lamp = { class = "IsoLightSwitch", isActivated = function() return true end, canSwitchLight = function() return true end,
  setActivated = function(_, v) played[#played+1] = "lamp=" .. tostring(v) end }
local cache = {}
local cell = {}
function cell:getGridSquare(x, y, z) local k = x .. "," .. y .. "," .. z
  if not cache[k] then cache[k] = sq(x, y, z, { door = (x % 5 == 0 and y % 3 == 0) and door or nil, objs = (x % 7 == 0) and { lamp } or {} }) end
  return cache[k] end
local zsq_ = nil
local zombie = { getX=function() return 106.5 end, getY=function() return 100.5 end, getZ=function() return 0 end,
  getCurrentSquare=function() return cell:getGridSquare(106,100,0) end, getModData=function() return zmd end,
  isRespondingToPlayerSound=function() return zresp end, isMovingToPlayerSound=function() return false end,
  getTarget=function() return nil end, pathToLocationF=function(_, x, y) played[#played+1]="PATH@"..math.floor(x)..","..math.floor(y) end }
zmd = {}; zresp = true
function cell:getZombieList() return list({ zombie }) end
local md = {}
local stats = { get = function(_, s) return s.v end }
CharacterStat = {}
for _, n in ipairs({ "ENDURANCE","FATIGUE","STRESS","PANIC","SANITY","WETNESS" }) do
  CharacterStat[n] = { v = 0.3, getMinimumValue = function() return 0 end, getMaximumValue = function() return 1 end } end
local player = { getX=function() return 100.5 end, getY=function() return 100.5 end, getZ=function() return 0 end,
  getCurrentSquare=function() return cell:getGridSquare(100,100,0) end, getModData=function() return md end,
  isDead=function() return false end, getVehicle=function() return nil end, isAsleep=function() return false end,
  getPlayerNum=function() return 0 end, getForwardDirectionX=function() return 1 end, getForwardDirectionY=function() return 0 end, getStats=function() return stats end,
  isRunning=function() return true end, isSprinting=function() return false end,
  getBodyDamage=function() return { getThermoregulator=function() return { getCoreCelcius=function() return 35.5 end } end } end }
function getPlayer() return player end
function getCell() return cell end
function getGameTime() return { getWorldAgeHours = function() return 24*30 end } end
function getClimateManager() return { getNightStrength=function() return 0.9 end, getRainIntensity=function() return 0.5 end,
  getWindIntensity=function() return 0.2 end, getFogIntensity=function() return 0 end } end
function getWorld() return { getFreeEmitter = function(_, x, y, z) return { playSound = function(_, n) played[#played+1] = n; return 1 end,
  setVolume = function(_, h, v) played[#played+1] = string.format("vol=%.2f", v) end, setPitch = function() end } end,
  isHydroPowerOn = function() return true end } end
function getActivatedMods() return { contains = function() return false end } end
local tms = 0
function getTimestampMs() return tms end
GameSounds = { isKnownSound = function(n) return n ~= "FootstepsIndoor" end,
  getCategories = function() return list({ "c" }) end,
  getSoundsInCategory = function() return list({ { getName = function() return "Footstep_Wood" end }, { getName = function() return "BreathHeavy" end }, { getName = function() return "HouseAlarm" end } }) end }
local store = {}
ModData = { getOrCreate = function(k) store[k] = store[k] or {}; return store[k] end }
function isClient() return false end function isServer() return false end
function getWorldSoundManager() return { addSound = function(_, _, x, y) played[#played+1] = "LURE@" .. x .. "," .. y end } end
function getOnlinePlayers() return list({ player }) end
function sendServerCommand() end

for _, f in ipairs({ "shared/Echoes/Core.lua","shared/Echoes/WorldEvents.lua","client/Echoes/Timer.lua","client/Echoes/Sounds.lua",
  "client/Echoes/Weather.lua","client/Echoes/Acoustics.lua","client/Echoes/Body.lua","client/Echoes/Psyche.lua",
  "client/Echoes/Phenomena.lua","client/Echoes/Places.lua","client/Echoes/Stories.lua","client/Echoes/Senses.lua","client/Echoes/VehicleSense.lua","client/Echoes/Interaction.lua","client/Echoes/Visual.lua","client/Echoes/Director.lua","client/Echoes/RoomDecay.lua","server/Echoes/ZombieAwareness.lua" }) do
  dofile("/home/user/ECHOES/Echoes/common/media/lua/" .. f) end
fire("OnGameStart")
fire("EveryOneMinute"); fire("EveryTenMinutes"); fire("EveryHours")
zresp = true; fire("EveryOneMinute")   -- zombie hears something
zresp = false; tms = tms + 1000; fire("EveryOneMinute")  -- ...then loses it: should start a search
Echoes.Places.mark(player, 1)
local sq0 = cell:getGridSquare(100,100,0)
Echoes.Interaction.listen(player, { getSquare = function() return cell:getGridSquare(104,100,0) end })
Echoes.Stories.createLockedIn(player)
for i = 1, 6 do Echoes.Director.evaluate(true) end
-- advance timers
for i = 1, 40 do tms = tms + 200; for _, f in ipairs(handlers.OnTick or {}) do f() end end
print("PLAYED:", table.concat(played, " | "))
print("pressure", Echoes.Psyche.pressure, "winded", Echoes.Body.state.winded, "tremor", Echoes.Body.state.tremor)
