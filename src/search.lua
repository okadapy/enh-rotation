local M = {}

M.HORIZON = 6.0
M.BEAM = 6
M.DEPTH = 4
M.BUDGET_MS = 2
M.READY_EPS = 0.05
M.WEAVE = { lightningBolt = true, chainLightning = true } -- what waiting for a swing is for
M.NOW_SLOTS = 3 -- beam places kept for "press now" children
M.IDLE_MIN = 1.0 -- a plan whose first button waits this long gets a button tried in front of it

M.REASONS = {
  stormstrike = "Stormstrike: +20% nature",
  lavaLash = "filler",
  earthShock = "shock filler",
  frostShock = "shock filler",
  searingTotem = "no fire totem",
  fireElemental = "big cooldown",
  feralSpirit = "big cooldown",
  callOfElements = "totems expiring",
  lightningShield = "Lightning Shield missing",
}

local function q(x) return math.floor((x or 0) * 4 + 0.5) end

local FIRE_CODE = { searing = 1, magma = 2, fireElemental = 3, other = 4 }

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
    bytes[10 + i] = v
  end
  local hpStep = (t.hpMax or 1) * 0.005
  if hpStep < 1 then hpStep = 1 end
  local n = 10 + #keys
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

function M.reason(S, key, afterSwing)
  local mw = (S.buffs and S.buffs.mw and S.buffs.mw.stacks) or 0
  if key == "lightningBolt" or key == "chainLightning" then
    if mw >= 5 then return "5 Maelstrom stacks" end
    if afterSwing then return "after swing - no clip" end
    return ("%d Maelstrom stacks"):format(math.floor(mw))
  elseif key == "flameShock" then
    return (S.target.fs or 0) <= 0 and "Flame Shock expired" or "refresh Flame Shock"
  elseif key == "fireNova" or key == "magmaTotem" then
    local n = (S.enemies and S.enemies.nearby) or 1
    if n >= 2 then return ("%d targets"):format(n) end
    return key == "fireNova" and "Fire Nova ready" or "Magma Totem down"
  elseif key == "shamanisticRage" then
    local p = S.player
    return (p.manaMax and p.mana / p.manaMax < 0.3) and "low mana" or "damage cooldown"
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
  return v + o.value.terminal(S)
end

