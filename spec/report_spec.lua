local report = require("report")
local fixtures = require("fixtures")
local util = require("util")

local RECORDED = "spec/fixtures/recorded.lua"

-- a snapshot record as the recorder writes it: { S, plan[, pressed] }
local function rec(patch, steps, pressed)
  return { S = fixtures.state(patch), plan = { steps = steps or {}, trigger = { kind = "pulse" } }, pressed = pressed }
end

local function libs() return { serialize = require("LibSerialize"), deflate = require("LibDeflate") } end

local function tmpWrite(text)
  local path = os.tmpname()
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
  return path
end

describe("report: the recorded snapshots #integration", function()
  local list = dofile(RECORDED)
  local R = report.analyze(list)
  local text = report.format(R)

  it("has one row per snapshot with the game plan and the current suggestion", function()
    assert.are.equal(#list, #R.rows)
    for i, r in ipairs(R.rows) do
      assert.are.equal(i, r.i)
      assert.is_true(type(r.nowFirst) == "string" and type(r.shownFirst) == "string")
      assert.are.equal(report.stepsText(list[i].plan), r.shown)
    end
    assert.are.equal(0, R.rows[1].time)
  end)

  it("lists every snapshot whose first button differs as a disagreement", function()
    local n = 0
    for _, r in ipairs(R.rows) do if r.shownFirst ~= r.nowFirst then n = n + 1 end end
    assert.are.equal(n, #R.disagree)
  end)

  it("runs the noisy time-to-die check on every dying mob", function()
    local dying = 0
    for _, x in ipairs(list) do
      local t = x.S.target
      if t.exists and t.enemy and t.ttd and t.ttd < report.DYING_TTD then dying = dying + 1 end
    end
    assert.is_true(dying >= 5)
    assert.are.equal(dying, R.stability.runs)
    assert.is_true(R.stability.changes * 5 <= R.stability.runs, report.format(R))
  end)

  it("prints all sections and says when the presses are missing", function()
    for _, h in ipairs({ "1. Disagreements", "2. Stability", "3. Alerts", "4. Mana by mob", "5. Presses: no `pressed`" }) do
      assert.is_truthy(text:find(h, 1, true), h)
    end
    assert.is_nil(text:find("6. Against the baseline", 1, true))
  end)

  it("reads the fixture file by path", function()
    assert.are.equal(#list, #report.load(RECORDED))
  end)

  it("a baseline of its own suggestions differs nowhere", function()
    local path = tmpWrite(report.suggestionsFixture(R))
    local base = report.suggestionsOf(dofile(path))
    os.remove(path)
    local again = report.analyze(list, { baseline = base })
    assert.are.same({}, again.diff)
    assert.is_truthy(report.format(again):find("6. Against the baseline: 0", 1, true))
  end)
end)

describe("report: handcrafted snapshots", function()
  it("flags melee without auto-attack, low mana and a far target", function()
    local list = {
      rec({ now = 100, swing = { attacking = false }, target = { range = "melee" } }),
      rec({ now = 102, player = { mana = 100, manaMax = 1000 } }),
      rec({ now = 104, target = { range = "far" } }),
    }
    local R = report.analyze(list)
    assert.are.same({ "melee-no-autoattack" }, R.rows[1].flags)
    assert.are.equal("autoAttack", R.rows[1].alert)
    assert.are.same({ "low-mana" }, R.rows[2].flags)
    assert.are.same({ "far" }, R.rows[3].flags)
    assert.are.equal("outOfRange", R.rows[3].alert)
    assert.are.equal(3, #R.alerts)
    assert.are.near(4, R.rows[3].time, 1e-9)
  end)

  it("sums the mana of one mob, split into the pull and melee", function()
    local function at(now, hp, mana, range, hpMax)
      return rec({ now = now, player = { mana = mana, manaMax = 5000 },
                   target = { hp = hp, hpMax = hpMax or 1000, range = range } })
    end
    local list = {
      at(0, 1000, 5000, "30"),
      at(2, 1000, 4600, "20"),   -- pull: 400
      at(4, 800, 4300, "melee"), -- pull: 300 (range at the start of the gap)
      at(6, 500, 4100, "melee"), -- melee: 200
      at(8, 900, 4000, "melee", 2000), -- another mob: not counted
      at(9, 700, 4000, "melee", 2000),
    }
    local mobs, total = report.mana(list, 0)
    assert.are.equal(2, #mobs)
    assert.are.equal(1, mobs[1].from)
    assert.are.equal(4, mobs[1].last)
    assert.are.equal(700, mobs[1].pull)
    assert.are.equal(200, mobs[1].melee)
    assert.are.equal(6, mobs[1].seconds)
    assert.are.same({ pull = 700, melee = 200 }, total)
  end)

  it("reports the presses: match rate, median reaction and the top mismatches", function()
    local ll = { { key = "lavaLash", at = 0 } }
    local ss = { { key = "stormstrike", at = 0 } }
    local list = {
      rec({ now = 0 }, ll, { key = "lavaLash", after = 0.4, matched = true }),
      rec({ now = 2 }, ll, { key = "earthShock", after = 0.8, matched = false }),
      rec({ now = 4 }, ll, { key = "earthShock", after = 0.6, matched = false }),
      rec({ now = 6 }, ss, { key = "lavaLash", after = 1.2, matched = false }),
      rec({ now = 8 }, ss), -- no press after this one
    }
    local p = report.presses(list)
    assert.are.equal(4, p.count)
    assert.are.equal(1, p.matched)
    assert.are.near(0.25, p.rate, 1e-9)
    assert.are.near(0.7, p.medianAfter, 1e-9)
    assert.are.same({ { pair = "lavaLash -> earthShock", count = 2 }, { pair = "stormstrike -> lavaLash", count = 1 } }, p.top)
    local text = report.format(report.analyze(list))
    assert.is_truthy(text:find("5. Presses: 1/4 matched (25%), median reaction 0.70 s", 1, true), text)
    assert.is_truthy(text:find("pressed earthShock +0.80s MISS", 1, true), text)
  end)

  it("has no press section without the field", function()
    assert.is_nil(report.presses({ rec({ now = 0 }) }))
  end)

  it("the stability check is deterministic for a seed", function()
    local s = fixtures.state({ target = { ttd = 5 } })
    local model, planner = require("model"), require("planner")
    local c1, seq1, seed1 = report.stability(s, 1, planner, model, util)
    local c2, seq2, seed2 = report.stability(s, 1, planner, model, util)
    assert.are.equal(c1, c2)
    assert.are.equal(seq1, seq2)
    assert.are.equal(seed1, seed2)
    assert.are_not.equal(1, seed1)
  end)

  it("diffs the current suggestions against a baseline of plans or of saved suggestions", function()
    local list = { rec({ now = 0 }), rec({ now = 2 }) }
    local R = report.analyze(list)
    local base = report.suggestionsOf({ { first = "nothing", steps = "nothing@0.0" }, { first = R.rows[2].nowFirst } })
    local d = report.analyze(list, { baseline = base }).diff
    assert.are.equal(1, #d)
    assert.are.equal(1, d[1].i)
    assert.are.equal("nothing", d[1].before)
    local fromPlans = report.suggestionsOf({ { plan = { steps = { { key = "lavaLash", at = 0.5 } } } } })
    assert.are.same({ { first = "lavaLash", steps = "lavaLash@0.5" } }, fromPlans)
  end)

  it("reads the export string of version 1 and of version 2 (with the press log)", function()
    local list = { rec({ now = 0 }) }
    local v1 = require("recorder").export(list, libs())
    local got = report.decodeAny(v1)
    assert.are.equal(1, #got)

    local L = libs()
    local body = { version = "0.2.0", snapshots = list, presses = { { t = 1, key = "lavaLash", sug = "lavaLash", hit = true, delay = 0.3, cf = true },
                                                                    { t = 3, key = "earthShock", sug = "lavaLash", hit = false, delay = 0.5 } } }
    local v2 = "!ENHROT:2!" .. L.deflate:EncodeForPrint(L.deflate:CompressDeflate(
      L.serialize:SerializeEx({ errorOnUnserializableType = false }, body), { level = 1 }))
    local path = tmpWrite(v2)
    local snaps, presses, version = report.load(path)
    os.remove(path)
    assert.are.equal(1, #snaps)
    assert.are.equal(2, #presses)
    assert.are.equal("0.2.0", version)
    local R = report.analyze(snaps, { presses = presses, version = version })
    assert.are.same({ count = 2, hit = 1, confirmed = 1, medianDelay = 0.4 }, R.pressLog)
    assert.is_truthy(report.format(R):find("press log: 2 presses, 1 hit the suggestion, 1 confirmed, median delay 0.40 s", 1, true))
  end)
end)
