local default_settings = {
    colors = {
        hp = {
            r = 30,  -- Red component (Lower for Darker/More Green)
            g = 180,  -- Green component (Slightly Lower for Darker)
            b = 30,  -- Blue component (Lower for Darker/More Green)
            a = 1     -- Alpha (opacity)
        },
        mp = {
            r = 30,   -- Red component (Low for Cyan)
            g = 180,  -- Green component (High for Cyan)
            b = 200,  -- Blue component (High for Cyan)
            a = 1     -- Alpha (opacity)
        },
        ehp = {
            r = 255,  -- Red component (Default Red)
            g = 0,    -- Green component
            b = 0,    -- Blue component
            a = 1     -- Alpha (opacity)
        }
    }
}

return default_settings 