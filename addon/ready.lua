-- "Is everything ready": imbues on both weapons, a shield, a totem of each element on the Call
-- of the Elements bar (from 30), talents spent and recognized, the newest ranks the level
-- allows. Pure checks (ranks, items) over what gather() reads; a window of our own lists them on
-- the first login and on /dmr check (on later logins only a chat line if something is red);
-- outdated ranks also get one chat line on login and on a level up.
local spells = require("spells")
local data = require("spells_data")
local talents = require("talents")

local M = {}
M.OPTIONS = {
  { type = "toggle", key = "readyCheck", name = "Show the checklist on first login", default = true },
  { type = "toggle", key = "rankWarning", name = "Tell me when the trainer has new ranks", default = true },
}
M.TALENT = { stormstrike = true, lavaLash = true, shamanisticRage = true, feralSpirit = true }
M.ELEMENTS = { { 2, "Earth" }, { 1, "Fire" }, { 3, "Water" }, { 4, "Air" } } -- totem slot, name
M.CALL_LEVEL = 30
M.MAX_NAMES = 4
M.DELAY = 3     -- s after login or a level up: imbues and auras are read by then
M.REFRESH = 1   -- s between updates of the open window
M.ROW = 36
M.ICON_OK = "Interface\\RaidFrame\\ReadyCheck-Ready"
M.ICON_NO = "Interface\\RaidFrame\\ReadyCheck-NotReady"
M.NOT_READY = "something is not ready yet - /dmr check"

function M.ranks(level, known, names)
  local out = {}
  for _, key in ipairs(spells.KEYS) do
    if not M.TALENT[key] then
      local list, want = data[key] or {}, 0
      for i, r in ipairs(list) do if (r.level or 0) <= level then want = i end end
      local have = known[key] and known[key].rank or 0
      if want > have then
        out[#out + 1] = { key = key, name = (names and names[key]) or spells.byKey[key].name,
                          have = have, want = want, level = list[want].level }
      end
    end
  end
  return out
end

