local BetterBars = {
  name = "BetterBars",
  -- Keep in sync with ADDON_VERSION in settings_page.lua (the credit label).
  -- Deliberately NOT read via require: pulling settings_page in at parse
  -- time drags the settings module along BEFORE the engine's settings store
  -- is ready - api.GetSettings then hands back a detached empty table, the
  -- whole session runs on defaults (welcome card included), and the first
  -- save overwrites the player's real file. That was the every-login reset.
  version = "3.1",
  author = "Dehling",
  desc = "Improves the look of vanilla unit frames"
}

-- Damage-trail (afterImage) colours.
--
-- These start as the old flat greys and are replaced at runtime by
-- RefreshAfterImageColors below. The newer client does not use a grey trail: it
-- draws the trail with the SAME colour key as the fill, resolved through a
-- second, darker palette, so the trail is a dark version of whatever the bar is
-- rather than a neutral smear. Measured from its gauge atlas:
--
--     fill 127,189,28 (green) -> trail  43,92,3
--     fill 199,80,57  (red)   -> trail 107,23,17
--
-- Per-channel those ratios are all over the place, but the LUMINANCE ratio is
-- 0.44 and 0.42 - near enough constant. So the trail is derived by scaling the
-- bar colour to ~43% luminance, which reproduces the two measured pairs closely
-- and, unlike copying the palette outright, still works for any colour the user
-- picks in the settings window.
local AFTERIMAGE_TRAIL_LUMA = 0.43

-- Aborts the enclosing pcall. The addon sandbox provides neither error() nor
-- assert(), so indexing a nil is the only way addon code can raise on purpose.
-- The old code called error() directly, which "worked" only because calling
-- the nil global ALSO throws - the texture fallback paths were riding on an
-- accident. Same behaviour, now by intent.
local function BBFail()
    local nothing
    return nothing.forced_failure
end

local LARGE_BAR_COORDS = { 0, 120, 300, 19 }
local SMALL_BAR_COORDS = { 301, 120, 150, 19 }


-- STATUSBAR_STYLE overrides.
--
-- Each entry gets its OWN afterImage tables rather than sharing one pair.
-- Sharing them was a real bug: the game re-calls ApplyBarTexture on its own
-- schedule (target change, HP change, ApplyFrameStyle), and it reads whichever
-- colours the shared table happened to hold - so a hostile target repainting
-- would stamp its dark red trail onto the player's own bar. Per-entry tables
-- mean the game picks up the right trail for whichever style it applies.
--
-- The tables are filled by RefreshAfterImageColors once colours are known;
-- these initial greys only matter for the moments before the first refresh.
local function newTrail()
    return { 0.235, 0.235, 0.235, 1 }
end

local HP_STYLE_KEYS = {
    L_HP_FRIENDLY = "friendly", S_HP_FRIENDLY = "friendly",
    L_HP_HOSTILE  = "hostile",  S_HP_HOSTILE  = "hostile",
    L_HP_NEUTRAL  = "neutral",  S_HP_NEUTRAL  = "neutral",
    -- "Preemptive strike": the unit was first hit by someone who is not you or
    -- your team, so the kill and its loot are not yours. The client swaps to
    -- these styles for it (unitframe.lua:86-94, gated on
    -- X2Unit:IsFirstHitByMeOrMyTeam("target") returning false while in combat)
    -- and draws them from a separate atlas row - y=100, against hostile's y=40.
    --
    -- Without them here the style carries no bbKey, so the recolour hook
    -- ignores it and UpdateFrameStyles then paints plain enemy red over the
    -- top: the distinction the client is trying to show is erased.
    L_HP_PREEMTIVE_STRIKE = "preemptive",
    S_HP_PREEMTIVE_STRIKE = "preemptive",
}
local MP_STYLE_KEYS = { L_MP = true, S_MP = true }

-- Mutated IN PLACE, never replaced. ApplyBarTexture stores the style table
-- reference as the bar's textureInfo (statusbar_view.lua:177), and on every HP
-- drop the game re-reads textureInfo.afterImage_color_up and repaints the trail
-- from it (unitframe.lua:117-120). The player bar is styled once at UI creation
-- (player.lua:120) - BEFORE this addon loads - so replacing the table here left
-- that bar's textureInfo pointing at the old one with the stock dark-green
-- trail: every hit repainted the player's trail green while restyled-on-demand
-- frames (target, targettarget) picked up the new tables and worked. Keeping
-- the table identity means stale references see the custom colours too.
local function restyleInPlace(name, key)
    local style = STATUSBAR_STYLE[name] or {}
    STATUSBAR_STYLE[name] = style
    style.coords = (string.sub(name, 1, 2) == "L_") and LARGE_BAR_COORDS or SMALL_BAR_COORDS
    style.afterImage_color_up = newTrail()
    style.afterImage_color_down = newTrail()
    -- Read back by the ApplyBarTexture wrapper to learn which style the
    -- game just chose, instead of the addon re-deriving hostility itself
    style.bbKey = key
end
for name, _ in pairs(HP_STYLE_KEYS) do
    restyleInPlace(name, HP_STYLE_KEYS[name])
end
for name, _ in pairs(MP_STYLE_KEYS) do
    restyleInPlace(name, "mp")
end

local FrameLabels = {}
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Custom fill texture
--
-- Loose PNGs are loaded with SetTgaTexture and a path relative to the client's
-- working directory - the same route TrackThatPlease uses for its recording
-- icon, and the client itself for user images (x2ui/ucc/ucc.lua).
--
-- The drawable is attached with AddAnchorChildToBar, which anchors to the bar's
-- FILL rather than to the bar window. That is what makes the texture grow and
-- shrink with the value instead of covering the empty remainder; the engine does
-- the tracking, so no update loop is needed. The client uses the same call to
-- pin the casting bar's leading-edge glow (x2ui/components/bar.lua:24).
--
-- The PNGs are greyscale so SetColor tints them: the texture carries the
-- shading, the colour setting carries the hue.
-- Forward declaration: ColorBarForKey (defined above ApplyFillTexture so the
-- hook reads in order) calls it before its definition point.
local ApplyFillTexture

local BAR_TEXTURE_DIR = "../Addon/BetterBars/textures/"

-- Textures that ship a separate MP variant.
--
-- The newer client does not reuse one fill sprite for both bars: its hp sprite
-- (300x17) ramps 219..251 while its mp sprite (300x13) ramps 236..253 - half the
-- depth. Using the HP ramp on the mana bar gives it about twice the shading it
-- should have, so the extracted pair is kept as a pair.
local BAR_TEXTURE_MP_VARIANT = { bar_retail = true }

-- Source size per texture.
--
-- The extracted pair are the reference sprites at their native 300x17 and
-- 300x13 rather than a derived ramp. That matters: the sprite is not a pure
-- vertical gradient - its ends are bright white caps fading into a darker
-- middle (x=0 is 255 throughout, x=50 bottoms out at 209), and averaging the
-- columns into a 1-D ramp threw that structure away. Native size also keeps the
-- 1px bright top and bottom lips sharp, where resampling through 32 rows and
-- back down to 17 blurred them.
--
-- The retail pair is all that ships as of 3.1: the five generated styles it
-- replaced (flat, gloss, sheen, striped, tube) are gone. The 64x32 fallback
-- below is what an unlisted name gets, so a PNG dropped into textures/ by hand
-- still draws without a code change.
local BAR_TEXTURE_DEFAULT_W, BAR_TEXTURE_DEFAULT_H = 64, 32
local BAR_TEXTURE_SIZE = {
    bar_retail    = { 300, 17 },
    bar_retail_mp = { 300, 13 },
}

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--Color Variables
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Define default colors (will be overwritten by settings)
-- Placeholders until UpdateColorsFromSettings loads the real values. These
-- mirror default_settings.colors, so anything painted before the settings
-- load (as the pet frames once were) still looks right instead of the old
-- pink/purple placeholders bleeding through.
local HP_COLORS = { 127 / 255, 189 / 255, 28 / 255, 1 }
local EHP_COLORS = { 199 / 255, 80 / 255, 57 / 255, 1 }
local MP_COLORS = { 50 / 255, 150 / 255, 255 / 255, 1 }
local CAST_COLORS = { 230 / 255, 180 / 255, 60 / 255, 1 }

-- Preemptive-strike colour: derived from the enemy colour, not configured
-- separately, so it tracks whatever the player picks.
--
-- The transform is taken from the client's own pair. statusbar_style.lua gives
-- L_HP_HOSTILE a trail of (223,69,69) and L_HP_PREEMTIVE_STRIKE (202,110,105).
-- Pulling each channel toward the brightest one by 0.70 and then scaling by
-- 0.91 turns the first into (203,105,105) - the second, near enough, and its
-- small red/green asymmetry looks hand-tuned rather than derived.
--
-- So it is the same hue, desaturated and very slightly darkened: a duller,
-- flatter red that reads clearly as "not your kill" beside a live enemy bar.
-- Lower PREEMPT_VAL to deepen it further; that is the knob.
local PREEMPT_SAT = 0.70
local PREEMPT_VAL = 0.91

local function DerivePreemptColors(c)
    local mx = math.max(c[1] or 0, c[2] or 0, c[3] or 0)
    local function ch(v)
        return (mx - (mx - (v or 0)) * PREEMPT_SAT) * PREEMPT_VAL
    end
    return { ch(c[1]), ch(c[2]), ch(c[3]), c[4] or 1 }
end

local PREEMPT_COLORS = DerivePreemptColors(EHP_COLORS)

-- UI scale, and why any of this needs to care about it.
--
-- Defined HERE, above everything geometric, because these are locals: Lua only
-- sees a local from its declaration point onward, so a helper declared further
-- down is simply nil to the code above it - which is exactly how the addon
-- failed to load with "attempt to call global 'Snap'".
--
-- The client scales the whole UI tree by one engine-level factor
-- (UIParent:SetUIScale / GetUIScale). Widget offsets and extents are in UI
-- units; device pixels = UI units * scale. The option slider runs 40..160 in
-- steps of 10, and two of its stops are deliberately NOT round -
-- F_LAYOUT.GetUIScaleValueByOptionWindowValue maps "80" to 0.85 and "90" to
-- 0.93 - and the default is 0.85 on any resolution below 1280x864
-- (screen_option.lua:7-13). A fractional factor is the norm, not an edge case.
--
-- It matters because the flat backdrop is built from 1px COLOUR RECTANGLES, and
-- the client never does that. Its own unit frames contain no CreateColorDrawable
-- and no SetHeight(1) anywhere - every border, divider and shadow is a ninepart
-- or threepart TEXTURE cell out of the atlas, and a texture resamples smoothly
-- at any scale. A 1-UI-unit rectangle at 0.85 is 0.85 device pixels and
-- rasterises to 0 or 1 depending where it lands: a border row that exists along
-- part of a bar and vanishes along the rest.
local function UIScale()
    local s
    pcall(function() s = api.Interface:GetUIScale() end)
    if type(s) ~= "number" or s <= 0 then return 1 end
    return s
end

-- Px FIXES a size in device pixels: "2px gap" stays 2 screen pixels at any
-- scale. Same arithmetic as the client's own F_LAYOUT.CalcDontApplyUIScale(v) =
-- v / GetUIScale(), which is what it uses wherever something must be a fixed
-- size on screen. Used for the things that cannot scale below a pixel without
-- disappearing - border thickness, ramp rows, the outset, the gap, the shift.
local function Px(n)
    return n / UIScale()
end

-- Snap keeps a size in UI UNITS, so it still grows with the UI the way the
-- client's own layout does (hpBar:SetHeight(19)), but nudges its edges onto the
-- pixel grid. Used for bar heights and the anchor Y.
--
-- Bars need this rather than Px: fixing them in device pixels would freeze them
-- while the name, level and wing kept scaling, and they would desync at
-- anything but 100%. But a 17-unit bar at 1.3 is 22.1 device pixels, and that
-- trailing .1 puts its bottom edge mid-pixel - after which no amount of
-- device-exact border arithmetic can draw a crisp line against it, because the
-- thing the line is anchored to is itself half a pixel out.
--
-- Lua 5.1 has no math.round; floor(x + 0.5) is it.
local function Snap(v)
    local s = UIScale()
    return math.floor(v * s + 0.5) / s
end

-- Bar geometry: vanilla, untouched.
--
-- AAC builds each bar as a wrapper window whose statusbars sit flush to it
-- (0,0 / 0,0), and hangs the frame's entire ornamentation off that wrapper -
-- heirWing, bg, line, combatIcon, heirFrame, reporterIcon, buffWindow and
-- lootIcon all anchor to hpBar/mpBar (unitframe_view.lua:51-132,
-- player.lua:74-133, target.lua:104-197).
--
-- So the bar keeps AAC's geometry exactly: the configured height IS the wrapper
-- height, and the fill spans the whole wrapper at its full 300px. Nothing is
-- inset and nothing is nudged, which is why every piece of furniture lines up -
-- none of it ever has to be compensated for.
--
-- Two earlier schemes are gone. The statusbar used to be inset 2px so the
-- backdrop's border ring would show around it (wrapper = fill + 4), and before
-- that the whole box was slid by (-5, -2) with the right edge stretched +7 to
-- hit the newer client's exact fill rect. The border is now drawn by outsetting
-- the BACKDROP around the bar instead (BAR_BG_OUTSET below) - which is the same
-- trick AAC uses for its own frame.bg, anchored a pixel outside the bars.
--
-- The anchors are re-stated rather than simply left alone. These are the game's
-- own widgets and they outlive an addon reload, so a bar inset by a previous
-- version of this addon would keep that inset until the client next rebuilt the
-- frame. Writing vanilla back is idempotent and upgrade-safe.
local function ApplyBarBox(bar, height)
    if not bar then return end
    -- Snapped, not raw: the bar keeps the configured size in UI units and grows
    -- with the UI like the client's own bars do, but both its edges land on the
    -- pixel grid so the backdrop can draw a crisp border against them.
    bar:SetHeight(Snap(height))
    for _, inner in ipairs({ bar.statusBar, bar.statusBarAfterImage }) do
        if inner then
            pcall(function()
                inner:RemoveAllAnchors()
                inner:AddAnchor("TOPLEFT", bar, 0, 0)
                inner:AddAnchor("BOTTOMRIGHT", bar, 0, 0)
            end)
        end
    end
