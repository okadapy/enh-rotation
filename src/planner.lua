local util = require("util")
local spells = require("spells")
local model = require("model")

local M = {}

-- A new plan replaces the held one only if it is better by HYSTERESIS x the damage the held
-- plan does inside the horizon (not x its total value: the terminal estimate of the state after
-- the horizon is large and varies a lot, it made the margin arbitrary). When the held first
-- button is due within HOLD seconds, the margin is HOLD_FACTOR times larger: the player is
-- about to press it, and a late change costs more than the small gain.
M.HYSTERESIS = 0.08
M.HOLD = 0.3
M.HOLD_FACTOR = 2
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
    hold = opts.hold or M.HOLD,
    holdFactor = opts.holdFactor or M.HOLD_FACTOR,
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
      -- its cooldown, until the game reports it (the press is known from SENT, a round trip early);
      -- a cooldown the game already shows is taken as it is
      local sp = n.spells and n.spells[key]
      if sp and (sp.cd or 0) <= 0 then
        local cd = model.cooldownFor(n, key) - (M.INFLIGHT - left)
        local group = spells.byKey[key] and spells.byKey[key].sharedCd
        for _, k in ipairs(group and model.SHARED[group] or { key }) do
          local e = n.spells[k]
          if e and (e.cd or 0) < cd then e.cd = cd end
        end
      end
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

-- ev: what asked for this search (kept on the plan it produces: plan.trigger)
function P:begin(s, force, ev)
  self.job = { s = s, force = force, ev = ev, search = startJob(self.search, s, self.searchOpts) }
end

-- the search of job finished: keep the current plan unless the new one is clearly better
function P:finish(job)
  local fresh, s = job.search.result, job.s
  self.job = nil
  -- the last finished search as found (not the held plan): the fight review prices presses by it
  self.last = { now = s.now, value = fresh.value, firstValue = fresh.firstValue, s = s }
  if not job.force and self.plan then
    local old = shifted(self.plan, s.now - self.planNow)
    -- a search's "press nothing" is held too: without it any new search replaced it at once,
    -- and near a mob's death the big icon came and went with every noisy time-to-die
    -- (a plan emptied by pressing its last button is no such decision)
    if #old > 0 or (self.plan.idle and self.search.idle) then
      local oldValue, retimed, horizonValue
      if #old > 0 then
        oldValue, retimed, horizonValue = self.search.evaluate(s, old, self.searchOpts)
        -- The held first button is weighed by its best continuation the new search found: the
        -- old tail is not re-optimized and waits through the seconds the horizon has moved on,
        -- a handicap larger than the margin, so right after a press the icon changed for nothing.
        local alt = fresh.byFirst and self.search.firstKey and fresh.byFirst[self.search.firstKey(old[1])]
        if alt and #alt > 0 then
          local v, r, h = self.search.evaluate(s, alt, self.searchOpts)
          if v and (not oldValue or v > oldValue) then oldValue, retimed, horizonValue = v, r, h end
        end
      else
        retimed = {}
        oldValue, horizonValue = self.search.idle(s, self.searchOpts)
      end
      local margin = oldValue and math.abs(horizonValue or oldValue) * self.hysteresis
      if margin and retimed[1] and retimed[1].at <= self.hold then margin = margin * self.holdFactor end
      if oldValue and fresh.value <= oldValue + margin then
        self.plan = { value = oldValue, steps = retimed, timedOut = fresh.timedOut, capped = fresh.capped, held = true,
                      trigger = job.ev, idle = #retimed == 0 or nil }
        self.planNow = s.now
        return
      end
    end
  end
  fresh.trigger = job.ev
  fresh.idle = #fresh.steps == 0 or nil
  self.plan = fresh
  self.planNow = s.now
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
    self:begin(q.s, q.force, q.ev)
  end
  return true
end

-- the current plan as seen at time now
function P:view(now)
  local plan = self.plan
  if not plan then return nil end
  local steps = shifted(plan, now - self.planNow)
  return { value = plan.value, steps = steps, timedOut = plan.timedOut, capped = plan.capped, held = plan.held,
           trigger = plan.trigger }
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
      self.plan = { value = self.plan.value, steps = shifted(self.plan, S.now - self.planNow, true), held = true, trigger = ev }
      self.planNow = S.now
      restart = true
    else
      force, restart = true, true
    end
  end
  local s = self:prepare(S)
  if ev.kind == "pulse" and not force then
    -- Nothing happened: the running search goes on, or the held plan is only moved on in time.
    -- A new search now could only find what the moving horizon brings in, and that is flicker.
    if self.job then return self:view(S.now) end
    local old = shifted(self.plan, S.now - self.planNow)
    if #old > 0 then
      local v, retimed = self.search.evaluate(s, old, self.searchOpts)
      if v then
        local pl = self.plan
        self.plan = { value = v, steps = retimed, timedOut = pl.timedOut, capped = pl.capped, held = true, trigger = pl.trigger }
        self.planNow = S.now
        return self:view(S.now)
      end
      force = true -- the held plan can no longer be played
    end
  end
  if self.job and not restart then
    -- a search is running: it finishes first, then the newest state is searched
    -- the queued search stands for every event since: keep the most telling one
    local q = self.queued
    local qev = (q and q.ev and q.ev.kind ~= "pulse" and ev.kind == "pulse") and q.ev or ev
    self.queued = { s = s, force = force or (q and q.force) or false, ev = qev }
  else
    -- a press or a new target makes a running search stale
    self.queued = nil
    self:begin(s, force, ev)
  end
  self:work()
  return self:view(S.now) or { value = 0, steps = {} }
end

return M
