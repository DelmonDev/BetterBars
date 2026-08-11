local api = require("api")
local settings = require("BetterBars/settings")
local default_settings = require("BetterBars/default_settings")

-- UI scale. Same rules as main.lua - see UI_SCALING.md for the full story.
--
-- Widget offsets are in UI units and device pixels = UI units * scale, and the
-- scale is usually neither 1 nor round (the option slider's "80" and "90" apply
-- 0.85 and 0.93; the default is 0.85 below 1280x864).
--
-- This whole window is drawn in the "dark rectangle with a 1-unit inset fill"
-- idiom, which is a 1px border by construction. At 1.3 that inset is 1.3 device
-- pixels, so it rasterises to 1 or 2 depending where the widget happens to sit -
-- borders that look doubled on some controls and not others.
--
-- Px(n) fixes a size in device pixels, so a 1px border is 1px at any scale.
-- Deliberately NOT applied to the chunky decoration (24/30px headers, the 4px
-- accent stripe, the colour cube's thick inset): those are meant to scale with
-- the window, and they are wide enough that a fractional edge does not show.
--
-- Read at build time. If the player changes UI scale with the window open it
-- will not re-derive until the window is rebuilt, which is a fair trade for not
-- recomputing this on every draw.
local function UIScale()
    local s
    pcall(function() s = api.Interface:GetUIScale() end)
    if type(s) ~= "number" or s <= 0 then return 1 end
    return s
end

local function Px(n)
    return n / UIScale()
end

-- Single source of the addon version for the credit label; main.lua's
-- manifest carries the same literal (kept in sync by hand - requiring this
-- module at parse time caused the every-login reset bug).
local ADDON_VERSION = "3.1"

-- Aborts the enclosing pcall - the sandbox has no error()/assert(); indexing a
-- nil is the only deliberate raise available. See BBFail in main.lua.
local function BBFail()
    local nothing
    return nothing.forced_failure
end

-- Waiting for Aguru to enable castbar in API :)
-- Hides the Cast bar toggle and its colour control; the feature itself is
-- parked behind the same flag in main.lua.
local CAST_BAR_ENABLED = false

-- =============================================
-- MAIN SETTINGS WINDOW SECTION

-- Reload-safe session counter — bare global survives /reloadui
if not bbSession then bbSession = 1 else bbSession = bbSession + 1 end
local SESSION = bbSession
-- =============================================
local settingsWindow = nil
local controls = {}
local currentSettings = {}
local isSettingsPageOpened = false
local colorPopup = nil
local colorPopupTarget = nil  -- which color key ("hp", "mp", "ehp") the popup is editing
local wndColorCubes = {}      -- color cube widgets for live update
local wndUpdateColorCubes = nil  -- function to refresh cubes from colorValues
local wndRefreshDisplayValues = nil  -- function to refresh value labels after reset

-- Color value storage — source of truth, never read from drawables
local colorValues = {}

local function loadColorValues()
    local s = settings.getColors()
    for _, key in ipairs({"hp", "mp", "ehp", "cast"}) do
        if s[key] then
            colorValues[key] = {
                r = s[key].r,
                g = s[key].g,
                b = s[key].b,
                a = s[key].a or 1
            }
        end
    end
end

local function applyColorToDrawable(key)
    local btn = controls[key .. "ColorButton"]
    if not btn or not btn.colorBG then return end
    local cv = colorValues[key]
    if cv then
        btn.colorBG:SetColor(cv.r / 255, cv.g / 255, cv.b / 255, cv.a or 1)
    end
end

local function saveColorToGame(key)
    local cv = colorValues[key]
    if not cv then return end
    local newColors = {}
    newColors[key] = { r = cv.r, g = cv.g, b = cv.b, a = cv.a }
    settings.updateColors(newColors)
    settings.saveSettings()
end

local function applyAllColors()
    for _, key in ipairs({"hp", "mp", "ehp", "cast"}) do
        applyColorToDrawable(key)
    end
end

-- Debug helper
local function debugLog(message)
    -- if api.Log and api.Log.Info then
    --     api.Log:Info("BetterBars: " .. message)
    -- end
end

-- Error helper
local function errorLog(message)
    -- if api.Log and api.Log.Err then
    --     api.Log:Err("BetterBars: " .. message)
    -- end
end

-- Function to hide color popup
local function hideColorPopup()
    if colorPopup then
        colorPopup:Show(false)
    end
end

-- Function to update settings fields from colorValues, and refresh cubes
local function updateSettingsFields()
    if not settingsWindow then return end
    loadColorValues()
    applyAllColors()
    if wndUpdateColorCubes then
        wndUpdateColorCubes()
    end
end

-- Function to save settings from colorValues table (NOT from drawables)
local function saveSettings()
    if not currentSettings then
        currentSettings = { colors = {} }
    elseif not currentSettings.colors then
        currentSettings.colors = {}
    end
    
    -- Save each color from the colorValues table (reliable) instead of reading from drawables (unreliable)
    for _, key in ipairs({"hp", "mp", "ehp", "cast"}) do
        local cv = colorValues[key]
        if cv then
            currentSettings.colors[key] = { r = cv.r, g = cv.g, b = cv.b, a = cv.a }
        end
    end
    
    settings.updateColors(currentSettings.colors)
    settings.saveSettings()
    UpdateColorsFromSettings()
    
    -- Hide color popup if it's visible
    hideColorPopup()
end

-- Function to reset settings to defaults. Each stage is pcall'd and any
-- failure is surfaced: the event emitter behind saveSettings runs listeners
-- WITHOUT protection (addons.lua EventHandler:emit), so an unprotected error
-- anywhere down the chain used to kill this handler silently, mid-reset.
local function resetSettings()
    local function step(name, fn)
        local ok, err = pcall(fn)
        if not ok then
            api.Log:Err("BetterBars reset - " .. name .. " failed: " .. tostring(err))
        end
        return ok
    end
    step("colors", function()
        colorValues = {}
        for _, key in ipairs({"hp", "mp", "ehp", "cast"}) do
            local d = default_settings.colors[key]
            colorValues[key] = { r = d.r, g = d.g, b = d.b, a = d.a }
        end
        applyAllColors()
    end)
    step("store", function() settings.resetToDefaults() end)
    step("cubes", function() if wndUpdateColorCubes then wndUpdateColorCubes() end end)
    step("controls", function() if wndRefreshDisplayValues then wndRefreshDisplayValues() end end)
    step("popup", hideColorPopup)
end

-- Function to close settings window
local function closeSettingsWindow()
    if settingsWindow then
        settingsWindow:Show(false)
        isSettingsPageOpened = false
        
        -- Hide color popup if it's visible
        hideColorPopup()
    end
end

-- Preset swatches under the wheel: 10 hues in a bright and a deep row. The
-- wheel + brightness slider cover everything else, so the six-row wall of
-- near-duplicates is gone.
local colorPalette = {
    -- Row 1 (bright)
    { r = 255, g = 80,  b = 80,  a = 1 },
    { r = 255, g = 150, b = 60,  a = 1 },
    { r = 255, g = 220, b = 70,  a = 1 },
    { r = 150, g = 220, b = 60,  a = 1 },
    { r = 127, g = 189, b = 28,  a = 1 },   -- default HP green
    { r = 70,  g = 210, b = 180, a = 1 },
    { r = 50,  g = 150, b = 255, a = 1 },   -- default MP blue
    { r = 90,  g = 120, b = 255, a = 1 },
    { r = 170, g = 100, b = 255, a = 1 },
    { r = 240, g = 100, b = 200, a = 1 },
    -- Row 2 (deep)
    { r = 199, g = 80,  b = 57,  a = 1 },   -- default enemy red
    { r = 190, g = 100, b = 30,  a = 1 },
    { r = 200, g = 160, b = 30,  a = 1 },
    { r = 100, g = 160, b = 30,  a = 1 },
    { r = 40,  g = 150, b = 40,  a = 1 },
    { r = 30,  g = 150, b = 130, a = 1 },
    { r = 40,  g = 130, b = 200, a = 1 },
    { r = 50,  g = 70,  b = 190, a = 1 },
    { r = 120, g = 60,  b = 190, a = 1 },
    { r = 180, g = 60,  b = 140, a = 1 },
}


-- =============================================
-- HELPERS — local UI widget factories
-- =============================================
local C  -- forward declaration (set below)
local U = {}

function U.SetTextColor(widget, color)
    if widget and widget.style and widget.style.SetColor and type(color) == "table" then
        widget.style:SetColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
end

