local profiles = require("profiles")
local settings = require("settings")

local OPTIONS = {
  { type = "range", key = "icons", name = "Icons", min = 1, max = 4, step = 1, default = 4 },
  { type = "toggle", key = "compact", name = "One button mode", default = false },
  { type = "toggle", key = "minimap", name = "Minimap button", default = true },
  { type = "toggle", key = "updateCheck", name = "Updates", default = true },
}

describe("addon profiles", function()
  -- the SavedVariables of the version before profiles: one account-wide config, place, hidden flag
  it("the old settings become the Default profile, nothing of them is lost", function()
    local db = { config = { icons = 2, compact = true, minimap = false }, point = { "TOP", nil, "TOP", 0, -50 }, hidden = true }
    local char = {}
    profiles.migrate(db, char)
    assert.are.same({ icons = 2, compact = true, minimap = false }, db.profiles.Default)
    assert.are_not.equal(db.config, db.profiles.Default)
    assert.are.same({ icons = 2, compact = true, minimap = false }, db.config) -- an older version still finds it
    assert.are.same({ minimap = false }, db.ui)
    assert.are.equal("Default", char.profile)
    assert.are.same({}, char.auto)
    assert.are.same({ "TOP", nil, "TOP", 0, -50 }, char.point)
    assert.is_true(char.hidden)
    local c = profiles.view(OPTIONS, db, "Default")
    assert.are.same({ icons = 2, compact = true, minimap = false, updateCheck = true }, c)
  end)

  it("a second run changes nothing; a new install starts empty", function()
    local db = { config = { icons = 2 } }
    local char = {}
    profiles.migrate(db, char)
    db.profiles.Default.icons = 3
    char.point = { "CENTER", nil, "CENTER", 1, 2 }
    db.point = { "TOP", nil, "TOP", 0, 0 }
    profiles.migrate(db, char)
    assert.are.equal(3, db.profiles.Default.icons)
    assert.are.same({ "CENTER", nil, "CENTER", 1, 2 }, char.point)
    local fresh, me = {}, {}
    profiles.migrate(fresh, me)
    assert.are.same({ Default = {} }, fresh.profiles)
    assert.is_nil(me.point)
    assert.is_false(me.hidden)
  end)

  -- profiles are the account's: another character may have deleted one this one uses
  it("a profile gone on another character falls back to Default, its rules go", function()
    local db = { profiles = { Default = {}, Raid = {} }, ui = {} }
    local char = { profile = "Leveling", auto = { raid = "Raid", party = "Gone" } }
    profiles.migrate(db, char)
    assert.are.equal("Default", char.profile)
    assert.are.same({ raid = "Raid" }, char.auto)
  end)

  it("pick: battleground, raid, dungeon, leveling, then the one picked by hand", function()
    local db = { profiles = { Default = {}, PvP = {}, Raid = {}, Dungeon = {}, Leveling = {}, Mine = {} } }
    local char = { profile = "Mine", auto = { pvp = "PvP", raid = "Raid", party = "Dungeon", leveling = "Leveling" } }
    assert.are.same({ "PvP", "pvp" }, { profiles.pick(db, char, "arena", 80) })
    assert.are.same({ "PvP", "pvp" }, { profiles.pick(db, char, "pvp", 70) })
    assert.are.same({ "Raid", "raid" }, { profiles.pick(db, char, "raid", 80) })
    assert.are.same({ "Dungeon", "party" }, { profiles.pick(db, char, "party", 60) })
    assert.are.same({ "Leveling", "leveling" }, { profiles.pick(db, char, "none", 79) })
    assert.are.same({ "Mine", "picked" }, { profiles.pick(db, char, "none", 80) })
    char.auto = {}
    assert.are.same({ "Mine", "picked" }, { profiles.pick(db, char, "raid", 80) })
    assert.are.same({ "Mine", "picked" }, { profiles.pick(db, char, nil, nil) })
  end)

  it("view checks every value, store puts each one where it lives", function()
    local db = { profiles = { Default = {}, Raid = { icons = 9, compact = true, minimap = true } }, ui = { minimap = false } }
    local c = profiles.view(OPTIONS, db, "Raid")
    assert.are.same({ icons = 4, compact = true, minimap = false, updateCheck = true }, c) -- 9 is out of range
    c.icons, c.minimap, c.updateCheck = 2, true, false
    profiles.store(OPTIONS, db, "Raid", c)
    assert.are.equal(2, db.profiles.Raid.icons)
    assert.is_true(db.ui.minimap)
    assert.is_false(db.ui.updateCheck)
    assert.is_nil(db.profiles.Raid.updateCheck)
    profiles.store(OPTIONS, db, "Gone", c)
    assert.is_nil(db.profiles.Gone)
  end)

  it("create, delete, reset and the list of names", function()
    local db = { profiles = { Default = { icons = 1 } }, ui = {} }
    local char = { profile = "Default", auto = {} }
    assert.are.equal("Raid", profiles.create(db, "  Raid ", { icons = 3 }))
    assert.are.same({ icons = 3 }, db.profiles.Raid)
    assert.are.equal("Alt", profiles.create(db, "Alt"))
    assert.are.same({}, db.profiles.Alt)
    assert.are.same({ nil, "Raid: there is one already" }, { profiles.create(db, "Raid") })
    assert.are.same({ nil, "a name of 1 to 24 letters" }, { profiles.create(db, "   ") })
    assert.are.same({ nil, "a name of 1 to 24 letters" }, { profiles.create(db, ("x"):rep(25)) })
    assert.are.same({ "Default", "Alt", "Raid" }, profiles.names(db))
    char.profile, char.auto.raid = "Raid", "Raid"
    assert.is_true(profiles.delete(db, char, "Raid"))
    assert.is_nil(db.profiles.Raid)
    assert.are.equal("Default", char.profile)
    assert.is_nil(char.auto.raid)
    assert.are.same({ nil, "Default stays" }, { profiles.delete(db, char, "Default") })
    assert.are.same({ nil, "Nope: no such profile" }, { profiles.delete(db, char, "Nope") })
    profiles.reset(db, "Default")
    assert.are.same({}, db.profiles.Default)
  end)

  -- "Copy current" hands over everything the window shows; the account's keys stay in db.ui
  it("a copy keeps only the profile's own values", function()
    local db = { profiles = { Default = {} }, ui = {} }
    profiles.create(db, "Raid", { icons = 3, minimap = false, updateCheck = false })
    assert.are.same({ icons = 3 }, db.profiles.Raid)
  end)

  it("pick never names a profile that is gone", function()
    local db = { profiles = { Default = {} } }
    assert.are.same({ "Default", "picked" }, { profiles.pick(db, { profile = "Gone", auto = {} }, "none", 80) })
    assert.are.same({ "Default", "picked" }, { profiles.pick(db, {}, "none", 80) })
  end)
end)
