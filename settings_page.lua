local api = require("api")
local settings = require("BetterBars/settings")
local default_settings = require("BetterBars/default_settings")

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
    for _, key in ipairs({"hp", "mp", "ehp"}) do
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
    for _, key in ipairs({"hp", "mp", "ehp"}) do
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
    for _, key in ipairs({"hp", "mp", "ehp"}) do
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

-- Function to reset settings to defaults
local function resetSettings()
    colorValues = {
        hp = { r = default_settings.colors.hp.r, g = default_settings.colors.hp.g, b = default_settings.colors.hp.b, a = default_settings.colors.hp.a },
        mp = { r = default_settings.colors.mp.r, g = default_settings.colors.mp.g, b = default_settings.colors.mp.b, a = default_settings.colors.mp.a },
        ehp = { r = default_settings.colors.ehp.r, g = default_settings.colors.ehp.g, b = default_settings.colors.ehp.b, a = default_settings.colors.ehp.a },
    }
    applyAllColors()
    settings.resetToDefaults()
    if wndUpdateColorCubes then wndUpdateColorCubes() end
    if wndRefreshDisplayValues then wndRefreshDisplayValues() end
    
    -- Hide color popup if it's visible
    hideColorPopup()
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

-- Define color palette with variations
local colorPalette = {
    -- Row 1 (Light colors)
    { r = 255, g = 204, b = 204, a = 1 }, -- Light pink
    { r = 255, g = 229, b = 204, a = 1 }, -- Light peach
    { r = 255, g = 255, b = 204, a = 1 }, -- Light yellow
    { r = 229, g = 255, b = 204, a = 1 }, -- Light lime
    { r = 204, g = 255, b = 204, a = 1 }, -- Light green
    { r = 204, g = 255, b = 229, a = 1 }, -- Light mint
    { r = 204, g = 255, b = 255, a = 1 }, -- Light cyan
    { r = 204, g = 229, b = 255, a = 1 }, -- Light sky
    { r = 204, g = 204, b = 255, a = 1 }, -- Light blue
    { r = 229, g = 204, b = 255, a = 1 }, -- Light purple

    -- Row 2 (Medium-light colors)
    { r = 255, g = 153, b = 153, a = 1 }, -- Medium-light red
    { r = 255, g = 204, b = 153, a = 1 }, -- Medium-light orange
    { r = 255, g = 255, b = 153, a = 1 }, -- Medium-light yellow
    { r = 204, g = 255, b = 153, a = 1 }, -- Medium-light lime
    { r = 153, g = 255, b = 153, a = 1 }, -- Medium-light green
    { r = 153, g = 255, b = 204, a = 1 }, -- Medium-light mint
    { r = 153, g = 255, b = 255, a = 1 }, -- Medium-light cyan
    { r = 153, g = 204, b = 255, a = 1 }, -- Medium-light sky
    { r = 153, g = 153, b = 255, a = 1 }, -- Medium-light blue
    { r = 204, g = 153, b = 255, a = 1 }, -- Medium-light purple

    -- Row 3 (Medium colors)
    { r = 255, g = 102, b = 102, a = 1 }, -- Medium red
    { r = 255, g = 178, b = 102, a = 1 }, -- Medium orange
    { r = 255, g = 255, b = 102, a = 1 }, -- Medium yellow
    { r = 178, g = 255, b = 102, a = 1 }, -- Medium lime
    { r = 102, g = 255, b = 102, a = 1 }, -- Medium green
    { r = 102, g = 255, b = 178, a = 1 }, -- Medium mint
    { r = 102, g = 255, b = 255, a = 1 }, -- Medium cyan
    { r = 102, g = 178, b = 255, a = 1 }, -- Medium sky
    { r = 102, g = 102, b = 255, a = 1 }, -- Medium blue
    { r = 178, g = 102, b = 255, a = 1 }, -- Medium purple

    -- Row 4 (Medium-dark colors)
    { r = 255, g = 51, b = 51, a = 1 },   -- Medium-dark red
    { r = 255, g = 153, b = 51, a = 1 },  -- Medium-dark orange
    { r = 255, g = 255, b = 51, a = 1 },  -- Medium-dark yellow
    { r = 153, g = 255, b = 51, a = 1 },  -- Medium-dark lime
    { r = 51, g = 255, b = 51, a = 1 },   -- Medium-dark green
    { r = 51, g = 255, b = 153, a = 1 },  -- Medium-dark mint
    { r = 51, g = 255, b = 255, a = 1 },  -- Medium-dark cyan
    { r = 51, g = 153, b = 255, a = 1 },  -- Medium-dark sky
    { r = 51, g = 51, b = 255, a = 1 },   -- Medium-dark blue
    { r = 153, g = 51, b = 255, a = 1 },  -- Medium-dark purple

    -- Row 5 (Dark colors)
    { r = 204, g = 0, b = 0, a = 1 },     -- Dark red
    { r = 204, g = 102, b = 0, a = 1 },   -- Dark orange
    { r = 204, g = 204, b = 0, a = 1 },   -- Dark yellow
    { r = 102, g = 204, b = 0, a = 1 },   -- Dark lime
    { r = 0, g = 204, b = 0, a = 1 },     -- Dark green
    { r = 0, g = 204, b = 102, a = 1 },   -- Dark mint
    { r = 0, g = 204, b = 204, a = 1 },   -- Dark cyan
    { r = 0, g = 102, b = 204, a = 1 },   -- Dark sky
    { r = 0, g = 0, b = 204, a = 1 },     -- Dark blue
    { r = 102, g = 0, b = 204, a = 1 },   -- Dark purple

    -- Row 6 (Darker colors)
    { r = 153, g = 0, b = 0, a = 1 },     -- Darker red
    { r = 153, g = 76, b = 0, a = 1 },    -- Darker orange
    { r = 153, g = 153, b = 0, a = 1 },   -- Darker yellow
    { r = 76, g = 153, b = 0, a = 1 },    -- Darker lime
    { r = 0, g = 153, b = 0, a = 1 },     -- Darker green
    { r = 0, g = 153, b = 76, a = 1 },    -- Darker mint
    { r = 0, g = 153, b = 153, a = 1 },   -- Darker cyan
    { r = 0, g = 76, b = 153, a = 1 },    -- Darker sky
    { r = 0, g = 0, b = 153, a = 1 },     -- Darker blue
    { r = 76, g = 0, b = 153, a = 1 }     -- Darker purple
}

