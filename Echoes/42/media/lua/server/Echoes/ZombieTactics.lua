-- ECHOES zombie tactics (server / single player): zombies with a past, armed zombies and simple squad plans.
--   Profile   A zombie gets a persistent profile the first time it is seen (zombie ModData, so it is remembered): a role
--             from its outfit (police, soldier, guard...), possibly a firearm with a fixed amount of ammo and a marksman
--             skill, and a grudge if the player has hurt it (a grudge zombie shoots faster and searches longer).
--   Shooting  An armed zombie that is hunting a player, 4..16 tiles away and in plain sight stops and aims for ~2 s, then
--             fires: a real gunshot sound, a loud world sound (everything within reach hears it), and a hit roll that
--             depends on skill, distance and whether you are running. A hit uses BodyPart.damageFromFirearm. Never the
--             head or neck, so no instant deaths. A miss still frightens. Ammo runs out and is remembered.
--   Plans     When three or more zombies hunt the same player, up to two bold ones peel off and take a flanking position
--             to the side (a square derived from the player they are already chasing, never a hidden one).
-- Confirmed with javap on the 42.21 classes: IsoZombie.getTarget/getOutfitName/pathToLocationF, BodyPart.damageFromFirearm,
-- BodyDamage.getBodyPart, WorldSoundManager.addSound. UNTESTED in game: damage scale (12..20 per hit), outfit names,
-- whether pathToLocationF to the zombie's own square holds it still, how the horde reacts to a flank.

require "Echoes/Core"
require "Echoes/ZombieUtil"

local Log, Config = Echoes.Log, Echoes.Config
local ZU = Echoes.ZombieUtil

local Tactics = {}
Echoes.Tactics = Tactics

local TICK_MS = 500
local SHOOT_RANGE_MAX, SHOOT_RANGE_MIN = 16, 4
local AIM_MS = 2200
local lastTick, lastPlan = 0, 0

