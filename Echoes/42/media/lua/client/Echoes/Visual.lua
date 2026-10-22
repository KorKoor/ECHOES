-- ECHOES visual (client): a transparent screen overlay for (a) eye adaptation / glare and (b) fleeting silhouettes.
-- Everything is drawn with plain rectangles through the vanilla UI (ISPanel): no models, no textures, no shaders.
-- EXPERIMENTAL, off by default (sandbox: Visual, Apparitions). Risks to verify in game:
--   * the full-screen panel must not swallow mouse clicks;
--   * under Viewpoint / shader packs the UI layer is still drawn on top, but its look may change.
-- Fairness: the overlay is uniform (no region hides a threat) and capped at low alpha. The silhouette sits at the
-- screen edge in screen space, so it never pretends to be a real object in the world. UNTESTED.

require "Echoes/Core"

local Log, Config = Echoes.Log, Echoes.Config

local Visual = {}
Echoes.Visual = Visual

local state = {
    glare = 0, dark = 0, avgLight = nil, lastSample = 0, lastFrame = 0,
    fig = nil,
}
local panel

local MAX_GLARE, MAX_DARK, MAX_FIG_ALPHA = 0.30, 0.22, 0.5

local function facingAngle(player)
    return Echoes.atan2(player:getForwardDirectionY(), player:getForwardDirectionX())
end

-- Adaptation ------------------------------------------------------------------------------------
local function sampleLight(player, now)
    if now - state.lastSample < 300 then return end
    state.lastSample = now
    local sq = player:getCurrentSquare()
    if not sq then return end
    local ok, light = pcall(function() return sq:getLightLevel(player:getPlayerNum()) end)
    if not ok or type(light) ~= "number" then return end
    light = Echoes.clamp(light, 0, 1)
    if state.avgLight == nil then state.avgLight = light; return end
    local delta = light - state.avgLight
    if delta > 0.35 then
        state.glare = math.max(state.glare, math.min(MAX_GLARE, delta * 0.5))
    elseif delta < -0.35 then
        state.dark = math.max(state.dark, math.min(MAX_DARK, -delta * 0.4))
    end
    state.avgLight = state.avgLight + (light - state.avgLight) * 0.25 -- eyes adapt over a few samples
end

-- Silhouette ----------------------------------------------------------------------------------------
local function drawFigure(p, cx, baseY, h, a)
    local parts = {
        { -0.060, -1.00, 0.120, 0.13 },  -- head
        { -0.110, -0.87, 0.220, 0.38 },  -- torso
        { -0.165, -0.85, 0.050, 0.34 },  -- left arm
        { 0.115, -0.85, 0.050, 0.34 },   -- right arm
        { -0.095, -0.49, 0.085, 0.49 },  -- left leg
        { 0.010, -0.49, 0.085, 0.49 },   -- right leg
    }
    for pass = 1, 3 do -- soft edge: wider, fainter copies underneath
        local grow = (3 - pass) * 3
        local alpha = a * (pass == 3 and 1.0 or (pass == 2 and 0.35 or 0.18))
        for _, r in ipairs(parts) do
            p:drawRect(cx + r[1] * h - grow, baseY + r[2] * h - grow, r[3] * h + 2 * grow, r[4] * h + 2 * grow,
                alpha, 0.02, 0.02, 0.04)
        end
    end
end

function Visual.apparition(player)
    if not panel or state.fig then return nil end
    local w, hgt = getCore():getScreenWidth(), getCore():getScreenHeight()
    local left = ZombRand(2) == 0
    local fx = left and (0.07 + ZombRandFloat(0, 0.13)) or (0.80 + ZombRandFloat(0, 0.13))
    local figH = hgt * (0.14 + ZombRandFloat(0, 0.08)) -- small: it is "far away"
    state.fig = {
        x = fx * w, base = hgt * (0.58 + ZombRandFloat(0, 0.06)), h = figH,
        start = getTimestampMs(), life = 700 + ZombRand(900), angle = facingAngle(player),
    }
    Log.debug("apparition started")
    return player:getCurrentSquare()
end

local function figureAlpha(now, fig, player)
    local t = now - fig.start
    if t >= fig.life then return nil end
    -- vanishes as soon as you turn toward it
    local turned = math.abs(Echoes.atan2(math.sin(facingAngle(player) - fig.angle), math.cos(facingAngle(player) - fig.angle)))
    if turned > 0.6 then return nil end
    local fadeIn, fadeOut = 250, 350
    local a = MAX_FIG_ALPHA
    if t < fadeIn then a = a * (t / fadeIn) end
    if fig.life - t < fadeOut then a = a * ((fig.life - t) / fadeOut) end
    return a
