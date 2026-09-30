local M = {}

M.HORIZON = 6.0
M.BEAM = 6
M.DEPTH = 4
M.BUDGET_MS = 2
M.READY_EPS = 0.05

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

function M.signature(S)
  local hpStep = math.max(1, (S.target.hpMax or 1) * 0.005)
  local parts = {
    q(S.now), math.floor((S.player.mana or 0) / 50),
    q(S.buffs.mw and S.buffs.mw.stacks), q(S.target.fs), math.floor((S.target.hp or 0) / hpStep),
    q(S.target.ss and S.target.ss.charges), q(S.gcdRemains), q(S.castRemains),
  }
  -- swing timers and the fire totem decide what the next seconds bring, keep them apart
  local sw = S.swing
  if sw then
    parts[#parts + 1] = (sw.attacking and "a" or "-") .. q(sw.mh and sw.mh.next) .. "/" .. q(sw.oh and sw.oh.next)
  end
  local fire = S.totems and S.totems.fire
  if fire then parts[#parts + 1] = tostring(fire.kind or "none") .. q(fire.remains) end
  local keys = {}
  for k in pairs(S.spells) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. q(S.spells[k].cd) end
  return table.concat(parts, ":")
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

-- pad the chain with waiting up to the horizon, then add what the end state is still worth
local function finalScore(o, node, rootNow)
  local S, v = node.S, node.v
  local t = S.now - rootNow
  if t < o.horizon then
    local S2, dmg = o.model.wait(S, o.horizon - t)
    v = v + o.value.step(S, S2, dmg, 0)
    S = S2
  end
  return v + o.value.terminal(S)
end

local function extend(o, node, a, rootNow)
  local S, v = node.S, node.v
  if a.key == "waitSwing" then
    if node.waited or S.now + a.readyIn - rootNow >= o.horizon then return nil end
    local S1, d = o.model.wait(S, a.readyIn)
    return { S = S1, v = v + o.value.step(S, S1, d, 0), steps = node.steps, depth = node.depth,
             waited = true, afterSwing = true }
  end
  local afterSwing = node.afterSwing
  if a.readyIn > M.READY_EPS then
    if S.now + a.readyIn - rootNow >= o.horizon then return nil end
    local S1, d = o.model.wait(S, a.readyIn)
    v = v + o.value.step(S, S1, d, 0)
    S = S1
    afterSwing = false
  end
  local at = S.now - rootNow
  if at >= o.horizon then return nil end
  local S2, dmg = o.model.apply(S, a.key)
  v = v + o.value.step(S, S2, dmg, (S.player.mana or 0) - (S2.player.mana or 0))
  local steps = {}
  for i, s in ipairs(node.steps) do steps[i] = s end
  steps[#steps + 1] = { key = a.key, at = at, reason = M.reason(S, a.key, afterSwing) }
  return { S = S2, v = v, steps = steps, depth = node.depth + 1 }
end

local function chainKey(node)
  local parts = {}
  for i, s in ipairs(node.steps) do parts[i] = s.key .. "@" .. q(s.at) end
  return table.concat(parts, ",") .. (node.waited and "+w" or "")
end

function M.best(S, opts)
  local o = defaults(opts)
  local start = o.clock()
  local rootNow = S.now
  local frontier = { { S = S, v = 0, steps = {}, depth = 0 } }
  local best = { value = -math.huge, steps = {} }
  local timedOut = false
  for _ = 1, o.depth * 2 do
    local seen, order = {}, {}
    for _, node in ipairs(frontier) do
      if node.depth < o.depth then
        for _, a in ipairs(o.model.actions(node.S)) do
          local c = extend(o, node, a, rootNow)
          if c then
            c.score = finalScore(o, c, rootNow)
            if #c.steps > 0 and c.score > best.value then best = { value = c.score, steps = c.steps } end
            local sig = M.signature(c.S) .. (c.waited and "w" or "")
            local prev = seen[sig]
            if not prev then order[#order + 1] = sig end
            if not prev or c.score > prev.score then seen[sig] = c end
            if o.clock() - start > o.budgetMs then timedOut = true; break end
          end
        end
      end
      if timedOut then break end
    end
    if timedOut then break end
    local children = {}
    for i, sig in ipairs(order) do children[i] = seen[sig] end
    table.sort(children, function(x, y)
      if x.score ~= y.score then return x.score > y.score end
      return chainKey(x) < chainKey(y)
    end)
    frontier = {}
    for i = 1, math.min(o.beam, #children) do frontier[i] = children[i] end
    if #frontier == 0 then break end
  end
  if best.value == -math.huge then return { value = 0, steps = {}, timedOut = timedOut } end
  return { value = best.value, steps = best.steps, timedOut = timedOut }
end

-- replay an existing plan on a fresh state; nil if a step is no longer possible
function M.evaluate(S, steps, opts)
  local o = defaults(opts)
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

return M
