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

  it("is a group EnhRot with one texture host EnhRot Timeline", function()
    assert.are.equal("d", t.m)
    assert.are.equal("5.22.0", t.s)
    assert.are.equal("EnhRot", t.d.id)
    assert.are.equal("group", t.d.regionType)
    assert.are.same({ "EnhRot Timeline" }, t.d.controlledChildren)
    assert.are.equal(1, #t.c)
    local host = t.c[1]
    assert.are.equal("EnhRot Timeline", host.id)
    assert.are.equal("EnhRot", host.parent)
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
    assert.are.same({ "scale", "seconds", "icons", "mode", "showReason", "showLust", "record", "printDebug" },
      optionKeys(host.authorOptions))
    assert.are.same(aura.defaultConfig(), host.config)
    assert.are.same({ scale = 1, seconds = 6, icons = 4, mode = 1, showReason = true, showLust = true,
                      record = false, printDebug = false }, aura.defaultConfig())
    assert.are.equal("auto", host.authorOptions[4].values[1])
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
                      "value", "search", "planner", "snapshot", "timeline", "recorder", "runtime" }, build.MODULES)
    assert.are.equal("dist/EnhRot.txt", build.OUT)
  end)

  it("finds blocked words only as whole identifiers", function()
    assert.are.same({}, build.forbidden("local ok = mypcall(f); local x = pcallable; local _Gx = 1"))
    assert.are.same({ "pcall" }, build.forbidden("local ok = pcall(f)"))
    assert.are.same({ "loadstring", "_G" }, build.forbidden("x = loadstring(s)\nprint(_G.x)"))
    assert.are.same({ "SlashCmdList" }, build.forbidden("SlashCmdList['X'] = f"))
    assert.are.same({ "setfenv", "getfenv" }, build.forbidden("setfenv(1, getfenv(2))"))
    assert.are.same({ "xpcall", "RunScript" }, build.forbidden("xpcall(f, e) RunScript('x')"))
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

  it("uses nothing the WeakAuras sandbox blocks", function()
    assert.are.same({}, build.forbidden(build.bundle("src")))
  end)

  it("round-trips the import string", function()
    local code = build.initCode("src")
    local t = assert(enc.decode(enc.encode(aura.transmit(code))))
    assert.are.equal("EnhRot", t.d.id)
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
    setfenv(chunk, setmetatable({ aura_env = env }, { __index = _G }))
    chunk()
    EnhRotEngineFrame.scripts.OnUpdate(EnhRotEngineFrame, 0.3)
    assert.is_true(runtime.validPlan(env.rt.plan))
    assert.is_true(#env.rt.plan.steps >= 1)
    assert.are.equal("ENHROT_SHOW", G.sent[1][1])
    env.rt.tl:tick(0.016)
    assert.is_true(env.rt.tl.icons[1].shown)
  end)
end)
