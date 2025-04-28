local api = require("api")
local default_settings = require("BetterBars/default_settings")

local settings = {}

-- Load settings from saved variables
local function loadSettings()
    local saved = api.GetSettings("BetterBars")
    
    -- Initialize settings if they don't exist
    if not saved then
        saved = {}
    end
    
    -- Make sure colors exist
    if not saved.colors then
        saved.colors = {}
    end
    
    -- Make sure hp colors exist and have proper values
    if not saved.colors.hp then
        saved.colors.hp = default_settings.colors.hp
    else
        -- Ensure all required hp color components exist
        if not saved.colors.hp.r then saved.colors.hp.r = default_settings.colors.hp.r end
        if not saved.colors.hp.g then saved.colors.hp.g = default_settings.colors.hp.g end
        if not saved.colors.hp.b then saved.colors.hp.b = default_settings.colors.hp.b end
        if not saved.colors.hp.a then saved.colors.hp.a = default_settings.colors.hp.a end
    end
    
    -- Make sure mp colors exist and have proper values
    if not saved.colors.mp then
        saved.colors.mp = default_settings.colors.mp
    else
        -- Ensure all required mp color components exist
        if not saved.colors.mp.r then saved.colors.mp.r = default_settings.colors.mp.r end
        if not saved.colors.mp.g then saved.colors.mp.g = default_settings.colors.mp.g end
        if not saved.colors.mp.b then saved.colors.mp.b = default_settings.colors.mp.b end
        if not saved.colors.mp.a then saved.colors.mp.a = default_settings.colors.mp.a end
    end
    
    -- Make sure ehp colors exist and have proper values
    if not saved.colors.ehp then
        saved.colors.ehp = default_settings.colors.ehp
    else
        -- Ensure all required ehp color components exist
        if not saved.colors.ehp.r then saved.colors.ehp.r = default_settings.colors.ehp.r end
        if not saved.colors.ehp.g then saved.colors.ehp.g = default_settings.colors.ehp.g end
        if not saved.colors.ehp.b then saved.colors.ehp.b = default_settings.colors.ehp.b end
        if not saved.colors.ehp.a then saved.colors.ehp.a = default_settings.colors.ehp.a end
    end
    
    settings = saved
    return saved
end

-- Save current settings to saved variables
local function saveSettings()
    -- Create a deep copy of the current settings
    local settingsToSave = {
        colors = {
            hp = {
                r = settings.colors.hp.r,
                g = settings.colors.hp.g,
                b = settings.colors.hp.b,
                a = settings.colors.hp.a
            },
            mp = {
                r = settings.colors.mp.r,
                g = settings.colors.mp.g,
                b = settings.colors.mp.b,
                a = settings.colors.mp.a
            },
            ehp = {
                r = settings.colors.ehp.r,
                g = settings.colors.ehp.g,
                b = settings.colors.ehp.b,
                a = settings.colors.ehp.a
            }
        }
    }
    
    -- Update the global settings table
    -- _G["BetterBars_Settings"] = settingsToSave
    
    -- Force an immediate save
    api.SaveSettings()
    
    -- Notify the UI to update
    api.Emit("BETTERBARS_SETTINGS_UPDATED")
    api.Emit("UI_RELOADED")
end

-- Get current colors
local function getColors()
    if not settings.colors then
        settings.colors = default_settings.colors
    end
    return settings.colors
end

-- Update colors from the given values
local function updateColors(newColors)
    if not settings.colors then
        settings.colors = {}
    end
    
    -- Update HP colors
    if newColors.hp then
        settings.colors.hp = {
            r = newColors.hp.r,
            g = newColors.hp.g,
            b = newColors.hp.b,
            a = newColors.hp.a or 1
        }
    end
    
    
    -- Update MP colors
    if newColors.mp then
        settings.colors.mp = {
            r = newColors.mp.r,
            g = newColors.mp.g,
            b = newColors.mp.b,
            a = newColors.mp.a or 1
        }
    end
    
    -- Update EHP colors
    if newColors.ehp then
        settings.colors.ehp = {
            r = newColors.ehp.r,
            g = newColors.ehp.g,
            b = newColors.ehp.b,
            a = newColors.ehp.a or 1
        }
    end
end

-- Reset all settings to defaults
local function resetToDefaults()
    settings.colors = default_settings.colors
    saveSettings()
end

-- Initialize settings
loadSettings()

return {
    loadSettings = loadSettings,
    saveSettings = saveSettings,
    getColors = getColors,
    updateColors = updateColors,
    resetToDefaults = resetToDefaults
} 