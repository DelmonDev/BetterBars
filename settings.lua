local api = require("api")
local default_settings = require("BetterBars/default_settings")

local settings = {}

-- Deep merge saved settings with defaults (nil-checks preserve false)
local function mergeSettings(saved)
    saved = saved or {}
    
    -- Colors
    if not saved.colors then saved.colors = {} end
    for _, key in ipairs({"hp", "mp", "ehp"}) do
        if not saved.colors[key] then
            saved.colors[key] = default_settings.colors[key]
        else
            for _, comp in ipairs({"r", "g", "b", "a"}) do
                if saved.colors[key][comp] == nil then
                    saved.colors[key][comp] = default_settings.colors[key][comp]
                end
            end
        end
    end
    
    -- Label format
    if saved.labelFormat == nil then
        saved.labelFormat = default_settings.labelFormat
    end
    -- Label font size
    if saved.labelFontSize == nil then
        saved.labelFontSize = default_settings.labelFontSize
    end
    
    -- Bar height
    if not saved.barHeight then
        saved.barHeight = { hp = default_settings.barHeight.hp, mp = default_settings.barHeight.mp }
    else
        if saved.barHeight.hp == nil then saved.barHeight.hp = default_settings.barHeight.hp end
        if saved.barHeight.mp == nil then saved.barHeight.mp = default_settings.barHeight.mp end
    end
    
    -- Background
    if saved.backgroundOpacity == nil then
        saved.backgroundOpacity = default_settings.backgroundOpacity
    end
    
    -- Toggles
    if saved.showHostilityColor == nil then
        saved.showHostilityColor = default_settings.showHostilityColor
    end
    if saved.showBarSeparation == nil then
        saved.showBarSeparation = default_settings.showBarSeparation
    end
    
    return saved
end

-- Load settings from saved variables
local function loadSettings()
    local saved = api.GetSettings("BetterBars")
    settings = mergeSettings(saved or {})
    return settings
end

-- Save current settings (syncs local table into engine table for reliable persistence)
local function saveSettings()
    local engineTable = api.GetSettings("BetterBars")
    if not engineTable then
        engineTable = {}
    end
    -- Copy our local settings into the engine's tracked table
    engineTable.colors = settings.colors
    engineTable.labelFormat = settings.labelFormat
    engineTable.labelFontSize = settings.labelFontSize
    engineTable.barHeight = settings.barHeight
    engineTable.backgroundOpacity = settings.backgroundOpacity
    engineTable.showHostilityColor = settings.showHostilityColor
    engineTable.showBarSeparation = settings.showBarSeparation
    api.SaveSettings()
    api.Emit("BETTERBARS_SETTINGS_UPDATED")
end

-- Get full settings table
local function getSettings()
    return settings
end

-- Get colors only (backward compat)
local function getColors()
    if not settings.colors then
        settings.colors = default_settings.colors
    end
    return settings.colors
end

-- Update colors from given values
local function updateColors(newColors)
    if not settings.colors then
        settings.colors = {}
    end
    for _, key in ipairs({"hp", "mp", "ehp"}) do
        if newColors[key] then
            settings.colors[key] = {
                r = newColors[key].r,
                g = newColors[key].g,
                b = newColors[key].b,
                a = newColors[key].a or 1
            }
        end
    end
end

-- Update a single non-color setting
local function updateSetting(key, value)
    settings[key] = value
end

-- Reset all settings to defaults
local function resetToDefaults()
    settings = mergeSettings({})
    saveSettings()
end

-- Initialize settings
loadSettings()

return {
    loadSettings = loadSettings,
    saveSettings = saveSettings,
    getSettings = getSettings,
    getColors = getColors,
    updateColors = updateColors,
    updateSetting = updateSetting,
    resetToDefaults = resetToDefaults
}
