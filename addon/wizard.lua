-- The first-run guide: four pages, out of combat (addon/guide.lua decides when). It points at the
-- timeline, unlocks it to be dragged on page 3 and offers one button mode there, and ends on the
-- ready check of stage 1 when the host has one.
local M = {}
M.NAME = "DoubtMyRotationWizard"
M.WIDTH, M.HEIGHT = 400, 270

M.PAGES = {
  { title = "This is the timeline",
    text = "Icons slide from the right toward the yellow line on the left. The big icon is the button to press next, "
      .. "the small ones come after it. Marks at the bottom are your next weapon swings (gold: main hand, grey: off hand); "
      .. "a green bar there means a Lightning Bolt cast now does not delay a swing. The dots at the top right count Maelstrom Weapon stacks." },
  { title = "Press it at the line",
    text = "When the big icon reaches the line and glows, press that button on your action bars. "
      .. "The plan is worked out again after every swing, press and proc: just follow the big icon. "
      .. "An icon left of the line is a reminder - a missing shield or weapon imbue, auto-attack off, a target too far." },
  { title = "Put it where you look", move = true, compact = true,
    text = "The timeline is unlocked now: drag it close to your character, where your eyes already are. "
      .. "It locks again when you leave this page. /dmr unlock moves it later." },
  { title = "Ready to fight?", checklist = true,
    text = "Before a fight: your shield up, imbues on your weapons (once you have learned them), auto-attack on "
      .. "(right-click the target). /dmr check shows what is missing, /dmr opens the settings, /dmr guide shows this guide again." },
}

local BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                   edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                   tile = true, tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } }

local function lines(items)
  local out = {}
  -- { ok, text }; the records of addon/ready.lua call the line "label"
  for i, it in ipairs(items) do out[i] = (it.ok and "|cff33ff33+|r " or "|cffff5555-|r ") .. tostring(it.text or it.label) end
  return table.concat(out, "\n")
end

local W = {}

function W:open(close)
  self.close = close
  self:Show()
  self:page(self.n or 1)
end

function W:page(n)
  n = math.max(1, math.min(#M.PAGES, n))
  local p = M.PAGES[n]
  self.n = n
  self:move(p.move == true)
  self.title:SetText(p.title)
  self.step:SetText(("%d / %d"):format(n, #M.PAGES))
  self.text:SetText(p.text)
  if p.compact then
    self.compact:SetChecked(self.host.config().compact == true)
    self.compact:Show()
  else
    self.compact:Hide()
  end
  local items = p.checklist and self.host.checklist and self.host.checklist()
  self.list:SetText(items and lines(items) or "")
  if items and self.host.openChecklist then self.check:Show() else self.check:Hide() end
  if n == 1 then self.back:Hide() else self.back:Show() end
  self.next:SetText(n == #M.PAGES and "Done" or "Next")
end

-- unlocks the timeline for page 3 and locks it after; only what the guide unlocked itself
function W:move(on)
  if on and not self.moving and not self.host.unlocked() then
    self.moving = true
    self.host.move(true)
  elseif not on and self.moving then
    self.moving = false
    self.host.move(false)
  end
end

-- a fight began (addon/guide.lua): away without closing; the page stays for after the fight
function W:hide()
  self.close = nil
  self:move(false)
  self:Hide()
end

function W:finish(how)
  local close = self.close
  self.close = nil
  self:move(false)
  self.n = nil
  self:Hide()
  if how == "done" then self.host.done() elseif how == "never" then self.host.never() end
  if close then close() end
end

local function button(w, key, text, point, x, width, onClick)
  local b = CreateFrame("Button", M.NAME .. key, w, "UIPanelButtonTemplate")
  b.kind = "button"
  b:SetWidth(width)
  b:SetHeight(22)
  b:SetPoint(point, w, point, x, 16)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  w.widgets[#w.widgets + 1] = b
  return b
end

function M.new(host)
  local w = CreateFrame("Frame", M.NAME, UIParent)
  w.kind, w.widgets, w.host = "window", {}, host
  w:SetWidth(M.WIDTH)
  w:SetHeight(M.HEIGHT)
  w:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
  w:SetFrameStrata("DIALOG")
  w:SetBackdrop(BACKDROP)
  w:SetMovable(true)
  w:EnableMouse(true)
  w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", function(self) self:StartMoving() end)
  w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  w.title:SetPoint("TOP", w, "TOP", 0, -16)
  w.step = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  w.step:SetPoint("TOPRIGHT", w, "TOPRIGHT", -16, -18)
  w.text = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  w.text:SetPoint("TOPLEFT", w, "TOPLEFT", 20, -44)
  w.text:SetWidth(M.WIDTH - 40)
  w.text:SetJustifyH("LEFT")
  w.list = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  w.list:SetPoint("TOPLEFT", w.text, "BOTTOMLEFT", 0, -8)
  w.list:SetWidth(M.WIDTH - 40)
  w.list:SetJustifyH("LEFT")
  local c = CreateFrame("CheckButton", M.NAME .. "Compact", w, "InterfaceOptionsCheckButtonTemplate")
  c.kind = "toggle"
  c:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 16, 44)
  _G[c:GetName() .. "Text"]:SetText("One button mode: only the big icon and reminders")
  -- OnClick comes after the box has flipped; GetChecked gives 1 or nil
  c:SetScript("OnClick", function(self) w.host.set("compact", self:GetChecked() and true or false) end)
  w.compact = c
  w.widgets[#w.widgets + 1] = c
  w.back = button(w, "Back", "Back", "BOTTOMLEFT", 16, 70, function() w:page(w.n - 1) end)
  w.skip = button(w, "Skip", "Skip", "BOTTOMLEFT", 90, 70, function() w:finish("skip") end)
  w.never = button(w, "Never", "Don't show again", "BOTTOMLEFT", 164, 124, function() w:finish("never") end)
  w.next = button(w, "Next", "Next", "BOTTOMRIGHT", -16, 90, function()
    if w.n < #M.PAGES then w:page(w.n + 1) else w:finish("done") end
  end)
  w.check = CreateFrame("Button", M.NAME .. "Check", w, "UIPanelButtonTemplate")
  w.check.kind = "button"
  w.check:SetWidth(160)
  w.check:SetHeight(22)
  w.check:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 16, 46)
  w.check:SetText("Open the ready check")
  w.check:SetScript("OnClick", function() if w.host.openChecklist then w.host.openChecklist() end end)
  w.widgets[#w.widgets + 1] = w.check
  for k, fn in pairs(W) do w[k] = fn end
  -- Escape is Skip (the client hides the frames listed in UISpecialFrames)
  w:SetScript("OnHide", function(self) if self.close then self:finish("skip") end end)
  if UISpecialFrames then table.insert(UISpecialFrames, M.NAME) end
  w:Hide()
  return w
end

return M
