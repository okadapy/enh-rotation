local G = require("game_mock")
local spells = require("spells")
local Sc = require("scenario")

-- The neighbours (swing, enemies, ttd, planner, model) are replaced by fakes, so this spec
-- tests only the wiring. The "#integration" block at the end loads the real ones.
local NEIGHBOURS = { "swing", "enemies", "ttd", "planner", "model", "timeline", "runtime" }
local real = {}
for _, n in ipairs(NEIGHBOURS) do real[n] = package.loaded[n]; package.loaded[n] = nil end
local created = {}
package.loaded.swing = { new = function(saved)
  local c = { saved = saved, calls = {} }
  for _, m in ipairs({ "onSwing", "onExtraAttacks", "onSpeed", "onCastStart", "onCastEnd", "onCastDelayed", "onInstant", "onAttack" }) do
    c[m] = function(self, ...) self.calls[#self.calls + 1] = { m, ... } end
  end
  c.state = function() return { attacking = false, mh = { next = 1, speed = 2.6 }, resetByInstant = {} } end
  created.swing = c
  return c
end }
package.loaded.enemies = { new = function()
  local e = { calls = {} }
  function e:onEvent(...) self.calls[#self.calls + 1] = { ... } end
  function e:counts() return 1, 1 end
  return e
end }
package.loaded.ttd = { new = function()
  local t = { resets = {} }
  function t:add() end
  function t:estimate() return 60 end
  function t:reset(guid) self.resets[#self.resets + 1] = guid or "all" end
  return t
end }
package.loaded.planner = { new = function() return { update = function() return { value = 0, steps = {} } end } end }
package.loaded.model = { castTime = function() return 1.0 end }
local runtime = require("runtime")
local planner = package.loaded.planner
for _, n in ipairs(NEIGHBOURS) do package.loaded[n] = real[n] end

local function top(key) local r = spells.byKey[key].ranks; return r[#r] end

local PLAN = { value = 10, steps = { { key = "stormstrike", at = 0, reason = "Stormstrike" }, { key = "lavaLash", at = 1.5 } } }

local function allKnown()
  local k = {}
  for _, meta in ipairs(spells.CATALOG) do k[meta.ranks[#meta.ranks]] = true end
  return k
end

local function install(extra)
  local cfg = { now = 100, known = allKnown(), castMs = { ["Lightning Bolt"] = 2500 },
                target = { level = 83, hp = 1e6, hpMax = 1e6, guid = "Creature-9" }, inRange = { Stormstrike = 1 },
                enchants = { mh = true, oh = true }, tooltip = { [16] = { "Windfury 8" }, [17] = { "Flametongue 10" } },
                auras = { player = { HELPFUL = { { name = "Lightning Shield", count = 3, expires = 700 } } } } }
  for k, v in pairs(extra or {}) do cfg[k] = v end
  return G.install(cfg)
end

local function spy()
  local s = { calls = {}, saved = {} }
  for _, m in ipairs({ "onSwing", "onExtraAttacks", "onSpeed", "onCastStart", "onCastEnd", "onCastDelayed", "onInstant", "onAttack" }) do
    s[m] = function(self, ...) self.calls[#self.calls + 1] = { m, ... } end
  end
  s.state = function() return { attacking = true, mh = { next = 1, speed = 2.6 }, oh = { next = 0.5, speed = 2.6 }, resetByInstant = {} } end
  s.castWindow = function() return nil end
  return s
end

local function enemiesSpy()
  local e = { calls = {} }
  function e:onEvent(...) self.calls[#self.calls + 1] = { ... } end
  function e:counts() return 1, 1 end
  return e
end

describe("runtime", function()
  local realNew, calls, nextPlan
  before_each(function()
    realNew = planner.new
    calls, nextPlan = {}, PLAN
    planner.new = function()
      return { update = function(_, S, ev) calls[#calls + 1] = { S = S, ev = ev }; return nextPlan end }
    end
  end)
  after_each(function() planner.new = realNew end)

  local function start(config, extra)
    install(extra)
    local env = { config = config or {}, region = CreateFrame("Frame"), saved = {} }
    local rt = runtime.start(env.config, env)
    rt.ctx.swing = spy()
    rt.ctx.enemies = enemiesSpy()
    return rt, env
  end

  it("validates plans", function()
    assert.is_true(runtime.validPlan(PLAN))
    assert.is_true(runtime.validPlan({ steps = { { key = "waitSwing", at = 0.4 } } }))
    assert.is_false(runtime.validPlan(nil))
    assert.is_false(runtime.validPlan({ steps = { { key = "fireball", at = 0 } } }))
    assert.is_false(runtime.validPlan({ steps = { { key = "stormstrike", at = 0 / 0 } } }))
  end)

  it("raises alerts in order of importance", function()
    local S = Sc.state(80)
    S.buffs.ls.charges = 0
    assert.are.equal("lightningShield", runtime.alert(S).key)
    S = Sc.state(80); S.weapons.oh.enchant = nil
    assert.are.equal("noEnchant", runtime.alert(S).key)
    S = Sc.state(80); S.player.mana = S.player.manaMax * 0.1; S.spells.shamanisticRage.cd = 0
    local a = runtime.alert(S)
    assert.are.equal("shamanisticRage", a.key)
    assert.are.equal(spells.byKey.shamanisticRage.icon, a.icon)
    S = Sc.state(80); S.target.range = "far"
    assert.are.equal("outOfRange", runtime.alert(S).key)
    assert.is_nil(runtime.alert(Sc.state(80)))
  end)

  it("registers 3.3.5 events only and reuses the engine frame", function()
    local rt = start()
    assert.is_true(rt.frame.events.UNIT_MANA)
    assert.is_nil(rt.frame.events.UNIT_POWER)
    assert.is_true(rt.frame.events.COMBAT_LOG_EVENT_UNFILTERED)
    assert.is_true(rt.frame.events.SPELLS_CHANGED)
    local env2 = { config = {}, region = CreateFrame("Frame"), saved = {} }
    local old = rt.tl
    local rt2 = runtime.start({}, env2)
    assert.are.equal(rt.frame, rt2.frame)
    assert.is_false(old.frame.shown)
    assert.are.equal(rt2, env2.rt)
  end)

  it("feeds own swings and extra attacks to the swing clock", function()
    local rt = start()
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SWING_DAMAGE", "Player-1", "Me", 0x511, "Creature-9", "Mob", 0xa48, 1200)
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SPELL_EXTRA_ATTACKS", "Player-1", "Me", 0x511, "Player-1", "Me", 0x511, 15600, "Hand of Justice", 1, 2)
    assert.are.same({ "onSwing", 100, false }, rt.ctx.swing.calls[1])
    assert.are.same({ "onExtraAttacks", 100, 2 }, rt.ctx.swing.calls[2])
    assert.are.equal("swing", rt.pending.kind)
  end)

  it("drops combat log lines that do not involve the player", function()
    local rt = start()
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SWING_DAMAGE", "Creature-2", "A", 0, "Creature-3", "B", 0, 100)
    assert.are.equal(0, #rt.ctx.enemies.calls)
    assert.are.equal(0, #rt.ctx.swing.calls)
    assert.is_nil(rt.pending)
  end)

  it("replans when the current target dies", function()
    local rt = start()
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "UNIT_DIED", nil, nil, 0, "Creature-9", "Mob", 0xa48)
    assert.are.equal("target", rt.pending.kind)
  end)

  it("tracks a hard cast with the Maelstrom stacks at its start", function()
    local rt = start(nil, { casting = { name = "Lightning Bolt", startMs = 100000, endMs = 101500 },
      auras = { player = { HELPFUL = { { name = "Maelstrom Weapon", count = 3, expires = 110 } } } } })
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "player", "Lightning Bolt", "Rank 14")
    assert.are.same({ "onCastStart", 100, "lightningBolt", 3, 1.5 }, rt.ctx.swing.calls[1])
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Lightning Bolt", "Rank 14")
    assert.are.same({ "onCastEnd", 100, "lightningBolt", 3, true }, rt.ctx.swing.calls[2])
    assert.are.equal(101, rt.ctx.inflight.lightningBolt)
  end)

  it("passes spell pushback to the swing clock with the new cast end", function()
    local rt = start(nil, { casting = { name = "Lightning Bolt", startMs = 100000, endMs = 101500 } })
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "player", "Lightning Bolt", "Rank 14")
    rt.ctx.swing.calls = {}
    G.cfg.casting.endMs = 102000
    runtime.onEvent(rt, "UNIT_SPELLCAST_DELAYED", "player", "Lightning Bolt", "Rank 14")
    assert.are.same({ "onCastDelayed", 100, 102 }, rt.ctx.swing.calls[1])
  end)

  it("reports an interrupted cast and instant casts separately", function()
    local rt = start(nil, { casting = { name = "Lightning Bolt", startMs = 100000, endMs = 102500 } })
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "player", "Lightning Bolt", "Rank 14")
    runtime.onEvent(rt, "UNIT_SPELLCAST_INTERRUPTED", "player", "Lightning Bolt", "Rank 14")
    assert.are.same({ "onCastEnd", 100, "lightningBolt", 0, false }, rt.ctx.swing.calls[2])
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Earth Shock", "Rank 10")
    assert.are.same({ "onInstant", 100, "earthShock" }, rt.ctx.swing.calls[3])
    runtime.onEvent(rt, "UNIT_SPELLCAST_FAILED", "player", "Earth Shock", "Rank 10")
    assert.is_nil(rt.ctx.inflight.earthShock)
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "party1", "Lightning Bolt", "Rank 14")
    assert.are.equal(3, #rt.ctx.swing.calls)
  end)

  it("clears the in-flight mark when the aura lands", function()
    local rt = start()
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Flame Shock", "Rank 9")
    assert.is_not_nil(rt.ctx.inflight.flameShock)
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SPELL_AURA_APPLIED", "Player-1", "Me", 0x511, "Creature-9", "Mob", 0xa48, 49233, "Flame Shock", 4, "DEBUFF")
    assert.is_nil(rt.ctx.inflight.flameShock)
  end)

  it("passes attack speed changes and auto-attack state", function()
    local rt = start(nil, { speed = { 2.4, 2.4 } })
    runtime.onEvent(rt, "UNIT_ATTACK_SPEED", "player")
    assert.are.same({ "onSpeed", 100, 2.4, 2.4 }, rt.ctx.swing.calls[1])
    runtime.onEvent(rt, "PLAYER_ENTER_COMBAT")
    assert.is_true(rt.ctx.attacking)
    assert.are.same({ "onAttack", 100, true }, rt.ctx.swing.calls[2])
    runtime.onEvent(rt, "PLAYER_LEAVE_COMBAT")
    assert.is_false(rt.ctx.attacking)
    assert.are.same({ "onAttack", 100, false }, rt.ctx.swing.calls[3])
  end)

  it("coalesces events and keeps the most important one", function()
    local rt = start()
    runtime.onEvent(rt, "UNIT_MANA", "player")
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Earth Shock", "Rank 10")
    runtime.onEvent(rt, "UNIT_AURA", "player")
    runtime.update(rt, 0.01)
    assert.are.equal(1, #calls)
    assert.are.equal("cast", calls[1].ev.kind)
    assert.are.equal("earthShock", calls[1].ev.key)
  end)

  it("pulses every 0.25 s without events", function()
    local rt = start()
    runtime.update(rt, 0.1)
    assert.are.equal(0, #calls)
    runtime.update(rt, 0.2)
    assert.are.equal(1, #calls)
    assert.are.equal("pulse", calls[1].ev.kind)
  end)

  it("shows the host aura on the first update", function()
    local rt = start()
    runtime.update(rt, 0.01)
    assert.are.equal("ENHROT_SHOW", G.sent[1][1])
  end)

  it("does not plan without a hostile target", function()
    local rt = start(nil, { target = { exists = false } })
    runtime.update(rt, 0.3)
    assert.are.equal(0, #calls)
    assert.are.same({}, rt.plan.steps)
  end)

  it("reports a broken plan once and keeps the last good one", function()
    local rt = start()
    runtime.update(rt, 0.3)
    nextPlan = { steps = { { key = "fireball", at = 0 } } }
    runtime.update(rt, 0.3)
    runtime.update(rt, 0.3)
    assert.are.equal(1, #G.printed)
    assert.are.equal(PLAN, rt.plan)
    assert.are.equal(2, rt.counters.errors)
  end)

  it("prints debug lines only when the first action changes", function()
    local rt = start({ printDebug = true })
    runtime.update(rt, 0.3)
    runtime.update(rt, 0.3)
    assert.are.equal(1, #G.printed)
    assert.is_not_nil(G.printed[1]:find("stormstrike@0.0", 1, true))
  end)

  it("records a snapshot on replans when recording is on", function()
    local rt, env = start({ record = true })
    runtime.update(rt, 0.3)
    assert.are.equal(1, #env.saved.enhrotSnapshots)
  end)

  it("rescans spells after learning one", function()
    local rt = start(nil, { known = { [top("lightningBolt")] = true } })
    assert.is_nil(rt.ctx.cache.known.stormstrike)
    G.cfg.known[17364] = true
    runtime.onEvent(rt, "LEARNED_SPELL_IN_TAB")
    assert.is_not_nil(rt.ctx.cache.known.stormstrike)
    assert.are.equal("target", rt.pending.kind)
  end)

  it("resets enemies and the planner when combat ends", function()
    local rt = start()
    local p = rt.planner
    runtime.onEvent(rt, "PLAYER_REGEN_ENABLED")
    assert.are_not.equal(p, rt.planner)
  end)

  it("creates the swing clock on the saved calibration table and gives it weapon speeds", function()
    install({ speed = { 2.5, 2.4 } })
    local env = { config = {}, region = CreateFrame("Frame"), saved = {} }
    local rt = runtime.start({}, env)
    assert.is_table(env.saved.swing)
    assert.are.equal(env.saved.swing, rt.ctx.swing.saved)
    assert.are.same({ "onSpeed", 100, 2.5, 2.4 }, rt.ctx.swing.calls[1])
    assert.is_nil(rt.ctx.attacking)
    local saved = { swing = { reset = { stormstrike = true } } }
    rt = runtime.start({}, { config = {}, region = CreateFrame("Frame"), saved = saved })
    assert.are.equal(saved.swing, rt.ctx.swing.saved)
  end)

  it("picks up auto-attack that is already on after a reload", function()
    install({})
    _G.IsCurrentSpell = function(id) return id == 6603 and 1 or nil end
    local rt = runtime.start({}, { config = {}, region = CreateFrame("Frame"), saved = {} })
    _G.IsCurrentSpell = nil
    assert.is_true(rt.ctx.attacking)
    assert.are.same({ "onAttack", 100, true }, rt.ctx.swing.calls[2])
  end)

  it("remembers when the wolves were summoned", function()
    local rt = start()
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Feral Spirit", "")
    assert.are.equal(145, rt.ctx.wolvesUntil)
  end)

  it("forgets dead units in enemies and time-to-die, even when others killed them", function()
    local rt = start()
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "UNIT_DIED", nil, nil, 0, "Creature-5", "Mob", 0xa48)
    assert.are.same({ 100, "UNIT_DIED", nil, "Creature-5", "Player-1" }, rt.ctx.enemies.calls[1])
    assert.are.same({ "Creature-5" }, rt.ctx.ttd.resets)
    assert.is_nil(rt.pending)
  end)

  it("keeps combat log lines of the player's totems and wolves", function()
    local rt = start()
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SPELL_SUMMON", "Player-1", "Me", 0x511, "Creature-77", "Magma Totem", 0x2111, 58734, "Magma Totem VII", 4)
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SPELL_DAMAGE", "Creature-77", "Magma Totem", 0x2111, "Creature-3", "B", 0xa48, 58735, "Magma Totem", 4, 900)
    assert.are.equal(2, #rt.ctx.enemies.calls)
    assert.are.equal("Creature-77", rt.ctx.enemies.calls[2][3])
    assert.are.equal(0, #rt.ctx.swing.calls)
  end)

  it("forgets time-to-die and summons when combat ends", function()
    local rt = start()
    rt.mine["Creature-77"] = true
    runtime.onEvent(rt, "PLAYER_REGEN_ENABLED")
    assert.are.same({ "all" }, rt.ctx.ttd.resets)
    assert.are.same({}, rt.mine)
  end)

  it("hands a 0-value empty plan to the timeline when the planner finds nothing", function()
    local rt = start()
    nextPlan = { value = 0, steps = {} }
    assert.is_true(runtime.update(rt, 0.3))
    assert.are.same({}, rt.plan.steps)
    assert.are.equal(rt.plan, rt.tl.plan)
  end)
end)

describe("runtime with real neighbours #integration", function()
  it("starts, takes events and plans without errors", function()
    for _, n in ipairs(NEIGHBOURS) do package.loaded[n] = nil end
    local rtm = require("runtime")
    install({ speed = { 2.6, 2.6 } })
    local env = { config = {}, region = CreateFrame("Frame"), saved = {} }
    local rt = rtm.start({}, env)
    rtm.onEvent(rt, "PLAYER_ENTER_COMBAT")
    rtm.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SWING_DAMAGE", "Player-1", "Me", 0x511, "Creature-9", "Mob", 0xa48, 1200)
    assert.is_true(rtm.update(rt, 0.3))
    assert.is_true(rtm.validPlan(rt.plan))
    assert.is_true(rt.S.swing.attacking)
    assert.is_table(env.saved.swing.reset)
    for _, n in ipairs(NEIGHBOURS) do package.loaded[n] = real[n] end
  end)
end)
