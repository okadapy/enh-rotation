local G = require("game_mock")
local Sc = require("scenario")
local planner = require("planner")
local search = require("search")
local explain = require("explain")

local function steps(...)
  local out = {}
  for i, k in ipairs({ ... }) do out[i] = { key = k, at = (i - 1) * 1.5, reason = k .. " because" } end
  return out
end

-- a planner stand-in: alts planned at altsNow, prepare marks the state it was given
local function view(planSteps, alts, altsNow)
  local S = { now = 100 }
  local p = { alts = alts, altsNow = altsNow or 100 }
  function p:prepare(s) return { now = s.now, prepared = true } end
  return { plan = { steps = planSteps }, S = S, at = 100, planner = p }
end

-- value by the chain's first key; nil: the chain cannot be played
local function evaluator(values, seen)
  return function(S, st)
    assert.is_true(S.prepared, "evaluated on the planner's state")
    if seen then seen[#seen + 1] = st end
    local v = values[st[1].key]
    if v == nil then return nil end
    return v, st, 200
  end
end
local firstKey = search.firstKey

describe("explain: the runner-up", function()
  it("the best other first button, its loss and its share of the plan's 6 s", function()
    local v = view(steps("stormstrike", "lavaLash"),
      { stormstrike = steps("stormstrike"), earthShock = steps("earthShock"), lavaLash = steps("lavaLash") })
    local r = explain.rivals(v, evaluator({ stormstrike = 1000, earthShock = 950, lavaLash = 900 }), firstKey)
    assert.are.equal(1000, r.value)
    assert.are.equal("earthShock", r.second.key)
    assert.are.equal(50, r.second.loss)
    assert.are.near(25, r.second.pct, 1e-9) -- 50 of the 200 the plan does inside the horizon
  end)

  it("the alternatives are moved on by the time since their search", function()
    local seen = {}
    local v = view(steps("stormstrike"), { earthShock = { { key = "earthShock", at = 1.0 } } }, 99.6)
    explain.rivals(v, evaluator({ stormstrike = 1, earthShock = 1 }, seen), firstKey)
    assert.are.near(0.6, seen[2][1].at, 1e-9)
  end)

  it("a chain that can no longer be played is skipped; none left: no runner-up", function()
    local v = view(steps("stormstrike"), { earthShock = steps("earthShock") })
    local r = explain.rivals(v, evaluator({ stormstrike = 1000 }), firstKey)
    assert.are.equal(1000, r.value)
    assert.is_nil(r.second)
  end)

  it("no plan, no state or no planner: nothing", function()
    assert.is_nil(explain.rivals({ plan = { steps = {} } }, evaluator({}), firstKey))
    assert.is_nil(explain.rivals({ plan = { steps = steps("stormstrike") } }, evaluator({}), firstKey))
  end)

  -- the shown plan is the search's best after fillIdle; the runner-up's chain may not have been
  -- filled, so "not better" is not asserted to the last bit: only that it is a real alternative
  it("on a real level-80 state the runner-up is another first button, with numbers #integration", function()
    G.install({})
    local S = Sc.state(80)
    local p = planner.new()
    p:update(S)
    local plan = p:view(S.now)
    local r = explain.rivals({ plan = plan, S = S, planner = p })
    assert.is_truthy(r.second)
    assert.are_not.equal(search.firstKey(plan.steps[1]), r.second.key .. (r.second.afterSwing and "+swing" or ""))
    assert.is_number(r.second.loss)
    assert.is_number(r.second.pct)
  end)

  it("is quick enough to run once a second while the tooltip is open #perf", function()
    G.install({})
    local factor = tonumber(os.getenv("ENHROT_PERF_FACTOR") or "") or 1
    local total, n = 0, 0
    for _, S in ipairs(Sc.randomStates(30)) do
      local p = planner.new()
      p:update(S)
      local v = { plan = p:view(S.now), S = S, planner = p }
      if v.plan.steps[1] then
        local t0 = os.clock()
        explain.rivals(v)
        total, n = total + (os.clock() - t0) * 1000, n + 1
      end
    end
    assert.is_true(total / n <= 3 * factor, ("%.2f ms"):format(total / n))
  end)
end)

describe("explain: the tooltip text", function()
  it("name and key, press now, why, then, runner-up", function()
    local v = view(steps("stormstrike", "lavaLash", "earthShock"))
    local r = { value = 1000, horizon = 200, second = { key = "earthShock", value = 986, loss = 14, pct = 7 } }
    local L = explain.lines(v, 0, "S-E", r)
    local text = {}
    for i, l in ipairs(L) do text[i] = l[1] end
    assert.are.same({ "Stormstrike [S-E]", "Press now", "Why: stormstrike because", "Then: Lava Lash, Earth Shock",
                      "Runner-up: Earth Shock - 7% worse over the next 6 s" }, text)
  end)

  it("a button due later says when; a close runner-up is about as good; no key, no brackets", function()
    local v = view({ { key = "lightningBolt", at = 1.6, reason = "5 Maelstrom: instant" } })
    local L = explain.lines(v, 0.4, nil, { value = 1, horizon = 1, second = { key = "lavaLash", value = 1, loss = 0.001, pct = 0.4 } })
    assert.are.equal("Lightning Bolt", L[1][1])
    assert.are.equal("Press in 1.2 s", L[2][1])
    assert.are.equal("Runner-up: Lava Lash - about as good", L[#L][1])
  end)

  it("no runner-up: says so; nothing to press: no tooltip", function()
    local L = explain.lines(view(steps("stormstrike")), 0, nil, { value = 1, horizon = 1 })
    assert.are.equal("No other first button comes close", L[#L][1])
    assert.is_nil(explain.lines(view({}), 0, nil, nil))
  end)
end)

describe("explain: on mouse-over", function()
  local tip, mouse, combat, shift, now
  local function tooltip()
    local t = { lines = {}, shown = false }
    function t:SetOwner(o, a) self.owner, self.anchor, self.lines, self.shown = o, a, {}, false end
    function t:SetText(s) self.lines = { s } end
    function t:AddLine(s) self.lines[#self.lines + 1] = s end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    function t:IsOwned(o) return self.owner == o end
    return t
  end
  local function driver(enabled)
    G.install({})
    tip, mouse, combat, shift, now = tooltip(), true, false, false, 100
    local v = view(steps("stormstrike"))
    v.frame, v.icon, v.active = CreateFrame("Frame"), G.texture(), true
    local e = explain.new({
      view = function() return v end, enabled = function() return enabled ~= false end,
      hotkey = function() return "3" end, now = function() return now end,
      inCombat = function() return combat end, shift = function() return shift end,
      tooltip = tip, over = function() return mouse end,
      evaluate = evaluator({ stormstrike = 10 }), firstKey = firstKey,
    })
    return e, v
  end

  it("out of combat the hover shows the tooltip; leaving hides it", function()
    local e = driver()
    e:tick(0.2)
    assert.is_true(tip.shown)
    assert.are.equal("Stormstrike [3]", tip.lines[1])
    assert.are.equal(e.hover, tip.owner)
    mouse = false
    e:tick(0.2)
    assert.is_false(tip.shown)
  end)

  it("in combat only with Shift held", function()
    local e = driver()
    combat = true
    e:tick(0.2)
    assert.is_false(tip.shown)
    shift = true
    e:tick(0.2)
    assert.is_true(tip.shown)
  end)

  it("the hover area never takes the mouse: clicks go through the timeline", function()
    local e = driver()
    e:tick(0.2)
    assert.is_falsy(e.hover.mouse)
  end)

  it("someone else's tooltip is not hidden", function()
    local e = driver()
    mouse = false
    tip:SetOwner("another frame")
    tip:Show()
    e:tick(0.2)
    assert.is_true(tip.shown)
  end)

  it("the option off: no tooltip", function()
    local e = driver(false)
    e:tick(0.2)
    assert.is_false(tip.shown)
  end)

  it("the runner-up is worked out again once a second while open, not every poll", function()
    local e, v = driver()
    local calls = 0
    e.deps.evaluate = function(...) calls = calls + 1; return 10, {}, 10 end
    e:tick(0.2)
    local first = calls
    now = now + 0.5
    e:tick(0.2)
    assert.are.equal(first, calls)
    now = now + 0.6
    e:tick(0.2)
    assert.is_true(calls > first)
  end)
end)