end

-- Per-bar backdrop, measured from the newer client's own cell.
--
-- Its background sprite is a 17x17 ninepart at (430,0) whose pixels are, across
-- and down:
--
--     0        rgba(118,118,118,  0)   fully transparent
--     1        rgba( 15, 23, 35,153)   the 1px border
--     2..6     rgba(  0,  0,  0, 171/160/147/136/130)   falloff under the top
--     7..14    rgba(  0,  0,  0,128)   flat interior
--     15       rgba( 15, 23, 35,153)   border
--     16       transparent
--
-- Two things follow that the first attempt got wrong. The OUTERMOST pixel is
-- not drawn, so the border sits one pixel INSIDE the drawable's bounds - drawing
-- it flush at the edge made every bar's frame read a pixel thicker than retail.
-- And there is a five-row alpha falloff beneath the top border, an inner shadow,
-- not a flat fill.
--
-- The fill is flush to the wrapper (vanilla geometry), so this cell is drawn
-- OUTSET around the bar instead of inside it: the border ring and its inner
-- shadow land just outside the fill rather than under it, and the interior sits
-- behind the fill exactly as it does in the reference.
--
-- Built once per bar and cached. Rebuilding per restyle would add drawables to
-- every bar on every target change and never free the old ones.
-- Neutral grey at the same luminance as the reference's rgb(15,23,35) border.
-- That colour is genuinely blue-tinted - blue exceeds red by 20 - and at any
-- appreciable alpha it reads as a cyan cast along every edge. Desaturating to
-- equal luminance keeps the depth without the tint. bar_frame.png carries the
-- same substitution so the ninepart and this fallback agree.
local BAR_BG_EDGE = { 22 / 255, 22 / 255, 22 / 255 }
local BAR_BG_BORDER_A = 153 / 255
local BAR_BG_BODY_A = 128 / 255
-- rows 2..6 of the cell, the inner shadow under the top border
local BAR_BG_FADE_A = { 171 / 255, 160 / 255, 147 / 255, 136 / 255, 130 / 255 }

local BAR_FRAME_PNG = BAR_TEXTURE_DIR .. "bar_frame.png"
local BAR_FRAME_CELL = 17     -- the cell as the newer client ships it
local BAR_FRAME_INSET = 8     -- ninepart inset, as the .g declares it

-- How far the backdrop extends beyond the bar on every side.
--
-- The cell draws its 1px border one pixel inside its own bounds, plus a
-- five-row inner shadow beneath the top border. With the fill flush to the
-- wrapper, an outset of 2 puts that border ring just outside the fill and keeps
-- the shadow reading as depth along the top edge - the reference look, without
-- taking a single pixel of width or height off the bar itself.
--
-- This is what AAC does with its own frame.bg too: 2.0 anchored it hpBar -1,-1
-- to mpBar +1,+1, a pixel outside the bars on every side.
local BAR_BG_OUTSET = 2

-- Gap between the HP bar and the MP bar below it.
--
-- MEASURED: this many pixels is what you see between the two bars.
--
-- It briefly looked as though the engine added a row - 2 here measured as 3 in
-- game - but that reading was taken while frame.bg was still visible, and
-- vanilla's frame art was padding the junction. With that hidden (see the
-- hideDeco calls in SeatBars) the constant maps straight to the visible gap.
--
-- Kept as its own number rather than tied to BAR_BG_OUTSET. They happen to be
-- equal, but they answer different questions - one is how far the backdrop
-- reaches beyond its bar, the other is how far apart the two bars sit - and
-- chaining them together only obscures which one to change.
local MP_BAR_GAP = 2

-- Horizontal shift applied to both bars, negative = left.
--
-- Moves the BARS, not their contents: the wrapper carries its own furniture, so
-- bg, line, hpBar_deco, combatIcon, lootIcon, heirWing, heirFrame and buffWindow
-- all travel with it. The level number and the name do NOT - the client anchors
-- level to the window (unitframe_view.lua: level:AddAnchor("TOPLEFT", w, 0, 0))
-- and hangs name off level - so they stay put by design.
local BAR_SHIFT_X = -7

-- Re-seat both bars: the HP bar shifted horizontally, the MP bar MP_BAR_GAP
-- below it. Every number here is taken from the client's own decompiled source.
--
-- HP: the client anchors it TOPLEFT to the frame at (1, level:GetHeight() + 5)
-- (unitframe_view.lua:48, target.lua:223, target_to_target.lua:71). Target and
-- target-of-target additionally pin RIGHT to the frame (target.lua:224) so the
-- bar stretches with the frame's grade width - 180 weak / 300 normal / 430
-- strong. That anchor has to be reproduced or those bars lose their width; the
-- player and watch frames instead carry an explicit SetWidth(300), so they take
-- the TOPLEFT anchor alone.
--
-- MP: seated MP_BAR_GAP below. With the fill spanning the bar and the backdrop
-- outset 2, an HP bar of height h puts its bottom border at y = h (cell row 0
-- transparent at -2, border row 1 at -1, border row 15 at h, transparent row 16
-- at h+1); an MP bar seated g below puts its top border at y = h + g - 1.
--
--   g = 2  ->  borders at h and h+1: adjacent rows, and the overlap falls
--             entirely on the two transparent rings, so nothing composites.
--             This is the reference look, and what the client's own gap of 0
--             cannot give once the backdrop is outset.
--   g = 0  ->  the boxes overlap four rows and the HP border lands under the MP
--             shadow ramp (153 over 171) - a dark seam at the junction.
--
-- Two-corner rather than a single centred TOP anchor, matching what the client
-- does itself (target.lua:226-227): anchoring by centre pins only the midpoint,
-- so the MP bar would keep its own width and its left edge need not line up with
-- the HP bar above it.
local function SeatBars(frame)
    if not frame or not frame.hpBar then return end
    local hp = frame.hpBar
    local s = require("BetterBars/settings").getSettings()

    -- Heights are re-applied here, not just anchors.
    --
    -- target.lua and target_to_target.lua set the bar heights THEMSELVES inside
    -- UpdateFrameStyle_ForUniType, from UNIT_FRAME_HEIGHT (common.lua: HP_BAR
    -- 19, MP_BAR 13) - target.lua:209,212 and target_to_target.lua:56,59. Since
    -- that function runs on its own schedule and survives the addon replacing
    -- ApplyFrameStyle, re-seating only the anchors left the configured height
    -- overwritten with the client's 19 whenever a target changed. That is what
    -- made the target-of-target bars look right sometimes and wrong others.
    local mpShown = frame.mpBar ~= nil and frame.mpBar:IsVisible()
    local hpH = s.barHeight and s.barHeight.hp or 17
    local mpH = s.barHeight and s.barHeight.mp or 13
    if not mpShown then
        -- No MP bar (slaves, housing, transfers, shipyards): the client gives
        -- the HP bar the whole span instead, HP_BAR + MP_BAR (target.lua:192).
        -- The same idea scaled to the configured sizes - the gap is included
        -- because it is space the two-bar layout would have occupied.
        hpH = hpH + MP_BAR_GAP + mpH
    end
    ApplyBarBox(hp, hpH)
    if frame.mpBar then ApplyBarBox(frame.mpBar, mpH) end

    pcall(function()
        -- Reproduce the client's own y so only x changes. GetHeight is read back
        -- rather than assumed: the level label is font-sized, and the client
        -- computes this expression fresh every time it re-anchors.
        local y = 5
        if frame.level and frame.level.GetHeight then
            local h = frame.level:GetHeight()
            if type(h) == "number" and h > 0 then y = h + 5 end
        end
        -- Snapped: level:GetHeight() is font-derived and need not be a whole
        -- number of device pixels, and a bar whose TOP starts mid-pixel cannot
        -- carry a crisp border however carefully the border itself is built.
        y = Snap(y)
        -- The shift is a number of SCREEN pixels - "move it 6px left" should
        -- mean the same thing at every UI scale - so it converts through Px,
        -- while the client's own base offset of 1 stays a snapped UI unit. At
        -- 100% this is exactly 1 + BAR_SHIFT_X, as before.
        local x = Snap(1) + Px(BAR_SHIFT_X)
        local stretchRight = frame.unitType == "target"
            or frame.unitType == "targettarget"
        hp:RemoveAllAnchors()
        hp:AddAnchor("TOPLEFT", frame, "TOPLEFT", x, y)
        if stretchRight then
            -- Both edges move, so the bar shifts rather than widening
            hp:AddAnchor("RIGHT", frame, Px(BAR_SHIFT_X), 0)
        end
    end)

    -- The MP bar rides the HP bar, so it inherits the shift for free.
    if frame.mpBar then
        pcall(function()
            -- Device pixels, like the border it has to meet: you asked for a
            -- 2px gap and it should stay 2px on screen at any UI scale, not
            -- 2.6px at 130% where it lands mid-pixel and measures as 3.
            local gap = Px(MP_BAR_GAP)
            frame.mpBar:RemoveAllAnchors()
            frame.mpBar:AddAnchor("TOPLEFT", hp, "BOTTOMLEFT", 0, gap)
            frame.mpBar:AddAnchor("TOPRIGHT", hp, "BOTTOMRIGHT", 0, gap)
        end)
    end

    -- Re-hide the vanilla separators, every time.
    --
    -- The client turns BOTH back on whenever the target type changes:
    -- target.lua:210 and target_to_target.lua:57 call
    -- hpBar_deco:SetVisible(true), and target_to_target.lua:70 does the same
    -- for line. hpBar_deco is the white 8px three-part drawable anchored across
    -- the HP bar's bottom edge and overhanging it 1px left and 2px right - the
    -- heavy band that kept reappearing between the bars.
    --
    -- ApplyCommonStyle already hides them, but it runs BEFORE
    -- UpdateFrameStyle_ForUniType, so that hide is undone a moment later. This
    -- runs from the hook on that function, which is after it - so it sticks.
    --
    -- Both Show(false) and SetVisible(false) are called: this addon has always
    -- used Show while the client uses SetVisible, and they are not known to be
    -- the same flag, so clearing one may leave the other set.
    local function hideDeco(d)
        if not d then return end
        pcall(function() d:Show(false) end)
        pcall(function() d:SetVisible(false) end)
    end
    -- Re-centre the HP/MP value labels, every restyle.
    --
    -- This used to run once in OnLoad and never again - the last piece of the
    -- addon's styling still applied as a one-shot. Three separate bugs this
    -- session came from exactly that shape (hpBar_deco, frame.bg and the bar
    -- heights, all re-set by the client after our setup ran), and a user report
    -- of labels sitting hard right - vanilla's BOTTOMRIGHT/ALIGN_RIGHT
    -- placement from unitframe_view.lua:60,71 - while still showing OUR text
    -- format is exactly what a lost anchor with a surviving SetText wrap looks
    -- like.
    --
    -- Nothing in this client re-anchors them (unitframe.lua only calls Show and
    -- SetText), so this is belt and braces rather than a known clobber. It costs
    -- two anchors per restyle and removes the whole failure mode.
    --
    -- CENTER on the bar with the label left auto-resizing, which is what the
    -- frames already do and demonstrably lands correctly. Deliberately not
    -- switched to the client's other idiom - two-corner anchor plus
    -- ALIGN_CENTER, as tooltip_view.lua:982-984 does - because that relies on
    -- the label filling the bar, and whether the text then centres VERTICALLY
    -- is not something to change blind.
    local function seatLabel(bar, label)
        if not bar or not label then return end
        pcall(function()
            label:RemoveAllAnchors()
            label:AddAnchor("CENTER", bar, "CENTER", 0, 0)
            label.style:SetAlign(ALIGN.CENTER)
        end)
    end
    seatLabel(frame.hpBar, frame.hpBar and frame.hpBar.hpLabel)
    seatLabel(frame.mpBar, frame.mpBar and frame.mpBar.mpLabel)

    hideDeco(frame.hpBar_deco)
    hideDeco(frame.line)
    -- frame.bg belongs in this list too, and is the reason the MP background
    -- looked like it was sized to vanilla rather than to our height.
    --
    -- It is the client's 304x38 frame image (unitframe_view.lua:32), stretched
    -- across the WHOLE bar stack: every target-type change re-anchors it
    -- hpBar TOPLEFT(-1,-4) -> mpBar BOTTOMRIGHT(4,4) (target.lua:214-215,
    -- target_to_target.lua:61-62). Those offsets are built around vanilla's
    -- 19/13 bars, so with custom heights the art lands at the wrong scale and
    -- reads as a background that does not follow the MP bar - exactly the gap
    -- between it and our own shadow ramp.
    --
    -- ApplyCommonStyle hides it, but that runs before UpdateFrameStyle_ForUniType
    -- re-anchors it, so the hide has to be repeated from here.
    hideDeco(frame.bg)
end

-- Keep SeatBars applied on the frames that re-anchor their own bars.
--
-- target.lua and target_to_target.lua re-seat BOTH bars inside
-- UpdateFrameStyle_ForUniType (target.lua:222-227), which the game calls on
-- every target-type change. That is NOT ApplyFrameStyle - the addon replaces
-- ApplyFrameStyle wholesale, but this one survives and runs on its own
-- schedule, so without a hook it silently undoes the shift and the MP gap
-- whenever the target changes. player, watch_target and pet have no such
-- function; their bars are only touched through ApplyFrameStyle.
local function HookUniTypeStyle(frame)
    if not frame or frame.bbUniTypeHooked then return end
    local orig = frame.UpdateFrameStyle_ForUniType
    if type(orig) ~= "function" then return end
    frame.bbUniTypeHooked = true
    frame.UpdateFrameStyle_ForUniType = function(self, detailType)
        orig(self, detailType)
        pcall(SeatBars, self)
    end
end

