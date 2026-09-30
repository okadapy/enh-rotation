local util = require("util")
local spells = require("spells")

local M = {}

M.HYSTERESIS = 0.03
M.INFLIGHT = 1.0
M.FS_DURATION = (spells.byKey.flameShock and spells.byKey.flameShock.duration) or 18

-- what a just-cast spell does before the game confirms it with an aura update
M.EFFECTS = {
  flameShock = function(S) S.target.fs = math.max(S.target.fs or 0, M.FS_DURATION) end,
  stormstrike = function(S) S.target.ss = { charges = 4, remains = 12 } end,
  lightningShield = function(S) S.buffs.ls = { charges = 3, remains = 600 } end,
  lightningBolt = function(S)
    if (S.buffs.mw.stacks or 0) >= 5 then S.buffs.mw = { stacks = 0, remains = 0 } end
  end,
}
M.EFFECTS.chainLightning = M.EFFECTS.lightningBolt

local P = {}
P.__index = P

function M.new(opts)
  opts = opts or {}
  return setmetatable({
    search = opts.search or require("search"),
    searchOpts = opts.searchOpts,
    hysteresis = opts.hysteresis or M.HYSTERESIS,
    inflight = {},
    plan = nil,
    planNow = nil,
  }, P)
end

function P:prepare(S)
  local n = util.copy(S)
  -- keep what the snapshot already tracks, add (or extend) the planner's own casts
  n.inflight = n.inflight or {}
  for key, expires in pairs(self.inflight) do
    local left = expires - S.now
    if left > 0 then
      n.inflight[key] = math.max(n.inflight[key] or 0, left)
      local fx = M.EFFECTS[key]
      if fx then fx(n) end
    else
      self.inflight[key] = nil
    end
  end
  return n
end

local function shifted(plan, elapsed, dropFirst)
  local steps = {}
  for i, st in ipairs(plan.steps) do
    if not (dropFirst and i == 1) then
      steps[#steps + 1] = { key = st.key, at = math.max(0, st.at - elapsed), reason = st.reason }
    end
  end
  return steps
end

function P:update(S, ev)
  ev = ev or { kind = "pulse" }
  local first = self.plan and self.plan.steps[1]
  local force = self.plan == nil or ev.kind == "target"
  local consumed = false
  if ev.kind == "cast" and ev.key then
    self.inflight[ev.key] = S.now + M.INFLIGHT
    if first and first.key == ev.key then consumed = true else force = true end
  end
  local s = self:prepare(S)
  local fresh = self.search.best(s, self.searchOpts)
  if not force then
    local old = shifted(self.plan, s.now - self.planNow, consumed)
    if #old > 0 then
      local oldValue, retimed = self.search.evaluate(s, old, self.searchOpts)
      if oldValue and fresh.value <= oldValue + math.abs(oldValue) * self.hysteresis then
        self.plan = { value = oldValue, steps = retimed, timedOut = fresh.timedOut, held = true }
        self.planNow = s.now
        return self.plan
      end
    end
  end
  self.plan = fresh
  self.planNow = s.now
  return fresh
end

return M
