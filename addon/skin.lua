-- ElvUI's look for the addon's own windows, when ElvUI is installed and the option is on. ElvUI's
-- engine is the global ElvUI ({ E, L, V, P, G }); its Skins module styles one widget per call.
-- Loaded before us (OptionalDeps: ElvUI) it is up by our PLAYER_LOGIN; loaded after, the styling
-- waits for S:AddCallback, which S:Initialize fires once - so it is used only while S is not up.
-- Every ElvUI call is protected: another ElvUI version must not break our windows. ElvUI's style
-- cannot be taken off again, so turning the option off works after /reload.
local M = {}
M.CALLBACK = "DoubtMyRotation"

-- kind -> how ElvUI styles it (signatures as in ElvUI Rebuffed 6.10, Modules/Skins/Skins.lua)
M.HANDLE = {
  range = function(S, w) S:HandleSliderFrame(w) end,
  toggle = function(S, w) S:HandleCheckBox(w) end,
  select = function(S, w) S:HandleDropDownBox(w, w.skinWidth or 180) end,
  button = function(S, w) S:HandleButton(w) end,
  edit = function(S, w) S:HandleEditBox(w) end,
  close = function(S, w) S:HandleCloseButton(w) end,
  scroll = function(S, w) S:HandleScrollBar(w) end,
  window = function(_, w) w:SetTemplate("Transparent") end,
  minimap = function(_, b)
    b:SetTemplate("Default")
    -- the round tracking border does not fit ElvUI's square frame
    if b.border then b.border:Hide() end
    if b.icon then
      b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      b.icon:ClearAllPoints()
      b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
      b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    end
  end,
  -- the timeline's backdrop while unlocked (addon/core.lua frame.bg): ElvUI's panel instead of the
  -- plain dark texture; swapped only once SetTemplate worked, so a failure keeps the plain one
  timeline = function(_, f)
    local bg = CreateFrame("Frame", nil, f)
    bg:Hide()
    bg:SetAllPoints(f)
    -- a level below the timeline, as ElvUI's own backdrops: the icons are the timeline's textures
    bg:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    bg:SetTemplate("Transparent")
    local shown = not f.bg or f.bg:IsShown()
    if f.bg then f.bg:Hide() end
    f.bg = bg
    if shown then bg:Show() end
  end,
}

local Skin = {}
Skin.__index = Skin

-- deps: enabled() -> bool, elv() -> the global ElvUI (default: ElvUI), say(line)
function M.new(deps)
  return setmetatable({ deps = deps or {}, frames = {}, done = {}, waiting = false, failed = false }, Skin)
end

function Skin:on()
  local enabled = self.deps.enabled
  return not enabled or enabled() ~= false
end

-- ElvUI's Skins module, or nil (not installed, or not ElvUI as we know it)
function Skin:skins()
  local g
  if self.deps.elv then g = self.deps.elv() else g = ElvUI end
  local E = type(g) == "table" and g[1]
  if type(E) ~= "table" or type(E.GetModule) ~= "function" then return nil end
  local ok, S = pcall(E.GetModule, E, "Skins", true)
  if ok and type(S) == "table" then return S end
  return nil
end

-- one line for the whole session; after it nothing more is styled (half an ElvUI look is worse)
function Skin:fail(err)
  if self.failed then return end
  self.failed = true
  local say = self.deps.say or print
  say("ElvUI style failed, the standard look stays: " .. tostring(err))
end

-- the frame's own parts: f.widgets, or (an options page, which has no list) its children by kind
local function parts(f)
  if f.widgets then return f.widgets end
  local out = {}
  if f.GetChildren then
    for _, c in ipairs({ f:GetChildren() }) do
      if M.HANDLE[c.kind] then out[#out + 1] = c end
    end
  end
  return out
end

function Skin:style(f, S)
  if self.done[f] or self.failed then return end
  self.done[f] = true
  local list = { f }
  for _, w in ipairs(parts(f)) do list[#list + 1] = w end
  for _, w in ipairs(list) do
    local h = w.kind and M.HANDLE[w.kind]
    if h then
      local ok, err = pcall(h, S, w)
      if not ok then return self:fail(err) end
    end
  end
end

function Skin:refresh()
  if self.failed or not self:on() then return end
  local S = self:skins()
  if not S then return end
  if not S.Initialized then
    -- ElvUI refuses a callback name twice: one callback, however many windows wait
    if not self.waiting then
      self.waiting = true
      local ok, err = pcall(S.AddCallback, S, M.CALLBACK, function()
        self.waiting = false
        self:refresh()
      end)
      if not ok then self:fail(err) end
    end
    return
  end
  for _, f in ipairs(self.frames) do self:style(f, S) end
end

function Skin:frame(f)
  if not f then return end
  local known = false
  for _, g in ipairs(self.frames) do
    if g == f then known = true end
  end
  if not known then self.frames[#self.frames + 1] = f end
  self:refresh()
end

-- a dialog built elsewhere without kinds: the frame is a window, button is its text button,
-- any other plain button its close button, bar its scroll bar
local function adopt(w, button, bar)
  if w.widgets then return end
  w.kind, w.widgets = "window", {}
  for _, c in ipairs({ w:GetChildren() }) do
    if c == button then
      c.kind = "button"
    elseif not M.HANDLE[c.kind] and c:GetObjectType() == "Button" then
      c.kind = "close"
    end
    if M.HANDLE[c.kind] then w.widgets[#w.widgets + 1] = c end
  end
  if bar then
    bar.kind = "scroll"
    w.widgets[#w.widgets + 1] = bar
  end
end

-- the copy window of src/timeline.lua (EnhRotExportFrame): the engine builds it, so its parts are
-- found here; the scroll bar is the one UIPanelScrollFrameTemplate names after its scroll frame
function Skin:export(w)
  if not w then return end
  adopt(w, w.again, _G["EnhRotExportScrollScrollBar"])
  self:frame(w)
end

-- the ready-to-fight window of addon/ready.lua (DoubtMyRotationReady): a frame and its close button
function Skin:ready(w)
  if not w then return end
  adopt(w)
  self:frame(w)
end

return M
