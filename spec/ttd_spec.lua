local ttd = require("ttd")

local function feed(t, guid, start, samples)
  for i, hp in ipairs(samples) do
    t:add(start + (i - 1), guid, hp)
  end
end

describe("ttd", function()
  it("unknown guid gives nil", function()
    assert.is_nil(ttd.new():estimate(100, "0xA"))
  end)

  it("needs at least 3 samples", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9 })
    assert.is_nil(t:estimate(101, "0xA"))
  end)

  it("needs at least 1.5 s of span", function()
    local t = ttd.new()
    t:add(100.0, "0xA", 1.0)
    t:add(100.5, "0xA", 0.95)
    t:add(101.0, "0xA", 0.9)
    assert.is_nil(t:estimate(101.0, "0xA"))
  end)

  it("linear decline of 10%/s at 80% gives 8 s", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9, 0.8 })
    assert.are.near(8, t:estimate(102, "0xA"), 1e-6)
  end)

  it("accounts for time passed since the last sample", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9, 0.8 })
    assert.are.near(7, t:estimate(103, "0xA"), 1e-6)
  end)

  it("never returns negative", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 0.3, 0.2, 0.1 })
    assert.are.equal(0, t:estimate(150, "0xA"))
  end)

  it("flat or rising health gives nil", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 0.5, 0.5, 0.5 })
    assert.is_nil(t:estimate(102, "0xA"))
    local r = ttd.new()
    feed(r, "0xB", 100, { 0.50, 0.52, 0.54 })
    assert.is_nil(r:estimate(102, "0xB"))
  end)

  it("heal-up above 5% resets the samples", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9, 0.8 })
    t:add(103, "0xA", 1.0)
    assert.is_nil(t:estimate(103, "0xA"))
  end)

  it("drops samples older than the window", function()
    local t = ttd.new()
    -- fast early drop, then slow: only the last 10 s matter
    t:add(100, "0xA", 1.0)
    t:add(101, "0xA", 0.5)
    for i = 0, 4 do t:add(112 + i, "0xA", 0.5 - 0.01 * i) end
    -- slope -0.01/s over 112..116, hp 0.46 -> 46 s
    assert.are.near(46, t:estimate(116, "0xA"), 1e-6)
  end)

  it("keeps separate estimates per guid", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9, 0.8 })
    feed(t, "0xB", 100, { 1.0, 0.8, 0.6 })
    assert.are.near(8, t:estimate(102, "0xA"), 1e-6)
    assert.are.near(3, t:estimate(102, "0xB"), 1e-6)
  end)

  it("reset forgets one guid or all", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9, 0.8 })
    feed(t, "0xB", 100, { 1.0, 0.9, 0.8 })
    t:reset("0xA")
    assert.is_nil(t:estimate(102, "0xA"))
    assert.is_not_nil(t:estimate(102, "0xB"))
    t:reset()
    assert.is_nil(t:estimate(102, "0xB"))
  end)

  it("forgets guids not seen for 30 s", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9, 0.8 })
    t:add(140, "0xB", 1.0)
    assert.is_nil(t.units["0xA"])
  end)

  it("ignores nil guid or hp", function()
    local t = ttd.new()
    t:add(100, nil, 0.5)
    t:add(100, "0xA", nil)
    assert.is_nil(t:estimate(100, "0xA"))
  end)
end)

describe("ttd smoothed", function()
  it("is the raw estimate at first and runs down with the clock when the rate holds", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9, 0.8 })
    assert.are.near(8, t:smoothed(102, "0xA"), 1e-6)
    assert.are.near(7, t:smoothed(103, "0xA"), 1e-6) -- no new sample: raw and prediction agree
  end)

  -- health in whole percent, hits every 0.5-1 s: the raw regression jumps, the smoothed one far less
  it("damps the jumps of the raw estimate", function()
    local t = ttd.new()
    local hp, now = 1.0, 100
    local rawJump, smJump, lastRaw, lastSm = 0, 0, nil, nil
    local hits = { 0.07, 0, 0.02, 0.09, 0, 0, 0.08, 0.01, 0.06, 0, 0.1, 0.03, 0, 0.07, 0.05, 0 }
    for _, h in ipairs(hits) do
      hp = hp - h
      t:add(now, "0xA", hp)
      local raw, sm = t:estimate(now, "0xA"), t:smoothed(now, "0xA")
      if raw and lastRaw then
        rawJump = math.max(rawJump, math.abs(raw - (lastRaw - 0.5)))
        smJump = math.max(smJump, math.abs(sm - (lastSm - 0.5)))
      end
      lastRaw, lastSm = raw, sm
      now = now + 0.5
    end
    assert.is_true(smJump < rawJump / 2, ("raw %.2f, smoothed %.2f"):format(rawJump, smJump))
  end)

  it("keeps a long estimate long (a boss) and starts afresh after a heal", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 0.5, 0.499, 0.498 })
    assert.is_true(t:smoothed(102, "0xA") > 400)
    t:add(103, "0xA", 1.0) -- healed: the samples start again
    assert.is_nil(t:smoothed(103, "0xA"))
    feed(t, "0xA", 104, { 0.9, 0.8, 0.7 })
    assert.are.near(7, t:smoothed(106, "0xA"), 1e-6)
  end)
end)

