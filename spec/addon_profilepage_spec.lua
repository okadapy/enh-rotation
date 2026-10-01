local G = require("game_mock")
local P = require("panel_mock")
local profilepage = require("profilepage")

local function host()
  local h = { names = { "Default", "Raid" }, cur = "Default", act = "Default", why = "picked", rules = {}, calls = {} }
  local function log(...) h.calls[#h.calls + 1] = { ... } end
  h.list = function()
    local c = {}
    for i, n in ipairs(h.names) do c[i] = n end
    return c
  end
  h.current = function() return h.cur end
  h.active = function() return h.act, h.why end
  h.pick = function(n) log("pick", n); h.cur = n end
  h.create = function(n, copy)
    log("create", n, copy)
    if n == "" then return nil, "a name of 1 to 24 letters" end
    h.names[#h.names + 1] = n
    return n
  end
  h.delete = function(n) log("delete", n); return true end
  h.reset = function() log("reset") end
  h.rule = function(r) return h.rules[r] end
  h.setRule = function(r, n) log("rule", r, n); h.rules[r] = n end
  return h
end

describe("profiles page", function()
  before_each(function()
    G.install({})
    P.install()
  end)

  it("is a hidden page Profiles under DoubtMyRotation", function()
    local f = profilepage.new(host())
    assert.are.equal(f, DoubtMyRotationPanelProfiles)
    assert.are.equal(f, G.categories[1])
    assert.are.same({ "Profiles", "DoubtMyRotation" }, { f.name, f.parent })
    assert.is_false(f:IsShown())
    for _, w in ipairs(f.widgets) do assert.is_string(w.kind) end
    assert.are.equal("edit", f.controls.name.kind)
  end)

  it("shows the character's pick, the rules and what is active now", function()
    local h = host()
    h.cur, h.act, h.why, h.rules.raid = "Default", "Raid", "raid", "Raid"
    local f = profilepage.new(h)
    f.refresh(f)
    assert.are.equal("Default", f.controls.profile.ddText)
    assert.are.equal("Raid", f.controls.rule_raid.ddText)
    assert.are.equal("(no change)", f.controls.rule_party.ddText)
    assert.are.equal("Active now: Raid (in a raid)", f.status.text)
  end)

  it("a profile picked from the list goes to the host; a rule may be no rule", function()
    local h = host()
    local f = profilepage.new(h)
    local items = G.menu(f.controls.profile)
    assert.are.same({ "Default", "Raid" }, { items[1].text, items[2].text })
    items[2].func()
    local rule = G.menu(f.controls.rule_party)
    assert.are.equal("(no change)", rule[1].text)
    rule[3].func()
    rule[1].func()
    assert.are.same({ { "pick", "Raid" }, { "rule", "party", "Raid" }, { "rule", "party", nil } }, h.calls)
    assert.are.equal("Raid", f.controls.profile.ddText)
  end)

  it("New takes the name, Copy current copies; a bad name says why", function()
    local h = host()
    local f = profilepage.new(h)
    f.controls.name:SetText("Leveling")
    f.controls.new:Click()
    assert.are.equal("", f.controls.name:GetText())
    f.controls.name:SetText("Raid2")
    f.controls.copy:Click()
    f.controls.name:SetText("")
    f.controls.new:Click()
    assert.are.same({ { "create", "Leveling", false }, { "create", "Raid2", true }, { "create", "", false } }, h.calls)
    assert.are.equal("a name of 1 to 24 letters", f.status.text)
  end)

  it("Delete asks for a second click; Default is never deleted", function()
    local h = host()
    local f = profilepage.new(h)
    f.controls.delete:Click()
    assert.are.equal("Default stays", f.status.text)
    h.cur = "Raid"
    f.controls.delete:Click()
    assert.are.equal("Click again: delete Raid", f.controls.delete.text)
    assert.are.same({}, h.calls)
    f.controls.delete:Click()
    assert.are.same({ { "delete", "Raid" } }, h.calls)
    assert.are.equal("Delete", f.controls.delete.text)
    f.controls.reset:Click()
    assert.are.same({ "reset" }, h.calls[2])
  end)

  -- Interface Options shows the page long after it was made: the profile may have changed since
  it("shows fresh values each time it opens, a half-done delete is forgotten", function()
    local h = host()
    h.cur = "Raid"
    local f = profilepage.new(h)
    f.controls.delete:Click()
    f:Show()
    assert.are.equal("Raid", f.controls.profile.ddText)
    f:Hide()
    h.cur, h.act = "Default", nil
    f:Show()
    assert.are.equal("Default", f.controls.profile.ddText)
    assert.are.equal("Delete", f.controls.delete.text)
    assert.are.equal("Active now: Default (picked above)", f.status.text)
  end)

  it("Enter in the name box is New", function()
    local h = host()
    local f = profilepage.new(h)
    f.controls.name:SetText("Leveling")
    f.controls.name.scripts.OnEnterPressed(f.controls.name)
    assert.are.same({ { "create", "Leveling", false } }, h.calls)
  end)
end)
