local G = require("game_mock")
local guide = require("guide")

local function item(id, log)
  return { id = id,
           show = function(close) log[#log + 1] = "show " .. id; log[id] = close end,
           hide = function() log[#log + 1] = "hide " .. id end }
end

describe("message queue", function()
  local fighting, q, log
  before_each(function()
    fighting, log = false, {}
    q = guide.new({ fighting = function() return fighting end })
  end)

  it("one window at a time, in order", function()
    assert.is_true(q:push(item("wizard", log)))
    assert.is_true(q:push(item("card10", log)))
    assert.are.same({ "show wizard" }, { log[1], log[2] })
    log.wizard()
    assert.are.equal("show card10", log[2])
    log.card10()
    assert.is_nil(q.current)
  end)

  it("nothing opens in a fight; a fight hides the open one and brings it back after", function()
    fighting = true
    q:push(item("wizard", log))
    assert.are.equal(0, #log)
    fighting = false
    q:pump()
    assert.are.equal("show wizard", log[1])
    fighting = true
    q:combat()
    assert.are.equal("hide wizard", log[2])
    q:pump()
    assert.are.equal(2, #log)
    fighting = false
    q:pump()
    assert.are.equal("show wizard", log[3])
  end)

  it("a close left over from before a fight does not close the window shown again", function()
    q:push(item("wizard", log))
    local stale = log.wizard
    fighting = true
    q:combat()
    fighting = false
    q:pump()
    q:push(item("card30", log))
    stale()
    assert.are.equal("wizard", q.current.id)
    log.wizard()
    assert.are.equal("card30", q.current.id)
  end)

  it("the same message is not queued twice", function()
    q:push(item("card20", log))
    assert.is_false(q:push(item("card20", log)))
    q:push(item("wizard", log))
    assert.is_false(q:push(item("wizard", log)))
    assert.are.equal(1, #q.items)
  end)

  it("follows the fight events of its frame; by default the client says who fights", function()
    G.install({ inCombat = false, lockdown = true })
    local real = guide.new()
    local f = CreateFrame("Frame")
    real:start(f)
    assert.is_true(f.events.PLAYER_REGEN_DISABLED)
    assert.is_true(f.events.PLAYER_REGEN_ENABLED)
    real:push(item("wizard", log))
    assert.are.equal(0, #log)
    G.cfg.lockdown = false
    f.scripts.OnEvent(f, "PLAYER_REGEN_ENABLED")
    assert.are.equal("show wizard", log[1])
    f.scripts.OnEvent(f, "PLAYER_REGEN_DISABLED")
    assert.are.equal("hide wizard", log[2])
  end)
end)
