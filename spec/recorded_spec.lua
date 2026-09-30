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
