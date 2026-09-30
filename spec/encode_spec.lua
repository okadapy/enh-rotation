local enc = require("encode")

describe("encode", function()
  it("round-trips a table through the WeakAuras string format", function()
    local t = { m = "d", d = { id = "X", list = { 1, 2, 3 }, nested = { a = true, s = "text" } }, v = 1421 }
    local str = enc.encode(t)
    assert.are.equal("!WA:2!", str:sub(1, 6))
    assert.are.same(t, enc.decode(str))
  end)

  it("rejects other strings", function()
    local t, err = enc.decode("hello")
    assert.is_nil(t)
    assert.is_not_nil(err)
  end)
end)
