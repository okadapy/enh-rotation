local swing = require("swing")

-- Две руки по 2.6 с, атака начата в 100. После двух ударов:
-- mh due = 105.2, oh due = 105.4.
local function dual()
  local c = swing.new()
  c:onSpeed(100, 2.6, 2.6)
  c:onAttack(100, true)
  assert.are.equal("mh", c:onSwing(102.6, false))
  assert.are.equal("oh", c:onSwing(102.8, false))
  return c
end

-- Двуручник 3.6 с, один удар в 103.6 -> due = 107.2.
local function twoHand(saved)
  local c = swing.new(saved)
  c:onSpeed(100, 3.6, nil)
  c:onAttack(100, true)
  assert.are.equal("mh", c:onSwing(103.6, false))
  return c
end

-- Мгновенное заклинание за 1.3 с до ожидаемого удара, затем удар:
-- "reset" — удар пришёл через полную скорость после заклинания, "keep" — по старому отсчёту.
local function instantThenSwing(c, key, arrive)
  local s = c:state(0)
  local due = s.mh.next -- state(0) -> next = абсолютный due
  local t = due - 1.3
  c:onInstant(t, key)
  local at = arrive == "reset" and (t + 3.6) or due
  c:onSwing(at, false)
  return at
end

describe("swing", function()
  describe("speed and state", function()
    it("first onSpeed schedules each hand one full swing ahead", function()
      local c = swing.new()
      c:onSpeed(100, 2.6, 1.8)
      local s = c:state(100)
      assert.are.near(2.6, s.mh.next, 1e-9)
      assert.are.near(1.8, s.oh.next, 1e-9)
      assert.are.equal(2.6, s.mh.speed)
    end)

    it("has no oh when off-hand speed is nil", function()
      local c = swing.new()
      c:onSpeed(100, 3.6, nil)
      assert.is_nil(c:state(100).oh)
    end)

    it("removes oh when the off-hand disappears", function()
      local c = dual()
      c:onSpeed(103, 2.6, nil)
      assert.is_nil(c:state(103).oh)
      assert.is_not_nil(c:state(103).mh)
    end)

    it("reports attacking flag and never negative next", function()
      local c = dual()
      local s = c:state(110)
      assert.is_true(s.attacking)
      assert.are.equal(0, s.mh.next)
      c:onAttack(111, false)
      assert.is_false(c:state(111).attacking)
    end)

    it("speed change rescales the remaining time proportionally", function()
      local c = dual()                 -- mh due 105.2 (2.2 left at 103)
      c:onSpeed(103, 2.0, 2.6)         -- Flurry: 2.6 -> 2.0
      local s = c:state(103)
      assert.are.near(2.2 * 2.0 / 2.6, s.mh.next, 1e-9)
      assert.are.equal(2.0, s.mh.speed)
      assert.are.near(2.4, s.oh.next, 1e-9) -- oh untouched
    end)

    it("attack start pulls overdue hands to now", function()
      local c = swing.new()
      c:onSpeed(100, 2.6, 2.6)
      c:onAttack(110, true)
      local s = c:state(110)
      assert.are.equal(0, s.mh.next)
      assert.are.equal(0, s.oh.next)
    end)
  end)

  describe("hand attribution", function()
    it("attributes to the hand whose expected swing is nearest", function()
      local c = dual()
      local s = c:state(103)
      assert.are.near(2.2, s.mh.next, 1e-9)
      assert.are.near(2.4, s.oh.next, 1e-9)
      assert.are.equal("oh", c:onSwing(105.6, false))  -- only oh is within tolerance
      assert.are.equal(0, c.resyncs)
    end)

    -- the server never swings the later hand first (off hand trails by >= 0.2 s),
    -- so with jitter the earlier-due hand takes the swing even if the other one is nearer
    it("both hands within tolerance: the earlier-due hand swings first", function()
      local c = dual()                 -- mh 105.2, oh 105.4
      assert.are.equal("mh", c:onSwing(105.31, false))
      assert.are.equal("oh", c:onSwing(105.5, false))
      assert.are.equal(0, c.resyncs)
    end)

    it("resync moves both hands, keeping their offset", function()
      local c = dual()                 -- mh 105.2, oh 105.4
      assert.are.equal("mh", c:onSwing(104.0, false))
      assert.are.equal(1, c.resyncs)
      assert.are.near(2.6, c:state(104.0).mh.next, 1e-9)
      assert.are.near(0.2, c:state(104.0).oh.next, 1e-9) -- was 0.2 s behind mh, still is
    end)

    it("resync keeps at least 0.2 s between hands of equal speed", function()
      local c = swing.new()
      c:onSpeed(100, 2.6, 2.6)         -- both due 102.6
      c:onAttack(100, true)
      assert.are.equal("mh", c:onSwing(101.0, false))
      assert.are.near(0.2, c:state(101.0).oh.next, 1e-9)
    end)

    it("returns nil when no weapon speed is known", function()
      local c = swing.new()
      assert.is_nil(c:onSwing(100, false))
    end)
  end)

  describe("extra attacks", function()
    it("explicit extra swing does not move timers", function()
      local c = dual()
      assert.are.equal("extra", c:onSwing(103.0, true))
      assert.are.near(2.2, c:state(103).mh.next, 1e-9)
    end)

    it("swing right after SPELL_EXTRA_ATTACKS is the extra one", function()
      local c = dual()                 -- mh 105.2
      assert.are.equal("mh", c:onSwing(105.2, false))  -- real swing, procs Hand of Justice
      c:onExtraAttacks(105.2, 1)
      assert.are.equal("extra", c:onSwing(105.22, false))
      assert.are.near(107.8 - 105.3, c:state(105.3).mh.next, 1e-9)
    end)

    it("extra window expires after 0.1 s", function()
      local c = dual()
      c:onExtraAttacks(104.0, 1)
      assert.are_not.equal("extra", c:onSwing(105.2, false))
    end)
  end)

  describe("casts", function()
    it("Lightning Bolt with 0 Maelstrom resets both hands at cast end", function()
      local c = dual()
      c:onCastStart(103.0, "lightningBolt", 0, 2.5)
      -- во время каста прогноз уже учитывает сброс
      assert.are.near(105.5 + 2.6 - 103.0, c:state(103.0).mh.next, 1e-9)
      c:onCastEnd(105.5, "lightningBolt", 0, true)
      local s = c:state(105.5)
      assert.are.near(2.6, s.mh.next, 1e-9)
      assert.are.near(2.6, s.oh.next, 1e-9)
    end)

    it("Chain Lightning with 0 Maelstrom also resets", function()
      local c = dual()
      c:onCastStart(103.0, "chainLightning", 0, 2.0)
      c:onCastEnd(105.0, "chainLightning", 0, true)
      assert.are.near(2.6, c:state(105.0).mh.next, 1e-9)
    end)

    it("cast with 1-4 Maelstrom delays swings that come due during the cast", function()
      local c = dual()                 -- mh 105.2, oh 105.4
      c:onCastStart(104.0, "lightningBolt", 3, 1.5) -- ends 105.5
      local s = c:state(104.2)
      assert.are.near(1.3, s.mh.next, 1e-9)
      assert.are.near(1.3, s.oh.next, 1e-9)
      c:onCastEnd(105.5, "lightningBolt", 3, true)
      assert.are.equal(0, c:state(105.5).mh.next)
      assert.are.equal("mh", c:onSwing(105.5, false))
      assert.are.equal("oh", c:onSwing(105.7, false))
    end)

    it("cast with 1-4 Maelstrom does not touch swings due after the cast", function()
      local c = dual()                 -- mh 105.2
      c:onCastStart(103.0, "lightningBolt", 4, 1.0) -- ends 104.0
      assert.are.near(2.2, c:state(103.0).mh.next, 1e-9)
      c:onCastEnd(104.0, "lightningBolt", 4, true)
      assert.are.near(1.2, c:state(104.0).mh.next, 1e-9)
    end)

    it("interrupted 0-stack cast does not reset, only releases delayed swings", function()
      local c = dual()                 -- mh 105.2, oh 105.4
      c:onCastStart(104.0, "lightningBolt", 0, 2.5)
      c:onCastEnd(105.3, "lightningBolt", 0, false)
      local s = c:state(105.3)
      assert.are.equal(0, s.mh.next)
      assert.are.near(0.1, s.oh.next, 1e-9)
    end)

    it("pushback moves the cast end and the delayed swings with it", function()
      local c = dual()                 -- mh 105.2, oh 105.4
      c:onCastStart(104.0, "lightningBolt", 3, 1.5) -- ends 105.5
      c:onCastDelayed(104.5, 106.0)
      local s = c:state(104.5)
      assert.are.near(1.5, s.mh.next, 1e-9)
      assert.are.near(1.5, s.oh.next, 1e-9)
    end)

    it("pushback without a tracked cast is ignored", function()
      local c = dual()
      c:onCastDelayed(104.5, 106.0)
      assert.are.near(0.7, c:state(104.5).mh.next, 1e-9)
    end)

    it("instant (5 stacks) cast start is ignored", function()
      local c = dual()
      c:onCastStart(103.0, "lightningBolt", 5, 0)
      assert.are.near(2.2, c:state(103.0).mh.next, 1e-9)
      c:onCastEnd(103.0, "lightningBolt", 5, true)
      assert.are.near(2.2, c:state(103.0).mh.next, 1e-9)
    end)

    it("non-reset spell with 0 stacks only delays", function()
      local c = dual()
      c:onCastStart(104.0, "hex", 0, 1.5)
      c:onCastEnd(105.5, "hex", 0, true)
      assert.are.equal(0, c:state(105.5).mh.next)
    end)
  end)

  describe("instant calibration", function()
    it("three reset observations mark the spell as resetting", function()
      local c = twoHand()
      for _ = 1, 3 do instantThenSwing(c, "earthShock", "reset") end
      assert.is_true(c.saved.reset.earthShock)
      assert.is_true(c:state(0).resetByInstant.earthShock)
    end)

    it("three keep observations mark the spell as not resetting", function()
      local c = twoHand()
      for _ = 1, 3 do instantThenSwing(c, "stormstrike", "keep") end
      assert.is_false(c.saved.reset.stormstrike)
      assert.is_nil(c:state(0).resetByInstant.stormstrike)
    end)

    it("undecided after two votes", function()
      local c = twoHand()
      for _ = 1, 2 do instantThenSwing(c, "earthShock", "reset") end
      assert.is_nil(c.saved.reset.earthShock)
      assert.are.equal(2, c.saved.votes.earthShock.reset)
    end)

    it("a calibrated resetting instant resets the swing immediately", function()
      local c = twoHand()
      for _ = 1, 3 do instantThenSwing(c, "earthShock", "reset") end
      local due = c:state(0).mh.next
      local t = due - 1.0
      c:onInstant(t, "earthShock")
      assert.are.near(3.6, c:state(t).mh.next, 1e-9)
    end)

    it("ambiguous observation (old and reset moments too close) is not counted", function()
      local c = twoHand()              -- due 107.2
      c:onInstant(103.8, "earthShock") -- reset due 107.4, only 0.2 from old
      c:onSwing(107.2, false)
      assert.is_nil(c.saved.votes.earthShock)
    end)

    it("calibration survives into a new clock through saved", function()
      local saved = {}
      local c = twoHand(saved)
      for _ = 1, 3 do instantThenSwing(c, "earthShock", "reset") end
      local c2 = twoHand(saved)
      assert.is_true(c2:state(0).resetByInstant.earthShock)
    end)

    it("reads c.saved on every access, even if replaced by an empty table", function()
      local c = twoHand()
      local fresh = {}
      c.saved = fresh
      assert.are.same({}, c:state(0).resetByInstant)
      for _ = 1, 3 do instantThenSwing(c, "earthShock", "reset") end
      assert.is_true(fresh.reset.earthShock)
      assert.are.equal(3, fresh.votes.earthShock.reset)
    end)

    -- dual wield: the off hand trails by 0.2 s, closer than HAND_TOLERANCE
    local function dualRound(c, arrive)
      local mh, oh = c.hands.mh.due, c.hands.oh.due
      local t = mh - 1.2
      c:onInstant(t, "earthShock")
      if arrive == "keep" then
        c:onSwing(mh, false)
        c:onSwing(oh, false)
      else
        c:onSwing(oh, false)
        c:onSwing(t + 2.6, false)
      end
    end

    it("dual wield: keep observations count although the off hand is due 0.2 s later", function()
      local c = dual()
      for _ = 1, 3 do dualRound(c, "keep") end
      assert.are.equal(3, c.saved.votes.earthShock.keep)
      assert.is_false(c.saved.reset.earthShock)
    end)

    it("dual wield: an off-hand swing before the reset moment does not settle the observation", function()
      local c = dual()
      for _ = 1, 3 do dualRound(c, "reset") end
      assert.are.equal(3, c.saved.votes.earthShock.reset)
      assert.is_true(c.saved.reset.earthShock)
    end)

    it("drops the observation once both moments have passed", function()
      local c = dual()                 -- mh 105.2, oh 105.4
      c:onInstant(104.0, "earthShock") -- old 105.2, reset 106.6
      c.hands.oh.due = 107.0
      c:onSwing(107.0, false)          -- off hand, long after both moments
      assert.is_nil(c.obs)
      assert.is_nil(c.saved.votes.earthShock)
    end)

    it("a speed change rescales both calibration moments", function()
      local c = twoHand()              -- due 107.2
      c:onInstant(105.0, "earthShock") -- old 107.2, reset 108.6
      c:onSpeed(105.5, 2.7, nil)       -- Flurry: 3.6 -> 2.7
      assert.are.near(105.5 + 1.7 * 0.75, c.obs.oldDue, 1e-9)
      assert.are.near(105.5 + 3.1 * 0.75, c.obs.resetDue, 1e-9)
      c:onSwing(105.5 + 3.1 * 0.75, false)
      assert.are.equal(1, c.saved.votes.earthShock.reset)
    end)

    it("a cast between instant and swing cancels the observation", function()
      local c = twoHand()              -- due 107.2
      c:onInstant(105.9, "earthShock")
      c:onCastStart(106.0, "lightningBolt", 2, 1.0)
      c:onCastEnd(107.0, "lightningBolt", 2, true)
      c:onSwing(107.2, false)
      assert.is_nil(c.saved.votes.earthShock)
    end)
  end)

  describe("castWindow", function()
    it("any time is fine when not auto-attacking", function()
      local c = swing.new()
      c:onSpeed(100, 2.6, 2.6)
      local a, b = c:castWindow(100, 1.0, 0.15)
      assert.are.equal(0, a)
      assert.are.equal(swing.HORIZON, b)
    end)

    it("finds the first gap between swings long enough for cast + latency", function()
      local c = dual()                 -- mh due 105.2, oh due 105.4
      c:onSwing(105.2, false)          -- mh -> 107.8
      c:onSwing(105.4, false)          -- oh -> 108.0
      -- at 105.5: events 2.3, 2.5, 4.9, 5.1; gap 0..2.3 fits 1.0 + 0.15
      local a, b = c:castWindow(105.5, 1.0, 0.15)
      assert.are.near(0, a, 1e-9)
      assert.are.near(2.3 - 1.15, b, 1e-9)
    end)

    it("skips gaps that are too short", function()
      local c = dual()                 -- at 105.1: mh next 0.1, oh 0.3
      local a, b = c:castWindow(105.1, 1.0, 0.15)
      -- events: 0.1, 0.3, 2.7, 2.9, 5.3, 5.5 -> first fitting gap 0.3..2.7
      assert.are.near(0.3, a, 1e-9)
      assert.are.near(2.7 - 1.15, b, 1e-9)
    end)

    it("returns nil when no gap fits inside the horizon", function()
      local c = dual()
      assert.is_nil(c:castWindow(105.1, 3.0, 0.15))
    end)
  end)
end)
