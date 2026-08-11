# UI scaling in ArcheAge Classic, and how BetterBars handles it

Notes for whoever (or whatever) works on this addon next. Everything here was
read out of the client's own decompiled scripts, not inferred from behaviour.

## The mechanism

The client scales the **entire UI tree** by a single engine-level factor:

```lua
UIParent:SetUIScale(value, immediatelyApply)
UIParent:GetUIScale()
```

There is no per-widget scaling. Everything inherits it.

**Widget offsets and extents are in UI units. Device pixels = UI units × scale.**

That single sentence is the whole problem. Every number you pass to
`SetHeight`, `SetExtent` or `AddAnchor` is in UI units, and what the player
actually sees is that number multiplied by a factor you do not control.

## The factor is usually not 1, and usually not round

From `x2ui/baselib/func_layout.lua`:

```lua
function F_LAYOUT.GetUIScaleValueByOptionWindowValue(selectedValue)
  if selectedValue == 80 then return 0.85
  elseif selectedValue == 90 then return 0.93 end
  return selectedValue / 100
end
```

The slider **displays a percentage that is not the applied factor**: "80%"
applies `0.85`, "90%" applies `0.93`. The slider itself runs 40..160 in steps of
10 (`option/screen_option.lua:334-338`).

And the default is resolution-dependent (`option/screen_option.lua:7-13`):

```lua
local function GetDefaultUIScaleByResolution(screenWidth, screenHeight)
  if screenWidth < 1280 or screenHeight < 864 then return 0.85 else return 1 end
end
```

So assume a fractional scale. Testing only at 100% proves nothing: at 100%
every scale conversion is the identity, so scale-related bugs are invisible.

## The only helper the client provides

```lua
function F_LAYOUT.CalcDontApplyUIScale(value, customUIScale)
  if customUIScale == nil then return value / UIParent:GetUIScale()
  else return value / customUIScale end
end
```

That is it. **There is no snapping or rounding helper anywhere in the client.**
`CalcDontApplyUIScale` is used where something must be a fixed size on screen —
the loading background, and the top-level *position* of each unit frame.

A whole window can also opt out with `window:ApplyUIScale(false)`, but only two
windows in the entire client do (market price, web browser). **The unit frames
do not.**

## Why the client never trips over this and an addon does

The client's unit frames contain **zero** `CreateColorDrawable`, **zero**
`SetHeight(1)`, **zero** `SetWidth(1)`. Grep them and see. Every border,
divider and shadow is a ninepart or threepart **texture** cell sampled from the
atlas.

A texture resamples smoothly at any scale — at 0.85 a 1px border just gets
slightly soft. **A 1-UI-unit colour rectangle at 0.85 scale is 0.85 device
pixels and rasterises to 0 or 1 depending where it lands.** That is a border row
that exists along part of a bar and vanishes along the rest.

BetterBars is forced onto colour rectangles because **`SetTgaTexture` does not
work on a `NinePartDrawable` in this client** — the ninepart path in
`ApplyBarBackdrop` always fails and the flat fallback is what actually renders.
(`SetTgaTexture` *does* work on an `ImageDrawable`; that is how the fill texture
loads.) Run `bbinfo` in chat to see which path is live.

So the addon inherited a rasterisation problem the client never has.

## The two rules this addon uses

Both helpers live at the **top** of `main.lua`, above every geometric function.

### `Px(n)` — fix a size in device pixels

```lua
local function Px(n) return n / UIScale() end
```

Same arithmetic as the client's `CalcDontApplyUIScale`. Use for anything that
must stay crisp and cannot scale below one pixel without disappearing:

- border line thickness
- the shadow ramp rows
- `BAR_BG_OUTSET` (how far the backdrop reaches past its bar)
- `MP_BAR_GAP` (a 2px gap should be 2 screen pixels at any scale)
- `BAR_SHIFT_X` ("move it 6px left" should mean the same thing at any scale)

### `Snap(v)` — keep a size in UI units, align it to the pixel grid

```lua
local function Snap(v)
  local s = UIScale()
  return math.floor(v * s + 0.5) / s   -- Lua 5.1 has no math.round
end
```

Use for **layout**: bar heights, and anchor offsets derived from measured
values such as `level:GetHeight()`.

Why not `Px` for bar heights? Fixing them in device pixels would freeze the bars
while the name, level number and wing kept scaling — they would desync at
anything but 100%. `Snap` keeps them growing with the UI the way the client's
own `hpBar:SetHeight(19)` does, while ensuring both edges land on whole pixels.

That matters because **a bar whose edge is mid-pixel cannot carry a crisp
border** however carefully the border itself is built. At 1.3 a 17-unit bar is
22.1 device pixels; that trailing `.1` is enough.

## Rules of thumb

1. **Positions and thicknesses must use the same rule.** Mixing them is worse
   than using neither. A 1px-thick border positioned 1.3px from an edge, with a
   body starting 2.6px in, puts every boundary mid-pixel.
2. **Anything you can call "N pixels" out loud is `Px(N)`.**
3. **Anything the player sizes and expects to grow with the UI is `Snap(v)`.**
4. **Chain adjacent drawables** (`AddAnchor("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)`)
   rather than positioning each by its own absolute offset. Two independent
   arithmetic expressions only meet if they stay in step; chained ones meet by
   construction. This is what closed the transparent seam across the backdrop.
5. **Both conversions are the identity at scale 1.0**, so adopting them cannot
   change behaviour for anyone at 100%.
6. **Test at 130% and at 80%.** They round in opposite directions: below 1.0,
   `Px(1)` is larger than one UI unit; above 1.0 it is smaller.

## Gotchas that cost real time here

- **`luac -p` cannot catch a helper used before it is declared.** Lua locals are
  visible only from their declaration point onward, so a helper defined below
  its first use is `nil` at that point — a *runtime* error that parses
  perfectly. This addon failed to load exactly that way. Check declaration
  order separately from syntax.
- **Backdrop drawables are cached on the game's own widgets** and survive an
  addon reload, so the creation block runs once per client session. Changes to
  *anchoring* apply immediately (it re-runs every restyle); changes to how many
  drawables get created do not, until a full client restart.
- **`bbinfo`** in chat dumps live state to `BetterBars/bbinfo_dump.txt`,
  including the current UI scale and which backdrop path is in use. Start there.
