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
        },
        -- No abyssal colour since 3.1: the charge pips are plain authored
        -- artwork. The settings.lua migration still nils the key out of old
        -- saves, and nothing reads or refills it any more.
    },
    -- Label format: "both" (current + percent), "current", "percent", "hide"
    labelFormat = "both",
    -- Label font size
    labelFontSize = 11,
    -- Bar dimensions.
    --
    -- These are BAR heights, applied straight through with SetHeight, and the
    -- fill spans the whole bar - so the height is also the fill height.
    --
    -- 17 and 13 are the reference's own fill rects, which is exactly what the
    -- shipped sprites measure (bar_retail.png is 300x17, bar_retail_mp.png is
    -- 300x13). At these sizes ApplyFillTexture's SetCoords(0,0,300,17) maps one
    -- source pixel to one screen pixel, so the sprite's bright top and bottom
    -- lips stay sharp instead of being blurred through a resample.
    --
    -- Note this is 2px under AAC's native HP bar of 19. With the backdrop
    -- outset by 2 the whole visual box is 21, so it reads 1px proud of the
    -- native slot top and bottom. Set hp = 15 instead if matching the frame
    -- art's 19px slot matters more than sprite-exact proportions.
    barHeight = {
        hp = 17,
        mp = 13,
    },
    -- Background. 1.0 draws the reference's cell at its own alphas - border 153,
    -- ramp 171..130, interior 128 - which is what it does itself. 1.1 pushes them
    -- a step past that, which reads deeper against bright scenery than the
    -- reference does over its own frame art.
    backgroundOpacity = 1.1,

    -- Custom fill texture drawn over the bar colour: the extracted retail
    -- sprite pair (bar_retail / bar_retail_mp) in BetterBars/textures/. They
    -- are greyscale, so the bar colour tints them - the texture supplies the
    -- shading, the colour setting supplies the hue. "none" leaves the vanilla
    -- flat fill.
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
    -- Restyle the abyssal charge bar (the client's bubble action bar). Off
    -- restores the client's own bubble art. The bar only exists at all for
    -- classes with the high-ability feature set, so this is a no-op otherwise.
    -- Opt-in: this replaces artwork the player did not ask us to touch, and it
    -- is the one part of the addon that is not a unit frame, so an install
    -- looks like vanilla-plus-frames until it is switched on deliberately.
    showAbyssal = false,
    -- Pip diameter, in the same units as the client's cell (49x49 with a 2px
    -- gap, bubble_action_bar_view.lua:1-4). The slider runs 8-69: past 49 the
    -- pips overhang the invisible slots, which is safe because spacing follows
    -- pip size rather than the client's pitch. 35 is the original hand-picked
    -- size, which sat 7 in from each side.
    abyssalSize = 35,
    -- INERT. The MP bar is no longer re-anchored at all - it stays where AAC
    -- puts it, like every other part of the frame. Kept so existing saves that
    -- carry the key merge cleanly; nothing reads it.
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
