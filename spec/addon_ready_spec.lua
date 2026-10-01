local G = require("game_mock")
local spells = require("spells")
local data = require("spells_data")
local ready = require("ready")

local function rankAt(key, level)
  local n = 0
  for i, r in ipairs(data[key]) do if r.level <= level then n = i end end
  return n
end

-- everything learned at its newest rank for the level
local function knownAt(level)
  local k = {}
  for _, key in ipairs(spells.KEYS) do
    local n = rankAt(key, level)
    if n > 0 then k[key] = { id = spells.byKey[key].ranks[n], rank = n } end
  end
  return k
end

local function S(over)
  local s = { weapons = { mh = { enchant = "wf" }, oh = { enchant = "ft" } }, player = { shield = "lightning" },
              spells = { lightningShield = { cd = 0 } }, shieldPref = "auto" }
  for k, v in pairs(over or {}) do s[k] = v end
  return s
end

local function info(over)
  local i = { level = 80, S = S(), known = knownAt(80), talents = { spent = 71, listed = 80, recognized = true },
              call = { true, true, true, true } }
  for k, v in pairs(over or {}) do i[k] = v end
  return i
end

local function byKey(items)
  local out = {}
  for _, it in ipairs(items) do out[it.key] = it end
  return out
end

describe("ready: ranks", function()
  it("a spell one rank behind the level is listed, with the rank to buy", function()
    local known = knownAt(40)
    known.lightningBolt = { id = spells.byKey.lightningBolt.ranks[1], rank = 1 }
    local list = ready.ranks(40, known)
    assert.are.equal(1, #list)
    assert.are.same({ "lightningBolt", "Lightning Bolt", 1, rankAt("lightningBolt", 40) },
                    { list[1].key, list[1].name, list[1].have, list[1].want })
  end)

  it("a spell not learned at all counts; talent spells never do", function()
    local known = knownAt(80)
    known.earthShock, known.stormstrike, known.feralSpirit = nil, nil, nil
    local list = ready.ranks(80, known)
    assert.are.equal(1, #list)
    assert.are.equal("earthShock", list[1].key)
    assert.are.equal(0, list[1].have)
  end)

  it("the localized name when the client gave one", function()
    local known = knownAt(80)
    known.earthShock = nil
    assert.are.equal("Erdschock", ready.ranks(80, known, { earthShock = "Erdschock" })[1].name)
  end)

  it("up to date: nothing", function()
    for _, lvl in ipairs({ 1, 10, 30, 60, 80 }) do assert.are.same({}, ready.ranks(lvl, knownAt(lvl)), lvl) end
  end)

  it("the chat line names a few and counts the rest", function()
    local list = {}
    for i = 1, 6 do list[i] = { name = "Spell" .. i, have = i % 2, want = 3 } end
    assert.are.equal("the trainer has new ranks: Spell1 3, Spell2 (new), Spell3 3, Spell4 (new), +2 more - /dmr check",
                     ready.rankLine(list))
    assert.is_nil(ready.rankLine({}))
  end)
end)

describe("ready: the checklist", function()
  it("all green when all is there", function()
    for _, it in ipairs(ready.items(info())) do assert.is_true(it.ok, it.key); assert.is_nil(it.hint) end
  end)

  it("a missing imbue says which one to cast, by level", function()
    local s = S({ weapons = { mh = { enchant = nil }, oh = { enchant = nil } } })
    local it = byKey(ready.items(info({ S = s })))
    assert.are.equal("Cast Windfury Weapon on the main hand", it.mh.hint)
    assert.are.equal("Cast Flametongue Weapon on the off hand", it.oh.hint)
    it = byKey(ready.items(info({ S = s, level = 20, known = knownAt(20) })))
    assert.are.equal("Cast Flametongue Weapon on the main hand", it.mh.hint)
  end)

  it("no off hand weapon: no off hand row", function()
    local it = byKey(ready.items(info({ S = S({ weapons = { mh = { enchant = "wf", twoHand = true } } }) })))
    assert.is_nil(it.oh)
  end)

  it("no shield up: the one the settings want", function()
    local it = byKey(ready.items(info({ S = S({ player = {}, shieldPref = "water" }) })))
    assert.are.equal("Cast Water Shield", it.shield.hint)
  end)

  it("Call of the Elements: from 30, each empty element named", function()
    local it = byKey(ready.items(info({ call = { true, false, true, false } })))
    assert.is_false(it.totems.ok)
    assert.are.equal("Put a totem on each empty slot of the totem bar: Earth, Air", it.totems.hint)
    assert.is_nil(byKey(ready.items(info({ level = 29, known = knownAt(29), call = nil }))).totems)
  end)

  it("talents: none spent, or not recognized", function()
    local it = byKey(ready.items(info({ talents = { spent = 0, listed = 80, recognized = false } })))
    assert.are.equal("Spend your talent points", it.talents.hint)
    it = byKey(ready.items(info({ talents = { spent = 40, listed = 80, recognized = false } })))
    assert.are.equal("Talents not recognized - unsupported client language?", it.talents.hint)
    assert.is_nil(byKey(ready.items(info({ talents = { spent = 0, listed = 0, recognized = false } }))).talents)
  end)

  it("old ranks: visit the trainer", function()
    local known = knownAt(80)
    known.lightningBolt.rank = 10
    local it = byKey(ready.items(info({ known = known })))
    assert.are.equal("Visit the trainer: Lightning Bolt", it.ranks.hint)
  end)
end)

describe("ready: in game", function()
  local said, db, now, cfg, combat
  local function checker(snapshot)
    G.install({ level = 80 })
    said, db, now, cfg, combat = {}, {}, 100, { readyCheck = true, rankWarning = true }, false
    _G.DoubtMyRotationReady = nil
    _G.HasAction = function(slot) return slot >= 133 and slot <= 136 and 1 or nil end
    _G.NUM_ACTIONBAR_PAGES = 6
    _G.GetMultiCastBarOffset = function() return 6 end
    local known = knownAt(80)
    known.lightningBolt.rank = 10
    local v = { S = snapshot or S(), cache = { known = known, names = {}, talents = { x = 1 } } }
    local c = ready.new({ view = function() return v end, config = function() return cfg end, db = db,
                          say = function(l) said[#said + 1] = l end, now = function() return now end,
                          inCombat = function() return combat end })
    local f = CreateFrame("Frame")
    c:start(f)
    return c, f, v
  end
  local function after(f, s) now = now + s; f.scripts.OnUpdate(f, s) end

  it("the first login: the checklist once, a rank line, both after a short delay", function()
    local _, f = checker()
    after(f, 1)
    assert.is_nil(DoubtMyRotationReady)
    after(f, ready.DELAY)
    assert.is_true(DoubtMyRotationReady:IsShown())
    assert.is_true(db.readySeen)
    assert.are.equal(1, #said)
    assert.is_truthy(said[1]:find("Lightning Bolt", 1, true))
  end)

  it("the next login: no window, the rank line again and one line that something is red", function()
    local _, f = checker()
    db.readySeen = true
    after(f, ready.DELAY + 1)
    assert.is_nil(DoubtMyRotationReady)
    assert.are.equal(2, #said)
    assert.is_truthy(said[1]:find("Lightning Bolt", 1, true))
    assert.are.equal(ready.NOT_READY, said[2])
    assert.are.equal("something is not ready yet - /dmr check", ready.NOT_READY)
  end)

  it("the next login with everything green: nothing in the chat", function()
    local _, f, v = checker()
    db.readySeen = true
    v.cache.known.lightningBolt.rank = rankAt("lightningBolt", 80)
    after(f, ready.DELAY + 1)
    assert.is_nil(DoubtMyRotationReady)
    assert.are.same({}, said)
  end)

  it("the 'not ready' line waits for the end of a fight and comes once a session", function()
    local c, f = checker()
    db.readySeen = true
    combat = true
    after(f, ready.DELAY + 1)
    assert.are.equal(1, #said) -- the rank line does not wait
    combat = false
    c:onEvent("PLAYER_REGEN_ENABLED")
    after(f, 0.1)
    assert.are.equal(2, #said)
    assert.are.equal(ready.NOT_READY, said[2])
    c:onEvent("PLAYER_LEVEL_UP", 80)
    after(f, ready.DELAY + 1)
    c:onEvent("PLAYER_REGEN_ENABLED")
    after(f, 0.1)
    assert.are.equal(2, #said)
    assert.is_nil(DoubtMyRotationReady)
  end)

  it("readyCheck off: no 'not ready' line, the rank line stays", function()
    local _, f = checker()
    db.readySeen = true
    cfg.readyCheck = false
    after(f, ready.DELAY + 1)
    assert.are.equal(1, #said)
    assert.is_truthy(said[1]:find("Lightning Bolt", 1, true))
  end)

  it("the rank line on a level up is for the level the event gives", function()
    local c, f, v = checker()
    after(f, ready.DELAY + 1)
    c:onEvent("PLAYER_LEVEL_UP", 74)
    after(f, ready.DELAY + 1)
    assert.are.equal(2, #said)
    assert.are.equal(ready.rankLine(ready.ranks(74, v.cache.known)), said[2])
    assert.are_not.equal(said[1], said[2])
  end)

  it("no snapshot yet: tries again a second later; /dmr check says so", function()
    local c, f, v = checker()
    local snap = v.S
    v.S = nil
    after(f, ready.DELAY + 1)
    assert.is_nil(DoubtMyRotationReady)
    assert.are.same({}, said)
    c:open()
    assert.are.same({ "no data yet - try again in a moment" }, said)
    v.S = snap
    after(f, 0.5)
    assert.is_nil(DoubtMyRotationReady)
    after(f, 0.6)
    assert.is_true(DoubtMyRotationReady:IsShown())
  end)

  it("in combat at login: the window waits for the end of the fight", function()
    local c, f = checker()
    combat = true
    after(f, ready.DELAY + 1)
    assert.is_nil(DoubtMyRotationReady)
    combat = false
    c:onEvent("PLAYER_REGEN_ENABLED")
    after(f, 0.1)
    assert.is_true(DoubtMyRotationReady:IsShown())
  end)

  it("a level up says the line for the new level, the same line only once a session", function()
    local c, f = checker()
    after(f, ready.DELAY + 1)
    c:onEvent("PLAYER_LEVEL_UP", 80)
    after(f, ready.DELAY + 1)
    assert.are.equal(1, #said)
  end)

  it("options off: no window, no line", function()
    local _, f = checker()
    cfg.readyCheck, cfg.rankWarning = false, false
    after(f, ready.DELAY + 1)
    assert.is_nil(DoubtMyRotationReady)
    assert.are.equal(0, #said)
  end)

  it("/dmr check opens it any time; it turns green while open", function()
    local snap = S({ weapons = { mh = { enchant = nil }, oh = { enchant = "ft" } } })
    local c, f = checker(snap)
    db.readySeen = true
    c:open()
    local w = DoubtMyRotationReady
    assert.are.equal(ready.ICON_NO, w.rows[1].icon.texture)
    snap.weapons.mh.enchant = "wf"
    after(f, 1.1)
    assert.are.equal(ready.ICON_OK, w.rows[1].icon.texture)
  end)

  it("gather reads Call of the Elements from slots 133-136", function()
    local _, _, v = checker()
    v.cache.known.callOfElements = { id = 66842, rank = 1 }
    local asked = {}
    _G.HasAction = function(slot) asked[#asked + 1] = slot; return slot ~= 136 and 1 or nil end
    local i = ready.gather(v)
    assert.are.same({ 133, 134, 135, 136 }, asked)
    assert.are.same({ true, true, true, false }, i.call)
    assert.are.equal(80, i.level)
  end)
end)
