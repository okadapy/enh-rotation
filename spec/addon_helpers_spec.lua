local G = require("game_mock")

-- the helpers have their own specs: here they are stand-ins that record what helpers gives them
local made = {}
local function stub(name, extra)
  local m = extra or {}
  m.new = function(deps)
    local o = { deps = deps, name = name }
    function o:start(frame) self.frame = frame end
    function o:open() self.opened = true end
    function o:hotkey(k) return k == "stormstrike" and "S-E" or nil end
    made[name] = o
    return o
  end
  return m
end
package.loaded.highlight = stub("highlight", { OPTIONS = { { key = "highlightButtons" }, { key = "showKeybind" } } })
package.loaded.explain = stub("explain", { OPTION = { key = "hoverTips" } })
package.loaded.ready = stub("ready", { OPTIONS = { { key = "readyCheck" }, { key = "rankWarning" } } })
package.loaded.helpers = nil

local helpers = require("helpers")

describe("addon helpers", function()
  before_each(function()
    G.install({})
    _G.GameTooltip = { name = "GameTooltip" }
    made = {}
  end)

  it("their options, in order", function()
    local keys = {}
    for i, o in ipairs(helpers.options()) do keys[i] = o.key end
    assert.are.same({ "highlightButtons", "showKeybind", "hoverTips", "readyCheck", "rankWarning" }, keys)
  end)

  it("start runs each on a frame of its own, reading the engine through core.view", function()
    local view = {}
    local said = {}
    local core = { view = function() return view end, db = { config = { hoverTips = false } } }
    local h = helpers.start(core, function(line) said[#said + 1] = line end)
    assert.are.equal(DoubtMyRotationHighlight, made.highlight.frame)
    assert.are.equal(DoubtMyRotationExplain, made.explain.frame)
    assert.are.equal(DoubtMyRotationChecks, made.ready.frame)
    assert.are.equal(made.highlight, h.highlight)
    assert.are.equal(made.explain, h.explain)
    assert.are.equal(made.ready, h.ready)
    assert.are.equal(view, made.highlight.deps.view())
    assert.are.equal(core.db.config, made.highlight.deps.config())
    assert.are.equal(100, made.highlight.deps.now())
    assert.is_false(made.explain.deps.enabled())
    core.db.config.hoverTips = nil
    assert.is_true(made.explain.deps.enabled())
    assert.are.equal("S-E", made.explain.deps.hotkey("stormstrike"))
    assert.is_nil(made.explain.deps.hotkey("lightningBolt"))
    assert.are.equal(GameTooltip, made.explain.deps.tooltip)
    -- the mock client has no IsShiftKeyDown: no Shift, no error
    assert.is_falsy(made.explain.deps.shift())
    _G.IsShiftKeyDown = function() return 1 end
    assert.is_truthy(made.explain.deps.shift())
    assert.is_truthy(made.explain.deps.inCombat()) -- the mock is in combat unless told otherwise
    G.install({ inCombat = false })
    assert.is_falsy(made.explain.deps.inCombat())
    assert.are.equal(core.db, made.ready.deps.db)
    made.ready.deps.say("hi")
    assert.are.same({ "hi" }, said)
    h.check()
    assert.is_true(made.ready.opened)
  end)

  it("a settings change reaches them without a restart: config is read on every call", function()
    local core = { view = function() end, db = { config = {} } }
    helpers.start(core, function() end)
    core.db = { config = { hoverTips = false } } -- /dmr reset replaces the table
    assert.is_false(made.explain.deps.enabled())
    assert.are.equal(core.db.config, made.ready.deps.config())
  end)

  it("frames that already exist are taken again, not made anew", function()
    local f = CreateFrame("Frame", "DoubtMyRotationHighlight")
    helpers.start({ view = function() end, db = { config = {} } }, function() end)
    assert.are.equal(f, made.highlight.frame)
  end)
end)
