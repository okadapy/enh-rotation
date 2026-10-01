local planner = require("planner")
local fixtures = require("fixtures")
local F = require("fight")

-- Closed loop (spec/support/fight.lua): a level-80 raid boss for 60 s, auto-attack on, random but
-- seeded Maelstrom procs, cast START / SUCCEEDED, pulse 0.25 s, 0.1 s throttle and the real
-- per-frame search budget. A bot presses the big icon when it says "now".
describe("stability in a simulated fight #integration", function()
  local SEEDS = { 7919, 15838, 23757, 31676 }
  local total = { minutes = 0, quiet = 0, late = 0, mismatch = 0, searches = 0, frames = 0, presses = 0, changes = 0 }
  for _, seed in ipairs(SEEDS) do
    local r = F.run({ seed = seed, seconds = 60, budgetMs = 2 })
    total.minutes = total.minutes + r.seconds / 60
    for _, k in ipairs({ "quiet", "late", "mismatch", "searches", "presses", "changes" }) do total[k] = total[k] + r[k] end
    total.frames = total.frames + r.frameSum
  end
  local info = ("per minute: %.1f changes, %.1f quiet, %.1f late, %.1f presses; %.2f frames per search, %d/%d searches differ from the whole search")
    :format(total.changes / total.minutes, total.quiet / total.minutes, total.late / total.minutes, total.presses / total.minutes,
            total.frames / total.searches, total.mismatch, total.searches)
  print("\nstability: " .. info)

  it("the first button never changes without an event", function()
    assert.are.equal(0, total.quiet, info)
  end)

  -- issue #9: the held first button used to be weighed by the old plan's stale tail and lost to
  -- every new search right after a press (15.8 changes a minute)
  it("the first button changes at most 8 times a minute besides the presses", function()
    assert.is_true(total.changes <= 8 * total.minutes, info)
  end)

  it("the first button changes at most once a minute within 0.3 s before its press", function()
    assert.is_true(total.late <= total.minutes, info)
  end)

  it("what is shown is exactly the whole search's result, whatever the per-frame budget cut", function()
    assert.is_true(total.searches > 100, info)
    assert.are.equal(0, total.mismatch, info)
  end)

  it("the bot keeps pressing (the plan is not stuck)", function()
    assert.is_true(total.presses / total.minutes >= 30, info)
  end)
end)

-- Extra case: no auto-attack, no swings - nothing happens but time
local FRAME = 0.05

local function quiet()
  return fixtures.state({
    swing = { attacking = false },
    target = { fs = 8 },
    buffs = { mw = { stacks = 2, remains = 20 } },
  })
end

local function replay(frames, onFrame)
  local p = planner.new({})
  local S = quiet()
  local firsts = {}
  for i = 1, frames do
    local ev = { kind = "pulse" }
    if onFrame then S, ev = onFrame(i, S, ev) end
    local plan = p:update(S, ev)
    firsts[i] = plan.steps[1] and plan.steps[1].key or "-"
    S = require("model").wait(S, FRAME)
  end
  return firsts
end

local function changes(firsts, from, to)
  local n = 0
  for i = from + 1, to do if firsts[i] ~= firsts[i - 1] then n = n + 1 end end
  return n
end

describe("stability without auto-attack #integration", function()
  it("the first step does not change over 3 seconds without events", function()
    local firsts = replay(60)
    assert.are_not.equal("-", firsts[1])
    assert.are.equal(0, changes(firsts, 1, 60), table.concat(firsts, " "))
  end)

  it("a Maelstrom proc changes the first step at most once, and only after the proc", function()
    local firsts = replay(60, function(i, S, ev)
      if i == 20 then
        local n = require("util").copy(S)
        n.buffs.mw = { stacks = 5, remains = 30 }
        return n, { kind = "aura" }
      end
      return S, ev
    end)
    assert.are.equal(0, changes(firsts, 1, 19), table.concat(firsts, " "))
    assert.is_true(changes(firsts, 19, 60) <= 1, table.concat(firsts, " "))
  end)
end)

