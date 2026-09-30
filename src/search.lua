local M = {}

M.HORIZON = 6.0
M.BEAM = 7
M.DEPTH = 4
M.BUDGET_MS = 2 -- per frame: a search runs in slices (search.start), never cut by the clock
M.NODE_CAP = 300 -- the whole search stops after this many candidates (deterministic)
M.READY_EPS = 0.05
M.WEAVE_KEYS = { "lightningBolt", "chainLightning" } -- what waiting for a swing is for
M.PER_FIRST = 1 -- beam places kept for the best chains of every first button (diversity)
M.DIVERSITY = 0.05 -- ... if their score is within this share of the layer's best
M.SWING_SLACK = 0.3 -- replay: an "after swing" step waits for a swing at most this much later than planned
M.FILL_MARGIN = 0.02 -- first buttons whose best chain is within this share of the best get fillIdle too
M.FILL_REPLAYS = 12 -- fillIdle replays per search, best chains first (bounds its time)
M.IDLE_MIN = 1.0 -- a wait this long inside the plan gets each ready button tried in it (fillIdle)

-- the text under the first icon: short (it fits under a 64 px icon), plain words, and it says why
-- this button and not its neighbour (M.reason picks the case; these are the fixed ones)
M.REASONS = {
  stormstrike = "Stormstrike: +20% nature",
  lavaLash = "filler",
  frostShock = "Frost Shock: damage + slow",
  fireElemental = "big cooldown",
  feralSpirit = "big cooldown",
  callOfElements = "totems expiring",
  lightningShield = "Lightning Shield missing",
}

local function q(x) return math.floor((x or 0) * 4 + 0.5) end

local FIRE_CODE = { searing = 1, magma = 2, fireElemental = 3, other = 4 }
local RANGE_CODE = { melee = 1, ["20"] = 2, ["30"] = 3, far = 4 }

local floor, char, unpack_ = math.floor, string.char, unpack
local BYTES = {} -- reused by every signature() call

-- quantized to 0.25 s and packed into one byte; anything past 63.5 s is "far away" anyway
local function b(x)
  if not x or x <= 0 then return 0 end
  local v = floor(x * 4 + 0.5)
  if v > 254 then return 254 end
  return v
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- equal signatures = states the rest of the horizon cannot tell apart
function M.signature(S)
  local sw, fire, t = S.swing, S.totems and S.totems.fire, S.target
  local mw, ss = S.buffs and S.buffs.mw, t.ss
  local mh, oh = sw and sw.mh, sw and sw.oh
  local bytes = BYTES
  bytes[1], bytes[2], bytes[3], bytes[4], bytes[5] =
    b(mw and mw.stacks), b(t.fs), b(ss and ss.charges), b(S.gcdRemains), b(S.castRemains)
  bytes[6], bytes[7], bytes[8] = sw and (sw.attacking and 1 or 2) or 0, b(mh and mh.next), b(oh and oh.next)
  bytes[9], bytes[10] = fire and (FIRE_CODE[fire.kind] or 0) or 255, b(fire and fire.remains)
  -- a mob on its way in (model.advance moves it to melee): where it is and when it arrives
  local mi = t.meleeIn
  bytes[11], bytes[12] = RANGE_CODE[t.range] or 0, mi and b(mi) or 255
  -- the spell key set is the same in the whole search tree: sort it once per search
  local memo = S.memo
  local keys = memo and memo.sigKeys
  if not keys then
    keys = sortedKeys(S.spells)
    if memo then memo.sigKeys = keys end
  end
  local spells = S.spells
  for i = 1, #keys do
    local sp = spells[keys[i]]
    local v = 255
    if sp then
      local cd = sp.cd
      if cd and cd > 0 then
        v = floor(cd * 4 + 0.5)
        if v > 254 then v = 254 end
      else
        v = 0
      end
    end
    bytes[12 + i] = v
  end
  local hpStep = (t.hpMax or 1) * 0.005
  if hpStep < 1 then hpStep = 1 end
  local n = 12 + #keys
  local hp = floor((t.hp or 0) / hpStep)
  local mana = floor((S.player.mana or 0) / 50)
  local now = floor((S.now or 0) * 4 + 0.5)
  if hp > 255 then hp = 255 elseif hp < 0 then hp = 0 end
  if mana < 0 then mana = 0 end
  if now < 0 then now = 0 end
  bytes[n + 1] = hp
  bytes[n + 2], bytes[n + 3], bytes[n + 4] = mana % 256, floor(mana / 256) % 256, floor(mana / 65536) % 256
  bytes[n + 5], bytes[n + 6] = now % 256, floor(now / 256) % 256
  bytes[n + 7], bytes[n + 8] = floor(now / 65536) % 256, floor(now / 16777216) % 256
  return char(unpack_(bytes, 1, n + 8))
