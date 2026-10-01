local G = require("game_mock")
-- addon/cards.lua has its own spec: here a stand-in with a card every 10 levels
package.loaded.cards = {
  firstRun = function(level, seen) for l = 10, level, 10 do seen[l] = true end end,
  due = function(level, seen)
    local l = math.floor(level / 10) * 10
    if l >= 10 and not seen[l] then return { level = l } end
  end,
}
local coach = require("coach")
local guide = require("guide")

local function setup(opts)
  opts = opts or {}
  local s = { opened = {}, cardsOn = opts.cardsOn ~= false, level = opts.level or 1 }
  s.db, s.char = opts.db or {}, opts.char or {}
  s.q = guide.new({ fighting = function() return false end })
  s.wizard = { open = function(_, close) s.opened[#s.opened + 1] = "wizard"; s.close = close end, hide = function() end }
  s.card = { open = function(_, card, close) s.opened[#s.opened + 1] = "card" .. card.level; s.close = close end,
             hide = function() end }
  s.c = coach.new({ guide = s.q, db = s.db, char = s.char, level = function() return s.level end,
                    enabled = function(key) return key ~= "levelCards" or s.cardsOn end,
                    wizard = function() return s.wizard end, card = function() return s.card end })
  return s
end

describe("guide and cards schedule", function()
  it("a new character: the guide on login, nothing behind it to catch up on", function()
    local s = setup({ level = 1 })
    s.c:login()
    assert.are.same({ "wizard" }, s.opened)
    assert.are.same({}, s.char.cards)
  end)

  it("a grown character: the cards behind it count as seen, none shows on login", function()
    local s = setup({ level = 45, char = { wizard = "done" } })
    s.c:login()
    assert.are.same({}, s.opened)
    assert.are.same({ [10] = true, [20] = true, [30] = true, [40] = true }, s.char.cards)
    s.char.cards[50] = nil
    s.c:login() -- the second login leaves the record alone
    assert.is_nil(s.char.cards[50])
  end)

  it("the guide stays away once done here, or turned off for the account", function()
    local s = setup({ char = { wizard = "done" } })
    s.c:login()
    local t = setup({ db = { wizardOff = true } })
    t.c:login()
    assert.are.same({}, s.opened)
    assert.are.same({}, t.opened)
  end)

  it("a level brings its card; closing it marks it seen", function()
    local s = setup({ level = 19, char = { wizard = "done" } })
    s.c:login()
    s.c:levelUp(20)
    assert.are.same({ "card20" }, s.opened)
    assert.is_nil(s.char.cards[20])
    s.close()
    assert.is_true(s.char.cards[20])
    s.c:levelUp(21)
    assert.are.same({ "card20" }, s.opened)
  end)

  it("cards off: the levels passed count as seen, nothing shows", function()
    local s = setup({ level = 29, cardsOn = false, char = { wizard = "done" } })
    s.c:login()
    s.c:levelUp(30)
    assert.are.same({}, s.opened)
    assert.is_true(s.char.cards[30])
  end)

  it("/dmr guide brings the guide back even when done", function()
    local s = setup({ char = { wizard = "done" } })
    s.c:login()
    s.c:openGuide()
    assert.are.same({ "wizard" }, s.opened)
  end)

  -- UnitLevel still gives the old level while PLAYER_LEVEL_UP runs
  it("takes the new level from PLAYER_LEVEL_UP itself", function()
    G.install({})
    local s = setup({ level = 9, char = { wizard = "done" } })
    s.c:login()
    local f = CreateFrame("Frame")
    s.c:start(f)
    assert.is_true(f.events.PLAYER_LEVEL_UP)
    f.scripts.OnEvent(f, "PLAYER_LEVEL_UP", 10)
    assert.are.same({ "card10" }, s.opened)
  end)
end)