-- Issue #9 (level 52, solo, normal mobs): near a mob's death the big icon came and went. The
-- time-to-die estimate is noisy in game; with it the first button must not flip. States: the
-- recorded snapshots whose target dies within 10 s, 3 s of events without presses, time-to-die
-- off by up to ±20% on every event (a fixed LCG, not math.random: the same on every platform).
describe("stability near a mob's death with a noisy time-to-die #integration", function()
  local model, util = require("model"), require("util")
  local path = "spec/fixtures/recorded.lua"

  it("the first button changes at most once per 5 dying mobs", function()
    local seed = 12345
    local function rnd()
      seed = (seed * 1103515245 + 12345) % 2147483648
      return seed / 2147483648
    end
    local runs, changes, stale, lines = 0, 0, 0, {}
    for i, rec in ipairs(dofile(path)) do
      local t = rec.S.target
      if t.exists and t.enemy and t.ttd and t.ttd < 10 then
        local p, S, last, seq = planner.new({}), util.copy(rec.S), nil, {}
        for k = 1, 12 do
          local dead = S.target.dead -- by model time: from here an empty plan is right, not a flip
          local s = util.copy(S)
          s.target.ttd = S.target.ttd * (1 + 0.2 * (2 * rnd() - 1))
          local ev = k == 1 and { kind = "target" } or { kind = k % 2 == 0 and "swing" or "aura" }
          local plan = p:update(s, ev)
          local f = plan.steps[1] and plan.steps[1].key or "-"
          if dead then
            -- no stale button that needs the (dead) target; a buff like Lightning Shield may stay
            if model.NEEDS_TARGET[f] then stale = stale + 1 end
          elseif last and f ~= last then
            changes = changes + 1
          end
          last, seq[k] = f, (dead and "+" or "") .. f
          S = model.wait(S, 0.25)
        end
        runs = runs + 1
        lines[#lines + 1] = ("#%d %s"):format(i, table.concat(seq, " "))
      end
    end
    assert.is_true(runs >= 5, "recorded dying mobs: " .. runs)
    assert.is_true(changes * 5 <= runs, ("%d changes in %d runs\n%s"):format(changes, runs, table.concat(lines, "\n")))
    assert.are.equal(0, stale, "a button for the dead target stayed (+ = after death)\n" .. table.concat(lines, "\n"))
  end)
end)

-- Review, round 4: recorded #8 and #9 (a mob near its death in melee, Earth Shock ready) with the
-- health (and time to die) scaled 0.5-2.0: a press planned or not changed back and forth
-- (#8: nothing, LB, ES, nothing, ES), the finisher icon came and went as the health fell. The
-- kill was at the hit that took the last point: the seconds a press saved jumped with the health.
describe("a finisher as a dying mob's health falls #integration", function()
  local search, util = require("search"), require("util")
  local recorded = dofile("spec/fixtures/recorded.lua")
  for _, i in ipairs({ 8, 9 }) do
    it("#" .. i .. ": planned or not changes at most once each way along 0.5-2.0x the health", function()
      local S0 = recorded[i].S
      local seq, ups, downs, last = {}, 0, 0, nil
      for k = 0, 30 do
        local f = 0.5 + 0.05 * k
        local S = util.copy(S0)
        S.target.hp = S0.target.hp * f
        S.target.ttd = S0.target.ttd * f
        local plan = search.best(S)
        local first = plan.steps[1] and plan.steps[1].key or "-"
        local pressed = first ~= "-"
        if last ~= nil and pressed ~= last then
          if pressed then ups = ups + 1 else downs = downs + 1 end
        end
        last = pressed
        seq[#seq + 1] = ("%.2f:%s"):format(f, first)
      end
      local info = table.concat(seq, " ")
      assert.is_true(ups <= 1 and downs <= 1, info)
    end)
  end
end)

-- Review of the cooldown gate: a trash mob whose noisy time to die hovers around Feral Spirit's
-- 22.5 s line, only Feral Spirit and Stormstrike ready. Deciding the gate per model state flipped
-- the first button feralSpirit <-> stormstrike on every update (the gate made the held plan
-- unplayable, so the planner's margin never applied). Now the snapshot decides it once, latched
-- per target (snapshot.cooldownGate).
describe("stability of the long cooldowns' gate with a noisy time to die #integration", function()
  local Sc, model, util, snapshot = require("scenario"), require("model"), require("util"), require("snapshot")
  local NOISY = { 24, 21, 23, 22, 25, 21, 24, 22, 23, 21, 25, 22, 24, 21, 23, 22 }

  local function trash()
    local S = Sc.state(80, { mode = "group" })
    S.target.isBoss, S.target.level = false, 80
    S.target.hpMax, S.target.hp, S.target.hpPct = 200000, 100000, 0.5
    for _, sp in pairs(S.spells) do sp.cd = 10 end
    Sc.cd(S, { feralSpirit = 0, stormstrike = 0 })
    S.target.fs = 15
    S.totems.fire = { kind = "magma", remains = 30 }
    S.cooldowns = { feralSpirit = "auto", fireElemental = "auto", shamanisticRage = "always" }
    return S
  end

  -- ttds: one per update; guid(i): the target's GUID then
  local function run(ttds, guid)
    local p, S, ctx, firsts = planner.new({}), trash(), {}, {}
    for i, ttd in ipairs(ttds) do
      local s = util.copy(S)
      s.target.ttd = ttd
      s.cdAllowed = snapshot.cooldownGate(ctx, s, guid and guid(i) or "Creature-1")
      local plan = p:update(s, { kind = i == 1 and "target" or (i % 2 == 0 and "swing" or "aura") })
      firsts[i] = plan.steps[1] and plan.steps[1].key or "-"
      S = model.wait(S, 0.1)
    end
    return firsts
  end

  it("the first button changes at most once", function()
    local firsts = run(NOISY)
    assert.are.equal("feralSpirit", firsts[1], table.concat(firsts, " "))
    assert.is_true(changes(firsts, 1, #firsts) <= 1, table.concat(firsts, " "))
  end)

  it("the latch is released below 75% of the line: then Stormstrike", function()
    local ttds = { 24, 21, 23, 22 }
    for _ = 1, 6 do ttds[#ttds + 1] = 16 end -- < 22.5 x 0.75
    local firsts = run(ttds)
    assert.are.equal("feralSpirit", firsts[4], table.concat(firsts, " "))
    assert.are.equal("stormstrike", firsts[#firsts], table.concat(firsts, " "))
    assert.are.equal(1, changes(firsts, 1, #firsts), table.concat(firsts, " "))
  end)

  it("a new target starts without the latch", function()
    local ttds = { 24, 23, 22, 21, 21, 21, 21, 21 }
    local firsts = run(ttds, function(i) return i <= 4 and "Creature-1" or "Creature-2" end)
    assert.are.equal("feralSpirit", firsts[4], table.concat(firsts, " "))
    assert.are.equal("stormstrike", firsts[#firsts], table.concat(firsts, " "))
  end)
end)
