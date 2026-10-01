local search = require("search")
local Sc = require("scenario")

local function ms() return os.clock() * 1000 end

-- A slower machine (a shared CI runner) sets ENHROT_PERF_FACTOR: every time limit is that many
-- times longer and the frames are that many times BUDGET_MS, so the frame counts keep their
-- limits. CI runs with 2: noise on a shared runner passes, a search twice as slow fails.
local FACTOR = tonumber(os.getenv("ENHROT_PERF_FACTOR") or "") or 1
local BUDGET = search.BUDGET_MS * FACTOR

-- In game a search runs BUDGET_MS per frame (search.start / job:run) and stops at NODE_CAP
-- candidates. The cap is chosen so that on realistic level-80 states a search takes about three
-- frames here (the container's speed); the numbers below are what "about" means.
describe("performance #integration #perf", function()
  local states = Sc.randomStates(150)

  it("a node-capped search on realistic level-80 states takes about 3 frames of BUDGET_MS #timing", function()
    local frames, total, within3, worst = {}, 0, 0, 0
    for i, S in ipairs(states) do
      -- the faster of two runs: the search's own cost, without a garbage collection or the
      -- container's scheduler landing in one of them
      local job, n
      for _ = 1, 2 do
        local j = search.start(S, { clock = ms })
        local k = 1
        while not j:run(BUDGET) do k = k + 1 end
        if not job or j.ms < job.ms then job, n = j, k end
      end
      frames[i] = n
      total = total + job.ms
      if n <= 3 then within3 = within3 + 1 end
      if n > worst then worst = n end
      assert.is_true(job.result.nodes <= search.NODE_CAP)
    end
    local avg = total / #states
    local info = ("average %.2f ms, %d/%d states in <= 3 frames, worst %d frames"):format(avg, within3, #states, worst)
    if FACTOR ~= 1 then info = info .. (" (limits x%g)"):format(FACTOR) end
    print("\nperf: " .. info)
    assert.is_true(avg <= 3 * BUDGET, info)
    assert.is_true(within3 >= 0.8 * #states, info)
    assert.is_true(worst <= 5, info)
  end)

  -- Garbage does not depend on the machine's speed: the model's states, spell entries and player
  -- tables of a search come from an arena and go back when it ends (model.newArena / release).
  -- Before the arena a search left about 600 KB; now about 175 KB (candidates, steps, the memo).
  it("a search leaves little garbage", function()
    for i = 1, 5 do search.best(states[i]) end -- the free lists are filled once
    collectgarbage("collect")
    collectgarbage("stop")
    local kb0 = collectgarbage("count")
    for _, S in ipairs(states) do search.best(S) end
    local kb = (collectgarbage("count") - kb0) / #states
    collectgarbage("restart")
    local info = ("%.0f KB per search"):format(kb)
    print("\nperf: " .. info)
    assert.is_true(kb <= 300, info)
  end)

  -- The same work on any machine: Lua VM instructions per search (a count hook every 1000). A
  -- change that makes the search do twice the work fails here even where the clock is too noisy
  -- to tell (CI). Now about 480 thousand; allocation and garbage collection are not counted.
  it("the work of a search, in Lua instructions, stays under its limit", function()
    local n = 0
    debug.sethook(function() n = n + 1 end, "", 1000)
    for _, S in ipairs(states) do search.best(S) end
    debug.sethook()
    local k = n / #states
    local info = ("%.0f thousand Lua instructions per search"):format(k)
    print("\nperf: " .. info)
    assert.is_true(k <= 600, info)
  end)

  it("run in real 2 ms slices, a search gives exactly the plan of the whole search", function()
    for i = 1, 40 do
      local S = states[i]
      local job = search.start(S, { clock = ms })
      while not job:run(BUDGET) do end
      local whole = search.best(S)
      assert.are.equal(whole.value, job.result.value, "state " .. i)
      assert.are.equal(#whole.steps, #job.result.steps, "state " .. i)
      for k, st in ipairs(whole.steps) do
        assert.are.equal(st.key, job.result.steps[k].key, "state " .. i)
        assert.are.equal(st.at, job.result.steps[k].at, "state " .. i)
      end
    end
  end)
end)
