local BetterBars = {
  name = "BetterBars",
  version = "2.0.0",
  author = "Dehling",
  desc = "Improves the look of vanilla unit frames"
}

-- Define reusable afterImage colors and coords
local AFTERIMAGE_UP_COLOR = { ConvertColor(60), ConvertColor(60), ConvertColor(60), 1 } -- Lighter Black
local AFTERIMAGE_DOWN_COLOR = { ConvertColor(210), ConvertColor(210), ConvertColor(210), 1 } -- Light White
local LARGE_BAR_COORDS = { 0, 120, 300, 19 }
local SMALL_BAR_COORDS = { 301, 120, 150, 19 }

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Modify the global STATUSBAR_STYLE.L_HP_FRIENDLY to match game format
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
STATUSBAR_STYLE.L_HP_FRIENDLY = { --large HP bar
  coords = LARGE_BAR_COORDS,
  -- Use defined variables for afterImage colors
  afterImage_color_up = AFTERIMAGE_UP_COLOR,
  afterImage_color_down = AFTERIMAGE_DOWN_COLOR
}
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Modify the global STATUSBAR_STYLE.S_HP_FRIENDLY to match game format
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
STATUSBAR_STYLE.S_HP_FRIENDLY = { --small HP bar
  coords = SMALL_BAR_COORDS,
  -- Use defined variables for afterImage colors
  afterImage_color_up = AFTERIMAGE_UP_COLOR,
  afterImage_color_down = AFTERIMAGE_DOWN_COLOR
}
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Modify the global STATUSBAR_STYLE.L_HP_HOSTILE to match game format
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
STATUSBAR_STYLE.L_HP_HOSTILE = { --large HP bar
  coords = LARGE_BAR_COORDS,
  -- Use defined variables for afterImage colors
  afterImage_color_up = AFTERIMAGE_UP_COLOR,
  afterImage_color_down = AFTERIMAGE_DOWN_COLOR
}
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Modify the global STATUSBAR_STYLE.S_HP_HOSTILE to match game format
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
STATUSBAR_STYLE.S_HP_HOSTILE = { --small HP bar
  coords = SMALL_BAR_COORDS,
  -- Use defined variables for afterImage colors
  afterImage_color_up = AFTERIMAGE_UP_COLOR,
  afterImage_color_down = AFTERIMAGE_DOWN_COLOR
}
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Modify the global STATUSBAR_STYLE.L_HP_NEUTRAL to match game format
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
STATUSBAR_STYLE.L_HP_NEUTRAL = {
  coords = LARGE_BAR_COORDS,
  afterImage_color_up = AFTERIMAGE_UP_COLOR,
  afterImage_color_down = AFTERIMAGE_DOWN_COLOR
}
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Modify the global STATUSBAR_STYLE.S_HP_NEUTRAL to match game format
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
STATUSBAR_STYLE.S_HP_NEUTRAL = {
  coords = SMALL_BAR_COORDS,
  afterImage_color_up = AFTERIMAGE_UP_COLOR,
  afterImage_color_down = AFTERIMAGE_DOWN_COLOR
}
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Modify the global STATUSBAR_STYLE.L_MP to match game format
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
STATUSBAR_STYLE.L_MP = {
  coords = LARGE_BAR_COORDS,
  afterImage_color_up = AFTERIMAGE_UP_COLOR,
  afterImage_color_down = AFTERIMAGE_DOWN_COLOR
}
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Modify the global STATUSBAR_STYLE.S_MP to match game format
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
STATUSBAR_STYLE.S_MP = {
  coords = SMALL_BAR_COORDS,
  afterImage_color_up = AFTERIMAGE_UP_COLOR,
  afterImage_color_down = AFTERIMAGE_DOWN_COLOR
}
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local FrameLabels = {}
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
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--Color Variables
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Define default colors (will be overwritten by settings)
local HP_COLORS = { 0.745, 0.392, 0.509, 1 } -- Default: ~Pink/Reddish
local EHP_COLORS = { 1, 0, 0, 1 }           -- Default: Red
local MP_COLORS = { 0.352, 0.196, 0.509, 1 } -- Default: Purple/Blueish

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Format label text based on settings
local function formatLabelText(unitType, isHP)
    local s = require("BetterBars/settings").getSettings()
    local fmt = s.labelFormat or "both"
    local current = isHP and api.Unit:UnitHealth(unitType) or api.Unit:UnitMana(unitType)
    local max = isHP and api.Unit:UnitMaxHealth(unitType) or api.Unit:UnitMaxMana(unitType)
    if not current or not max or max <= 0 then
        if fmt == "hide" then return "" end
        return "0 (0%)"
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
    if frame.bg and frame.mpBar:IsVisible() then
        frame.bg:SetColor(0.15, 0.15, 0.15, bgOpacity)
        frame.bg:SetCoords(0, 80, 300, 19)
        frame.bg:RemoveAllAnchors()
        frame.bg:AddAnchor("TOPLEFT", frame.hpBar, -1, -1)
        frame.bg:AddAnchor("BOTTOMRIGHT", frame.mpBar, 1, 1)
        frame.bg:Show(true)
        frame.hpBar_deco:Show(true)
      else
        frame.bg:SetCoords(0,80,300,19)
        frame.bg:SetColor(0.15, 0.15, 0.15, bgOpacity)
        frame.bg:RemoveAllAnchors()
        frame.bg:AddAnchor("TOPLEFT", frame.hpBar, -1, -1)
        frame.bg:AddAnchor("BOTTOMRIGHT", frame.hpBar, 1, 1)
        frame.bg:Show(true)
        frame.hpBar_deco:Show(false)
    end
    if frame.effect_texture then
        frame.effect_texture:SetVisible(false)
        frame.effect_texture:SetStartEffect(false)
    end
    if frame.use_effect_texture ~= nil then
        frame.use_effect_texture = false
    end

    -- Bar separation (toggle-controlled)
    if frame.mpBar then
        frame.mpBar:RemoveAllAnchors()
        if s.showBarSeparation ~= false then
            frame.mpBar:AddAnchor("TOP", frame.hpBar, "BOTTOM", 0, 1)
        else
            frame.mpBar:AddAnchor("TOP", frame.hpBar, "BOTTOM", 0, 0)
        end
    end

    -- Set the MP bar color for all frames
    if frame.mpBar and frame.mpBar.statusBar then
        frame.mpBar.statusBar:SetBarColor(unpack(MP_COLORS))
    else
        api.Log:Err("BetterBars: Could not set MP bar color - missing statusBar")
    end
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Player frame style
local function StylePlayerFrame(frame)
  frame.ApplyFrameStyle = function(frame)
    local s = require("BetterBars/settings").getSettings()
    ApplyCommonStyle(frame)
    if frame then
      frame.hpBar:SetHeight(s.barHeight.hp or 17)
      frame.mpBar:SetHeight(s.barHeight.mp or 15)
      frame.hpBar:ApplyBarTexture(STATUSBAR_STYLE.L_HP_FRIENDLY)
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
      frame.hpBar:SetHeight(s.barHeight.hp or 17)
      frame.mpBar:SetHeight(s.barHeight.mp or 15)
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
      frame.hpBar:SetHeight(s.barHeight.hp or 17)
      frame.mpBar:SetHeight(s.barHeight.mp or 15)
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
      frame.hpBar:SetHeight(s.barHeight.hp or 17)
      frame.mpBar:SetHeight(s.barHeight.mp or 15)
    end
  end
  frame:ApplyFrameStyle()
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Pet frame style and SPAWN_PET event handler
-- petFrame is a global set by the game engine when pets spawn
local function StylePetFrame(frame) 
    if not frame then return end
    local s = require("BetterBars/settings").getSettings()
    ApplyCommonStyle(frame)
    if frame.hpBar then
        frame.hpBar.statusBar:SetBarColor(unpack(HP_COLORS))
        frame.hpBar:SetHeight(s.barHeight.hp and math.max(13, s.barHeight.hp - 2) or 15)
    end
    if frame.mpBar then
        frame.mpBar.statusBar:SetBarColor(unpack(MP_COLORS))
        frame.mpBar:SetHeight(s.barHeight.mp and math.max(11, s.barHeight.mp - 2) or 13)
    end