end

-- built once: the search asks for a reason for many candidates
local FITS, DELAYS, HARD = {}, {}, {}
for n = 0, 4 do
  local st = n == 1 and "1 stack" or n .. " stacks"
  FITS[n], DELAYS[n], HARD[n] = st .. ", fits before swing", st .. ": delays swing", st .. ": hard-cast"
end
-- with no stacks the cast resets the swing timer however short it is (model: cast.reset)
DELAYS[0], FITS[0] = "0 stacks: resets swing", "0 stacks: resets swing"

local castModel
-- the swing clock goes on when the server ends a cast (castTime + latency after the press, as in
-- model.apply) and swings due before that wait for it. true: the cast ends before the next own
-- swing of either hand; false: it holds one back; nil: no swings are coming
local function beforeSwing(S, key)
  local sw = S.swing
  if not (sw and sw.attacking) then return nil end
  local mh, oh = sw.mh, sw.oh
  local nxt = mh and mh.next
  if oh and oh.next and not (nxt and nxt <= oh.next) then nxt = oh.next end
  if not nxt then return nil end
  castModel = castModel or require("model")
  return castModel.castTime(S, key) + (S.latency or 0) <= nxt + 1e-9
end

-- afterSwing: kept for the callers; whether a cast fits is read from the state's swing clock
function M.reason(S, key, afterSwing)
  local t = S.target
  if key == "lightningBolt" or key == "chainLightning" then
    local mw = (S.buffs and S.buffs.mw and S.buffs.mw.stacks) or 0
    if mw >= 5 then return "5 stacks: instant" end
    if t.range and t.range ~= "melee" then return "pull: target out of melee" end
    mw = math.floor(mw)
    local fits = beforeSwing(S, key)
    if fits == nil then return HARD[mw] end
    return fits and FITS[mw] or DELAYS[mw]
  elseif key == "flameShock" then
    return (t.fs or 0) <= 0 and "Flame Shock not ticking" or "refresh Flame Shock"
  elseif key == "earthShock" then
    return (t.fs or 0) > 0 and "Flame Shock up: Earth Shock" or "Earth Shock: instant damage"
  elseif key == "searingTotem" or key == "magmaTotem" or key == "fireNova" then
    local n = require("damage").totemTargets(S)
    if key == "searingTotem" then return n <= 1 and "1 target: Searing Totem" or "fire totem: Searing Totem" end
    if n >= 2 then return ("%d targets: %s"):format(n, key == "fireNova" and "Fire Nova" or "Magma Totem") end
    return key == "fireNova" and "Fire Nova ready" or "fire totem: Magma Totem"
  elseif key == "shamanisticRage" then
    local p = S.player
    return (p.manaMax and p.manaMax > 0 and p.mana / p.manaMax < 0.3) and "mana: Shamanistic Rage"
      or "Rage: mana, -30% damage"
  elseif key == "lightningShield" then
    local ls = S.buffs and S.buffs.ls
    if ls and (ls.charges or 0) > 0 then return "Lightning Shield low" end
  end
  return M.REASONS[key] or key
end

-- in game: debugprofilestop() (ms); in tests: os.clock()
local function defaultClock()
  if debugprofilestop then return debugprofilestop() end
  if os and os.clock then return os.clock() * 1000 end
  return 0
end

local function defaults(opts)
  opts = opts or {}
  return {
    model = opts.model or require("model"),
    value = opts.value or require("value"),
    horizon = opts.horizon or M.HORIZON,
    beam = opts.beam or M.BEAM,
    depth = opts.depth or M.DEPTH,
    budgetMs = opts.budgetMs or M.BUDGET_MS,
    nodeCap = opts.nodeCap or M.NODE_CAP,
    perFirst = opts.perFirst or M.PER_FIRST,
    diversity = opts.diversity or M.DIVERSITY,
    fillMargin = opts.fillMargin or M.FILL_MARGIN,
    fillReplays = opts.fillReplays or M.FILL_REPLAYS,
    clock = opts.clock or defaultClock,
  }
