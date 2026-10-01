-- The addon's entry: SavedVariables, the timeline's frame, /dmr, the settings window, the update
-- check, and the same engine the aura runs (runtime.start). The aura's host gives the engine a
-- region, saved data and a "show me" signal; here the frame is ours, always there, and needs no
-- signal (env.show stays nil).
local runtime = require("runtime")
local settings = require("settings")
local panel = require("panel")
local update = require("update")
local review = require("review")
local fightlog = require("fightlog")

local M = {}
M.NAME = "DoubtMyRotation"
M.TAG = "|cff33ff99DoubtMyRotation|r "
M.PAUSE = 0.3

local function say(line) print(M.TAG .. line) end

-- the build's option list plus the update check's and the fight summary's, as a copy: the
-- caller's list stays the aura's; one already there is not added twice (boot may run twice)
local function withExtras(options)
  local list, have = {}, {}
  for i, opt in ipairs(options) do
    list[i] = opt
    have[opt.key] = true
  end
  for _, opt in ipairs({ update.OPTION, fightlog.OPTION }) do
    if not have[opt.key] then list[#list + 1] = opt end
  end
  return list
end

-- the saved place, or the default one under the screen's center
local function place(f, p)
  f:ClearAllPoints()
  -- the anchor's frame is saved as nil: a frame reference does not survive SavedVariables
  if p then f:SetPoint(p[1], UIParent, p[3], p[4], p[5]) else f:SetPoint("CENTER", UIParent, "CENTER", 0, -200) end
end

function M.newFrame(o, db)
  local f = CreateFrame("Frame", "DoubtMyRotationFrame", UIParent)
  f:SetWidth(o.width)
  f:SetHeight(o.height)
  place(f, db.point)
  -- dragged past the edge or a smaller resolution: it stays where it can be reached
  f:SetClampedToScreen(true)
  -- what there is to grab while unlocked
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints(f)
  f.bg:SetTexture(0, 0, 0, 0.4)
  f.bg:Hide()
  f:SetMovable(true)
  f:EnableMouse(false)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local a, _, b, x, y = self:GetPoint()
    db.point = { a, nil, b, x, y }
  end)
  return f
end

function M.load(o)
  local db = DoubtMyRotationDB or {}
  DoubtMyRotationDB = db
  db.config = settings.merge(o.options, db.config)
  db.saved = db.saved or {}
  M.db = db
end

local function start()
  M.rt = runtime.start(M.db.config, M.env)
  -- a fresh engine runs; behind a hidden frame it must sleep (OnHide will not fire again)
  -- (IsVisible, not IsShown: Alt+Z hides the whole interface, the frame stays "shown")
  if M.rt and not M.frame:IsVisible() then runtime.sleep(M.rt) end
end

function M.login(o)
  local _, class = UnitClass("player")
  if class ~= "SHAMAN" then return end
  M.frame = M.frame or M.newFrame(o, M.db)
  M.frame:Show()
  M.env = { region = M.frame, saved = M.db.saved, libs = o.libs,
            onPress = function(e) if M.review then M.review:press(e) end end }
  start()
  M.review = M.review or review.new({
    rt = function() return M.rt end, db = M.db, say = say, config = function() return M.db.config end,
    now = GetTime, time = time, date = date,
  })
  M.review:start(DoubtMyRotationFights or CreateFrame("Frame", "DoubtMyRotationFights"))
  M.panel = M.panel or panel.new(o, M.host(o))
  M.updates = M.updates or update.new(runtime.VERSION, {
    db = M.db, send = SendAddonMessage, say = say,
    enabled = function() return M.db.config.updateCheck ~= false end,
  })
  M.updates:start(DoubtMyRotationUpdates or CreateFrame("Frame", "DoubtMyRotationUpdates"))
  -- hidden last time: the frame's OnHide (hooked by runtime.start) puts the engine to sleep
  if M.db.hidden then M.frame:Hide() end
end

-- restart the engine with the current settings; with a delay, once the changes stop coming
-- (a slider dragged by the mouse sends dozens of values a second). The timer is a frame of its
-- own: the timeline's frame may be hidden, and a hidden frame gets no OnUpdate.
function M.apply(delay)
  if not M.rt then return end
  M.due = delay
  if not delay then return start() end
  local t = DoubtMyRotationTimer or CreateFrame("Frame", "DoubtMyRotationTimer")
  t:SetScript("OnUpdate", function(_, dt)
    if not M.due then return end
    M.due = M.due - (dt or 0)
    if M.due <= 0 then M.apply() end
  end)
end

function M.open()
  InterfaceOptionsFrame_OpenToCategory(M.panel)
  InterfaceOptionsFrame_OpenToCategory(M.panel) -- the first call only expands the AddOns list
end

function M.handle(o, msg)
  if not M.db then return end
  if not M.frame then return say("shaman only") end
  local r = settings.command(o.options, M.db.config, msg)
  for _, line in ipairs(r.lines) do say(line) end
  local a = r.action
  if a == "open" then M.open()
  elseif a == "export" then runtime.showExport(M.env)
  elseif a == "unlock" or a == "lock" then
    M.frame:EnableMouse(a == "unlock")
    if a == "unlock" then M.frame.bg:Show() else M.frame.bg:Hide() end
  elseif a == "hide" then M.db.hidden = true; M.frame:Hide()
  elseif a == "show" then M.db.hidden = false; M.frame:Show()
  elseif a == "last" or a == "history" then M.review:open(a) end
  -- reset: the place too, the one way back for a timeline lost off screen
  if (msg or ""):match("^%s*(%S*)"):lower() == "reset" then
    M.db.point = nil
    place(M.frame, nil)
  end
  if r.changed then M.apply() end
end

-- what the settings window (addon/panel.lua) may read and do
function M.host(o)
  return {
    config = function() return M.db.config end,
    set = function(key, value) M.db.config[key] = value; M.apply(M.PAUSE) end,
    replace = function(c) M.db.config = settings.merge(o.options, c); M.apply() end,
    -- one button each for lock/unlock and hide/show: it does what its label says
    action = function(name)
      if name == "lock" then name = M.frame:IsMouseEnabled() and "lock" or "unlock"
      elseif name == "hide" then name = M.frame:IsShown() and "hide" or "show" end
      M.handle(o, name)
    end,
    label = function(name)
      if name == "lock" then return M.frame:IsMouseEnabled() and "Lock timeline" or "Unlock timeline" end
      if name == "hide" then return M.frame:IsShown() and "Hide timeline" or "Show timeline" end
      return "Export snapshots"
    end,
  }
end

function M.boot(o)
  o.options = withExtras(o.options)
  -- the aura (tools/build.lua B.initCode) stays idle while the addon is installed
  DoubtMyRotationAddon = M
  SLASH_DOUBTMYROTATION1 = "/dmr"
  SlashCmdList.DOUBTMYROTATION = function(msg) M.handle(o, msg) end
  local loader = DoubtMyRotationLoader or CreateFrame("Frame", "DoubtMyRotationLoader")
  loader:RegisterEvent("ADDON_LOADED")
  loader:RegisterEvent("PLAYER_LOGIN")
  loader:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == M.NAME then M.load(o)
    elseif event == "PLAYER_LOGIN" and M.db then M.login(o) end
  end)
  return loader
end

return M