end

-- Panel -----------------------------------------------------------------------------------------------
local function createPanel()
    if panel or not ISPanel then return end
    EchoesOverlay = ISPanel:derive("EchoesOverlay")

    function EchoesOverlay:onMouseDown() return false end
    function EchoesOverlay:onMouseUp() return false end
    function EchoesOverlay:onRightMouseDown() return false end
    function EchoesOverlay:onRightMouseUp() return false end
    function EchoesOverlay:onMouseMove() return false end
    function EchoesOverlay:prerender() end

    function EchoesOverlay:renderInner()
        local player = getPlayer()
        if not player or not Config.isEnabled("Visual") then return end
        local now = getTimestampMs()
        local dt = math.min(0.1, (now - state.lastFrame) / 1000)
        state.lastFrame = now

        sampleLight(player, now)
        state.glare = math.max(0, state.glare - dt * 0.20)
        state.dark = math.max(0, state.dark - dt * 0.08)

        local w, h = self:getWidth(), self:getHeight()
        if state.glare > 0.01 then self:drawRect(0, 0, w, h, state.glare, 1.0, 1.0, 0.95) end
        if state.dark > 0.01 then self:drawRect(0, 0, w, h, state.dark, 0.0, 0.0, 0.02) end

        -- Fear / dizziness vignette: dark edges that pulse with the heartbeat.
        local edge = math.max((Echoes.Fear and Echoes.Fear.level or 0) * 0.5, (Echoes.Dizzy and Echoes.Dizzy.level or 0) * 0.6)
        if edge > 0.05 then
            local since = now - (Echoes.Fear and Echoes.Fear.lastBeat or 0)
            local env = math.exp(-since / 180)
            local a = math.min(0.35, edge * (0.25 + 0.5 * env))
            for i = 0, 5 do
                local band = w * 0.025 * (i + 1)
                local ai = a * (1 - i / 6)
                self:drawRect(0, 0, w, band * h / w, ai * 0.5, 0, 0, 0)
                self:drawRect(0, h - band * h / w, w, band * h / w, ai * 0.5, 0, 0, 0)
                self:drawRect(0, 0, band, h, ai * 0.5, 0, 0, 0)
                self:drawRect(w - band, 0, band, h, ai * 0.5, 0, 0, 0)
            end
        end

        if state.fig and Config.isEnabled("Apparitions") then
            local a = figureAlpha(now, state.fig, player)
            if a then drawFigure(self, state.fig.x, state.fig.base, state.fig.h, a) else state.fig = nil end
        end
    end

    local renderErrors = 0
    function EchoesOverlay:render()
        if renderErrors >= 5 then return end -- gave up: never spam errors every frame
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        if self:getWidth() ~= sw or self:getHeight() ~= sh then -- window or resolution changed
            pcall(function() self:setWidth(sw); self:setHeight(sh) end)
        end
        local ok, err = pcall(self.renderInner, self)
        if not ok then
            renderErrors = renderErrors + 1
            if renderErrors == 1 then Log.error("overlay render failed: " .. tostring(err)) end
            if renderErrors >= 5 then Log.warn("overlay disabled after repeated errors") end
        else
            renderErrors = 0
        end
    end

    local p = EchoesOverlay:new(0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
    p:initialise()
    p:instantiate()
    p.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    p.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    pcall(function() p.javaObject:setConsumeMouseEvents(false) end)
    p:addToUIManager()
    p:setVisible(true)
    panel = p
    Log.info("visual overlay created")
end

-- Creates the overlay if it is wanted now but was not made at game start (effects switched on at runtime).
function Visual.ensure()
    if Config.isEnabled("Visual") and not panel then Echoes.safe("Visual.createPanel", createPanel) end
end

function Visual.available()
    if not Config.isEnabled("Visual") or not Config.isEnabled("Apparitions") or not panel then return {} end
    return { { id = "apparition", weight = 0.08, ambiguous = true, run = Visual.apparition } }
end

Events.OnGameStart.Add(function()
    if panel then -- a previous game's overlay: remove it, the screen state belongs to the old world
        pcall(function() panel:removeFromUIManager() end)
        panel = nil
    end
    state.glare, state.dark, state.avgLight, state.fig = 0, 0, nil, nil
    if Config.isEnabled("Visual") then Echoes.safe("Visual.createPanel", createPanel) end
end)
