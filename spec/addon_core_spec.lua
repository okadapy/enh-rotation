local G = require("game_mock")

-- the settings window (addon/panel.lua) and the update check (addon/update.lua) have their own
-- specs: here they are stand-ins that record what core gives them
local panels, checkers = {}, {}
package.loaded.panel = {
  new = function(o, host)
    local f = CreateFrame("Frame", "DoubtMyRotationPanel")
    f.o, f.host = o, host
    panels[#panels + 1] = f
    return f
  end,
}
package.loaded.update = {
  OPTION = { type = "toggle", key = "updateCheck", name = "Tell me when a newer version is out", default = true },
  new = function(version, deps)
    local c = { version = version, deps = deps }
    function c:start(frame) self.frame = frame end
    checkers[#checkers + 1] = c
    return c
  end,
}

local helperRuns = {}
package.loaded.helpers = {
  options = function() return { { type = "toggle", key = "highlightButtons", name = "Light up", default = true } } end,
  start = function(core, say)
    local h = { core = core, say = say, checks = 0 }
    h.check = function() h.checks = h.checks + 1 end
    helperRuns[#helperRuns + 1] = h
    return h
  end,
}

local core = require("core")
local settings = require("settings")
local spells = require("spells")
local runtime = require("runtime")

local function opts()
  local aura = require("aura")
  local list = {}
  for _, o in ipairs(aura.OPTIONS) do if o.key ~= "export" then list[#list + 1] = o end end
  return { options = list, width = aura.WIDTH, height = aura.HEIGHT,
           libs = { serialize = require("LibSerialize"), deflate = require("LibDeflate") } }
end

local function shaman(extra)
  local known = {}
  for _, meta in ipairs(spells.CATALOG) do known[meta.ranks[#meta.ranks]] = true end
  local cfg = { now = 100, known = known, target = { level = 83, hp = 1e6, hpMax = 1e6, guid = "Creature-9" } }
  for k, v in pairs(extra or {}) do cfg[k] = v end
  G.install(cfg)
end

local function login(o, db)
  _G.DoubtMyRotationDB = db
  local loader = core.boot(o)
  loader.scripts.OnEvent(loader, "ADDON_LOADED", "DoubtMyRotation")
  loader.scripts.OnEvent(loader, "PLAYER_LOGIN")
  return loader
end

describe("addon core", function()
  before_each(function()
    core.db, core.frame, core.env, core.rt, core.panel, core.updates, core.due = nil, nil, nil, nil, nil, nil, nil
    panels, checkers = {}, {}
    core.helpers, helperRuns = nil, {}
  end)

  it("a shaman gets the timeline frame and a running engine on login", function()
    shaman()
    local o = opts()
    login(o)
    assert.are.equal(core, DoubtMyRotationAddon)
    assert.are.equal("/dmr", SLASH_DOUBTMYROTATION1)
    assert.are.same(settings.defaults(o.options), DoubtMyRotationDB.config)
    assert.are.equal(DoubtMyRotationFrame, core.frame)
    assert.is_true(core.frame.shown)
    assert.are.equal(core.frame, core.env.region)
    assert.are.equal(DoubtMyRotationDB.saved, core.env.saved)
    assert.are.equal(o.libs, core.env.libs)
    assert.is_nil(core.env.show)
    assert.is_not_nil(core.rt)
  end)

  it("anyone else gets nothing, and /dmr says why", function()
    shaman({ class = "MAGE" })
    login(opts())
    assert.is_nil(core.frame)
    assert.is_nil(core.rt)
    assert.are.equal(0, #panels)
    assert.are.equal(0, #checkers)
    SlashCmdList.DOUBTMYROTATION("list")
    assert.are.equal("|cff33ff99DoubtMyRotation|r shaman only", G.printed[#G.printed])
  end)

  it("/dmr set restarts the engine with the new value, a bad one does not", function()
    shaman()
    login(opts())
    local first = core.rt
    SlashCmdList.DOUBTMYROTATION("set icons 2")
    assert.are.equal(2, DoubtMyRotationDB.config.icons)
    assert.are_not.equal(first, core.rt)
    assert.are.equal(2, core.rt.config.icons)
    local second = core.rt
    SlashCmdList.DOUBTMYROTATION("set icons 99")
    assert.are.equal(second, core.rt)
    assert.are.equal(2, DoubtMyRotationDB.config.icons)
  end)

  -- /reload: a new Lua state, the same SavedVariables
  it("the saved position and hidden state come back after a reload", function()
    shaman()
    login(opts(), { point = { "TOPLEFT", nil, "TOPLEFT", 10, -20 }, hidden = true, config = { icons = 3 } })
    assert.are.same({ "TOPLEFT", UIParent, "TOPLEFT", 10, -20 }, core.frame.point)
    assert.is_false(core.frame.shown)
    assert.are.equal(3, DoubtMyRotationDB.config.icons)
    assert.is_true(core.rt.sleeping)
  end)

  it("a restart while hidden keeps the engine asleep", function()
    shaman()
    login(opts(), { hidden = true })
    SlashCmdList.DOUBTMYROTATION("set icons 2")
    assert.is_true(core.rt.sleeping)
  end)

  it("unlock lets the frame be dragged and saves where it stopped", function()
    shaman()
    login(opts())
    SlashCmdList.DOUBTMYROTATION("unlock")
    assert.is_true(core.frame.mouse)
    core.frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 5, 50)
    core.frame.scripts.OnDragStop(core.frame)
    assert.are.same({ "BOTTOM", nil, "BOTTOM", 5, 50 }, DoubtMyRotationDB.point)
    SlashCmdList.DOUBTMYROTATION("lock")
    assert.is_false(core.frame.mouse)
  end)

  -- dragged off the screen or a smaller resolution: the timeline must stay reachable
  it("the frame stays on screen, shows a backdrop only while unlocked", function()
    shaman()
    login(opts())
    assert.is_true(core.frame.clamped)
    assert.is_false(core.frame.bg.shown)
    SlashCmdList.DOUBTMYROTATION("unlock")
    assert.is_true(core.frame.bg.shown)
    SlashCmdList.DOUBTMYROTATION("lock")
    assert.is_false(core.frame.bg.shown)
  end)

  it("/dmr reset also puts the timeline back in its place", function()
    shaman()
    login(opts(), { point = { "TOPLEFT", nil, "TOPLEFT", 10, -20 } })
    SlashCmdList.DOUBTMYROTATION("reset")
    assert.is_nil(DoubtMyRotationDB.point)
    assert.are.same({ "CENTER", UIParent, "CENTER", 0, -200 }, core.frame.point)
  end)

  -- Alt+Z hides UIParent: the timeline is not visible though its own frame is shown
  it("a restart behind a hidden interface sleeps", function()
    shaman()
    login(opts())
    UIParent.shown = false
    core.frame.IsVisible = function(self) return self.shown and UIParent.shown end
    SlashCmdList.DOUBTMYROTATION("set icons 2")
    assert.is_true(core.rt.sleeping)
    UIParent.shown = true
  end)

  it("hide and show put the engine to sleep and wake it", function()
    shaman()
    login(opts())
    SlashCmdList.DOUBTMYROTATION("hide")
    assert.is_true(DoubtMyRotationDB.hidden)
    assert.is_true(core.rt.sleeping)
    SlashCmdList.DOUBTMYROTATION("show")
    assert.is_false(DoubtMyRotationDB.hidden)
    assert.is_false(core.rt.sleeping)
  end)

  it("export opens the copy window with the addon's own libraries", function()
    shaman({ noLibs = true })
    assert.is_nil(LibStub)
    login(opts(), { saved = { enhrotSnapshots = { { S = { now = 42 }, plan = { value = 1, steps = {} } } } } })
    SlashCmdList.DOUBTMYROTATION("export")
    assert.is_true(EnhRotExportFrame.shown)
    assert.are.same(DoubtMyRotationDB.saved.enhrotSnapshots, require("build").decodeExport(EnhRotExportFrame.box.text))
  end)

  it("/dmr before login does nothing", function()
    shaman()
    core.boot(opts())
    SlashCmdList.DOUBTMYROTATION("set icons 2")
    assert.is_nil(core.rt)
    assert.are.same({}, G.printed)
  end)

  it("/dmr alone opens the settings window", function()
    shaman()
    login(opts())
    assert.are.equal(DoubtMyRotationPanel, core.panel)
    SlashCmdList.DOUBTMYROTATION("")
    assert.are.equal(DoubtMyRotationPanel, G.opened)
    -- the first call only expands the AddOns list
    assert.are.equal(2, G.opens)
  end)

  -- a slider dragged by the mouse sends dozens of values a second
  it("many changes in a row restart the engine once, after the pause", function()
    shaman()
    login(opts())
    local first = core.rt
    for _ = 1, 10 do core.apply(0.3) end
    assert.are.equal(first, core.rt)
    DoubtMyRotationTimer.scripts.OnUpdate(DoubtMyRotationTimer, 0.2)
    assert.are.equal(first, core.rt)
    DoubtMyRotationTimer.scripts.OnUpdate(DoubtMyRotationTimer, 0.2)
    assert.are_not.equal(first, core.rt)
    local second = core.rt
    DoubtMyRotationTimer.scripts.OnUpdate(DoubtMyRotationTimer, 1)
    assert.are.equal(second, core.rt)
  end)

  describe("the window's host", function()
    it("set changes one value and restarts after the pause", function()
      shaman()
      login(opts())
      local h, first = panels[1].host, core.rt
      assert.are.equal(DoubtMyRotationDB.config, h.config())
      h.set("icons", 2)
      assert.are.equal(2, DoubtMyRotationDB.config.icons)
      assert.are.equal(first, core.rt)
      DoubtMyRotationTimer.scripts.OnUpdate(DoubtMyRotationTimer, 0.3)
      assert.are.equal(2, core.rt.config.icons)
    end)

    it("replace takes a whole config (Cancel, Defaults) at once, invalid values fall back", function()
      shaman()
      local o = opts()
      login(o)
      local first = core.rt
      panels[1].host.replace({ icons = 3, scale = "big" })
      assert.are.equal(3, DoubtMyRotationDB.config.icons)
      assert.are.equal(settings.defaults(o.options).scale, DoubtMyRotationDB.config.scale)
      assert.are_not.equal(first, core.rt)
      assert.are.equal(DoubtMyRotationDB.config, core.rt.config)
    end)

    it("the lock and hide buttons toggle and say what they will do next", function()
      shaman()
      login(opts())
      local h = panels[1].host
      assert.are.equal("Unlock timeline", h.label("lock"))
      h.action("lock")
      assert.is_true(core.frame.mouse)
      assert.are.equal("Lock timeline", h.label("lock"))
      h.action("lock")
      assert.is_false(core.frame.mouse)
      assert.are.equal("Hide timeline", h.label("hide"))
      h.action("hide")
      assert.is_true(DoubtMyRotationDB.hidden)
      assert.are.equal("Show timeline", h.label("hide"))
      h.action("hide")
      assert.is_false(DoubtMyRotationDB.hidden)
      assert.are.equal("Export snapshots", h.label("export"))
      h.action("export")
      assert.is_true(EnhRotExportFrame.shown)
    end)
  end)

  describe("the helpers", function()
    it("start once on a shaman's login, their options are in the list", function()
      shaman()
      local o = opts()
      login(o, nil)
      assert.are.equal(1, #helperRuns)
      assert.are.equal(core, helperRuns[1].core)
      local keys = {}
      for _, opt in ipairs(o.options) do keys[opt.key] = (keys[opt.key] or 0) + 1 end
      assert.are.equal(1, keys.highlightButtons)
      assert.are.equal(1, keys.updateCheck)
      assert.is_true(DoubtMyRotationDB.config.highlightButtons)
      -- a second login (the loader's event again) starts nothing more
      core.login(o)
      assert.are.equal(1, #helperRuns)
    end)

    it("a list that already has their keys gets no second copy", function()
      shaman()
      local o = opts()
      o.options[#o.options + 1] = { type = "toggle", key = "highlightButtons", name = "Mine", default = false }
      local n = #o.options
      login(o, nil)
      assert.are.equal(n + 1, #o.options) -- only updateCheck joins
      assert.are.equal("Mine", o.options[n].name)
    end)

    it("/dmr check opens the checklist", function()
      shaman()
      login(opts(), nil)
      SlashCmdList.DOUBTMYROTATION("check")
      assert.are.equal(1, helperRuns[1].checks)
    end)

    it("not a shaman: no helpers", function()
      shaman({ class = "WARRIOR" })
      login(opts(), nil)
      assert.are.equal(0, #helperRuns)
      assert.is_nil(core.helpers)
    end)

    it("view: the running engine's plan, snapshot, cache and big icon; nil before login", function()
      assert.is_nil(core.view())
      shaman()
      login(opts(), nil)
      local v = core.view()
      local rt = core.rt
      assert.are.equal(rt.tl.icons[1], v.icon)
      assert.are.equal(rt.tl.frame, v.frame)
      assert.are.equal(rt.tl.at, v.at)
      assert.are.equal(rt.ctx.cache, v.cache)
      assert.are.equal(rt.planner, v.planner)
      assert.are.equal(rt.plan, v.plan)
      assert.are.equal(rt.S, v.S)
      assert.is_true(v.active)
      -- one table, filled anew from whatever engine runs now
      rt.sleeping = true
      assert.are.equal(v, core.view())
      assert.is_false(v.active)
      rt.sleeping = false
      rt.stopped = true
      assert.is_false(core.view().active)
    end)
  end)

  describe("the update check", function()
    it("its option joins the settings, the given list stays as it was", function()
      shaman()
      local o = opts()
      local given, n = o.options, #o.options
      login(o)
      assert.are.equal(n, #given)
      assert.are.equal(n + 2, #o.options)
      assert.are.equal("updateCheck", o.options[n + 1].key)
      assert.is_true(DoubtMyRotationDB.config.updateCheck)
      assert.are.equal(o.options, panels[1].o.options)
    end)

    it("a shaman's login starts it with the engine's version, once", function()
      shaman()
      local loader = login(opts())
      assert.are.equal(1, #checkers)
      local c = checkers[1]
      assert.are.equal(SendAddonMessage, c.deps.send)
      assert.are.equal(runtime.VERSION, c.version)
      assert.are.equal(DoubtMyRotationUpdates, c.frame)
      assert.are.equal(DoubtMyRotationDB, c.deps.db)
      assert.is_true(c.deps.enabled())
      SlashCmdList.DOUBTMYROTATION("set updateCheck off")
      assert.is_false(c.deps.enabled())
      c.deps.say("hi")
      assert.are.equal("|cff33ff99DoubtMyRotation|r hi", G.printed[#G.printed])
      loader.scripts.OnEvent(loader, "PLAYER_LOGIN")
      assert.are.equal(1, #checkers)
    end)
  end)
end)