end

-- waiting spends no mana, but Shamanistic Rage returns some on every swing
local function waitValue(o, S, S1, dmg)
  return o.value.step(S, S1, dmg, (S.player.mana or 0) - (S1.player.mana or 0))
end

-- A cast must end inside the horizon: its damage counts at once, while what it costs (swings
-- held back or reset after it) would fall past the horizon and never be paid.
local function fitsHorizon(o, S, key, at)
  local ct = o.model.castTime and o.model.castTime(S, key) or 0
  return ct <= 0 or at + ct <= o.horizon + 1e-9
end

-- pad the chain with waiting up to the horizon, then add what the end state is still worth
local function finalScore(o, node, rootNow)
  local S, v = node.S, node.v
  local t = S.now - rootNow
  if t < o.horizon then
    -- the padded state is thrown away: use the model's allocation-free scratch when it has one
    local S2, dmg = (o.model.peekWait or o.model.wait)(S, o.horizon - t)
    v = v + waitValue(o, S, S2, dmg)
    S = S2
  end
  return v + o.value.terminal(S), v
end

-- replay one step: wait exactly a.readyIn (> 0), then press.
-- peek: the new state is a scratch one (model.peek*), for a chain read only at its newest state
-- and the one before (a scratch state may share tables with the one two steps before it, which
-- the next peek changes); else a real state, which stays valid (a node extended again later).
-- replayed: the caller sets the step's reason itself (not computed here).
local function extend(o, node, a, rootNow, afterSwing, peek, replayed)
  local S, v = node.S, node.v
  local m = o.model
  local wait, apply = m.wait, m.apply
  if peek and m.peekApply then wait, apply = m.peekWait, m.peekApply end
  if a.readyIn > 1e-9 then
    if S.now + a.readyIn - rootNow >= o.horizon then return nil end
    local S1, d = wait(S, a.readyIn)
    v = v + waitValue(o, S, S1, d)
    S = S1
  end
  local at = S.now - rootNow
  if at >= o.horizon or not fitsHorizon(o, S, a.key, at) then return nil end
  local S2, dmg = apply(S, a.key, o.horizon - at)
  v = v + o.value.step(S, S2, dmg, (S.player.mana or 0) - (S2.player.mana or 0))
  local steps = {}
  for i, s in ipairs(node.steps) do steps[i] = s end
  steps[#steps + 1] = { key = a.key, at = at, reason = not replayed and M.reason(S, a.key, afterSwing) or nil,
                        afterSwing = afterSwing or nil }
  return { S = S2, v = v, steps = steps, depth = node.depth + 1 }
end

local stepsOf
-- tie-break for equal scores; cached, the sort asks for it many times
local function chainKey(node)
  local k = node.chainKey
  if k then return k end
  local parts = {}
  for i, s in ipairs(stepsOf(node)) do parts[i] = s.key .. "@" .. q(s.at) end
  k = table.concat(parts, ",") .. (node.waited and "+w" or "")
  node.chainKey = k
  return k
end

-- shallow root copy with a fresh per-search memo (see damage.lua); S itself is never touched
local function root(S)
  local r = {}
  for k, v in pairs(S) do r[k] = v end
  r.memo = {}
  return r
end

-- stands in for the state before a step in value.step (manaSpent = 0, or its price given,
-- reads only these): the tail to the horizon, a press in the buffer of the wait before it
local PRE = { target = {} }

