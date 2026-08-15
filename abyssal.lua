local api = require("api")

-- Abyssal charge bar.
--
-- Restyles the client's own bubble action bar in place rather than drawing a
-- new one. The vanilla bar already solves show/hide, slot count, Shift-drag,
-- saved position and per-scale re-layout (bubble_action_bar.lua:186-205), and
-- all of that is free if we keep its window and only replace its art.
--
-- The resource itself:
--   api.Unit:GetHighAbilityRscInfo() -> { maxHighAbilityRsc,
--                                          highAbilityPreciseRsc,  -- x100
--                                          show }
-- Ungated and takes no unit - it is always the player's own. The client's HUD
-- reads exactly these three (bubble_action_bar.lua:34-39).
--
-- The x100 is the interesting part. Vanilla throws the fraction away: it lights
-- bubble i when floor(precise/100) >= i and animates between whole steps. We
-- keep it, so the slot currently filling shows a partial fill. That is the one
-- thing this can show that the stock bar cannot.
local abyssal = {}

-- Pip diameter, from settings.
--
-- The client's own cell is 49x49 with a 2px gap (bubble_action_bar_view.lua:1-4),
-- so the pip is sized within that: smaller reads as separate slots, larger fills
-- the cell. Clamped at both ends - past the cell height the neighbouring slots
-- would touch, and below a few pixels the ring and fill collapse into each other.
-- The function that reads it lives below settings(), which it needs.
local PIP_SIZE_DEFAULT = 35
local PIP_SIZE_MIN = 8
-- Above the client's 49px cell the pips overhang the (invisible) slots, which
-- is fine: spacing follows pip size rather than the client's pitch, so they
-- never collide with each other.
local PIP_SIZE_MAX = 69

-- Two authored states rather than drawn shapes.
--
-- abyss_on.png and abyss_off.png are the lit and dark halves of the artwork,
-- cut from the same source at the same scale and centred on their own bounding
-- boxes, so they overlay exactly - the lit state can simply be shown on top of
-- the dark one without either shifting.
--
-- Loaded with SetTgaTexture on an ImageDrawable, which works in this client
-- (unlike SetTgaTexture on a NinePartDrawable, the reason the bar backdrop is
-- stuck on its flat fallback).
local PIP_TEXTURE_ON = "../Addon/BetterBars/textures/abyss_on.png"
local PIP_TEXTURE_OFF = "../Addon/BetterBars/textures/abyss_off.png"
local PIP_TEXTURE_SIZE = 128

-- UI scale. Same rules as main.lua and settings_page.lua - see UI_SCALING.md.
-- Device pixels = UI units * scale, and the scale is usually neither 1 nor
-- round, so a 1-unit border is a fraction of a pixel and rasterises away.
local function UIScale()
    local s
    pcall(function() s = api.Interface:GetUIScale() end)
    if type(s) ~= "number" or s <= 0 then return 1 end
    return s
end

local function Px(n)
    return n / UIScale()
end

local frame = nil
-- The unwrapped ShowBubbleActionBar, kept so the OFF path can ask the client to
-- rebuild its own art without going back through our hook and recursing.
local origShow = nil
-- Last known state of the toggle, so switching OFF can restore vanilla exactly
-- once rather than on every repaint.
local lastEnabled = nil
-- Guards the restore call: origShow triggers the client's own repaint chain,
-- which lands back in ours.
local restoring = false

-- Session ownership token. The client's bubble bar frame - and everything
-- stamped on it, including our hook closures - survives /reload, while this
-- module is recreated fresh. The old closures kept firing with the OLD
-- session's settings module, so toggling or resizing abyssal after a reload
-- had two sessions fighting over the art: changes appeared to revert and
-- pips flickered off. Each load stamps the frame with its own token (a table,
-- unique by identity); repaints from a load that no longer owns the frame go
-- inert.
local myToken = {}

local function settings()
    return require("BetterBars/settings").getSettings()
end

-- The pips are plain artwork now - the Abyss colour option is gone (3.1).
-- paintPip still calls SetColor(1,1,1,1) rather than nothing: pip drawables
-- persist on the client's icons across /reload, so a tint applied by an older
-- build would otherwise stick for the rest of the session.

