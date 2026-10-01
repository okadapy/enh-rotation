-- The fight review in the game: the collector (fightlog) on the client's events and the
-- engine's press hook, the copied presses valued out of combat one a frame, then the tips,
-- the history, a line in chat and the window.
local fightlog = require("fightlog")
local advice = require("advice")
local history = require("history")
local fightwin = require("fightwin")
local search = require("search")

local M = {}
M.EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_SPELLCAST_START" }

function M.boss()
  if UnitExists("boss1") then return UnitName("boss1") end
  if UnitExists("target") and UnitClassification("target") == "worldboss" then return UnitName("target") end
  return nil
end

-- "25 Player", "10 Player (Heroic)", ... ; "" outside instances
function M.difficulty()
  local _, kind, _, name = GetInstanceInfo()
  if kind == nil or kind == "none" then return "" end
  return name or ""
end

local function evaluate(s, steps) return (search.evaluate(s, steps)) end

local R = {}
R.__index = R

-- deps: rt() -> the engine's rt or nil, db, say(line), config(), now(), time(), date(fmt, t)
function M.new(deps)
  local self = setmetatable({ deps = deps }, R)
  self.log = fightlog.new({
    now = deps.now,
    state = function() local rt = deps.rt(); return rt and rt.S end,
    due = function() local rt = deps.rt(); return rt and rt.due end,
    boss = M.boss,
    targetName = function() if UnitExists("target") and UnitCanAttack("player", "target") then return UnitName("target") end end,
    difficulty = M.difficulty,
  })
  self.history = history.new(deps.db, deps.time)
  return self
end

function R:report(f)
  local tips = advice.tips(f)
  local entry = self.history:add(f, tips)
  if self.deps.config().fightSummary ~= false then self.deps.say(advice.summary(f, tips, entry.trend)) end
  if self.window and self.window.frame:IsShown() then self.window:refresh() end
end

function R:onEvent(event, ...)
  if event == "PLAYER_REGEN_DISABLED" then
    if self.settling then
      fightlog.abandon(self.settling)
      self:report(self.settling)
      self.settling = nil
    end
    if self.window then self.window:hide() end
    self.log:begin()
  elseif event == "PLAYER_REGEN_ENABLED" then
    -- a second ENABLED without DISABLED (a /reload) must not drop a fight still being valued
    local f = self.log:finish()
    if f then self.settling = f end
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    local _, sub, _, _, _, dst, _, _, spellId, _, _, _, amount = ...
    if spellId == fightlog.MW_ID and dst == UnitGUID("player") then self.log:aura(sub, amount) end
  elseif event == "UNIT_SPELLCAST_START" then
    if (...) ~= "player" then return end
    local _, _, _, _, startMs, endMs = UnitCastingInfo("player")
    self.log:castStart((startMs and endMs) and (endMs - startMs) / 1000 or 0)
  end
end

function R:onUpdate(dt)
  if self.log:active() then
    self.log:tick(dt)
  elseif self.settling and fightlog.settle(self.settling, evaluate) then
    local f = self.settling
    self.settling = nil
    self:report(f)
  end
end

function R:press(e) self.log:press(e) end

function R:open(mode)
  self.window = self.window or fightwin.new({ history = self.history, date = self.deps.date })
  self.window:open(mode)
end

function R:start(frame)
  for _, e in ipairs(M.EVENTS) do frame:RegisterEvent(e) end
  frame:SetScript("OnEvent", function(_, event, ...) self:onEvent(event, ...) end)
  frame:SetScript("OnUpdate", function(_, dt) self:onUpdate(dt) end)
  return frame
end

return M
