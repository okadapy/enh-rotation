package.path = "src/?.lua;tools/?.lua;vendor/?.lua;" .. package.path

local B = {}

B.MODULES = { "util", "spells_data", "spells", "talents", "raid", "gear_data", "gear", "swing", "enemies", "ttd",
              "damage", "model", "value", "search", "planner", "snapshot", "timeline", "recorder", "version", "runtime" }
-- Addon-only code (AGENTS.md): whole lines from --@addon to --@end, markers included, and the
-- modules of B.ADDON_SRC go into the addon only. The aura gets blank lines in their place: line
-- numbers in errors still match src/, and the engine computes exactly as before them (the aura's
-- import string has no room left, B.MAX_IMPORT).
B.ADDON_OPEN, B.ADDON_CLOSE = "--@addon", "--@end"
B.ADDON_SRC = { raid = true, gear_data = true, gear = true }
B.OUT = "dist/DoubtMyRotation.txt"
B.FIXTURE = "spec/fixtures/recorded.lua"
B.ADDON = "DoubtMyRotation"
B.ADDON_DIR = "dist/" .. B.ADDON
-- the addon's own modules and the libraries the aura borrows from WeakAuras (export window)
B.ADDON_MODULES = { { "LibSerialize", "vendor/LibSerialize.lua" }, { "LibDeflate", "vendor/LibDeflate.lua" },
                    { "settings", "addon/settings.lua" }, { "profiles", "addon/profiles.lua" },
                    { "panel", "addon/panel.lua" }, { "profilepage", "addon/profilepage.lua" },
                    { "update", "addon/update.lua" }, { "actionbars", "addon/actionbars.lua" },
                    { "highlight", "addon/highlight.lua" }, { "explain", "addon/explain.lua" },
                    { "ready", "addon/ready.lua" }, { "helpers", "addon/helpers.lua" },
                    { "guide", "addon/guide.lua" }, { "cards", "addon/cards.lua" },
                    { "wizard", "addon/wizard.lua" }, { "coach", "addon/coach.lua" },
                    { "minimap", "addon/minimap.lua" }, { "skin", "addon/skin.lua" },
                    { "core", "addon/core.lua" } }