local function extend(o, node, a, rootNow)
  local S, v = node.S, node.v
  if a.key == "waitSwing" then
    if node.waited or S.now + a.readyIn - rootNow >= o.horizon then return nil end
    local S1, d = o.model.wait(S, a.readyIn)
    return { S = S1, v = v + waitValue(o, S, S1, d), steps = node.steps, depth = node.depth,
             waited = true, afterSwing = true }
  end
  local afterSwing = node.afterSwing
  if a.readyIn > M.READY_EPS then
    if S.now + a.readyIn - rootNow >= o.horizon then return nil end
    local S1, d = o.model.wait(S, a.readyIn)
    v = v + waitValue(o, S, S1, d)
    S = S1
    afterSwing = false
  end
  local at = S.now - rootNow
  if at >= o.horizon or not fitsHorizon(o, S, a.key, at) then return nil end
  local S2, dmg = o.model.apply(S, a.key, o.horizon - at)
  v = v + o.value.step(S, S2, dmg, (S.player.mana or 0) - (S2.player.mana or 0))
  local steps = {}
  for i, s in ipairs(node.steps) do steps[i] = s end
  steps[#steps + 1] = { key = a.key, at = at, reason = M.reason(S, a.key, afterSwing) }
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
  local c = { parent = node, a = a, depth = node.depth + 1, at = at }
  if waited and m.peekWait then
    -- S is a scratch state: keep what the step text needs now, rebuild the rest on demand
    c.reason = M.reason(S, a.key, afterSwing)
  else
    c.pre, c.reasonAfterSwing = S, afterSwing
  end
  local S2, dmg = peekApply(S, a.key, o.horizon - at)
  c.v = v + o.value.step(S, S2, dmg, (S.player.mana or 0) - (S2.player.mana or 0))
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
    steps[#steps + 1] = { key = c.a.key, at = c.at, reason = c.reason or M.reason(c.pre, c.a.key, c.reasonAfterSwing) }
    c.steps = steps
  end
  return c.steps
end

-- a real (allocated) state for a candidate that goes on to the next beam step
local function materialize(o, c)
  if c.waited then
    c.S = o.model.wait(c.parent.S, c.a.readyIn)
  else
    local pre = c.pre
    if not pre then pre = o.model.wait(c.parent.S, c.a.readyIn) end
    c.S = o.model.apply(pre, c.a.key, o.horizon - c.at)
  end
end

-- stands in for the state before the tail in value.step (manaSpent = 0 reads only these)
local PRE = { target = {} }

-- CS comes from a peek (a scratch state): pad it to the horizon in place
-- the candidate's state again, as a scratch state
local function peekState(o, c)
  local m = o.model
  if c.waited then return (m.peekWait(c.parent.S, c.a.readyIn)) end
  local pre = c.pre or m.peekWait(c.parent.S, c.a.readyIn)
  return (m.peekApply(pre, c.a.key, o.horizon - c.at))
end

local function scoreFrom(o, CS, v, rootNow)
  local t = CS.now - rootNow
  if t < o.horizon then
    if o.model.peekApply and o.model.advance then
      PRE.mode, PRE.target.hp, PRE.target.hpMax = CS.mode, CS.target.hp, CS.target.hpMax
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

local fillIdleStart

function M.best(S, opts)
  local o = defaults(opts)
  local start = o.clock()
  S = root(S)
  local rootNow = S.now
  local rootNode = { S = S, v = 0, steps = {}, depth = 0 }
  local rootActions = {}
  local frontier = { rootNode }
  local best, bestNode = -math.huge, nil
  local timedOut = false
  for _ = 1, o.depth * 2 do
    local children = {}
    local function add(node, a)
      local c, CS = candidate(o, node, a, rootNow)
      if not c then return false end
      c.score = scoreFrom(o, CS, c.v, rootNow)
      if (not c.waited or #stepsOf(node) > 0) and c.score > best then best, bestNode = c.score, c end
      children[#children + 1] = c
      if o.clock() - start > o.budgetMs then timedOut = true end
      return timedOut
    end
    for _, node in ipairs(frontier) do
      if node.depth < o.depth then
        local acts = o.model.actions(node.S)
        if node == rootNode then rootActions = acts end
        for _, a in ipairs(acts) do
          if a.key == "waitSwing" and node == rootNode then
            -- the first step decides what is shown: "swing, then Bolt" competes with "Bolt now" as
            -- one step; as a bare wait it would lose the first beam cut to any button
            local S0 = node.S
            if S0.now + a.readyIn - rootNow < o.horizon then
              local S1, d = o.model.wait(S0, a.readyIn)
              local wn = { S = S1, v = node.v + waitValue(o, S0, S1, d), steps = node.steps, depth = node.depth,
                           waited = true, afterSwing = true, parent = node, a = a }
              for _, b in ipairs(o.model.actions(S1)) do
                if M.WEAVE[b.key] and add(wn, b) then break end
              end
            end
          end
          if not timedOut and add(node, a) then break end
        end
      end
      if timedOut then break end
    end
    if timedOut then break end
    table.sort(children, function(x, y)
      if x.score ~= y.score then return x.score > y.score end
      return chainKey(x) < chainKey(y)
    end)
    -- best first; a state already in the beam (same signature) is skipped. Signatures are only
    -- needed for the few children looked at here, so they are taken from rebuilt states.
    -- At most beam - NOW_SLOTS places go to children that first wait: "button now, the big one
    -- later" must not lose the cut to a row of "wait, then the big one" (every 1-step chain idles
    -- to the horizon, so pressing a small button now looks worse than it is).
    frontier = {}
    local taken = {}
    local later, maxLater = 0, o.beam - math.min(o.beam, M.NOW_SLOTS)
    local skipped = {}
    local function take(c)
      local sig
      if c.depth < o.depth or not o.model.peekApply then
        materialize(o, c)
        sig = M.signature(c.S)
      else
        sig = M.signature(peekState(o, c)) -- never expanded: no real state needed
      end
      if c.waited then sig = sig .. "w" end
      if taken[sig] then return end
      taken[sig] = true
      frontier[#frontier + 1] = c
    end
    for i = 1, #children do
      if #frontier >= o.beam then break end
      local c = children[i]
      local waits = c.waited or c.a.readyIn > M.READY_EPS
      if waits and later >= maxLater then
        skipped[#skipped + 1] = c
      else
        local n = #frontier
        take(c)
        if waits and #frontier > n then later = later + 1 end
      end
    end
    -- not enough buttons to press now: the waiting ones fill the rest
    for i = 1, #skipped do
      if #frontier >= o.beam then break end
      take(skipped[i])
    end
    if #frontier == 0 then break end
  end
  if not bestNode then return { value = 0, steps = {}, timedOut = timedOut } end
  local steps = stepsOf(bestNode)
  if not timedOut then best, steps = fillIdleStart(o, S, best, steps, rootActions) end
  -- pressing nothing can be the best plan (solo: a mob the swings finish, mana is dear)
  local idle = finalScore(o, rootNode, rootNow)
  if idle >= best then return { value = idle, steps = {}, timedOut = timedOut } end
  return { value = best, steps = steps, timedOut = timedOut }
end

local function evaluateFrom(o, S, steps)
  local rootNow = S.now
  local node = { S = S, v = 0, steps = {}, depth = 0 }
  for _, st in ipairs(steps) do
    local r = o.model.readyIn(node.S, st.key)
    if r == nil then return nil end
    local planned = st.at - (node.S.now - rootNow)
    local c = extend(o, node, { key = st.key, readyIn = math.max(r, planned) }, rootNow)
    if not c then break end
    c.steps[#c.steps].reason = st.reason
    node = c
  end
  if #node.steps == 0 then return nil end
  return finalScore(o, node, rootNow), node.steps
end

-- replay an existing plan on a fresh state; nil if a step is no longer possible
function M.evaluate(S, steps, opts)
  return evaluateFrom(defaults(opts), root(S), steps)
end

-- The plan starts with a wait of at least a GCD: try each button that can be pressed now in
-- front of it (the beam compares chains by button count and may have cut "small button now").
function fillIdleStart(o, S, value, steps, actions)
  local first = steps[1]
  if not first or first.at < M.IDLE_MIN then return value, steps end
  for _, a in ipairs(actions) do
    if a.key ~= "waitSwing" and a.readyIn <= M.READY_EPS and a.key ~= first.key then
      local tryList = { { key = a.key, at = 0, reason = M.reason(S, a.key, false) } }
      for i, st in ipairs(steps) do tryList[i + 1] = st end
      local v, st = evaluateFrom(o, S, tryList)
      if v and v > value and st[1].key == a.key then value, steps = v, st end
    end
  end
  return value, steps
end

return M