-- =============================================
-- CACHED COLOR POPUP — built once, reused
-- =============================================
local popupRGBInputs = {}
local popupCustomPicker = nil

local function buildColorPopup()
    if colorPopup then return end
    
    colorPopup = api.Interface:CreateWidget("window", "BetterBarsColorPopup")
    colorPopup:SetExtent(350, 350)
    
    -- Black background
    local popupBG = colorPopup:CreateColorDrawable(0, 0, 0, 1, "background")
    popupBG:AddAnchor("TOPLEFT", colorPopup, 0, 0)
    popupBG:AddAnchor("BOTTOMRIGHT", colorPopup, 0, 0)
    
    -- White border
    local popupBorder = colorPopup:CreateNinePartDrawable(TEXTURE_PATH.DEFAULT, "overlay")
    popupBorder:SetCoords(949, 199, 8, 8)
    popupBorder:SetInset(3, 3, 3, 3)
    popupBorder:SetColor(1, 1, 1, 0.5)
    popupBorder:AddAnchor("TOPLEFT", colorPopup, 0, 0)
    popupBorder:AddAnchor("BOTTOMRIGHT", colorPopup, 0, 0)
    
    -- Title
    local popupTitle = colorPopup:CreateChildWidget("label", "popupTitle", 0, true)
    popupTitle:SetText("Select a Color")
    popupTitle:AddAnchor("TOP", colorPopup, 0, 30)
    popupTitle.style:SetFontSize(FONT_SIZE.MIDDLE)
    popupTitle.style:SetAlign(ALIGN.CENTER)
    popupTitle.style:SetColor(1, 1, 1, 1)
    
    -- Preset color grid
    local colorGrid = colorPopup:CreateChildWidget("window", "colorGrid", 0, true)
    colorGrid:SetExtent(280, 210)
    colorGrid:AddAnchor("TOP", popupTitle, "BOTTOM", 0, 40)
    
    local squareSize = 24
    local spacing = 2
    local squaresPerRow = 10
    
    for i, colorData in ipairs(colorPalette) do
        local row = math.floor((i-1) / squaresPerRow)
        local col = (i-1) % squaresPerRow
        
        local square = colorGrid:CreateChildWidget("window", "square" .. i, 0, true)
        square:SetExtent(squareSize, squareSize)
        square:AddAnchor("TOPLEFT", colorGrid, col * (squareSize + spacing) + 10, row * (squareSize + spacing) + 10)
        
        local squareBG = square:CreateColorDrawable(
            colorData.r/255, colorData.g/255, colorData.b/255, colorData.a, "background"
        )
        squareBG:AddAnchor("TOPLEFT", square, 0, 0)
        squareBG:AddAnchor("BOTTOMRIGHT", square, 0, 0)
        
        local squareBorder = square:CreateNinePartDrawable(TEXTURE_PATH.DEFAULT, "overlay")
        squareBorder:SetCoords(949, 199, 8, 8)
        squareBorder:SetInset(2, 2, 2, 2)
        squareBorder:SetColor(1, 1, 1, 0.1)
        squareBorder:AddAnchor("TOPLEFT", square, 0, 0)
        squareBorder:AddAnchor("BOTTOMRIGHT", square, 0, 0)
        
        square:SetHandler("OnClick", function()
            local key = colorPopupTarget
            if not key then return end
            colorValues[key] = { r = colorData.r, g = colorData.g, b = colorData.b, a = colorData.a }
            if wndColorCubes and wndColorCubes[key] and wndColorCubes[key]._fill then
                wndColorCubes[key]._fill:SetColor(colorData.r/255, colorData.g/255, colorData.b/255, colorData.a)
            end
            saveColorToGame(key)
            hideColorPopup()
        end)
        
        square:SetHandler("OnEnter", function()
            squareBorder:SetColor(0, 0, 0, 0.8)
        end)
        square:SetHandler("OnLeave", function()
            squareBorder:SetColor(1, 1, 1, 0.3)
        end)
    end
    
    -- Custom Color button
    local customButton = colorPopup:CreateChildWidget("button", "customButton", 0, true)
    customButton:SetText("Custom Color")
    customButton:SetExtent(140, 30)
    customButton:AddAnchor("BOTTOM", colorPopup, 0, -62)
    ApplyButtonSkin(customButton, BUTTON_BASIC.DEFAULT)
    
    -- Custom color picker container
    popupCustomPicker = colorPopup:CreateChildWidget("window", "customColorPicker", 0, true)
    popupCustomPicker:SetExtent(260, 210)
    popupCustomPicker:RemoveAllAnchors()
    popupCustomPicker:AddAnchor("TOPLEFT", colorGrid, "TOPRIGHT", 39, -70)
    popupCustomPicker:Show(false)
    
    local customBG = popupCustomPicker:CreateColorDrawable(0, 0, 0, 1, "background")
    customBG:AddAnchor("TOPLEFT", popupCustomPicker, 0, 0)
    customBG:AddAnchor("BOTTOMRIGHT", popupCustomPicker, 0, 0)
    local customBorder = popupCustomPicker:CreateNinePartDrawable(TEXTURE_PATH.DEFAULT, "overlay")
    customBorder:SetCoords(949, 199, 8, 8)
    customBorder:SetInset(3, 3, 3, 3)
    customBorder:SetColor(1, 1, 1, 0.5)
    customBorder:AddAnchor("TOPLEFT", popupCustomPicker, 0, 0)
    customBorder:AddAnchor("BOTTOMRIGHT", popupCustomPicker, 0, 0)
    
    -- Custom RGB title
    local customTitle = popupCustomPicker:CreateChildWidget("label", "customTitle", 0, true)
    customTitle:SetText("Custom RGB Values")
    customTitle:SetExtent(180, 35)
    customTitle:AddAnchor("TOP", popupCustomPicker, 0, 0)
    customTitle.style:SetFontSize(FONT_SIZE.MIDDLE)
    customTitle.style:SetAlign(ALIGN.CENTER)
    customTitle.style:SetColor(0.9, 0.9, 0.9, 1)
    
    -- RGB inputs
    local function createColorInput(label, parent, yOffset, defaultValue, textColor)
        local container = parent:CreateChildWidget("window", label .. "Container", 0, true)
        container:SetExtent(200, 30)
        container:AddAnchor("TOP", parent, 0, yOffset)
        local rowBG = container:CreateColorDrawable(0.15, 0.15, 0.15, 0.5, "background")
        rowBG:AddAnchor("TOPLEFT", container, 5, 0)
        rowBG:AddAnchor("BOTTOMRIGHT", container, -5, 0)
        local labelWidget = container:CreateChildWidget("label", label .. "Label", 0, true)
        labelWidget:SetText(label .. ":")
        labelWidget:SetExtent(30, 20)
        labelWidget:AddAnchor("LEFT", container, 20, 0)
        labelWidget.style:SetFontSize(FONT_SIZE.MIDDLE)
        labelWidget.style:SetColor(unpack(textColor))
        local inputBG = container:CreateColorDrawable(0.1, 0.1, 0.1, 0.8, "background")
        inputBG:SetExtent(60, 22)
        inputBG:AddAnchor("LEFT", labelWidget, "RIGHT", 15, 0)
        local input = W_CTRL.CreateEdit(label .. "Input", container)
        input:SetExtent(50, 20)
        input:AddAnchor("CENTER", inputBG, 0, 0)
        input:SetText(tostring(defaultValue))
        input:SetMaxTextLength(3)
        input.style:SetAlign(ALIGN.CENTER)
        function input:OnTextChanged()
            local text = self:GetText()
            local number = tonumber(text) or 0
            if number > 255 then number = 255 end
            if number < 0 then number = 0 end
            self:SetText(tostring(number))
        end
        input:SetHandler("OnTextChanged", input.OnTextChanged)
        return input
    end
    
    popupRGBInputs.red = createColorInput("R", popupCustomPicker, 40, 0, {1, 0.4, 0.4, 1})
    popupRGBInputs.green = createColorInput("G", popupCustomPicker, 80, 0, {0.4, 1, 0.4, 1})
    popupRGBInputs.blue = createColorInput("B", popupCustomPicker, 120, 0, {0.4, 0.4, 1, 1})
    
    -- Apply custom color
    local applyButton = popupCustomPicker:CreateChildWidget("button", "applyButton", 0, true)
    applyButton:SetText("Apply")
    applyButton:SetExtent(100, 30)
    applyButton:AddAnchor("TOP", popupRGBInputs.blue, "BOTTOM", 0, 25)
    ApplyButtonSkin(applyButton, BUTTON_BASIC.DEFAULT)
    applyButton:SetHandler("OnClick", function()
        local key = colorPopupTarget
        if not key then return end
        local r = tonumber(popupRGBInputs.red:GetText()) or 0
        local g = tonumber(popupRGBInputs.green:GetText()) or 0
        local b = tonumber(popupRGBInputs.blue:GetText()) or 0
        colorValues[key] = { r = r, g = g, b = b, a = 1 }
        if wndColorCubes and wndColorCubes[key] and wndColorCubes[key]._fill then
            wndColorCubes[key]._fill:SetColor(r/255, g/255, b/255, 1)
        end
        saveColorToGame(key)
        hideColorPopup()
    end)
    
    -- Toggle custom color picker
    customButton:SetHandler("OnClick", function()
        popupCustomPicker:Show(not popupCustomPicker:IsVisible())
        if popupCustomPicker:IsVisible() then
            local key = colorPopupTarget
            local cv = colorValues[key]
            if cv then
                popupRGBInputs.red:SetText(tostring(cv.r))
                popupRGBInputs.green:SetText(tostring(cv.g))
                popupRGBInputs.blue:SetText(tostring(cv.b))
            end
        end
    end)
    
    -- Close button
    local closeButton = colorPopup:CreateChildWidget("button", "closeButton", 0, true)
    closeButton:SetText("Close")
    closeButton:SetExtent(100, 30)
    closeButton:AddAnchor("BOTTOM", colorPopup, 0, -10)
    ApplyButtonSkin(closeButton, BUTTON_BASIC.DEFAULT)
    closeButton:SetHandler("OnClick", hideColorPopup)
    
    -- Make draggable
    colorPopup:SetHandler("OnDragStart", colorPopup.StartMoving)
    colorPopup:SetHandler("OnDragStop", colorPopup.StopMovingOrSizing)
    colorPopup:Show(false)
