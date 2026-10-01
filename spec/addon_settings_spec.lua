local settings = require("settings")

local OPTIONS = {
  { type = "range", key = "scale", name = "Scale", min = 0.5, max = 2, step = 0.05, default = 1 },
  { type = "select", key = "mode", name = "Mode", values = { "auto", "solo", "group" }, default = 1 },
  { type = "toggle", key = "showReason", name = "Show reason under icon", default = true },
}

describe("addon settings", function()
  it("defaults: every option's default", function()
    assert.are.same({ scale = 1, mode = 1, showReason = true }, settings.defaults(OPTIONS))
  end)

  -- SavedVariables of an older version: missing keys, removed ones, wrong types, out of range
  it("merge keeps valid saved values and drops the rest", function()
    local saved = { scale = 1.5, mode = 9, showReason = "yes", removed = 3 }
    assert.are.same({ scale = 1.5, mode = 1, showReason = true }, settings.merge(OPTIONS, saved))
    assert.are.same(settings.defaults(OPTIONS), settings.merge(OPTIONS, nil))
  end)

  it("coerce: numbers in range, select by index or name, toggles by word", function()
    assert.are.equal(1.25, settings.coerce(OPTIONS[1], "1.25"))
    assert.is_nil(settings.coerce(OPTIONS[1], "3"))
    assert.is_nil(settings.coerce(OPTIONS[1], "big"))
    assert.are.equal(3, settings.coerce(OPTIONS[2], "3"))
    assert.are.equal(2, settings.coerce(OPTIONS[2], "SOLO"))
    assert.is_nil(settings.coerce(OPTIONS[2], "4"))
    assert.is_false(settings.coerce(OPTIONS[3], "off"))
    assert.is_true(settings.coerce(OPTIONS[3], "1"))
    assert.is_nil(settings.coerce(OPTIONS[3], "maybe"))
  end)

  it("set changes the config and reports it", function()
    local c = settings.defaults(OPTIONS)
    local r = settings.command(OPTIONS, c, "set mode group")
    assert.is_true(r.changed)
    assert.are.equal(3, c.mode)
    assert.are.same({ "Mode = group" }, r.lines)
  end)

  it("a bad key or value changes nothing", function()
    local c = settings.defaults(OPTIONS)
    local r = settings.command(OPTIONS, c, "set nope 1")
    assert.is_false(r.changed)
    assert.are.same({ "unknown setting: nope (see /dmr list)" }, r.lines)
    r = settings.command(OPTIONS, c, "set scale 9")
    assert.is_false(r.changed)
    assert.are.same({ "Scale: a number from 0.5 to 2" }, r.lines)
    assert.are.same(settings.defaults(OPTIONS), c)
  end)

  it("list shows every setting with its key and value", function()
    local r = settings.command(OPTIONS, settings.defaults(OPTIONS), "list")
    assert.are.same({ "scale: Scale = 1", "mode: Mode = auto (auto, solo, group)", "showReason: Show reason under icon = on" }, r.lines)
  end)

  it("reset brings the defaults back", function()
    local c = { scale = 2, mode = 2, showReason = false }
    local r = settings.command(OPTIONS, c, "reset")
    assert.is_true(r.changed)
    assert.are.same(settings.defaults(OPTIONS), c)
  end)

  it("/dmr check is an action: the checklist", function()
    assert.are.same({ lines = {}, changed = false, action = "check" }, settings.command(OPTIONS, {}, "check"))
  end)

  it("plain words are actions", function()
    for _, a in ipairs({ "export", "lock", "unlock", "show", "hide", "check", "guide", "last", "history" }) do
      assert.are.equal(a, settings.command(OPTIONS, {}, " " .. a:upper() .. " ").action)
    end
  end)

  -- the addon's entry opens the Interface Options page on "open"
  it("an empty line asks to open the window, help prints help", function()
    for _, msg in ipairs({ "", "   ", nil }) do
      assert.are.same({ lines = {}, changed = false, action = "open" }, settings.command(OPTIONS, {}, msg))
    end
    local r = settings.command(OPTIONS, {}, "help")
    assert.is_nil(r.action)
    assert.is_false(r.changed)
    assert.are.same(settings.HELP, r.lines)
    assert.are.equal("/dmr list - settings; /dmr set <key> <value> - change one", r.lines[1])
    local check
    for _, line in ipairs(r.lines) do if line:find("^/dmr check") then check = line end end
    assert.are.equal("/dmr check - is everything ready (imbues, shield, totems, ranks)", check)
    assert.are.equal("/dmr guide - the first-run guide again", r.lines[#r.lines - 1])
    assert.are.equal("/dmr last - review of the last fights; /dmr history - per boss", r.lines[#r.lines])
    r = settings.command(OPTIONS, {}, "whatever")
    assert.is_nil(r.action)
    assert.are.same(settings.HELP, r.lines)
  end)

  it("the addon's own options: toggles with valid defaults, in a fixed order", function()
    local keys, defaults = {}, {}
    for _, o in ipairs(settings.ADDON_OPTIONS) do
      assert.are.equal("toggle", o.type)
      assert.is_string(o.name)
      assert.is_string(o.desc)
      assert.is_true(settings.valid(o, o.default), o.key)
      keys[#keys + 1], defaults[#defaults + 1] = o.key, o.default
    end
    assert.are.same({ "compact", "minimap", "levelCards", "elvui", "fightSummary" }, keys)
    assert.are.same({ false, true, true, true, true }, defaults)
  end)

  it("withExtra adds the options not there yet, as a copy", function()
    local extra = { { type = "toggle", key = "showReason", name = "again", default = false },
                    { type = "toggle", key = "brandNew", name = "Brand new", default = true } }
    local list = settings.withExtra(OPTIONS, extra)
    assert.are.equal(#OPTIONS + 1, #list)
    assert.are.equal(OPTIONS[1], list[1])
    assert.are.equal(OPTIONS[3], list[3])
    assert.are.equal("brandNew", list[#list].key)
    assert.are_not.equal(OPTIONS, list)
    assert.are.equal(3, #OPTIONS)
    assert.are.equal(2, #extra)
    assert.are.same(OPTIONS, settings.withExtra(OPTIONS, nil))
  end)

  it("snap rounds a slider value to its step inside the range", function()
    assert.are.equal(1.25, settings.snap(OPTIONS[1], 1.2690001))
    assert.are.equal(0.5, settings.snap(OPTIONS[1], 0.1))
    assert.are.equal(2, settings.snap(OPTIONS[1], 7))
  end)
end)
