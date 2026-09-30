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