local GUN_WORDS = { "police", "swat", "army", "soldier", "military", "ranger", "security", "guard", "sheriff", "deputy", "national" }
local BODY_PARTS = { "Torso_Upper", "Torso_Upper", "Torso_Upper", "Torso_Lower", "Torso_Lower", "UpperArm_L", "UpperArm_R",
    "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "ForeArm_L", "ForeArm_R" } -- never Head / Neck

-- Profile ------------------------------------------------------------------------------------------------------
function Tactics.profile(z)
    local md = z:getModData()
    if md.echoesRole then return md end
    local outfit = ""
    pcall(function() outfit = string.lower(tostring(z:getOutfitName() or "")) end)
    md.echoesRole = "walker"
    for _, w in ipairs(GUN_WORDS) do
        if string.find(outfit, w, 1, true) then
            md.echoesRole = "gunner"
            if ZombRandFloat(0, 1) < 0.6 then -- not every uniform kept its weapon
                md.echoesAmmo = 3 + ZombRand(10)
                md.echoesSkill = 0.3 + ZombRandFloat(0, 0.5)
            end
            Echoes.count("ai.gunner")
            break
        end
    end
    return md
end

local function armed(md) return md.echoesRole == "gunner" and (md.echoesAmmo or 0) > 0 end

-- Memory of being hurt: the handler looks for a zombie among the event arguments, so any argument order works.
local function onHit(...)
    local player = getPlayer()
    if not player then return end
    for _, a in ipairs({ ... }) do
        if type(a) == "userdata" and instanceof(a, "IsoZombie") then
            local md = a:getModData()
            md.echoesGrudge = true
            md.echoesHits = (md.echoesHits or 0) + 1
            local p = ZU.personality(a)
            p.persist = math.min(1, p.persist + 0.15)
            Echoes.count("ai.grudge")
            return
        end
    end
end
Events.OnWeaponHitCharacter.Add(function(...) Echoes.safe("Tactics.grudge", onHit, ...) end)

-- Shooting -------------------------------------------------------------------------------------------------------
local gunNames
local function gunSounds()
    if gunNames == nil then
        gunNames = {}
        if Echoes.Sounds then
            local excl = { "reload", "insert", "eject", "equip", "rack", "jam", "dry", "empty", "break", "pump", "cartridge",
                "clip", "magazine", "fall", "unload", "load", "safety", "holster" }
            gunNames = Echoes.Sounds.resolve("gunShot", {}, { "pistolshoot", "revolvershoot", "shoot" }, excl)
        end
    end
    return gunNames
end

local function hitChance(md, d, running, grudge)
    local skill = (md.echoesSkill or 0.4) + (grudge and 0.1 or 0)
    local c = skill * (1.0 - d / 22.0) * (running and 0.6 or 1.0) * 0.8
    return Echoes.clamp(c, 0.05, 0.55)
end

local function fire(z, md, player, now)
    md.echoesAmmo = md.echoesAmmo - 1
    md.echoesNextShot = now + 3500 + ZombRand(2500)
    Echoes.count("ai.shot")
    local x, y, zz = z:getX(), z:getY(), z:getZ()
    local names = gunSounds()
    if #names > 0 and Echoes.Sounds then Echoes.Sounds.playAt(x, y, zz, names, 1.0, 0.03, false, true) end
    pcall(function() getWorldSoundManager():addSound(z, x, y, zz, 60, 80) end) -- a gunshot carries; every zombie nearby hears it
    local dx, dy = player:getX() - x, player:getY() - y
    local d = math.sqrt(dx * dx + dy * dy)
    local running = false
    pcall(function() running = player:isRunning() or player:isSprinting() end)
    if ZombRandFloat(0, 1) < hitChance(md, d, running, md.echoesGrudge) then
        Echoes.count("ai.shot_hit")
        pcall(function()
            local part = player:getBodyDamage():getBodyPart(BodyPartType[BODY_PARTS[1 + ZombRand(#BODY_PARTS)]])
            part:damageFromFirearm(12 + ZombRand(9)) -- damage scale unverified: 12..20
        end)
        if Echoes.Fear then Echoes.Fear.shock(0.35) end
        Echoes.feel(player, { PAIN = 0.10, PANIC = 0.20, STRESS = 0.10 })
        if Echoes.Mind then Echoes.Mind.react("shot_hit", 1.0, { urgent = true }) end
    else
        if Echoes.Fear then Echoes.Fear.shock(0.15) end
        Echoes.feel(player, { PANIC = 0.08, STRESS = 0.05 })
        if Echoes.Mind then Echoes.Mind.react("shot_miss", 1.0, { urgent = true }) end
    end
end

local function shoot(players, now)
    for _, z in ipairs(ZU.nearbyZombies(players, SHOOT_RANGE_MAX + 2, 40)) do
        local md = Tactics.profile(z)
        if armed(md) then
            local target = z:getTarget()
            local pl = target and ZU.nearestPlayer(z, players, SHOOT_RANGE_MAX)
            local ok = false
            if pl and target == pl then
                local dx, dy = pl:getX() - z:getX(), pl:getY() - z:getY()
                local d2 = dx * dx + dy * dy
                local zsq = z:getCurrentSquare()
                ok = d2 >= SHOOT_RANGE_MIN * SHOOT_RANGE_MIN and math.abs(pl:getZ() - z:getZ()) < 1
                    and zsq ~= nil and zsq:isCouldSee(pl:getPlayerNum())
            end
            if ok and now >= (md.echoesNextShot or 0) then
                if not md.echoesAim then
                    md.echoesAim = now
                    if not md.echoesAnnounced and Echoes.Mind then
                        md.echoesAnnounced = true
                        Echoes.count("ai.aim")
                        Echoes.Mind.react("gunner", 1.0, { urgent = true })
                    end
                end
                pcall(function() z:pathToLocationF(z:getX(), z:getY(), z:getZ()) end) -- hold still while aiming
                ZU.setBusy(z, now, 1500)
                local aim = AIM_MS * (md.echoesGrudge and 0.75 or 1.0) * (1.4 - (md.echoesSkill or 0.4))
                if now - md.echoesAim >= aim then
                    md.echoesAim = nil
                    fire(z, md, target, now)
                end
            else
                md.echoesAim = nil
            end
        end
    end
end

-- Plans --------------------------------------------------------------------------------------------------------
local function plan(players, now)
    if now - lastPlan < 10000 then return end
    for _, p in ipairs(players) do
        local chasers = {}
        for _, z in ipairs(ZU.nearbyZombies({ p }, 25, 30)) do
            if z:getTarget() == p then chasers[#chasers + 1] = z end
        end
        if #chasers >= 3 then
            local sent = 0
            for _, z in ipairs(chasers) do
                local md = Tactics.profile(z)
                local pers = ZU.personality(z)
                local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
                local d = math.sqrt(dx * dx + dy * dy)
                if sent < 2 and md.echoesRole ~= "gunner" and pers.bold > 0.55 and d >= 8 and d <= 20 and ZU.isIdle(z, now) == false
                    and (md.echoesBusy == nil or now > md.echoesBusy) then
                    local side = (sent == 0) and 1 or -1
                    local ang = math.atan2(dy, dx) + side * 1.2 -- about 70 degrees to the side of the line to the player
                    local tx, ty = p:getX() + math.cos(ang) * 6, p:getY() + math.sin(ang) * 6
                    local sq = getCell():getGridSquare(math.floor(tx), math.floor(ty), math.floor(p:getZ()))
                    if sq and sq:isFree(false) then
                        pcall(function() z:pathToLocationF(sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ()) end)
                        ZU.setBusy(z, now, 4000)
                        sent = sent + 1
                        Echoes.count("ai.flank")
                    end
                end
            end
            if sent > 0 then
                lastPlan = now
                if Echoes.Mind and p == getPlayer() then Echoes.Mind.react("plan", 0.6) end
                return
            end
        end
    end
end

local function tick()
    if isClient() then return end
    local now = getTimestampMs()
    if now - lastTick < TICK_MS then return end
    lastTick = now
    local players = ZU.players()
    if #players == 0 then return end
    if Config.isEnabled("ArmedZombies") then Echoes.safe("Tactics.shoot", shoot, players, now) end
    -- Flanking is owned by Brain when it is on (it adds beliefs, cordons and sweeps); this older planner is the fallback.
    if Config.isEnabled("Tactics") and not Config.isEnabled("Brain") then Echoes.safe("Tactics.plan", plan, players, now) end
end

Events.OnTick.Add(tick)
Events.OnGameStart.Add(function() lastTick, lastPlan, gunNames = 0, 0, nil end)