end

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
    fill:AddAnchor("TOPLEFT", btn, 1, 1)
    fill:AddAnchor("BOTTOMRIGHT", btn, -1, -1)
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
    fill:AddAnchor("TOPLEFT", button, 1, 1)
    fill:AddAnchor("BOTTOMRIGHT", button, -1, -1)
    fill:Show(true)
    local textLabel = U.ChildLabel(button, id .. "_text", text, 4, 2, w - 8, h - 4, 11, white, align or ALIGN.LEFT)
    textLabel:Clickable(false)
    button.cleanFill = fill
    button.cleanLabel = textLabel
    function button:SetCleanText(value) self.cleanLabel:SetText(value or "") end
    function button:SetTone(value) self.cleanFill:SetColor(value[1], value[2], value[3], value[4]) end
    if onClick then button:SetHandler("OnClick", onClick) end
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

local btnRefs = {}  -- references to toggle buttons for refresh

local function setToggle(btn, state, text)
    U.SetToggle(btn, state, text)
end

local function refreshAllToggleButtons()
    local s = settings.getSettings()
    for key, btnInfo in pairs(btnRefs) do
        setToggle(btnInfo.btn, s[key] or s.barHeight and s.barHeight[key] or s.backgroundOpacity and math.floor(s.backgroundOpacity * 10), btnInfo.text)
    end
