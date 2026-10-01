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
  function t:smoothed() return 60 end
  function t:reset(guid) self.resets[#self.resets + 1] = guid or "all" end
  return t
end }
package.loaded.planner = { new = function() return { update = function() return { value = 0, steps = {} } end } end }
-- snapshot decides the long cooldowns' gate through the model (snapshot_spec tests it)
package.loaded.model = { castTime = function() return 1.0 end, COOLDOWN_TTD = { feralSpirit = 22.5 },
                         cooldownDecide = function() return true end }
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
                auras = { player = { HELPFUL = { { name = "Lightning Shield", count = 3, expires = 700 } } } },
                talents = { { { "Maelstrom Weapon", 5 } } } }
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

  it("fills the cooldown options from the config (defaults without it)", function()
    local rt = start({ cdFeralSpirit = 2, cdFireElemental = 4, cdShamanisticRage = 1 })
    assert.are.same({ feralSpirit = "boss", fireElemental = "never", shamanisticRage = "auto" }, rt.ctx.cooldowns)
    rt = start({})
    assert.are.same({ feralSpirit = "auto", fireElemental = "auto", shamanisticRage = "always" }, rt.ctx.cooldowns)
  end)

  it("fills the weaving option from the config (3+ stacks without it)", function()
    assert.are.equal(3, (start({})).ctx.weaveMin)
    assert.are.equal(5, (start({ weave = 2 })).ctx.weaveMin)
    assert.are.equal(0, (start({ weave = 3 })).ctx.weaveMin)
  end)

  it("fills the solo mana option from the config (balanced without it)", function()
    assert.are.equal("balanced", (start({})).ctx.manaPolicy)
    assert.are.equal("save", (start({ manaPolicy = 2 })).ctx.manaPolicy)
    assert.are.equal("spend", (start({ manaPolicy = 3 })).ctx.manaPolicy)
  end)

  it("no low-mana Shamanistic Rage alert when the player set it to never", function()
    local S = Sc.state(80); S.player.mana = S.player.manaMax * 0.1; S.spells.shamanisticRage.cd = 0
    S.cooldowns = { shamanisticRage = "never" }
    assert.is_nil(runtime.alert(S))
  end)

  it("validates plans", function()
    assert.is_true(runtime.validPlan(PLAN))
    assert.is_true(runtime.validPlan({ steps = { { key = "waitSwing", at = 0.4 } } }))
    assert.is_false(runtime.validPlan(nil))
    assert.is_false(runtime.validPlan({ steps = { { key = "fireball", at = 0 } } }))
    assert.is_false(runtime.validPlan({ steps = { { key = "stormstrike", at = 0 / 0 } } }))
  end)

  it("Bloodlust ready only without Sated / Exhaustion", function()
    local known = allKnown(); known[2825] = true
    install({ known = known })
    local S = Sc.state(80)
    assert.are.equal("lust", runtime.lustReady(S, 100).key)
    install({ known = known, auras = { player = { HARMFUL = { { name = "Sated", id = 57724, expires = 500 } } } } })
    assert.is_nil(runtime.lustReady(S, 100))
    install({ known = known, auras = { player = { HARMFUL = { { name = "Exhaustion", id = 57723, expires = 500 } } } } })
    assert.is_nil(runtime.lustReady(S, 100))
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

  it("asks for auto-attack in melee reach when it is off", function()
    local S = Sc.state(53)
    S.swing.attacking = false
    local a = runtime.alert(S)
    assert.are.equal("autoAttack", a.key)
    assert.are.equal(runtime.ALERT_ICONS.autoAttack, a.icon)
    S.target.range = "20"
    assert.is_nil(runtime.alert(S))
    S.target.range = "melee"; S.buffs.ls.charges = 0
    assert.are.equal("autoAttack", runtime.alert(S).key) -- before a missing buff
  end)

  it("does not ask for Lightning Shield while its cast is on the way", function()
    local S = Sc.state(80)
    S.buffs.ls.charges = 0
    S.inflight = { lightningShield = 0.6 }
    assert.is_nil(runtime.alert(S))
  end)

  it("asks for the shield the player wants kept up", function()
    local S = Sc.state(80)
    S.buffs.ls.charges = 0; S.player.shield = "water"; S.buffs.ws = { charges = 3, remains = 500 }
    assert.is_nil(runtime.alert(S)) -- auto with Water Shield on
    S.shieldPref = "water"
    assert.is_nil(runtime.alert(S))
    S.shieldPref = "lightning"
    assert.are.equal("lightningShield", runtime.alert(S).key)
    S.player.shield, S.buffs.ws = nil, nil
    S.shieldPref = "auto"
    assert.are.equal("lightningShield", runtime.alert(S).key) -- nothing up: as before
    S.shieldPref = "water"
    local a = runtime.alert(S)
    assert.are.equal("waterShield", a.key)
    assert.are.equal("Water Shield missing", a.reason)
    assert.are.equal(runtime.ALERT_ICONS.waterShield, a.icon)
    S.player.shield = "lightning"; S.buffs.ls.charges = 3
    assert.are.equal("waterShield", runtime.alert(S).key) -- Lightning Shield up, Water wanted
  end)

  -- recorded: Rage pressed at 20 yards without auto-attack on the hint - its mana comes from hits
  it("suggests Shamanistic Rage for mana only in melee with auto-attack on", function()
    local S = Sc.state(80); S.player.mana = S.player.manaMax * 0.1; S.spells.shamanisticRage.cd = 0
    S.target.range = "20"
    assert.is_nil(runtime.alert(S))
    S.target.range = "melee"; S.swing.attacking = false
    assert.are.equal("autoAttack", runtime.alert(S).key)
  end)

  it("hints to move into melee when nothing is worth pressing at 20-30 yards", function()
    local S = Sc.state(53)
    S.target.range = "20"
    assert.are.equal("moveIn", runtime.idleHint({ steps = {} }, S).key)
    assert.is_nil(runtime.idleHint({ steps = { { key = "flameShock", at = 0 } } }, S))
    assert.is_nil(runtime.idleHint({ steps = {} }, S, true)) -- the search is still running
    S.target.range = "melee"
    assert.is_nil(runtime.idleHint({ steps = {} }, S))
  end)

  it("an empty plan in melee with no mana for any button says so; not for the GCD", function()
    local S = Sc.state(80)
    S.spells.shamanisticRage.cd = 30
    S.player.mana = 0
    local h = runtime.idleHint({ steps = {} }, S)
    assert.are.equal("outOfMana", h.key)
    assert.are.equal("Out of mana", h.reason)
    assert.are.equal(runtime.ALERT_ICONS.outOfMana, h.icon)
    S.spells.shamanisticRage.cd = 0 -- Rage is ready: that is the hint (runtime.alert), not "Out of mana"
    assert.is_nil(runtime.idleHint({ steps = {} }, S))
    S = Sc.state(80)
    S.spells.shamanisticRage.cd = 30
    S.gcdRemains = 1.2 -- enough mana, only the GCD: nothing to say
    assert.is_nil(runtime.idleHint({ steps = {} }, S))
  end)

  it("suggests a drink out of combat with no enemy target and low mana, unless drinking", function()
    local S = Sc.state(80)
    S.target = { exists = false }
    S.player.inCombat = false
    S.player.mana = S.player.manaMax * 0.3
    local h = runtime.idleHint({ steps = {} }, S, false, function() return false end)
    assert.are.equal("drink", h.key)
    assert.are.equal(runtime.ALERT_ICONS.drink, h.icon)
    assert.is_nil(runtime.idleHint({ steps = {} }, S, false, function() return true end))
    S.player.inCombat = true
    assert.is_nil(runtime.idleHint({ steps = {} }, S))
    S.player.inCombat, S.player.mana = false, S.player.manaMax * 0.8
    assert.is_nil(runtime.idleHint({ steps = {} }, S))
  end)

  -- recorded #63 (level 54, solo, a mob at 30 yd not pulled, 11% mana, empty plan): the hint said
  -- "Move into melee"; with the bar that empty the drink comes first
  it("solo, a mob out of melee, nobody in combat, mana at most 30%: Drink before the walk", function()
    local S = dofile("spec/fixtures/recorded.lua")[63].S
    assert.are.equal("solo", S.mode)
    assert.are.equal("30", S.target.range)
    local h = runtime.idleHint({ steps = {} }, S, false, function() return false end)
    assert.are.equal("drink", h.key)
    assert.are.equal("Drink", h.reason)
    assert.are.equal(runtime.ALERT_ICONS.drink, h.icon)
    -- already drinking: nothing to add (the walk waits for the drink)
    assert.is_nil(runtime.idleHint({ steps = {} }, S, false, function() return true end))
    assert.is_nil(runtime.idleHint({ steps = {} }, S, true)) -- the search is still running
    assert.is_nil(runtime.idleHint({ steps = { { key = "lightningBolt", at = 0 } } }, S))
    -- boundaries: 30% drinks, above it the walk as before
    local p = S.player
    p.mana = p.manaMax * 0.3
    assert.are.equal("drink", runtime.idleHint({ steps = {} }, S).key)
    p.mana = p.manaMax * 0.31
    assert.are.equal("moveIn", runtime.idleHint({ steps = {} }, S).key)
    p.mana = p.manaMax * 0.1
    -- in combat (the player or the mob): the fight is on, go
    p.inCombat = true
    assert.are.equal("moveIn", runtime.idleHint({ steps = {} }, S).key)
    p.inCombat = false
    S.target.inCombat = true
    assert.are.equal("moveIn", runtime.idleHint({ steps = {} }, S).key)
    S.target.inCombat = false
    -- in a group: as before
    S.mode = "group"
    assert.are.equal("moveIn", runtime.idleHint({ steps = {} }, S).key)
    S.mode = "solo"
    S.target.range = "20"
    assert.are.equal("drink", runtime.idleHint({ steps = {} }, S).key)
    -- in melee the rule does not apply
    S.target.range = "melee"
    assert.are_not.equal("drink", (runtime.idleHint({ steps = {} }, S) or {}).key)
  end)

  it("shows the drink hint with no target, and not while the Drink buff is on", function()
    local rt = start(nil, { target = { exists = false }, inCombat = false, mana = 2000, manaMax = 10000 })
    runtime.update(rt, 0.3)
    assert.is_true(rt.tl.alert.shown)
    assert.are.equal(runtime.ALERT_ICONS.drink, rt.tl.alert.texture)
    assert.are.equal("Drink", rt.tl.alertText.text)
    rt = start(nil, { target = { exists = false }, inCombat = false, mana = 2000, manaMax = 10000,
                      auras = { player = { HELPFUL = { { name = "Lightning Shield", count = 3, expires = 700 },
                                                       { name = "Drink", expires = 120 } } } } })
    runtime.update(rt, 0.3)
    assert.is_false(rt.tl.alert.shown)
  end)

  -- conjured mana food (Ritual of Refreshment) is eaten under "Refreshment", not "Drink";
  -- names come localized from the spell ids
  it("counts the Refreshment buff of conjured mana food as drinking, localized; Food is not", function()
    local function aura(name)
      install({ auras = { player = { HELPFUL = { { name = "Lightning Shield", count = 3, expires = 700 },
                                                  { name = name, expires = 30 } } } },
                spellNames = { [runtime.DRINK_ID] = "Trinken", [runtime.REFRESHMENT_ID] = "Erfrischung" } })
      return runtime.drinking()
    end
    assert.is_true(aura("Trinken"))
    assert.is_true(aura("Erfrischung"))
    assert.is_false(aura("Drink"))
    assert.is_false(aura("Nahrung"))
    install({ auras = { player = { HELPFUL = { { name = "Refreshment", expires = 30 } } } } })
    assert.is_true(runtime.drinking())
    install({ auras = { player = { HELPFUL = { { name = "Food", expires = 30 } } } } })
    assert.is_false(runtime.drinking())
  end)

  it("imbue and range alerts have their own icons", function()
    local S = Sc.state(80); S.weapons.mh.enchant = nil
    local a = runtime.alert(S)
    assert.are.equal(runtime.IMBUE_ICONS.windfury, a.icon)
    assert.are.equal("Main-hand imbue missing", a.reason)
    S = Sc.state(80); S.weapons.oh.enchant = nil
    a = runtime.alert(S)
    assert.are.equal(runtime.IMBUE_ICONS.flametongue, a.icon)
    assert.are.equal("Off-hand imbue missing", a.reason)
    S = Sc.state(20); S.weapons.mh.enchant = nil
    assert.are.equal(runtime.IMBUE_ICONS.flametongue, runtime.alert(S).icon)
    S = Sc.state(8); S.weapons.mh.enchant = nil
    assert.are.equal(runtime.IMBUE_ICONS.rockbiter, runtime.alert(S).icon)
    assert.are_not.equal(runtime.ALERT_ICONS.moveIn, runtime.ALERT_ICONS.outOfRange)
    local seen = {}
    for k, icon in pairs(runtime.ALERT_ICONS) do
      if k ~= "noEnchant" then
        assert.is_nil(seen[icon], k .. " shares its icon with " .. tostring(seen[icon]))
        seen[icon] = k
      end
      assert.truthy(icon:match("^Interface\\Icons\\[%w_]+$"), icon)
    end
    for _, icon in pairs(runtime.IMBUE_ICONS) do assert.truthy(icon:match("^Interface\\Icons\\[%w_]+$"), icon) end
  end)

  it("Bloodlust ready only in a fight: an enemy target and combat", function()
    local known = allKnown(); known[2825] = true
    install({ known = known })
    local S = Sc.state(80)
    S.target.inCombat, S.player.inCombat = false, false
    assert.is_nil(runtime.lustReady(S, 100))
    S.player.inCombat = true
    assert.are.equal("lust", runtime.lustReady(S, 100).key)
    S.player.inCombat, S.target.inCombat = false, true
    assert.are.equal("lust", runtime.lustReady(S, 100).key)
    S.target = { exists = false }
    S.player.inCombat = true
    assert.is_nil(runtime.lustReady(S, 100)) -- in town, no target
    S.target = { exists = true, enemy = false, inCombat = true }
    assert.is_nil(runtime.lustReady(S, 100))
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
    assert.are.equal(rt2, env2.rt)
    -- re-init (any option edit) reuses the timeline too, under the new host region
    assert.are.equal(old.frame, rt2.tl.frame)
    assert.are.equal(env2.region, rt2.tl.frame.parent)
    local n = #rt2.tl.frame.children
    runtime.start({}, env2)
    assert.are.equal(n, #rt2.tl.frame.children)
  end)

  it("goes to sleep when the host aura hides and wakes up when it shows again", function()
    local rt, env = start()
    runtime.update(rt, 0.3)
    env.region:Show()
    env.region:Hide() -- aura unloaded or disabled
    assert.is_nil(rt.frame.events.COMBAT_LOG_EVENT_UNFILTERED)
    assert.is_nil(rt.tl.frame.scripts.OnUpdate)
    assert.is_false(rt.tl.frame.shown)
    local sent = #G.sent
    rt.frame.scripts.OnUpdate(rt.frame, 1.1) -- a sleeping engine only asks the aura to show now and then
    assert.are.equal(sent + 1, #G.sent)
    assert.are.equal(1, #calls)
    env.region:Show()
    assert.is_true(rt.frame.events.COMBAT_LOG_EVENT_UNFILTERED)
    assert.is_not_nil(rt.tl.frame.scripts.OnUpdate)
    rt.frame.scripts.OnUpdate(rt.frame, 0.01)
    assert.are.equal(2, #calls)
  end)

  it("goes on after a single error and says it once", function()
    local rt = start()
    local boom = true
    rt.planner = { update = function() if boom then boom = false; error("boom", 0) end; return PLAN end }
    assert.is_false(rt.frame.scripts.OnUpdate(rt.frame, 0.3) or false)
    assert.are.equal(1, #G.printed)
    assert.are.equal("|cffff5555EnhRot|r error: boom", G.printed[1])
    assert.are.equal(1, rt.counters.errors)
    assert.is_nil(rt.stopped)
    assert.is_not_nil(rt.frame.scripts.OnUpdate)
    assert.is_true(rt.frame.events.COMBAT_LOG_EVENT_UNFILTERED)
    -- the planner starts afresh and plans again
    local calls = 0
    rt.planner = { update = function() calls = calls + 1; return PLAN end }
    rt.frame.scripts.OnUpdate(rt.frame, 0.3)
    assert.are.equal(1, calls)
    assert.are.equal("stormstrike", rt.plan.steps[1].key)
    assert.are.equal(1, #G.printed)
    -- one long-lived coroutine per guarded function, not one per frame
    local co = rt.guards[runtime.step]
    rt.frame.scripts.OnUpdate(rt.frame, 0.3)
    assert.are.equal(co, rt.guards[runtime.step])
    assert.are.equal("suspended", coroutine.status(co))
  end)

  it("counts a timeline error and starts the timeline again", function()
    local rt = start()
    rt.tl:stop()
    rt.tl.onError()
    assert.are.equal("|cffff5555EnhRot|r error: timeline error", G.printed[1])
    assert.is_true(rt.tl.frame.shown)
    assert.is_nil(rt.stopped)
  end)

  it("says the same error once, and stops after too many in a short time", function()
    local rt = start()
    local fails = 0
    local function broken() return { update = function() fails = fails + 1; error("again", 0) end } end
    for i = 1, runtime.MAX_ERRORS - 1 do
      rt.planner = broken()
      rt.frame.scripts.OnUpdate(rt.frame, 0.3)
      assert.is_nil(rt.stopped)
    end
    assert.are.equal(1, #G.printed)
    rt.planner = broken()
    rt.frame.scripts.OnUpdate(rt.frame, 0.3)
    assert.are.equal(runtime.MAX_ERRORS, fails)
    assert.is_true(rt.stopped)
    assert.are.equal(2, #G.printed)
    assert.are.equal("|cffff5555EnhRot|r stopped after errors - retrying in 30 s or on a new target", G.printed[2])
    -- only the wait for a retry is left: a target change, the time
    assert.are.same({ PLAYER_TARGET_CHANGED = true }, rt.frame.events)
    assert.is_false(rt.tl.frame.shown)
    rt.planner = broken()
    rt.frame.scripts.OnUpdate(rt.frame, 0.3)
    rt.frame.scripts.OnEvent(rt.frame, "UNIT_AURA", "player")
    assert.are.equal(runtime.MAX_ERRORS, fails)
    assert.is_true(rt.stopped)
  end)

  -- five errors in a row, as from one odd target
  local function failNow(rt)
    for i = 1, runtime.MAX_ERRORS do
      rt.planner = { update = function() error("odd target", 0) end }
      rt.frame.scripts.OnUpdate(rt.frame, 0.3)
    end
    assert.is_true(rt.stopped)
  end

  local function running(rt)
    assert.is_nil(rt.stopped)
    assert.is_true(rt.frame.events.COMBAT_LOG_EVENT_UNFILTERED)
    assert.is_true(rt.frame.events.UNIT_AURA)
    assert.is_true(rt.tl.frame.shown)
    -- a fresh planner (not the broken one) plans at once: the restart asks for a replan
    local before = #calls
    rt.frame.scripts.OnUpdate(rt.frame, 0.01)
    assert.are.equal(before + 1, #calls)
    assert.are.equal("target", calls[#calls].ev.kind)
    assert.are.equal("stormstrike", rt.plan.steps[1].key)
  end

  it("after a stop starts again on its own after RETRY_AFTER seconds", function()
    local rt = start()
    rt.env.region:Show()
    failNow(rt)
    rt.frame.scripts.OnUpdate(rt.frame, runtime.RETRY_AFTER - 1)
    assert.is_true(rt.stopped)
    assert.are.equal(0, #calls)
    rt.frame.scripts.OnUpdate(rt.frame, 1)
    running(rt)
    -- the same event handlers as start(): events reach the engine again
    rt.frame.scripts.OnEvent(rt.frame, "PLAYER_ENTER_COMBAT")
    assert.are.equal("swing", rt.pending.kind)
    -- and errors are counted from scratch
    rt.planner = { update = function() error("once", 0) end }
    rt.frame.scripts.OnUpdate(rt.frame, 0.3)
    assert.is_nil(rt.stopped)
  end)

  it("after a stop starts again on a new target", function()
    local rt = start()
    rt.env.region:Show()
    failNow(rt)
    rt.frame.scripts.OnEvent(rt.frame, "UNIT_AURA", "target")
    assert.is_true(rt.stopped)
    rt.frame.scripts.OnEvent(rt.frame, "PLAYER_TARGET_CHANGED")
    running(rt)
  end)

  it("a restart while the aura is hidden goes to sleep", function()
    local rt = start()
    failNow(rt)
    rt.env.region:Hide()
    rt.frame.scripts.OnEvent(rt.frame, "PLAYER_TARGET_CHANGED")
    assert.is_nil(rt.stopped)
    assert.is_true(rt.sleeping)
    assert.are.same({}, rt.frame.events)
    assert.is_false(rt.tl.frame.shown)
    rt.env.region:Show()
    assert.is_false(rt.sleeping)
    assert.is_true(rt.frame.events.UNIT_AURA)
  end)

  it("after MAX_RESTARTS restarts in a session it stays stopped until /reload", function()
    local rt = start()
    rt.env.region:Show()
    for i = 1, runtime.MAX_RESTARTS do
      failNow(rt)
      rt.frame.scripts.OnEvent(rt.frame, "PLAYER_TARGET_CHANGED")
      assert.is_nil(rt.stopped)
    end
    -- a re-init of the aura is the same session
    local frame = rt.frame
    rt = runtime.start(rt.config, rt.env)
    assert.are.equal(frame, rt.frame)
    failNow(rt)
    assert.are.equal("|cffff5555EnhRot|r stopped after an error - /reload to retry", G.printed[#G.printed])
    assert.is_nil(rt.frame.scripts.OnUpdate)
    assert.are.same({}, rt.frame.events)
    rt.frame.scripts.OnEvent(rt.frame, "PLAYER_TARGET_CHANGED")
    assert.is_true(rt.stopped)
    local n = 0
    for _, line in ipairs(G.printed) do if line:find("retrying in", 1, true) then n = n + 1 end end
    assert.are.equal(runtime.MAX_RESTARTS, n)
  end)

  it("does not stop for errors spread over a longer time", function()
    local rt = start()
    for i = 1, runtime.MAX_ERRORS * 2 do
      G.cfg.now = 100 + i * (runtime.ERROR_WINDOW / 2)
      rt.planner = { update = function() error("rare", 0) end }
      rt.frame.scripts.OnUpdate(rt.frame, 0.3)
    end
    assert.is_nil(rt.stopped)
    assert.are.equal(runtime.MAX_ERRORS * 2, rt.counters.errors)
  end)

  it("survives an error in an event handler and in a running search job", function()
    local rt = start()
    local swing = rt.ctx.swing
    rt.ctx.swing = { onAttack = function() error("event boom", 0) end }
    rt.frame.scripts.OnEvent(rt.frame, "PLAYER_ENTER_COMBAT")
    assert.are.equal("|cffff5555EnhRot|r error: event boom", G.printed[1])
    rt.ctx.swing = swing
    rt.frame.scripts.OnEvent(rt.frame, "PLAYER_ENTER_COMBAT")
    assert.are.equal("swing", rt.pending.kind)
    -- a search coroutine that dies raises its error again from job:run
    local job = coroutine.create(function() error("search boom", 0) end)
    rt.planner = { update = function() return PLAN end, busy = function() return true end,
                   work = function() local ok, e = coroutine.resume(job); if not ok then error(e, 0) end end,
                   view = function() return PLAN end }
    rt.frame.scripts.OnUpdate(rt.frame, 0.3)
    assert.is_true(rt.searching)
    rt.frame.scripts.OnUpdate(rt.frame, 0.01)
    assert.are.equal("|cffff5555EnhRot|r error: search boom", G.printed[2])
    assert.is_false(rt.searching)
    assert.is_nil(rt.stopped)
    assert.is_nil(rt.planner.work)
  end)

  it("starts only on a WotLK 3.3.5a client", function()
    install()
    runtime.buildWarned = nil
    _G.GetBuildInfo = function() return "3.3.5", "12340", "Jun 24 2010", 30300 end
    assert.is_true((runtime.supported()))
    local env = { config = {}, region = CreateFrame("Frame"), saved = {} }
    assert.is_not_nil(runtime.start(env.config, env))
    _G.GetBuildInfo = function() return "10.2.0", "52188", "Nov 1 2023", 100200 end
    local ok, msg = runtime.supported()
    assert.is_false(ok)
    assert.truthy(msg:find("supports only WotLK 3.3.5a (build 30300); this client is 10.2.0", 1, true))
    G.printed = {}
    local env2 = { config = {}, region = CreateFrame("Frame"), saved = {} }
    assert.is_nil(runtime.start(env2.config, env2))
    assert.is_nil(runtime.start(env2.config, env2))
    assert.is_nil(env2.rt)
    assert.are.equal(1, #G.printed)
    assert.truthy(G.printed[1]:find("supports only WotLK 3.3.5a", 1, true))
    _G.GetBuildInfo = nil
    runtime.buildWarned = nil
    assert.is_true((runtime.supported()))
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

  -- START already told the planner about the press: the end of the same cast is no new press
  -- (it used to force a full replan exactly when the player pressed the next button)
  it("the end or pushback of a tracked hard cast is reported as done, not as a new press", function()
    local rt = start(nil, { casting = { name = "Lightning Bolt", startMs = 100000, endMs = 101500, castID = 7 } })
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "player", "Lightning Bolt", "Rank 14", 7)
    assert.are.same({ kind = "cast", key = "lightningBolt" }, rt.pending)
    rt.pending = nil
    runtime.onEvent(rt, "UNIT_SPELLCAST_DELAYED", "player", "Lightning Bolt", "Rank 14", 7)
    assert.are.same({ kind = "cast", key = "lightningBolt", done = true }, rt.pending)
    rt.pending = nil
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Lightning Bolt", "Rank 14", 7)
    assert.are.same({ kind = "cast", key = "lightningBolt", done = true }, rt.pending)
    rt.pending = nil
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Earth Shock", "Rank 10")
    assert.are.same({ kind = "cast", key = "earthShock" }, rt.pending)
  end)

  -- SENT comes at the key press; START / SUCCEEDED a round trip later (the client GCD runs already)
  it("takes the press from SENT; the server's confirmation is then no new press", function()
    local rt = start()
    runtime.onEvent(rt, "UNIT_SPELLCAST_SENT", "player", "Earth Shock", "Rank 10", "Mob")
    assert.are.same({ kind = "cast", key = "earthShock" }, rt.pending)
    rt.pending = nil
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Earth Shock", "Rank 10")
    assert.are.same({ kind = "cast", key = "earthShock", done = true }, rt.pending)
    assert.are.same({ "onInstant", 100, "earthShock" }, rt.ctx.swing.calls[1])
    rt.pending = nil
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Earth Shock", "Rank 10") -- no SENT: a press
    assert.are.same({ kind = "cast", key = "earthShock" }, rt.pending)
  end)

  it("a hard cast confirmed by START after SENT is no second press", function()
    local rt = start(nil, { casting = { name = "Lightning Bolt", startMs = 100000, endMs = 101500, castID = 7 } })
    runtime.onEvent(rt, "UNIT_SPELLCAST_SENT", "player", "Lightning Bolt", "Rank 14", "Mob")
    rt.pending = nil
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "player", "Lightning Bolt", "Rank 14", 7)
    assert.are.same({ kind = "cast", key = "lightningBolt", done = true }, rt.pending)
    assert.are.equal("onCastStart", rt.ctx.swing.calls[1][1])
  end)

  -- a second tap during the GCD fails in the client: the first press still counts
  it("a FAILED after SENT does not take the press back; its SUCCEEDED is still no new press", function()
    local rt = start()
    runtime.onEvent(rt, "UNIT_SPELLCAST_SENT", "player", "Stormstrike", "", "Mob")
    rt.pending = nil
    runtime.onEvent(rt, "UNIT_SPELLCAST_FAILED", "player", "Stormstrike", "")
    assert.are.same({ kind = "cast" }, rt.pending)
    rt.pending = nil
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Stormstrike", "")
    assert.are.same({ kind = "cast", key = "stormstrike", done = true }, rt.pending)
  end)

  it("a new press in the same frame wins over the end of the previous cast", function()
    local rt = start(nil, { casting = { name = "Lightning Bolt", startMs = 100000, endMs = 101500, castID = 7 } })
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "player", "Lightning Bolt", "Rank 14", 7)
    rt.pending = nil
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Lightning Bolt", "Rank 14", 7)
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Earth Shock", "Rank 10")
    assert.are.same({ kind = "cast", key = "earthShock" }, rt.pending)
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Lightning Bolt", "Rank 14", 7)
    assert.are.same({ kind = "cast", key = "earthShock" }, rt.pending)
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

  -- 3.3.5a UNIT_SPELLCAST_*: unit, spell name, rank, castID (ElvUI oUF castbar reads it the same way)
  it("a FAILED press during the own cast does not end the cast", function()
    local rt = start(nil, { casting = { name = "Lightning Bolt", startMs = 100000, endMs = 101500, castID = 7 } })
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "player", "Lightning Bolt", "Rank 14", 7)
    runtime.onEvent(rt, "UNIT_SPELLCAST_FAILED", "player", "Lightning Bolt", "Rank 14", 8) -- "Another action is in progress"
    runtime.onEvent(rt, "UNIT_SPELLCAST_FAILED", "player", "Lightning Bolt", "Rank 14")    -- no castID, cast still running
    assert.are.equal(1, #rt.ctx.swing.calls)
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Lightning Bolt", "Rank 14", 7)
    assert.are.same({ "onCastEnd", 100, "lightningBolt", 0, true }, rt.ctx.swing.calls[2])
    assert.are.equal(2, #rt.ctx.swing.calls)
  end)

  it("an INTERRUPTED of another castID is ignored, of the own castID ends the cast", function()
    local rt = start(nil, { casting = { name = "Lightning Bolt", startMs = 100000, endMs = 101500, castID = 7 } })
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "player", "Lightning Bolt", "Rank 14", 7)
    runtime.onEvent(rt, "UNIT_SPELLCAST_INTERRUPTED", "player", "Lightning Bolt", "Rank 14", 6)
    assert.are.equal(1, #rt.ctx.swing.calls)
    runtime.onEvent(rt, "UNIT_SPELLCAST_INTERRUPTED", "player", "Lightning Bolt", "Rank 14", 7)
    assert.are.same({ "onCastEnd", 100, "lightningBolt", 0, false }, rt.ctx.swing.calls[2])
  end)

  it("never calibrates instants on a spell with a cast time (5-stack Lightning Bolt)", function()
    local rt = start()
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Lightning Bolt", "Rank 14", 9)
    assert.are.equal(0, #rt.ctx.swing.calls)
  end)

  it("only SUCCEEDED tells the planner a spell was cast", function()
    local rt = start()
    runtime.onEvent(rt, "UNIT_SPELLCAST_FAILED", "player", "Flame Shock", "Rank 9")
    assert.are.equal("cast", rt.pending.kind)
    assert.is_nil(rt.pending.key)
    rt.pending = nil
    runtime.onEvent(rt, "UNIT_SPELLCAST_INTERRUPTED", "player", "Lightning Bolt", "Rank 14")
    assert.is_nil(rt.pending.key)
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Flame Shock", "Rank 9")
    assert.are.equal("flameShock", rt.pending.key)
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

  it("replans on aura, mana and swing events at most every 0.1 s, on casts at once", function()
    local rt = start()
    runtime.update(rt, 0.3)
    assert.are.equal(1, #calls)
    runtime.onEvent(rt, "UNIT_AURA", "target")
    runtime.update(rt, 0.02)
    assert.are.equal(1, #calls)
    runtime.update(rt, 0.09)
    assert.are.equal(2, #calls)
    assert.are.equal("aura", calls[2].ev.kind)
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Earth Shock", "Rank 10")
    runtime.update(rt, 0.01)
    assert.are.equal(3, #calls)
    runtime.onEvent(rt, "PLAYER_TARGET_CHANGED")
    runtime.update(rt, 0.01)
    assert.are.equal(4, #calls)
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

  for _, case in ipairs({ { "dead or a ghost", { playerDead = true } }, { "on a flight path", { taxi = true } },
                          { "in a vehicle", { vehicle = true } }, { "mounted out of combat", { mounted = true, inCombat = false } } }) do
    it("hides the timeline and does not plan when " .. case[1], function()
      local rt = start(nil, case[2])
      runtime.update(rt, 0.3)
      assert.are.equal(0, #calls)
      assert.is_false(rt.tl.frame.shown)
      for k in pairs(case[2]) do G.cfg[k] = nil end
      rt.pending = { kind = "aura" }
      runtime.update(rt, 0.3)
      assert.are.equal(1, #calls)
      assert.is_true(rt.tl.frame.shown)
    end)
  end

  -- talents are matched by localized names (GetSpellInfo of each talent's rank-1 spell) and English names
  it("warns once in chat when points are spent but no talent is recognized", function()
    local rt = start(nil, { level = 80, talents = { { { "Elementarschutz", 3 } } } })
    assert.are.equal(1, #G.printed)
    assert.truthy(G.printed[1]:find("talents not recognized", 1, true))
    runtime.onEvent(rt, "PLAYER_TALENT_UPDATE")
    assert.are.equal(1, #G.printed)
  end)

  it("reads talents on a Russian client through the spell-id names, without a warning", function()
    local rt = start(nil, { level = 80, spellNames = { [51528] = "Оружие водоворота", [16256] = "Шквал" },
                            talents = { { { "Оружие водоворота", 5 }, { "Шквал", 5 } } } })
    assert.are.equal(0, #G.printed)
    assert.are.equal(5, rt.ctx.cache.talents.maelstromWeapon)
    assert.are.equal(5, rt.ctx.cache.talents.flurry)
    runtime.onEvent(rt, "PLAYER_TALENT_UPDATE")
    assert.are.equal(5, rt.ctx.cache.talents.maelstromWeapon)
  end)

  it("does not warn with no points spent, before talents load, or when a talent is read", function()
    start(nil, { level = 9, talents = {} })
    assert.are.equal(0, #G.printed)
    -- a fresh level 10 (or 80) that has not spent a point, talents listed in any language
    start(nil, { level = 10, talents = { { { "Elementarschutz", 0 }, { "Konvektion", 0 } } } })
    assert.are.equal(0, #G.printed)
    -- at login the client may list no talents yet
    local rt = start(nil, { level = 80, talents = {} })
    assert.are.equal(0, #G.printed)
    G.cfg.talents = { { { "Maelstrom Weapon", 5 } } }
    runtime.onEvent(rt, "PLAYER_TALENT_UPDATE")
    assert.are.equal(0, #G.printed)
    start(nil, { level = 80, talents = { { { "Maelstrom Weapon", 5 } } } })
    assert.are.equal(0, #G.printed)
  end)

  it("plans when mounted in combat", function()
    local rt = start(nil, { mounted = true })
    runtime.update(rt, 0.3)
    assert.are.equal(1, #calls)
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

  -- the press log: the press is taken at SENT, the server's START / SUCCEEDED only confirms it
  it("logs the press at SENT against the shown plan and confirms it at SUCCEEDED", function()
    local rt, env = start({ record = true })
    runtime.update(rt, 0.3) -- shows stormstrike @0 at 100
    G.cfg.now = 100.4
    runtime.onEvent(rt, "UNIT_SPELLCAST_SENT", "player", "Stormstrike", "", "Mob")
    local log = env.saved.enhrotPresses
    assert.are.same({ t = 100.4, key = "stormstrike", sug = "stormstrike", at = 0, hit = true, delay = 0.4 }, log[1])
    assert.are.same({ key = "stormstrike", after = 0.4, matched = true }, env.saved.enhrotSnapshots[1].pressed)
    G.cfg.now = 100.5
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Stormstrike", "")
    assert.are.equal(1, #log)
    assert.is_true(log[1].cf)
    -- SUCCEEDED without SENT: the press itself, logged once
    G.cfg.now = 101
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Earth Shock", "Rank 10")
    assert.are.equal(2, #log)
    assert.are.same({ t = 101, key = "earthShock", sug = "stormstrike", at = 0, hit = false, delay = 1 }, log[2])
  end)

  it("logs a hard cast once: SENT, then START and SUCCEEDED of the same cast", function()
    local rt, env = start({ record = true }, { casting = { name = "Lightning Bolt", startMs = 100000, endMs = 101500, castID = 7 } })
    runtime.update(rt, 0.3)
    runtime.onEvent(rt, "UNIT_SPELLCAST_SENT", "player", "Lightning Bolt", "Rank 14", "Mob")
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "player", "Lightning Bolt", "Rank 14", 7)
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Lightning Bolt", "Rank 14", 7)
    local log = env.saved.enhrotPresses
    assert.are.equal(1, #log)
    assert.are.equal("lightningBolt", log[1].key)
    assert.is_false(log[1].hit)
    assert.is_true(log[1].cf)
  end)

  it("keeps no press log without recording", function()
    local rt, env = start()
    runtime.update(rt, 0.3)
    runtime.onEvent(rt, "UNIT_SPELLCAST_SENT", "player", "Stormstrike", "", "Mob")
    assert.is_nil(env.saved.enhrotPresses)
  end)

  it("counts the delay from the moment the first button became due, not from the last replan", function()
    local rt = {}
    local ss = { steps = { { key = "stormstrike", at = 0.5 } } }
    runtime.trackDue(rt, ss, 100)
    assert.are.same({ key = "stormstrike", at = 100.5 }, rt.due)
    runtime.trackDue(rt, { steps = { { key = "stormstrike", at = 0.2 } } }, 100.4) -- not due yet: new estimate
    assert.are.near(100.6, rt.due.at, 1e-9)
    runtime.trackDue(rt, { steps = { { key = "stormstrike", at = 0 } } }, 101) -- due since 100.6
    assert.are.near(100.6, rt.due.at, 1e-9)
    runtime.trackDue(rt, { steps = { { key = "lavaLash", at = 0 } } }, 101.5)
    assert.are.same({ key = "lavaLash", at = 101.5 }, rt.due)
    runtime.trackDue(rt, { steps = {} }, 102)
    assert.is_nil(rt.due)
  end)

  it("exports the addon version, snapshots and presses", function()
    install()
    local saved = { enhrotSnapshots = { { S = { now = 1 }, plan = { steps = {} } } },
                    enhrotPresses = { { t = 1, key = "stormstrike" } } }
    local w = runtime.showExport({ saved = saved })
    local d = require("build").decodeExportFull(w.box.text)
    assert.are.equal(runtime.VERSION, d.version)
    assert.are.equal("dev", runtime.VERSION)
    assert.are.same(saved.enhrotSnapshots, d.snapshots)
    assert.are.same(saved.enhrotPresses, d.presses)
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

  it("keeps the Fire Elemental that the player's totem summons", function()
    local rt = start()
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SPELL_SUMMON", "Player-1", "Me", 0x511, "Creature-78", "Fire Elemental Totem", 0x2111, 2894, "Fire Elemental Totem", 4)
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SPELL_SUMMON", "Creature-78", "Fire Elemental Totem", 0x2111, "Creature-79", "Greater Fire Elemental", 0x1111, 32982, "Fire Elemental Totem", 4)
    assert.is_true(rt.mine["Creature-79"])
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SWING_DAMAGE", "Creature-79", "Greater Fire Elemental", 0x1111, "Creature-3", "B", 0xa48, 500)
    assert.are.equal("Creature-79", rt.ctx.enemies.calls[#rt.ctx.enemies.calls][3])
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

describe("runtime with the real planner and a search over several frames", function()
  it("keeps showing the current plan while a search runs and shows the new one when it is done", function()
    install()
    local rtm = require("runtime")
    local env = { config = {}, region = CreateFrame("Frame"), saved = {} }
    local rt = rtm.start({}, env)
    rt.ctx.swing = spy()
    rt.ctx.enemies = enemiesSpy()
    local key, runs = "stormstrike", 0
    local search = {
      start = function()
        local left, k = 3, key
        return { run = function(job)
          runs = runs + 1
          left = left - 1
          if left > 0 then return false end
          job.result = { value = 100, steps = { { key = k, at = 0, reason = "" } } }
          return true
        end }
      end,
      evaluate = function() return nil end,
    }
    local realPlanner = real.planner or require("planner")
    rt.planner = realPlanner.new({ search = search, budgetMs = 2 })
    rtm.update(rt, 0.3) -- first slice
    assert.are.equal(0, #rt.plan.steps)
    rtm.update(rt, 0.016)
    assert.are.equal(0, #rt.plan.steps)
    rtm.update(rt, 0.016)
    assert.are.equal("stormstrike", rt.plan.steps[1].key)
    assert.are.equal(rt.plan, rt.tl.plan)
    key = "lavaLash"
    rt.pending = { kind = "target" }
    rtm.update(rt, 0.016)
    rtm.update(rt, 0.016)
    assert.are.equal("stormstrike", rt.plan.steps[1].key)
    rtm.update(rt, 0.016)
    assert.are.equal("lavaLash", rt.plan.steps[1].key)
    assert.are.equal(6, runs)
    rtm.update(rt, 0.016) -- nothing left to run
    assert.are.equal(6, runs)
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