local function ApplyBarBackdrop(bar, opacity)
    if not bar then return end

    if not bar.bbBg then
        local made = { fades = {} }

        -- Preferred: the newer client's own frame cell, extracted to a PNG and
        -- drawn as a ninepart. The inset keeps the border and the shadow ramp at
        -- their true sizes while only the middle stretches, so it is exact at any
        -- bar height - where the flat-rectangle fallback can only step the ramp
        -- in whole rows.
        --
        -- SetTgaTexture returns whether the file loaded (the client checks it the
        -- same way in ucc.lua), and no ninepart is known to accept it, so both
        -- the call and its result are treated as untrusted.
        local okNine = pcall(function()
            local d = bar:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
            -- Same as the fill texture: without this the engine can apply an
            -- sRGB conversion to the loaded PNG, which shifts the border's dark
            -- navy noticeably bluer than the cell it came from.
            pcall(function() d:SetSRGB(false) end)
            local loaded = d:SetTgaTexture(BAR_FRAME_PNG)
            if loaded == false then BBFail() end
            d:SetCoords(0, 0, BAR_FRAME_CELL, BAR_FRAME_CELL)
            d:SetInset(BAR_FRAME_INSET, BAR_FRAME_INSET, BAR_FRAME_INSET, BAR_FRAME_INSET)
            made.nine = d
        end)

        -- Which path we land on decides how faithful the backdrop is, and it
        -- has never been confirmed - no ninepart anywhere in either client calls
        -- SetTgaTexture. Recorded so "bbinfo" can report it on demand, and
        -- announced once so it is a fact rather than a guess.
        bbBackdropPath = okNine and "ninepart" or "fallback"
        if not bbBackdropPathLogged then
            bbBackdropPathLogged = true
            api.Log:Info("BetterBars: backdrop using "
                .. (okNine and "the extracted ninepart cell (exact)"
                            or "the flat-rectangle fallback (approximate)"))
        end

        if not okNine then
            -- Fallback: rebuild the cell from flat rectangles. Each pixel row is
            -- painted exactly once - the body starts below the ramp rather than
            -- under it, or the two alphas composite and the top reads as a dark
            -- block instead of a shadow.
            local ok = pcall(function()
                local e = BAR_BG_EDGE
                made.body = bar:CreateColorDrawable(0, 0, 0, 1, "background")
                made.edges = {
                    { bar:CreateColorDrawable(e[1], e[2], e[3], 1, "background"), "TOPLEFT", "TOPRIGHT", true },
                    { bar:CreateColorDrawable(e[1], e[2], e[3], 1, "background"), "BOTTOMLEFT", "BOTTOMRIGHT", true },
                    { bar:CreateColorDrawable(e[1], e[2], e[3], 1, "background"), "TOPLEFT", "BOTTOMLEFT", false },
                    { bar:CreateColorDrawable(e[1], e[2], e[3], 1, "background"), "TOPRIGHT", "BOTTOMRIGHT", false },
                }
                for i = 1, #BAR_BG_FADE_A do
                    made.fades[i] = bar:CreateColorDrawable(0, 0, 0, 1, "background")
                end
            end)
            if not ok or not made.body then return end
        end

        bar.bbBg = made
    end

    -- Anchoring happens on EVERY call, not just at creation.
    --
    -- These drawables live on the game's own frame widgets, which outlive an
    -- addon reload, so bar.bbBg is still populated next time round and the
    -- creation block above is skipped. Anchoring only there meant a bar whose
    -- configured height later changed kept a backdrop sized for the old one.
    local bg = bar.bbBg
    -- The ENTIRE backdrop is laid out in device pixels, converted to UI units
    -- through px1. Positions and thicknesses must agree or the cell falls apart:
    -- with thicknesses in device pixels but offsets left in UI units, at 1.3
    -- scale the border came out 1 device pixel thick sitting 1.3 device pixels
    -- from the edge, with the body starting 2.6 in - every boundary landing
    -- mid-pixel. Same units throughout, and the ring is 1px thick at 1px inset
    -- at any scale.
    local px1 = Px(1)
    local O = BAR_BG_OUTSET * px1
    local two = 2 * px1
    -- Recorded from the drawables that actually exist, on every call. Setting it
    -- only in the creation block above reported "not built yet" forever: these
    -- drawables live on the game's widgets and survive an addon reload, so the
    -- creation block is skipped on every load after the first.
    bbBackdropPath = bg.nine and "ninepart" or "fallback"
    pcall(function()
        if bg.nine then
            bg.nine:RemoveAllAnchors()
            bg.nine:AddAnchor("TOPLEFT", bar, -O, -O)
            bg.nine:AddAnchor("BOTTOMRIGHT", bar, O, O)
            return
        end

        -- The ramp rows and the body are CHAINED - each anchored to the bottom
        -- of the one above it rather than to an absolute offset from the bar's
        -- top.
        --
        -- Absolute offsets meant every row's position was computed independently
        -- from the bar's top, so the ramp and the body agreeing depended on the
        -- two arithmetic expressions staying in step - and a transparent seam
        -- across the background is what a one-pixel disagreement looks like.
        -- Chaining makes the question moot: the body starts where the ramp ends
        -- by construction, and the ramp rows cannot drift apart from each other,
        -- whatever the engine does with a given offset.
        local prev
        for _, d in ipairs(bg.fades) do
            d:RemoveAllAnchors()
            if prev then
                d:AddAnchor("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)
                d:AddAnchor("TOPRIGHT", prev, "BOTTOMRIGHT", 0, 0)
            else
                d:AddAnchor("TOPLEFT", bar, -O + two, 0)
                d:AddAnchor("TOPRIGHT", bar, O - two, 0)
            end
            d:SetHeight(px1)
            prev = d
        end

        bg.body:RemoveAllAnchors()
        if prev then
            bg.body:AddAnchor("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)
        else
            bg.body:AddAnchor("TOPLEFT", bar, -O + two,
                -O + two + #BAR_BG_FADE_A * px1)
        end
        bg.body:AddAnchor("BOTTOMRIGHT", bar, O - two, O - two)

        -- One device pixel in from whichever corner the anchor names, so the
        -- ring sits at inset 1 with the cell's outermost pixel left undrawn
        local function off(point)
            local y = string.find(point, "BOTTOM") and (O - px1) or (-O + px1)
            local x = string.find(point, "RIGHT") and (O - px1) or (-O + px1)
            return x, y
        end
        for _, spec in ipairs(bg.edges) do
            local d, a1, a2, horizontal = spec[1], spec[2], spec[3], spec[4]
            local x1, y1 = off(a1)
            local x2, y2 = off(a2)
            if horizontal then
                -- Pull the horizontal edges in by one so the VERTICAL edges own
                -- the corners. Previously all four ran corner to corner, so at
                -- each corner two 153-alpha rectangles covered the same pixel
                -- and composited to about 217 - four dark dots framing every
                -- bar. The real cell has a single, lighter, anti-aliased pixel
                -- there (123/111/111/86 measured off bar_frame.png), so one
                -- drawable per corner pixel is the closest this path can get.
                x1 = x1 + (string.find(a1, "RIGHT") and -px1 or px1)
                x2 = x2 + (string.find(a2, "RIGHT") and -px1 or px1)
            end
            d:RemoveAllAnchors()
            d:AddAnchor(a1, bar, x1, y1)
            d:AddAnchor(a2, bar, x2, y2)
            if horizontal then d:SetHeight(px1) else d:SetWidth(px1) end
        end

    end)

    -- The reference applies NO tint to the unit-frame background: it creates the
    -- drawable and draws the cell at its literal alphas - border 153, ramp
    -- 171..130, interior 128 (SetViewOfStatusBarOfUnitFrame; the SetTextureColor
    -- calls nearby belong to the exp/labor/siege bars, not this one).
    --
    -- So 1.0 IS the reference, and the setting is a plain multiplier from there.
    -- This used to divide by 0.6 - the old addon's default - which only landed
    -- on exact by coincidence and quietly scaled the whole cell otherwise.
    local k = opacity or 1
    pcall(function()
        if bg.nine then
            bg.nine:SetColor(1, 1, 1, math.min(1, k))
            return
        end
        local e = BAR_BG_EDGE
        bg.body:SetColor(0, 0, 0, BAR_BG_BODY_A * k)
        for _, spec in ipairs(bg.edges) do
            spec[1]:SetColor(e[1], e[2], e[3], BAR_BG_BORDER_A * k)
        end
        for i, d in ipairs(bg.fades) do
            d:SetColor(0, 0, 0, BAR_BG_FADE_A[i] * k)
        end
    end)
end

-- Paint a bar's damage trail directly rather than leaving it to whichever style
-- table the game last read. Per-style tables stopped the trail colour leaking
-- between frames, but a bar only got the right colour if the game happened to
-- re-apply that bar's own style; one whose style was not re-applied kept
-- whatever the previous ApplyBarTexture left on it, which is how an HP bar ended
-- up wearing the MP bar's blue trail across its empty portion. Setting it on the
-- widget makes it a property of this bar.
local function SetBarTrail(bar, colors)
    if not bar or not bar.statusBarAfterImage or not colors then return end
    pcall(function()
        bar.statusBarAfterImage:SetBarColor(
            (colors[1] or 0) * AFTERIMAGE_TRAIL_LUMA,
            (colors[2] or 0) * AFTERIMAGE_TRAIL_LUMA,
            (colors[3] or 0) * AFTERIMAGE_TRAIL_LUMA,
            colors[4] or 1)
    end)
end

local function ColorBarForKey(bar, key)
    if not bar or not bar.statusBar or not key then return false end
    local s = require("BetterBars/settings").getSettings()
    local colors = HP_COLORS
    if key == "mp" then
        colors = MP_COLORS
    elseif key == "hostile" and s.showHostilityColor ~= false then
        colors = EHP_COLORS
    elseif key == "preemptive" and s.showHostilityColor ~= false then
        colors = PREEMPT_COLORS
    end
    bar.statusBar:SetBarColor(unpack(colors))
    ApplyFillTexture(bar, colors, key == "mp")

    -- Paint the damage trail directly rather than leaving it to whichever style
    -- table the game last read. Per-style tables stopped the trail colour
    -- leaking between frames, but the bar still only got the right colour if the
    -- game happened to re-apply that bar's own style; a bar whose style was not
    -- re-applied kept whatever the previous ApplyBarTexture left on it, which is
    -- how an HP bar ended up wearing the MP bar's blue trail across its empty
    -- portion. Setting it on the widget makes it a property of this bar.
    SetBarTrail(bar, colors)
    return true
end

-- Wrap the bar's own ApplyBarTexture so the addon recolours exactly when the
-- game restyles, instead of only on TARGET_CHANGED.
--
-- ApplyBarTexture is a closure created per bar inside the game's
-- SetViewOfStatusBarOfUnitFrame, so each bar owns its own copy and replacing it
-- on one frame cannot leak into another. The game calls it whenever hostility,
-- first-hit or frame style changes - which is precisely the set of moments this
-- addon was trying to guess at.
--
-- Guarded rather than assumed: if the wrap never fires, or the style carries no
-- bbKey, frame.bbStyleKey stays nil and UpdateFrameStyles falls back to the old
-- resolution. Nothing depends on the hook succeeding.
-- The combat glow is left entirely alone.
--
-- It used to be wrapped: AddAnchor was intercepted so that anything anchored to
-- one of this frame's bars picked up the nudge, because the glow anchors to the
-- bar WRAPPERS while the nudge moved only their contents. With the nudge gone
-- the bar box fills the wrapper the glow already anchors to, so the game's own
-- anchoring is correct and there is nothing to correct.
--
-- Leaving it untouched is also the more robust choice. The game re-anchors the
-- glow itself on target and grade changes (target.lua:183-204,
-- target_to_target.lua:41-62) with different offsets per code path - -10/-10 to
-- 10,8 when the MP bar is hidden, to 10,10 when it is not, and -10/-8 for
-- target-of-target - so any offset this addon applied had to be re-applied
-- through a hook to survive, and was wrong for some frame regardless.


local function HookBarStyle(frame, bar)
    if not bar or bar.bbHooked then return end
    local orig = bar.ApplyBarTexture
    if type(orig) ~= "function" then return end
    bar.bbHooked = true
    bar.ApplyBarTexture = function(self, info)
        orig(self, info)
        local key = type(info) == "table" and info.bbKey or nil
        if key then
            -- Only HP styles say anything about hostility. Recording "mp" here
            -- overwrote the frame's key with a value that is neither "hostile"
            -- nor nil, so the hostility fallback below could never fire and every
            -- unit stayed friendly-coloured.
            if key ~= "mp" then
                frame.bbStyleKey = key
            end
            pcall(ColorBarForKey, self, key)
        end
    end
end

ApplyFillTexture = function(bar, colors, isMP)
    if not bar or not bar.statusBar then return end

    local s = require("BetterBars/settings").getSettings()
    local name = s.barTexture
    if isMP and name and BAR_TEXTURE_MP_VARIANT[name] then
        name = name .. "_mp"
    end
    if not name or name == "none" then
        if bar.bbFill then bar.bbFill:SetVisible(false) end
        return
    end

    local tex = bar.bbFill
    if not tex then
        -- Seeded with a stock texture, then repointed at the PNG. Taken in two
        -- steps so the drawable is owned the moment it exists: if the anchoring
        -- throws it is still recorded, where a single pcall around both would
        -- drop it on the floor and build another one on every later call.
        local created
        pcall(function()
            created = bar.statusBar:CreateImageDrawable("Textures/Defaults/White.dds", "overlay")
        end)
        if not created then return end
        bar.bbFill = created
        bar.bbFillName = nil
        tex = created
        pcall(function()
            tex:SetSRGB(false)
            bar.statusBar:AddAnchorChildToBar(tex, "TOPLEFT", "TOPLEFT", 0, 0)
            bar.statusBar:AddAnchorChildToBar(tex, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0)
        end)
    end

    -- Keyed on the name AND the size, not the name alone.
    --
    -- These drawables live on the game's frames and outlive an addon reload, so
    -- the cache survives too. When the shipped PNGs were regenerated at their
    -- native 300x17 and 300x13 the name did not change, so the crop was never
    -- re-applied and the drawable kept sampling a 64x32 corner of a 300px image
    -- and stretching it across the bar.
    local size = BAR_TEXTURE_SIZE[name]
    local tw = size and size[1] or BAR_TEXTURE_DEFAULT_W
    local th = size and size[2] or BAR_TEXTURE_DEFAULT_H
    local key = name .. "@" .. tw .. "x" .. th
    if bar.bbFillName ~= key then
        pcall(function()
            tex:SetTgaTexture(BAR_TEXTURE_DIR .. name .. ".png")
            -- The drawable inherits the stock texture's crop; widen it to the
            -- whole PNG or only its top-left corner is shown
            tex:SetCoords(0, 0, tw, th)
        end)
        bar.bbFillName = key
    end

    -- The texture carries its own shading, including the slight darkening the
    -- reference bars have; the colour is applied straight.
    tex:SetColor(colors[1], colors[2], colors[3], colors[4] or 1)
    -- Only show it if the bar actually has a value: a restyle can land on a dead
    -- unit, and unconditionally showing here would put the sliver back.
    local v = 0
    pcall(function() v = bar.statusBar:GetValue() or 0 end)
    tex:SetVisible(v > 0)
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function SetupFrame(unitType, uicType)
  local frame = ADDON:GetContent(uicType)
  if not frame then
      api.Log:Err("Failed to get frame for " .. unitType)
      return
  end
  -- Store the unitType with the frame for later hostility checks
  frame.unitType = unitType
  FrameLabels[unitType] = frame
  -- Let the game drive recolouring (see HookBarStyle). Wrapped in pcall: if the
  -- sandbox hands back a proxy that will not take the assignment, the addon
  -- simply keeps using its own resolution.
  pcall(function()
      HookBarStyle(frame, frame.hpBar)
      HookBarStyle(frame, frame.mpBar)
      HookUniTypeStyle(frame)
  end)
  -- The player frame is styled ONCE at UI creation (player.lua:120), before
  -- this addon rebuilds the style coords - so its statusBar keeps sampling
  -- the vanilla baked-green cell, and with the fill texture off the custom
  -- colour tints green art instead of the white cell (dark muddy result).
  -- Re-applying is safe here, unlike on target frames: the player is always
  -- friendly, so no game-chosen hostility style gets stomped. Routed through
  -- the bar's ApplyBarTexture so the hook records the key and recolours.
  if unitType == "player" then
      pcall(function() frame.hpBar:ApplyBarTexture(STATUSBAR_STYLE.L_HP_FRIENDLY) end)
      pcall(function() frame.mpBar:ApplyBarTexture(STATUSBAR_STYLE.L_MP) end)
  end
end

-- Hide the fill texture when a bar reaches zero.
--
-- The texture is a drawable anchored to the bar's FILL via AddAnchorChildToBar,
-- so at 0% its quad should collapse to nothing - but the engine leaves it at a
-- minimum size, which showed as a coloured sliver stuck at the left of a dead
-- unit's bar. The statusbar underneath empties correctly; only the overlay
-- needs hiding.
--
-- Driven from the label's SetText, which the game already calls on every health
-- and mana change, so this needs no update loop of its own.
-- Read the statusbar's own value, not api.Unit: the game drives the bar
-- through its ungated natives, so this works where UnitHealth is filtered
-- and returns nil - housing - which used to permanently hide the fill
-- texture on house targets.
--
-- The setting gate matters too: this runs on every health tick, and showing
-- purely on value > 0 used to resurrect the fill texture right after the
-- Retail fill toggle hid it.
local function SyncFillVisibilityBar(bar)
    if not bar or not bar.bbFill then return end
    local s = require("BetterBars/settings").getSettings()
    local enabled = (s.barTexture or "none") ~= "none"
    local v = 0
    pcall(function() v = bar.statusBar:GetValue() or 0 end)
    pcall(function() bar.bbFill:SetVisible(enabled and v > 0) end)
end

local function SyncFillVisibility(unitType, isHP)
    local frame = FrameLabels[unitType]
    if not frame then return end
    SyncFillVisibilityBar(isHP and frame.hpBar or frame.mpBar)
end

-- Fill every style entry's own trail tables from the colour that style paints
-- with, scaled to the damage-trail's ~43% luminance so the hue is preserved.
--
-- Done per style, not per frame: the game re-applies a style whenever it likes,
-- so the correct trail has to already be sitting in that style's table. The
-- friendly styles trail dark green, the hostile ones dark red, and so on -
-- matching whatever the user has configured for each.
local function setTrail(style, colors)
    if not style or not colors then return end
    local r = (colors[1] or 0) * AFTERIMAGE_TRAIL_LUMA
    local g = (colors[2] or 0) * AFTERIMAGE_TRAIL_LUMA
    local b = (colors[3] or 0) * AFTERIMAGE_TRAIL_LUMA
    -- "down" is the trail damage leaves behind - the one actually seen. "up" is
    -- the heal flash; the newer client keeps that dark too rather than flashing
    -- white, so both get the same treatment.
    for _, t in ipairs({ style.afterImage_color_down, style.afterImage_color_up }) do
        t[1], t[2], t[3] = r, g, b
    end
end

local function RefreshAfterImageColors()
    for _, n in ipairs({ "L_HP_FRIENDLY", "S_HP_FRIENDLY", "L_HP_NEUTRAL", "S_HP_NEUTRAL" }) do
        setTrail(STATUSBAR_STYLE[n], HP_COLORS)
    end
    for _, n in ipairs({ "L_HP_HOSTILE", "S_HP_HOSTILE" }) do
        setTrail(STATUSBAR_STYLE[n], EHP_COLORS)
    end
    for _, n in ipairs({ "L_HP_PREEMTIVE_STRIKE", "S_HP_PREEMTIVE_STRIKE" }) do
        setTrail(STATUSBAR_STYLE[n], PREEMPT_COLORS)
    end
    for _, n in ipairs({ "L_MP", "S_MP" }) do
        setTrail(STATUSBAR_STYLE[n], MP_COLORS)
    end
    -- Party frames are the one unit-frame family the addon cannot reach as
    -- widgets: partyFrame is a local in the game's party.lua, never registered
    -- as ADDON content and not exposed by sandbox.lua (pets got that favour,
    -- party did not). Their FILL is baked atlas art with no SetBarColor call
    -- anywhere, so it must stay vanilla - but the styles live in the shared
    -- STATUSBAR_STYLE table, so the damage trail can still follow the custom
    -- colours. Party MP uses S_MP and is already covered above.
    local party = STATUSBAR_STYLE.S_HP_PARTY
    if party then
        party.afterImage_color_down = party.afterImage_color_down or newTrail()
        party.afterImage_color_up = party.afterImage_color_up or newTrail()
        setTrail(party, HP_COLORS)
    end
end


---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Format label text based on settings
local function formatLabelText(unitType, isHP)
    local s = require("BetterBars/settings").getSettings()
    local fmt = s.labelFormat or "both"
    local current = isHP and api.Unit:UnitHealth(unitType) or api.Unit:UnitMana(unitType)
    local max = isHP and api.Unit:UnitMaxHealth(unitType) or api.Unit:UnitMaxMana(unitType)
    if not current or not max or max <= 0 then
        if fmt == "hide" then return "" end
        -- api cannot read this unit (housing is filtered out): return nil so
        -- the label wrap falls back to the game's own text instead of "???".
        return nil
    end
    local percent = math.floor((current / max) * 100)
    if fmt == "hide" then return "" end
    if fmt == "current" then return tostring(current) end
    if fmt == "percent" then return tostring(percent) .. "%" end
    -- "both" default
    return string.format("%d (%d%%)", current, percent)
end


----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Common style function
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function ApplyCommonStyle(frame)
    -- Read settings (re-read on each call so changes apply immediately)
    local s = require("BetterBars/settings").getSettings()
    local bgOpacity = s.backgroundOpacity or 0.6

    
    if frame.line then
        frame.line:Show(false)  -- Hide line
    end
    -- bg, mpBar and hpBar_deco are all optional. Pet frames in particular do not
    -- carry the full set, and StylePetFrame routes through here - the old
    -- condition read `frame.bg and frame.mpBar:IsVisible()`, which dereferences
    -- mpBar under a guard that only checks bg, and whose else branch then used
    -- bg unguarded. Either shape errored out on a frame missing one of them.
    --
    -- The two branches only ever differed in what the background's bottom-right
    -- corner attaches to, so they collapse into one.
    local mpVisible = frame.mpBar ~= nil and frame.mpBar:IsVisible()

    -- Each bar carries its own backdrop now (see ApplyBarBackdrop), matching the
    -- newer client. The frame's single shared bg is hidden rather than removed,
    -- so the game can keep resizing it harmlessly.
    if frame.bg then
        pcall(function() frame.bg:Show(false) end)
    end
    ApplyBarBackdrop(frame.hpBar, bgOpacity)
    if mpVisible then
        ApplyBarBackdrop(frame.mpBar, bgOpacity)
    end
    -- AAC draws a white three-part divider between the HP and MP bars
    -- (unitframe_view.lua: hpBar_deco, 8px tall, anchored across the HP bar's
    -- bottom edge and overhanging it by 1px left and 2px right). The newer
    -- client has no such divider - each bar's own border is the separation - and
    -- that overhang is part of why the bars looked misaligned. Always hidden.
    if frame.hpBar_deco then
        pcall(function() frame.hpBar_deco:Show(false) end)
    end
    if frame.effect_texture then
        frame.effect_texture:SetVisible(false)
        frame.effect_texture:SetStartEffect(false)
    end
    if frame.use_effect_texture ~= nil then
        frame.use_effect_texture = false
    end

    -- Level number font, user-selectable (Font button in settings). Vanilla
    -- is the ornate LEEYAGI (unit.lua:16); default here is the UI font -
    -- which is also what RETAIL uses (RU unit.lua: plain label, no SetFont).
    -- The game sets font and size once at creation and never again, so this
    -- sticks - and re-runs on every settings change, so picks apply live.
    -- Some labels carry an extraStyle (outline layer) that needs the same
    -- font or it renders mixed - korean_combat_text sets both, so both are.
    if frame.level and frame.level.label then
        local lbl = frame.level.label
        local fontPath = s.levelFont or "ui/font/yd_ygo540.ttf"
        pcall(function()
            lbl.style:SetFont(fontPath, FONT_SIZE.XXLARGE)
        end)
        pcall(function()
            if lbl.extraStyle then
                lbl.extraStyle:SetFont(fontPath, FONT_SIZE.XXLARGE)
            end
        end)
    end

    -- Combat / hostility glow: not touched. AAC anchors it to the bar wrappers
    -- itself (unitframe_view.lua:84-85) and re-anchors it on target and grade
    -- changes, and the wrappers are where this addon leaves them - so vanilla's
    -- anchoring already frames the bar correctly, including the bottom edge
    -- following the MP bar only while that bar is showing.

    SeatBars(frame)

    -- Set the MP bar color for all frames. A frame without an MP bar is normal
    -- (some pet frames), so its absence is not an error worth logging - this ran
    -- on every target change and reported a condition nothing can act on.
    if frame.mpBar and frame.mpBar.statusBar then
        frame.mpBar.statusBar:SetBarColor(unpack(MP_COLORS))
        ApplyFillTexture(frame.mpBar, MP_COLORS, true)
    end
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Player frame style
local function StylePlayerFrame(frame)
  frame.ApplyFrameStyle = function(frame)
    local s = require("BetterBars/settings").getSettings()
    ApplyCommonStyle(frame)
    if frame then
      -- Heights and anchors are both applied by SeatBars, from ApplyCommonStyle
      -- above. Setting them again here would force the HP height unconditionally
      -- and undo the full-span treatment SeatBars gives a frame whose MP bar is
      -- hidden.
      -- The HP style is deliberately NOT forced here. Applying L_HP_FRIENDLY on
      -- every restyle overwrote whatever hostility style the game had just
      -- chosen - and, through the hook, the recorded key with it - so hostile
      -- units came out green. The game applies the right HP style itself; the
      -- overrides at the top of this file mean it picks up our coords and trail
      -- whichever one it picks. MP has no hostility variants, so it stays explicit.
      frame.mpBar:ApplyBarTexture(STATUSBAR_STYLE.L_MP)
    end
  end
  frame:ApplyFrameStyle()
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Target frame style
local function StyleTargetFrame(frame)
  frame.ApplyFrameStyle = function(frame)
    local s = require("BetterBars/settings").getSettings()
    ApplyCommonStyle(frame)
    if frame then
      -- Heights and anchors are both applied by SeatBars, from ApplyCommonStyle
      -- above. Setting them again here would force the HP height unconditionally
      -- and undo the full-span treatment SeatBars gives a frame whose MP bar is
      -- hidden.
      frame.line:Show(false)
    end
  end
  frame:ApplyFrameStyle()
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- TargetTarget frame style
local function StyleTargetTargetFrame(frame)
  frame.ApplyFrameStyle = function(frame)
    local s = require("BetterBars/settings").getSettings()
    ApplyCommonStyle(frame)
    if frame then 
      -- Heights and anchors are both applied by SeatBars, from ApplyCommonStyle
      -- above. Setting them again here would force the HP height unconditionally
      -- and undo the full-span treatment SeatBars gives a frame whose MP bar is
      -- hidden.
      frame.mpBar:ApplyBarTexture(STATUSBAR_STYLE.S_MP)
    end
  end
  frame:ApplyFrameStyle()
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- WatchTarget frame style
local function StyleWatchTargetFrame(frame)
  frame.ApplyFrameStyle = function(frame)
    local s = require("BetterBars/settings").getSettings()
    ApplyCommonStyle(frame)
    if frame then 
      -- Heights and anchors are both applied by SeatBars, from ApplyCommonStyle
      -- above. Setting them again here would force the HP height unconditionally
      -- and undo the full-span treatment SeatBars gives a frame whose MP bar is
      -- hidden.
    end
  end
  frame:ApplyFrameStyle()
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Pet frame style and SPAWN_PET event handler
-- petFrame is a global set by the game engine when pets spawn
-- Wrap a pet bar's label the same way OnLoad wraps the main frames': centre it
-- on the visible bar and reformat through formatLabelText. Pets are not in
-- FrameLabels (UpdateFrameStyles would run its target-frame logic on them), so
-- they get their own wrap with the bar captured directly.
local function WrapPetLabel(bar, label, unitToken, isHP)
    if not label or label.SetTextOrig then return end
    pcall(function()
        label:RemoveAllAnchors()
        label:AddAnchor("CENTER", bar, "CENTER", 0, 0)
        label.style:SetAlign(ALIGN.CENTER)
    end)
    label.SetTextOrig = label.SetText
    label.SetText = function(self, text)
        pcall(function()
            local s = require("BetterBars/settings").getSettings()
            self.style:SetFontSize(s.labelFontSize or FONT_SIZE.MIDDLE)
            pcall(function() self.style:SetShadow(s.labelShadow == true) end)
            -- Pets are readable through the api, so formatLabelText normally
            -- answers; the game's own text is the safety net, not "???".
            self:SetTextOrig(formatLabelText(unitToken, isHP) or text or "")
            SyncFillVisibilityBar(bar)
        end)
    end
end

local function StylePetFrame(frame)
    if not frame then return end
    local s = require("BetterBars/settings").getSettings()
    ApplyCommonStyle(frame)
    -- Same stale-coords problem as the player frame: pets style once at
    -- creation (pet.lua:45-46), possibly before this addon loaded. Pets are
    -- always friendly, so re-applying is safe.
    pcall(function() frame.hpBar:ApplyBarTexture(STATUSBAR_STYLE.S_HP_FRIENDLY) end)
    pcall(function() frame.mpBar:ApplyBarTexture(STATUSBAR_STYLE.S_MP) end)
    -- The engine names pet units "playerpet<mateType>" (func_unit.lua:70-75);
    -- mateType is stored on the frame by CreatePetFrame.
    local unitToken = frame.mateType and ("playerpet" .. tostring(frame.mateType)) or nil
    if frame.hpBar then
        -- statusBar is checked separately: the outer guard only proves the bar
        -- window exists, not that it carries one
        if frame.hpBar.statusBar then
            frame.hpBar.statusBar:SetBarColor(unpack(HP_COLORS))
            ApplyFillTexture(frame.hpBar, HP_COLORS)
        end
        -- Heights come from SeatBars via ApplyCommonStyle, same as every other
        -- frame. The client builds pet frames with the very same
        -- CreateUnitFrame (pet.lua:4), so their bars start at the identical
        -- 19/13 and its own ApplyFrameStyle only ever changes the WIDTH, to
        -- PET_FRAME_WIDTH = 120 (pet.lua:60-61). The old "height - 2, floored
        -- at 13" shrink was an addon invention written for the previous
        -- fill-height semantics, so under wrapper semantics it silently made
        -- pet bars shorter than asked for - the setting looked inert.
        if unitToken then
            WrapPetLabel(frame.hpBar, frame.hpBar.hpLabel, unitToken, true)
        end
    end
    if frame.mpBar then
        if frame.mpBar.statusBar then
            frame.mpBar.statusBar:SetBarColor(unpack(MP_COLORS))
            ApplyFillTexture(frame.mpBar, MP_COLORS, true)
        end
        -- Height applied by SeatBars, as above
        if unitToken then
            WrapPetLabel(frame.mpBar, frame.mpBar.mpLabel, unitToken, false)
        end
    end
end

local function StyleAllPetFrames()
    if not petFrame then return end
    -- Walked with pairs rather than a 1..2 index sweep. The client keys this
    -- table by the engine's MATE_TYPE constants (pet.lua:169,
    -- petFrame[mateType] = CreatePetFrame(...)), and those are C-side globals
    -- whose values never appear in the Lua - so assuming they are 1 and 2 is a
    -- guess. The index loop is kept as a fallback in case the sandbox proxy
    -- will not enumerate.
    local seen, ok = {}, pcall(function()
        for k, f in pairs(petFrame) do
            if f then seen[k] = true; StylePetFrame(f) end
        end
    end)
    if not ok then
        for i = 1, 2 do
            if petFrame[i] and not seen[i] then StylePetFrame(petFrame[i]) end
        end
    end
end

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Custom cast bar.
--
-- The vanilla playerCastingBar is a global the sandbox whitelist does not
-- expose, so it cannot be restyled or hidden. But W_BAR.CreateCastingBar IS
-- exposed, and the widget it builds is fully self-driving (bar.lua: OnUpdate
-- polls UnitCastingInfo, the SPELLCAST_* events drive show/hide) - so the
-- addon spawns its own and parks it exactly over the vanilla bar, slightly
-- larger, with an opaque backdrop that occludes it. The vanilla bar's spell
-- text sits BELOW its bar and stays visible, so ours keeps its own text
-- hidden - one name, not two.
-- Waiting for Aguru to enable castbar in API :)
--
-- Everything below builds a fully working replacement cast bar parked over
-- the vanilla one - but the sandbox does not expose playerCastingBar, so the
-- vanilla bar cannot be hidden and the cover kept leaking at the edges.
-- Flip this flag when the api grows support.
local CAST_BAR_ENABLED = false

local castBar = nil
-- Vanilla is 340x12 at BOTTOM -150; this covers it with ~6px side and
-- ~4-6px vertical margins so none of its fill or decos can peek out.
local CAST_BAR_W, CAST_BAR_H = 352, 22

local function EnsureCastBar()
    if castBar then return castBar end
    local ok, bar = pcall(function()
        return W_BAR.CreateCastingBar("bbCastBar", "UIParent", "player")
    end)
    if not ok or not bar then
        api.Log:Err("BetterBars: could not create cast bar: " .. tostring(bar))
        return nil
    end
    castBar = bar

    -- Vanilla playerCastingBar sits at BOTTOM -150, 340x12. Ours covers it
    -- with a real margin on every side; the bottom stops at -146 so the
    -- vanilla spell text underneath (which starts ~5px below its bar) stays
    -- readable as our label.
    pcall(function()
        bar:RemoveAllAnchors()
        bar:AddAnchor("BOTTOM", "UIParent", 0, -146)
        bar:SetExtent(CAST_BAR_W, CAST_BAR_H)
    end)

    -- Vanilla atlas art off; opaque base first - without it the vanilla fill
    -- blasts straight through the cell's half-transparent interior during a
    -- cast (tried and seen) - then the same backdrop cell the unit frames
    -- wear, at their backgroundOpacity (applied in SyncCastBar).
    pcall(function() bar.bg:SetVisible(false) end)
    pcall(function()
        local base = bar:CreateColorDrawable(0, 0, 0, 0.92, "background")
        base:AddAnchor("TOPLEFT", bar, 0, 0)
        base:AddAnchor("BOTTOMRIGHT", bar, 0, 0)
    end)
    pcall(function()
        local nine = bar:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        pcall(function() nine:SetSRGB(false) end)
        local loaded = nine:SetTgaTexture(BAR_FRAME_PNG)
        if loaded ~= false then
            nine:SetCoords(0, 0, BAR_FRAME_CELL, BAR_FRAME_CELL)
            nine:SetInset(BAR_FRAME_INSET, BAR_FRAME_INSET, BAR_FRAME_INSET, BAR_FRAME_INSET)
            nine:AddAnchor("TOPLEFT", bar, 0, 0)
            nine:AddAnchor("BOTTOMRIGHT", bar, 0, 0)
            bar.bbNine = nine
        end
    end)

    -- The fill sits at the cell's interior, inset 2 like every other bar.
    -- ChangeBarTexture re-adds the statusBar's TOPLEFT anchor with vanilla
    -- offsets on every usable/unusable switch, so it is wrapped to restore
    -- ours afterwards.
    local function reanchorFill()
        pcall(function()
            bar.statusBar:RemoveAllAnchors()
            bar.statusBar:AddAnchor("TOPLEFT", bar, 2, 2)
            bar.statusBar:AddAnchor("BOTTOMRIGHT", bar, -2, -2)
        end)
    end
    reanchorFill()
    local origCBT = bar.ChangeBarTexture
    if type(origCBT) == "function" then
        bar.ChangeBarTexture = function(self, usable)
            origCBT(self, usable)
            reanchorFill()
        end
    end

    -- Our text stays hidden - ShowAll() re-shows it on every cast, so it is
    -- wrapped too; the vanilla spell text below serves as the single label.
    -- Raise() on every show keeps this bar above the vanilla one: both are
    -- children of UIParent, so they are siblings - exactly the case Raise
    -- reorders - and anything that lifted the vanilla bar between casts
    -- (clicking its area does) would otherwise leave it covering ours.
    -- (The original ShowAll ignores self; both call styles it receives -
    -- frame:ShowAll() and frame.ShowAll() - work through this wrapper.)
    local origShowAll = bar.ShowAll
    if type(origShowAll) == "function" then
        bar.ShowAll = function()
            origShowAll()
            pcall(function() bar.text:Show(false) end)
            pcall(function() bar:Raise() end)
        end
    end
    pcall(function() bar.text:Show(false) end)
    pcall(function() bar:Raise() end)

    -- Raising only on ShowAll is not enough: clicking the vanilla bar (its
    -- spell text stays visible below ours) raises IT above ours mid-cast.
    -- The widget's OnUpdate runs every frame while the bar is active, so a
    -- raise there wins that fight permanently. SetVisibleCastingBar(true) in
    -- SyncCastBar re-binds the handler, picking this wrapper up.
    local origOnUpdate = bar.OnUpdate
    if type(origOnUpdate) == "function" then
        bar.OnUpdate = function(self)
            origOnUpdate(self)
            -- Only while actually shown: OnUpdate stays bound even when the
            -- bar is hidden between casts, and an every-frame Raise for an
            -- invisible widget is pure waste.
            pcall(function()
                if bar:IsVisible() then bar:Raise() end
            end)
        end
    end

    -- The widget's own OnEvent handler consumes these; without registration
    -- they never arrive.
    pcall(function()
        bar:RegisterEvent("SPELLCAST_START")
        bar:RegisterEvent("SPELLCAST_STOP")
        bar:RegisterEvent("SPELLCAST_SUCCEEDED")
    end)

    bar:Show(false)
    return castBar
end

local function SyncCastBar()
    if not CAST_BAR_ENABLED then
        if castBar then
            pcall(function() castBar:SetVisibleCastingBar(false) end)
            pcall(function() castBar:Show(false) end)
        end
        return
    end
    local s = require("BetterBars/settings").getSettings()
    if s.showCastBar ~= false then
        local bar = EnsureCastBar()
        if not bar then return end
        pcall(function() bar:SetVisibleCastingBar(true) end)
        pcall(function() bar.statusBar:SetBarColor(unpack(CAST_COLORS)) end)
        -- Backdrop at the exact opacity the unit frames use (ApplyBarBackdrop
        -- applies the same formula to their cell)
        pcall(function()
            if bar.bbNine then
                bar.bbNine:SetColor(1, 1, 1, math.min(1, s.backgroundOpacity or 1))
            end
        end)
        ApplyFillTexture(bar, CAST_COLORS)
        -- The fill's visibility is normally synced from the bar value, which
        -- is 0 outside a cast - but this whole frame hides between casts, so
        -- the fill can simply stay on.
        pcall(function() if bar.bbFill then bar.bbFill:SetVisible(true) end end)
    elseif castBar then
        pcall(function() castBar:SetVisibleCastingBar(false) end)
        pcall(function() castBar:Show(false) end)
    end
end

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Single registration point for events.
--
-- This used to keep a list so OnUnload could unregister everything, but the
-- unregister loop was written as `if api.Off then ... end` and this API has no
-- api.Off - the guard is never true, so nothing was ever removed and the
-- cleanup only looked like it worked. The list is kept because it is the one
-- place that knows what this addon subscribed to, but nothing pretends to undo
-- it: handlers have to tolerate firing after unload.
local registeredHandlers = {}
local function onEvent(event, handler)
    api.On(event, handler)
    table.insert(registeredHandlers, { event = event, handler = handler })
end

local betterBarsEventWnd = api.Interface:CreateEmptyWindow("BetterBarsEventWnd")
function betterBarsEventWnd:OnEvent(event, ...)
    if event == "SPAWN_PET" then
        StyleAllPetFrames()
    end
    -- Add more event handlers here as needed
end
betterBarsEventWnd:SetHandler("OnEvent", betterBarsEventWnd.OnEvent)
betterBarsEventWnd:RegisterEvent("SPAWN_PET")
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Create info labels (Class, GS, Guild) on a frame â€” one-time creation
local function CreateInfoLabels(frame, unitType)
    if frame.infoContainer then return end

    -- The container is only the ownership/visibility vehicle now: each label
    -- anchors independently to the bars, with per-item offsets from settings
    -- (applied in UpdateInfoLabels, every call, per the re-anchor rule).
    local container = frame:CreateChildWidget("window", unitType .. "_infoContainer", 0, true)
    container:SetExtent(1, 1)
    container:AddAnchor("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
    container:Show(true)
    -- Click-through, container included: these are labels sitting on top of the
    -- unit frame, and anything they swallow is a click that should have hit the
    -- frame - selecting the target, opening its menu, dragging the frame. The
    -- guild label is 160 wide and the class label 120, so they cover a lot of
    -- the row. Clickable is probed rather than assumed: it is not guaranteed on
    -- every widget type the sandbox hands back.
    pcall(function() container:Clickable(false) end)

    local function makeLabel(id, w)
        local lbl = container:CreateChildWidget("label", unitType .. id, 0, true)
        lbl:SetExtent(w, 18)
        lbl.style:SetAlign(ALIGN.CENTER)
        lbl.style:SetFontSize(12)
        lbl.style:SetColor(1, 1, 1, 1)
        pcall(function() lbl:Clickable(false) end)
        lbl:Show(true)
        return lbl
    end
    frame.classLabel = makeLabel("_classLabel", 120)
    frame.gsLabel = makeLabel("_gsLabel", 80)
    frame.guildLabel = makeLabel("_guildLabel", 160)

    frame.infoContainer = container
end

-- Re-anchor the info items from settings. Class and guild ride the row above
-- the visible bar (where the name sits), centered on the bar's contents; the
-- gear score hangs centered below the bottom bar. Offsets shift from there.
local function AnchorInfoLabels(frame)
    local s = require("BetterBars/settings").getSettings()
    local off = s.infoOffsets or {}
    local hpBar = frame.hpBar
    if not hpBar then return end
    local bottomBar = (frame.mpBar and frame.mpBar:IsVisible()) and frame.mpBar or hpBar

    local function seat(lbl, o, point, bar, barPoint, baseY)
        if not lbl then return end
        o = o or { x = 0, y = 0 }
        pcall(function()
            lbl:RemoveAllAnchors()
            lbl:AddAnchor(point, bar, barPoint,
                (o.x or 0), baseY + (o.y or 0))
        end)
    end
    seat(frame.classLabel, off.class, "BOTTOM", hpBar, "TOP", -4)
    seat(frame.guildLabel, off.guild, "BOTTOM", hpBar, "TOP", -4)
    seat(frame.gsLabel, off.gs, "TOP", bottomBar, "BOTTOM", 3)
end

-- Update info labels content from game state
local function UpdateInfoLabels(frame, unitType)
    -- Info labels belong to the target frame and nothing else.
    --
    -- A whitelist rather than a list of exclusions: your own class, gear score
    -- and guild are already known to you, target-of-target is far too small for
    -- the row, and the watch (tracked) target is a secondary frame the row only
    -- clutters. Stating the one frame that gets them means a frame added later
    -- stays clean by default instead of inheriting the labels by omission.
    if unitType ~= "target" then
        if frame.infoContainer then frame.infoContainer:Show(false) end
        return
    end
    local s = require("BetterBars/settings").getSettings()
    -- Per-item font size (infoOffsets carries it); global infoFontSize is
    -- the legacy fallback
    local off = s.infoOffsets or {}
    local fallbackFs = s.infoFontSize or 12
    local fsClass = (off.class and off.class.size) or fallbackFs
    local fsGS = (off.gs and off.gs.size) or fallbackFs
    local fsGuild = (off.guild and off.guild.size) or fallbackFs
    local showClass = s.showClass
    local showGS = s.showGearScore
    local showGuild = s.showGuild
    local anyVisible = showClass or showGS or showGuild

    -- Engine text shadow, own toggle separate from the HP/MP labels'
    local infoShadowOn = s.infoShadow == true
    for _, l in ipairs({ frame.classLabel, frame.gsLabel, frame.guildLabel }) do
        if l then pcall(function() l.style:SetShadow(infoShadowOn) end) end
    end
    
    if not frame.infoContainer then
        CreateInfoLabels(frame, unitType)
    end
    
    -- Class. The old chain led with api.Unit.UnitClass - which returns junk
    -- like "0" for players - and fell back to unitInfo.type/title, which
    -- painted literal "character" as a class. power_ranger_on's proven path:
    -- Ability.GetUnitClassName resolves the combo class name in the api
    -- itself (F_UNIT.GetPlayerJobName over the skillset triple) and is only
    -- gated on the unit being allowed, so it answers for any real target.
    -- A class value only counts when it is a real name: the api mapper hands
    -- back "0" for junk and "Pending" while the skillsets are unresolved -
    -- neither is worth displaying, so the label hides instead.
    local function isRealClassName(v)
        return type(v) == "string" and v ~= "" and v ~= "0"
            and string.lower(v) ~= "pending"
    end
    if frame.classLabel then
        if showClass then
            local cls = ""
            local okA, rA = pcall(api.Ability.GetUnitClassName, api.Ability, unitType)
            if okA and isRealClassName(rA) then
                cls = rA
            end
            -- Fallback: detailed info carries the raw skillset triple for
            -- player/team units; resolve it through the same api mapper.
            if cls == "" then
                local uid = api.Unit:GetUnitId(unitType)
                if uid and uid ~= 0 then
                    local okI, info = pcall(api.Unit.GetUnitInfoById, api.Unit, uid)
                    if okI and info and type(info.class) == "table" then
                        local okC, rC = pcall(api.Ability.GetClassNameFromSkillsetIds, api.Ability,
                            tonumber(info.class["1"]), tonumber(info.class["2"]), tonumber(info.class["3"]))
                        if okC and isRealClassName(rC) then
                            cls = rC
                        end
                    end
                end
            end
            frame.classLabel:SetText(cls)
            frame.classLabel:Show(cls ~= "")
        else
            frame.classLabel:Show(false)
        end
        frame.classLabel.style:SetFontSize(fsClass)
    end
    
    -- GS. 0 means "no data" (NPCs, units out of inspect range), not a real
    -- score - hide the label rather than print it.
    if frame.gsLabel then
        if showGS then
            local gs = tonumber(api.Unit:UnitGearScore(unitType))
            local hasGS = gs ~= nil and gs > 0
            frame.gsLabel:SetText(hasGS and tostring(gs) or "")
            frame.gsLabel:Show(hasGS)
        else
            frame.gsLabel:Show(false)
        end
        frame.gsLabel.style:SetFontSize(fsGS)
    end
    
    -- Guild
    if frame.guildLabel then
        if showGuild then
            local guild = ""
            local unitId = api.Unit:GetUnitId(unitType)
            if unitId and unitId ~= 0 then
                local ok, info = pcall(api.Unit.GetUnitInfoById, api.Unit, unitId)
                if ok and info and info.expeditionName and info.expeditionName ~= "" then
                    guild = info.expeditionName
                end
            end
            -- Fallback to UnitInfo(string) in case GetUnitInfoById failed
            if guild == "" then
                local ok, info = pcall(api.Unit.UnitInfo, api.Unit, unitType)
                if ok and info and info.expeditionName and info.expeditionName ~= "" then
                    guild = info.expeditionName
                end
            end
            frame.guildLabel:SetText(guild)
            frame.guildLabel:Show(guild ~= "")
        else
            frame.guildLabel:Show(false)
        end
        frame.guildLabel.style:SetFontSize(fsGuild)
    end
    
    AnchorInfoLabels(frame)

    if frame.infoContainer then
        frame.infoContainer:Show(anyVisible)
    end
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Updates the Styles for the frames
local function UpdateFrameStyles()
    -- Apply common styles and specific colors
    for unitType, frame in pairs(FrameLabels) do
        if frame then
            -- Each of these calls ApplyCommonStyle itself, so calling it here as
            -- well ran the whole common pass twice per frame per update - every
            -- anchor torn down and rebuilt for nothing.
            if unitType == "player" then StylePlayerFrame(frame) end
            if unitType == "target" then StyleTargetFrame(frame) end
            if unitType == "targettarget" then StyleTargetTargetFrame(frame) end
            if unitType == "watchtarget" then StyleWatchTargetFrame(frame) end

            -- Set HP bar color based on hostility using unitInfo.faction
            --
            -- The player frame is exempt from the whole resolution below: you
            -- are never hostile to yourself, and the fallbacks are not safe to
            -- run against "player". UnitIsForceAttack("player") answers true
            -- whenever something has made you force-attackable - Bloodlust and
            -- friends - which flipped isHostile and painted the player's own
            -- HP bar enemy-red mid-fight. The style key the game applies to the
            -- player is always L_HP_FRIENDLY, so friendly is simply correct.
            if unitType == "player" and frame.hpBar and frame.hpBar.statusBar then
                frame.hpBar.statusBar:SetBarColor(unpack(HP_COLORS))
                ApplyFillTexture(frame.hpBar, HP_COLORS)
                SetBarTrail(frame.hpBar, HP_COLORS)
            elseif frame.hpBar and frame.hpBar.statusBar then
                local isHostile = false -- Default to friendly/neutral
                local hadUnitInfo = false

                local unitId = nil
                if api.Unit and api.Unit.GetUnitId then
                    unitId = api.Unit:GetUnitId(unitType)
                end

                -- Housing: the game's addon api filters housing out of GetUnitId
                -- and every gated call (DISALLOWED_UNIT_TYPES), so houses never
                -- yield unitInfo - a named target with no unitId is a house.
                -- The game itself DOES restyle the frame for housing, so the
                -- hook's bbStyleKey is authoritative (verified with bbdebug
                -- dumps: ally house recorded "friendly", enemy "hostile").
                -- GetFactionName is no help here: for houses it returns the
                -- owning guild/nation name, which differs between allies.
                local isHousing = false
                if not unitId or unitId == 0 then
                    local okN, tName = pcall(api.Unit.UnitName, api.Unit, unitType)
                    isHousing = okN and tName ~= nil and tName ~= ""
                end

                if unitId and unitId ~= 0 then
                    local unitInfo = nil
                    -- Fallback to GetUnitInfoById(id) only â€” UnitInfo tried above
                    if api.Unit and api.Unit.GetUnitInfoById then
                        local success, result = pcall(api.Unit.GetUnitInfoById, api.Unit, unitId)
                        if success and result then
                            unitInfo = result
                            hadUnitInfo = true
                        else
                            api.Log:Warn("BetterBars: Failed to get unit info for unitType: " .. unitType .. " (ID: " .. unitId .. "). Error: " .. tostring(result))
                        end
                    end

                    if unitInfo then
                        -- Hostility: aggressive kills, otherwise check if proven friendly
                        if unitInfo.isAggressive then
                            isHostile = true
                        elseif unitInfo.faction == "hostile" then
                            isHostile = true
                        elseif unitInfo.faction and unitInfo.faction ~= "" and unitInfo.faction ~= "neutral" and unitInfo.faction ~= "friendly" then
                            -- Real faction name â€” check if it matches player
                            local okPF, pf = pcall(api.Unit.GetFactionName, api.Unit, "player")
                            if okPF and pf and pf ~= "" then
                                if unitInfo.faction ~= pf then
                                    isHostile = true  -- different faction = enemy
                                end
                                -- same faction = friendly (isHostile stays false)
                            else
                                isHostile = true  -- can't confirm friendly â†’ enemy
                            end
                        end
                        -- If faction is nil/empty/neutral/friendly here, isHostile stays false = friendly
                    end

                else
                    -- Don't log spam for types that might not always have a unitId (like targettarget initially)
                    -- api.Log:Warn("BetterBars: Could not get valid unitId for unitType: " .. unitType .. ". Defaulting color.")
                end

                -- Try UnitInfo(unitType) â€” takes a unit string like "target", works even when unitId is 0
                -- This runs AFTER the unitId block so it doesn't interfere with hadUnitInfo from GetUnitInfoById
                if not hadUnitInfo and api.Unit and api.Unit.UnitInfo then
                    local success, result = pcall(api.Unit.UnitInfo, api.Unit, unitType)
                    if success and result then
                        -- Hostility checks
                        if result.isAggressive then
                            isHostile = true
                            hadUnitInfo = true
                        elseif result.faction then
                            hadUnitInfo = true
                            if result.faction == "hostile" then
                                isHostile = true
                            elseif result.faction ~= "" and result.faction ~= "neutral" and result.faction ~= "friendly" then
                                local okPF, pf = pcall(api.Unit.GetFactionName, api.Unit, "player")
                                if okPF and pf and pf ~= "" and result.faction ~= pf then
                                    isHostile = true
                                end
                            end
                        end
                    end
                end


                -- Engine-level fallbacks (for all frame types, including buildings with no unitInfo)
                if not isHostile then
                    local okFA, isFA = pcall(api.Unit.UnitIsForceAttack, api.Unit, unitType)
                    if okFA and isFA then isHostile = true end
                end
                if not isHostile then
                    local maxHP = api.Unit:UnitMaxHealth(unitType)
                    if maxHP and maxHP <= 0 then isHostile = true end
                end
                -- No unitInfo data (buildings) and nothing proved friendly â†’ assume hostile
                if not isHostile and not hadUnitInfo then
                    isHostile = true
                end
                local s = require("BetterBars/settings").getSettings()
                -- Prefer what the game itself decided, recorded by the
                -- ApplyBarTexture hook. The block above is now only a fallback
                -- for frames whose hook has not fired yet - notably its final
                -- `not hadUnitInfo -> hostile` guess, which paints anything it
                -- cannot identify enemy-red.
                -- Either source may report hostility and neither vetoes the
                -- other: the game's own style key when the hook has fired, and
                -- this addon's own resolution otherwise. Requiring the key to be
                -- absent before trusting isHostile meant one stale key disabled
                -- hostility colouring entirely.
                local hpColor = HP_COLORS
                -- The game's own preemptive-strike verdict wins outright. It
                -- knows something this addon cannot derive - who landed the
                -- first hit - so no amount of faction resolution should be
                -- allowed to overwrite it with plain enemy red.
                if frame.bbStyleKey == "preemptive"
                    and s.showHostilityColor ~= false then
                    hpColor = PREEMPT_COLORS
                elseif isHousing then
                    -- Trust the game's own verdict alone. The "no unitInfo =
                    -- assume hostile" guess below is exactly what painted every
                    -- house red: it OR'd over the game's correct friendly key.
                    if frame.bbStyleKey == "hostile" and s.showHostilityColor ~= false then
                        hpColor = EHP_COLORS
                    end
                elseif (frame.bbStyleKey == "hostile" or isHostile)
                    and s.showHostilityColor ~= false then
                    hpColor = EHP_COLORS
                end
                frame.hpBar.statusBar:SetBarColor(unpack(hpColor))
                ApplyFillTexture(frame.hpBar, hpColor)
                SetBarTrail(frame.hpBar, hpColor)
                -- The trail has to be set here, not in the Style*Frame pass:
                -- every STATUSBAR_STYLE entry shares one afterImage table, and
                -- hostility is only known at this point. Re-applying the style
                -- is what pushes the new colour into the bar.
                -- The trail is no longer set here: each style entry carries its
                -- own, refreshed by RefreshAfterImageColors when colours change.
            end
             -- Ensure MP color is also applied (redundant if already in ApplyCommonStyle, but safe)
            if frame.mpBar and frame.mpBar.statusBar then
                frame.mpBar.statusBar:SetBarColor(unpack(MP_COLORS))
                ApplyFillTexture(frame.mpBar, MP_COLORS, true)
                SetBarTrail(frame.mpBar, MP_COLORS)
            end
        
            -- Update info labels (Class, GS, Guild) for this frame
            pcall(UpdateInfoLabels, frame, unitType)
        end
    end
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Function to update colors from settings
function UpdateColorsFromSettings()
    local settings = require("BetterBars/settings")
    local colors = settings.getColors()
    
    if not colors then 
        api.Log:Err("BetterBars: No colors returned from settings.getColors()")
        return 
    end
    
    -- Update HP colors
    if colors.hp then
        HP_COLORS = {
            colors.hp.r/255,    -- Convert from 0-255 to 0-1 range
            colors.hp.g/255,
            colors.hp.b/255,
            colors.hp.a or 1    -- Default to 1 if alpha is not set
        }
    else
        api.Log:Warn("BetterBars: No HP colors in settings, using default.")
    end
    
    -- Update EHP colors
    if colors.ehp then
        EHP_COLORS = {
            colors.ehp.r/255,    -- Convert from 0-255 to 0-1 range
            colors.ehp.g/255,
            colors.ehp.b/255,
            colors.ehp.a or 1    -- Default to 1 if alpha is not set
        }
    end
    
    -- Update MP colors
    if colors.mp then
        MP_COLORS = {
            colors.mp.r/255,    -- Convert from 0-255 to 0-1 range
            colors.mp.g/255,
            colors.mp.b/255,
            colors.mp.a or 1    -- Default to 1 if alpha is not set
        }
    else
        api.Log:Warn("BetterBars: No MP colors in settings, using default.")
    end

    -- Cast bar color
    if colors.cast then
        CAST_COLORS = {
            colors.cast.r/255,
            colors.cast.g/255,
            colors.cast.b/255,
            colors.cast.a or 1
        }
    end
    
    -- The preemptive-strike red follows the enemy colour, so it has to be
    -- re-derived whenever that changes - before the trails are refreshed, since
    -- those read it.
    PREEMPT_COLORS = DerivePreemptColors(EHP_COLORS)

    -- Derive each style's damage trail from the colour it paints with, before
    -- restyling - UpdateFrameStyles re-applies the styles and would otherwise
    -- push the previous trail colours back onto the bars.
    RefreshAfterImageColors()

    -- Update frame styles with new colors
    UpdateFrameStyles()

    -- Pets are not in FrameLabels, so UpdateFrameStyles misses them. Restyling
    -- here keeps them on the current colours: OnLoad used to paint them before
    -- the settings were loaded, leaving the placeholder colours on the bars
    -- until the next SPAWN_PET, and colour changes never reached them at all.
    pcall(StyleAllPetFrames)

    -- Cast bar: creation, colour and the on/off toggle all resolve here, so
    -- a settings change applies live.
    pcall(SyncCastBar)

    -- Abyssal charge bar. Refresh re-attempts setup if the bubble bar did not
    -- exist yet at load, so a class that gains it later still gets picked up.
    pcall(function() require("BetterBars/abyssal").Refresh() end)
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Handler for chat messages to detect commands
local DBG_DUMP_PATH = "BetterBars/bbdebug_dump.txt"
-- Overwritten each run rather than appended: this is a snapshot of current
-- state, so the latest one is the only one that matters.
local INFO_DUMP_PATH = "BetterBars/bbinfo_dump.txt"
-- Cached: this handler runs on EVERY chat line, and the player's name never
-- changes mid-session - two api calls per message added up to nothing but
-- waste.
local cachedPlayerName = nil
local function HandleChatCommand(channel, unit, isHostile, name, message, speakerInChatBound, specifyName, factionName, trialPosition)
  -- Check if it's the player's message
  if not cachedPlayerName then
    cachedPlayerName = api.Unit:GetUnitNameById(api.Unit:GetUnitId("player"))
  end
  local playerName = cachedPlayerName
  
  -- If the message is from the player and is our command
  if playerName == name and message == "bb" then
    local ok, settings_page = pcall(require, "BetterBars/settings_page")
    if not ok then
      return
    end
    if settings_page and settings_page.openSettingsWindow then
      pcall(function() 
        settings_page.openSettingsWindow() 
      end)
    else
      api.Log:Err("BetterBars: settings_page missing openSettingsWindow")
    end
  end

  -- "bbinfo": report what the addon is actually doing right now.
  --
  -- Chiefly answers whether the border is the exact ninepart cell or the
  -- approximate flat-rectangle fallback - the two look different at the corners
  -- and there is no other way to tell from in-game. Also dumps the live bar
  -- heights, which is how you catch the client overwriting them, and the pet
  -- frames, which confirms the pairs() enumeration is finding them.
  if playerName == name and message == "bbinfo" then
    local s = require("BetterBars/settings").getSettings()
    -- Mirrored to chat AND to a file. api.Log:Info may or may not reach the
    -- chat window, and the report is worth having either way; File:Write puts
    -- it at <Addon>/BetterBars/bbinfo_dump.txt (ADDON_API.baseDir is the
    -- client's UCC directory with "USER" stripped, plus "/Addon").
    --
    -- The line array is handed over whole rather than concatenated: File:Write
    -- runs its argument through serializeTable, which %q-quotes a bare string
    -- and escapes every newline into one long blob. A table comes out as one
    -- readable quoted line per entry.
    local lines = {}
    local function say(t)
      api.Log:Info(t)
      table.insert(lines, t)
    end
    local pathText = "not built yet"
    if bbBackdropPath == "ninepart" then
      pathText = "ninepart cell (exact)"
    elseif bbBackdropPath == "fallback" then
      pathText = "flat rectangles (approximate)"
    end
    say("=== BetterBars " .. tostring(BetterBars.version) .. " ===")
    say("  backdrop: " .. pathText)
    say(string.format("  geometry: shift %d, mp gap %d, bg outset %d",
      BAR_SHIFT_X, MP_BAR_GAP, BAR_BG_OUTSET))
    -- 1.0 means UI units and device pixels are the same thing and scaling is
    -- exonerated; anything else and every thin element is fractional.
    local sc = UIScale()
    say(string.format("  ui scale: %.4f  (1 device px = %.4f UI units)", sc, Px(1)))
    say(string.format("  settings: hp %s, mp %s, texture %s, bg %.1f",
      tostring(s.barHeight and s.barHeight.hp),
      tostring(s.barHeight and s.barHeight.mp),
      tostring(s.barTexture), tonumber(s.backgroundOpacity) or 0))
    -- Describe a bar's backdrop by what it actually holds, so a fallback that
    -- half-built (missing body, short on ramp rows) is visible rather than
    -- being reported as a working "flat".
    local function describeBg(b)
      local out = "none"
      pcall(function()
        if not b or not b.bbBg then return end
        local g = b.bbBg
        if g.nine then out = "nine" return end
        out = string.format("flat %s/%de/%df",
          g.body and "body" or "NOBODY",
          g.edges and #g.edges or 0,
          g.fades and #g.fades or 0)
      end)
      return out
    end
    for _, ut in ipairs({ "player", "target", "targettarget", "watchtarget" }) do
      local f = FrameLabels[ut]
      if f then
        local hph, mph, vis = "?", "-", "-"
        pcall(function() if f.hpBar then hph = tostring(f.hpBar:GetHeight()) end end)
        pcall(function() if f.mpBar then mph = tostring(f.mpBar:GetHeight()) end end)
        pcall(function()
          if f.mpBar then vis = f.mpBar:IsVisible() and "shown" or "hidden" end
        end)
        say(string.format("  %-12s hp %-4s mp %-4s %-6s key=%s",
          ut, hph, mph, vis, tostring(f.bbStyleKey)))
        -- deco/line are the vanilla separators the client re-shows on every
        -- target-type change; VISIBLE here means the re-hide is not sticking.
        local deco, ln = "-", "-"
        pcall(function()
          if f.hpBar_deco then deco = f.hpBar_deco:IsVisible() and "VISIBLE" or "hidden" end
        end)
        pcall(function()
          if f.line then ln = f.line:IsVisible() and "VISIBLE" or "hidden" end
        end)
        say(string.format("      hpBg %-18s mpBg %-18s deco %-7s line %s",
          describeBg(f.hpBar), describeBg(f.mpBar), deco, ln))
      end
    end
    if petFrame then
      local found = false
      pcall(function()
        for k, f in pairs(petFrame) do
          if f and f.hpBar then
            found = true
            local hph, mph = "?", "-"
            pcall(function() hph = tostring(f.hpBar:GetHeight()) end)
            pcall(function() if f.mpBar then mph = tostring(f.mpBar:GetHeight()) end end)
            say(string.format("  pet[%-6s] hp %-4s mp %-4s", tostring(k), hph, mph))
          end
        end
      end)
      if not found then say("  pet: none out (or not enumerable)") end
    end
    local okT, ts = pcall(api.Time.GetLocalTime, api.Time)
    say("=== end (t=" .. (okT and tostring(ts) or "?") .. ") ===")
    local okW, werr = pcall(function()
      api.File:Write(INFO_DUMP_PATH, lines)
    end)
    if okW then
      api.Log:Info("BetterBars: written to " .. INFO_DUMP_PATH)
    else
      api.Log:Err("BetterBars: could not write " .. INFO_DUMP_PATH
        .. " - " .. tostring(werr))
    end
  end

  -- Quick fill-texture switch, so a PNG can be tried without the settings
  -- window: "bbtex retail" | "bbtex none", or any file dropped into textures/.
  -- The leading "bar_" is optional - the files are textures/bar_<name>.png.
  if playerName == name and string.sub(message, 1, 6) == "bbtex " then
    local which = string.sub(message, 7)
    which = string.gsub(which, "^%s+", "")
    which = string.gsub(which, "%s+$", "")
    if which ~= "" then
      if which ~= "none" and string.sub(which, 1, 4) ~= "bar_" then
        which = "bar_" .. which
      end
      local settings_module = require("BetterBars/settings")
      settings_module.updateSetting("barTexture", which)
      settings_module.saveSettings()   -- emits the update event, which restyles
      api.Log:Info("BetterBars: fill texture = " .. which)
    end
  end

  -- Debug command: dump faction/unit info for current target
  -- "bbdebug" alone, or with a label so dumps are self-describing:
  -- "bbdebug enemy" / "bbdebug ally" (any single word is accepted as label).
  local dbgLabel = nil
  if playerName == name then
    if message == "bbdebug" then
      dbgLabel = "unlabeled"
    else
      dbgLabel = string.match(message, "^bbdebug%s+(%a+)%s*$")
    end
  end
  if dbgLabel then
    local lines = {}
    local function say(text)
      api.Log:Info(text)
      table.insert(lines, text)
    end
    local function tryAPI(label, fn, ...)
      local ok, result = pcall(fn, ...)
      if ok then
        if type(result) == "table" then
          local parts = {}
          for k, v in pairs(result) do
            table.insert(parts, tostring(k) .. "=" .. tostring(v))
          end
          say("  " .. label .. " => {" .. table.concat(parts, ", ") .. "}")
        else
          say("  " .. label .. " => " .. tostring(result))
        end
      else
        say("  " .. label .. " => ERROR: " .. tostring(result))
      end
    end

    local now = ""
    local okT, ts = pcall(api.Time.GetLocalTime, api.Time)
    if okT then now = tostring(ts) end
    say("=== BetterBars Debug [" .. dbgLabel .. "] t=" .. now .. " ===")
    local t = "target"
    local uid = api.Unit:GetUnitId(t)
    say("unitId=" .. tostring(uid))

    -- Ungated calls: these bypass the api's housing filter, so they answer
    -- even when unitId is nil (housing target). Probe them first, always.
    tryAPI("UnitName (ungated)", api.Unit.UnitName, api.Unit, t)
    tryAPI("GetFactionName (ungated)", api.Unit.GetFactionName, api.Unit, t)
    tryAPI("Player GetFactionName", api.Unit.GetFactionName, api.Unit, "player")
    tryAPI("UnitIsForceAttack (ungated)", api.Unit.UnitIsForceAttack, api.Unit, t)
    tryAPI("UnitIsTeamMember (ungated)", api.Unit.UnitIsTeamMember, api.Unit, t)
    tryAPI("UnitTeamAuthority (ungated)", api.Unit.UnitTeamAuthority, api.Unit, t)
    local tf = FrameLabels["target"]
    say("  target bbStyleKey => " .. tostring(tf and tf.bbStyleKey))

    if uid and uid ~= 0 then
      -- Identity
      tryAPI("UnitName", api.Unit.UnitName, api.Unit, t)
      tryAPI("UnitClass", api.Unit.UnitClass, api.Unit, t)
      tryAPI("UnitGearScore", api.Unit.UnitGearScore, api.Unit, t)
      tryAPI("GetUnitInfoById", api.Unit.GetUnitInfoById, api.Unit, uid)

      -- Faction / hostility
      tryAPI("GetFactionName", api.Unit.GetFactionName, api.Unit, t)
      tryAPI("UnitIsTeamMember", api.Unit.UnitIsTeamMember, api.Unit, t)
      tryAPI("UnitIsForceAttack", api.Unit.UnitIsForceAttack, api.Unit, t)
      tryAPI("UnitIsOffline", api.Unit.UnitIsOffline, api.Unit, t)

      -- Vitals
      tryAPI("UnitHealth", api.Unit.UnitHealth, api.Unit, t)
      tryAPI("UnitMaxHealth", api.Unit.UnitMaxHealth, api.Unit, t)
      tryAPI("UnitMana", api.Unit.UnitMana, api.Unit, t)
      tryAPI("UnitMaxMana", api.Unit.UnitMaxMana, api.Unit, t)
      tryAPI("UnitDistance", api.Unit.UnitDistance, api.Unit, t)
      tryAPI("UnitModifierInfo", api.Unit.UnitModifierInfo, api.Unit, t)
      tryAPI("UnitBuffCount", api.Unit.UnitBuffCount, api.Unit, t)
      tryAPI("UnitDeBuffCount", api.Unit.UnitDeBuffCount, api.Unit, t)

      -- Player baseline
      say("-- Player baseline --")
      local puid = api.Unit:GetUnitId("player")
      say("player unitId=" .. tostring(puid))
      tryAPI("Player UnitClass", api.Unit.UnitClass, api.Unit, "player")
      tryAPI("Player UnitGearScore", api.Unit.UnitGearScore, api.Unit, "player")
      tryAPI("Player GetUnitInfoById", api.Unit.GetUnitInfoById, api.Unit, puid)
      tryAPI("Player UnitIsTeamMember", api.Unit.UnitIsTeamMember, api.Unit, "player")
      tryAPI("Player UnitIsForceAttack", api.Unit.UnitIsForceAttack, api.Unit, "player")
    else
      say("  No unitId: no target, or a housing-type unit the api filters out")
    end
    say("=== End Debug ===")

    -- Append this run to a dump file so labelled runs can be compared outside
    -- the game. File:Read returns what File:Write stored - one string - or
    -- nil before the first run.
    local okR, existing = pcall(function() return api.File:Read(DBG_DUMP_PATH) end)
    local prefix = (okR and type(existing) == "string") and (existing .. "\n\n") or ""
    local okW = pcall(function()
      api.File:Write(DBG_DUMP_PATH, prefix .. table.concat(lines, "\n"))
    end)
    if okW then
      api.Log:Info("BetterBars: dump appended to " .. DBG_DUMP_PATH)
    else
      api.Log:Err("BetterBars: could not write " .. DBG_DUMP_PATH)
    end
  end
end

local function OnLoad()
  SetupFrame("player", UIC.PLAYER_UNITFRAME)
  SetupFrame("target", UIC.TARGET_UNITFRAME)
  SetupFrame("targettarget", UIC.TARGET_OF_TARGET_FRAME)
  SetupFrame("watchtarget", UIC.WATCH_TARGET_FRAME)

  -- Abyssal charge bar: restyles the client's bubble action bar in place.
  -- Silently does nothing for classes without the high-ability feature set,
  -- which is most of them - the bar simply is not created for those.
  pcall(function() require("BetterBars/abyssal").Setup() end)

  UpdateFrameStyles()

  -- Pets already out when the addon loads (a /reload with a summon active)
  -- never fire SPAWN_PET again. They are styled by UpdateColorsFromSettings
  -- further down, AFTER the settings load - styling them here painted the
  -- placeholder colours (that red/purple pet bar) before the real ones
  -- existed, and nothing repainted them afterwards.

  -- Register for chat message events
  onEvent("CHAT_MESSAGE", HandleChatCommand)

  -- Set up TARGET_CHANGED event handler on the target frame
  local targetFrame = FrameLabels["target"]
  if targetFrame and targetFrame.eventWindow then
    function targetFrame.eventWindow:OnEvent(event)
      if event == "TARGET_CHANGED" then
        -- Immediately update frame styles
        UpdateFrameStyles()
      end
    end
    targetFrame.eventWindow:SetHandler("OnEvent", targetFrame.eventWindow.OnEvent)
    targetFrame.eventWindow:RegisterEvent("TARGET_CHANGED")
  else
    api.Log:Err("Failed to set up TARGET_CHANGED event handler")
  end

  -- Modify existing label update functions
  -- NOTE: each iteration creates a new `capturedType` local so closures
  -- capture the correct per-frame unitType (Lua 5.1 closure-in-loop fix)
  for unitType, frame in pairs(FrameLabels) do
      local hpLabel = frame.hpBar and frame.hpBar.hpLabel
      local mpLabel = frame.mpBar and frame.mpBar.mpLabel
      local capturedType = unitType

      -- Centring is NOT done here any more - SeatBars re-states it on every
      -- restyle. Only the SetText wrap stays a one-shot, because wrapping is
      -- the one thing that must not happen twice.
      if hpLabel and not hpLabel.SetTextOrig then
          -- Guarded on SetTextOrig. /reload does not fire OnUnload, so OnLoad
          -- can run again over an already-wrapped label; without the guard
          -- SetTextOrig would capture the previous WRAPPER, chaining a second
          -- copy onto every call and leaving OnUnload restoring a wrapper
          -- instead of the original. WrapPetLabel has always guarded this way.
          hpLabel.SetTextOrig = hpLabel.SetText
          hpLabel.SetText = function(self, text)
              pcall(function()
                  local s = require("BetterBars/settings").getSettings()
                  self.style:SetFontSize(s.labelFontSize or FONT_SIZE.MIDDLE)
                  pcall(function() self.style:SetShadow(s.labelShadow == true) end)
                  -- nil from formatLabelText = api can't read this unit
                  -- (housing). showHousingHP decides whether the game's own
                  -- text shows there; off keeps the label blank.
                  local fallback = s.showHousingHP and text or ""
                  self:SetTextOrig(formatLabelText(capturedType, true) or fallback)
                  SyncFillVisibility(capturedType, true)
              end)
          end
      end

      if mpLabel and not mpLabel.SetTextOrig then
          mpLabel.SetTextOrig = mpLabel.SetText
          mpLabel.SetText = function(self, text)
              pcall(function()
                  local s = require("BetterBars/settings").getSettings()
                  self.style:SetFontSize(s.labelFontSize or FONT_SIZE.MIDDLE)
                  pcall(function() self.style:SetShadow(s.labelShadow == true) end)
                  local fallback = s.showHousingHP and text or ""
                  self:SetTextOrig(formatLabelText(capturedType, false) or fallback)
                  SyncFillVisibility(capturedType, false)
              end)
          end
      end
  end
  
  -- Load settings
  local settings_module = require("BetterBars/settings")
  settings_module.loadSettings()
  
  -- Apply colors from settings
  UpdateColorsFromSettings()
  
  -- Register for settings update event (delegates to shared color-update function)
  onEvent("BETTERBARS_SETTINGS_UPDATED", function()
      UpdateColorsFromSettings()
  end)
  
  -- Also register for specific color change events from the color picker
  onEvent("BETTERBARS_COLOR_CHANGED", function(colorType, r, g, b, a)
      local changed = false
      -- Update the global color arrays directly
      if colorType == "hp" then
          HP_COLORS = {r, g, b, a or 1}
          changed = true
      elseif colorType == "mp" then
          MP_COLORS = {r, g, b, a or 1}
          changed = true
      elseif colorType == "ehp" then
          EHP_COLORS = {r, g, b, a or 1}
          changed = true
      end

      -- If a color changed, update all frame styles
      if changed then
          UpdateFrameStyles()
      end
  end)
  
  -- Load settings page module and initialize it
  local ok_sp, settings_page = pcall(require, "BetterBars/settings_page")
  if ok_sp and settings_page and settings_page.Load then
      pcall(function() settings_page.Load() end)
  end
  
  -- Register for addon settings UI event
  onEvent("ADDON_SETTINGS_OPENED", function(addonName)
    if addonName == "BetterBars" then
      local settings_page = require("BetterBars/settings_page")
      if settings_page and settings_page.openSettingsWindow then
        pcall(function() 
          settings_page.openSettingsWindow() 
        end)
      else
        api.Log:Err("BetterBars: Failed to open settings window from ADDON_SETTINGS_OPENED event")
      end
    end
  end)

  -- Setup the addon in the addon list
  pcall(function()
    if X2Addon then
      -- Register addon with settings button
      if X2Addon.Register then
        X2Addon:Register("BetterBars", BetterBars)
      end
      
      -- Add settings button
      if X2Addon.RegisterAddonButton then
        X2Addon:RegisterAddonButton("BetterBars", function()
          local settings_page = require("BetterBars/settings_page")
          if settings_page and settings_page.openSettingsWindow then
            pcall(function() settings_page.openSettingsWindow() end)
          else
            api.Log:Err("BetterBars: Failed to open settings, settings_page not available")
          end
        end)
      end
    end
  end)
  
  -- Register in ESC menu Addon Options (self-contained michaelClient)
  pcall(function()
    local configMenu = ADDON:GetContent(UIC.SYSTEM_CONFIG_FRAME)
    if not configMenu then return end
    
    -- Build michaelClient if no other addon has yet
    if not configMenu.michaelClient then
      local mc = configMenu:CreateChildWidget("label", "mc_BetterBars", 0, true)
      mc:AddAnchor("TOPLEFT", configMenu, -110, 5)
      mc:SetExtent(110, 28)
      mc:SetText("Addon Options")
      configMenu.michaelClient = mc
      configMenu.michaelClient.addons = {}
      
      mc.bg = mc:CreateNinePartDrawable("ui/common/tab_list.dds", "background")
      mc.bg:SetTextureInfo("bg_quest")
      mc.bg:SetColor(0, 0, 0, 0.5)
      mc.bg:AddAnchor("TOPLEFT", mc, 0, 0)
      mc.bg:AddAnchor("BOTTOMRIGHT", mc, 0, 0)
      
      mc.addonCount = 0
      function configMenu.michaelClient:AddAddon(title, callback)
        if self.addons[title] then
          self.addons[title]:SetHandler("OnClick", function() callback() end)
          self.addons[title]:Show(true)
          return
        end
        self.addonCount = self.addonCount + 1
        local btn = self:CreateChildWidget("button", "bb_addon_" .. tostring(self.addonCount), 0, true)
        btn:SetText(title)
        btn:AddAnchor("TOPLEFT", mc, 5, self.addonCount * 30)
        btn:SetExtent(100, 28)
        btn:SetHandler("OnClick", function() callback() end)
        btn:Show(true)
        self.addons[title] = btn
        
        local cw = mc.bg:GetWidth()
        mc.bg:SetExtent(cw, self.addonCount * 30)
        mc.bg:RemoveAllAnchors()
        mc.bg:AddAnchor("TOPLEFT", mc, 0, 0)
        mc.bg:AddAnchor("BOTTOMRIGHT", mc, 0, self.addonCount * 30 + 10)
      end
    end
    
    -- Register BetterBars (michaelClient now definitely exists)
    if configMenu.michaelClient.AddAddon then
      configMenu.michaelClient:AddAddon("BetterBars", function()
        local settings_page = require("BetterBars/settings_page")
        if settings_page and settings_page.openSettingsWindow then
          pcall(function() settings_page.openSettingsWindow() end)
        end
      end)
    end
  end)

  -- ESCMenu integration (optional). With the ESCMenu addon installed this is
  -- our settings row in its menu; without it, the queue is inert data and the
  -- michaelClient panel above is what players see. The name matches the
  -- AddAddon title EXACTLY so ESCMenu dedupes the two registrations (this one
  -- wins). Registered from main.lua on purpose: require'd modules write
  -- globals into a private environment and ESCMenu would never see it.
  pcall(function()
    ESCMenu = ESCMenu or {}
    ESCMenu.queue = ESCMenu.queue or {}
    table.insert(ESCMenu.queue, {
      name = "BetterBars",
      callback = function()
        local settings_page = require("BetterBars/settings_page")
        if settings_page and settings_page.openSettingsWindow then
          pcall(function() settings_page.openSettingsWindow() end)
        end
      end,
    })
  end)
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function OnUnload()
  -- No api.Off in this API, so event handlers cannot be unregistered here (see
  -- onEvent). Everything below undoes the frame changes, which is the part that
  -- actually can be undone.
  registeredHandlers = {}

  for unitType, frame in pairs(FrameLabels) do
      local hpLabel = frame.hpBar and frame.hpBar.hpLabel
      local mpLabel = frame.mpBar and frame.mpBar.mpLabel

      if hpLabel and hpLabel.SetTextOrig then
          hpLabel.SetText = hpLabel.SetTextOrig
          hpLabel.SetTextOrig = nil
          -- Reset label style
          hpLabel:RemoveAllAnchors()
          hpLabel:AddAnchor("BOTTOMRIGHT", frame.hpBar, -1, -1)
          hpLabel.style:SetFontSize(FONT_SIZE.SMALL)
          hpLabel.style:SetAlign(ALIGN.RIGHT)
      end

      if mpLabel and mpLabel.SetTextOrig then
          mpLabel.SetText = mpLabel.SetTextOrig
          mpLabel.SetTextOrig = nil
          -- Reset label style
          mpLabel:RemoveAllAnchors()
          mpLabel:AddAnchor("TOPRIGHT", frame.mpBar, -1, 2)
          mpLabel.style:SetFontSize(FONT_SIZE.SMALL)
          mpLabel.style:SetAlign(ALIGN.RIGHT)
      end

      -- Reset frame styles
      if frame.hpBar then
        frame.hpBar:SetHeight(19)  -- Default height
      end
      if frame.mpBar then
        frame.mpBar:SetHeight(13)  -- Default height
      end
      
      -- Hide and discard info labels
      if frame.infoContainer then
          pcall(function()
              frame.infoContainer:Show(false)
              frame.classLabel = nil
              frame.gsLabel = nil
              frame.guildLabel = nil
              frame.infoContainer = nil
          end)
      end
  end

  FrameLabels = {}
  
  -- Unload settings page. Every other entry point into this module goes through
  -- pcall; this one did not, so a module that failed to load would turn unload
  -- into an error and skip whatever ran after it.
  pcall(function()
      local settings_page = require("BetterBars/settings_page")
      if settings_page and settings_page.unload then
          settings_page.unload()
      end
  end)
end

-- Handler for opening settings window
local function OnSettingToggle()
  local settings_page = require("BetterBars/settings_page")
  if settings_page and settings_page.openSettingsWindow then
    pcall(function() settings_page.openSettingsWindow() end)
  else
    api.Log:Err("BetterBars: Failed to open settings from OnSettingToggle")
  end
end

BetterBars.OnLoad = OnLoad
BetterBars.OnUnload = OnUnload
BetterBars.OnSettingToggle = OnSettingToggle

return BetterBars 
