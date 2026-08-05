local default_settings = {
    colors = {
        -- The newer client's own palette, read out of its gauge atlas
        -- (ui/common/hud_gauge.g): hp_green, mp_blue and hp_red verbatim.
        -- Its bar texture is near-white (219..251 of 255), so these colours
        -- carry essentially the whole look - which is why the originals
        -- (30/180/30 and a 30/180/200 cyan) read so differently.
        hp = {
            r = 127,  -- Green
            g = 189,
            b = 28,
            a = 1
        },
        mp = {
            r = 50,   -- Blue
            g = 150,
            b = 255,
            a = 1
        },
        ehp = {
            r = 199,  -- Red
            g = 80,
            b = 57,
            a = 1
        },
        -- The custom cast bar's fill; warm gold, the genre standard
        cast = {
            r = 230,
            g = 180,
            b = 60,
            a = 1
        }
    },
    -- Label format: "both" (current + percent), "current", "percent", "hide"
    labelFormat = "both",
    -- Label font size
    labelFontSize = 11,
    -- Bar dimensions
    -- The newer client's fill areas measure exactly 300x17 (HP) and 300x13 (MP)
    -- in its gauge atlas, so these match it. The old mp default of 15 made the
    -- mana bar noticeably chunkier than retail's.
    barHeight = {
        hp = 17,
        mp = 13,
    },
    -- Background. 1.0 draws the reference's cell at its own alphas - border 153,
    -- ramp 171..130, interior 128 - which is what it does itself. 1.1 pushes them
    -- a step past that, which reads deeper against bright scenery than the
    -- reference does over its own frame art.
    backgroundOpacity = 1.1,

    -- Custom fill texture drawn over the bar colour. The PNGs live in
    -- BetterBars/textures/ and are greyscale, so the bar colour tints them:
    -- the texture supplies shading, the colour setting supplies the hue.
    -- "none" leaves the vanilla flat fill.
    barTexture = "bar_retail",
    -- Font for the level number on the frames (client font path). The
    -- vanilla ornate one is ui/font/sd_leeyagil.ttf.
    levelFont = "ui/font/yd_ygo540.ttf",
    -- Toggles
    showHostilityColor = true,
    -- Custom cast bar drawn over the vanilla one (which the addon api cannot
    -- touch) - restyled to match the unit frames.
    showCastBar = true,
    -- Show the HP number on housing targets. The addon api cannot read house
    -- health, so the text shown is the game's own label; off keeps it blank.
    showHousingHP = true,
    -- false is the reference geometry: each bar carries its own border and the
    -- two sit directly against each other, which IS the separation. true leaves
    -- one clear row between them instead - a preference, not the reference look.
    showBarSeparation = false,
    
    -- Info labels (class, GS, guild) - off by default, opt-in; the tuned
    -- layout below is ready the moment they are switched on
    showClass = false,
    showGearScore = false,
    showGuild = false,
    infoFontSize = 12,
    -- Per-item anchor offsets, applied on top of each item's base position
    -- (class/guild above the bars at name height, gear score below). These
    -- are the author's tuned layout: guild left of the name row, class right
    -- of it, gear score up beside the level.
    -- Each item also carries its own font size.
    infoOffsets = {
        class = { x = 85,  y = -20, size = 12 },
        guild = { x = -70, y = -20, size = 12 },
        gs    = { x = 132, y = -40, size = 12 },
    },
    -- Default engine text shadow on the HP/MP value labels (the same shading
    -- the level and name use)
    labelShadow = false,
    -- Same shadow for the info labels (class, GS, guild)
    infoShadow = false,

    -- Set once the welcome card has been dismissed, so it never shows again.
    infoCardSeen = false,
}

return default_settings