local function pipDiameter(iconH)
    local d = tonumber(settings().abyssalSize) or PIP_SIZE_DEFAULT
    if d < PIP_SIZE_MIN then d = PIP_SIZE_MIN end
    -- The cell used to be the ceiling; since our spacing follows pip size the
    -- only cap left is taste. iconH is still accepted for the callers' sake.
    if d > PIP_SIZE_MAX then d = PIP_SIZE_MAX end
    return d
end

-- Hide the five effect drawables the client stacks on every slot.
--
-- They live in parallel arrays on the window (bubble_action_bar_view.lua:27-55):
-- empty, yellow, red, full and light - the last offset (-7,-10) so its glow
-- overhangs the cell. All are effect drawables, so both SetVisible and Show are
-- attempted: the addon has no guarantee which flag an effect drawable honours,
-- and clearing one may not clear the other.
--
-- Re-hidden on every repaint, not once at setup: CreateEffectBubbleOn/Init/Off
-- rebuild and re-show them whenever the charge count changes.
local VANILLA_LAYERS = { "empty", "yellow", "red", "full", "light" }

local function hideVanillaArt(i)
    for _, key in ipairs(VANILLA_LAYERS) do
        local arr = frame[key]
        local d = arr and arr[i]
        if d then
            pcall(function() d:SetVisible(false) end)
            pcall(function() d:Show(false) end)
            -- Stopping the EFFECT matters as much as hiding the drawable.
            -- These are effect drawables, and
            -- F_ANIMATION.StartEffectDrawableAnimation drives them with
            -- SetStartEffect(true) (func_animation.lua:159-162) - an animation
            -- already in flight can therefore keep drawing between our repaints,
            -- which is vanilla's bubble briefly reappearing over ours. The addon
            -- already pairs these two calls for effect_texture on the unit
            -- frames; same treatment here.
            pcall(function() d:SetStartEffect(false) end)
        end
    end
end

-- Build our own art for one slot, once. The drawables hang off the client's own
-- icon widget, so they inherit its position, its show/hide and its drag - we
-- never position a slot ourselves.
local function newSprite(icon, path)
    local d
    pcall(function()
        d = icon:CreateImageDrawable("Textures/Defaults/White.dds", "overlay")
    end)
    if not d then return nil end
    pcall(function()
        -- Without this the engine can sRGB-convert the loaded PNG and shift the
        -- colours, the same reason the bar fill textures set it.
        d:SetSRGB(false)
        d:SetTgaTexture(path)
        -- The drawable inherits the seed texture's crop; widen it to the whole
        -- PNG or only its top-left corner is sampled.
        d:SetCoords(0, 0, PIP_TEXTURE_SIZE, PIP_TEXTURE_SIZE)
    end)
    return d
end

local function ensurePip(icon)
    if icon.bbAbyss then return icon.bbAbyss end
    local made = {}
    -- off first, on second: later-created drawables render above, so the lit
    -- state covers the dark one rather than the other way round.
    made.off = newSprite(icon, PIP_TEXTURE_OFF)
    made.on = newSprite(icon, PIP_TEXTURE_ON)
    if not made.off or not made.on then return nil end
    icon.bbAbyss = made
    return made
end

-- Paint one slot. frac is 0..1 for THIS slot: 1 full, 0 empty, anything between
-- is the slot currently charging.
-- Three concentric discs, centred on the client's own icon widget.
--
-- Concentric rather than anchored corner-to-corner because a circle's border
-- has to be a ring, and the only way to get one from a single disc texture is
-- to draw a slightly larger dark disc behind a slightly smaller light one. The
-- size difference IS the border, so it is set in device pixels and the ring
-- stays 1px at any UI scale.
--
-- The charge fill grows RADIALLY rather than bottom-up. A rectangle can be part
-- filled by shortening it; a circle cannot, because the texture would simply be
-- squashed rather than clipped. Scaling the whole disc keeps it a circle at
-- every fraction, and a slot swelling as it charges reads as clearly as a bar
-- filling.
-- Both sprites at the same size and position; the lit one is simply shown or
-- hidden over the dark one. They were cut from one source on a common square,
-- so nothing has to be nudged to make them line up.
--
-- The dark state stays visible underneath rather than being swapped out: the
-- lit artwork has a soft glow around its rim, and with nothing behind it the
-- slot would appear to change size as it lights up.
local function paintPip(icon, frac, d, xOff)
    local pip = ensurePip(icon)
    if not pip then return end
    if d <= 0 then return end

    pcall(function()
        pip.off:RemoveAllAnchors()
        pip.off:SetExtent(d, d)
        pip.off:AddAnchor("CENTER", icon, xOff, 0)
        pip.off:SetVisible(true)

        pip.on:RemoveAllAnchors()
        pip.on:SetExtent(d, d)
        pip.on:AddAnchor("CENTER", icon, xOff, 0)
        -- White = untinted; also clears any tint a pre-3.1 session left on the
        -- persisted drawable (see the note above pipDiameter).
        pip.on:SetColor(1, 1, 1, 1)
        -- Charges are whole (see the floor in repaint), so this is on or off.
        pip.on:SetVisible(frac > 0)
    end)
