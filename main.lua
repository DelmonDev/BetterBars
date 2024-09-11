local BetterBars = {
  name = "BetterBars",
  version = "0.4",
  author = "Dehling",
  desc = "Simply Makes the bars Better"
}

local FrameLabels = {}
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function SetupFrame(unitType, uicType)
  local frame = ADDON:GetContent(uicType)
  if not frame then
      api.Log:Err("Failed to get frame for " .. unitType)
      return
  end
  FrameLabels[unitType] = frame
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Common style function
local function ApplyCommonStyle(frame)
    if frame.hpBar_deco then
        frame.hpBar_deco:Show(true)
    end
    if frame.line then
        frame.line:Show(false)
    end
    if frame.bg then
        frame.bg:SetColor(0.11, 0.114, 0.122, 0.8)
    end
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Player frame style
local function StylePlayerFrame(frame)
  frame.ApplyFrameStyle = function(frame)
    ApplyCommonStyle(frame)
    if frame then
      frame.hpBar:SetHeight(17)
      frame.mpBar:SetHeight(15)
    end
  end
  frame:ApplyFrameStyle()
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Target frame style
local function StyleTargetFrame(frame)
  frame.ApplyFrameStyle = function(frame)
    ApplyCommonStyle(frame)
    if frame then
      frame.hpBar:SetHeight(17)
      frame.mpBar:SetHeight(15)
    end
  end
  frame:ApplyFrameStyle()
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- TargetTarget frame style
local function StyleTargetTargetFrame(frame)
  frame.ApplyFrameStyle = function(frame)
    ApplyCommonStyle(frame)
    if frame then 
      frame.hpBar:SetHeight(17)
      frame.mpBar:SetHeight(15)
    end
  end
  frame:ApplyFrameStyle()
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- WatchTarget frame style
local function StyleWatchTargetFrame(frame)
  frame.ApplyFrameStyle = function(frame)
    ApplyCommonStyle(frame)
    if frame then 
      frame.hpBar:SetHeight(17)
      frame.mpBar:SetHeight(15)
    end
  end
  frame:ApplyFrameStyle()
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Updates the Styles for the frames
local function UpdateFrameStyles()
  -- Apply styles
  if FrameLabels["player"] then StylePlayerFrame(FrameLabels["player"]) end
  if FrameLabels["target"] then StyleTargetFrame(FrameLabels["target"]) end
  if FrameLabels["targettarget"] then StyleTargetTargetFrame(FrameLabels["targettarget"]) end
  if FrameLabels["watchtarget"] then StyleWatchTargetFrame(FrameLabels["watchtarget"]) end
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function OnLoad()
  api.Log:Info("BetterBars addon loaded")

  SetupFrame("player", UIC.PLAYER_UNITFRAME)
  SetupFrame("target", UIC.TARGET_UNITFRAME)
  SetupFrame("targettarget", UIC.TARGET_OF_TARGET_FRAME)
  SetupFrame("watchtarget", UIC.WATCH_TARGET_FRAME)

  UpdateFrameStyles()

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
  for unitType, frame in pairs(FrameLabels) do
      local hpLabel = frame.hpBar and frame.hpBar.hpLabel
      local mpLabel = frame.mpBar and frame.mpBar.mpLabel

      if hpLabel then
          -- Center the HP label and increase font size
          hpLabel:RemoveAllAnchors()
          hpLabel:AddAnchor("CENTER", frame.hpBar, "CENTER", 0, 0)
          hpLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
          hpLabel.style:SetAlign(ALIGN.CENTER)

          hpLabel.SetTextOrig = hpLabel.SetText
          hpLabel.SetText = function(self, text)
              local current = api.Unit:UnitHealth(unitType)
              local max = api.Unit:UnitMaxHealth(unitType)
              if current and max and max > 0 then
                  local percent = math.floor((current / max) * 100)
                  self:SetTextOrig(string.format("%d (%d%%)", current, percent))
              else
                  self:SetTextOrig("0 (0%)")
              end
          end
      end

      if mpLabel then
          -- Center the MP label and increase font size
          mpLabel:RemoveAllAnchors()
          mpLabel:AddAnchor("CENTER", frame.mpBar, "CENTER", 0, 0)
          mpLabel.style:SetFontSize(FONT_SIZE.MIDDLE)
          mpLabel.style:SetAlign(ALIGN.CENTER)

          mpLabel.SetTextOrig = mpLabel.SetText
          mpLabel.SetText = function(self, text)
              local current = api.Unit:UnitMana(unitType)
              local max = api.Unit:UnitMaxMana(unitType)
              if current and max and max > 0 then
                  local percent = math.floor((current / max) * 100)
                  self:SetTextOrig(string.format("%d (%d%%)", current, percent))
              else
                  self:SetTextOrig("0 (0%)")
              end
          end
      end
  end
end
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function OnUnload()
  -- Unregister UpdateFrameStyles
  api.On("UPDATE", nil)

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
end

BetterBars.OnLoad = OnLoad
BetterBars.OnUnload = OnUnload

return BetterBars