function U.AddBg(parent, r, g, b, a)
    local bg = parent:CreateColorDrawable(r, g, b, a, "background")
    bg:AddAnchor("TOPLEFT", parent, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", parent, 0, 0)
    bg:Show(true)
    return bg
end

function U.Label(parent, id, text, x, y, w, h, size, color, align)
    local l = api.Interface:CreateWidget("label", id, parent)
    l:SetExtent(w, h)
    l:AddAnchor("TOPLEFT", parent, x, y)
    l.style:SetFontSize(size or 12)
    l.style:SetAlign(align or ALIGN.LEFT)
    if l.style.SetShadow then l.style:SetShadow(false) end
    if l.style.SetOutline then l.style:SetOutline(false) end
    U.SetTextColor(l, color or {1, 1, 1, 1})
    l:SetText(text or "")
    l:Show(true)
    return l
end

function U.ChildLabel(parent, id, text, x, y, w, h, size, color, align)
    local widget = parent:CreateChildWidget("label", id, 0, true)
    widget:SetExtent(w, h)
    widget:AddAnchor("TOPLEFT", parent, x, y)
    widget.style:SetFontSize(size or 11)
    widget.style:SetAlign(align or ALIGN.LEFT)
    U.SetTextColor(widget, color or {1, 1, 1, 1})
    widget:SetText(text or "")
    widget:Show(true)
    return widget
end

function U.FlatButton(parent, id, text, x, y, w, h, tone, onClick)
    local btnTone = tone or C.button or {0.14, 0.14, 0.16, 0.95}
    local white = C.white or {1, 1, 1, 1}
    local btn = api.Interface:CreateWidget("button", id, parent)
    btn:SetExtent(w, h)
    btn:AddAnchor("TOPLEFT", parent, x, y)
    btn:SetText("")
    local border = btn:CreateColorDrawable(0, 0, 0, 0.92, "background")
    border:AddAnchor("TOPLEFT", btn, 0, 0)
    border:AddAnchor("BOTTOMRIGHT", btn, 0, 0)
    border:Show(true)
    local fill = btn:CreateColorDrawable(btnTone[1], btnTone[2], btnTone[3], btnTone[4], "background")
    local bp = Px(1)
    fill:AddAnchor("TOPLEFT", btn, bp, bp)
    fill:AddAnchor("BOTTOMRIGHT", btn, -bp, -bp)
    fill:Show(true)
    local txt = U.Label(btn, id .. "_txt", text, 1, 2, w - 2, h - 4, 11, white, ALIGN.CENTER)
    txt:Clickable(false)
    btn._fill = fill
    btn._text = txt
    function btn:SetCleanText(value) self._text:SetText(value or "") end
    function btn:SetTone(color) self._fill:SetColor(color[1], color[2], color[3], color[4]) end
    if onClick then btn:SetHandler("OnClick", onClick) end
    btn:Show(true)
    return btn
end

function U.ChildFlatButton(parent, id, text, x, y, w, h, tone, onClick, align)
    local btnTone = tone or C.button or {0.14, 0.14, 0.16, 0.95}
    local white = C.white or {1, 1, 1, 1}
    local button = parent:CreateChildWidget("button", id, 0, true)
    button:SetExtent(w, h)
    button:AddAnchor("TOPLEFT", parent, x, y)
    button:SetText("")
    local border = button:CreateColorDrawable(0, 0, 0, 0.92, "background")
    border:AddAnchor("TOPLEFT", button, 0, 0)
    border:AddAnchor("BOTTOMRIGHT", button, 0, 0)
    border:Show(true)
    local fill = button:CreateColorDrawable(btnTone[1], btnTone[2], btnTone[3], btnTone[4], "background")
    local bp = Px(1)
    fill:AddAnchor("TOPLEFT", button, bp, bp)
    fill:AddAnchor("BOTTOMRIGHT", button, -bp, -bp)
    fill:Show(true)
    local textLabel = U.ChildLabel(button, id .. "_text", text, 4, 2, w - 8, h - 4, 11, white, align or ALIGN.LEFT)
    textLabel:Clickable(false)
    button.cleanFill = fill
    button.cleanLabel = textLabel
    function button:SetCleanText(value) self.cleanLabel:SetText(value or "") end
    function button:SetTone(value) self.cleanFill:SetColor(value[1], value[2], value[3], value[4]) end
    if onClick then button:SetHandler("OnClick", onClick) end
    pcall(function() button:RegisterForClicks("LeftButton") end)
    button:Show(true)
    return button
end

function U.Panel(parent, id, x, y, w, h)
    local p = parent:CreateChildWidget("emptywidget", id, 0, true)
    p:SetExtent(w, h)
    p:AddAnchor("TOPLEFT", parent, x, y)
    U.AddBg(p, C.panel[1], C.panel[2], C.panel[3], C.panel[4])
    p:Show(true)
    return p
end

function U.SetToggle(btn, enabled, text)
    if not btn then return end
    btn:SetCleanText((text or "") .. (enabled and " ON" or " OFF"))
    btn:SetTone(enabled and (C.active or {0.12, 0.28, 0.15, 0.95}) or (C.button or {0.14, 0.14, 0.16, 0.95}))
end

function U.ColorCube(parent, id, x, y, key, onClick, size)
    size = size or 20
    local inset = math.max(3, math.floor(size * 0.15))
    local btn = api.Interface:CreateWidget("button", id, parent)
    btn:SetExtent(size, size)
    btn:AddAnchor("TOPLEFT", parent, x, y)
    btn:SetText("")
    local border = btn:CreateColorDrawable(0, 0, 0, 0.96, "background")
    border:AddAnchor("TOPLEFT", btn, 0, 0)
    border:AddAnchor("BOTTOMRIGHT", btn, 0, 0)
    border:Show(true)
    local fill = btn:CreateColorDrawable(1, 1, 1, 1, "background")
    fill:AddAnchor("TOPLEFT", btn, inset, inset)
    fill:AddAnchor("BOTTOMRIGHT", btn, -inset, -inset)
    fill:Show(true)
    btn._fill = fill
    btn._colorKey = key
    if onClick then btn:SetHandler("OnClick", onClick) end
    btn:Show(true)
    return btn
end

-- Local section panel with accent stripe
local function createSectionPanel(parent, id, x, y, w, h, titleText)
    local p = U.Panel(parent, id, x, y, w, h)
    local header = p:CreateColorDrawable(0.09, 0.09, 0.11, 0.95, "background")
    header:SetExtent(w, 24)
    header:AddAnchor("TOPLEFT", p, 0, 0)
    header:Show(true)
    local accent = p:CreateColorDrawable(C.accent[1], C.accent[2], C.accent[3], 0.85, "background")
    accent:SetExtent(4, 24)
    accent:AddAnchor("TOPLEFT", p, 0, 0)
    accent:Show(true)
    U.Label(p, id .. "_title", titleText or "", 14, 4, w - 28, 16, 12, C.gold, ALIGN.LEFT)
    return p
end

-- Colors matching power_ranger_on palette
C = {
    dark    = {0.06, 0.06, 0.068, 0.96},
    header  = {0.09, 0.09, 0.11, 0.98},
    gold    = {1, 0.84, 0, 1},            -- Gold text
    accent  = {0, 0.75, 0.75, 1},    -- Cyan accent stripe
    white   = {1, 1, 1, 1},
    muted   = {0.5, 0.5, 0.5, 1},
    active  = {0.12, 0.28, 0.15, 0.95},
    button  = {0.14, 0.14, 0.16, 0.95},
    blue    = {0.16, 0.21, 0.30, 0.96},
    panel   = {0.045, 0.045, 0.052, 0.84},
}

-- =============================================
-- HSV <-> RGB (color wheel math)
-- =============================================
local function hsvToRgb(h, s, v) -- h 0..360, s/v 0..1 -> r,g,b 0..255
    local c = v * s
    local hp = (h % 360) / 60
    local x = c * (1 - math.abs(hp % 2 - 1))
    local r, g, b = 0, 0, 0
    if hp < 1 then r, g, b = c, x, 0
    elseif hp < 2 then r, g, b = x, c, 0
    elseif hp < 3 then r, g, b = 0, c, x
    elseif hp < 4 then r, g, b = 0, x, c
    elseif hp < 5 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    local m = v - c
    return math.floor((r + m) * 255 + 0.5),
           math.floor((g + m) * 255 + 0.5),
           math.floor((b + m) * 255 + 0.5)
end

local function rgbToHsv(r, g, b) -- 0..255 -> h 0..360, s 0..1, v 0..1
    r, g, b = r / 255, g / 255, b / 255
    local maxc = math.max(r, g, b)
    local minc = math.min(r, g, b)
    local d = maxc - minc
    local h = 0
    if d > 0 then
        if maxc == r then h = ((g - b) / d) % 6
        elseif maxc == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h * 60
    end
    local s = maxc == 0 and 0 or d / maxc
    return h, s, maxc
end

-- =============================================
-- TTP-style flat slider and check factories
-- =============================================
-- Shared row layout, sized to fit both the 408-wide section panels and the
-- 360-wide color popup: label 14..94, "-" 98, track 120..270, "+" 274,
-- value label 296..346.
local SLIDER_TRACK_W, SLIDER_TRACK_H = 150, 16

function U.SliderRow(panel, id, labelText, y, minV, maxV, value, onChanged, displayFn)
    displayFn = displayFn or tostring
    local cur = math.max(minV, math.min(maxV, value))
    U.ChildLabel(panel, id .. "_lbl", labelText, 14, y + 2, 82, 16, 13, C.gold, ALIGN.LEFT)
    local valLbl = U.ChildLabel(panel, id .. "_val", displayFn(cur), 296, y + 2, 50, 16, 13, C.white, ALIGN.CENTER)

    local track = panel:CreateChildWidget("button", id .. "_track", 0, true)
    track:SetExtent(SLIDER_TRACK_W, SLIDER_TRACK_H)
    track:AddAnchor("TOPLEFT", panel, 120, y)
    track:SetText("")
    local trackBorder = track:CreateColorDrawable(0, 0, 0, 0.92, "background")
    trackBorder:AddAnchor("TOPLEFT", track, 0, 0)
    trackBorder:AddAnchor("BOTTOMRIGHT", track, 0, 0)
    local trackBg = track:CreateColorDrawable(0.10, 0.10, 0.12, 0.95, "background")
    local bp = Px(1)
    trackBg:AddAnchor("TOPLEFT", track, bp, bp)
    trackBg:AddAnchor("BOTTOMRIGHT", track, -bp, -bp)
    local fill = track:CreateColorDrawable(0, 0.55, 0.55, 0.9, "background")
    fill:AddAnchor("TOPLEFT", track, bp, bp)

    local function refreshFill()
        local frac = (cur - minV) / (maxV - minV)
        -- The track's border is bp thick on each side, so the fill area is the
        -- track less 2*bp - not less 2, which over-filled by a fraction of a
        -- pixel at either end whenever the scale was not 1.
        local w = math.floor(frac * (SLIDER_TRACK_W - 2 * bp) + 0.5)
        if w < 1 then
            fill:SetVisible(false)
        else
            fill:SetVisible(true)
            fill:SetExtent(w, SLIDER_TRACK_H - 2 * bp)
        end
    end
    refreshFill()

    local function apply(nv, silent)
        if nv < minV then nv = minV end
        if nv > maxV then nv = maxV end
        if nv == cur then return end
        cur = nv
        valLbl:SetText(displayFn(cur))
        refreshFill()
        if not silent then onChanged(cur) end
    end

    track:SetHandler("OnWheelUp", function() apply(cur + 1) end)
    track:SetHandler("OnWheelDown", function() apply(cur - 1) end)
    U.ChildFlatButton(panel, id .. "_dec", "-", 98, y, 18, SLIDER_TRACK_H, C.button,
        function() apply(cur - 1) end, ALIGN.CENTER)
    U.ChildFlatButton(panel, id .. "_inc", "+", 274, y, 18, SLIDER_TRACK_H, C.button,
        function() apply(cur + 1) end, ALIGN.CENTER)

    return {
        SetValue = function(v) apply(v, true) end,
        GetValue = function() return cur end,
    }
end

-- Flat check: gold label left, 14px box right whose fill carries the state
-- (cyan = on). Same control TTP uses, so the two addons read as one family.
function U.FlatCheck(panel, id, labelText, x, y, w, isOn, onToggle)
    local btn = panel:CreateChildWidget("button", id, 0, true)
    btn:SetExtent(w, 20)
    btn:AddAnchor("TOPLEFT", panel, x, y)
    btn:SetText("")
    -- The ring is the 14 box minus the 12 fill, i.e. 1 unit on each side. That
    -- has to be 1 DEVICE pixel per side or the check reads with a doubled edge
    -- at some scales, so the fill is sized off the box rather than hardcoded.
    local bp = Px(1)
    local border = btn:CreateColorDrawable(0, 0, 0, 0.92, "overlay")
    border:SetExtent(14, 14)
    border:AddAnchor("RIGHT", btn, 0, 0)
    local fill = btn:CreateColorDrawable(0.14, 0.14, 0.16, 1, "overlay")
    fill:SetExtent(14 - 2 * bp, 14 - 2 * bp)
    fill:AddAnchor("RIGHT", btn, -bp, 0)
    local lbl = U.ChildLabel(btn, id .. "_lbl", labelText, 0, 2, w - 22, 16, 13, C.gold, ALIGN.LEFT)
    lbl:Clickable(false)
    local function refresh()
        if isOn() then
            fill:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
        else
            fill:SetColor(0.14, 0.14, 0.16, 1)
        end
    end
    btn:SetHandler("OnClick", function() onToggle(); refresh() end)
    refresh()
    return { btn = btn, Refresh = refresh }
end

-- =============================================
-- LIVE PREVIEW BARS (built inside the COLORS panel)
-- =============================================
local BB_TEX_DIR = "../Addon/BetterBars/textures/"
-- Mirrors BAR_BG_OUTSET in main.lua: the fill spans the whole bar and the
-- backdrop cell is drawn this far outside it, so the border ring sits around
-- the fill rather than under it.
local PREV_BG_OUTSET = 2
-- Mirrors MP_BAR_GAP in main.lua (which is tied to BAR_BG_OUTSET there)
local PREV_MP_GAP = PREV_BG_OUTSET
local previewRefs = nil

-- Mock values the preview renders with
local PREVIEW_HP, PREVIEW_HP_PCT = 14580, 70
local PREVIEW_MP, PREVIEW_MP_PCT = 9999, 70

local function buildPreviewBar(panel, idSuffix, x, y, w, h, texName, texW, texH)
    local bar = panel:CreateChildWidget("emptywidget", "bbPrev" .. idSuffix, 0, true)
    bar:SetExtent(w, h)
    bar:AddAnchor("TOPLEFT", panel, x, y)

    -- Backdrop: the extracted ninepart cell, flat fallback (same pair of
    -- paths ApplyBarBackdrop takes in main.lua). Kept on the returned refs so
    -- updatePreview can apply the Background opacity setting to it.
    local nineD, flatD
    local okNine = pcall(function()
        local d = bar:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        pcall(function() d:SetSRGB(false) end)
        local loaded = d:SetTgaTexture(BB_TEX_DIR .. "bar_frame.png")
        if loaded == false then BBFail() end
        d:SetCoords(0, 0, 17, 17)
        d:SetInset(8, 8, 8, 8)
        d:AddAnchor("TOPLEFT", bar, -Px(PREV_BG_OUTSET), -Px(PREV_BG_OUTSET))
        d:AddAnchor("BOTTOMRIGHT", bar, Px(PREV_BG_OUTSET), Px(PREV_BG_OUTSET))
        nineD = d
    end)
    if not okNine then
        flatD = bar:CreateColorDrawable(0, 0, 0, 0.55, "background")
        flatD:AddAnchor("TOPLEFT", bar, -Px(PREV_BG_OUTSET), -Px(PREV_BG_OUTSET))
        flatD:AddAnchor("BOTTOMRIGHT", bar, Px(PREV_BG_OUTSET), Px(PREV_BG_OUTSET))
    end

    -- Trail behind, fill on top (later-created drawables render above).
    -- Both start flush at the bar's own top-left: the fill fills the bar.
    local trail = bar:CreateColorDrawable(0.1, 0.1, 0.1, 1, "background")
    trail:AddAnchor("TOPLEFT", bar, 0, 0)
    local fillFlat = bar:CreateColorDrawable(0.5, 0.5, 0.5, 1, "background")
    fillFlat:AddAnchor("TOPLEFT", bar, 0, 0)
    local fillTex
    pcall(function()
        fillTex = bar:CreateImageDrawable("Textures/Defaults/White.dds", "background")
        pcall(function() fillTex:SetSRGB(false) end)
        local loaded = fillTex:SetTgaTexture(BB_TEX_DIR .. texName .. ".png")
        if loaded == false then BBFail() end
        fillTex:SetCoords(0, 0, texW, texH)
        fillTex:AddAnchor("TOPLEFT", bar, 0, 0)
    end)
    local lbl = U.ChildLabel(bar, "bbPrev" .. idSuffix .. "_lbl", "", 0, 0, w, 14, 11, C.white, ALIGN.CENTER)
    lbl:RemoveAllAnchors()
    lbl:AddAnchor("CENTER", bar, 0, 0)
    return { bar = bar, trail = trail, fillFlat = fillFlat, fillTex = fillTex,
             nine = nineD, flatBg = flatD, lbl = lbl, w = w, h = h }
end

local function previewLabelText(fmt, cur, pct)
    if fmt == "hide" then return "" end
    if fmt == "current" then return tostring(cur) end
    if fmt == "percent" then return pct .. "%" end
    return string.format("%d (%d%%)", cur, pct)
end

local function updatePreview()
    if not previewRefs then return end
    local ok, err = pcall(function()
        local s2 = settings.getSettings()
        local useTex = (s2.barTexture or "none") ~= "none"
        local fmt = s2.labelFormat or "both"
        local fontSize = s2.labelFontSize or 11
        local hpH = (s2.barHeight and s2.barHeight.hp) or 17
        local mpH = (s2.barHeight and s2.barHeight.mp) or 13
        -- Mirrors MP_BAR_GAP in main.lua: the MP bar is seated this far below
        -- the HP bar so the two outset backdrops meet on adjacent border rows.
        local gap = Px(PREV_MP_GAP)
        -- While the popup edits the enemy colour, the HP preview wears it so
        -- the change is visible live.
        local hpKey = (colorPopup and colorPopup:IsVisible() and colorPopupTarget == "ehp")
            and "ehp" or "hp"

        -- Re-apply geometry. The height setting IS the bar height now, exactly
        -- as ApplyBarBox applies it - no inset to add back.
        local hpBox = hpH
        local mpBox = mpH
        previewRefs.hp.h = hpBox
        previewRefs.mp.h = mpBox
        previewRefs.hp.bar:SetExtent(previewRefs.hp.w, hpBox)
        previewRefs.mp.bar:SetExtent(previewRefs.mp.w, mpBox)
        previewRefs.mp.bar:RemoveAllAnchors()
        previewRefs.mp.bar:AddAnchor("TOPLEFT", previewRefs.panel,
            previewRefs.x, previewRefs.y + hpBox + gap)

        -- Mock level digit: current font pick, centered on the bar stack
        if previewRefs.levelLbl then
            local lbl = previewRefs.levelLbl
            pcall(function()
                lbl.style:SetFont(s2.levelFont or "ui/font/yd_ygo540.ttf", 22)
            end)
            pcall(function()
                lbl:RemoveAllAnchors()
                lbl:AddAnchor("TOPLEFT", previewRefs.panel, 4,
                    previewRefs.y + math.floor((hpBox + gap + mpBox) / 2) - 13)
            end)
        end

        -- Background slider: same application as ApplyBarBackdrop - 1.0 is
        -- the reference cell at its own alphas, the setting scales from there.
        local bgK = s2.backgroundOpacity or 1

        local function paint(refs, cv, pctFill, labelText)
            if not refs or not cv then return end
            local r, g, b = cv.r / 255, cv.g / 255, cv.b / 255
            if refs.nine then
                refs.nine:SetColor(1, 1, 1, math.min(1, bgK))
            elseif refs.flatBg then
                refs.flatBg:SetColor(0, 0, 0, 0.55 * bgK)
            end
            -- The fill spans the whole bar; the backdrop is outset around it.
            local fh = refs.h
            local innerW = refs.w
            local fw = math.floor(innerW * pctFill / 100 + 0.5)
            -- damage trail: 15% of the bar behind the fill edge, at the same
            -- 0.43 luminance main.lua paints real trails with
            local tw = math.floor(innerW * 0.15 + 0.5)
            if fw + tw > innerW then tw = innerW - fw end
            refs.trail:RemoveAllAnchors()
            refs.trail:AddAnchor("TOPLEFT", refs.bar, fw, 0)
            refs.trail:SetExtent(tw, fh)
            refs.trail:SetColor(r * 0.43, g * 0.43, b * 0.43, 1)
            refs.trail:SetVisible(tw > 0)
            if useTex and refs.fillTex then
                refs.fillTex:SetExtent(fw, fh)
                refs.fillTex:SetColor(r, g, b, 1)
                refs.fillTex:SetVisible(true)
                refs.fillFlat:SetVisible(false)
            else
                refs.fillFlat:SetExtent(fw, fh)
                refs.fillFlat:SetColor(r, g, b, 1)
                refs.fillFlat:SetVisible(true)
                if refs.fillTex then refs.fillTex:SetVisible(false) end
            end
            refs.lbl.style:SetFontSize(fontSize)
            refs.lbl:SetText(labelText)
        end

        paint(previewRefs.hp, colorValues[hpKey], PREVIEW_HP_PCT,
            previewLabelText(fmt, PREVIEW_HP, PREVIEW_HP_PCT))
        paint(previewRefs.mp, colorValues.mp, PREVIEW_MP_PCT,
            previewLabelText(fmt, PREVIEW_MP, PREVIEW_MP_PCT))
    end)
    if not ok then api.Log:Err("BetterBars preview: " .. tostring(err)) end
end

-- Push a colour change everywhere at once: saved settings + live bars (via
-- BETTERBARS_SETTINGS_UPDATED), the section's colour cube, and the preview.
local function applyLiveColor(key)
    saveColorToGame(key)
    local cv = colorValues[key]
    if cv and wndColorCubes and wndColorCubes[key] and wndColorCubes[key]._fill then
        wndColorCubes[key]._fill:SetColor(cv.r / 255, cv.g / 255, cv.b / 255, cv.a or 1)
    end
    updatePreview()
end

-- =============================================
-- COLOR POPUP — wheel + brightness + RGB + presets
-- =============================================
local popupRGBInputs = {}
local WHEEL_SIZE = 200
local popupState = { h = 0, s = 0, v = 1 }
local popupSwatch = nil
local popupValSlider = nil
local popupTitleLbl = nil

local function popupSyncInputs()
    local key = colorPopupTarget
    local cv = key and colorValues[key]
    if not cv then return end
    if popupSwatch then popupSwatch:SetColor(cv.r / 255, cv.g / 255, cv.b / 255, 1) end
    if popupRGBInputs.r then
        popupRGBInputs.r:SetText(tostring(cv.r))
        popupRGBInputs.g:SetText(tostring(cv.g))
        popupRGBInputs.b:SetText(tostring(cv.b))
    end
end

local function popupApplyHSV()
    local key = colorPopupTarget
    if not key then return end
    local r, g, b = hsvToRgb(popupState.h, popupState.s, popupState.v)
    local a = colorValues[key] and colorValues[key].a or 1
    colorValues[key] = { r = r, g = g, b = b, a = a }
    popupSyncInputs()
    applyLiveColor(key)
end

local function popupSetRGB(r, g, b)
    local key = colorPopupTarget
    if not key then return end
    local a = colorValues[key] and colorValues[key].a or 1
    colorValues[key] = { r = r, g = g, b = b, a = a }
    popupState.h, popupState.s, popupState.v = rgbToHsv(r, g, b)
    if popupValSlider then popupValSlider.SetValue(math.floor(popupState.v * 100 + 0.5)) end
    popupSyncInputs()
    applyLiveColor(key)
end

local function buildColorPopup()
    if colorPopup then return end

    local W, H = 360, 442
    colorPopup = api.Interface:CreateEmptyWindow("BetterBarsColorPopup", "UIParent")
    colorPopup:SetExtent(W, H)
    U.AddBg(colorPopup, 0, 0, 0, 0.96)

    local body = colorPopup:CreateColorDrawable(C.dark[1], C.dark[2], C.dark[3], C.dark[4], "background")
    body:AddAnchor("TOPLEFT", colorPopup, Px(1), Px(1))
    body:AddAnchor("BOTTOMRIGHT", colorPopup, -Px(1), -Px(1))
    local header = colorPopup:CreateColorDrawable(C.header[1], C.header[2], C.header[3], C.header[4], "background")
    header:SetExtent(W - 2 * Px(1), 30)
    header:AddAnchor("TOPLEFT", colorPopup, Px(1), Px(1))
    local accent = colorPopup:CreateColorDrawable(C.accent[1], C.accent[2], C.accent[3], 0.85, "background")
    accent:SetExtent(4, 30)
    accent:AddAnchor("TOPLEFT", colorPopup, Px(1), Px(1))
    popupTitleLbl = U.Label(colorPopup, "bbPopupTitle", "COLOR", 16, 7, 200, 16, 13, C.gold, ALIGN.LEFT)

    U.FlatButton(colorPopup, "bbPopupClose", "X", W - 32, 5, 22, 22, C.button, function()
        hideColorPopup()
        updatePreview()
    end)

    -- The wheel: one image drawable on a button; clicks map back to hue and
    -- saturation through the mouse position. GetEffectiveOffset gives the
    -- widget's absolute origin in UI units; GetMousePos is raw pixels, so it
    -- is divided by the UI scale first.
    local wheelBtn = colorPopup:CreateChildWidget("button", "bbWheel", 0, true)
    wheelBtn:SetExtent(WHEEL_SIZE, WHEEL_SIZE)
    wheelBtn:AddAnchor("TOPLEFT", colorPopup, 80, 44)
    wheelBtn:SetText("")
    local wheelOk = pcall(function()
        local d = wheelBtn:CreateImageDrawable("Textures/Defaults/White.dds", "background")
        pcall(function() d:SetSRGB(false) end)
        local loaded = d:SetTgaTexture(BB_TEX_DIR .. "colorwheel.png")
        if loaded == false then BBFail() end
        d:SetCoords(0, 0, WHEEL_SIZE, WHEEL_SIZE)
        d:AddAnchor("TOPLEFT", wheelBtn, 0, 0)
        d:AddAnchor("BOTTOMRIGHT", wheelBtn, 0, 0)
    end)
    if not wheelOk then
        api.Log:Err("BetterBars: colorwheel.png missing - wheel disabled, presets still work")
    end
    -- Hit-test entirely in DEVICE pixels.
    --
    -- This used to divide the mouse position by the UI scale and then compare it
    -- against GetEffectiveOffset and a radius derived from WHEEL_SIZE - three
    -- different coordinate spaces in five lines. At 100% they all coincide, so
    -- it worked; at any other scale the mouse was shrunk while the widget offset
    -- was not, dist came out far too large, and "if dist > R then return"
    -- silently swallowed the click. The wheel looked dead while the presets, RGB
    -- entry and Default button carried on working.
    --
    -- The client's own spectrum picker settles the units
    -- (x2ui/customizing_new/components.lua:300-308): it compares GetMousePos
    -- against GetEffectiveOffset and GetEffectiveExtent with no scale division
    -- anywhere. "Effective" means after scaling - the same space the mouse is
    -- reported in. So: take the radius from the widget's effective extent rather
    -- than from the design constant, and convert nothing.
    wheelBtn:SetHandler("OnClick", function(self)
        local ok = pcall(function()
            local mx, my = api.Input:GetMousePos()
            local wx, wy = self:GetEffectiveOffset()
            -- GetEffectiveExtent is what the client uses, but it is not
            -- guaranteed on an addon widget; the design size scaled up is the
            -- same number when it is missing.
            local ew, eh
            pcall(function() ew, eh = self:GetEffectiveExtent() end)
            if type(ew) ~= "number" or ew <= 0 then
                ew = WHEEL_SIZE * UIScale()
                eh = ew
            end
            if type(eh) ~= "number" or eh <= 0 then eh = ew end
            local rx, ry = ew / 2, eh / 2
            local dx = (mx - wx) - rx
            local dy = (my - wy) - ry
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > rx then return end
            popupState.h = math.deg(math.atan2(dy, dx)) % 360
            -- 2px short of the edge so the rim still reaches full saturation
            popupState.s = math.min(1, dist / (rx - 2))
            popupApplyHSV()
        end)
        if not ok then
            api.Log:Err("BetterBars: wheel click could not resolve mouse position")
        end
    end)

    -- Current colour swatch beside the wheel
    local swatchBorder = colorPopup:CreateColorDrawable(0, 0, 0, 0.96, "background")
    swatchBorder:SetExtent(30, 30)
    swatchBorder:AddAnchor("TOPLEFT", colorPopup, 24, 44)
    popupSwatch = colorPopup:CreateColorDrawable(1, 1, 1, 1, "background")
    popupSwatch:SetExtent(28, 28)
    popupSwatch:AddAnchor("TOPLEFT", colorPopup, 25, 45)
    U.Label(colorPopup, "bbSwatchLbl", "Now", 24, 78, 32, 12, 11, C.muted, ALIGN.CENTER)

    -- Brightness: the wheel is drawn at full value; this darkens the pick
    popupValSlider = U.SliderRow(colorPopup, "bbPopupVal", "Bright", 258, 0, 100, 100, function(v)
        popupState.v = v / 100
        popupApplyHSV()
    end)

    -- RGB inputs + Set
    local function rgbInput(id, x)
        local inputBG = colorPopup:CreateColorDrawable(0.1, 0.1, 0.12, 0.9, "background")
        inputBG:SetExtent(44, 20)
        inputBG:AddAnchor("TOPLEFT", colorPopup, x, 288)
        local input = W_CTRL.CreateEdit("bbPopup" .. id, colorPopup)
        input:SetExtent(40, 18)
        input:AddAnchor("TOPLEFT", colorPopup, x + 2, 289)
        input:SetMaxTextLength(3)
        input.style:SetAlign(ALIGN.CENTER)
        input.style:SetColor(1, 1, 1, 1)
        return input
    end
    U.Label(colorPopup, "bbPopupRLbl", "R", 24, 290, 12, 14, 12, {1, 0.45, 0.45, 1}, ALIGN.LEFT)
    popupRGBInputs.r = rgbInput("R", 38)
    U.Label(colorPopup, "bbPopupGLbl", "G", 96, 290, 12, 14, 12, {0.45, 1, 0.45, 1}, ALIGN.LEFT)
    popupRGBInputs.g = rgbInput("G", 110)
    U.Label(colorPopup, "bbPopupBLbl", "B", 168, 290, 12, 14, 12, {0.5, 0.6, 1, 1}, ALIGN.LEFT)
    popupRGBInputs.b = rgbInput("B", 182)
    U.FlatButton(colorPopup, "bbPopupSet", "Set", 244, 287, 52, 22, C.blue, function()
        local function readInput(w)
            local n = tonumber(w:GetText()) or 0
            if n < 0 then n = 0 end
            if n > 255 then n = 255 end
            return math.floor(n)
        end
        popupSetRGB(readInput(popupRGBInputs.r), readInput(popupRGBInputs.g), readInput(popupRGBInputs.b))
    end)

    -- Preset swatches: 2 rows of 10
    local cell, gap = 18, 2
    local gridX = math.floor((W - (10 * cell + 9 * gap)) / 2)
    for i, colorData in ipairs(colorPalette) do
        local row = math.floor((i - 1) / 10)
        local col = (i - 1) % 10
        local square = colorPopup:CreateChildWidget("button", "bbPreset" .. i, 0, true)
        square:SetExtent(cell, cell)
        square:AddAnchor("TOPLEFT", colorPopup,
            gridX + col * (cell + gap), 322 + row * (cell + gap))
        square:SetText("")
        local sqBorder = square:CreateColorDrawable(0, 0, 0, 0.9, "background")
        sqBorder:AddAnchor("TOPLEFT", square, 0, 0)
        sqBorder:AddAnchor("BOTTOMRIGHT", square, 0, 0)
        local sqFill = square:CreateColorDrawable(
            colorData.r / 255, colorData.g / 255, colorData.b / 255, 1, "background")
        sqFill:AddAnchor("TOPLEFT", square, Px(1), Px(1))
        sqFill:AddAnchor("BOTTOMRIGHT", square, -Px(1), -Px(1))
        square:SetHandler("OnClick", function()
            popupSetRGB(colorData.r, colorData.g, colorData.b)
        end)
    end

    -- Default for the colour being edited, and Close
    U.FlatButton(colorPopup, "bbPopupDefault", "Default", 52, 372, 120, 26, C.button, function()
        local key = colorPopupTarget
        local d = key and default_settings.colors[key]
        if d then popupSetRGB(d.r, d.g, d.b) end
    end)
    U.FlatButton(colorPopup, "bbPopupCloseBtn", "Close", 188, 372, 120, 26, C.blue, function()
        hideColorPopup()
        updatePreview()
    end)

    colorPopup:EnableDrag(true)
    colorPopup:SetHandler("OnDragStart", function(self)
        self:StartMoving()
        api.Cursor:ClearCursor()
        api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
    end)
    colorPopup:SetHandler("OnDragStop", function(self)
        self:StopMovingOrSizing()
        api.Cursor:ClearCursor()
    end)
    colorPopup:Show(false)
end

-- =============================================
-- FONT POPUP — level number font picker
-- =============================================
-- Every client font; each row renders IN its font, so the list previews
-- itself. CJK-focused families at the bottom may lack pretty latin digits.
local FONT_CHOICES = {
    { path = "ui/font/yd_ygo540.ttf",                  label = "Default UI" },
    { path = "ui/font/sd_leeyagil.ttf",                label = "Leeyagi (vanilla)" },
    { path = "ui/font/frizquadratac.ttf",              label = "Friz Quadrata" },
    { path = "ui/font/frizquadratactt-mod.ttf",        label = "Friz Quadrata TT" },
    { path = "ui/font/frizqtcyr.ttf",                  label = "Friz Quadrata Cyr" },
    { path = "ui/font/librebaskerville-bold.ttf",      label = "Libre Baskerville" },
    { path = "ui/font/flareserif_821_roman.ttf",       label = "Flareserif 821" },
    { path = "ui/font/nanumgothicbold.ttf",            label = "Nanum Gothic Bold" },
    { path = "ui/font/yoon_firedgothic_b.ttf",         label = "Fired Gothic" },
    { path = "ui/font/yoon_snail_b.ttf",               label = "Snail Bold" },
    { path = "ui/font/pgm-mod.ttf",                    label = "PGM" },
    { path = "ui/font/archeage_mail.ru_pgm-mod.ttf",   label = "PGM (Mail.ru)" },
    { path = "ui/font/archeage_mail.ru_snail-mod.ttf", label = "Snail (Mail.ru)" },
    { path = "ui/font/dfheistd-w5_1.ttf",              label = "DFHei W5" },
    { path = "ui/font/dfheistd-w9_1.ttf",              label = "DFHei W9" },
    { path = "ui/font/migmix-2p-regular.ttf",          label = "MigMix 2P" },
    { path = "ui/font/fzlantinghei_r_gbk.ttf",         label = "FZ LantingHei" },
    { path = "ui/font/fzlbk.ttf",                      label = "FZ LiBian" },
}

local fontPopup = nil
local fontRowRefs = {}

local function hideFontPopup()
    if fontPopup then fontPopup:Show(false) end
end

local function refreshFontRows()
    local cur = settings.getSettings().levelFont or "ui/font/yd_ygo540.ttf"
    for _, row in ipairs(fontRowRefs) do
        row.btn:SetTone(row.path == cur and C.active or C.button)
    end
end

local function buildFontPopup()
    if fontPopup then return end
    local ROW_H, ROW_GAP = 22, 2
    local W = 240
    local H = 40 + #FONT_CHOICES * (ROW_H + ROW_GAP) + 10

    fontPopup = api.Interface:CreateEmptyWindow("BetterBarsFontPopup", "UIParent")
    fontPopup:SetExtent(W, H)
    U.AddBg(fontPopup, 0, 0, 0, 0.96)
    local body = fontPopup:CreateColorDrawable(C.dark[1], C.dark[2], C.dark[3], C.dark[4], "background")
    body:AddAnchor("TOPLEFT", fontPopup, Px(1), Px(1))
    body:AddAnchor("BOTTOMRIGHT", fontPopup, -Px(1), -Px(1))
    local header = fontPopup:CreateColorDrawable(C.header[1], C.header[2], C.header[3], C.header[4], "background")
    header:SetExtent(W - 2 * Px(1), 30)
    header:AddAnchor("TOPLEFT", fontPopup, Px(1), Px(1))
    local accent = fontPopup:CreateColorDrawable(C.accent[1], C.accent[2], C.accent[3], 0.85, "background")
    accent:SetExtent(4, 30)
    accent:AddAnchor("TOPLEFT", fontPopup, Px(1), Px(1))
    U.Label(fontPopup, "bbFontTitle", "LEVEL FONT", 16, 7, 160, 16, 13, C.gold, ALIGN.LEFT)
    U.FlatButton(fontPopup, "bbFontClose", "X", W - 32, 5, 22, 22, C.button, hideFontPopup)

    for i, choice in ipairs(FONT_CHOICES) do
        local y = 38 + (i - 1) * (ROW_H + ROW_GAP)
        local btn = U.FlatButton(fontPopup, "bbFontRow" .. i, choice.label,
            10, y, W - 20, ROW_H, C.button, function()
                settings.updateSetting("levelFont", choice.path)
                settings.saveSettings()
                refreshFontRows()
                updatePreview()
            end)
        -- The row IS the preview: render its label in the font it offers
        pcall(function() btn._text.style:SetFont(choice.path, 13) end)
        table.insert(fontRowRefs, { btn = btn, path = choice.path })
    end

    fontPopup:EnableDrag(true)
    fontPopup:SetHandler("OnDragStart", function(self)
        self:StartMoving()
        api.Cursor:ClearCursor()
        api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
    end)
    fontPopup:SetHandler("OnDragStop", function(self)
        self:StopMovingOrSizing()
        api.Cursor:ClearCursor()
    end)
    fontPopup:Show(false)
end

local function openFontPopup()
    buildFontPopup()
    hideColorPopup()
    refreshFontRows()
    if settingsWindow then
        fontPopup:RemoveAllAnchors()
        fontPopup:AddAnchor("TOPLEFT", settingsWindow, "TOPRIGHT", 5, 0)
    end
    fontPopup:Show(true)
    fontPopup:Raise()
end

local function openColorPopup(key, title)
    buildColorPopup()
    hideFontPopup()
    colorPopupTarget = key
    local cv = colorValues[key] or { r = 255, g = 255, b = 255, a = 1 }
    popupState.h, popupState.s, popupState.v = rgbToHsv(cv.r, cv.g, cv.b)
    if popupValSlider then popupValSlider.SetValue(math.floor(popupState.v * 100 + 0.5)) end
    if popupTitleLbl then popupTitleLbl:SetText("COLOR - " .. title) end
    popupSyncInputs()
    if settingsWindow then
        colorPopup:RemoveAllAnchors()
        colorPopup:AddAnchor("TOPLEFT", settingsWindow, "TOPRIGHT", 5, 0)
    end
    colorPopup:Show(true)
    colorPopup:Raise()
    updatePreview()
end


-- =============================================
-- One-time welcome card
-- =============================================
-- Shown on the first load only. Dismissing it sets infoCardSeen, which persists
-- like any other setting, so it never reappears.
local infoCardWindow

local function showInfoCard()
    if infoCardWindow then
        infoCardWindow:Show(true)
        return
    end

    local width, height = 380, 168
    infoCardWindow = api.Interface:CreateEmptyWindow("BetterBarsInfoCard", "UIParent")
    infoCardWindow:SetExtent(width, height)
    infoCardWindow:AddAnchor("CENTER", "UIParent", 0, -60)
    U.AddBg(infoCardWindow, 0, 0, 0, 0.96)

    local body = infoCardWindow:CreateColorDrawable(C.dark[1], C.dark[2], C.dark[3], C.dark[4], "background")
    body:AddAnchor("TOPLEFT", infoCardWindow, Px(1), Px(1))
    body:AddAnchor("BOTTOMRIGHT", infoCardWindow, -Px(1), -Px(1))
    body:Show(true)

    local header = infoCardWindow:CreateColorDrawable(C.header[1], C.header[2], C.header[3], C.header[4], "background")
    header:SetExtent(width - 2 * Px(1), 30)
    header:AddAnchor("TOPLEFT", infoCardWindow, Px(1), Px(1))
    header:Show(true)

    local accent = infoCardWindow:CreateColorDrawable(C.accent[1], C.accent[2], C.accent[3], C.accent[4], "background")
    accent:SetExtent(4, 30)
    accent:AddAnchor("TOPLEFT", infoCardWindow, Px(1), Px(1))
    accent:Show(true)

    U.Label(infoCardWindow, "bbInfoTitle", "BetterBars", 16, 7, 220, 16, 15, C.gold, ALIGN.LEFT)

    U.Label(infoCardWindow, "bbInfoL1",
        "This addon is completely free.", 20, 46, width - 40, 16, 13, C.white, ALIGN.LEFT)
    U.Label(infoCardWindow, "bbInfoL2",
        "If you find it useful, in-game donations are appreciated", 20, 68, width - 40, 16, 13, C.muted, ALIGN.LEFT)
    U.Label(infoCardWindow, "bbInfoL3",
        "but never expected.", 20, 86, width - 40, 16, 13, C.muted, ALIGN.LEFT)
    U.Label(infoCardWindow, "bbInfoL4",
        "Character:  Dehling", 20, 110, width - 40, 16, 14, C.gold, ALIGN.LEFT)

    U.FlatButton(infoCardWindow, "bbInfoClose", "Got it", width - 116, height - 40, 96, 26, C.blue, function()
        infoCardWindow:Show(false)
    end)

    infoCardWindow:EnableDrag(true)
    infoCardWindow:SetHandler("OnDragStart", function(self) self:StartMoving() end)
    infoCardWindow:SetHandler("OnDragStop", function(self) self:StopMovingOrSizing() end)
    infoCardWindow:Show(true)
end

local function maybeShowInfoCard()
    local s = settings.getSettings()
    if s.infoCardSeen ~= true then
        pcall(showInfoCard)
        -- Marked seen on SHOW, not on the button: dismissing the card any
        -- other way (a reload with it open, dragging it off and forgetting)
        -- used to leave the flag unset, so the card greeted every session.
        -- The ? button reopens it on demand regardless.
        settings.updateSetting("infoCardSeen", true)
        settings.saveSettings()
    end
end

-- Label format cycle order and display names (the button itself lives in the
-- LABELS section below)
local fmtCycle = {"both", "current", "percent", "hide"}
local fmtLabels = {both = "Both", current = "Current", percent = "Percent", hide = "Hide"}

-- Function to initialize settings page — Power Ranger ON style
local function initializeSettingsPage()
    -- If we have a window from this session, show it. Otherwise discard stale orphan.
    if settingsWindow then
        if settingsWindow.bbSession == SESSION then
            settingsWindow:Show(true)
            return
        else
            pcall(function() settingsWindow:Show(false) end)
            settingsWindow = nil
        end
    end
    
    loadColorValues()
    local s = settings.getSettings()
    -- Height is provisional: the real value is computed from the stacked
    -- sections at the bottom of the build (COLORS grows with bar heights)
    local width, height = 420, 598
    
    -- Shell window (no chrome, just dark fill + header)
    settingsWindow = api.Interface:CreateEmptyWindow("BetterBarsSettings", "UIParent")
    settingsWindow.bbSession = SESSION
    settingsWindow:SetExtent(width, height)
    settingsWindow:AddAnchor("TOPLEFT", "UIParent", 300, 100)
    U.AddBg(settingsWindow, 0, 0, 0, 0.96)
    
    local body = settingsWindow:CreateColorDrawable(C.dark[1], C.dark[2], C.dark[3], C.dark[4], "background")
    body:AddAnchor("TOPLEFT", settingsWindow, Px(1), Px(1))
    body:AddAnchor("BOTTOMRIGHT", settingsWindow, -Px(1), -Px(1))
    body:Show(true)
    
    -- Header bar
    local header = settingsWindow:CreateColorDrawable(C.header[1], C.header[2], C.header[3], C.header[4], "background")
    header:SetExtent(width - 2 * Px(1), 34)
    header:AddAnchor("TOPLEFT", settingsWindow, Px(1), Px(1))
    header:Show(true)
    
    -- Title
    local title = U.Label(settingsWindow, "BetterBars_title", "BetterBars", 16, 8, 200, 18, 17, C.gold, ALIGN.LEFT)
    
    -- Header buttons: Reset, help, close. Reset lives up here now - every
    -- control saves live, so the old bottom Save/Reset row is gone.
    --
    -- Reset asks twice: the first click arms it - red, "Are you sure?" - and
    -- only a second click within 5 seconds resets. api:DoIn drives the
    -- expiry; the token guards against a stale timer disarming a fresh arm.
    local resetArmed = false
    local resetArmToken = 0
    local resetBtn
    local RESET_RED = {0.45, 0.10, 0.10, 0.95}
    local function disarmReset()
        resetArmed = false
        if resetBtn then
            resetBtn:SetCleanText("Reset")
            resetBtn:SetTone(C.button)
        end
    end
    resetBtn = U.FlatButton(settingsWindow, "BetterBarsSettings_reset", "Reset",
        width - 160, 7, 92, 22, C.button, function()
            if resetArmed then
                disarmReset()
                resetSettings()
                return
            end
            resetArmed = true
            resetArmToken = resetArmToken + 1
            local token = resetArmToken
            resetBtn:SetCleanText("Are you sure?")
            resetBtn:SetTone(RESET_RED)
            pcall(function()
                api:DoIn(5000, function()
                    if resetArmed and resetArmToken == token then
                        disarmReset()
                    end
                end)
            end)
        end)

    U.FlatButton(settingsWindow, "BetterBarsSettings_help", "?", width - 62, 7, 22, 22, C.button, function()
        showInfoCard()
    end)

    U.FlatButton(settingsWindow, "BetterBarsSettings_close", "X", width - 36, 7, 22, 22, C.button, function()
        settingsWindow:Show(false)
        isSettingsPageOpened = false
        hideColorPopup()
    end)
    
    -- Make draggable (EnableDrag required for CreateEmptyWindow)
    settingsWindow:EnableDrag(true)
    settingsWindow:SetHandler("OnDragStart", function(self)
        self:StartMoving()
        api.Cursor:ClearCursor()
        api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
    end)
    settingsWindow:SetHandler("OnDragStop", function(self)
        self:StopMovingOrSizing()
        api.Cursor:ClearCursor()
    end)
    
    local y = 52

    -- =============================================
    -- SECTION: BARS — geometry sliders + toggles
    -- =============================================
    -- 172 rather than 144: the abyssal size slider sits on its own row below
    -- the toggle row. Everything after this is stacked off y, and the window's
    -- height is computed from y at the end, so the panel simply grows.
    local barP = createSectionPanel(settingsWindow, "barPanel", 18, y, 384, 172, "BARS")
    y = y + 180

    local hpSlider = U.SliderRow(barP, "bbHpH", "HP height", 32, 5, 50,
        (s.barHeight and s.barHeight.hp) or 17, function(v)
            local s2 = settings.getSettings()
            local bh = s2.barHeight or {}
            bh.hp = v
            settings.updateSetting("barHeight", bh)
            settings.saveSettings()
            updatePreview()
        end)
    local mpSlider = U.SliderRow(barP, "bbMpH", "MP height", 58, 5, 50,
        (s.barHeight and s.barHeight.mp) or 13, function(v)
            local s2 = settings.getSettings()
            local bh = s2.barHeight or {}
            bh.mp = v
            settings.updateSetting("barHeight", bh)
            settings.saveSettings()
            updatePreview()
        end)
    local bgSlider = U.SliderRow(barP, "bbBgO", "Background", 84, 0, 11,
        math.floor((s.backgroundOpacity or 1) * 10 + 0.5), function(v)
            settings.updateSetting("backgroundOpacity", v / 10)
            settings.saveSettings()
            updatePreview()
        end, function(v) return string.format("%.1f", v / 10) end)

    -- Bottom row. "Retail fill" replaces the old texture cycle - ON is the
    -- retail sprite, OFF the vanilla flat fill; other texture names still
    -- work if set by hand in settings. There is no bar-gap control: the MP bar
    -- keeps AAC's own anchoring, so showBarSeparation is inert.
    local fillCheck = U.FlatCheck(barP, "bbFillCheck", "Texture", 14, 114, 76,
        function() return (settings.getSettings().barTexture or "none") ~= "none" end,
        function()
            local s2 = settings.getSettings()
            local on = (s2.barTexture or "none") ~= "none"
            settings.updateSetting("barTexture", on and "none" or "bar_retail")
            settings.saveSettings()
            updatePreview()
        end)
    -- Level number font picker
    U.ChildFlatButton(barP, "bbFontBtn", "Font", 152, 112, 96, 22, C.blue,
        openFontPopup, ALIGN.CENTER)
    -- Abyssal charge bar. Restyles the client's bubble action bar in place, so
    -- OFF simply hands its own bubble art back rather than hiding the bar.
    -- Opt-in, so the test is for an explicit true rather than "anything but
    -- false": a settings table read before the merge fills it in carries no
    -- key at all, and the old idiom read that absence as ON.
    local abyssCheck = U.FlatCheck(barP, "bbAbyssCheck", "Abyssal", 290, 114, 82,
        function() return settings.getSettings().showAbyssal == true end,
        function()
            local s2 = settings.getSettings()
            settings.updateSetting("showAbyssal", s2.showAbyssal ~= true)
            settings.saveSettings()
        end)
    -- Abyssal pip diameter. Runs past the client's 49px cell up to 69: our
    -- spacing follows pip size, so oversized pips overhang the invisible
    -- slots without colliding with each other
    -- (bubble_action_bar_view.lua:2-3) - the slots are spaced by it, so a wider
    -- pip would run into its neighbour. abyssal.lua clamps to the live cell
    -- height as well, in case a future client sizes them differently.
    local abyssSizeSlider = U.SliderRow(barP, "bbAbyssSize", "Abyss size", 142, 8, 69,
        s.abyssalSize or 35, function(v)
            settings.updateSetting("abyssalSize", v)
            settings.saveSettings()
        end)
    -- Assigned after the COLORS section builds; hides the Cast colour
    -- control while the cast bar itself is off.
    local syncCastColorUI
    local castCheck
    if CAST_BAR_ENABLED then
        castCheck = U.FlatCheck(barP, "bbCastCheck", "Cast bar", 290, 114, 82,
            function() return settings.getSettings().showCastBar ~= false end,
            function()
                local s2 = settings.getSettings()
                settings.updateSetting("showCastBar", not (s2.showCastBar ~= false))
                settings.saveSettings()
                if syncCastColorUI then syncCastColorUI() end
            end)
    end

    -- =============================================
    -- SECTION: COLORS — cubes + live preview
    -- =============================================
    -- Panel height follows the bar heights at build time so the preview fits;
    -- resizing the sliders afterwards may spill slightly until reopened.
    -- Heights ARE the bar heights (ApplyBarBox applies them straight through).
    local pvHpH = (s.barHeight and s.barHeight.hp) or 17
    local pvMpH = (s.barHeight and s.barHeight.mp) or 13
    local colorPH = 70 + math.max(38, pvHpH + pvMpH + 8) + 12
    local colorP = createSectionPanel(settingsWindow, "colorPanel", 18, y, 384, colorPH, "COLORS")
    y = y + colorPH + 8

    -- Three groups centred across the 384 panel (back from the four-across
    -- squeeze the Abyss cube needed): 30px margins, 76px between groups, each
    -- group a label then its cube.
    U.ChildLabel(colorP, "hpColorLabel", "HP", 30, 39, 22, 14, 13, C.gold, ALIGN.LEFT)
    local hpCube = U.ColorCube(colorP, "hpColorCube", 54, 34, "hp", function()
        openColorPopup("hp", "HP")
    end, 24)
    U.ChildLabel(colorP, "mpColorLabel", "MP", 154, 39, 24, 14, 13, C.gold, ALIGN.LEFT)
    local mpCube = U.ColorCube(colorP, "mpColorCube", 180, 34, "mp", function()
        openColorPopup("mp", "MP")
    end, 24)
    U.ChildLabel(colorP, "ehpColorLabel", "Enemy", 280, 39, 46, 14, 13, C.gold, ALIGN.LEFT)
    local ehpCube = U.ColorCube(colorP, "ehpColorCube", 330, 34, "ehp", function()
        openColorPopup("ehp", "Enemy")
    end, 24)
    -- No Abyss cube since 3.1: the charge pips are plain authored artwork and
    -- carry their own colour (see abyssal.lua). A pre-3.1 session may have
    -- created the old cube widgets on this window; they are simply not rebuilt.
    wndColorCubes = { hp = hpCube, mp = mpCube, ehp = ehpCube }

    if CAST_BAR_ENABLED then
        -- NOTE: when this wakes up, the cube row needs its four-across
        -- squeeze back (see git history) - these coords overlap Enemy.
        local castColorLbl = U.ChildLabel(colorP, "castColorLabel", "Cast", 286, 39, 34, 14, 13, C.gold, ALIGN.LEFT)
        local castCube = U.ColorCube(colorP, "castColorCube", 322, 34, "cast", function()
            openColorPopup("cast", "Cast")
        end, 24)
        wndColorCubes.cast = castCube

        -- Cast colour only makes sense while the cast bar exists; hide the
        -- control with the feature. If the popup is editing it when it goes,
        -- the popup goes too.
        syncCastColorUI = function()
            local on = settings.getSettings().showCastBar ~= false
            pcall(function() castColorLbl:Show(on) end)
            pcall(function() castCube:Show(on) end)
            if not on and colorPopup and colorPopup:IsVisible() and colorPopupTarget == "cast" then
                hideColorPopup()
            end
        end
        syncCastColorUI()
    end

    -- Live preview: fake HP + MP bars painted from colorValues and the
    -- current settings. updatePreview() re-applies colours, fill, format,
    -- font size and bar heights on every change. While the popup edits the
    -- enemy colour, the HP bar wears it - no extra toggle needed.
    previewRefs = {
        panel = colorP,
        x = 40,
        y = 70,
        hp = buildPreviewBar(colorP, "HP", 40, 70, 300, pvHpH, "bar_retail", 300, 17),
        mp = buildPreviewBar(colorP, "MP", 40, 70 + pvHpH + Px(PREV_MP_GAP), 300, pvMpH, "bar_retail_mp", 300, 13),
    }
    -- Mock level digit left of the bars; follows the Font pick live
    previewRefs.levelLbl = U.ChildLabel(colorP, "bbPrevLevel", "47", 4, 74, 34, 26, 22, C.gold, ALIGN.CENTER)
    updatePreview()

    -- =============================================
    -- SECTION: LABELS
    -- =============================================
    local labelP = createSectionPanel(settingsWindow, "labelPanel", 18, y, 384, 118, "LABELS")
    y = y + 126

    U.ChildLabel(labelP, "labelFormatTitle", "Format", 14, 34, 50, 14, 13, C.gold, ALIGN.LEFT)
    local fmtBtn
    fmtBtn = U.ChildFlatButton(labelP, "labelFormatBtn", fmtLabels[s.labelFormat or "both"] or "Both",
        120, 30, 96, 22, C.blue, function()
            local s2 = settings.getSettings()
            local cur = s2.labelFormat or "both"
            local idx = 1
            for i, v in ipairs(fmtCycle) do
                if v == cur then idx = i break end
            end
            idx = (idx % #fmtCycle) + 1
            settings.updateSetting("labelFormat", fmtCycle[idx])
            settings.saveSettings()
            fmtBtn:SetCleanText(fmtLabels[fmtCycle[idx]] or "Both")
            updatePreview()
        end, ALIGN.CENTER)

    local fsSlider = U.SliderRow(labelP, "bbFs", "Text size", 60, 8, 30,
        s.labelFontSize or 11, function(v)
            settings.updateSetting("labelFontSize", v)
            settings.saveSettings()
            updatePreview()
        end)

    local houseCheck = U.FlatCheck(labelP, "bbHouseCheck", "House HP", 14, 88, 94,
        function() return settings.getSettings().showHousingHP == true end,
        function()
            local s2 = settings.getSettings()
            settings.updateSetting("showHousingHP", not (s2.showHousingHP == true))
            settings.saveSettings()
        end)
    -- Engine text shadow on the HP/MP numbers (the same shading level/name use)
    local shadowCheck = U.FlatCheck(labelP, "bbShadowCheck", "Shadow", 152, 88, 80,
        function() return settings.getSettings().labelShadow == true end,
        function()
            local s2 = settings.getSettings()
            settings.updateSetting("labelShadow", not (s2.labelShadow == true))
            settings.saveSettings()
        end)

    -- =============================================
    -- SECTION: INFO (class, gear score, guild)
    -- =============================================
    local infoP = createSectionPanel(settingsWindow, "infoPanel", 18, y, 384, 166, "INFO")
    y = y + 174

    local classCheck = U.FlatCheck(infoP, "bbClassCheck", "Class", 14, 34, 68,
        function() return settings.getSettings().showClass == true end,
        function()
            local s2 = settings.getSettings()
            settings.updateSetting("showClass", not (s2.showClass == true))
            settings.saveSettings()
        end)
    local gsCheck = U.FlatCheck(infoP, "bbGsCheck", "GS", 150, 34, 50,
        function() return settings.getSettings().showGearScore == true end,
        function()
            local s2 = settings.getSettings()
            settings.updateSetting("showGearScore", not (s2.showGearScore == true))
            settings.saveSettings()
        end)
    local guildCheck = U.FlatCheck(infoP, "bbGuildCheck", "Guild", 270, 34, 68,
        function() return settings.getSettings().showGuild == true end,
        function()
            local s2 = settings.getSettings()
            settings.updateSetting("showGuild", not (s2.showGuild == true))
            settings.saveSettings()
        end)

    -- Per-item anchor offsets: pick the item, then drive its X and Y. The
    -- write path goes through updateSetting("infoOffsets", ...) so the whole
    -- nested table lands in the engine store on save.
    local infoItems = { "class", "gs", "guild" }
    local infoItemLabels = { class = "Class", gs = "GS", guild = "Guild" }
    local curInfoItem = "class"
    local xSlider, ySlider, sizeSlider

    local function infoOff()
        local s2 = settings.getSettings()
        local t = s2.infoOffsets or {}
        t[curInfoItem] = t[curInfoItem] or { x = 0, y = 0, size = 12 }
        return t, t[curInfoItem]
    end

    local infoShadowCheck = U.FlatCheck(infoP, "bbInfoShadowCheck", "Shadow", 270, 62, 80,
        function() return settings.getSettings().infoShadow == true end,
        function()
            local s2 = settings.getSettings()
            settings.updateSetting("infoShadow", not (s2.infoShadow == true))
            settings.saveSettings()
        end)

    U.ChildLabel(infoP, "bbInfoOffTitle", "Offsets", 14, 64, 52, 14, 13, C.gold, ALIGN.LEFT)
    local itemBtn
    itemBtn = U.ChildFlatButton(infoP, "bbInfoItemBtn", infoItemLabels[curInfoItem],
        120, 60, 96, 22, C.blue, function()
            local idx = 1
            for i, v in ipairs(infoItems) do
                if v == curInfoItem then idx = i break end
            end
            curInfoItem = infoItems[(idx % #infoItems) + 1]
            itemBtn:SetCleanText(infoItemLabels[curInfoItem])
            local _, o = infoOff()
            xSlider.SetValue(o.x or 0)
            ySlider.SetValue(o.y or 0)
            sizeSlider.SetValue(o.size or 12)
        end, ALIGN.CENTER)

    xSlider = U.SliderRow(infoP, "bbInfoX", "X offset", 88, -150, 150,
        (s.infoOffsets and s.infoOffsets.class and s.infoOffsets.class.x) or 0,
        function(v)
            local t, o = infoOff()
            o.x = v
            settings.updateSetting("infoOffsets", t)
            settings.saveSettings()
        end)
    ySlider = U.SliderRow(infoP, "bbInfoY", "Y offset", 114, -60, 60,
        (s.infoOffsets and s.infoOffsets.class and s.infoOffsets.class.y) or 0,
        function(v)
            local t, o = infoOff()
            o.y = v
            settings.updateSetting("infoOffsets", t)
            settings.saveSettings()
        end)

    -- Per-item font size, bound to the same item selector as X/Y
    sizeSlider = U.SliderRow(infoP, "bbInfoSz", "Size", 140, 6, 30,
        (s.infoOffsets and s.infoOffsets.class and s.infoOffsets.class.size) or 12,
        function(v)
            local t, o = infoOff()
            o.size = v
            settings.updateSetting("infoOffsets", t)
            settings.saveSettings()
        end)

    -- =============================================
    -- BOTTOM: credit label (TTP convention). Reset lives in the header and
    -- everything saves live, so no button row down here.
    -- =============================================
    local credit = U.Label(settingsWindow, "bbCredit", "BetterBars - " .. ADDON_VERSION .. " - By Dehling",
        6, y + 4, 260, 11, 10, {0.30, 0.31, 0.35, 1}, ALIGN.LEFT)
    credit:Clickable(false)

    -- The window is sized to the content: sections stacked to y, credit 20
    height = y + 20
    settingsWindow:SetExtent(width, height)

    -- Refresh every control from saved settings (used after reset)
    local function refreshDisplayValues()
        local s2 = settings.getSettings()
        hpSlider.SetValue((s2.barHeight and s2.barHeight.hp) or 17)
        mpSlider.SetValue((s2.barHeight and s2.barHeight.mp) or 13)
        bgSlider.SetValue(math.floor((s2.backgroundOpacity or 1) * 10 + 0.5))
        fsSlider.SetValue(s2.labelFontSize or 11)
        local io2 = (s2.infoOffsets and s2.infoOffsets[curInfoItem]) or {}
        sizeSlider.SetValue(io2.size or 12)
        fmtBtn:SetCleanText(fmtLabels[s2.labelFormat or "both"] or "Both")
        abyssSizeSlider.SetValue(s2.abyssalSize or 35)
        fillCheck.Refresh()
        abyssCheck.Refresh()
        if castCheck then castCheck.Refresh() end
        if syncCastColorUI then syncCastColorUI() end
        houseCheck.Refresh()
        shadowCheck.Refresh()
        classCheck.Refresh()
        gsCheck.Refresh()
        guildCheck.Refresh()
        infoShadowCheck.Refresh()
        local s3 = settings.getSettings()
        local o = (s3.infoOffsets and s3.infoOffsets[curInfoItem]) or { x = 0, y = 0 }
        xSlider.SetValue(o.x or 0)
        ySlider.SetValue(o.y or 0)
        updatePreview()
    end
    wndRefreshDisplayValues = refreshDisplayValues

    -- Update color cubes from saved values
    local function updateColorCubes()
        for key, cube in pairs(wndColorCubes) do
            local cv = colorValues[key]
            if cv and cube._fill then
                cube._fill:SetColor(cv.r / 255, cv.g / 255, cv.b / 255, cv.a or 1)
            end
        end
        updatePreview()
    end
    updateColorCubes()
    wndUpdateColorCubes = updateColorCubes
    
    -- Window close handler
    function settingsWindow:OnHide()
        isSettingsPageOpened = false
        hideColorPopup()
        hideFontPopup()
    end
    
    -- Center on screen
    local sw = api.Interface:GetScreenWidth()
    local sh = api.Interface:GetScreenHeight()
    settingsWindow:SetOffset((sw - width) / 2, (sh - height) / 2)
    
    isSettingsPageOpened = false
    settingsWindow:Show(false)
end

-- Function to open settings window
-- Shown the first time the settings window is opened rather than at load, so
-- it lands when the player is already looking at the addon instead of
-- interrupting them mid-game.
local function openSettingsWindow()
    -- Load current settings
            currentSettings = { colors = settings.getColors() }
    
    -- If window wasn't initialized, create it
    if not settingsWindow then
        initializeSettingsPage()
    else
        updateSettingsFields()
    end
    
    -- Show window
        if settingsWindow then
            settingsWindow:Show(true)
            isSettingsPageOpened = true
        end
end

-- First open shows the card once; the ? button re-opens it any time.
local realOpenSettingsWindow = openSettingsWindow
openSettingsWindow = function(...)
    local r = realOpenSettingsWindow(...)
    pcall(maybeShowInfoCard)
    return r
end

-- Function to unload settings page
local function unload()
        if settingsWindow then
            settingsWindow:Show(false)
            settingsWindow:ReleaseHandler("OnHide")
            settingsWindow = nil
        end
    
        if colorPopup then
            colorPopup:Show(false)
            colorPopup = nil
        end

        if fontPopup then
            fontPopup:Show(false)
            fontPopup = nil
        end
        fontRowRefs = {}
    
        controls = {}
        currentSettings = {}
        colorValues = {}
        popupRGBInputs = {}
        previewRefs = nil
        popupSwatch = nil
        popupValSlider = nil
        popupTitleLbl = nil
        wndColorCubes = {}
        wndUpdateColorCubes = nil
        wndRefreshDisplayValues = nil
end

-- Return the settings page module
local settings_page = {
    ADDON_VERSION = ADDON_VERSION,
    openSettingsWindow = openSettingsWindow,
    maybeShowInfoCard = maybeShowInfoCard,
    unload = unload,
    Load = initializeSettingsPage,
    Unload = unload
}

return settings_page 