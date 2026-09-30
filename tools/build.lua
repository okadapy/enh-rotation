package.path = "src/?.lua;tools/?.lua;vendor/?.lua;" .. package.path

local B = {}

B.MODULES = { "util", "spells_data", "spells", "talents", "swing", "enemies", "ttd", "damage", "model", "value",
              "search", "planner", "snapshot", "timeline", "recorder", "runtime" }
B.OUT = "dist/EnhRot.txt"
B.FIXTURE = "spec/fixtures/recorded.lua"
-- Слова, которые песочница WeakAuras блокирует или которые запрещены в src/ (Global Constraints).
B.FORBIDDEN = { "pcall", "xpcall", "loadstring", "setfenv", "getfenv", "_G", "SlashCmdList", "RunScript" }

function B.readFile(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

-- Возвращает список запрещённых слов, найденных в code как отдельные идентификаторы.
function B.forbidden(code, words)
  local found = {}
  for _, word in ipairs(words or B.FORBIDDEN) do
    if code:find("%f[%w_]" .. word .. "%f[^%w_]") then found[#found + 1] = word end
  end
  return found
end

function B.bundle(srcDir)
  local parts = {
    "local __mods = {}\n",
    "local function __require(name)\n  local m = __mods[name]\n  if m == nil then error('EnhRot: module not loaded: ' .. name) end\n  return m\nend\n",
  }
  for _, name in ipairs(B.MODULES) do
    parts[#parts + 1] = ('__mods["%s"] = (function(require)\n%s\nend)(__require)\n'):format(name, B.readFile(srcDir .. "/" .. name .. ".lua"))
  end
  return table.concat(parts)
end

function B.initCode(srcDir)
  return B.bundle(srcDir) .. "__require('runtime').start(aura_env.config or {}, aura_env)\n"
end

local function number(n)
  if n ~= n then return "0/0" end
  if n == math.huge then return "math.huge" end
  if n == -math.huge then return "-math.huge" end
  if n == math.floor(n) and math.abs(n) < 2 ^ 53 then return ("%d"):format(n) end
  return ("%.17g"):format(n)
end

function B.dump(t, indent)
  indent = indent or ""
  if type(t) == "number" then return number(t) end
  if type(t) ~= "table" then return type(t) == "string" and ("%q"):format(t) or tostring(t) end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta == "number" and tb == "number" then return a < b end
    if ta ~= tb then return ta < tb end
    return tostring(a) < tostring(b)
  end)
  local out = { "{\n" }
  for _, k in ipairs(keys) do
    out[#out + 1] = ("%s  [%s] = %s,\n"):format(indent, B.dump(k), B.dump(t[k], indent .. "  "))
  end
  out[#out + 1] = indent .. "}"
  return table.concat(out)
end

function B.findSnapshots(t, seen)
  seen = seen or {}
  if type(t) ~= "table" or seen[t] then return nil end
  seen[t] = true
  if type(t.enhrotSnapshots) == "table" then return t.enhrotSnapshots end
  for _, v in pairs(t) do
    local found = B.findSnapshots(v, seen)
    if found then return found end
  end
  return nil
end

-- Разбирает текст SavedVariables (WeakAuras.lua) и возвращает список снимков.
function B.parseSnapshots(text, name)
  local chunk = assert(loadstring(text, name or "SavedVariables"))
  local env = {}
  setfenv(chunk, env)
  chunk()
  return assert(B.findSnapshots(env), "no enhrotSnapshots in " .. (name or "SavedVariables"))
end

function B.importSnapshots(path, out)
  local list = B.parseSnapshots(B.readFile(path), path)
  out = out or B.FIXTURE
  local dir = out:match("^(.*)/[^/]*$")
  if dir and dir ~= "" then os.execute("mkdir -p '" .. dir .. "'") end
  local f = assert(io.open(out, "wb"))
  f:write("return " .. B.dump(list) .. "\n")
  f:close()
  return #list
end

function B.main(cmd, a, b)
  local enc = require("encode")
  if cmd == "decode" then
    print(B.dump(assert(enc.decode(B.readFile(a)))))
    return
  end
  if cmd == "import-snapshots" then
    print(("%d snapshots -> %s"):format(B.importSnapshots(a, b), b or B.FIXTURE))
    return
  end
  local aura = require("aura")
  local str = enc.encode(aura.transmit(B.initCode("src")))
  os.execute("mkdir -p dist")
  local f = assert(io.open(B.OUT, "wb"))
  f:write(str)
  f:close()
  print(("%s: %d bytes"):format(B.OUT, #str))
end

if arg and arg[0] and arg[0]:match("build%.lua$") then B.main(arg[1], arg[2], arg[3]) end

return B
