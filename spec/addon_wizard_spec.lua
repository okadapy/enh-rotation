local G = require("game_mock")
local P = require("panel_mock")
local wizard = require("wizard")

local function host(extra)
  local h = { cfg = { compact = false }, sets = {}, moves = {}, isUnlocked = false, dones = 0, nevers = 0 }
  h.config = function() return h.cfg end
  h.set = function(k, v) h.sets[#h.sets + 1] = { k, v }; h.cfg[k] = v end
  h.unlocked = function() return h.isUnlocked end
  h.move = function(on) h.moves[#h.moves + 1] = on; h.isUnlocked = on end
  h.done = function() h.dones = h.dones + 1 end
  h.never = function() h.nevers = h.nevers + 1 end
  for k, v in pairs(extra or {}) do h[k] = v end
  return h
end

describe("first-run guide", function()
  local closed
  local function close() closed = closed + 1 end
  before_each(function()
    G.install({})
    P.install()
    closed = 0
  end)

  it("four pages; Done on the last closes it once and tells the host", function()
    local h = host()
    local w = wizard.new(h)
    assert.are.equal(w, DoubtMyRotationWizard)
    assert.are.equal(4, #wizard.PAGES)
    w:open(close)
    assert.are.equal(wizard.PAGES[1].title, w.title.text)
    assert.are.equal("1 / 4", w.step.text)
    assert.is_false(w.back.shown)
    assert.are.equal("Next", w.next.text)
    for _ = 1, 3 do w.next:Click() end
    assert.are.equal("4 / 4", w.step.text)
    assert.are.equal("Done", w.next.text)
    w.next:Click()
    assert.is_false(w:IsShown())
    assert.are.same({ 1, 1, 0 }, { closed, h.dones, h.nevers })
    for _, x in ipairs(w.widgets) do assert.is_string(x.kind) end
    assert.are.equal("window", w.kind)
  end)

  it("page 3 unlocks the timeline to be dragged and locks it again when left", function()
    local h = host()
    local w = wizard.new(h)
    w:open(close)
    w:page(3)
    assert.are.same({ true }, h.moves)
    w.next:Click()
    assert.are.same({ true, false }, h.moves)
    w.back:Click()
    w.skip:Click()
    assert.are.same({ true, false, true, false }, h.moves)
    assert.are.same({ 1, 0 }, { closed, h.dones })
    -- unlocked by the player before: the guide leaves it as it was
    local mine = host({ isUnlocked = true })
    local w2 = wizard.new(mine)
    w2:open(close)
    w2:page(3)
    w2:page(4)
    assert.are.same({}, mine.moves)
  end)

  it("offers one button mode on page 3 only", function()
    local h = host()
    local w = wizard.new(h)
    w:open(close)
    assert.is_false(w.compact.shown)
    w:page(3)
    assert.is_true(w.compact.shown)
    w.compact:SetChecked(true)
    w.compact:Click()
    assert.are.same({ { "compact", true } }, h.sets)
  end)

  it("the last page shows the ready check when the host has one", function()
    local opened = 0
    local h = host({ checklist = function() return { { ok = true, text = "Lightning Shield" }, { ok = false, text = "Off-hand imbue" } } end,
                     openChecklist = function() opened = opened + 1 end })
    local w = wizard.new(h)
    w:open(close)
    w:page(4)
    assert.truthy(w.list.text:find("Lightning Shield", 1, true))
    assert.truthy(w.list.text:find("Off-hand imbue", 1, true))
    assert.is_true(w.check.shown)
    w.check:Click()
    assert.are.equal(1, opened)
    -- the records of addon/ready.lua name the line "label"
    local ready = wizard.new(host({ checklist = function() return { { ok = false, label = "Main hand imbue" } } end }))
    ready:open(close)
    ready:page(4)
    assert.truthy(ready.list.text:find("Main hand imbue", 1, true))
    assert.is_false(ready.check.shown)
    local plain = wizard.new(host())
    plain:open(close)
    plain:page(4)
    assert.are.equal("", plain.list.text)
    assert.is_false(plain.check.shown)
  end)

  it("Don't show again tells the host; a fight hides it on its page; Escape is Skip", function()
    local h = host()
    local w = wizard.new(h)
    w:open(close)
    w.never:Click()
    assert.are.same({ 1, 1 }, { closed, h.nevers })
    w:open(close)
    assert.are.equal("1 / 4", w.step.text)
    w:page(3)
    w:hide()
    assert.is_false(w:IsShown())
    assert.are.equal(1, closed)
    assert.are.same({ true, false }, h.moves)
    w:open(close)
    assert.are.equal("3 / 4", w.step.text)
    w:Hide() -- Escape (UISpecialFrames)
    assert.are.same({ 2, 0 }, { closed, h.dones })
    assert.are.equal("DoubtMyRotationWizard", UISpecialFrames[1])
  end)
end)
