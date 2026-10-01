-- Регресс по снимкам, записанным в игре (опция record + tools/build.lua import-snapshots).
-- Поле expect в фикстуре дописывается руками: правильная первая кнопка, рядом комментарием —
-- почему именно она. Значения:
--   expect = "lavaLash"                    — первая кнопка плана;
--   expect = "-"                           — план пустой (ничего не нажимать);
--   expect = { "stormstrike", "lavaLash" } — любая из равноценных кнопок.
-- pending = "<причина>" — текущий код с ожиданием не согласен (известная ошибка): снимок не
-- проверяется, а печатается, что ждём и что выходит. Когда код исправят, pending убрать.
local path = "spec/fixtures/recorded.lua"

local function firstKey(plan)
  local st = plan.steps[1]
  return st and st.key or "-"
end

local function accepts(expect, key)
  if type(expect) ~= "table" then return expect == key end
  for _, k in ipairs(expect) do
    if k == key then return true end
  end
  return false
end

local function show(expect)
  if type(expect) ~= "table" then return expect end
  return table.concat(expect, " | ")
end

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
      if not rec.expect then return end
      local got = firstKey(plan)
      if rec.pending then
        print(("recorded #%d pending: expect %s, got %s%s — %s"):format(i, show(rec.expect), got,
          accepts(rec.expect, got) and " (passes now: drop pending)" or "", rec.pending))
        return
      end
      assert.is_true(accepts(rec.expect, got), ("snapshot #%d: expected %s, got %s"):format(i, show(rec.expect), got))
    end)
    if rec.expect and rec.pending then
      pending("snapshot #" .. i .. " expects " .. show(rec.expect) .. ": " .. rec.pending)
    end
  end
end)

-- The solo mana option (value.MANA_POLICY): a dearer price never plans more mana, a cheaper one
-- never less (the mana of the plan's buttons, every recorded snapshot)
describe("recorded snapshots: the solo mana option #integration", function()
  local f = io.open(path, "rb")
  if not f then return end
  f:close()
  local search, util = require("search"), require("util")
  local Sc = require("scenario")
  it("save <= balanced (nil) <= spend in the mana planned", function()
    local total, lines = { save = 0, balanced = 0, spend = 0 }, {}
    for i, rec in ipairs(dofile(path)) do
      local cost = {}
      for _, pol in ipairs({ "save", "balanced", "spend" }) do
        local S = util.copy(rec.S)
        S.manaPolicy = pol ~= "balanced" and pol or nil
        local c = 0
        for _, st in ipairs(search.best(S, Sc.OPTS).steps) do
          local sp = S.spells[st.key]
          c = c + (sp and sp.cost or 0)
        end
        cost[pol] = c
        total[pol] = total[pol] + c
      end
      if cost.save > cost.balanced or cost.balanced > cost.spend then
        lines[#lines + 1] = ("#%d %d / %d / %d"):format(i, cost.save, cost.balanced, cost.spend)
      end
    end
    assert.are.equal(0, #lines, table.concat(lines, "\n"))
    assert.is_true(total.save < total.balanced and total.balanced < total.spend,
      ("%d / %d / %d"):format(total.save, total.balanced, total.spend))
  end)
end)
