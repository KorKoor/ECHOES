-- EchoesInventory: engine / Viewpoint reconnaissance for the Java tier of ECHOES.
-- Prints "[EchoesInv]" lines to console.txt. Read-only; changes nothing.
-- Run: enter a game and press F10 (or wait for the automatic run ~10 s after start).
-- Needs ZombieBuddy launched with the `experimental` parameter for zbinspect/zbmethods/zbgrep; without it only the
-- first sections work (see doc/DevDebugFunctions.md in the ZombieBuddy repo).

local TAG = "[EchoesInv] "
local function log(msg) print(TAG .. tostring(msg)) end

local function try(name, fn)
    local ok, res = pcall(fn)
    if not ok then log("FAIL " .. name .. " -> " .. tostring(res)) end
    return ok and res or nil
end

local PATTERNS = { "viewpoint", "firstperson", "first_person", "fpv", "camera", "perspective", "fov", "lean", "peek" }

local function matches(s)
    s = string.lower(tostring(s))
    for _, p in ipairs(PATTERNS) do
        if string.find(s, p, 1, true) then return true end
    end
    return false
end

local function section(title) log("---- " .. title .. " ----") end

local function globals()
    section("Lua globals that look related")
    local found = 0
    for k, v in pairs(_G) do
        if type(k) == "string" and matches(k) then
            found = found + 1
            log("global " .. k .. " : " .. type(v))
            if type(v) == "table" then
                local n = 0
                for kk, vv in pairs(v) do
                    n = n + 1
                    if n <= 60 then log("    " .. k .. "." .. tostring(kk) .. " : " .. type(vv)) end
                end
                log("    (" .. n .. " entries)")
            end
        end
    end
    log(found .. " related globals")
end

local function zbStatus()
    section("ZombieBuddy and Java mods")
    if not ZombieBuddy then log("ZombieBuddy global not present"); return end
    try("version", function() log("ZombieBuddy " .. tostring(ZombieBuddy.getVersion())) end)
    try("policy", function()
        if type(ZombieBuddy.getPolicy) ~= "function" then log("ZombieBuddy.getPolicy not available in 2.3.4") return end
        log("policy " .. tostring(ZombieBuddy.getPolicy()))
    end)
    for _, id in ipairs({ "Viewpoint", "ZombieBuddy", "EchoesEngine" }) do
        try("status " .. id, function()
            if type(ZombieBuddy.getJavaModStatus) ~= "function" then log("ZombieBuddy.getJavaModStatus not available in 2.3.4") return end
            local s = ZombieBuddy.getJavaModStatus(id)
            if not s then log("javaMod[" .. id .. "] = no JAR considered") return end
            log("javaMod[" .. id .. "] loaded=" .. tostring(s.loaded) .. " reason=" .. tostring(s.reason))
        end)
    end
end

local function viewpointEvents()
    section("Event callbacks registered by Viewpoint-like Lua files")
    if not (ZombieBuddy and ZombieBuddy.Events) then log("ZombieBuddy.Events not available"); return end
    try("events", function()
        local all = ZombieBuddy.Events.getAll()
        local hits = 0
        for evName, callbacks in pairs(all) do
            for i = 1, callbacks:size() do
                local info = ZombieBuddy.getClosureInfo(callbacks:get(i - 1))
                if info and matches(info.filename or "") then
                    hits = hits + 1
                    log(evName .. " <- " .. tostring(info.filename) .. ":" .. tostring(info.line))
                end
            end
        end
        log(hits .. " callbacks from related files")
    end)
end

local function engineObjects()
    section("Engine objects: methods/fields that look related (needs experimental)")
    if not zbmethods then log("zbmethods not available: launch ZombieBuddy with `experimental`"); return end
    local targets = {
        { "getCore()", function() return getCore() end },
        { "getPlayer()", function() return getPlayer() end },
        { "getCell()", function() return getCell() end },
        { "getWorld()", function() return getWorld() end },
        { "getSoundManager()", function() return getSoundManager() end },
    }
    for _, t in ipairs(targets) do
        local obj = try(t[1], t[2])
        if obj then
            local ms = try("zbmethods " .. t[1], function() return zbmethods(obj) end)
            local count = 0
            if ms then
                for i = 1, #ms do
                    if matches(ms[i]) then count = count + 1; log(t[1] .. " method: " .. tostring(ms[i])) end
                end
            end
            local fs = try("zbfields " .. t[1], function() return zbfields(obj, true) end)
            if fs then
                for k, v in pairs(fs) do
                    if matches(k) then count = count + 1; log(t[1] .. " field: " .. tostring(k) .. " = " .. tostring(v)) end
                end
            end
            log(t[1] .. ": " .. count .. " related members")
        end
    end
end

local function audioClasses()
    section("Audio: concrete emitter classes (to find where every game sound can be intercepted)")
    if not zbinspect then log("zbinspect not available: launch ZombieBuddy with `experimental`"); return end
    local function describe(label, obj)
        local info = try(label, function() return zbinspect(obj) end)
        if info then
            log(label .. " class = " .. tostring(info.type))
            local n = 0
            for _, m in ipairs(info.methods or {}) do
                if string.find(string.lower(m), "play") or string.find(string.lower(m), "volume") or string.find(string.lower(m), "tick") then
                    n = n + 1
                    if n <= 25 then log("    " .. m) end
                end
            end
        end
    end
    try("world emitter", function()
        local p = getPlayer()
        local em = getWorld():getFreeEmitter(p:getX(), p:getY(), p:getZ())
        describe("getWorld():getFreeEmitter()", em)
    end)
    try("player emitter", function() describe("getPlayer():getEmitter()", getPlayer():getEmitter()) end)
    try("sound manager", function() describe("getSoundManager()", getSoundManager()) end)
end

local function runAll()
    log("== inventory start ==")
    zbStatus()
    globals()
    viewpointEvents()
    engineObjects()
    audioClasses()
    log("== inventory end ==")
end

local ticks, done = 0, false
local function onTick()
    if done then return end
    ticks = ticks + 1
    if ticks >= 600 then
        done = true
        Events.OnTick.Remove(onTick)
        runAll()
    end
end

Events.OnGameStart.Add(function() ticks, done = 0, false; Events.OnTick.Add(onTick) end)
Events.OnKeyPressed.Add(function(key) if key == Keyboard.KEY_F10 then runAll() end end)
