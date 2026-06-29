local default_settings = {
    colors = {
        hp = {
            r = 30,   -- Green
            g = 180,
            b = 30,
            a = 1
        },
        mp = {
            r = 30,   -- Cyan
            g = 180,
            b = 200,
            a = 1
        },
        ehp = {
            r = 255,  -- Red
            g = 0,
            b = 0,
            a = 1
        }
    },
    -- Label format: "both" (current + percent), "current", "percent", "hide"
    labelFormat = "both",
    -- Label font size
    labelFontSize = 14,
    -- Bar dimensions
    barHeight = {
        hp = 17,
        mp = 15,
    },
    -- Background
    backgroundOpacity = 0.6,
    -- Toggles
    showHostilityColor = true,
    showBarSeparation = true,
}

return default_settings
