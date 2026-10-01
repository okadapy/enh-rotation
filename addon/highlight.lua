-- The button to press lit on the action bars (every source of addon/actionbars.lua) and its key
-- on the big icon. Frames and textures of our own laid over the buttons: nothing is ever set on
-- a button (protected frames), so it works the same in combat without taint.
local actionbars = require("actionbars")
local spells = require("spells")

local M = {}
M.OPTIONS = {
  { type = "toggle", key = "highlightButtons", name = "Light up the button to press on your action bars", default = true },
  { type = "toggle", key = "showKeybind", name = "Show its key on the big icon", default = true },
}
M.GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
M.SIZE = 1.8      -- the border art is a ring inside a larger square (the timeline's glow: 1.7)
M.COLOR = { 1, 0.82, 0.3 }
M.AT = 0.3        -- lit once due within this: the moment the timeline's big icon glows
M.RESCAN = 1      -- s: ElvUI pages its bars by a state driver, with no event to us
M.PULSE = 2       -- pulses a second
M.EVENTS = { "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BINDINGS",
             "UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }

-- the plan's first button: the timeline's big icon (it skips steps that are not a spell)
local function first(view)
  local steps = view and view.plan and view.plan.steps
  for _, st in ipairs(steps or {}) do
    if spells.byKey[st.key] then return st end
  end
  return nil
end

function M.due(view, now)
  local st = first(view)
  if not st then return nil end
  local t = view.S and view.S.target
  if not (t and t.exists and t.enemy) then return nil end
  if (st.at or 0) - (now - (view.at or now)) > M.AT then return nil end
  return st.key
end

local H = {}
H.__index = H

function M.new(deps)
  deps.scan = deps.scan or actionbars.scan
  return setmetatable({ deps = deps, map = {}, overlays = {}, lit = {}, litKey = false,
                        dirty = true, scanAt = -math.huge }, H)
end

function H:start(frame)
  for _, e in ipairs(M.EVENTS) do frame:RegisterEvent(e) end
  frame:SetScript("OnEvent", function() self.dirty = true end)
  frame:SetScript("OnUpdate", function(_, dt) self:tick(dt) end)
end

function H:hotkey(key)
  local m = self.map[key]
  return m and m.hotkey
end

-- ours, on UIParent, anchored to the button's center at its scale, one per button
function H:overlay(button)
  local o = self.overlays[button]
  if not o then
    o = CreateFrame("Frame", nil, UIParent)
    o.tex = o:CreateTexture(nil, "OVERLAY")
    o.tex:SetAllPoints(o)
    o.tex:SetTexture(M.GLOW)
    o.tex:SetBlendMode("ADD")
    o.tex:SetVertexColor(unpack(M.COLOR))
    o:Hide()
    self.overlays[button] = o
  end
  local s = (button.GetEffectiveScale and button:GetEffectiveScale() or 1)
    / (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1)
  if o.SetScale then o:SetScale(s) end
  local w = (button:GetWidth() or 36) * M.SIZE
  o:SetWidth(w)
  o:SetHeight(w)
  o:ClearAllPoints()
  o:SetPoint("CENTER", button, "CENTER", 0, 0)
  if button.GetFrameStrata then o:SetFrameStrata(button:GetFrameStrata()) end
  if button.GetFrameLevel then o:SetFrameLevel(button:GetFrameLevel() + 10) end
  return o
end

function H:light(key)
  for o in pairs(self.lit) do o:Hide(); self.lit[o] = nil end
  self.litKey = key
  local m = key and self.map[key]
  for _, e in ipairs(m and m.buttons or {}) do
    local o = self:overlay(e.frame)
    o:Show()
    self.lit[o] = true
  end
end

function H:keyOn(view, text)
  local f = self.keyFrame
  if not f or f.on ~= view.frame then
    -- a restarted engine draws on a new frame: the old text must not stay on the old one
    if self.keyText then self.keyText:Hide() end
    f = CreateFrame("Frame", nil, view.frame)
    f.on = view.frame
    f:SetAllPoints(view.frame)
    self.keyFrame = f
    self.keyText = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    self.keyIcon = nil
  end
  local fs = self.keyText
  if self.keyIcon ~= view.icon then
    fs:ClearAllPoints()
    -- inside the icon's lower edge: right under it the timeline writes the reason
    fs:SetPoint("BOTTOM", view.icon, "BOTTOM", 0, 3)
    self.keyIcon = view.icon
  end
  fs:SetText(text)
  fs:Show()
end

function H:tick()
  local d = self.deps
  local now, view, c = d.now(), d.view(), d.config() or {}
  -- an event rescans on the next frame (once, however many came); ElvUI pages its bars by a
  -- state driver with no event to us, hence the rescan once a RESCAN as well
  if view and view.cache and (self.dirty or now - self.scanAt >= M.RESCAN) then
    self.map = d.scan(view.cache.keyByName or {})
    self.dirty, self.scanAt, self.litKey = false, now, false -- buttons may have changed: light again
  end
  local key = view and view.active and c.highlightButtons ~= false and M.due(view, now) or nil
  if key ~= self.litKey then self:light(key) end
  if next(self.lit) then
    local a = 0.65 + 0.35 * math.sin(now * M.PULSE * 2 * math.pi)
    for o in pairs(self.lit) do o:SetAlpha(a) end
  end
  local st = view and view.active and first(view)
  local text = c.showKeybind ~= false and st and view.icon and view.icon:IsShown() and self:hotkey(st.key)
  if text then self:keyOn(view, text) elseif self.keyText then self.keyText:Hide() end
end

return M
