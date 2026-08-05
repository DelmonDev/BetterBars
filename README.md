# BetterBars

Restyles the vanilla ArcheAge Classic unit frames to match the newer client's
look — bar art, backdrop and colours measured pixel-for-pixel from its own
texture atlas.

Type `bb` in chat, or open it from the addon list, to configure everything.

![BetterBars settings window](https://github.com/user-attachments/assets/ecb0c7f9-f81d-446c-b86e-183886a588e0)

## Features

- **Retail-style bars** — the newer client's exact backdrop cell (border,
  inner shadow, feathered corners) and its fill sprites, on every unit frame:
  player, target, target-of-target, watch target and pets.
- **Full colour control** — HP, MP and Enemy colours with an HSV colour
  wheel, brightness slider, RGB input and curated presets. Every change
  applies live, including the damage trail, which is derived from your bar
  colour the way the newer client does it.
- **Reliable hostility colours** — enemy red / ally green driven by the
  game's own hostility decision, including player housing (ally houses are
  green, enemy houses red — vanilla got this wrong through the addon api).
- **Live preview** — a mock frame in the settings window mirrors your
  colours, bar heights, texture, label format, font size and level font as
  you change them.
- **Level font picker** — the level number on the frames can use any of the
  client's 18 fonts; the picker previews each font in itself.
- **Info labels (opt-in)** — class, gear score and guild under or around the
  frame, each with its own X/Y position and font size, plus shadow toggles.
  Values that cannot be read (NPC gear score, unresolved classes) hide
  instead of showing junk.
- **Quality of life** — labels formatted your way (current / percent / both /
  hidden), housing HP display, bar heights, background opacity, and a Reset
  button with a 5-second are-you-sure arm.

### Colour wheel

Pick any colour by hue and saturation, dial the brightness, type exact RGB,
or take one of the presets. Everything applies to the live bars instantly.

![Colour wheel picker](https://github.com/user-attachments/assets/b985f02a-7370-459d-b932-d080375b9a46)

### Level font picker

Every font the client ships, each row drawn in the font it offers.

![Level font picker](https://github.com/user-attachments/assets/7eac19e9-554a-4dbe-b97a-cd2f3fd0b754)

### Live preview

The preview carries your colours, bar heights, texture, label format, font
size and level font — no need to leave the window to see a change.

![Live preview](https://github.com/user-attachments/assets/379c3bcd-471e-4668-b2bf-45c37daf2c20)

## Install

1. Download the release zip and extract it into your `Documents/AAClassic/Addon/`
   folder, so it sits at `Addon/BetterBars/`.
2. Enable BetterBars in the in-game addon list.
3. Type `bb` in chat to open the settings.

Settings save automatically — there is no Save button. Upgrading from 2.0
performs a one-time reset to the new defaults (your first 3.0 launch only).

## Changelog — 3.0

- Bars rebuilt against the newer client's atlas: exact backdrop ninepart,
  retail fill sprites for HP and MP, per-bar backdrops, and damage trails
  tinted from the bar colour instead of flat grey.
- Housing targets colour correctly (ally green / enemy red) and can show the
  game's own HP text (LABELS → House HP).
- Player and pet bars keep the custom colours in every case — including with
  the fill texture off and after `/reload` with a pet out.
- Pet frame HP/MP labels are formatted and centred like the main frames.
- Party frames: the damage trail follows your HP colour (the one element the
  addon api exposes; full party styling needs api support).
- Settings window rebuilt: flat sliders and checks, everything saves live,
  colour wheel picker, live preview frame, level font picker, per-item info
  label controls, double-confirm Reset.
- Fixes: the welcome card no longer returns after a Reset or reload, settings
  no longer reset on login, the fill texture no longer resurrects after being
  toggled off, and class/gear-score labels hide junk values instead of
  printing them.

## Credits

By **Dehling**. Free, always. In-game donations appreciated, never expected.
