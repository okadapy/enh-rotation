local LibSerialize = require("LibSerialize")
local LibDeflate = require("LibDeflate")

local M = {}
M.PREFIX = "!WA:2!"

function M.encode(t)
  local serialized = LibSerialize:SerializeEx({ errorOnUnserializableType = false }, t)
  local compressed = LibDeflate:CompressDeflate(serialized, { level = 9 })
  return M.PREFIX .. LibDeflate:EncodeForPrint(compressed)
end

function M.decode(str)
  local body = str:match("^!WA:2!(.+)$")
  if not body then return nil, "not a !WA:2! string" end
  local compressed = LibDeflate:DecodeForPrint(body)
  if not compressed then return nil, "base64 decode failed" end
  local serialized = LibDeflate:DecompressDeflate(compressed)
  if not serialized then return nil, "decompress failed" end
  local ok, t = LibSerialize:Deserialize(serialized)
  if not ok then return nil, "deserialize failed" end
  return t
end

return M
