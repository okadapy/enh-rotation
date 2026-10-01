local recorder = require("recorder")

describe("recorder", function()
  it("stores a deep copy of the snapshot and plan", function()
    local saved = {}
    local r = recorder.new(saved, 30)
    local S = { now = 100, buffs = { mw = { stacks = 2 } } }
    assert.is_true(r:push(S, { steps = { { key = "stormstrike", at = 0 } } }))
    S.buffs.mw.stacks = 5
    assert.are.equal(2, saved.enhrotSnapshots[1].S.buffs.mw.stacks)
    assert.are.equal("stormstrike", saved.enhrotSnapshots[1].plan.steps[1].key)
  end)

  it("keeps at least MIN_GAP seconds between records", function()
    local r = recorder.new({}, 30)
    assert.is_true(r:push({ now = 100 }, { steps = {} }))
    assert.is_false(r:push({ now = 101 }, { steps = {} }))
    assert.is_true(r:push({ now = 102.5 }, { steps = {} }))
  end)

  it("keeps only the newest max records", function()
    local saved = {}
    local r = recorder.new(saved, 3)
    for i = 1, 5 do r:push({ now = i * 10 }, { steps = {} }) end
    assert.are.equal(3, #saved.enhrotSnapshots)
    assert.are.equal(30, saved.enhrotSnapshots[1].S.now)
  end)

  it("exports version, snapshots and presses as one printable string the build tool reads back", function()
    local libs = { serialize = require("LibSerialize"), deflate = require("LibDeflate") }
    local list = { { S = { now = 100, target = { ttd = 3.5 } }, plan = { value = 1, steps = { { key = "lavaLash", at = 0 } } } } }
    local presses = { { t = 100.25, key = "lavaLash", sug = "lavaLash", at = 0, hit = true, delay = 0.25, cf = true } }
    local s = recorder.export({ version = "v1.2.3", snapshots = list, presses = presses }, libs)
    assert.are.equal("!ENHROT:2!", s:sub(1, 10))
    assert.is_nil(s:find("%s"))
    local build = require("build")
    assert.are.same(list, build.decodeExport("  " .. s .. "\n"))
    local full = build.decodeExportFull(s)
    assert.are.equal("v1.2.3", full.version)
    assert.are.same(presses, full.presses)
    assert.is_nil(recorder.export({ snapshots = list }, nil))
  end)

  it("logs presses against the shown plan and keeps only the newest PRESS_MAX", function()
    local saved = {}
    local r = recorder.new(saved, 30, 3)
    local plan = { steps = { { key = "stormstrike", at = 0.4 }, { key = "lavaLash", at = 1.5 } } }
    local e = r:press("stormstrike", 100.6004, plan, 100.4)
    assert.are.same({ t = 100.6, key = "stormstrike", sug = "stormstrike", at = 0.4, hit = true, delay = 0.2 }, e)
    assert.are.equal(e, saved.enhrotPresses[1])
    local e2 = r:press("earthShock", 101, plan, 102)
    assert.is_false(e2.hit)
    assert.are.equal(-1, e2.delay) -- pressed before the suggestion was due
    local e3 = r:press("lightningShield", 102, { steps = {} }, nil)
    assert.are.same({ t = 102, key = "lightningShield" }, e3)
    r:press("stormstrike", 103, plan, 102)
    assert.are.equal(3, #saved.enhrotPresses)
    assert.are.equal("earthShock", saved.enhrotPresses[1].key)
  end)

  it("marks the last press confirmed only for the same key", function()
    local saved = {}
    local r = recorder.new(saved, 30)
    r:press("stormstrike", 100, nil, nil)
    r:confirm("lavaLash")
    assert.is_nil(saved.enhrotPresses[1].cf)
    r:confirm("stormstrike")
    assert.is_true(saved.enhrotPresses[1].cf)
  end)

  it("writes the first press after a snapshot into it; none before the next snapshot leaves it nil", function()
    local saved = {}
    local r = recorder.new(saved, 30)
    local plan = { steps = { { key = "stormstrike", at = 0 } } }
    r:push({ now = 100 }, plan)
    r:press("stormstrike", 100.35, plan, 100)
    r:press("lavaLash", 101, plan, 100) -- only the first press counts
    assert.are.same({ key = "stormstrike", after = 0.35, matched = true }, saved.enhrotSnapshots[1].pressed)
    r:push({ now = 103 }, plan)
    r:push({ now = 106 }, { steps = { { key = "lavaLash", at = 0 } } })
    r:press("earthShock", 106.5, plan, 106)
    assert.is_nil(saved.enhrotSnapshots[2].pressed)
    assert.are.same({ key = "earthShock", after = 0.5, matched = false }, saved.enhrotSnapshots[3].pressed)
  end)

  it("continues an existing list after reload", function()
    local saved = { enhrotSnapshots = { { S = { now = 1 }, plan = { steps = {} } } } }
    local r = recorder.new(saved, 30)
    r:push({ now = 100 }, { steps = {} })
    assert.are.equal(2, #saved.enhrotSnapshots)
  end)
end)
