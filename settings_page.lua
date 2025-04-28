local api = require("api")
local settings = require("BetterBars/settings")
local default_settings = require("BetterBars/default_settings")

-- =============================================
-- MAIN SETTINGS WINDOW SECTION
-- =============================================
local settingsWindow = nil
local controls = {}
local currentSettings = {}
local isSettingsPageOpened = false
local colorPopup = nil

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

-- Function to update settings fields
local function updateSettingsFields()
    if not settingsWindow then return end
    
    -- Update HP color picker
        if controls.hpColorButton and controls.hpColorButton.colorBG then
            if currentSettings and currentSettings.colors and currentSettings.colors.hp then
            controls.hpColorButton.colorBG:SetColor(
                currentSettings.colors.hp.r/255, 
                currentSettings.colors.hp.g/255, 
                currentSettings.colors.hp.b/255, 
                currentSettings.colors.hp.a
            )
        end
    end
    
    -- Update MP color picker
        if controls.mpColorButton and controls.mpColorButton.colorBG then
            if currentSettings and currentSettings.colors and currentSettings.colors.mp then
            controls.mpColorButton.colorBG:SetColor(
                currentSettings.colors.mp.r/255, 
                currentSettings.colors.mp.g/255, 
                currentSettings.colors.mp.b/255, 
                currentSettings.colors.mp.a
            )
        end
    end

    -- Update EHP color picker
    if controls.ehpColorButton and controls.ehpColorButton.colorBG then
        if currentSettings and currentSettings.colors and currentSettings.colors.ehp then
            controls.ehpColorButton.colorBG:SetColor(
                currentSettings.colors.ehp.r/255, 
                currentSettings.colors.ehp.g/255, 
                currentSettings.colors.ehp.b/255, 
                currentSettings.colors.ehp.a or 1 -- Use default alpha if missing
            )
        end
    end
end

-- Function to save settings
local function saveSettings()
    if not currentSettings then
        currentSettings = { colors = {} }
    elseif not currentSettings.colors then
        currentSettings.colors = {}
    end
    
    -- Get colors from color pickers
    -- TODO from Michael: Hey mr dehling, this wghole section is broken. Seems like `controls.hpColorButton.colorBG:GetColor()` is returning nil.
    -- TODO from Michael: I think the colorBG is not being set correctly in the createColorPickButton function.
        -- if controls.hpColorButton and controls.hpColorButton.colorBG then
        -- local r, g, b, a = controls.hpColorButton.colorBG:GetColor()
        --     currentSettings.colors.hp = {
        --         r = math.floor(tonumber(r) * 255),
        --         g = math.floor(tonumber(g) * 255),
        --         b = math.floor(tonumber(b) * 255),
        --         a = tonumber(a)
        --     }
        -- end
    
        -- if controls.mpColorButton and controls.mpColorButton.colorBG then
        -- local r, g, b, a = controls.mpColorButton.colorBG:GetColor()
        --     currentSettings.colors.mp = {
        --         r = math.floor(tonumber(r) * 255),
        --         g = math.floor(tonumber(g) * 255),
        --         b = math.floor(tonumber(b) * 255),
        --         a = tonumber(a)
        --     }
        -- end
    
        -- if controls.ehpColorButton and controls.ehpColorButton.colorBG then
        --     local r, g, b, a = controls.ehpColorButton.colorBG:GetColor()
        --     currentSettings.colors.ehp = {
        --         r = math.floor(tonumber(r) * 255),
        --         g = math.floor(tonumber(g) * 255),
        --         b = math.floor(tonumber(b) * 255),
        --         a = tonumber(a)
        --     }
        -- end
    
            settings.updateColors(currentSettings.colors)
            settings.saveSettings()
            UpdateColorsFromSettings()
    
    -- Hide color popup if it's visible
    hideColorPopup()
end

-- Function to reset settings to defaults
local function resetSettings()
    currentSettings.colors = default_settings.colors
    updateSettingsFields()
            settings.resetToDefaults()
            settings.saveSettings()
    
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

