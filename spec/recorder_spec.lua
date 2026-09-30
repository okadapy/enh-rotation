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

  it("continues an existing list after reload", function()
    local saved = { enhrotSnapshots = { { S = { now = 1 }, plan = { steps = {} } } } }
    local r = recorder.new(saved, 30)
    r:push({ now = 100 }, { steps = {} })
    assert.are.equal(2, #saved.enhrotSnapshots)
  end)
end)