local function names(list)
  local out = {}
  for i = 1, math.min(#list, M.MAX_NAMES) do out[i] = list[i].name end
  return table.concat(out, ", ")
end

function M.rankLine(list)
  if #list == 0 then return nil end
  local parts = {}
  for i = 1, math.min(#list, M.MAX_NAMES) do
    local r = list[i]
    parts[i] = r.have > 0 and ("%s %d"):format(r.name, r.want) or (r.name .. " (new)")
  end
  local more = #list > M.MAX_NAMES and (", +%d more"):format(#list - M.MAX_NAMES) or ""
  return "the trainer has new ranks: " .. table.concat(parts, ", ") .. more .. " - /dmr check"
end

local function imbue(level)
  return level >= 30 and "Windfury Weapon" or level >= 10 and "Flametongue Weapon" or "Rockbiter Weapon"
end

function M.items(info)
  local out = {}
  local function add(key, ok, label, hint)
    out[#out + 1] = { key = key, ok = ok and true or false, label = label, hint = (not ok) and hint or nil }
  end
  local S, lvl = info.S or {}, info.level or 80
  local w = S.weapons or {}
  if w.mh then add("mh", w.mh.enchant ~= nil, "Main hand imbue", "Cast " .. imbue(lvl) .. " on the main hand") end
  if w.oh then add("oh", w.oh.enchant ~= nil, "Off hand imbue", "Cast Flametongue Weapon on the off hand") end
  local water = S.shieldPref == "water"
  if water or (S.spells and S.spells.lightningShield) then
    add("shield", S.player and S.player.shield ~= nil, "Shield", "Cast " .. (water and "Water Shield" or "Lightning Shield"))
  end
  if lvl >= M.CALL_LEVEL and info.call then
    local missing = {}
    for _, e in ipairs(M.ELEMENTS) do if not info.call[e[1]] then missing[#missing + 1] = e[2] end end
    add("totems", #missing == 0, "Totems on Call of the Elements",
        "Put a totem on each empty slot of the totem bar: " .. table.concat(missing, ", "))
  end
  local t = info.talents
  if t and t.listed > 0 and lvl >= 10 then
    if t.spent == 0 then add("talents", false, "Talents", "Spend your talent points")
    else add("talents", t.recognized, "Talents recognized", "Talents not recognized - unsupported client language?") end
  end
  local old = M.ranks(lvl, info.known or {}, info.names)
  add("ranks", #old == 0, "Newest spell ranks",
      "Visit the trainer: " .. names(old) .. (#old > M.MAX_NAMES and ", ..." or ""))
  return out
end

function M.gather(view)
  local S = view and view.S
  if not S then return nil end
  local cache = view.cache or {}
  local spent, listed = talents.spent(GetNumTalentTabs, GetNumTalents, GetTalentInfo)
  local recognized = false
  for _, r in pairs(cache.talents or {}) do if r > 0 then recognized = true end end
  local info = { level = UnitLevel("player") or 1, S = S, known = cache.known or {}, names = cache.names,
                 talents = { spent = spent, listed = listed, recognized = recognized } }
  -- Call of the Elements: page 1 of the totem bar, action slots 133-136 in 3.3.5a
  -- (ActionButton_CalculateAction: page NUM_ACTIONBAR_PAGES + GetMultiCastBarOffset(); on page 1
  -- MultiCastActionBarFrame.lua gives each button the ID of its totem slot)
  if info.known.callOfElements and HasAction then
    local page = (NUM_ACTIONBAR_PAGES or 6) + (GetMultiCastBarOffset and GetMultiCastBarOffset() or 6)
    local base = (page - 1) * 12
    info.call = {}
    for slot = 1, 4 do info.call[slot] = HasAction(base + slot) and true or false end
  end
  return info
end

local function newWindow()
  local w = CreateFrame("Frame", "DoubtMyRotationReady", UIParent)
  w:SetWidth(380)
  w:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  w:SetFrameStrata("DIALOG")
  w:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                  tile = true, tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
  w:SetMovable(true)
  w:EnableMouse(true)
  w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", function(self) self:StartMoving() end)
  w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", w, "TOP", 0, -14)
  title:SetText("DoubtMyRotation: ready to fight?")
  local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", w, "TOPRIGHT", -4, -4)
  w.rows = {}
  return w
end

function M.window(items)
  local w = DoubtMyRotationReady or newWindow()
  for i, it in ipairs(items) do
    local r = w.rows[i]
    if not r then
      local y = -40 - (i - 1) * M.ROW
      r = { icon = w:CreateTexture(nil, "ARTWORK"),
            label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight"),
            hint = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") }
      r.icon:SetWidth(16)
      r.icon:SetHeight(16)
      r.icon:SetPoint("TOPLEFT", w, "TOPLEFT", 20, y)
      r.label:SetPoint("TOPLEFT", w, "TOPLEFT", 44, y)
      r.hint:SetPoint("TOPLEFT", w, "TOPLEFT", 44, y - 16)
      r.hint:SetWidth(310)
      r.hint:SetJustifyH("LEFT")
      w.rows[i] = r
    end
    r.icon:SetTexture(it.ok and M.ICON_OK or M.ICON_NO)
    r.icon:Show()
    r.label:SetText(it.label)
    r.label:Show()
    if it.hint then r.hint:SetText(it.hint); r.hint:Show() else r.hint:Hide() end
  end
  for i = #items + 1, #w.rows do
    local r = w.rows[i]
    r.icon:Hide(); r.label:Hide(); r.hint:Hide()
  end
  w:SetHeight(56 + #items * M.ROW)
  w:Show()
  return w
end

local R = {}
R.__index = R

function M.new(deps)
  deps.inCombat = deps.inCombat or function() return UnitAffectingCombat("player") end
  return setmetatable({ deps = deps, said = {} }, R)
end

function R:start(frame)
  frame:RegisterEvent("PLAYER_LEVEL_UP")
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:SetScript("OnEvent", function(_, event, ...) self:onEvent(event, ...) end)
  frame:SetScript("OnUpdate", function() self:tick() end)
  self.dueAt, self.login = self.deps.now() + M.DELAY, true
end

function R:onEvent(event, level)
  if event == "PLAYER_LEVEL_UP" then
    -- UnitLevel may still give the old level here: the event's own
    self.level, self.dueAt = tonumber(level), self.deps.now() + M.DELAY
  elseif event == "PLAYER_REGEN_ENABLED" and self.waiting then
    self.dueAt = self.deps.now()
  end
end

-- the rank line, the same text at most once a session
function R:sayRanks(info)
  if self.deps.config().rankWarning == false then return end
  local line = M.rankLine(M.ranks(info.level, info.known, info.names))
  if line and not self.said[line] then
    self.said[line] = true
    self.deps.say(line)
  end
end

function R:due()
  local d = self.deps
  local info = M.gather(d.view())
  if not info then self.dueAt = d.now() + 1; return end -- no snapshot yet
  if self.level then info.level = self.level end
  self:sayRanks(info)
  self.waiting = false
  if self.login and d.config().readyCheck ~= false then
    if d.inCombat() then self.waiting = true; return end
    if not d.db.readySeen then
      d.db.readySeen = true
      self:show(info)
    elseif not self.toldNotReady then
      -- the window comes by itself once a character's life; after that a red item is one line
      -- a session, so a forgotten imbue is still caught before the pull
      for _, it in ipairs(M.items(info)) do
        if not it.ok then
          self.toldNotReady = true
          d.say(M.NOT_READY)
          break
        end
      end
    end
  end
  self.login = false
end

function R:show(info)
  self.win = M.window(M.items(info))
  self.refreshAt = self.deps.now() + M.REFRESH
end

function R:open()
  local info = M.gather(self.deps.view())
  if not info then return self.deps.say("no data yet - try again in a moment") end
  self:show(info)
end

function R:tick()
  local now = self.deps.now()
  if self.dueAt and now >= self.dueAt then
    self.dueAt = nil
    self:due()
  end
  if self.win and self.win:IsShown() and now >= (self.refreshAt or 0) then
    local info = M.gather(self.deps.view())
    if info then self:show(info) end
  end
end

return M