end

local function StyleAllPetFrames()
    if petFrame then
        for i = 1, 2 do
            if petFrame[i] then
                StylePetFrame(petFrame[i])
            end
        end
    end
end

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Event handler tracking — ensures clean OnUnload
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
-- Updates the Styles for the frames
local function UpdateFrameStyles()
    -- Apply common styles and specific colors
    for unitType, frame in pairs(FrameLabels) do
        if frame then
            -- Apply common style changes first
            ApplyCommonStyle(frame) 

            -- Apply specific styles based on frame type if needed (e.g., textures)
            if unitType == "player" then StylePlayerFrame(frame) end
            if unitType == "target" then StyleTargetFrame(frame) end
            if unitType == "targettarget" then StyleTargetTargetFrame(frame) end
            if unitType == "watchtarget" then StyleWatchTargetFrame(frame) end

            -- Set HP bar color based on hostility using unitInfo.faction
            if frame.hpBar and frame.hpBar.statusBar then
                local isHostile = false -- Default to friendly/neutral

                local unitId = nil
                if api.Unit and api.Unit.GetUnitId then
                    unitId = api.Unit:GetUnitId(unitType)
                end

                if unitId and unitId ~= 0 then
                    local unitInfo = nil
                    if api.Unit and api.Unit.GetUnitInfoById then
                         -- Wrap the call in pcall for safety, as GetUnitInfoById might error for some units/states
                        local success, result = pcall(api.Unit.GetUnitInfoById, api.Unit, unitId)
                        if success and result then
                            unitInfo = result
                        else
                            api.Log:Warn("BetterBars: Failed to get unit info for unitType: " .. unitType .. " (ID: " .. unitId .. "). Error: " .. tostring(result))
                        end
                    end

                    if unitInfo and unitInfo.faction then
                        -- *** Check if faction is the string "hostile" ***
                        if unitInfo.faction == "hostile" then 
                            isHostile = true
                        end
                        -- api.Log:Info("UnitType: "..unitType..", Faction: "..tostring(unitInfo.faction)..", Hostile: "..tostring(isHostile)) -- Debugging line
                    else
                        -- Log only if unitInfo was expected but faction was missing (pcall already logs errors)
                        if unitInfo == nil and api.Unit and api.Unit.GetUnitInfoById then
                           api.Log:Warn("BetterBars: Could not get unit info or faction for unitType: " .. unitType .. " (ID: " .. unitId .. "). Defaulting color.")
                        end
                    end
                else
                    -- Don't log spam for types that might not always have a unitId (like targettarget initially)
                    -- api.Log:Warn("BetterBars: Could not get valid unitId for unitType: " .. unitType .. ". Defaulting color.")
                end

                local s = require("BetterBars/settings").getSettings()
                if s.showHostilityColor ~= false and isHostile then
                    frame.hpBar.statusBar:SetBarColor(unpack(EHP_COLORS))
                else
                    frame.hpBar.statusBar:SetBarColor(unpack(HP_COLORS))
                end
            end
             -- Ensure MP color is also applied (redundant if already in ApplyCommonStyle, but safe)
            if frame.mpBar and frame.mpBar.statusBar then
                frame.mpBar.statusBar:SetBarColor(unpack(MP_COLORS))
            end
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
    
    -- Update frame styles with new colors
    UpdateFrameStyles()
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Handler for chat messages to detect commands
local function HandleChatCommand(channel, unit, isHostile, name, message, speakerInChatBound, specifyName, factionName, trialPosition)
  -- Check if it's the player's message
  local playerName = api.Unit:GetUnitNameById(api.Unit:GetUnitId("player"))
  
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
end