-- Candidates are first evaluated on the model's scratch states (peekApply/peekWait, no
-- allocation); only the few that enter the beam get a real state again (materialize).
-- Both paths run the same model code on the same input, so the numbers are identical.
local function candidate(o, node, a, rootNow)
  local S, v = node.S, node.v
  local m = o.model
  local peekWait, peekApply = m.peekWait or m.wait, m.peekApply or m.apply
  if a.key == "waitSwing" then
    if node.waited or S.now + a.readyIn - rootNow >= o.horizon then return nil end
    local S1, d = peekWait(S, a.readyIn)
    local c = { parent = node, a = a, v = v + waitValue(o, S, S1, d), depth = node.depth,
                waited = true, afterSwing = true }
    return c, S1
  end
  local afterSwing = node.afterSwing
  local waited = false
  if a.readyIn > M.READY_EPS then
    if S.now + a.readyIn - rootNow >= o.horizon then return nil end
    local S1, d = peekWait(S, a.readyIn)
    v = v + waitValue(o, S, S1, d)
    S = S1
    afterSwing = false
    waited = true
  end
  local at = S.now - rootNow
  if at >= o.horizon or not fitsHorizon(o, S, a.key, at) then return nil end
  local c = { parent = node, a = a, depth = node.depth + 1, at = at,
              first = node.first or (node.virtual and (node.parent.first or a.key .. "+swing")) or a.key }
  c.afterSwingStep = afterSwing or nil
  if (waited or node.virtual) and m.peekWait then
    -- S is a scratch state: keep what the step text needs now, rebuild the rest on demand
    c.reason = M.reason(S, a.key, afterSwing)
  else
    c.pre = S
  end
  local val = o.value
  if waited and m.peekApplyOver and val.manaPrice then
    -- the waited state is read by nothing else: press in its own buffer (no second fill); what
    -- value.step reads of the state before the press is taken first
    local t = S.target
    PRE.mode, PRE.target.hp, PRE.target.hpMax, PRE.target.dead = S.mode, t.hp, t.hpMax, t.dead
    local mana0, price = S.player.mana or 0, val.manaPrice(S)
    local S2, dmg = m.peekApplyOver(S, a.key, o.horizon - at)
    c.v = v + val.step(PRE, S2, dmg, mana0 - (S2.player.mana or 0), price)
    return c, S2
  end
  local S2, dmg = peekApply(S, a.key, o.horizon - at)
  c.v = v + val.step(S, S2, dmg, (S.player.mana or 0) - (S2.player.mana or 0))
  return c, S2
end

-- the chain of steps up to c (built once, on demand)
function stepsOf(c)
  if c.steps then return c.steps end
  local parent = c.parent and stepsOf(c.parent) or {}
  if c.waited then
    c.steps = parent
  else
    local steps = {}
    for i, st in ipairs(parent) do steps[i] = st end
    steps[#steps + 1] = { key = c.a.key, at = c.at, reason = c.reason or M.reason(c.pre, c.a.key, c.afterSwingStep),
                          afterSwing = c.afterSwingStep }
    c.steps = steps
  end
  return c.steps
end

-- a real (allocated) state for a candidate that goes on to the next beam step
local function materialize(o, c)
  local parent = c.parent
  if c.waited then
    c.S = o.model.wait(parent.S, c.a.readyIn)
    return
  end
  local pre = c.pre
  if not pre then
    -- a "swing, then Bolt" child: its parent's state was a scratch one, rebuild it first
    local base = parent.virtual and o.model.wait(parent.parent.S, parent.a.readyIn) or parent.S
    pre = c.a.readyIn > M.READY_EPS and o.model.wait(base, c.a.readyIn) or base
  end
  c.S = o.model.apply(pre, c.a.key, o.horizon - c.at)
end

-- CS comes from a peek (a scratch state): pad it to the horizon in place
-- the candidate's state again, as a scratch state
local function peekState(o, c)
  local m, parent = o.model, c.parent
  if c.waited then return (m.peekWait(parent.S, c.a.readyIn)) end
  local pre = c.pre
  if not pre then
    if parent.virtual then
      pre = m.peekWait(parent.parent.S, parent.a.readyIn) -- weave children have no wait of their own
    elseif m.peekApplyOver then
      return (m.peekApplyOver(m.peekWait(parent.S, c.a.readyIn), c.a.key, o.horizon - c.at))
    else
      pre = m.peekWait(parent.S, c.a.readyIn)
    end
  end
  return (m.peekApply(pre, c.a.key, o.horizon - c.at))
end

local function scoreFrom(o, CS, v, rootNow)
  local t = CS.now - rootNow
  if t < o.horizon then
    if o.model.peekApply and o.model.advance then
      PRE.mode, PRE.target.hp, PRE.target.hpMax, PRE.target.dead = CS.mode, CS.target.hp, CS.target.hpMax, CS.target.dead
      local mana0 = CS.player.mana or 0
      local price = o.value.manaPrice and o.value.manaPrice(CS) or 0 -- before the state moves on
      local dmg = o.model.advance(CS, o.horizon - t)
      v = v + o.value.step(PRE, CS, dmg, 0) - (mana0 - (CS.player.mana or 0)) * price
    else
      local S2, dmg = o.model.wait(CS, o.horizon - t)
      v = v + waitValue(o, CS, S2, dmg)
      CS = S2
    end
  end
  return v + o.value.terminal(CS)
