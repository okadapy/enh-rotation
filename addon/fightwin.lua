-- The fight review window (/dmr last, /dmr history): the session's fights on the left, the
-- chosen one on the right, the boss history on a button. Its texts are pure functions.
local advice = require("advice")

local M = {}
M.ROWS = 10
M.WIDTH, M.HEIGHT = 640, 340
M.EMPTY = "No fight reviewed yet - fight something for 20s or more"

local function clock(s)
  s = math.floor((s or 0) + 0.5)
  return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

function M.listLine(entry)
  local f = entry.fight
  return ("%s %s %s"):format(f.name, clock(f.seconds), advice.pct(f.rate))
end

function M.detail(entry)
  local f, out = entry.fight, {}
  local function add(s) out[#out + 1] = s end
  local head = ("%s  %s  %s matched  ~%.2fs delay  ~%s lost"):format(f.key or f.name, clock(f.seconds), advice.pct(f.rate),
    f.delay or 0, advice.k(f.lost or 0))
  if entry.trend and advice.TRENDS[entry.trend] then head = head .. "  (" .. advice.TRENDS[entry.trend] .. ")" end
  add(head)
  add("")
  for _, t in ipairs(entry.tips or {}) do
    add("- " .. t.text)
    if t.detail then add("|cff999999  " .. t.detail .. "|r") end
  end
  add("")
  local mw, pr, fs = f.mw or {}, f.prep or {}, f.fs or {}
  local function s(x) return math.floor((x or 0) + 0.5) end
  add(("Maelstrom: %d stacks wasted, %ds on 5 stacks"):format(mw.wasted or 0, s(mw.idle)))
  add(("GCD idle %ds, swings delayed by casts %d"):format(s(f.gcdIdle), f.swings or 0))
  if (fs.seen or 0) > 0 then add(("Flame Shock uptime %s"):format(advice.pct(fs.up / fs.seen))) end
  add(("Without: shield %ds, fire totem %ds, enchants %ds, auto-attack %ds"):format(s(pr.shield), s(pr.totems), s(pr.enchants), s(pr.autoAttack)))
  add(("Not rated %d, stale plan %d, late %d"):format(f.unrated or 0, f.stale or 0, f.late or 0))
  return table.concat(out, "\n")
end

-- list: history's short records, newest first; date(fmt, t) formats a time (the client's date)
function M.historyText(key, list, date)
  local out = { "Boss history: " .. key }
  for _, r in ipairs(list) do
    out[#out + 1] = ("%s  %s  %s  ~%d/s lost  %s"):format(date("%m-%d %H:%M", r.date), clock(r.seconds), advice.pct(r.rate),
      math.floor((r.lostPerSec or 0) + 0.5), table.concat(r.tips or {}, ", "))
  end
  return table.concat(out, "\n")
end

local W = {}
W.__index = W

function M.new(deps)
  local self = setmetatable({ deps = deps, rows = {}, selected = 1 }, W)
  local f = CreateFrame("Frame", "DoubtMyRotationFightWindow", UIParent)
  f:SetWidth(M.WIDTH)
  f:SetHeight(M.HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                  tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  f:SetBackdropColor(0, 0, 0, 0.9)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(fr) if not InCombatLockdown() then fr:StartMoving() end end)
  f:SetScript("OnDragStop", function(fr) fr:StopMovingOrSizing() end)
  f:Hide()
  tinsert(UISpecialFrames, "DoubtMyRotationFightWindow") -- Esc closes it
  self.frame = f
  for i = 1, M.ROWS do
    local b = CreateFrame("Button", nil, f)
    b:SetWidth(180)
    b:SetHeight(18)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12 - (i - 1) * 20)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", b, "LEFT", 0, 0)
    b:SetScript("OnClick", function() self:select(i) end)
    self.rows[i] = b
  end
  self.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.text:SetPoint("TOPLEFT", f, "TOPLEFT", 204, -12)
  self.text:SetWidth(M.WIDTH - 216)
  self.text:SetJustifyH("LEFT")
  local hb = CreateFrame("Button", "DoubtMyRotationFightWindowHistory", f, "UIPanelButtonTemplate")
  hb:SetWidth(110)
  hb:SetHeight(22)
  hb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
  hb:SetText("Boss history")
  hb:SetScript("OnClick", function() self:showHistory() end)
  self.historyButton = hb
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  return self
end

function W:refresh()
  local list = self.deps.history.session
  for i, b in ipairs(self.rows) do
    local e = list[i]
    if e then
      b.label:SetText(M.listLine(e))
      b:Show()
    else
      b:Hide()
    end
  end
  local e = list[self.selected]
  local H = self.deps.history
  if self.mode == "history" and e and e.fight.key then
    self.text:SetText(M.historyText(e.fight.key, H:boss(e.fight.key), self.deps.date))
  elseif self.mode == "history" and not e and H:latestKey() then
    -- nothing fought this session: the saved history of the boss fought last
    self.text:SetText(M.historyText(H:latestKey(), H:boss(H:latestKey()), self.deps.date))
  elseif e then
    self.text:SetText(M.detail(e))
  else
    self.text:SetText(M.EMPTY)
  end
end

function W:select(i)
  self.selected, self.mode = i, "last"
  self:refresh()
end

function W:showHistory()
  self.mode = "history"
  self:refresh()
end

function W:open(mode)
  self.selected, self.mode = 1, mode or "last"
  self:refresh()
  self.frame:Show()
end

function W:hide() self.frame:Hide() end

return M
