-- The addon's entry: SavedVariables (the account's profiles in DoubtMyRotationDB, the character's
-- pick, place and progress in DoubtMyRotationCharDB), the timeline's frame, /dmr, the settings
-- window and its Profiles page, the update check, the stage 1 helpers, the first-run guide and
-- level cards, the minimap button, ElvUI's look, the fight review (addon/review.lua), and the same
-- engine the aura runs (runtime.start).
-- The aura's host gives the engine a region, saved data and a "show me" signal; here the frame is
-- ours, always there, and needs no signal (env.show stays nil).
local runtime = require("runtime")
local timeline = require("timeline")
local settings = require("settings")
local profiles = require("profiles")
local panel = require("panel")
local profilepage = require("profilepage")
local update = require("update")
local ready = require("ready")
local helpers = require("helpers")
local guide = require("guide")
local cards = require("cards")
local wizard = require("wizard")
local coach = require("coach")
local minimap = require("minimap")
local skin = require("skin")
local review = require("review")

local M = {}
M.NAME = "DoubtMyRotation"
M.TAG = "|cff33ff99DoubtMyRotation|r "
M.PAUSE = 0.3
M.EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED" }

local function say(line) print(M.TAG .. line) end

-- the build's option list plus the addon's own (the update check, the helpers, settings.ADDON_OPTIONS),
-- as a copy: the caller's list stays the aura's
local function addonOptions(options)
  local extra = { update.OPTION }
  for _, opt in ipairs(helpers.options()) do extra[#extra + 1] = opt end
  for _, opt in ipairs(settings.ADDON_OPTIONS) do extra[#extra + 1] = opt end
  return settings.withExtra(options, extra)
end

-- the saved place, or the default one under the screen's center
local function place(f, p)
  f:ClearAllPoints()
  -- the anchor's frame is saved as nil: a frame reference does not survive SavedVariables
  if p then f:SetPoint(p[1], UIParent, p[3], p[4], p[5]) else f:SetPoint("CENTER", UIParent, "CENTER", 0, -200) end
end

function M.newFrame(o, char)
  local f = CreateFrame("Frame", "DoubtMyRotationFrame", UIParent)
  f.kind = "timeline" -- addon/skin.lua: ElvUI's backdrop instead of f.bg
  f:SetWidth(o.width)
  f:SetHeight(o.height)
  place(f, char.point)
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
    char.point = { a, nil, b, x, y }
  end)
  return f
end

function M.load(o)
  local db = DoubtMyRotationDB or {}
  DoubtMyRotationDB = db
  -- a new SavedVariablesPerCharacter: the client reads the .toc only at its start
  local char = DoubtMyRotationCharDB or {}
  DoubtMyRotationCharDB = char
  profiles.migrate(db, char)
  db.saved = db.saved or {}
  M.db, M.char = db, char
  M.profile, M.why = char.profile, "picked"
  M.config = profiles.view(o.options, db, M.profile)
end

function M.save(o)
  profiles.store(o.options, M.db, M.profile, M.config)
end

local function start()
  -- one button mode: the frame shrinks to the icon (src/timeline.lua: 2 x nowX wide)
  M.frame:SetWidth(M.config.compact and 2 * timeline.DEFAULTS.nowX or M.width)
  M.rt = runtime.start(M.config, M.env)
  -- a fresh engine runs; behind a hidden frame it must sleep (OnHide will not fire again)
  -- (IsVisible, not IsShown: Alt+Z hides the whole interface, the frame stays "shown")
  if M.rt and not M.frame:IsVisible() then runtime.sleep(M.rt) end
end

-- what the helpers (addon/helpers.lua) read of the running engine: one table, filled anew from
-- M.rt each call, so a restarted engine is picked up with no word to them
local VIEW = {}
function M.view()
  local rt = M.rt
  if not rt then return nil end
  local tl = rt.tl
  VIEW.plan, VIEW.S, VIEW.planner = rt.plan, rt.S, rt.planner
  VIEW.cache = rt.ctx and rt.ctx.cache
  VIEW.at, VIEW.frame, VIEW.icon = tl and tl.at, tl and tl.frame, tl and tl.icons and tl.icons[1]
  VIEW.active = not (rt.sleeping or rt.stopped or rt.inactive)
  return VIEW
end

-- the guide's last page: the ready check of addon/ready.lua as { ok, label } lines, its window
-- through the helpers (the same as /dmr check)
local function checklist()
  return {
    items = function()
      local info = ready.gather(M.view())
      return info and ready.items(info) or {}
    end,
    open = function() if M.helpers then M.helpers.check() end end,
  }
end

function M.showMinimap()
  if not M.mini then return end
  if M.config.minimap ~= false then M.mini:Show() else M.mini:Hide() end
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

-- values changed: saved where they live, the addon's own parts follow, the engine restarts
function M.changed(o, delay)
  M.save(o)
  M.showMinimap()
  if M.skin then M.skin:refresh() end
  M.apply(delay)
end

-- where the character is and its level pick the profile (addon/profiles.lua)
function M.choose(o, announce)
  local _, where = IsInInstance()
  local level = math.max(M.level or 0, UnitLevel("player") or 0)
  local name, why = profiles.pick(M.db, M.char, where, level)
  M.switch(o, name, why, announce)
end

function M.switch(o, name, why, announce)
  if name == M.profile then
    M.why = why
    -- only an open page: its drop-downs share the client's menu list (it refreshes on OnShow anyway)
    if M.profilePage and M.profilePage:IsShown() then M.profilePage.refresh(M.profilePage) end
    return
  end
  -- a new profile restarts the engine: not in the middle of a fight (PLAYER_REGEN_ENABLED picks again)
  if M.rt and InCombatLockdown() then return end
  M.save(o)
  M.profile, M.why = name, why
  M.config = profiles.view(o.options, M.db, name)
  if M.panel then panel.reload(M.panel) end
  if M.profilePage then M.profilePage.refresh(M.profilePage) end
  if not M.rt then return end
  if announce then say(("profile %s (%s)"):format(name, profiles.RULE_NAMES[why] or "picked")) end
  M.changed(o)
end

-- Interface Options opened by an addon in a fight can taint Blizzard's own pages: after the fight
function M.open()
  if InCombatLockdown() then
    if not M.openLater then say("the settings open after combat") end
    M.openLater = true
    return
  end
  M.openLater = nil
  InterfaceOptionsFrame_OpenToCategory(M.panel)
  InterfaceOptionsFrame_OpenToCategory(M.panel) -- the first call only expands the AddOns list
end

function M.move(on)
  M.frame:EnableMouse(on)
  if on then M.frame.bg:Show() else M.frame.bg:Hide() end
end

function M.handle(o, msg)
  if not M.db then return end
  if not M.frame then return say("shaman only") end
  local r = settings.command(o.options, M.config, msg)
  for _, line in ipairs(r.lines) do say(line) end
  local a = r.action
  if a == "open" then M.open()
  elseif a == "guide" then if M.coach then M.coach:openGuide() end
  elseif a == "export" then
    runtime.showExport(M.env)
    if M.skin then M.skin:export(EnhRotExportFrame) end
  elseif a == "check" then if M.helpers then M.helpers.check() end
  elseif a == "unlock" or a == "lock" then M.move(a == "unlock")
  elseif a == "hide" then M.char.hidden = true; M.frame:Hide()
  elseif a == "show" then M.char.hidden = false; M.frame:Show()
  elseif a == "last" or a == "history" then if M.review then M.review:open(a) end end
  -- reset: the place too, the one way back for a timeline lost off screen
  if (msg or ""):match("^%s*(%S*)"):lower() == "reset" then
    M.char.point = nil
    place(M.frame, nil)
  end
  if r.changed then M.changed(o) end
end

-- what the settings window (addon/panel.lua) may read and do
function M.host(o)
  return {
    config = function() return M.config end,
    set = function(key, value) M.config[key] = value; M.changed(o, M.PAUSE) end,
    replace = function(c) M.config = settings.merge(o.options, c); M.changed(o) end,
    -- one button each for lock/unlock and hide/show: it does what its label says
    action = function(name)
      if name == "lock" then name = M.frame:IsMouseEnabled() and "lock" or "unlock"
      elseif name == "hide" then name = M.frame:IsShown() and "hide" or "show" end
      M.handle(o, name)
    end,
    label = function(name)
      if name == "lock" then return M.frame:IsMouseEnabled() and "Lock timeline" or "Unlock timeline" end
      if name == "hide" then return M.frame:IsShown() and "Hide timeline" or "Show timeline" end
      if name == "guide" then return "Show the guide" end
      return "Export snapshots"
    end,
  }
end

-- the Profiles page (addon/profilepage.lua)
function M.profileHost(o)
  return {
    list = function() return profiles.names(M.db) end,
    current = function() return M.char.profile end,
    active = function() return M.profile, M.why end,
    pick = function(name) M.char.profile = name; M.choose(o, false) end,
    create = function(name, copyCurrent)
      local n, err = profiles.create(M.db, name, copyCurrent and M.config or nil)
      if not n then return nil, err end
      M.char.profile = n
      M.choose(o, false)
      return n
    end,
    -- the active profile deleted: save() finds no profile to write into, Default comes in
    delete = function(name)
      local ok, err = profiles.delete(M.db, M.char, name)
      if ok then M.choose(o, false) end
      return ok, err
    end,
    reset = function()
      profiles.reset(M.db, M.profile)
      M.config = profiles.view(o.options, M.db, M.profile)
      if M.panel then panel.reload(M.panel) end
      M.changed(o)
    end,
    rule = function(rule) return M.char.auto[rule] end,
    setRule = function(rule, name) M.char.auto[rule] = name; M.choose(o, false) end,
  }
end

-- the first-run guide (addon/wizard.lua); stage 1's ready check on its last page, when there is one
function M.wizardHost(o)
  local c = M.checklist
  return {
    config = function() return M.config end,
    set = function(key, value) M.config[key] = value; M.changed(o) end,
    unlocked = function() return M.frame:IsMouseEnabled() end,
    move = function(on) M.move(on) end,
    checklist = c and c.items or nil,
    openChecklist = c and c.open or nil,
    done = function() M.char.wizard = "done" end,
    never = function() M.db.wizardOff = true end,
  }
end

function M.cardHost(o)
  return {
    config = function() return M.config end,
    set = function(key, value) M.config[key] = value; M.changed(o) end,
  }
end

function M.miniHost(o)
  return {
    open = function() M.open() end,
    toggle = function() M.host(o).action("hide") end,
    angle = function() return M.char.minimap and M.char.minimap.angle end,
    save = function(angle) M.char.minimap = { angle = angle } end,
  }
end

local function coachDeps(o)
  return {
    guide = M.guide, db = M.db, char = M.char,
    level = function() return math.max(M.level or 0, UnitLevel("player") or 0) end,
    enabled = function(key) return M.config[key] ~= false end,
    wizard = function()
      M.wizard = M.wizard or wizard.new(M.wizardHost(o))
      M.skin:frame(M.wizard)
      return M.wizard
    end,
    card = function()
      local w = cards.window(M.cardHost(o))
      M.skin:frame(w)
      return w
    end,
  }
end

-- the helpers, once; the ready window (addon/ready.lua) is made on its first showing, so it gets
-- ElvUI's look right after each showing (the skin styles a frame once)
local function startHelpers()
  if M.helpers then return end
  M.helpers = helpers.start(M, say)
  local r = M.helpers.ready
  if not r then return end
  local show = r.show
  r.show = function(self, ...)
    local w = show(self, ...)
    M.skin:ready(DoubtMyRotationReady)
    return w
  end
end

-- the zone and the level pick the profile; a fight's end lets a waiting switch and settings through
local function listen(o)
  local f = DoubtMyRotationEvents or CreateFrame("Frame", "DoubtMyRotationEvents")
  for _, e in ipairs(M.EVENTS) do f:RegisterEvent(e) end
  f:SetScript("OnEvent", function(_, event, arg)
    -- UnitLevel may still give the old level here: the event's own
    if event == "PLAYER_LEVEL_UP" then M.level = tonumber(arg) end
    if event == "PLAYER_REGEN_ENABLED" and M.openLater then M.open() end
    M.choose(o, true)
  end)
end

function M.login(o)
  local _, class = UnitClass("player")
  if class ~= "SHAMAN" then return end
  M.width = o.width
  M.choose(o, false) -- the profile for where the character is, before the engine starts
  M.frame = M.frame or M.newFrame(o, M.char)
  M.frame:Show()
  -- onPress: the engine's presses to the fight review (src/runtime.lua, addon-only)
  M.env = { region = M.frame, saved = M.db.saved, libs = o.libs,
            onPress = function(e) if M.review then M.review:press(e) end end }
  start()
  M.skin = M.skin or skin.new({ enabled = function() return M.config.elvui ~= false end, say = say })
  M.skin:frame(M.frame)
  M.panel = M.panel or panel.new(o, M.host(o))
  M.skin:frame(M.panel)
  M.profilePage = M.profilePage or profilepage.new(M.profileHost(o))
  M.skin:frame(M.profilePage)
  M.updates = M.updates or update.new(runtime.VERSION, {
    db = M.db, send = SendAddonMessage, say = say,
    enabled = function() return M.config.updateCheck ~= false end,
  })
  M.updates:start(DoubtMyRotationUpdates or CreateFrame("Frame", "DoubtMyRotationUpdates"))
  startHelpers()
  M.mini = M.mini or minimap.new(M.miniHost(o))
  M.skin:frame(M.mini)
  M.showMinimap()
  listen(o)
  M.checklist = M.checklist or checklist()
  M.guide = M.guide or guide.new()
  M.guide:start(DoubtMyRotationGuide or CreateFrame("Frame", "DoubtMyRotationGuide"))
  M.coach = M.coach or coach.new(coachDeps(o))
  M.coach:start(DoubtMyRotationCoach or CreateFrame("Frame", "DoubtMyRotationCoach"))
  M.coach:login()
  M.review = M.review or review.new({
    rt = function() return M.rt end, db = M.char, say = say, config = function() return M.config end,
    now = GetTime, time = time, date = date,
    guide = function() return M.guide end, skin = function(f) M.skin:frame(f) end,
  })
  M.review:start(DoubtMyRotationFights or CreateFrame("Frame", "DoubtMyRotationFights"))
  -- hidden last time: the frame's OnHide (hooked by runtime.start) puts the engine to sleep
  if M.char.hidden then M.frame:Hide() end
end

function M.boot(o)
  o.options = addonOptions(o.options)
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
