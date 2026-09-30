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

-- budgetMs: how much of a search one update() / work() call may run (nil = the whole search at
-- once). A search is never cut short by the clock: the displayed plan changes only when one has
-- finished, so what is shown does not depend on how fast the computer is.
function M.new(opts)
  opts = opts or {}
  return setmetatable({
    search = opts.search or require("search"),
    searchOpts = opts.searchOpts,
    hysteresis = opts.hysteresis or M.HYSTERESIS,
    budgetMs = opts.budgetMs,
    inflight = {},
    plan = nil,
    planNow = nil,
    job = nil,
    queued = nil,
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
      steps[#steps + 1] = { key = st.key, at = math.max(0, st.at - elapsed), reason = st.reason, afterSwing = st.afterSwing }
    end
  end
  return steps
end

-- a search without start() (a test stub) runs whole at once
local function startJob(search, s, opts)
  if search.start then return search.start(s, opts) end
  return { run = function(self) self.result = search.best(s, opts); return true end }
end

function P:begin(s, force)
  self.job = { s = s, force = force, search = startJob(self.search, s, self.searchOpts) }
end

-- the search of job finished: keep the current plan unless the new one is clearly better
function P:finish(job)
  local fresh, s = job.search.result, job.s
  self.job = nil
  self.searches = (self.searches or 0) + 1
  if not job.force and self.plan then
    local old = shifted(self.plan, s.now - self.planNow)
    if #old > 0 then
      local oldValue, retimed = self.search.evaluate(s, old, self.searchOpts)
      if oldValue and fresh.value <= oldValue + math.abs(oldValue) * self.hysteresis then
        self.plan = { value = oldValue, steps = retimed, timedOut = fresh.timedOut, capped = fresh.capped, held = true }
        self.planNow = s.now
        return
      end
    end
  end
  self.plan = fresh
  self.planNow = s.now
  self.swaps = (self.swaps or 0) + 1
end

-- run the pending search for at most budgetMs; true when a search finished in this call
function P:work(budgetMs)
  local job = self.job
  if not job then return false end
  if not job.search:run(budgetMs or self.budgetMs or math.huge) then return false end
  self:finish(job)
  if self.queued then
    local q = self.queued
    self.queued = nil
    self:begin(q.s, q.force)
  end
  return true
end

-- the current plan as seen at time now
function P:view(now)
  local plan = self.plan
  if not plan then return nil end
  local steps = shifted(plan, now - self.planNow)
  return { value = plan.value, steps = steps, timedOut = plan.timedOut, capped = plan.capped, held = plan.held }
end

function P:busy() return self.job ~= nil end

function P:update(S, ev)
  ev = ev or { kind = "pulse" }
  local first = self.plan and self.plan.steps[1]
  local force = self.plan == nil or ev.kind == "target"
  local restart = ev.kind == "target"
  if ev.kind == "cast" and ev.key then
    self.inflight[ev.key] = S.now + M.INFLIGHT
    if ev.done then
      -- the end of a cast whose start was already reported: nothing new was pressed
    elseif first and first.key == ev.key then
      -- the planned button was pressed: the rest of the plan goes on at once
      self.plan = { value = self.plan.value, steps = shifted(self.plan, S.now - self.planNow, true), held = true }
      self.planNow = S.now
      restart = true
    else
      force, restart = true, true
    end
  end
  local s = self:prepare(S)
  if self.job and not restart then
    -- a search is running: it finishes first, then the newest state is searched
    self.queued = { s = s, force = force }
  else
    -- a press or a new target makes a running search stale
    self.queued = nil
    self:begin(s, force)
  end
  self:work()
  return self:view(S.now) or { value = 0, steps = {} }
end

return M