describe("ttd with a prior", function()
  it("nil prior: the same numbers as without one", function()
    local a, b = ttd.new(), ttd.new()
    local hp = 1.0
    for i, h in ipairs({ 0.07, 0, 0.02, 0.09, 0, 0, 0.08, 0.01, 0.06, 0, 0.1 }) do
      hp = hp - h
      local now = 100 + 0.5 * i
      a:add(now, "0xA", hp); b:add(now, "0xA", hp)
      assert.are.equal(a:estimate(now, "0xA"), b:estimate(now, "0xA", nil))
      assert.are.equal(a:smoothed(now, "0xA"), b:smoothed(now, "0xA", nil))
    end
  end)

  it("before the regression has enough data it is the prior, not unknown", function()
    local t = ttd.new()
    t:add(100, "0xA", 0.9)
    local v, src = t:smoothed(100, "0xA", 9)
    assert.are.equal(9, v)
    assert.are.equal("prior", src)
    t:add(100.5, "0xA", 0.85)
    t:add(101, "0xA", 0.8) -- 3 samples but 1 s of span: still the prior
    assert.are.equal("prior", select(2, t:estimate(101, "0xA", 8)))
    assert.are.near(8, t:estimate(101, "0xA", 8), 1e-9)
  end)

  -- recorded: a mob at 88% said 128 s (whole-percent steps, a swing or two in the samples); it
  -- was at 45% 2.8 s later. The young regression must not outweigh the expected kill rate.
  it("a young regression that sees almost no decline is pulled to the prior", function()
    local t = ttd.new()
    -- 3 s, 2% down: the regression alone says ~135 s (a leading 0.89, 0.89 would be the time
    -- before the damage, not a sample of it: see "the seconds before the health first fell")
    feed(t, "0xA", 100, { 0.90, 0.89, 0.89, 0.88 })
    assert.is_true(t:estimate(103, "0xA") > 100)
    local v, src = t:smoothed(103, "0xA", 7)
    assert.are.equal("blend", src)
    assert.is_true(v < 12, ("%.1f"):format(v))
  end)

  it("the regression wins as data accumulates", function()
    -- the mob loses 5%/s; the prior thinks twice as fast
    local function share(seconds)
      local t = ttd.new()
      local n = seconds * 4
      for i = 0, n do t:add(100 + i * 0.25, "0xA", 1 - 0.05 * i * 0.25) end
      local now = 100 + seconds
      local hp = 1 - 0.05 * seconds
      local truth, prior = hp / 0.05, hp / 0.1
      local v = t:estimate(now, "0xA", prior)
      local rate = 1 / v
      return (rate - 1 / prior) / (1 / truth - 1 / prior) -- 0: the prior, 1: the regression
    end
    local s2, s5, s10 = share(2), share(5), share(10)
    assert.is_true(s2 > 0 and s2 < 0.5, ("%.2f"):format(s2))
    assert.is_true(s5 > s2 and s10 > s5, ("%.2f %.2f %.2f"):format(s2, s5, s10))
    assert.is_true(s10 > 0.7, ("%.2f"):format(s10))
  end)

  it("a flat regression (nothing is killing the mob) lengthens the prior", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 0.8, 0.8, 0.8, 0.8, 0.8 })
    assert.is_nil(t:estimate(104, "0xA"))
    local v = t:estimate(104, "0xA", 10)
    assert.is_true(v > 15, ("%.1f"):format(v))
  end)

  it("a prior of zero or a dead mob gives zero", function()
    local t = ttd.new()
    t:add(100, "0xA", 0.5)
    assert.are.equal(0, t:estimate(100, "0xA", 0))
    t:add(101, "0xA", 0)
    assert.are.equal(0, t:estimate(101, "0xA", 5))
  end)

  it("smoothing runs across the switch from prior to blend", function()
    local t = ttd.new()
    local hp, now = 1.0, 100
    local last
    for i = 1, 12 do
      t:add(now, "0xA", hp)
      local v = t:smoothed(now, "0xA", hp / 0.1) -- the prior agrees with the real 10%/s
      assert.are.near(hp / 0.1, v, 1.0)
      if last then assert.is_true(v < last) end
      last = v
      hp, now = hp - 0.05, now + 0.5
    end
  end)

  -- report 2026-10-02 (shaman 60, solo): the samples start when the mob is targeted, a sample a
  -- step; 5 s at full health while it was pulled, then ~10.6%/s. The line through the bend read
  -- 57% as 14.6 s (dead 5.8 s later) and 46% as 9.3 s (~6 s).
  local function pulled(flat, upTo, prior)
    local t = ttd.new()
    local now, hp, hpMax, dps = 100, 3989, 3989, 425
    local v
    while true do
      if now >= 100 + flat then hp = hp - dps * 0.1 end
      local pct = math.ceil(hp / hpMax * 100) / 100 -- whole percent
      t:add(now, "0xA", pct)
      local fighting = now >= 100 + flat - 0.5
      v = t:smoothed(now, "0xA", prior and fighting and hp / dps or nil)
      if pct <= upTo then return v, hp / dps, t, now end
      now = now + 0.1
    end
  end

  it("the seconds before the health first fell do not slow the estimate", function()
    for _, at in ipairs({ 0.57, 0.46, 0.3 }) do
      local v, truth = pulled(5, at, true)
      assert.is_true(math.abs(v - truth) < 0.15 * truth, ("%d%%: %.2f against %.2f"):format(at * 100, v, truth))
    end
  end)

  it("without a prior the regression is the same as if it had started at the first hit", function()
    local _, _, a, now = pulled(5, 0.6)
    local _, _, b = pulled(0, 0.6)
    assert.are.near(b:estimate(now - 5, "0xA"), a:estimate(now, "0xA"), 0.25)
  end)
end)