-- Function to create color picker button
local function createColorPickButton(id, parent, color, x, y)
    -- Add Debug Log Start
    -- api.Log:Info("BetterBars: createColorPickButton START - id: " .. id)
    if not color or type(color) ~= "table" then
         -- api.Log:Err("BetterBars: createColorPickButton - Invalid color data for id: " .. id .. ". Color Type: " .. type(color))
         return {} -- Return empty table to avoid downstream errors
    end
     -- api.Log:Info("BetterBars: createColorPickButton - Color for " .. id .. ": r=" .. tostring(color.r) .. ", g=" .. tostring(color.g) .. ", b=" .. tostring(color.b) .. ", a=" .. tostring(color.a))

    -- Create button container
    local container = parent:CreateChildWidget("window", id .. "Container", 0, true)
    container:SetExtent(200, 60)  -- Increased height for larger preview
    container:AddAnchor("TOP", parent, 0, y)
    
    -- Create color preview window
    local colorPreview = container:CreateChildWidget("window", id .. "Preview", 0, true)
    colorPreview:SetExtent(60, 60)  -- Doubled size from original 60x30
    colorPreview:AddAnchor("CENTER", container, 0, 0)
    
    -- Create color background
     -- api.Log:Info("BetterBars: createColorPickButton - Attempting to create colorBG for " .. id)
    local colorBG = nil -- Initialize as nil
    local success, result = pcall(function()
        -- Check color components again just before use
        if color.r == nil or color.g == nil or color.b == nil then
            error("Missing RGB color components")
        end
        colorBG = colorPreview:CreateColorDrawable(
            color.r/255, 
            color.g/255, 
            color.b/255, 
            color.a or 1, 
            "background"
        )
    end)

    if not success or not colorBG then
         -- api.Log:Err("BetterBars: createColorPickButton - FAILED to create colorBG for id: " .. id .. ". Error: " .. tostring(result))
         -- Attempt to create a fallback red background to indicate error visually
         pcall(function()
             colorBG = colorPreview:CreateColorDrawable(1, 0, 0, 1, "background") 
         end)
         if not colorBG then return {} end -- Still failed, return empty
    else
         -- api.Log:Info("BetterBars: createColorPickButton - colorBG created successfully for id: " .. id)
    end

    colorBG:AddAnchor("TOPLEFT", colorPreview, 0, 0)
    colorBG:AddAnchor("BOTTOMRIGHT", colorPreview, 0, 0)
    
    -- Create border
    local border = colorPreview:CreateNinePartDrawable(TEXTURE_PATH.DEFAULT, "overlay")
    border:SetCoords(949, 199, 8, 8)
    border:SetInset(3, 3, 3, 3)
    border:SetColor(1, 1, 1, 0.5)
    border:AddAnchor("TOPLEFT", colorPreview, 0, 0)
    border:AddAnchor("BOTTOMRIGHT", colorPreview, 0, 0)
    
    -- Click handler for color preview
    function colorPreview:OnClick()
        -- Close existing popup if open
        if colorPopup then
            colorPopup:Show(false)
            colorPopup = nil
        end
        
        -- Create color popup
        colorPopup = api.Interface:CreateWidget("window", "colorPopup")
        colorPopup:SetExtent(350, 350)  -- Narrower and taller
        
        -- Position popup to the right of the main window
        colorPopup:AddAnchor("TOPLEFT", settingsWindow, "TOPRIGHT", 5, 0)
        
        -- =============================================
        -- POPUP BACKGROUND AND BORDER SECTION
        -- =============================================
        -- Add black background
        local popupBG = colorPopup:CreateColorDrawable(0, 0, 0, 1, "background")
        popupBG:AddAnchor("TOPLEFT", colorPopup, 0, 0)
        popupBG:AddAnchor("BOTTOMRIGHT", colorPopup, 0, 0)
        
        -- Add white border
        local popupBorder = colorPopup:CreateNinePartDrawable(TEXTURE_PATH.DEFAULT, "overlay")
        popupBorder:SetCoords(949, 199, 8, 8)
        popupBorder:SetInset(3, 3, 3, 3)
        popupBorder:SetColor(1, 1, 1, 0.5)  -- White border
        popupBorder:AddAnchor("TOPLEFT", colorPopup, 0, 0)
        popupBorder:AddAnchor("BOTTOMRIGHT", colorPopup, 0, 0)
        
        -- =============================================
        -- PRESET COLORS GRID SECTION
        -- =============================================
        -- Title for the popup
        local popupTitle = colorPopup:CreateChildWidget("label", "popupTitle", 0, true)
        popupTitle:SetText("Select a Color")
        popupTitle:AddAnchor("TOP", colorPopup, 0, 30)
        popupTitle.style:SetFontSize(FONT_SIZE.MIDDLE)
        popupTitle.style:SetAlign(ALIGN.CENTER)
        popupTitle.style:SetColor(1, 1, 1, 1)
        
        -- Create color grid for preset colors
        local colorGrid = colorPopup:CreateChildWidget("window", "colorGrid", 0, true)
        colorGrid:SetExtent(280, 210)  -- Adjusted height for 6 rows
        colorGrid:AddAnchor("TOP", popupTitle, "BOTTOM", 0, 40)
        
        -- Create color squares
        local squareSize = 24  -- Smaller squares
        local spacing = 2      -- Less spacing
        local squaresPerRow = 10  -- 10 squares per row
        
        for i, colorData in ipairs(colorPalette) do
            local row = math.floor((i-1) / squaresPerRow)
            local col = (i-1) % squaresPerRow
            
            local square = colorGrid:CreateChildWidget("window", "square" .. i, 0, true)
            square:SetExtent(squareSize, squareSize)
            square:AddAnchor("TOPLEFT", colorGrid, col * (squareSize + spacing) + 10, row * (squareSize + spacing) + 10)
            
            -- Color background
            local squareBG = square:CreateColorDrawable(
                colorData.r/255,
                colorData.g/255,
                colorData.b/255,
                colorData.a,
                "background"
            )
            squareBG:AddAnchor("TOPLEFT", square, 0, 0)
            squareBG:AddAnchor("BOTTOMRIGHT", square, 0, 0)
            
            -- White border that gets brighter on hover
            local squareBorder = square:CreateNinePartDrawable(TEXTURE_PATH.DEFAULT, "overlay")
            squareBorder:SetCoords(949, 199, 8, 8)
            squareBorder:SetInset(2, 2, 2, 2)
            squareBorder:SetColor(1, 1, 1, 0.1)  -- Subtle white border
            squareBorder:AddAnchor("TOPLEFT", square, 0, 0)
            squareBorder:AddAnchor("BOTTOMRIGHT", square, 0, 0)
            
            function square:OnClick()
                    colorBG:SetColor(colorData.r/255, colorData.g/255, colorData.b/255, colorData.a)
                    
                -- Reorder checks: check for "ehp" first
                if id:find("ehp") then
                    currentSettings.colors = currentSettings.colors or {}
                        currentSettings.colors.ehp = {
                            r = colorData.r,
                            g = colorData.g,
                            b = colorData.b,
                            a = colorData.a
                        }
                        settings.updateColors(currentSettings.colors)
                        settings.saveSettings()
                elseif id:find("hp") then
                        currentSettings.colors = currentSettings.colors or {}
                            currentSettings.colors.hp = {
                                r = colorData.r,
                                g = colorData.g,
                                b = colorData.b,
                                a = colorData.a
                            }
                    settings.updateColors(currentSettings.colors)
                    settings.saveSettings()
                elseif id:find("mp") then
                    currentSettings.colors = currentSettings.colors or {}
                        currentSettings.colors.mp = {
                            r = colorData.r,
                            g = colorData.g,
                            b = colorData.b,
                            a = colorData.a
                        }
                        settings.updateColors(currentSettings.colors)
                        settings.saveSettings()
                end
                
                hideColorPopup()
            end
            
            square:SetHandler("OnClick", square.OnClick)
            
            -- Add hover effect
            function square:OnEnter()
                squareBorder:SetColor(0, 0, 0, 0.8)  -- Bright white border on hover
            end
            
            function square:OnLeave()
                squareBorder:SetColor(1, 1, 1, 0.3)  -- Back to subtle border
            end
            
            square:SetHandler("OnEnter", square.OnEnter)
            square:SetHandler("OnLeave", square.OnLeave)
        end
        
        -- =============================================
        -- CUSTOM COLOR PICKER SECTION
        -- =============================================
        -- Custom color button to toggle the picker
        local customButton = colorPopup:CreateChildWidget("button", "customButton", 0, true)
        customButton:SetText("Custom Color")
        customButton:SetExtent(140, 30)
        customButton:AddAnchor("BOTTOM", colorPopup, 0, -62)
        ApplyButtonSkin(customButton, BUTTON_BASIC.DEFAULT)
        
        -- Custom color picker container (shows when Custom Color is clicked)
        local customColorPicker = colorPopup:CreateChildWidget("window", "customColorPicker", 0, true)
        customColorPicker:SetExtent(260, 210)  -- Match width with grid
        customColorPicker:RemoveAllAnchors()
        customColorPicker:AddAnchor("TOPLEFT", colorGrid, "TOPRIGHT", 39, -70)  -- Position to the right of color grid
        customColorPicker:Show(false)

        -- Add background for custom color picker
        local customBG = customColorPicker:CreateColorDrawable(0, 0, 0, 1, "background")
        customBG:AddAnchor("TOPLEFT", customColorPicker, 0, 0)
        customBG:AddAnchor("BOTTOMRIGHT", customColorPicker, 0, 0)
        
        -- Add border for custom color picker
        local customBorder = customColorPicker:CreateNinePartDrawable(TEXTURE_PATH.DEFAULT, "overlay")
        customBorder:SetCoords(949, 199, 8, 8)
        customBorder:SetInset(3, 3, 3, 3)
        customBorder:SetColor(1, 1, 1, 0.5)  -- White border
        customBorder:AddAnchor("TOPLEFT", customColorPicker, 0, 0)
        customBorder:AddAnchor("BOTTOMRIGHT", customColorPicker, 0, 0)

        -- =============================================
        -- CUSTOM COLOR RGB INPUTS SECTION
        -- =============================================
        -- Title for custom color section
        local customTitle = customColorPicker:CreateChildWidget("label", "customTitle", 0, true)
        customTitle:SetText("Custom RGB Values")
        customTitle:SetExtent(180, 35)
        customTitle:AddAnchor("TOP", customColorPicker, 0, 0)
        customTitle.style:SetFontSize(FONT_SIZE.MIDDLE)
        customTitle.style:SetAlign(ALIGN.CENTER)
        customTitle.style:SetColor(0.9, 0.9, 0.9, 1)
        
        -- RGB Values
        local currentRed = 0
        local currentGreen = 0
        local currentBlue = 0
        
        -- Create RGB inputs
        local function createColorInput(label, parent, yOffset, defaultValue, textColor)
            local container = parent:CreateChildWidget("window", label .. "Container", 0, true)
            container:SetExtent(200, 30)
            container:AddAnchor("TOP", parent, 0, yOffset)
            
            -- Background for this row
            local rowBG = container:CreateColorDrawable(0.15, 0.15, 0.15, 0.5, "background")
            rowBG:AddAnchor("TOPLEFT", container, 5, 0)
            rowBG:AddAnchor("BOTTOMRIGHT", container, -5, 0)
            
            -- Label
            local labelWidget = container:CreateChildWidget("label", label .. "Label", 0, true)
            labelWidget:SetText(label .. ":")
            labelWidget:SetExtent(30, 20)
            labelWidget:AddAnchor("LEFT", container, 20, 0)
            labelWidget.style:SetFontSize(FONT_SIZE.MIDDLE)
            labelWidget.style:SetColor(unpack(textColor))
            
            -- Input field with background
            local inputBG = container:CreateColorDrawable(0.1, 0.1, 0.1, 0.8, "background")
            inputBG:SetExtent(60, 22)
            inputBG:AddAnchor("LEFT", labelWidget, "RIGHT", 15, 0)
            
            -- Create the editbox using W_CTRL
            local input = W_CTRL.CreateEdit(label .. "Input", container)
            input:SetExtent(50, 20)
            input:AddAnchor("CENTER", inputBG, 0, 0)
            input:SetText(tostring(defaultValue))
            input:SetMaxTextLength(3)
            input.style:SetAlign(ALIGN.CENTER)
            
            -- Only allow numbers
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
        
        -- Create RGB inputs with more spacing
        local redInput = createColorInput("R", customColorPicker, 40, currentRed, {1, 0.4, 0.4, 1})
        local greenInput = createColorInput("G", customColorPicker, 80, currentGreen, {0.4, 1, 0.4, 1})
        local blueInput = createColorInput("B", customColorPicker, 120, currentBlue, {0.4, 0.4, 1, 1})
        
        -- Apply button with improved styling
        local applyButton = customColorPicker:CreateChildWidget("button", "applyButton", 0, true)
        applyButton:SetText("Apply")
        applyButton:SetExtent(100, 30)  -- Wider button
        applyButton:AddAnchor("TOP", blueInput, "BOTTOM", 0, 25)  -- More spacing
        ApplyButtonSkin(applyButton, BUTTON_BASIC.DEFAULT)
        
        -- Apply custom color
        function applyButton:OnClick()
            currentRed = tonumber(redInput:GetText()) or 0
            currentGreen = tonumber(greenInput:GetText()) or 0
            currentBlue = tonumber(blueInput:GetText()) or 0
            
            -- Set the color to the color preview
            colorBG:SetColor(currentRed/255, currentGreen/255, currentBlue/255, 1)
            
            -- Update settings - Reorder checks: check for "ehp" first
            if id:find("ehp") then
                    currentSettings.colors = currentSettings.colors or {}
                        currentSettings.colors.ehp = {
                            r = currentRed,
                            g = currentGreen,
                            b = currentBlue,
                            a = 1
                        }
                    settings.updateColors(currentSettings.colors)
                    settings.saveSettings()
            elseif id:find("hp") then
                    currentSettings.colors = currentSettings.colors or {}
                        currentSettings.colors.hp = {
                            r = currentRed,
                            g = currentGreen,
                            b = currentBlue,
                            a = 1
                        }
                    settings.updateColors(currentSettings.colors)
                    settings.saveSettings()
                elseif id:find("mp") then
                    currentSettings.colors = currentSettings.colors or {}
                        currentSettings.colors.mp = {
                            r = currentRed,
                            g = currentGreen,
                            b = currentBlue,
                            a = 1
                        }
                        settings.updateColors(currentSettings.colors)
                        settings.saveSettings()
                end
            
            hideColorPopup()
        end
            applyButton:SetHandler("OnClick", applyButton.OnClick)
        
        -- Toggle custom color picker
        function customButton:OnClick()
            customColorPicker:Show(not customColorPicker:IsVisible())
            
            -- If showing, update the values from the current color
            if customColorPicker:IsVisible() then
                -- Get current color values
                local r, g, b, a = colorBG:GetColor()
                currentRed = math.floor(r * 255)
                currentGreen = math.floor(g * 255)
                currentBlue = math.floor(b * 255)
                
                -- Update input fields
                redInput:SetText(tostring(currentRed))
                greenInput:SetText(tostring(currentGreen))
                blueInput:SetText(tostring(currentBlue))
            end
        end
        customButton:SetHandler("OnClick", customButton.OnClick)
        
        -- =============================================
        -- POPUP CONTROL BUTTONS SECTION
        -- =============================================
        -- Close button at the bottom
        local closeButton = colorPopup:CreateChildWidget("button", "closeButton", 0, true)
        closeButton:SetText("Close")
        closeButton:SetExtent(100, 30)
        closeButton:AddAnchor("BOTTOM", colorPopup, 0, -10)  -- Position at bottom
        ApplyButtonSkin(closeButton, BUTTON_BASIC.DEFAULT)
        
        function closeButton:OnClick()
            hideColorPopup()
        end
        
        closeButton:SetHandler("OnClick", closeButton.OnClick)
        
        -- Make popup visible and draggable
        colorPopup:Show(true)
            -- colorPopup:SetMovable(true)
            colorPopup:SetHandler("OnDragStart", colorPopup.StartMoving)
            colorPopup:SetHandler("OnDragStop", colorPopup.StopMovingOrSizing)
    end
    
    colorPreview:SetHandler("OnClick", colorPreview.OnClick)
    
    -- Add hover effect
    function colorPreview:OnEnter()
        border:SetColor(1, 1, 1, 1)
    end
    
    function colorPreview:OnLeave()
        border:SetColor(1, 1, 1, 0.5)
    end
    
    colorPreview:SetHandler("OnEnter", colorPreview.OnEnter)
    colorPreview:SetHandler("OnLeave", colorPreview.OnLeave)
    
    -- Add Debug Log End
     -- api.Log:Info("BetterBars: createColorPickButton END - id: " .. id)
    return { colorBG = colorBG }