end

-- Spacing has to follow the pip size, or shrinking the pips just grows the gaps.
--
-- The client lays its slots out on a fixed pitch: icon i sits at
-- (i-1) * ACTION_BUTTON_WIDTH + i * ACTION_BUTTON_GAP, i.e. 51px apart for a
-- 49px cell (bubble_action_bar_view.lua:33-39). Our pips are centred in those
-- cells, so at 35 they already sit 16px apart and at 12 they are marooned.
--
-- The icons themselves are left alone. They carry the drag area, the client
-- anchors them once at creation, and moving them would mean re-deriving
-- positions the client owns. Instead each pip is drawn with a horizontal offset
-- INSIDE its own cell, which needs nothing from the client and cannot desync.
--
-- Returns the offset for slot i of n:
--   pitch  - how far apart we actually want the pips, capped at the client's own
--            pitch so the group never grows wider than the bar it replaces
--   shift  - re-centres the tightened group over the original footprint, so the
--            bar stays where the player dragged it instead of creeping left
local function pipOffset(i, n, d, cell)
    local gap = d * 0.15
    local minGap = Px(2)
    if gap < minGap then gap = minGap end
    local pitch = d + gap
    if pitch > cell then pitch = cell end
    local shift = (n - 1) * (cell - pitch) / 2
    return (i - 1) * (pitch - cell) + shift
end

-- Repaint every slot from the live resource.
local function repaint()
    if not frame or not frame.icons or restoring then return end
    if frame.bbAbyssToken ~= myToken then return end
    local s = settings()
    -- Explicit true, not "anything but false". The restyle is opt-in as of the
    -- 3.1 release, and a settings table read before mergeSettings fills the
    -- defaults in has no key at all - which the old test read as ON, putting
    -- our pips over the client's bubbles for a player who never asked.
    local enabled = s.showAbyssal == true

    -- Switched off since the last pass: hide our discs, then let the client
    -- rebuild its own bubbles.
    --
    -- Without this the toggle only half worked. Ours went away, but vanilla's
    -- five layers stayed hidden from the last time we hid them - they are only
    -- re-shown by CreateEffectBubbleOn/Init/Off, which the client calls when the
    -- charge count CHANGES. So the bar sat empty until the player next gained or
    -- spent a charge. Calling the client's own ShowBubbleActionBar rebuilds every
    -- slot immediately; the unwrapped reference and the guard keep it from
    -- re-entering this function.
    if lastEnabled == true and not enabled and origShow then
        for _, icon in ipairs(frame.icons) do
            if icon.bbAbyss then
                for _, dr in pairs(icon.bbAbyss) do
                    pcall(function() dr:SetVisible(false) end)
                end
            end
        end
        restoring = true
        pcall(function() origShow(frame) end)
        restoring = false
        lastEnabled = false
        return
    end
    lastEnabled = enabled

    local info
    pcall(function() info = api.Unit:GetHighAbilityRscInfo() end)
    -- Hold, don't hide, when the API hands back nothing: mount transitions
    -- swap the ability set and the info can vanish for a few frames. Hiding
    -- here STUCK, because the client only repaints when the charge count
    -- next CHANGES - the bar sat empty until then, which is the reported
    -- auto-hiding. The watchdog in main.lua repaints within 2s of the info
    -- recovering even if no charge moves.
    if type(info) ~= "table" then return end
    local maxRsc = tonumber(info.maxHighAbilityRsc) or 0
    -- Floored to whole charges, exactly as the client does.
    --
    -- The engine reports the resource x100 and it moves CONTINUOUSLY;
    -- UpdateBubbleActionBar compares math.floor(rsc / 100) between passes and
    -- only repaints when that integer changes, so vanilla never shows the
    -- in-between. Drawing the raw value instead made a spent charge shrink away
    -- over several frames rather than snapping off - accurate to the data, but
    -- soft and unreadable next to vanilla's instant blink.
    local cur = tonumber(info.highAbilityPreciseRsc) or 0
    cur = math.floor(cur / 100)

    -- Geometry shared by every slot, resolved once. The cell PITCH is the icon
    -- height plus the client's 2px gap - the same arithmetic
    -- bubble_action_bar_view.lua:33-36 lays the icons out with.
    local iconH = 0
    pcall(function()
        local first = frame.icons[1]
        if first then iconH = first:GetHeight() or 0 end
    end)
    local pipD = pipDiameter(iconH)
    local cell = iconH + 2
    -- Slots actually on screen; the client hides the rest, and the group has to
    -- be centred over those rather than over all twelve.
    local shown = maxRsc
    if shown > #frame.icons then shown = #frame.icons end
    if shown < 1 then shown = 1 end

    for i, icon in ipairs(frame.icons) do
        if not enabled then
            -- Switched off: drop our art and let the client's own bubbles back.
            if icon.bbAbyss then
                for _, d in pairs(icon.bbAbyss) do
                    pcall(function() d:SetVisible(false) end)
                end
            end
        elseif i <= maxRsc then
            hideVanillaArt(i)
            -- charge remaining for this slot, clamped into 0..1
            local frac = cur - (i - 1)
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
            paintPip(icon, frac, pipD, pipOffset(i, shown, pipD, cell))
        else
            -- Beyond the player's slot count. The client hides these icons
            -- itself; make sure our art goes with them.
            if icon.bbAbyss then
                for _, d in pairs(icon.bbAbyss) do
                    pcall(function() d:SetVisible(false) end)
                end
            end
        end
    end