end

local fillIdle

-- The whole search as one function. It stops by the node cap only, never by the clock, so its
-- result is the same however it is cut into frames. check() (nil = run to the end) is called
-- only where no scratch state (model.peek*) is held, so other code may use the scratch buffers
-- while the search is paused.
local function run(o, S, check)
  S = root(S)
  local rootNow = S.now
  local rootNode = { S = S, v = 0, steps = {}, depth = 0 }
  local frontier = { rootNode }
  local best, bestNode = -math.huge, nil
  local bestByFirst = {} -- first button -> its best chain
  local nodes, capped = 0, false
  for _ = 1, o.depth * 2 do
    local children = {}
    local function add(node, a)
      local c, CS = candidate(o, node, a, rootNow)
      nodes = nodes + 1
      if nodes >= o.nodeCap then capped = true end
      if not c then return capped end
      c.score = scoreFrom(o, CS, c.v, rootNow)
      if (not c.waited or #stepsOf(node) > 0) and c.score > best then best, bestNode = c.score, c end
      local fb = bestByFirst[c.first]
      if not fb or c.score > fb.score then bestByFirst[c.first] = c end
      children[#children + 1] = c
      return capped
    end
    for _, node in ipairs(frontier) do
      if node.depth < o.depth then
        local acts = o.model.actions(node.S)
        for _, a in ipairs(acts) do
          if a.key == "waitSwing" then
            -- "swing, then Bolt" competes with "Bolt now" as one step; a bare wait would lose
            -- every beam cut to any button. The waited state is a scratch one (virtual node).
            local S0 = node.S
            if S0.now + a.readyIn - rootNow < o.horizon then
              local S1, d = (o.model.peekWait or o.model.wait)(S0, a.readyIn)
              local wn = { S = S1, v = node.v + waitValue(o, S0, S1, d), depth = node.depth,
                           waited = true, afterSwing = true, parent = node, a = a, virtual = true }
              for _, key in ipairs(M.WEAVE_KEYS) do
                -- an instant (5 stacks) clips nothing: waiting for the swing would only be a twin
                local r = o.model.readyIn(S1, key)
                local ct = o.model.castTime and o.model.castTime(S1, key)
                if r and r <= M.READY_EPS and ct ~= 0 and add(wn, { key = key, readyIn = r }) then break end
              end
            end
          elseif add(node, a) then
            break
          end
        end
      end
      if capped then break end
      if check then check() end
    end
    if capped then break end
    -- the last layer is only scored, never expanded: no beam cut needed
    local deeper = false
    for i = 1, #children do if children[i].depth < o.depth then deeper = true; break end end
    if not deeper then break end
    table.sort(children, function(x, y)
      if x.score ~= y.score then return x.score > y.score end
      return chainKey(x) < chainKey(y)
    end)
    -- best first; a state already in the beam (same signature) is skipped. Signatures are only
    -- needed for the few children looked at here, so they are taken from rebuilt states.
    frontier = {}
    local taken = {}
    local function take(c)
      if c.inBeam ~= nil then return c.inBeam end
      c.inBeam = false
      local sig
      if c.depth < o.depth or not o.model.peekApply then
        materialize(o, c)
        sig = M.signature(c.S)
      else
        sig = M.signature(peekState(o, c)) -- never expanded: no real state needed
      end
      if c.waited then sig = sig .. "w" end
      if taken[sig] then return false end
      taken[sig] = true
      frontier[#frontier + 1] = c
      c.inBeam = true
      return true
    end
    for i = 1, #children do
      if #frontier >= o.beam then break end
      take(children[i])
    end
    -- Diversity: the best chain of every first button stays too, if it is within DIVERSITY of the
    -- layer's best. Chains are compared after different numbers of seconds, so the cut is myopic:
    -- a first button whose chains all lost it once could never show that it leads to the best plan.
    local firsts = {}
    for i = 1, #frontier do local f = frontier[i].first; firsts[f] = (firsts[f] or 0) + 1 end
    local floor = children[1] and children[1].score - math.abs(children[1].score) * o.diversity
    for i = 1, #children do
      local c = children[i]
      if c.score < floor then break end
      local f = c.first
      if (firsts[f] or 0) < o.perFirst and take(c) then firsts[f] = (firsts[f] or 0) + 1 end
    end
    if #frontier == 0 then break end
    if check then check() end
  end
  -- byFirst: the best chain found for every first button ("key" or "key+swing"), so the planner
  -- can weigh a held first button by its best continuation, not by the old plan's stale tail
  local byFirst = {}
  local function result(value, steps)
    return { value = value, steps = steps, capped = capped, timedOut = capped, nodes = nodes, byFirst = byFirst }
  end
  for f, c in pairs(bestByFirst) do byFirst[f] = stepsOf(c) end
  if not bestNode then return result(0, {}) end
  -- The best chain of every first button close enough to the best gets its waits filled
  -- (fillIdle), then the best of them wins: a first button must not lose only because its chain
  -- was not filled. Bounded (one replay per gap and ready button), so it runs after a capped
  -- search too. Order: by score, ties by chain (deterministic).
  local list = {}
  for _, c in pairs(bestByFirst) do
    if c.score >= best - math.abs(best) * o.fillMargin then list[#list + 1] = c end
  end
  table.sort(list, function(x, y)
    if x.score ~= y.score then return x.score > y.score end
    return chainKey(x) < chainKey(y)
  end)
  local steps
  local top = -math.huge
  local budget = { replays = o.fillReplays }
  for _, c in ipairs(list) do
    local v, st = fillIdle(o, S, c.score, stepsOf(c), check, budget)
    byFirst[c.first] = st
    if v > top then top, steps = v, st end
  end
  best = top
  -- pressing nothing can be the best plan (solo: a mob the swings finish, mana is dear)
  local idle = finalScore(o, rootNode, rootNow)
  if idle >= best then return result(idle, {}) end
  return result(best, steps)
end

-- synchronous: the whole search at once (tests, tools); the same result as a job run in slices
function M.best(S, opts)
  return run(defaults(opts), S, nil)
end

-- A search to be run in slices of at most budgetMs per frame (in game: one slice per frame).
-- job:run(ms) -> true once finished, job.result is the plan. Lua 5.1 coroutines are allowed in
-- the WeakAuras sandbox; an error inside the search is raised again, as if called directly.
local Job = {}
Job.__index = Job

function M.start(S, opts)
  local o = defaults(opts)
  local job = setmetatable({ o = o, slices = 0, ms = 0 }, Job)
  local function check()
    if o.clock() >= job.deadline then coroutine.yield() end
  end
  job.co = coroutine.create(function() return run(o, S, check) end)
  return job
end

function Job:run(budgetMs)
  if self.result then return true end
  local clock = self.o.clock
  local t0 = clock()
  self.deadline = t0 + (budgetMs or self.o.budgetMs)
  self.slices = self.slices + 1
  local ok, res = coroutine.resume(self.co)
  self.ms = self.ms + (clock() - t0)
  if not ok then error(res, 0) end
  if coroutine.status(self.co) == "dead" then
    self.result = res
    return true
  end
  return false
end

-- Replay steps[i0..] from node. truncate: a step that is no longer possible ends the plan there
-- (else: nil, the plan is invalid). gapFrom: stop before the first step i >= gapFrom whose planned
-- wait is at least IDLE_MIN and return that node and i (fillIdle).
-- The replayed states are scratch ones (extend: peek), except with gapFrom: the node returned at
-- the gap is extended again and again. Without gapFrom only the last node's state is read
-- (finalScore, which does not keep it), and only the steps outlive the call.
local function replay(o, node, steps, i0, rootNow, truncate, gapFrom)
  local peek = not gapFrom
  for i = i0, #steps do
    local st = steps[i]
    local r = o.model.readyIn(node.S, st.key)
    if r == nil and st.afterSwing and o.model.swingIn then
      -- the search tries a weave on the state after the swing: the mana Shamanistic Rage returns
      -- with it can pay for a Bolt the state before cannot (a scratch state, read only here)
      local sw = o.model.swingIn(node.S)
      if sw and node.S.now + sw - rootNow < o.horizon then
        local r2 = o.model.readyIn((o.model.peekWait or o.model.wait)(node.S, sw), st.key)
        if r2 then r = sw + r2 end
      end
    end
    if r == nil then
      if not truncate then return nil end
      return node
    end
    -- the planned wait is kept exactly (a residual cooldown under READY_EPS counts as ready, as in
    -- the search); an "after swing" step waits for the swing even if it comes a little later
    local wait = st.at - (node.S.now - rootNow)
    if gapFrom and i >= gapFrom and wait >= M.IDLE_MIN then return node, i end
    if r > M.READY_EPS and r > wait then wait = r end
    -- a step planned at its ready time waits exactly that: "at" went through S.now - rootNow and
    -- can differ in the last bits, which moves a swing due at that very moment (a mob arriving
    -- into melee) to the other side of the press
    if r > M.READY_EPS and wait - r < 1e-9 then wait = r end
    if st.afterSwing then
      local sw = o.model.swingIn and o.model.swingIn(node.S)
      if sw and sw > wait and sw <= wait + M.SWING_SLACK then wait = sw end
    end
    local c = extend(o, node, { key = st.key, readyIn = wait }, rootNow, st.afterSwing, peek, true)
    if not c then return node end
    c.steps[#c.steps].reason = st.reason
    node = c
  end
  return node
end

local function evaluateFrom(o, S, steps, truncate)
  local rootNow = S.now
  local node = replay(o, { S = S, v = 0, steps = {}, depth = 0 }, steps, 1, rootNow, truncate)
  if not node or #node.steps == 0 then return nil end
  local v, horizonValue = finalScore(o, node, rootNow)
  return v, node.steps, horizonValue
end

-- the byFirst key of a plan's first step
function M.firstKey(st)
  return st.afterSwing and (st.key .. "+swing") or st.key
end

-- replay an existing plan on a fresh state; nil if a step is no longer possible
-- -> value, retimed steps, the part of the value earned inside the horizon (without terminal)
function M.evaluate(S, steps, opts)
  return evaluateFrom(defaults(opts), root(S), steps)
end

-- pressing nothing for the whole horizon -> value, the part earned inside the horizon
-- (the planner holds an empty plan against a new one with this, like evaluate for a plan)
function M.idle(S, opts)
  local o = defaults(opts)
  local r = root(S)
  return finalScore(o, { S = r, v = 0, steps = {}, depth = 0 }, r.now)
end

-- A replay presses every step at its planned time or later, so a wait of IDLE_MIN before
-- steps[i] needs one in the plan itself: none from steps[from] on, no replay needed.
local function planHasGap(steps, from)
  for i = from, #steps do
    local prev = i > 1 and steps[i - 1].at or 0
    if steps[i].at - prev >= M.IDLE_MIN - 1e-6 then return true end
  end
  return false
end

-- A wait of at least IDLE_MIN inside the plan (before its first step or between two steps): try
-- each button that is ready when the wait starts in it. The beam compares chains by the number
-- of buttons, so "the big ones later" can win the cut against "a small one in the gap, then the
-- big ones" although the second is the better plan. Bounded: one replay per gap and ready button.
function fillIdle(o, S, value, steps, check, budget)
  local rootNow = S.now
  -- the replay goes on from the last gap's (real, never changed) state: the steps before it stay
  local node, i = { S = S, v = 0, steps = {}, depth = 0 }, 1
  local from = 1
  while budget.replays > 0 and planHasGap(steps, from) do
    local gapNode, gapAt = replay(o, node, steps, i, rootNow, true, from)
    if not gapAt then break end
    node, i = gapNode, gapAt
    local ready = {}
    for _, a in ipairs(o.model.actions(gapNode.S)) do
      if a.key ~= "waitSwing" and a.readyIn <= M.READY_EPS and a.key ~= steps[gapAt].key then ready[#ready + 1] = a.key end
    end
    local bestV, bestSteps = value, nil
    for _, key in ipairs(ready) do
      if check then check() end
      if budget.replays <= 0 then break end
      budget.replays = budget.replays - 1
      -- the plan's own later press of the same button may no longer fit: the plan ends there
      -- a scratch state: only the replay right below reads it
      local c = extend(o, gapNode, { key = key, readyIn = 0 }, rootNow, false, true)
      if c then
        local node = replay(o, c, steps, gapAt, rootNow, true)
        local v = finalScore(o, node, rootNow)
        if v > bestV then bestV, bestSteps = v, node.steps end
      end
    end
    if bestSteps then value, steps = bestV, bestSteps end
    from = gapAt + 1
  end
  return value, steps
end

return M
