local util = require("util")

describe("util", function()
  it("copy makes a deep independent copy", function()
    local a = { x = { y = 1 }, list = { 1, 2 } }
    local b = util.copy(a)
    b.x.y = 2
    b.list[1] = 9
    assert.are.equal(1, a.x.y)
    assert.are.equal(1, a.list[1])
    assert.are.equal(5, util.copy(5))
  end)

  it("merge patches nested tables deeply and copies new tables", function()
    local patch = { a = { b = 2 }, c = { d = 1 } }
    local t = util.merge({ a = { b = 1, keep = true }, x = 1 }, patch)
    assert.are.same({ a = { b = 2, keep = true }, x = 1, c = { d = 1 } }, t)
    t.c.d = 9
    assert.are.equal(1, patch.c.d)
    assert.are.same({ y = 1 }, util.merge({ y = 1 }, nil))
  end)

  it("clamp keeps a number inside the bounds", function()
    assert.are.equal(0, util.clamp(-1, 0, 1))
    assert.are.equal(1, util.clamp(3, 0, 1))
    assert.are.equal(0.5, util.clamp(0.5, 0, 1))
  end)
end)
