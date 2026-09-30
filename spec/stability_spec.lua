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
