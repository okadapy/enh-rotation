-- Регресс по снимкам, записанным в игре (опция record + tools/build.lua import-snapshots).
-- Поле expect в фикстуре дописывается руками, когда в игре замечено неправильное действие;
-- рядом комментарием — почему правильное именно такое.
local path = "spec/fixtures/recorded.lua"

describe("recorded snapshots #integration", function()
  local f = io.open(path, "rb")
  if not f then
    pending("no " .. path .. " yet — record in game and run tools/build.lua import-snapshots")
    return
  end
  f:close()
  local search = require("search")
  local runtime = require("runtime")
  local Sc = require("scenario")
  for i, rec in ipairs(dofile(path)) do
    it("snapshot #" .. i .. " gives a valid plan of known spells", function()
      local plan = search.best(rec.S, Sc.OPTS)
      assert.is_true(runtime.validPlan(plan))
      for _, st in ipairs(plan.steps) do
        assert.is_true(rec.S.spells[st.key] ~= nil or st.key == "waitSwing" or st.key == "wait", st.key)
      end
      if rec.expect then assert.are.equal(rec.expect, plan.steps[1] and plan.steps[1].key) end
    end)
  end
end)
