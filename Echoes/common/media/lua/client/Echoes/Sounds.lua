-- ECHOES sounds (client): resolve sound names against the sounds the game really has.
-- Uses GameSounds.isKnownSound / getCategories / getSoundsInCategory (present in the 42.20 Javadoc,
-- unverified from Lua). If those calls fail, static candidates are used unfiltered.

local Sounds = {}
Echoes.Sounds = Sounds

local knownCache, allNames, resolved = {}, nil, {}

-- true / false, or nil when the check itself is unavailable.
function Sounds.known(name)
    if knownCache[name] ~= nil then return knownCache[name] end
    local ok, res = pcall(function() return GameSounds.isKnownSound(name) end)
    if not ok then return nil end
    knownCache[name] = res and true or false
    return knownCache[name]
end

local function loadAll()
    if allNames then return allNames end
    allNames = {}
    local ok, err = pcall(function()
        local cats = GameSounds.getCategories()
        for i = 0, cats:size() - 1 do
            local list = GameSounds.getSoundsInCategory(cats:get(i))
            for j = 0, list:size() - 1 do
                allNames[#allNames + 1] = list:get(j):getName()
            end
        end
    end)
    if not ok then Echoes.Log.warn("sound discovery unavailable: " .. tostring(err)) end
    Echoes.Log.debug("sound names discovered: " .. #allNames)
    return allNames
end

-- Names whose lowercase form contains any pattern and none of the excluded words.
function Sounds.discover(patterns, exclude)
    local out = {}
    for _, name in ipairs(loadAll()) do
        local low = string.lower(name)
        local hit = false
        for _, p in ipairs(patterns) do
            if string.find(low, p, 1, true) then hit = true; break end
        end
        if hit then
            for _, x in ipairs(exclude or {}) do
                if string.find(low, x, 1, true) then hit = false; break end
            end
        end
        if hit then out[#out + 1] = name end
    end
    return out
end

-- Static candidates that the game does not reject; falls back to discovery by pattern.
-- Result is cached per key. May be empty: callers must handle that.
function Sounds.resolve(key, static, patterns, exclude)
    if resolved[key] then return resolved[key] end
    local out = {}
    for _, n in ipairs(static or {}) do
        if Sounds.known(n) ~= false then out[#out + 1] = n end
    end
    if #out == 0 and patterns then out = Sounds.discover(patterns, exclude) end
    resolved[key] = out
    Echoes.Log.debug("sounds[" .. key .. "] = " .. #out .. " candidates")
    return out
end

-- Plays one of `names` (random) at a world position. Returns the name played, or nil.
function Sounds.playAt(x, y, z, names, volume, pitchJitter)
    if not names or #names == 0 then return nil end
    local em = getWorld():getFreeEmitter(x, y, z)
    if not em then return nil end
    local name = names[1 + ZombRand(#names)]
    local ok, handle = pcall(function() return em:playSound(name) end)
    if not ok then
        Echoes.Log.debug("playSound failed for " .. tostring(name))
        return nil
    end
    if handle and handle ~= 0 then
        pcall(function() em:setVolume(handle, Echoes.clamp(volume or 1.0, 0, 1)) end)
        if pitchJitter then
            pcall(function() em:setPitch(handle, 1.0 - pitchJitter + ZombRandFloat(0, 2 * pitchJitter)) end)
        end
    end
    return name
end