end

-- Forward declaration so Refresh can fall back to it on the first call
local Setup

-- Re-runs Setup if the bar was not there yet. The bubble bar is created for the
-- player's class, so on a fresh login OnLoad can easily run before it exists -
-- and then a settings change is the next thing that would notice.
function abyssal.Refresh()
    if not frame then
        if Setup then Setup() end
        return
    end
    repaint()
end

-- Wrap the two functions that repaint the bar.
--
-- Both call CreateEffectBubbleOn/Init/Off, which rebuild and re-show the vanilla
-- effect drawables, so ours has to run AFTER them or the stock art comes back
-- the moment the charge count changes - the same trap hpBar_deco set on the
-- unit frames.
--
-- ShowBubbleActionBar also fires on scale change and on the client's own
-- BUBBLE_ACTION_BAR_SHOW event, so hooking it covers re-layout for free.
local function hookRepaint(name)
    -- Wrap from the STORED original, not from frame[name]: after a /reload
    -- frame[name] is the previous session's wrapper, and wrapping that would
    -- grow the chain by one dead layer per reload. Re-wrapping from the
    -- original replaces the old wrapper outright - constant depth, and the
    -- old session's closure simply stops being called.
    local orig = frame.bbAbyssOrig and frame.bbAbyssOrig[name]
    if type(orig) ~= "function" then return false end
    if name == "ShowBubbleActionBar" then origShow = orig end
    frame[name] = function(self, ...)
        orig(self, ...)
        pcall(repaint)
    end
    return true
end

Setup = function()
    if frame then return true end
    local got
    pcall(function() got = ADDON:GetContent(UIC.BUBBLE_ACTION_BAR) end)
    if not got then
        -- Not an error worth shouting about: the bar only exists for classes
        -- with the high-ability feature set (bubble_action_bar.lua:31).
        return false
    end
    frame = got
    -- Take ownership: repaints from previous loads go inert (see myToken).
    frame.bbAbyssToken = myToken
    pcall(function()
        -- The TRUE originals, captured exactly once ever. On a frame an older
        -- build already wrapped (bbAbyssHooked without bbAbyssOrig), what we
        -- see IS that build's wrapper and one stale layer stays in the chain
        -- until a full client restart; every session after this build
        -- re-wraps from the stored originals at constant depth.
        frame.bbAbyssOrig = frame.bbAbyssOrig or {
            ShowBubbleActionBar = frame.ShowBubbleActionBar,
            UpdateBubbleActionBar = frame.UpdateBubbleActionBar,
        }
        hookRepaint("ShowBubbleActionBar")
        hookRepaint("UpdateBubbleActionBar")
    end)
    repaint()
    return true
end

abyssal.Setup = Setup

return abyssal
