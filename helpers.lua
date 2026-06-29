local api = require("api")
local helpers = {}

local settingsOpened = false

-- Functions for working with UI
function helpers.createLabel(id, parent, text, offsetX, offsetY, fontSize)
    local label = W_CTRL.CreateLabel(id, parent)
    label:AddAnchor("TOPLEFT", offsetX, offsetY)
    label:SetExtent(255, 20)
    label:SetText(text)
    
    -- Set color if available
    if FONT_COLOR and FONT_COLOR.TITLE then
        label.style:SetColor(FONT_COLOR.TITLE[1], FONT_COLOR.TITLE[2], FONT_COLOR.TITLE[3], 1)
    else
        label.style:SetColor(0.87, 0.69, 0, 1) -- Gold color by default
    end
    
    label.style:SetAlign(ALIGN.LEFT)
    label.style:SetFontSize(fontSize or 18)
    
    return label
end

function helpers.createEdit(id, parent, text, offsetX, offsetY)
    local field = W_CTRL.CreateEdit(id, parent)
    field:SetExtent(100, 20)
    field:AddAnchor("TOPLEFT", offsetX, offsetY)
    field:SetText(tostring(text))
    field.style:SetColor(0, 0, 0, 1)
    field.style:SetAlign(ALIGN.LEFT)
    field:SetInitVal(tonumber(text) or 0)
    
    return field
end

function helpers.createButton(id, parent, text, offsetX, offsetY, width, onClick)
    local button = W_CTRL.CreateButton(id, parent)
    button:AddAnchor("TOPLEFT", offsetX, offsetY)
    button:SetExtent(width or 95, 26)
    button:SetText(text)
    
    if onClick then
        button:SetHandler("OnClick", onClick)
    end
    
    return button
end

function helpers.createCheckbox(id, parent, text, offsetX, offsetY)
    local checkBox = api._Library.UI.CreateCheckButton(id, parent, text)
    checkBox:AddAnchor("TOPLEFT", offsetX, offsetY)
    checkBox:SetButtonStyle("default")
    return checkBox
end

-- Create color pick button
function helpers.createColorPickButton(id, parent, color, offsetX, offsetY)
    -- Create simple color button
    local colorButton = W_CTRL.CreateButton(id, parent)
    colorButton:AddAnchor("TOPLEFT", parent, offsetX, offsetY)
    colorButton:SetExtent(80, 25)
    colorButton:SetText("Color")
    
    -- Create color background
    local r, g, b, a = 1, 1, 1, 1
    if color then
        -- Convert RGB values from 0-255 to 0-1
        r = (color.r or 255) / 255
        g = (color.g or 255) / 255
        b = (color.b or 255) / 255
        a = color.a or 1
    end
    
    local colorBG = colorButton:CreateColorDrawable(r, g, b, a, "background")
    colorBG:AddAnchor("TOPLEFT", colorButton, 1, 1)
    colorBG:AddAnchor("BOTTOMRIGHT", colorButton, -1, -1)
    colorButton.colorBG = colorBG
    
    -- Add click handler for color selection
    function colorButton:OnClick()
        if F_COLOR_PICKER and F_COLOR_PICKER.ShowColorPicker then
            F_COLOR_PICKER.ShowColorPicker(
                r, g, b, a, 
                function(newR, newG, newB, newA)
                    colorBG:SetColor(newR, newG, newB, newA)
                    r, g, b, a = newR, newG, newB, newA
                    if colorButton.SelectedProcedure then
                        colorButton:SelectedProcedure(newR, newG, newB, newA)
                    end
                end
            )
        else
            -- Simple fallback if color picker isn't available
            -- Toggle between a few colors
            local colors = {
                {1, 0, 0, 1}, -- Red
                {0, 1, 0, 1}, -- Green
                {0, 0, 1, 1}, -- Blue
                {1, 1, 0, 1}, -- Yellow
                {0, 1, 1, 1}, -- Cyan
                {1, 0, 1, 1}, -- Magenta
            }
            
            local currentIndex = 1
            for i, c in ipairs(colors) do
                if math.abs(c[1] - r) < 0.1 and math.abs(c[2] - g) < 0.1 and math.abs(c[3] - b) < 0.1 then
                    currentIndex = i
                    break
                end
            end
            
            currentIndex = currentIndex % #colors + 1
            r, g, b, a = unpack(colors[currentIndex])
            colorBG:SetColor(r, g, b, a)
            
            if colorButton.SelectedProcedure then
                colorButton:SelectedProcedure(r, g, b, a)
            end
        end
    end
    
    colorButton:SetHandler("OnClick", colorButton.OnClick)
    
    return colorButton
end

-- Functions for managing settings state
function helpers.setSettingsPageOpened(state) 
    settingsOpened = state 
end

function helpers.getSettingsPageOpened() 
    return settingsOpened 
end

return helpers 