end

-- Increment/decrement a numeric setting
local function shiftSetting(key, delta, min, max, displayDivisor)
    local s = settings.getSettings()
    local val
    if key == "barHeight_hp" then
        val = (s.barHeight and s.barHeight.hp) or 17
    elseif key == "barHeight_mp" then
        val = (s.barHeight and s.barHeight.mp) or 15
    elseif key == "backgroundOpacity" then
        val = math.floor((s.backgroundOpacity or 0.6) * 10)
    else
        val = s[key]
    end
    val = (val or 0) + delta
    if val < min then val = min end
    if val > max then val = max end
    
    if key == "barHeight_hp" then
        local bh = s.barHeight or {}
        bh.hp = val
        settings.updateSetting("barHeight", bh)
    elseif key == "barHeight_mp" then
        local bh = s.barHeight or {}
        bh.mp = val
        settings.updateSetting("barHeight", bh)
    elseif key == "backgroundOpacity" then
        settings.updateSetting(key, val / 10)
    else
        settings.updateSetting(key, val)
    end
    settings.saveSettings()
    return val
end

-- Cycle through label format options
local fmtCycle = {"both", "current", "percent", "hide"}
local fmtLabels = {both = "Both", current = "Current", percent = "Percent", hide = "Hide"}
local function cycleLabelFormat()
    local s = settings.getSettings()
    local cur = s.labelFormat or "both"
    local idx = 1
    for i, v in ipairs(fmtCycle) do
        if v == cur then idx = i; break end
    end
    idx = (idx % #fmtCycle) + 1
    settings.updateSetting("labelFormat", fmtCycle[idx])
    settings.saveSettings()
    if btnRefs.labelFormat and btnRefs.labelFormat.btn then
        btnRefs.labelFormat.btn:SetCleanText(fmtLabels[fmtCycle[idx]] or "Both")
    end
end

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
    local width, height = 420, 400
    
    -- Shell window (no chrome, just dark fill + header)
    settingsWindow = api.Interface:CreateEmptyWindow("BetterBarsSettings", "UIParent")
    settingsWindow.bbSession = SESSION
    settingsWindow:SetExtent(width, height)
    settingsWindow:AddAnchor("TOPLEFT", "UIParent", 300, 100)
    U.AddBg(settingsWindow, 0, 0, 0, 0.96)
    
    local body = settingsWindow:CreateColorDrawable(C.dark[1], C.dark[2], C.dark[3], C.dark[4], "background")
    body:AddAnchor("TOPLEFT", settingsWindow, 1, 1)
    body:AddAnchor("BOTTOMRIGHT", settingsWindow, -1, -1)
    body:Show(true)
    
    -- Header bar
    local header = settingsWindow:CreateColorDrawable(C.header[1], C.header[2], C.header[3], C.header[4], "background")
    header:SetExtent(width - 2, 34)
    header:AddAnchor("TOPLEFT", settingsWindow, 1, 1)
    header:Show(true)
    
    -- Title
    local title = U.Label(settingsWindow, "BetterBars_title", "BetterBars", 16, 8, 200, 18, 17, C.gold, ALIGN.LEFT)
    
    -- Close button
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
    -- SECTION: BARS
    -- =============================================
    local barP = createSectionPanel(settingsWindow, "barPanel", 18, y, 384, 100, "BARS")
    y = y + 108
    btnRefs = {}
    
    -- HP Height (centered pair with MP, wider spacing for font compatibility)
    local hpVal = (s.barHeight and s.barHeight.hp) or 17
    U.ChildLabel(barP, "hpHeightLabel", "HP", 58, 32, 22, 14, 14, C.white, ALIGN.LEFT)
    U.ChildFlatButton(barP, "hpHeightDown", "-", 88, 30, 22, 20, C.button, function()
        local v = shiftSetting("barHeight_hp", -1, 5, 50)
        settingsWindow.hpHeightVal:SetText(tostring(v))
    end)
    settingsWindow.hpHeightVal = U.ChildLabel(barP, "hpHeightValue", tostring(hpVal), 118, 32, 24, 14, 14, C.white, ALIGN.CENTER)
    U.ChildFlatButton(barP, "hpHeightUp", "+", 150, 30, 22, 20, C.button, function()
        local v = shiftSetting("barHeight_hp", 1, 5, 50)
        settingsWindow.hpHeightVal:SetText(tostring(v))
    end)
    
    -- MP Height (centered pair with HP)
    local mpVal = (s.barHeight and s.barHeight.mp) or 15
    U.ChildLabel(barP, "mpHeightLabel", "MP", 212, 32, 22, 14, 14, C.white, ALIGN.LEFT)
    U.ChildFlatButton(barP, "mpHeightDown", "-", 242, 30, 22, 20, C.button, function()
        local v = shiftSetting("barHeight_mp", -1, 5, 50)
        settingsWindow.mpHeightVal:SetText(tostring(v))
    end)
    settingsWindow.mpHeightVal = U.ChildLabel(barP, "mpHeightValue", tostring(mpVal), 272, 32, 24, 14, 14, C.white, ALIGN.CENTER)
    U.ChildFlatButton(barP, "mpHeightUp", "+", 304, 30, 22, 20, C.button, function()
        local v = shiftSetting("barHeight_mp", 1, 5, 50)
        settingsWindow.mpHeightVal:SetText(tostring(v))
    end)
    
    -- Background opacity (centered, wider spacing)
    local opacVal = math.floor((s.backgroundOpacity or 0.6) * 10)
    U.ChildLabel(barP, "opacLabel", "BG", 118, 60, 20, 14, 14, C.white, ALIGN.LEFT)
    U.ChildFlatButton(barP, "opacDown", "-", 181, 58, 22, 20, C.button, function()
        local v = shiftSetting("backgroundOpacity", -1, 0, 10)
        settingsWindow.opacVal:SetText(tostring(v))
    end)
    settingsWindow.opacVal = U.ChildLabel(barP, "opacValue", tostring(opacVal), 211, 60, 24, 14, 14, C.white, ALIGN.CENTER)
    U.ChildFlatButton(barP, "opacUp", "+", 243, 58, 22, 20, C.button, function()
        local v = shiftSetting("backgroundOpacity", 1, 0, 10)
        settingsWindow.opacVal:SetText(tostring(v))
    end)
    
    -- =============================================
    -- SECTION: COLORS
    -- =============================================
    local colorP = createSectionPanel(settingsWindow, "colorPanel", 18, y, 384, 76, "COLORS")
    y = y + 84
    
    -- HP Color cube (centered, bigger)
    U.ChildLabel(colorP, "hpColorLabel", "HP", 86, 39, 22, 14, 14, C.white, ALIGN.LEFT)
    local hpCube = U.ColorCube(colorP, "hpColorCube", 112, 36, "hp", function()
        colorPopupTarget = "hp"
        buildColorPopup()
        colorPopup:RemoveAllAnchors()
        colorPopup:AddAnchor("TOPLEFT", settingsWindow, "TOPRIGHT", 5, 0)
        colorPopup:Show(true)
        colorPopup:Raise()
    end, 28)
    
    -- MP Color cube (centered, bigger)
    U.ChildLabel(colorP, "mpColorLabel", "MP", 170, 39, 22, 14, 14, C.white, ALIGN.LEFT)
    local mpCube = U.ColorCube(colorP, "mpColorCube", 196, 36, "mp", function()
        colorPopupTarget = "mp"
        buildColorPopup()
        colorPopup:RemoveAllAnchors()
        colorPopup:AddAnchor("TOPLEFT", settingsWindow, "TOPRIGHT", 5, 0)
        colorPopup:Show(true)
        colorPopup:Raise()
    end, 28)
    
    -- EHP Color cube (centered, bigger, extra padding)
    U.ChildLabel(colorP, "ehpColorLabel", "Enemy", 240, 39, 44, 14, 14, C.white, ALIGN.LEFT)
    local ehpCube = U.ColorCube(colorP, "ehpColorCube", 306, 36, "ehp", function()
        colorPopupTarget = "ehp"
        buildColorPopup()
        colorPopup:RemoveAllAnchors()
        colorPopup:AddAnchor("TOPLEFT", settingsWindow, "TOPRIGHT", 5, 0)
        colorPopup:Show(true)
        colorPopup:Raise()
    end, 28)
    
    -- Store cube refs for color updates
    wndColorCubes = { hp = hpCube, mp = mpCube, ehp = ehpCube }
    
    -- =============================================
    -- SECTION: LABELS
    -- =============================================
    local labelP = createSectionPanel(settingsWindow, "labelPanel", 18, y, 384, 64, "LABELS")
    y = y + 72
    
    U.ChildLabel(labelP, "labelFormatTitle", "Format", 43, 32, 44, 14, 14, C.gold, ALIGN.LEFT)
    local fmtBtn = U.ChildFlatButton(labelP, "labelFormatBtn", fmtLabels[s.labelFormat or "both"] or "Both", 95, 28, 90, 22, C.blue, cycleLabelFormat)
    btnRefs.labelFormat = { btn = fmtBtn, text = "Format" }
    
    -- Font size (same row, right of format)
    local fsVal = s.labelFontSize or 14
    U.ChildLabel(labelP, "fsLabel", "Size", 215, 32, 30, 14, 14, C.gold, ALIGN.LEFT)
    U.ChildFlatButton(labelP, "fsDown", "-", 253, 28, 22, 22, C.button, function()
        local s2 = settings.getSettings()
        local v = (s2.labelFontSize or 14) - 1
        if v < 8 then v = 8 end
        settings.updateSetting("labelFontSize", v)
        settings.saveSettings()
        settingsWindow.fsVal:SetText(tostring(v))
    end)
    settingsWindow.fsVal = U.ChildLabel(labelP, "fsValue", tostring(fsVal), 283, 30, 28, 14, 14, C.white, ALIGN.CENTER)
    U.ChildFlatButton(labelP, "fsUp", "+", 319, 28, 22, 22, C.button, function()
        local s2 = settings.getSettings()
        local v = (s2.labelFontSize or 14) + 1
        if v > 30 then v = 30 end
        settings.updateSetting("labelFontSize", v)
        settings.saveSettings()
        settingsWindow.fsVal:SetText(tostring(v))
    end)
    
    -- =============================================
    -- BOTTOM BUTTONS
    -- =============================================
    U.FlatButton(settingsWindow, "bbSaveBtn", "Save", 56, y + 10, 144, 34, C.blue, saveSettings)
    U.FlatButton(settingsWindow, "bbResetBtn", "Reset", 220, y + 10, 144, 34, C.button, resetSettings)
    
    -- Store refresh function for use after reset
    local function refreshDisplayValues()
        local s2 = settings.getSettings()
        if settingsWindow.hpHeightVal then
            settingsWindow.hpHeightVal:SetText(tostring(s2.barHeight and s2.barHeight.hp or 17))
        end
        if settingsWindow.mpHeightVal then
            settingsWindow.mpHeightVal:SetText(tostring(s2.barHeight and s2.barHeight.mp or 15))
        end
        if settingsWindow.opacVal then
            settingsWindow.opacVal:SetText(tostring(math.floor((s2.backgroundOpacity or 0.6) * 10)))
        end
        if fmtBtn then
            fmtBtn:SetCleanText(fmtLabels[s2.labelFormat or "both"] or "Both")
        end
        if settingsWindow.fsVal then
            settingsWindow.fsVal:SetText(tostring(s2.labelFontSize or 14))
        end
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
    end
    updateColorCubes()
    wndUpdateColorCubes = updateColorCubes
    
    -- Window close handler
    function settingsWindow:OnHide()
        isSettingsPageOpened = false
        hideColorPopup()
    end
    
    -- Center on screen
    local sw = api.Interface:GetScreenWidth()
    local sh = api.Interface:GetScreenHeight()
    settingsWindow:SetOffset((sw - width) / 2, (sh - height) / 2)
    
    isSettingsPageOpened = false
    settingsWindow:Show(false)
end

-- Function to open settings window
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
    
        controls = {}
        currentSettings = {}
        colorValues = {}
        popupRGBInputs = {}
        popupCustomPicker = nil
        wndColorCubes = {}
        wndUpdateColorCubes = nil
        wndRefreshDisplayValues = nil
end

-- Return the settings page module
local settings_page = {
    openSettingsWindow = openSettingsWindow,
    unload = unload,
    Load = initializeSettingsPage,
    Unload = unload
}

return settings_page 