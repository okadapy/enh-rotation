local planner = require("planner")
local fixtures = require("fixtures")

local FRAME = 0.05

local function quiet()
  return fixtures.state({
    swing = { attacking = false },
    target = { fs = 8 },
    buffs = { mw = { stacks = 2, remains = 20 } },
  })
end

local function replay(frames, onFrame)
  local p = planner.new({ searchOpts = { budgetMs = 1e9 } })
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

describe("stability #integration", function()
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
