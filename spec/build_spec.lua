local build = require("build")
local aura = require("aura")
local enc = require("encode")

local SAMPLE = "spec/fixtures/weakauras_saved_sample.lua"

local function srcModules()
  local out = {}
  local p = io.popen("ls src")
  for f in p:lines() do
    local name = f:match("^(.+)%.lua$")
    if name then out[#out + 1] = name end
  end
  p:close()
  return out
end

-- globals of stock Lua that the WoW 3.3.5a client does not have (os: only time/date/clock/difftime)
local NOT_IN_CLIENT = { package = true, require = true, module = true, io = true, debug = true, dofile = true, loadfile = true }
local CLIENT_OS = { time = os.time, date = os.date, clock = os.clock, difftime = os.difftime }

-- the environment of a WeakAuras custom action: the client's globals and nothing else
local function clientEnv(extra)
  return setmetatable(extra, { __index = function(_, k)
    if NOT_IN_CLIENT[k] then return nil end
    if k == "os" then return CLIENT_OS end
    return _G[k]
  end })
end

local function optionKeys(opts)
  local keys = {}
  for _, o in ipairs(opts) do keys[#keys + 1] = o.key end
  return keys
end

describe("aura", function()
  local t

  before_each(function()
    t = aura.transmit("-- init code")
  end)

  it("is a group DoubtMyRotation with one texture host DoubtMyRotation Timeline", function()
    assert.are.equal("d", t.m)
    assert.are.equal("5.22.0", t.s)
    assert.are.equal("DoubtMyRotation", t.d.id)
    assert.are.equal("group", t.d.regionType)
    assert.are.same({ "DoubtMyRotation Timeline" }, t.d.controlledChildren)
    assert.are.equal(1, #t.c)
    local host = t.c[1]
    assert.are.equal("DoubtMyRotation Timeline", host.id)
    assert.are.equal("DoubtMyRotation", host.parent)
    assert.are.equal("texture", host.regionType)
    assert.are.same({ 0, 0, 0, 0 }, host.color)
  end)

  it("targets WeakAuras 5.22 backport on 3.3.5a", function()
    for _, d in ipairs({ t.d, t.c[1] }) do
      assert.are.equal(30300, d.tocversion)
      assert.are.equal(90, d.internalVersion)
    end
  end)

  it("puts the init code into the host init action", function()
    local init = t.c[1].actions.init
    assert.is_true(init.do_custom)
    assert.are.equal("-- init code", init.custom)
  end)

  it("shows the host on ENHROT_SHOW for shamans only", function()
    local host = t.c[1]
    local trig = host.triggers[1].trigger
    assert.are.equal("custom", trig.type)
    assert.are.equal("ENHROT_SHOW", trig.events)
    assert.are.equal("SHAMAN", host.load.class.single)
    local fn = assert(loadstring("return " .. trig.custom))()
    local states = {}
    assert.is_false(fn(states, "UNIT_AURA"))
    assert.is_true(fn(states, "ENHROT_SHOW"))
    assert.is_true(states[""].show)
  end)

  it("has custom options with defaults in config", function()
    local host = t.c[1]
    assert.are.same({ "scale", "seconds", "icons", "mode", "cdFeralSpirit", "cdFireElemental", "cdShamanisticRage",
                      "weave", "manaPolicy", "showReason", "showLust", "shield", "record", "export", "printDebug" },
      optionKeys(host.authorOptions))
    assert.are.same(aura.defaultConfig(), host.config)
    assert.are.same({ scale = 1, seconds = 6, icons = 4, mode = 1, cdFeralSpirit = 1, cdFireElemental = 1,
                      cdShamanisticRage = 3, weave = 1, manaPolicy = 1, showReason = true, showLust = false, shield = 1,
                      record = false, export = false, printDebug = false }, aura.defaultConfig())
    assert.are.equal("auto", host.authorOptions[4].values[1])
    assert.are.same({ "auto", "Lightning Shield", "Water Shield" }, host.authorOptions[12].values)
  end)

  it("cooldown options: auto / boss only / always / never, read by runtime in the same order", function()
    local runtime = require("runtime")
    local byKey = {}
    for _, o in ipairs(t.c[1].authorOptions) do byKey[o.key] = o end
    for key, o in pairs(runtime.COOLDOWN_OPTIONS) do
      local opt = byKey[o[1]]
      assert.are.same({ "auto", "boss only", "always", "never" }, opt.values)
      assert.are.equal(o[2], opt.default, key)
    end
    -- the defaults: wolves and the elemental on auto, Shamanistic Rage always (a mana tool solo)
    assert.are.same({ feralSpirit = "auto", fireElemental = "auto", shamanisticRage = "always" },
      runtime.cooldowns(aura.defaultConfig()))
    assert.are.same({ feralSpirit = "boss", fireElemental = "never", shamanisticRage = "auto" },
      runtime.cooldowns({ cdFeralSpirit = 2, cdFireElemental = 4, cdShamanisticRage = 1 }))
  end)

  it("weave option: 3+ / 5 stacks / any, read by runtime in the same order (default 3+)", function()
    local runtime = require("runtime")
    local opt
    for _, o in ipairs(t.c[1].authorOptions) do if o.key == "weave" then opt = o end end
    assert.are.same({ "3+ stacks", "5 stacks", "any (model decides)" }, opt.values)
    assert.are.equal(1, opt.default)
    assert.are.same({ 3, 5, 0 }, runtime.WEAVE_MINS)
    assert.are.equal(3, runtime.weaveMin(aura.defaultConfig()))
    assert.are.equal(3, runtime.weaveMin({}))
    assert.are.equal(5, runtime.weaveMin({ weave = 2 }))
    assert.are.equal(0, runtime.weaveMin({ weave = 3 }))
  end)

  it("solo mana option: balanced / save / spend right after the weave option, read by runtime in the same order", function()
    local runtime = require("runtime")
    local value = require("value")
    local opts = t.c[1].authorOptions
    local at
    for i, o in ipairs(opts) do if o.key == "manaPolicy" then at = i end end
    assert.are.equal("weave", opts[at - 1].key)
    assert.are.same({ "balanced", "save", "spend" }, opts[at].values)
    assert.are.equal(1, opts[at].default)
    assert.are.same(opts[at].values, runtime.MANA_POLICIES)
    for _, name in ipairs(runtime.MANA_POLICIES) do assert.is_number(value.MANA_POLICY[name]) end
    assert.are.equal("balanced", runtime.manaPolicy(aura.defaultConfig()))
    assert.are.equal("balanced", runtime.manaPolicy({}))
    assert.are.equal("save", runtime.manaPolicy({ manaPolicy = 2 }))
    assert.are.equal("spend", runtime.manaPolicy({ manaPolicy = 3 }))
  end)

  it("round-trips through the import string", function()
    local str = enc.encode(t)
    assert.are.equal("!WA:2!", str:sub(1, 6))
    assert.are.same(t, assert(enc.decode(str)))
  end)
end)

describe("build (pure)", function()
  it("lists modules in the load order of the contract", function()
    assert.are.same({ "util", "spells_data", "spells", "talents", "swing", "enemies", "ttd", "damage", "model",
                      "value", "search", "planner", "snapshot", "timeline", "recorder", "version", "runtime" }, build.MODULES)
    assert.are.equal("dist/DoubtMyRotation.txt", build.OUT)
  end)

  it("finds blocked words only as whole identifiers", function()
    assert.are.same({}, build.forbidden("local ok = mypcall(f); local x = pcallable; local _Gx = 1"))
    assert.are.same({ "pcall" }, build.forbidden("local ok = pcall(f)"))
    assert.are.same({ "loadstring", "_G" }, build.forbidden("x = loadstring(s)\nprint(_G.x)"))
    assert.are.same({ "SlashCmdList" }, build.forbidden("SlashCmdList['X'] = f"))
    assert.are.same({ "setfenv", "getfenv" }, build.forbidden("setfenv(1, getfenv(2))"))
    assert.are.same({ "xpcall", "RunScript" }, build.forbidden("xpcall(f, e) RunScript('x')"))
    assert.are.same({ "package", "io", "debug" }, build.forbidden("package.loaded.x = io.open(debug.traceback())"))
    assert.are.same({}, build.forbidden("local ratio, debugOn = 1, debugprofilestop"))
  end)

  it("dumps tables as loadable Lua", function()
    local t = { 1, 2.5, "a\"b\nc", n = { x = true, [10] = false }, inf = math.huge, small = 0.1 }
    local back = assert(loadstring("return " .. build.dump(t)))()
    assert.are.same(t, back)
  end)

  it("finds snapshots anywhere in a table", function()
    local list = { { S = { now = 1 } } }
    assert.are.equal(list, build.findSnapshots({ a = { b = { saved = { enhrotSnapshots = list } } } }))
    assert.is_nil(build.findSnapshots({ a = { b = 1 } }))
  end)

  it("finds snapshots inside an encoded information.saved string (WeakAuras 5.22)", function()
    local LibSerialize, LibDeflate = require("LibSerialize"), require("LibDeflate")
    local list = { { S = { now = 7 }, plan = { value = 1, steps = {} } } }
    local str = LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(
      LibSerialize:SerializeEx({ errorOnUnserializableType = false }, { enhrotSnapshots = list }), { level = 1 }))
    local found = build.findSnapshots({ displays = { x = { information = { saved = str } } } })
    assert.are.same(list, found)
    assert.is_nil(build.findSnapshots({ displays = { x = { information = { saved = "not encoded" } } } }))
  end)

  it("parses snapshots out of a WeakAuras SavedVariables file", function()
    local list = build.parseSnapshots(build.readFile(SAMPLE), SAMPLE)
    assert.are.equal(2, #list)
    assert.are.equal(1234.5, list[1].S.now)
    assert.are.equal("stormstrike", list[1].plan.steps[1].key)
    assert.are.equal('Maelstrom "5"', list[1].plan.steps[1].reason)
    assert.are.same({}, list[2].plan.steps)
  end)

  it("fails on SavedVariables without snapshots", function()
    assert.has_error(function() build.parseSnapshots("WeakAurasSaved = { displays = {} }") end)
  end)

  it("imports snapshots from the in-game export string", function()
    local list = { { S = { now = 5 }, plan = { value = 2, steps = {} } } }
    local s = require("recorder").export({ version = "v1.0.0", snapshots = list, presses = {} },
      { serialize = require("LibSerialize"), deflate = require("LibDeflate") })
    local path, out = os.tmpname(), os.tmpname()
    local f = assert(io.open(path, "wb"))
    f:write(s .. "\n")
    f:close()
    assert.are.equal(1, build.importSnapshots(path, out))
    assert.are.equal(5, dofile(out)[1].S.now)
    os.remove(path)
    os.remove(out)
  end)

  it("decodes the export string of format 1 (bare list) and 2 (version, snapshots, presses)", function()
    local LibSerialize, LibDeflate = require("LibSerialize"), require("LibDeflate")
    local list = { { S = { now = 5 }, plan = { value = 2, steps = {} } } }
    local v1 = "!ENHROT:1!" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(
      LibSerialize:SerializeEx({ errorOnUnserializableType = false }, list), { level = 9 }))
    assert.are.same(list, build.decodeExport(v1))
    assert.are.same({ format = 1, snapshots = list, presses = {} }, build.decodeExportFull(v1))
    local presses = { { t = 5.5, key = "stormstrike", sug = "stormstrike", at = 0, hit = true, delay = 0.5 } }
    local v2 = require("recorder").export({ version = "v0.9.1", snapshots = list, presses = presses },
      { serialize = LibSerialize, deflate = LibDeflate })
    assert.are.equal("!ENHROT:2!", v2:sub(1, 10))
    assert.are.same(list, build.decodeExport(v2))
    assert.are.same({ format = 2, version = "v0.9.1", snapshots = list, presses = presses }, build.decodeExportFull(v2))
    assert.is_nil(build.decodeExport("!ENHROT:3!" .. v2:sub(11)))
    assert.is_nil(build.decodeExport("not an export"))
  end)

  it("sums up the press log: followed share, median reaction delay, top mismatches", function()
    local P = {
      { key = "stormstrike", sug = "stormstrike", hit = true, delay = 0.3, cf = true },
      { key = "lavaLash", sug = "lavaLash", hit = true, delay = 0.1, cf = true },
      { key = "earthShock", sug = "earthShock", hit = true, delay = 0.9, cf = true },
      { key = "earthShock", sug = "stormstrike", hit = false, delay = -0.2, cf = true },
      { key = "earthShock", sug = "stormstrike", hit = false, delay = 0.1, cf = true },
      { key = "lavaLash", sug = "lightningBolt", hit = false, cf = true },
      { key = "lightningShield" }, -- nothing suggested, not confirmed
    }
    local sum = build.pressSummary(P)
    assert.are.equal(7, sum.total)
    assert.are.equal(6, sum.suggested)
    assert.are.equal(3, sum.matched)
    assert.are.equal(0.3, sum.median)
    assert.are.equal(1, sum.unconfirmed)
    assert.are.same({ { pressed = "earthShock", suggested = "stormstrike", count = 2 },
                      { pressed = "lavaLash", suggested = "lightningBolt", count = 1 } }, sum.mismatches)
    assert.are.equal(1, #build.pressSummary(P, 1).mismatches)
    assert.are.near(0.2, build.pressSummary({ P[1], P[2] }).median, 1e-9)
    local text = build.formatPresses(sum, "v1.0.0")
    assert.is_not_nil(text:find("version: v1.0.0", 1, true))
    assert.is_not_nil(text:find("followed it: 3 (50%)", 1, true))
    assert.is_not_nil(text:find("median reaction delay: 0.300 s", 1, true))
    assert.is_not_nil(text:find("2  earthShock <- stormstrike", 1, true))
    assert.is_nil(build.pressSummary({}).median)
    assert.is_not_nil(build.formatPresses(build.pressSummary({})):find("version: unknown", 1, true))
  end)

  it("reads the press log from an export string or WeakAuras.lua", function()
    local presses = { { t = 1, key = "stormstrike", sug = "lavaLash", hit = false } }
    local s = require("recorder").export({ version = "v2.0.0", snapshots = {}, presses = presses },
      { serialize = require("LibSerialize"), deflate = require("LibDeflate") })
    local path = os.tmpname()
    local f = assert(io.open(path, "wb"))
    f:write(s)
    f:close()
    local got, version = build.loadPresses(path)
    assert.are.same(presses, got)
    assert.are.equal("v2.0.0", version)
    f = assert(io.open(path, "wb"))
    f:write('WeakAurasSaved = { displays = { x = { saved = { enhrotPresses = { { t = 2, key = "lavaLash" } } } } } }')
    f:close()
    got, version = build.loadPresses(path)
    assert.are.same({ { t = 2, key = "lavaLash" } }, got)
    assert.is_nil(version)
    os.remove(path)
  end)

  it("takes the version from RELEASE_TAG, else the repository's tag, else dev", function()
    local function env(v) return function(name) return name == "RELEASE_TAG" and v or nil end end
    local function tag(v) return function() return v end end
    assert.are.equal("v1.4.2", build.version(env("v1.4.2"), tag("v1.4.1-3-gabc\n")))
    assert.are.equal("v1.4.1-3-gabc", build.version(env(""), tag("v1.4.1-3-gabc\n")))
    assert.are.equal("dev", build.version(env(nil), tag(nil)))
    assert.are.equal("dev", build.version(env('x"; os.exit()'), tag("")))
  end)

  it("writes the version into the bundle in place of src/version.lua", function()
    local code = build.bundle("src", "v3.1.4")
    assert.is_not_nil(code:find('__mods["version"] = (function(require)\nreturn "v3.1.4"\nend)', 1, true))
    local mods = assert(loadstring(code .. "\nreturn __require('version')"))
    assert.are.equal("v3.1.4", mods())
  end)

  it("minifies code: no comments, fewer spaces, strings untouched, line numbers kept", function()
    local code = table.concat({
      "local a = 1 -- a comment",
      "  local s = \"x -- not a comment\" .. 'it\\'s' -- tail",
      "--[[ long",
      "comment ]] local b = a - -a",
      "local l = [==[",
      "  kept -- as is ]] ]==]",
      "return s, l, b, 1 .. a, a --[[x]]+ b, b == a",
    }, "\n")
    local m = build.minify(code)
    assert.are.equal(table.concat({
      "local a=1",
      "local s=\"x -- not a comment\"..'it\\'s'",
      "",
      "local b=a- -a",
      "local l=[==[",
      "  kept -- as is ]] ]==]",
      "return s,l,b,1 ..a,a+b,b==a",
    }, "\n"), m)
    assert.are.equal(build.minify(m), m)
    local run = function(c) return assert(loadstring(c))() end
    assert.are.same({ run(code) }, { run(m) })
  end)

  it("treats every Lua whitespace as a separator when minifying", function()
    assert.are.equal("local a=1\nreturn a", build.minify("local\fa\v=\t1\r\nreturn\f\va"))
  end)

  it("imports recorded snapshots into a fixture file", function()
    local out = os.tmpname()
    assert.are.equal(2, build.importSnapshots(SAMPLE, out))
    local list = dofile(out)
    assert.are.equal(1234.5, list[1].S.now)
    assert.are.equal(1800.25, list[1].plan.value)
    assert.are.equal(1240, list[2].S.now)
    os.remove(out)
  end)
end)

describe("build #integration", function()
  it("lists every source module and bundles code that compiles", function()
    local listed = {}
    for _, name in ipairs(build.MODULES) do listed[name] = true end
    for _, name in ipairs(srcModules()) do assert.is_true(listed[name] == true, "not in build.MODULES: " .. name) end
    local code = build.initCode("src")
    assert.is_not_nil(loadstring(code))
    for _, name in ipairs(build.MODULES) do
      assert.is_not_nil(code:find('__mods["' .. name .. '"]', 1, true), name)
    end
  end)

  it("minifies every source module without changing its line count", function()
    for _, name in ipairs(build.MODULES) do
      local raw = build.readFile("src/" .. name .. ".lua")
      local m = build.minify(raw)
      assert.is_not_nil(loadstring(m), name)
      assert.are.equal(select(2, raw:gsub("\n", "")), select(2, m:gsub("\n", "")), name)
    end
  end)

  -- issue #20: the 3.3.5a client cuts a too long pasted import string, WeakAuras says "Error decompressing"
  it("keeps the import string short enough to paste into the client", function()
    local str = enc.encode(aura.transmit(build.initCode("src")))
    assert.is_true(#str <= build.MAX_IMPORT, ("import string %d > %d bytes"):format(#str, build.MAX_IMPORT))
  end)

  it("uses nothing the WeakAuras sandbox blocks", function()
    assert.are.same({}, build.forbidden(build.bundle("src")))
  end)

  it("round-trips the import string", function()
    local code = build.initCode("src")
    local t = assert(enc.decode(enc.encode(aura.transmit(code))))
    assert.are.equal("DoubtMyRotation", t.d.id)
    assert.are.equal(1, #t.c)
    assert.are.equal(code, t.c[1].actions.init.custom)
  end)

  it("runs as a WeakAuras init action and draws a plan", function()
    local G = require("game_mock")
    local spells = require("spells")
    local runtime = require("runtime")
    local known = {}
    for _, meta in ipairs(spells.CATALOG) do known[meta.ranks[#meta.ranks]] = true end
    G.install({ now = 100, known = known, castMs = { ["Lightning Bolt"] = 2500 },
                target = { level = 83, hp = 1e6, hpMax = 1e6, guid = "Creature-9" }, inRange = { Stormstrike = 1 },
                enchants = { mh = true, oh = true }, tooltip = { [16] = { "Windfury 8" }, [17] = { "Flametongue 10" } },
                auras = { player = { HELPFUL = { { name = "Lightning Shield", count = 3, expires = 700 } } } } })
    local env = { config = aura.defaultConfig(), region = CreateFrame("Frame"), saved = {} }
    local chunk = assert(loadstring(build.initCode("src")))
    setfenv(chunk, clientEnv({ aura_env = env }))
    chunk()
    EnhRotEngineFrame.scripts.OnUpdate(EnhRotEngineFrame, 0.3)
    -- the search runs in 2 ms slices, one per frame: the plan shows once it has finished
    for _ = 1, 20 do
      if #env.rt.plan.steps > 0 then break end
      EnhRotEngineFrame.scripts.OnUpdate(EnhRotEngineFrame, 0.016)
    end
    assert.is_true(runtime.validPlan(env.rt.plan))
    assert.is_true(#env.rt.plan.steps >= 1)
    assert.are.equal("ENHROT_SHOW", G.sent[1][1])
    env.rt.tl:tick(0.016)
    assert.is_true(env.rt.tl.icons[1].shown)
  end)
  it("opens the export window with the saved snapshots when the option is on", function()
    local G = require("game_mock")
    G.install({ now = 100 })
    local saved = { enhrotSnapshots = { { S = { now = 42 }, plan = { value = 1, steps = {} } } } }
    local cfg = aura.defaultConfig()
    cfg.record, cfg.export = true, true
    local env = { config = cfg, region = CreateFrame("Frame"), saved = saved }
    local chunk = assert(loadstring(build.initCode("src")))
    setfenv(chunk, clientEnv({ aura_env = env }))
    chunk()
    local w = EnhRotExportFrame
    assert.is_true(w.shown)
    assert.are.same(saved.enhrotSnapshots, build.decodeExport(w.box.text))
  end)

  it("the aura stays idle when the addon is installed", function()
    local G = require("game_mock")
    G.install({ now = 100 })
    _G.DoubtMyRotationAddon = {} -- the addon's global, seen by the chunk through the client env
    local env = { config = aura.defaultConfig(), region = CreateFrame("Frame"), saved = {} }
    local chunk = assert(loadstring(build.initCode("src")))
    setfenv(chunk, clientEnv({ aura_env = env }))
    chunk()
    _G.DoubtMyRotationAddon = nil
    assert.is_nil(env.rt)
    assert.is_nil(EnhRotEngineFrame)
    assert.are.equal("DoubtMyRotation: the addon is installed, this aura stays idle", G.printed[#G.printed])
  end)
end)

describe("addon build", function()
  local LIBS = { { "LibSerialize", "vendor/LibSerialize.lua" }, { "LibDeflate", "vendor/LibDeflate.lua" } }
  local CORE = { "core", "spec/fixtures/addon_core_stub.lua" }

  it("names its folder and its modules", function()
    assert.are.equal("DoubtMyRotation", build.ADDON)
    assert.are.equal("dist/DoubtMyRotation", build.ADDON_DIR)
    assert.are.same({ { "LibSerialize", "vendor/LibSerialize.lua" }, { "LibDeflate", "vendor/LibDeflate.lua" },
                      { "settings", "addon/settings.lua" }, { "panel", "addon/panel.lua" },
                      { "update", "addon/update.lua" }, { "core", "addon/core.lua" } }, build.ADDON_MODULES)
  end)

  it("the addon's toc: 3.3.5a, its SavedVariables, its one file", function()
    local toc = build.addonToc("v9.9.9")
    assert.truthy(toc:find("## Interface: 30300\n", 1, true))
    assert.truthy(toc:find("## Version: v9.9.9\n", 1, true))
    assert.truthy(toc:find("## SavedVariables: DoubtMyRotationDB\n", 1, true))
    assert.truthy(toc:find("\nDoubtMyRotation.lua\n", 1, true))
  end)

  it("the addon's options are the aura's without export", function()
    local o = build.addonOptions()
    assert.are.equal(#aura.OPTIONS - 1, #o.list)
    for _, opt in ipairs(o.list) do assert.are_not.equal("export", opt.key) end
    assert.are.equal(aura.WIDTH, o.width)
    assert.are.equal(aura.HEIGHT, o.height)
  end)

  -- each library is wrapped in a function: Lua 5.1 caps a function at 200 locals and 60 upvalues
  it("wraps the libraries so they compile and work without LibStub", function()
    local G = require("game_mock")
    G.install({ now = 100 })
    _G.LibStub = nil -- a client without WeakAuras or any other library addon
    local chunk = assert(loadstring(build.addonCode("src", "v0", { LIBS[1], LIBS[2], CORE })))
    local genv = clientEnv({})
    assert.is_nil(genv.LibStub)
    setfenv(chunk, genv)
    chunk()
    local o = assert(genv.BOOTED)
    assert.are.same(build.addonOptions().list, o.options)
    assert.are.equal(aura.WIDTH, o.width)
    assert.are.equal(aura.HEIGHT, o.height)
    local ser, def = o.libs.serialize, o.libs.deflate
    assert.is_function(ser.Serialize)
    assert.is_function(def.CompressDeflate)
    local t = { a = 1, list = { 1, 2.5, "x" }, flag = true }
    local packed = def:EncodeForPrint(def:CompressDeflate(ser:Serialize(t)))
    local ok, back = ser:Deserialize(def:DecompressDeflate(def:DecodeForPrint(packed)))
    assert.is_true(ok)
    assert.are.same(t, back)
  end)

  it("starts with the aura's bundle: the engine's line numbers and version stay", function()
    local code = build.addonCode("src", "v7.7.7", { CORE })
    assert.are.equal(1, code:find(build.bundle("src", "v7.7.7"), 1, true))
    assert.truthy(code:find('__mods["core"]', 1, true))
  end)

  it("takes the addon's modules by default", function()
    local seen = {}
    local readFile = build.readFile
    build.readFile = function(path)
      seen[path] = true
      if path:match("^addon/") then return "return {}" end
      return readFile(path)
    end
    build.addonCode("src", "v0")
    build.readFile = readFile
    for _, m in ipairs(build.ADDON_MODULES) do assert.is_true(seen[m[2]] == true, m[2]) end
  end)

  -- the whole addon file as the client loads it: no WeakAuras, no LibStub, its own frame and window
  it("runs as an addon without WeakAuras and draws a plan #integration", function()
    local G = require("game_mock")
    local spells = require("spells")
    local runtime = require("runtime")
    local known = {}
    for _, meta in ipairs(spells.CATALOG) do known[meta.ranks[#meta.ranks]] = true end
    G.install({ now = 100, known = known, noLibs = true, castMs = { ["Lightning Bolt"] = 2500 },
                target = { level = 83, hp = 1e6, hpMax = 1e6, guid = "Creature-9" }, inRange = { Stormstrike = 1 },
                enchants = { mh = true, oh = true }, tooltip = { [16] = { "Windfury 8" }, [17] = { "Flametongue 10" } },
                auras = { player = { HELPFUL = { { name = "Lightning Shield", count = 3, expires = 700 } } } } })
    require("panel_mock").install()
    _G.WeakAuras = nil
    local chunk = assert(loadstring(build.addonCode("src")))
    -- the addon's own globals (DoubtMyRotationAddon, DoubtMyRotationDB) land in this table;
    -- named frames go to _G through the mock's CreateFrame
    local genv = clientEnv({})
    setfenv(chunk, genv)
    chunk()
    DoubtMyRotationLoader.scripts.OnEvent(DoubtMyRotationLoader, "ADDON_LOADED", "DoubtMyRotation")
    DoubtMyRotationLoader.scripts.OnEvent(DoubtMyRotationLoader, "PLAYER_LOGIN")
    local core = genv.DoubtMyRotationAddon
    local rt = core.rt
    assert.are.equal(DoubtMyRotationFrame, rt.env.region)
    assert.are.equal(3, #G.categories)
    assert.is_not_nil(core.panel.controls.updateCheck)
    EnhRotEngineFrame.scripts.OnUpdate(EnhRotEngineFrame, 0.3)
    for _ = 1, 20 do
      if #rt.plan.steps > 0 then break end
      EnhRotEngineFrame.scripts.OnUpdate(EnhRotEngineFrame, 0.016)
    end
    assert.is_true(runtime.validPlan(rt.plan))
    assert.is_true(#rt.plan.steps >= 1)
    genv.SlashCmdList.DOUBTMYROTATION("")
    assert.are.equal(DoubtMyRotationPanel, G.opened)
  end)
end)