local function OnLoad()
  SetupFrame("player", UIC.PLAYER_UNITFRAME)
  SetupFrame("target", UIC.TARGET_UNITFRAME)
  SetupFrame("targettarget", UIC.TARGET_OF_TARGET_FRAME)
  SetupFrame("watchtarget", UIC.WATCH_TARGET_FRAME)

  UpdateFrameStyles()

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

      if hpLabel then
          -- Center the HP label
          hpLabel:RemoveAllAnchors()
          hpLabel:AddAnchor("CENTER", frame.hpBar, "CENTER", 0, 0)
          hpLabel.style:SetAlign(ALIGN.CENTER)

          hpLabel.SetTextOrig = hpLabel.SetText
          hpLabel.SetText = function(self, text)
              pcall(function()
                  local s = require("BetterBars/settings").getSettings()
                  self.style:SetFontSize(s.labelFontSize or FONT_SIZE.MIDDLE)
                  self:SetTextOrig(formatLabelText(capturedType, true))
              end)
          end
      end

      if mpLabel then
          -- Center the MP label
          mpLabel:RemoveAllAnchors()
          mpLabel:AddAnchor("CENTER", frame.mpBar, "CENTER", 0, 0)
          mpLabel.style:SetAlign(ALIGN.CENTER)

          mpLabel.SetTextOrig = mpLabel.SetText
          mpLabel.SetText = function(self, text)
              pcall(function()
                  local s = require("BetterBars/settings").getSettings()
                  self.style:SetFontSize(s.labelFontSize or FONT_SIZE.MIDDLE)
                  self:SetTextOrig(formatLabelText(capturedType, false))
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
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function OnUnload()
  -- Unregister event handlers through the tracker
  for _, reg in ipairs(registeredHandlers) do
      pcall(function()
          if api.Off then api.Off(reg.event, reg.handler) end
      end)
  end
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
  end

  FrameLabels = {}
  
  -- Unload settings page
  local settings_page = require("BetterBars/settings_page")
  settings_page.unload()
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