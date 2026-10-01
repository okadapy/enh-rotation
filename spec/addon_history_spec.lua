local history = require("history")

local function fight(over)
  local f = { name = "Marrowgar", key = "Marrowgar 25 Player", seconds = 100, rate = 0.9, delay = 0.2, lost = 1000 }
  for k, v in pairs(over or {}) do f[k] = v end
  return f
end
local TIPS = { { code = "wrong" }, { code = "delay" }, { code = "swings" }, { code = "gcd_idle" } }

local function rig()
  local w = { t = 1000, db = {} }
  w.H = history.new(w.db, function() return w.t end)
  return w
end

describe("addon fight history", function()
  it("exports the limits", function()
    assert.are.equal(10, history.SESSION_MAX)
    assert.are.equal(20, history.BOSS_FIGHTS)
    assert.are.equal(50, history.BOSS_MAX)
  end)

  it("keeps a short record: the first 3 tip codes, loss per second", function()
    assert.are.same({ date = 7, seconds = 100, rate = 0.9, delay = 0.2, lostPerSec = 10, tips = { "wrong", "delay", "swings" } },
      history.short(fight(), TIPS, 7))
  end)

  it("creates fights in old saved data and keeps the session newest first, at most 10", function()
    local w = rig()
    for i = 1, 12 do w.H:add(fight({ name = "M" .. i, key = nil, trash = true }), TIPS) end
    assert.are.equal(10, #w.H.session)
    assert.are.equal("M12", w.H.session[1].fight.name)
    assert.are.same({}, w.db.fights) -- trash: no boss history
  end)

  it("keeps 20 fights per boss, newest first", function()
    local w = rig()
    for i = 1, 22 do w.t = 1000 + i; w.H:add(fight({ seconds = i }), TIPS) end
    local list = w.H:boss("Marrowgar 25 Player")
    assert.are.equal(20, #list)
    assert.are.equal(22, list[1].seconds)
  end)

  it("drops the boss not fought for the longest past 50", function()
    local w = rig()
    for i = 1, 51 do w.t = 1000 + i; w.H:add(fight({ key = "Boss" .. i }), TIPS) end
    w.t = 2000
    w.H:add(fight({ key = "Boss1" }), TIPS) -- Boss1 fought again: Boss2 is the oldest
    w.t = 2001
    w.H:add(fight({ key = "Boss52" }), TIPS)
    assert.is_not_nil(w.db.fights.Boss1)
    assert.is_nil(w.db.fights.Boss2)
    local n = 0
    for _ in pairs(w.db.fights) do n = n + 1 end
    assert.are.equal(50, n)
  end)

  it("no trend with fewer than 2 fights before", function()
    local w = rig()
    assert.is_nil(w.H:add(fight(), TIPS).trend)
    assert.is_nil(w.H:add(fight(), TIPS).trend)
    assert.are.equal("same", w.H:add(fight(), TIPS).trend)
  end)

  it("trend against the mean of the last 5: better, worse, same", function()
    local prev = {}
    for i = 1, 7 do prev[i] = { rate = 0.8, lostPerSec = 10 } end
    prev[6], prev[7] = { rate = 0.1, lostPerSec = 100 }, { rate = 0.1, lostPerSec = 100 } -- older than 5: not counted
    assert.are.equal("better", history.trend(prev, { rate = 0.83, lostPerSec = 10 }))
    assert.are.equal("better", history.trend(prev, { rate = 0.8, lostPerSec = 9 }))
    assert.are.equal("worse", history.trend(prev, { rate = 0.77, lostPerSec = 10 }))
    assert.are.equal("worse", history.trend(prev, { rate = 0.8, lostPerSec = 11 }))
    assert.are.equal("same", history.trend(prev, { rate = 0.81, lostPerSec = 10.5 }))
    assert.are.equal("same", history.trend(prev, { rate = 0.9, lostPerSec = 20 })) -- mixed
  end)
end)