end

-- Function to initialize settings page
local function initializeSettingsPage()
    if settingsWindow then
        settingsWindow:Show(true)
        return
    end
    
    -- Create the main window
        settingsWindow = api.Interface:CreateWindow("betterBarsSettingsWindow", "BetterBars Settings")
    
    if not settingsWindow then
        errorLog("Failed to create settings window")
        return
    end
    
    -- Set up window close handler
        function settingsWindow:OnHide()
            isSettingsPageOpened = false
            hideColorPopup()
        end
        settingsWindow:SetHandler("OnHide", settingsWindow.OnHide)
    
    -- Load current settings
            currentSettings = { colors = settings.getColors() }
    if not currentSettings.colors then
                currentSettings.colors = default_settings.colors
            end
    
    -- Configure window
        settingsWindow:SetWidth(300)
        settingsWindow:SetHeight(420) -- Keep increased height
    
    -- HP Color settings
    local hpLabel = settingsWindow:CreateChildWidget("label", "hpLabel", 0, true)
            hpLabel:SetText("Health Bar Color:")
            -- Revert Anchor and Style
            hpLabel:AddAnchor("TOP", settingsWindow, 0, 60)
            hpLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
            hpLabel.style:SetColor(0, 0, 0, 1) -- Original color
            hpLabel.style:SetAlign(ALIGN.CENTER) -- Original alignment
    
            -- Revert Color Button Creation - anchor to window, use original Y offset
            controls.hpColorButton = createColorPickButton("hpColorButton", settingsWindow, currentSettings.colors.hp or default_settings.colors.hp, 0, 80) 
            controls.hpColorButton.colorType = "hp"
    
    -- MP Color settings
    local mpLabel = settingsWindow:CreateChildWidget("label", "mpLabel", 0, true)
            mpLabel:SetText("Mana Bar Color:")
            -- Revert Anchor and Style
            mpLabel:AddAnchor("TOP", settingsWindow, 0, 160)
            mpLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
            mpLabel.style:SetColor(0, 0, 0, 1) -- Original color
            mpLabel.style:SetAlign(ALIGN.CENTER) -- Original alignment
    
             -- Revert Color Button Creation - anchor to window, use original Y offset
            controls.mpColorButton = createColorPickButton("mpColorButton", settingsWindow, currentSettings.colors.mp or default_settings.colors.mp, 0, 180) 
            controls.mpColorButton.colorType = "mp"
    
    -- EHP Color settings - Mimic MP section structure
    local ehpLabel = settingsWindow:CreateChildWidget("label", "ehpLabel", 0, true)
            ehpLabel:SetText("Enemy HP Color:")
            -- Use exact same styling and anchoring strategy as HP/MP
            ehpLabel:AddAnchor("TOP", settingsWindow, 0, 260) -- Position below MP Label
            ehpLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
            ehpLabel.style:SetColor(0, 0, 0, 1) -- Match HP/MP label color
            ehpLabel.style:SetAlign(ALIGN.CENTER) -- Match HP/MP label alignment
    
             -- Create button exactly like HP/MP, adjusting ID, color key, offset, and type
            controls.ehpColorButton = createColorPickButton("ehpColorButton", settingsWindow, currentSettings.colors.ehp or default_settings.colors.ehp, 0, 280) -- Position below EHP Label
            -- Ensure controls table entry exists before assigning colorType
            if controls.ehpColorButton then 
                 controls.ehpColorButton.colorType = "ehp" 
            else
                 -- api.Log:Err("BetterBars: Failed to assign colorType, ehpColorButton creation likely failed.")
            end
    
    -- =============================================
    -- MAIN SETTINGS BUTTONS SECTION
    -- =============================================
    -- Button container
    local buttonContainer = settingsWindow:CreateChildWidget("window", "buttonContainer", 0, true)
            buttonContainer:SetExtent(240, 40)
            buttonContainer:AddAnchor("BOTTOM", settingsWindow, 0, -40)
    
    -- Save button
            local saveButton = buttonContainer:CreateChildWidget("button", "saveButton", 0, true)
                saveButton:SetText("Save")
                saveButton:SetExtent(100, 30)
                saveButton:AddAnchor("LEFT", buttonContainer, 10, 0)
    ApplyButtonSkin(saveButton, BUTTON_BASIC.DEFAULT)
                saveButton:SetHandler("OnClick", saveSettings)
    
    -- Reset button
            local resetButton = buttonContainer:CreateChildWidget("button", "resetButton", 0, true)
                resetButton:SetText("Reset")
                resetButton:SetExtent(100, 30)
                resetButton:AddAnchor("RIGHT", buttonContainer, -10, 0)
    ApplyButtonSkin(resetButton, BUTTON_BASIC.DEFAULT)
                resetButton:SetHandler("OnClick", resetSettings)
    
    -- Make window draggable
        settingsWindow:SetMovable(true)
        settingsWindow:SetHandler("OnDragStart", settingsWindow.StartMoving)
        settingsWindow:SetHandler("OnDragStop", settingsWindow.StopMovingOrSizing)
    
    -- Center window on screen
        local screenWidth, screenHeight = api.Interface:GetScreenSize()
        local windowWidth, windowHeight = settingsWindow:GetExtent()
        settingsWindow:SetOffset((screenWidth - windowWidth) / 2, (screenHeight - windowHeight) / 2)
    
    -- Default to hidden
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
end

-- Return the settings page module
local settings_page = {
    openSettingsWindow = openSettingsWindow,
    unload = unload,
    Load = initializeSettingsPage,
    Unload = unload
}

return settings_page 