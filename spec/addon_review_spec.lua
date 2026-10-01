local G = require("game_mock")
local P = require("panel_mock")
local review = require("review")
local fightlog = require("fightlog")

local function rig(config)
  G.install(); P.install()
  local w = { t = 100, said = {}, db = {}, config = config or {}, rt = { S = nil, due = nil } }
  w.R = review.new({
    rt = function() return w.rt end, db = w.db, say = function(l) w.said[#w.said + 1] = l end,
    config = function() return w.config end, now = function() return w.t end,
    time = function() return 5 end, date = function() return "d" end,
  })
  return w
end

-- a fight of n matched presses, one a second, ending at 100 + seconds
local function fight(w, n, seconds)
  w.R:onEvent("PLAYER_REGEN_DISABLED")
  for i = 1, n do
    w.t = 100 + i
    w.R:press({ t = w.t, key = "stormstrike", sug = "stormstrike", due = w.t,
                last = { now = w.t, value = 60, firstValue = { stormstrike = 60 } } })
  end
  w.t = 100 + seconds
  w.R:onEvent("PLAYER_REGEN_ENABLED")
end

describe("addon fight review", function()
  -- a live engine state with a due button long past, the GCD idle
  local function idleState(w, now)
    w.rt.S = { now = now, gcdRemains = 0, castRemains = 0, buffs = { mw = { stacks = 0 } },
               target = { exists = true, enemy = true, range = "melee" } }
    w.rt.due = { key = "stormstrike", at = 0 }
  end

  it("no idle GCD samples from a sleeping or stopped engine", function()
    for _, flag in ipairs({ "sleeping", "stopped", "inactive" }) do
      local w = rig()
      w.R:onEvent("PLAYER_REGEN_DISABLED")
      for i = 1, 10 do w.R:press({ t = 100, key = "x", sug = "x", due = 100, last = { now = 100, firstValue = { x = 1 } } }) end
      idleState(w, 100)
      w.rt[flag] = true
      w.t = 105
      for _ = 1, 5 do w.R:onUpdate(0.5) end
      assert.are.equal(0, w.R.log.f.gcdIdle, flag)
    end
  end)

  it("no idle GCD samples from a state older than a second", function()
    local w = rig()
    w.R:onEvent("PLAYER_REGEN_DISABLED")
    idleState(w, 90)
    w.t = 105
    for _ = 1, 5 do w.R:onUpdate(0.5) end
    assert.are.equal(0, w.R.log.f.gcdIdle)
    idleState(w, 105) -- the same state, fresh: counted
    for _ = 1, 5 do w.R:onUpdate(0.5) end
    assert.is_true(w.R.log.f.gcdIdle > 0)
  end)

  it("after a fight: one line in chat and the fight in the session", function()
    local w = rig()
    fight(w, 12, 30)
    w.R:onUpdate(0.016) -- nothing to settle: reported on the next frame
    assert.are.equal(1, #w.said)
    assert.is_truthy(w.said[1]:find("100%% matched"))
    assert.are.equal(1, #w.R.history.session)
  end)

  it("no line with the summary turned off; the fight is kept", function()
    local w = rig({ fightSummary = false })
    fight(w, 12, 30)
    w.R:onUpdate(0.016)
    assert.are.equal(0, #w.said)
    assert.are.equal(1, #w.R.history.session)
  end)

  it("a short fight gives nothing", function()
    local w = rig()
    fight(w, 12, 10)
    w.R:onUpdate(0.016)
    assert.are.equal(0, #w.said)
  end)

  it("a new fight before the copies are valued: the old one is reported, the rest not rated", function()
    local w = rig()
    w.R:onEvent("PLAYER_REGEN_DISABLED")
    for i = 1, 12 do
      w.t = 100 + i
      w.R:press({ t = w.t, key = "frostShock", sug = "stormstrike", due = w.t,
                  last = { now = w.t, value = 60, firstValue = { stormstrike = 60 }, s = { now = w.t } } })
    end
    w.t = 130
    w.R:onEvent("PLAYER_REGEN_ENABLED")
    w.R:onEvent("PLAYER_REGEN_DISABLED") -- before any frame
    assert.are.equal(1, #w.R.history.session)
    assert.are.equal(12, w.R.history.session[1].fight.unrated)
    assert.is_true(w.R.log:active())
  end)

  it("Maelstrom in the combat log: only the player's own buff", function()
    local w = rig()
    local me = UnitGUID("player")
    w.R:onEvent("PLAYER_REGEN_DISABLED")
    w.R.log.f.mw.stacks = 5
    w.R:onEvent("COMBAT_LOG_EVENT_UNFILTERED", 0, "SPELL_AURA_REFRESH", me, "Me", 0, me, "Me", 0, fightlog.MW_ID, "Maelstrom Weapon", 8, "BUFF")
    w.R:onEvent("COMBAT_LOG_EVENT_UNFILTERED", 0, "SPELL_AURA_REFRESH", "x", "X", 0, "other", "Other", 0, fightlog.MW_ID, "Maelstrom Weapon", 8, "BUFF")
    assert.are.equal(1, w.R.log.f.mw.wasted)
  end)

  it("the window hides when a fight begins", function()
    local w = rig()
    w.R:open("last")
    assert.is_true(w.R.window.frame:IsShown())
    w.R:onEvent("PLAYER_REGEN_DISABLED")
    assert.is_false(w.R.window.frame:IsShown())
  end)

  it("with the message queue: waits its turn, the queue hides it in a fight, its skin once", function()
    local w = rig()
    local calm = false
    local q = require("guide").new({ fighting = function() return not calm end })
    local styled = {}
    w.R.deps.guide = function() return q end
    w.R.deps.skin = function(f) styled[#styled + 1] = f end
    w.R:open("history")
    assert.is_false(w.R.window.frame:IsShown())
    assert.truthy(w.said[#w.said]:find("fight review opens", 1, true))
    w.R:open("last") -- asked again while waiting: one turn, the page asked last
    assert.are.equal(1, #q.items)
    calm = true
    q:pump()
    assert.is_true(w.R.window.frame:IsShown())
    assert.are.equal("last", w.R.window.mode)
    calm = false
    q:combat()
    assert.is_false(w.R.window.frame:IsShown())
    w.R:onEvent("PLAYER_REGEN_DISABLED") -- the review leaves the hiding to the queue
    assert.are.equal(1, #q.items)
    calm = true
    q:pump()
    assert.is_true(w.R.window.frame:IsShown())
    w.R.window.frame:Hide()
    assert.is_nil(q.current)
    assert.are.same({ w.R.window.frame }, styled)
  end)

  it("difficulty: none outside instances, the client's name inside", function()
    G.install()
    _G.GetInstanceInfo = function() return "Azeroth", "none", 1, "", 5 end
    assert.are.equal("", review.difficulty())
    _G.GetInstanceInfo = function() return "Icecrown Citadel", "raid", 2, "25 Player", 25 end
    assert.are.equal("25 Player", review.difficulty())
  end)
end)

describe("addon fight review on recorded states #integration", function()
  local path = "spec/fixtures/recorded.lua"
  local f = io.open(path, "rb")
  if not f then return pending("no " .. path) end
  f:close()
  local search = require("search")
  local Sc = require("scenario")
  local advice = require("advice")

  it("a fight of real searches, wrong presses valued after it, gives tips", function()
    local list = dofile(path)
    local t = 0
    local F = fightlog.new({ now = function() return t end, state = function() return nil end, due = function() return nil end,
                             boss = function() return nil end, targetName = function() return "Mob" end,
                             difficulty = function() return nil end })
    F:begin()
    local n = 0
    for _, rec in ipairs(list) do
      local res = search.best(rec.S, Sc.OPTS)
      local first = res.steps[1] and res.steps[1].key
      if first then
        local other
        for k in pairs(rec.S.spells) do if k ~= first then other = k break end end
        t = t + 1
        F:press({ t = t, key = other or first, sug = first, due = t,
                  last = { now = t, value = res.value, firstValue = res.firstValue, s = rec.S } })
        n = n + 1
      end
    end
    assert.is_true(n >= fightlog.MIN_PRESSES)
    t = math.max(t, fightlog.MIN_SECONDS) + 1
    local fight = F:finish()
    local evaluate = function(s, steps) return (search.evaluate(s, steps, Sc.OPTS)) end
    while not fightlog.settle(fight, evaluate) do end
    assert.is_true(fight.lost >= 0)
    local tips = advice.tips(fight)
    assert.is_true(#tips >= 1)
    assert.is_truthy(advice.summary(fight, tips):find("/dmr last$"))
  end)
end)
