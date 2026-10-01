-- A button on the minimap's rim: left click - the settings, right click - show or hide the
-- timeline, drag - move it round the rim. A frame of our own (no LibDBIcon), laid out like the
-- minimap buttons of 3.3.5a (Minimap.xml: MiniMapTracking); the angle is saved per character by
-- the host. The Minimap itself is only our parent: its scripts and points stay untouched (taint).
local M = {}
M.NAME = "DoubtMyRotationMinimapButton"
M.ICON = "Interface\\Icons\\Ability_Shaman_Stormstrike"
M.RADIUS = 80
-- the rim: half the minimap out plus a little (ElvUI's square one is 176 px and resizable)
function M.radius()
  local w = Minimap and Minimap.GetWidth and Minimap:GetWidth() or 0
  if w > 0 then return w / 2 + 5 end
  return M.RADIUS
end
M.ANGLE = 200
M.TIP = "DoubtMyRotation\nLeft-click: settings\nRight-click: show or hide the timeline\nDrag: move this button"

-- the offset from the minimap's center: round - on the circle; square (ElvUI's GetMinimapShape()
-- gives "SQUARE") - pushed out along the same ray to the square's edge
function M.offset(angle, shape, radius)
  radius = radius or M.RADIUS
  local a = math.rad(angle)
  local x, y = math.cos(a), math.sin(a)
  if shape == "SQUARE" then
    local m = math.max(math.abs(x), math.abs(y))
    x, y = x / m, y / m
  end
  return x * radius, y * radius
end

function M.angle(cx, cy, px, py)
  local d = math.deg(math.atan2(py - cy, px - cx))
  if d < 0 then d = d + 360 end
  return d
end

-- the stock client has no GetMinimapShape; addons that reshape the minimap define it
local function shape()
  return GetMinimapShape and GetMinimapShape() or "ROUND"
end

-- while dragged: the angle from the minimap's center to the cursor (the cursor is in screen
-- pixels, the minimap's center in its own scale)
local function follow(b)
  local cx, cy = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local s = Minimap:GetEffectiveScale()
  b.angle = M.angle(cx, cy, px / s, py / s)
  b:place(b.angle)
end

function M.new(host)
  local b = CreateFrame("Button", M.NAME, Minimap)
  b.kind, b.host = "minimap", host
  b:SetWidth(31)
  b:SetHeight(31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(M.ICON)
  b.icon:SetWidth(20)
  b.icon:SetHeight(20)
  b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)
  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b.border:SetWidth(53)
  b.border:SetHeight(53)
  b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  function b:place(angle)
    local x, y = M.offset(angle, shape(), M.radius())
    self:ClearAllPoints()
    self:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end
  b.angle = host.angle() or M.ANGLE
  b:place(b.angle)
  -- the host decides what opening means (in combat it only promises the window after combat)
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then host.toggle() else host.open() end
  end)
  -- OnUpdate only while dragged: an idle button costs nothing per frame
  b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", follow) end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    host.save(self.angle)
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(M.TIP)
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

return M
