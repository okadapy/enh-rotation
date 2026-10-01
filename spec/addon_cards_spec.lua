local G = require("game_mock")
local P = require("panel_mock")
local cards = require("cards")
local spells = require("spells")
local talents = require("talents")

local function levels()
  local out = {}
  for i, c in ipairs(cards.CARDS) do out[i] = c.level end
  return out
end

describe("level cards", function()
  it("eight cards, at 10 to 80", function()
    assert.are.same({ 10, 20, 30, 40, 50, 60, 70, 80 }, levels())
    for _, c in ipairs(cards.CARDS) do
      assert.is_string(c.title)
      assert.is_string(c.text)
    end
  end)

  -- talents come on the standard leveling path (src/talents.lua M.STANDARD), not at the spell's rank level
  it("the levels and numbers in the text come from the spell and talent data", function()
    assert.are.equal("40", cards.text("{lvl:stormstrike}"))
    assert.are.equal("45", cards.text("{lvl:lavaLash}"))
    assert.are.equal("50", cards.text("{lvl:shamanisticRage}"))
    assert.are.equal("60", cards.text("{lvl:feralSpirit}"))
    assert.are.equal("55", cards.text("{lvl:maelstromWeapon}"))
    assert.are.equal("41", cards.text("{lvl:dualWield}"))
    assert.are.equal("68", cards.text("{lvl:fireElemental}"))
    assert.are.equal("3 min", cards.text("{cd:feralSpirit}"))
    assert.are.equal("10 min", cards.text("{cd:fireElemental}"))
    assert.are.equal("1 min", cards.text("{cd:shamanisticRage}"))
    assert.are.equal("6 s", cards.text("{cd:earthShock}"))
    assert.are.equal("18 s", cards.text("{dur:flameShock}"))
    assert.are.equal("2 min", cards.text("{dur:fireElemental}"))
    assert.are.equal("4", cards.text("{charges:stormstrike}"))
    assert.are.equal("20", cards.text("{bonus:stormstrike}"))
    assert.are.equal("3", cards.text("{targets:chainLightning}"))
    assert.has_error(function() cards.text("{cd:noSuchSpell}") end)
    assert.has_error(function() cards.text("{what:stormstrike}") end)
  end)

  it("every card's text resolves", function()
    for _, c in ipairs(cards.CARDS) do
      local t = cards.text(c.text)
      assert.is_nil(t:find("{", 1, true), c.level)
    end
  end)

  -- every number in a text is a substitution from the data, none typed by hand
  it("no number in a card's text outside the substitutions", function()
    for _, c in ipairs(cards.CARDS) do
      local bare = c.text:gsub("{%a+:%a+}", "")
      assert.is_nil(bare:find("%d"), ("a number on the level %d card: %s"):format(c.level, bare))
      for _, word in ipairs({ "two", "three", "four", "five" }) do
        assert.is_nil(bare:lower():find("%f[%a]" .. word .. "%f[%A]"), ("'%s' on the level %d card"):format(word, c.level))
      end
    end
  end)

  -- no invented facts: a card names a spell or a talent only once the player can have it
  it("no spell or talent in a card before its level", function()
    for _, c in ipairs(cards.CARDS) do
      local t = cards.text(c.title .. " " .. c.text)
      for _, s in ipairs(spells.CATALOG) do
        if t:find(s.name, 1, true) then
          assert.is_true(cards.learned(s.key) <= c.level, ("%s on the level %d card"):format(s.name, c.level))
        end
      end
      for _, k in ipairs(talents.KEYS) do
        if t:find(k.name, 1, true) then
          local l = cards.talentLevel(k.key)
          assert.is_true(l ~= nil and l <= c.level, ("%s on the level %d card"):format(k.name, c.level))
        end
      end
      for name, l in pairs(cards.HAND_LEVELS) do
        if t:find(name, 1, true) then assert.is_true(l <= c.level, ("%s on the level %d card"):format(name, c.level)) end
      end
    end
  end)

  it("what is new since the previous card, every spell on exactly one card", function()
    local function keys(list)
      local out = {}
      for i, s in ipairs(list) do out[i] = s.key end
      return out
    end
    assert.are.same({ "lightningBolt", "earthShock", "lightningShield", "flameShock", "searingTotem" }, keys(cards.newSince(0, 10)))
    assert.are.same({ "lavaLash", "shamanisticRage" }, keys(cards.newSince(40, 50)))
    assert.are.same({ "feralSpirit" }, keys(cards.newSince(50, 60)))
    assert.are.equal(0, cards.previous(10))
    assert.are.equal(40, cards.previous(50))
    local count = 0
    for _, c in ipairs(cards.CARDS) do count = count + #cards.newSince(cards.previous(c.level), c.level) end
    assert.are.equal(#spells.CATALOG, count)
  end)

  it("one card at a time: the newest unseen, older ones count as seen", function()
    local seen = {}
    assert.is_nil(cards.due(9, seen))
    assert.are.equal(10, cards.due(10, seen).level)
    assert.is_nil(seen[10]) -- marked when the player closes it
    assert.are.equal(30, cards.due(35, seen).level)
    assert.is_true(seen[10])
    assert.is_true(seen[20])
    assert.is_nil(seen[30])
    seen[30] = true
    assert.is_nil(cards.due(39, seen))
    local grown = {}
    cards.firstRun(45, grown)
    assert.are.same({ [10] = true, [20] = true, [30] = true, [40] = true }, grown)
    assert.are.equal(50, cards.due(50, grown).level)
  end)
end)

describe("level card window", function()
  local h
  before_each(function()
    G.install({})
    P.install()
    cards.frame = nil
    h = { cfg = { levelCards = true }, sets = {} }
    h.config = function() return h.cfg end
    h.set = function(k, v) h.sets[#h.sets + 1] = { k, v } end
  end)

  it("shows the card with the new spells; OK closes it once", function()
    local w = cards.window(h)
    assert.are.equal(w, DoubtMyRotationCard)
    assert.are.equal(w, cards.window(h))
    local closed = 0
    w:open(cards.CARDS[5], function() closed = closed + 1 end)
    assert.is_true(w:IsShown())
    assert.are.equal(cards.CARDS[5].title, w.title.text)
    assert.are.equal(cards.text(cards.CARDS[5].text), w.text.text)
    assert.are.equal("New since level 40: Lava Lash, Shamanistic Rage", w.names.text)
    assert.are.equal(spells.byKey.lavaLash.icon, w.icons[1].texture)
    assert.is_true(w.icons[2].shown)
    assert.is_false(w.icons[3].shown)
    w.ok:Click()
    assert.is_false(w:IsShown())
    assert.are.equal(1, closed)
    for _, x in ipairs(w.widgets) do assert.is_string(x.kind) end
  end)

  it("the check box turns the cards off; a fight hides it without closing; Escape closes", function()
    local w = cards.window(h)
    local closed = 0
    w:open(cards.CARDS[1], function() closed = closed + 1 end)
    assert.is_true(w.again:GetChecked() == 1)
    w.again:SetChecked(false)
    w.again:Click()
    assert.are.same({ { "levelCards", false } }, h.sets)
    w:hide()
    assert.are.equal(0, closed)
    w:open(cards.CARDS[1], function() closed = closed + 1 end)
    w:Hide() -- Escape (UISpecialFrames)
    assert.are.equal(1, closed)
    assert.are.equal("DoubtMyRotationCard", UISpecialFrames[1])
  end)
end)
