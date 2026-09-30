local search = require("search")
local Sc = require("scenario")

local function ms() return os.clock() * 1000 end

-- In game a search runs BUDGET_MS per frame (search.start / job:run) and stops at NODE_CAP
-- candidates. The cap is chosen so that on realistic level-80 states a search takes about three
-- frames here (the container's speed); the numbers below are what "about" means.
describe("performance #integration #perf", function()
  local states = Sc.randomStates(150)

  it("a node-capped search on realistic level-80 states takes about 3 frames of BUDGET_MS", function()
    local frames, total, within3, worst = {}, 0, 0, 0
    for i, S in ipairs(states) do
      -- the faster of two runs: the search's own cost, without a garbage collection or the
      -- container's scheduler landing in one of them
      local job, n
      for _ = 1, 2 do
        local j = search.start(S, { clock = ms })
        local k = 1
        while not j:run(search.BUDGET_MS) do k = k + 1 end
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
    print("\nperf: " .. info)
    assert.is_true(avg <= 3 * search.BUDGET_MS, info)
    assert.is_true(within3 >= 0.8 * #states, info)
    assert.is_true(worst <= 5, info)
  end)

  it("run in real 2 ms slices, a search gives exactly the plan of the whole search", function()
    for i = 1, 40 do
      local S = states[i]
      local job = search.start(S, { clock = ms })
      while not job:run(search.BUDGET_MS) do end
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