-- Потолок длины строки импорта: клиент 3.3.5a обрезает длинную вставку (issue #20). Строка v0.1.9
-- (63 336 байт) импортировалась, v1.0.0 (99 154) — уже нет; выше потолка — ужимать сборку.
B.MAX_IMPORT = 63000
-- Слова, которые песочница WeakAuras блокирует или которые запрещены в src/ (Global Constraints),
-- и библиотеки Lua, которых нет в клиенте 3.3.5a (package, io, debug): обращение к ним падает в игре.
B.FORBIDDEN = { "pcall", "xpcall", "loadstring", "setfenv", "getfenv", "_G", "SlashCmdList", "RunScript",
                "package", "io", "debug" }

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

-- Версия аддона для отчётов: тег релиза из окружения (CI передаёт RELEASE_TAG), иначе
-- `git describe --tags`, иначе "dev". getenv / describe подменяются в тестах.
function B.version(getenv, describe)
  getenv = getenv or os.getenv
  describe = describe or function()
    local p = io.popen("git describe --tags --always 2>/dev/null")
    if not p then return nil end
    local out = p:read("*a")
    p:close()
    return out
  end
  local function clean(v)
    v = type(v) == "string" and v:match("^%s*(.-)%s*$") or ""
    if v ~= "" and v:match("^[%w%._%+%-]+$") then return v end
    return nil
  end
  return clean(getenv("RELEASE_TAG")) or clean(describe()) or "dev"
end

-- Длинная скобка Lua в позиции i ("[[", "[==["): возвращает конец открывающей скобки и закрывающую.
local function longBracket(code, i)
  local eq = code:match("^%[(=*)%[", i)
  if not eq then return nil end
  return i + #eq + 1, "]" .. eq .. "]"
end

-- Нужен ли пробел между символами a и b, чтобы лексемы не слились: "x y", "1 ..", "- -", ". .", "[ [".
local GLUED = { ["--"] = true, [".."] = true, ["[["] = true, ["[="] = true }
function B.needsSpace(a, b)
  if a:find("[%w_]") and (b:find("[%w_]") or b == ".") then return true end
  return GLUED[a .. b] == true
end

-- Код без комментариев и лишних пробелов: строки и длинные строки не трогаются, переводы строк
-- остаются на месте (номера строк в ошибках из игры совпадают с src/). Клиент 3.3.5a обрезает
-- слишком длинную вставленную строку импорта, и WeakAuras пишет "Error decompressing" (issue #20).
function B.minify(code)
  local out, n, i, len = {}, 0, 1, #code
  local ws, lineStart = false, true
  local function emit(s)
    if ws and not lineStart and B.needsSpace(out[n]:sub(-1), s:sub(1, 1)) then n = n + 1; out[n] = " " end
    ws, lineStart = false, false
    n = n + 1; out[n] = s
  end
  while i <= len do
    local c = code:sub(i, i)
    if c == "\n" then
      n = n + 1; out[n] = "\n"
      ws, lineStart = false, true
      i = i + 1
    elseif c:find("%s") then -- остальные пробельные Lua: " ", \t, \r, \f, \v
      ws = true
      i = i + 1
    elseif code:sub(i, i + 1) == "--" then
      local open, close = longBracket(code, i + 2)
      if open then
        local stop = assert(code:find(close, open + 1, true), "unfinished long comment")
        local _, lines = code:sub(i, stop):gsub("\n", "")
        for _ = 1, lines do n = n + 1; out[n] = "\n" end
        if lines > 0 then ws, lineStart = false, true else ws = true end
        i = stop + #close
      else
        i = (code:find("\n", i, true) or len + 1)
      end
    elseif c == '"' or c == "'" then
      local j = i + 1
      while true do
        local d = code:sub(j, j)
        assert(d ~= "", "unfinished string")
        if d == "\\" then j = j + 2
        elseif d == c then break
        else j = j + 1 end
      end
      emit(code:sub(i, j))
      i = j + 1
    else
      local open, close = longBracket(code, i)
      if open then
        local stop = assert(code:find(close, open + 1, true), "unfinished long string")
        emit(code:sub(i, stop + #close - 1))
        i = stop + #close
      else
        local j = code:find("[%s\"'%-%[]", i + 1) or len + 1
        emit(code:sub(i, j - 1))
        i = j
      end
    end
  end
  return table.concat(out)
end

-- A marker is a whole line (only spaces around it), so a comment that merely names one stays.
-- Blocks don't nest: an unclosed, nested or stray marker is a mistake in src/, not something to guess.
function B.strip(code)
  local out, n, inside = {}, 0, false
  for line in (code .. "\n"):gmatch("(.-)\n") do
    local mark = line:match("^%s*(%-%-@%a+)%s*$")
    if mark == B.ADDON_OPEN then
      assert(not inside, "--@addon inside --@addon")
      inside, line = true, ""
    elseif mark == B.ADDON_CLOSE then
      assert(inside, "--@end without --@addon")
      inside, line = false, ""
    elseif inside then
      line = ""
    end
    n = n + 1
    out[n] = line
  end
  assert(not inside, "--@addon without --@end")
  return table.concat(out, "\n")
end

-- src/version.lua в сборке заменяется строкой версии (version = nil: B.version()).
-- addon: the addon's bundle (every module, addon blocks kept); else the aura's (B.strip, no B.ADDON_SRC)
function B.bundle(srcDir, version, addon)
  version = version or B.version()
  local parts = {
    "local __mods = {}\n",
    "local function __require(name)\n  local m = __mods[name]\n  if m == nil then error('DoubtMyRotation: module not loaded: ' .. name) end\n  return m\nend\n",
  }
  for _, name in ipairs(B.MODULES) do
    if addon or not B.ADDON_SRC[name] then
      local code
      if name == "version" then
        code = ("return %q"):format(version)
      else
        code = B.readFile(srcDir .. "/" .. name .. ".lua")
        if not addon then code = B.strip(code) end
        code = B.minify(code)
      end
      parts[#parts + 1] = ('__mods["%s"] = (function(require)\n%s\nend)(__require)\n'):format(name, code)
    end
  end
  return table.concat(parts)
end

-- the addon and the aura installed together: the addon runs the engine, the aura stays idle
function B.initCode(srcDir, version)
  return "if DoubtMyRotationAddon then print('DoubtMyRotation: the addon is installed, this aura stays idle') return end\n"
    .. B.bundle(srcDir, version)
    .. "aura_env.show = function() WeakAuras.ScanEvents('ENHROT_SHOW') end\n"
    .. "__require('runtime').start(aura_env.config or {}, aura_env)\n"
end

function B.addonOptions()
  local aura = require("aura")
  local list = {}
  for _, o in ipairs(aura.OPTIONS) do
    if o.key ~= "export" then list[#list + 1] = o end -- the addon has /dmr export
  end
  return { list = list, width = aura.WIDTH, height = aura.HEIGHT }
end

-- One file: src as in the aura (minified, line numbers kept) plus its addon-only code, then the libraries and addon/ as they
-- are, each in its own function (its locals and upvalues stay within that function's Lua 5.1 limits).
-- Without LibStub the libraries return plain tables, which boot hands to the engine as env.libs.
-- With LibStub and the same version already registered by another addon (WeakAuras, TSM...),
-- LibSerialize returns nothing: the registered one is taken instead.
function B.addonCode(srcDir, version, modules)
  local parts = { B.bundle(srcDir, version, true) }
  for _, m in ipairs(modules or B.ADDON_MODULES) do
    local fallback = m[1]:match("^Lib") and (' or (LibStub and LibStub("%s", true))'):format(m[1]) or ""
    parts[#parts + 1] = ('__mods["%s"] = (function(require)\n%s\nend)(__require)%s\n'):format(m[1], B.readFile(m[2]), fallback)
  end
  parts[#parts + 1] = "local __o = " .. B.dump(B.addonOptions()) .. "\n"
  parts[#parts + 1] = "__require('core').boot({ options = __o.list, width = __o.width, height = __o.height,\n"
    .. "  libs = { serialize = __require('LibSerialize'), deflate = __require('LibDeflate') } })\n"
  return table.concat(parts)
end

function B.addonToc(version)
  return table.concat({
    "## Interface: 30300",
    "## Title: DoubtMyRotation - Enh Shaman",
    "## Notes: Enhancement shaman rotation helper: a 6 s fight simulation, timeline and swing clock",
    "## Version: " .. (version or B.version()),
    "## SavedVariables: DoubtMyRotationDB",
    "## SavedVariablesPerCharacter: DoubtMyRotationCharDB",
    -- ElvUI first: its Skins module is up by our PLAYER_LOGIN (addon/skin.lua)
    "## OptionalDeps: ElvUI",
    "",
    "DoubtMyRotation.lua",
    "",
  }, "\n")
end

-- the addon/ files not written yet (the addon is built only when there are none)
local function missingAddonFiles()
  local missing = {}
  for _, m in ipairs(B.ADDON_MODULES) do
    local f = io.open(m[2], "rb")
    if f then f:close() else missing[#missing + 1] = m[2] end
  end
  return missing
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

-- WeakAuras 5.22 stores aura_env.saved as a string: SerializeEx -> CompressDeflate -> EncodeForPrint
-- (Private.SaveAuraEnvironment). Returns the table, or nil if s is not such a string.
function B.decodeSaved(s)
  if type(s) ~= "string" or s == "" then return nil end
  local LibDeflate = require("LibDeflate")
  local compressed = LibDeflate:DecodeForPrint(s)
  if not compressed then return nil end
  local serialized = LibDeflate:DecompressDeflate(compressed)
  if not serialized then return nil end
  local ok, t = require("LibSerialize"):Deserialize(serialized)
  if ok and type(t) == "table" then return t end
  return nil
end

-- the string of the in-game export window (recorder.export) -> { format, version, snapshots, presses },
-- or nil. Format 1 held the bare snapshot list (no version, no presses); format 2 the whole table.
function B.decodeExportFull(s)
  if type(s) ~= "string" then return nil end
  local fmt, body = s:match("^%s*!ENHROT:(%d+)!(%S+)")
  fmt = tonumber(fmt)
  if not (body and (fmt == 1 or fmt == 2)) then return nil end
  local LibDeflate = require("LibDeflate")
  local compressed = LibDeflate:DecodeForPrint(body)
  local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
  if not serialized then return nil end
  local ok, t = require("LibSerialize"):Deserialize(serialized)
  if not (ok and type(t) == "table") then return nil end
  if fmt == 1 then return { format = 1, snapshots = t, presses = {} } end
  return { format = 2, version = t.version, snapshots = t.snapshots or {}, presses = t.presses or {} }
end

-- the string of the in-game export window -> the snapshot list (formats 1 and 2), or nil
function B.decodeExport(s)
  local d = B.decodeExportFull(s)
  return d and d.snapshots
end

-- the table saved under key anywhere in t (information.saved strings of WeakAuras 5.22 decoded)
function B.findSaved(t, key, seen)
  seen = seen or {}
  if type(t) ~= "table" or seen[t] then return nil end
  seen[t] = true
  if type(t[key]) == "table" then return t[key] end
  for k, v in pairs(t) do
    if k == "saved" and type(v) == "string" then v = B.decodeSaved(v) end
    local found = B.findSaved(v, key, seen)
    if found then return found end
  end
  return nil
end

function B.findSnapshots(t, seen)
  return B.findSaved(t, "enhrotSnapshots", seen)
end

local function loadSaved(text, name)
  local chunk = assert(loadstring(text, name or "SavedVariables"))
  local env = {}
  setfenv(chunk, env)
  chunk()
  return env
end

-- Разбирает текст SavedVariables (WeakAuras.lua) и возвращает список снимков.
function B.parseSnapshots(text, name)
  return assert(B.findSnapshots(loadSaved(text, name)), "no enhrotSnapshots in " .. (name or "SavedVariables"))
end

-- Файл со строкой экспорта или WeakAuras.lua -> журнал нажатий и версия (если известна).
function B.loadPresses(path)
  local text = B.readFile(path)
  local d = B.decodeExportFull(text)
  if d then return d.presses, d.version end
  return B.findSaved(loadSaved(text, path), "enhrotPresses") or {}, nil
end

-- Сводка журнала нажатий: сколько нажатий совпало с подсказкой, медиана задержки реакции
-- (от момента, когда подсказанная кнопка стала нужна, до нажатия; только совпавшие) и
-- самые частые расхождения «нажал X, подсказано Y».
function B.pressSummary(presses, top)
  local sum = { total = #presses, suggested = 0, matched = 0, unconfirmed = 0, mismatches = {} }
  local delays, byPair = {}, {}
  for _, p in ipairs(presses) do
    if p.sug then
      sum.suggested = sum.suggested + 1
      if p.hit then
        sum.matched = sum.matched + 1
        if type(p.delay) == "number" then delays[#delays + 1] = p.delay end
      else
        local id = tostring(p.key) .. " <- " .. tostring(p.sug)
        local m = byPair[id]
        if not m then
          m = { pressed = p.key, suggested = p.sug, count = 0 }
          byPair[id] = m
          sum.mismatches[#sum.mismatches + 1] = m
        end
        m.count = m.count + 1
      end
    end
    if not p.cf then sum.unconfirmed = sum.unconfirmed + 1 end
  end
  table.sort(delays)
  local n = #delays
  if n > 0 then
    sum.median = n % 2 == 1 and delays[(n + 1) / 2] or (delays[n / 2] + delays[n / 2 + 1]) / 2
  end
  table.sort(sum.mismatches, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if a.pressed ~= b.pressed then return tostring(a.pressed) < tostring(b.pressed) end
    return tostring(a.suggested) < tostring(b.suggested)
  end)
  top = top or 5
  while #sum.mismatches > top do table.remove(sum.mismatches) end
  return sum
end

function B.formatPresses(sum, version)
  local share = sum.suggested > 0 and ("%d%%"):format(math.floor(sum.matched * 100 / sum.suggested + 0.5)) or "-"
  local out = {
    ("version: %s"):format(version or "unknown"),
    ("presses: %d, with a suggestion: %d, followed it: %d (%s)"):format(sum.total, sum.suggested, sum.matched, share),
    ("median reaction delay: %s"):format(sum.median and ("%.3f s"):format(sum.median) or "-"),
    ("not confirmed by the server: %d"):format(sum.unconfirmed),
  }
  if #sum.mismatches > 0 then
    out[#out + 1] = "top mismatches (pressed <- suggested):"
    for _, m in ipairs(sum.mismatches) do
      out[#out + 1] = ("  %3d  %s <- %s"):format(m.count, tostring(m.pressed), tostring(m.suggested))
    end
  end
  return table.concat(out, "\n")
end

function B.importSnapshots(path, out)
  local text = B.readFile(path)
  local list = B.decodeExport(text) or B.parseSnapshots(text, path)
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
  if cmd == "presses" then
    local presses, version = B.loadPresses(a)
    print(B.formatPresses(B.pressSummary(presses), version))
    return
  end
  local aura = require("aura")
  local version = B.version()
  local str = enc.encode(aura.transmit(B.initCode("src", version)))
  os.execute("mkdir -p dist")
  local f = assert(io.open(B.OUT, "wb"))
  f:write(str)
  f:close()
  print(("%s: %d bytes, version %s"):format(B.OUT, #str, version))
  local missing = missingAddonFiles()
  if #missing > 0 then
    print(("%s/: skipped, no %s"):format(B.ADDON_DIR, table.concat(missing, ", ")))
    return
  end
  os.execute("mkdir -p " .. B.ADDON_DIR)
  for name, text in pairs({ [B.ADDON .. ".toc"] = B.addonToc(version), [B.ADDON .. ".lua"] = B.addonCode("src", version) }) do
    local out = assert(io.open(B.ADDON_DIR .. "/" .. name, "wb"))
    out:write(text)
    out:close()
  end
  print(("%s/: addon, version %s"):format(B.ADDON_DIR, version))
end

if arg and arg[0] and arg[0]:match("build%.lua$") then B.main(arg[1], arg[2], arg[3]) end

return B
