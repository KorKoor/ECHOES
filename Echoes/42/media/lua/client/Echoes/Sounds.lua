-- ECHOES sounds (client): resolve sound names against the sounds the game really has.
-- Uses GameSounds.isKnownSound / getCategories / getSoundsInCategory (present in the 42.20 Javadoc,
-- unverified from Lua). If those calls fail, static candidates are used unfiltered and discovery is retried later.

require "Echoes/Core"

local Sounds = {}
Echoes.Sounds = Sounds

local knownCache, allNames, resolved = {}, nil, {}
local discoveryFailedAt = nil
local RETRY_MS = 60000

-- A looping sound never frees its emitter (we do not keep handles to stop it), so such sounds are never used.
local function isLooping(name)
    local ok, res = pcall(function() return GameSounds.getSound(name):isLooped() end)
    return ok and res == true
end

-- true / false, or nil when the check itself is unavailable.
function Sounds.known(name)
    if knownCache[name] ~= nil then return knownCache[name] end
    local ok, res = pcall(function() return GameSounds.isKnownSound(name) end)
    if not ok then return nil end
    knownCache[name] = res and true or false
    return knownCache[name]
end

-- Loads every sound name once. A failure is not cached: it is retried after RETRY_MS (the sound list may simply
-- not have been ready yet), and in the meantime callers get an empty list.
local function loadAll()
    if allNames then return allNames end
    local okT, now = pcall(getTimestampMs)
    if not okT or type(now) ~= "number" then now = nil end
    if discoveryFailedAt and now and now - discoveryFailedAt < RETRY_MS then return {} end
    local names = {}
    local ok, err = pcall(function()
        local cats = GameSounds.getCategories()
        for i = 0, cats:size() - 1 do
            local list = GameSounds.getSoundsInCategory(cats:get(i))
            for j = 0, list:size() - 1 do
                local gs = list:get(j)
                local okL, looped = pcall(function() return gs:isLooped() end)
                if not (okL and looped == true) then names[#names + 1] = gs:getName() end
            end
        end
    end)
    if not ok or #names == 0 then
        discoveryFailedAt = now -- nil without a clock: then every call retries
        Echoes.Log.warn("sound discovery unavailable (retry in 60 s): " .. tostring(err))
        return {}
    end
    allNames = names
    Echoes.Log.debug("sound names discovered: " .. #names)
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
-- The result is cached under a key made from ALL inputs (two callers with different excludes never share it),
-- except an empty result obtained while discovery was unavailable, which is recomputed later.
function Sounds.resolve(key, static, patterns, exclude)
    local cacheKey = key .. "|" .. table.concat(static or {}, ",") .. "|" .. table.concat(patterns or {}, ",")
        .. "|" .. table.concat(exclude or {}, ",")
    if resolved[cacheKey] then return resolved[cacheKey] end
    local out = {}
    for _, n in ipairs(static or {}) do
        if Sounds.known(n) ~= false and not isLooping(n) then out[#out + 1] = n end
    end
    if #out == 0 and patterns then out = Sounds.discover(patterns, exclude) end
    if #out > 0 or allNames then resolved[cacheKey] = out end
    Echoes.Log.debug("sounds[" .. key .. "] = " .. #out .. " candidates")
    return out
end

-- Plays one of `names` (random order, up to 3 tries) at a world position. Returns the name that actually played, or
-- nil. A handle of 0 from the emitter means "nothing started" and counts as a failure.
-- Sounds from the world are scaled by the player's current hearing (deafness after gunfire, panic); `internal`
-- sounds (your own breathing, heartbeat, ringing) are not.
function Sounds.playAt(x, y, z, names, volume, pitchJitter, uncertain, internal)
    if not names or #names == 0 then return nil end
    if uncertain and Echoes.Senses then x, y, z = Echoes.Senses.uncertain(x, y, z) end
    if not internal and Echoes.Body then volume = (volume or 1.0) * Echoes.Body.hearingNow() end
    local em = getWorld():getFreeEmitter(x, y, z)
    if not em then return nil end
    local tries = math.min(3, #names)
    local start = ZombRand(#names)
    for i = 0, tries - 1 do
        local name = names[1 + (start + i) % #names]
        local ok, handle = pcall(function() return em:playSound(name) end)
        if ok and not (type(handle) == "number" and handle == 0) then
            if type(handle) == "number" then
                pcall(function() em:setVolume(handle, Echoes.clamp(volume or 1.0, 0, 1)) end)
                if pitchJitter then
                    pcall(function() em:setPitch(handle, 1.0 - pitchJitter + ZombRandFloat(0, 2 * pitchJitter)) end)
                end
            end
            return name
        end
        Echoes.Log.debug("sound did not play: " .. tostring(name))
    end
    return nil
end
