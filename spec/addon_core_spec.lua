local G = require("game_mock")

-- the settings window (addon/panel.lua), its Profiles page (addon/profilepage.lua), the guide
-- (addon/wizard.lua), the level cards (addon/cards.lua) and the update check (addon/update.lua)
-- have their own specs: here they are stand-ins that record what core gives them
local panels, checkers = {}, {}
local reloads, pages, wizards, cardWindows = {}, {}, {}, {}
package.loaded.panel = {
  new = function(o, host)
    local f = CreateFrame("Frame", "DoubtMyRotationPanel")
    f.o, f.host = o, host
    f.widgets = { CreateFrame("Button") }
    f.widgets[1].kind = "button"
    panels[#panels + 1] = f
    return f
  end,
  reload = function(main) reloads[#reloads + 1] = main end,
}
package.loaded.profilepage = {
  new = function(host)
    local f = CreateFrame("Frame", "DoubtMyRotationPanelProfiles")
    f.host, f.refreshes = host, 0
    f.refresh = function(self) self.refreshes = self.refreshes + 1 end
    pages[#pages + 1] = f
    return f
  end,
}
package.loaded.wizard = {
  new = function(host)
    local w = CreateFrame("Frame", "DoubtMyRotationWizard")
    w.kind, w.widgets, w.host = "window", {}, host
    function w:open(close) self.close = close; self:Show() end
    function w:hide() self:Hide() end
    wizards[#wizards + 1] = w
    return w
  end,
}
package.loaded.cards = {
  firstRun = function(level, seen) for l = 10, level, 10 do seen[l] = true end end,
  due = function(level, seen)
    local l = math.floor(level / 10) * 10
    if l >= 10 and not seen[l] then return { level = l } end
  end,
  window = function(host)
    local w = DoubtMyRotationCard or CreateFrame("Frame", "DoubtMyRotationCard")
    w.kind, w.widgets, w.host = "window", {}, host
    function w:open(card, close) self.card, self.close = card, close; self:Show() end
    function w:hide() self:Hide() end
    cardWindows[#cardWindows + 1] = w
    return w
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

-- the ready window of addon/ready.lua is made on its first showing, as the real one is
local helperRuns = {}
package.loaded.helpers = {
  options = function() return { { type = "toggle", key = "highlightButtons", name = "Light up", default = true } } end,
  start = function(core, say)
    local h = { core = core, say = say, checks = 0 }
    h.ready = { show = function(self) self.win = DoubtMyRotationReady or CreateFrame("Frame", "DoubtMyRotationReady") end }
    h.check = function() h.checks = h.checks + 1; h.ready:show() end
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

-- the mock says "in combat" unless told otherwise; the guide and the cards need a calm moment
local function calm(extra)
  extra = extra or {}
  extra.inCombat = false
  shaman(extra)
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
    core.char, core.config, core.profile, core.why, core.level = nil, nil, nil, nil, nil
    core.skin, core.mini, core.guide, core.coach, core.wizard = nil, nil, nil, nil, nil
    core.profilePage, core.openLater, core.checklist = nil, nil, nil
    reloads, pages, wizards, cardWindows = {}, {}, {}, {}
    -- a failed ElvUI test must not leave it to the next one
    require("elvui_mock").remove()
  end)

  it("a shaman gets the timeline frame and a running engine on login", function()
    shaman()
    local o = opts()
    login(o)
    assert.are.equal(core, DoubtMyRotationAddon)
    assert.are.equal("/dmr", SLASH_DOUBTMYROTATION1)
    assert.are.same(settings.defaults(o.options), core.config)
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
    assert.are.equal(2, core.config.icons)
    assert.are.equal(2, DoubtMyRotationDB.profiles.Default.icons)
    assert.are_not.equal(first, core.rt)
    assert.are.equal(2, core.rt.config.icons)
    local second = core.rt
    SlashCmdList.DOUBTMYROTATION("set icons 99")
    assert.are.equal(second, core.rt)
    assert.are.equal(2, core.config.icons)
  end)

  -- /reload: a new Lua state, the same SavedVariables
  it("the saved position and hidden state come back after a reload", function()
    shaman()
    login(opts(), { point = { "TOPLEFT", nil, "TOPLEFT", 10, -20 }, hidden = true, config = { icons = 3 } })
    assert.are.same({ "TOPLEFT", UIParent, "TOPLEFT", 10, -20 }, core.frame.point)
    assert.is_false(core.frame.shown)
    assert.are.equal(3, core.config.icons)
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
    assert.are.same({ "BOTTOM", nil, "BOTTOM", 5, 50 }, DoubtMyRotationCharDB.point)
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
    assert.is_nil(DoubtMyRotationCharDB.point)
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
    assert.is_true(DoubtMyRotationCharDB.hidden)
    assert.is_true(core.rt.sleeping)
    SlashCmdList.DOUBTMYROTATION("show")
    assert.is_false(DoubtMyRotationCharDB.hidden)
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
      assert.are.equal(core.config, h.config())
      h.set("icons", 2)
      assert.are.equal(2, core.config.icons)
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
      assert.are.equal(3, core.config.icons)
      assert.are.equal(settings.defaults(o.options).scale, core.config.scale)
      assert.are_not.equal(first, core.rt)
      assert.are.equal(core.config, core.rt.config)
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
      assert.is_true(DoubtMyRotationCharDB.hidden)
      assert.are.equal("Show timeline", h.label("hide"))
      h.action("hide")
      assert.is_false(DoubtMyRotationCharDB.hidden)
      assert.are.equal("Export snapshots", h.label("export"))
      assert.are.equal("Show the guide", h.label("guide"))
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
      assert.is_true(core.config.highlightButtons)
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
      assert.are.equal(n + 1 + #settings.ADDON_OPTIONS, #o.options) -- updateCheck and the addon's own join
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
      assert.are.equal(n + 2 + #settings.ADDON_OPTIONS, #o.options)
      assert.are.equal("updateCheck", o.options[n + 1].key)
      assert.are.equal("elvui", o.options[#o.options].key)
      assert.is_true(core.config.updateCheck)
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

  describe("profiles", function()
    -- the SavedVariables of the version before profiles
    it("the old settings become the Default profile and stay where they were", function()
      shaman()
      local old = { config = { icons = 2, showReason = false }, point = { "TOP", nil, "TOP", 0, -40 } }
      login(opts(), old)
      assert.are.equal("Default", core.profile)
      assert.are.equal(2, core.config.icons)
      assert.is_false(core.config.showReason)
      assert.are.same({ icons = 2, showReason = false }, DoubtMyRotationDB.config)
      assert.are.same({ "TOP", nil, "TOP", 0, -40 }, DoubtMyRotationCharDB.point)
      assert.are.same({ "TOP", UIParent, "TOP", 0, -40 }, core.frame.point)
    end)

    it("a dungeon picks the dungeon rule's profile, the open world the picked one", function()
      shaman({ instance = "party" })
      _G.DoubtMyRotationCharDB = { profile = "Default", auto = { party = "Dungeon" } }
      login(opts(), { profiles = { Default = {}, Dungeon = { icons = 1 } } })
      assert.are.equal("Dungeon", core.profile)
      assert.are.equal(1, core.rt.config.icons)
      local first = core.rt
      G.cfg.instance = "none"
      DoubtMyRotationEvents.scripts.OnEvent(DoubtMyRotationEvents, "PLAYER_ENTERING_WORLD")
      assert.are.equal("Default", core.profile)
      assert.are.equal(4, core.rt.config.icons)
      assert.are_not.equal(first, core.rt)
      assert.truthy(G.printed[#G.printed]:find("profile Default", 1, true))
      assert.are.same({ panels[1] }, reloads)
    end)

    it("in a fight the profile waits for the fight's end", function()
      shaman({ instance = "raid" })
      _G.DoubtMyRotationCharDB = { auto = { raid = "Raid" } }
      login(opts(), { profiles = { Default = {}, Raid = { icons = 2 } } })
      G.cfg.instance, G.cfg.lockdown = "none", true
      local before = core.rt
      DoubtMyRotationEvents.scripts.OnEvent(DoubtMyRotationEvents, "ZONE_CHANGED_NEW_AREA")
      assert.are.equal("Raid", core.profile)
      assert.are.equal(before, core.rt)
      G.cfg.lockdown = false
      DoubtMyRotationEvents.scripts.OnEvent(DoubtMyRotationEvents, "PLAYER_REGEN_ENABLED")
      assert.are.equal("Default", core.profile)
      assert.are_not.equal(before, core.rt)
    end)

    -- UnitLevel still gives the old level while PLAYER_LEVEL_UP runs
    it("hitting 80 leaves the leveling profile, by the event's own level", function()
      shaman({ level = 79 })
      _G.DoubtMyRotationCharDB = { auto = { leveling = "Leveling" } }
      login(opts(), { profiles = { Default = {}, Leveling = { compact = true } } })
      assert.are.equal("Leveling", core.profile)
      DoubtMyRotationEvents.scripts.OnEvent(DoubtMyRotationEvents, "PLAYER_LEVEL_UP", 80)
      assert.are.equal("Default", core.profile)
    end)

    it("a value set goes into the active profile, the account's ones into db.ui", function()
      shaman()
      _G.DoubtMyRotationCharDB = { profile = "Raid" }
      login(opts(), { profiles = { Default = {}, Raid = {} } })
      SlashCmdList.DOUBTMYROTATION("set icons 3")
      SlashCmdList.DOUBTMYROTATION("set minimap off")
      assert.are.equal(3, DoubtMyRotationDB.profiles.Raid.icons)
      assert.is_nil(DoubtMyRotationDB.profiles.Default.icons)
      assert.is_false(DoubtMyRotationDB.ui.minimap)
      assert.is_false(DoubtMyRotationMinimapButton.shown)
    end)

    it("the Profiles page's host: new, copy, delete the active one, rules", function()
      shaman()
      login(opts())
      local h = pages[1].host
      SlashCmdList.DOUBTMYROTATION("set icons 2")
      assert.are.equal("Copy", h.create("Copy", true))
      assert.are.equal("Copy", core.profile)
      assert.are.equal(2, core.config.icons)
      assert.are.same({ nil, "Copy: there is one already" }, { h.create("Copy") })
      assert.are.same({ "Default", "Copy" }, h.list())
      assert.is_true(h.delete("Copy"))
      assert.are.equal("Default", core.profile)
      h.setRule("raid", "Default")
      assert.are.equal("Default", h.rule("raid"))
      assert.are.same({ "Default", "picked" }, { h.active() })
      assert.is_true(pages[1].refreshes > 0)
    end)

    it("reset puts the active profile back to the defaults and restarts", function()
      shaman()
      local o = opts()
      login(o, { profiles = { Default = { icons = 2 } } })
      local first = core.rt
      pages[1].host.reset()
      assert.are.equal(settings.defaults(o.options).icons, core.config.icons)
      assert.are_not.equal(first, core.rt)
      assert.are.same({ panels[1] }, reloads)
    end)
  end)

  describe("first-run guide and level cards", function()
    it("a new character out of combat gets the guide; Done keeps it away on this character", function()
      calm()
      login(opts())
      local w = wizards[1]
      assert.is_true(w:IsShown())
      w.host.done()
      w.close()
      assert.are.equal("done", DoubtMyRotationCharDB.wizard)
      -- the guide's page 3 moves the timeline through the host
      w.host.move(true)
      assert.is_true(core.frame.mouse)
      assert.is_true(w.host.unlocked())
      w.host.move(false)
      w.host.set("compact", true)
      assert.is_true(core.config.compact)
    end)

    it("not in a fight: the guide waits for the fight's end", function()
      shaman() -- the mock says: in combat
      login(opts())
      assert.is_nil(wizards[1])
      G.cfg.inCombat = false
      DoubtMyRotationGuide.scripts.OnEvent(DoubtMyRotationGuide, "PLAYER_REGEN_ENABLED")
      assert.is_true(wizards[1]:IsShown())
    end)

    it("Don't show again: no guide on any character; /dmr guide still opens it", function()
      calm()
      login(opts(), { wizardOff = true })
      assert.is_nil(wizards[1])
      SlashCmdList.DOUBTMYROTATION("guide")
      assert.is_true(wizards[1]:IsShown())
      wizards[1].host.never()
      assert.is_true(DoubtMyRotationDB.wizardOff)
    end)

    it("the settings window's Show the guide button opens it too", function()
      calm()
      _G.DoubtMyRotationCharDB = { wizard = "done" }
      login(opts())
      assert.is_nil(wizards[1])
      panels[1].host.action("guide")
      assert.is_true(wizards[1]:IsShown())
    end)

    it("a level up brings its card once; the option off brings none", function()
      calm({ level = 19 })
      _G.DoubtMyRotationCharDB = { wizard = "done" }
      login(opts())
      DoubtMyRotationCoach.scripts.OnEvent(DoubtMyRotationCoach, "PLAYER_LEVEL_UP", 20)
      local w = cardWindows[#cardWindows]
      assert.are.equal(20, w.card.level)
      w.close()
      assert.is_true(DoubtMyRotationCharDB.cards[20])
      SlashCmdList.DOUBTMYROTATION("set levelCards off")
      DoubtMyRotationCoach.scripts.OnEvent(DoubtMyRotationCoach, "PLAYER_LEVEL_UP", 30)
      assert.are.equal(20, cardWindows[#cardWindows].card.level)
      assert.is_true(DoubtMyRotationCharDB.cards[30])
    end)

    it("the guide's last page lists stage 1's ready check when there is one", function()
      calm()
      core.checklist = { items = function() return { { ok = true, text = "Lightning Shield" } } end, open = function() end }
      login(opts())
      assert.are.same({ { ok = true, text = "Lightning Shield" } }, wizards[1].host.checklist())
      assert.is_function(wizards[1].host.openChecklist)
    end)

    -- addon/ready.lua: ready.items(ready.gather(core.view())), its window through the helpers
    it("by default the checklist is addon/ready.lua's, opened like /dmr check", function()
      calm()
      login(opts())
      local h = wizards[1].host
      -- no snapshot before the engine's first tick: nothing to list yet
      assert.are.same({}, h.checklist())
      EnhRotEngineFrame.scripts.OnUpdate(EnhRotEngineFrame, 0.3)
      local items = h.checklist()
      assert.is_true(#items > 0)
      for _, it in ipairs(items) do
        assert.is_boolean(it.ok)
        assert.is_string(it.label)
      end
      h.openChecklist()
      assert.are.equal(1, helperRuns[1].checks)
    end)
  end)

  describe("minimap button, combat and ElvUI", function()
    it("left click opens the settings, out of combat only; right click hides the timeline", function()
      shaman()
      login(opts())
      local b = DoubtMyRotationMinimapButton
      assert.is_true(b.shown)
      G.cfg.lockdown = true
      b.scripts.OnClick(b, "LeftButton")
      assert.is_nil(G.opened)
      assert.are.equal("|cff33ff99DoubtMyRotation|r the settings open after combat", G.printed[#G.printed])
      local lines = #G.printed
      SlashCmdList.DOUBTMYROTATION("") -- asked again in the same fight: no second line
      assert.are.equal(lines, #G.printed)
      assert.is_nil(G.opened)
      G.cfg.lockdown = false
      DoubtMyRotationEvents.scripts.OnEvent(DoubtMyRotationEvents, "PLAYER_REGEN_ENABLED")
      assert.are.equal(DoubtMyRotationPanel, G.opened)
      b.scripts.OnClick(b, "RightButton")
      assert.is_true(DoubtMyRotationCharDB.hidden)
      b.scripts.OnDragStop(b)
      assert.are.equal(200, DoubtMyRotationCharDB.minimap.angle)
    end)

    it("the saved angle puts the button back where it was dragged", function()
      shaman()
      _G.DoubtMyRotationCharDB = { minimap = { angle = 90 } }
      login(opts())
      assert.are.equal(90, DoubtMyRotationMinimapButton.angle)
    end)

    it("one button mode shrinks the frame to the icon", function()
      shaman()
      login(opts())
      assert.are.equal(340, core.frame.w)
      SlashCmdList.DOUBTMYROTATION("set compact on")
      assert.are.equal(120, core.frame.w)
      assert.is_true(core.rt.tl.o.compact)
      SlashCmdList.DOUBTMYROTATION("set compact off")
      assert.are.equal(340, core.frame.w)
    end)

    it("ElvUI loaded first: our windows, the minimap button and the backdrop get its look", function()
      shaman()
      local S = require("elvui_mock").install()
      login(opts())
      assert.are.equal("HandleButton", panels[1].widgets[1].elv)
      assert.are.equal("Default", DoubtMyRotationMinimapButton.elvTemplate)
      assert.are.equal("Transparent", core.frame.bg.elvTemplate)
      SlashCmdList.DOUBTMYROTATION("export")
      assert.are.equal("Transparent", EnhRotExportFrame.elvTemplate)
      -- the ready window is made on its first showing: styled once it is there
      SlashCmdList.DOUBTMYROTATION("check")
      assert.are.equal("Transparent", DoubtMyRotationReady.elvTemplate)
      assert.is_true(#S.calls >= 2)
      require("elvui_mock").remove()
    end)

    it("ElvUI style off: ElvUI is left alone until the option is turned on", function()
      shaman()
      local S = require("elvui_mock").install()
      login(opts(), { ui = { elvui = false } })
      assert.are.same({}, S.calls)
      assert.is_nil(DoubtMyRotationMinimapButton.elvTemplate)
      SlashCmdList.DOUBTMYROTATION("set elvui on")
      assert.are.equal("Default", DoubtMyRotationMinimapButton.elvTemplate)
      assert.are.equal("HandleButton", panels[1].widgets[1].elv)
      require("elvui_mock").remove()
    end)
  end)
end)
