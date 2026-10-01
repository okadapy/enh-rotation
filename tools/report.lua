-- Разбор отчёта об ошибке: снимки из игры -> одинаковый набор проверок для каждого issue.
--   lua tools/report.lua <строка экспорта | WeakAuras.lua | fixture.lua> [--baseline <git-ref | fixture>] [--save <file>]
-- --save пишет подсказки текущего кода как фикстуру: её потом можно дать в --baseline.
-- Модуль: M.load(path) -> список, M.analyze(list, opts) -> отчёт (таблица), M.format(отчёт) -> текст.
if arg and arg[0] and arg[0]:match("report%.lua$") then
  package.path = "src/?.lua;tools/?.lua;vendor/?.lua;" .. package.path
end

local M = {}

M.DYING_TTD = 10    -- s: снимки, где цель умирает раньше, проверяются на дрожание первой кнопки
M.NOISE = 0.2       -- ±20% к времени до смерти на каждом событии
M.STEPS = 12        -- 12 событий по 0.25 с = 3 с
M.STEP_DT = 0.25
M.SEED = 12345
M.LOW_MANA = 0.2    -- доля маны, ниже которой — «мало маны»
M.TOP = 5           -- сколько самых частых несовпадений нажатий показывать

local function mods(suggestOnly)
  if suggestOnly then return require("search") end
  return require("search"), require("planner"), require("model"), require("runtime"), require("util")
end

----------------------------------------------------------------------------------------------
-- Чтение входа

-- ENHROT-строка любой версии: v1 — голый список снимков, v2 — { version, snapshots, presses }.
-- Возвращает список снимков и (для v2) журнал нажатий.
function M.decodeAny(text)
  local B = require("build")
  -- the build's own decoder knows every export format (snapshots, presses, version)
  if B.decodeExportFull then
    local d = B.decodeExportFull(text)
    if d then return d.snapshots, d.presses, d.version end
  end
  local t = B.decodeExport(text)
  if not t then
    local body = type(text) == "string" and text:match("^%s*!ENHROT:%d+!(%S+)")
    if not body then return nil end
    local LibDeflate = require("LibDeflate")
    local compressed = LibDeflate:DecodeForPrint(body)
    local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
    if not serialized then return nil end
    local ok, v = require("LibSerialize"):Deserialize(serialized)
    if not (ok and type(v) == "table") then return nil end
    t = v
  end
  if type(t.snapshots) == "table" then return t.snapshots, t.presses, t.version end
  return t
end

-- путь -> список снимков { S, plan[, pressed] }, журнал нажатий (или nil), версия (или nil)
function M.load(path)
  local B = require("build")
  local text = B.readFile(path)
  local list, presses, version = M.decodeAny(text)
  if list then return list, presses, version end
  -- a fixture returns the list; WeakAuras.lua only sets globals, the list is under enhrotSnapshots
  -- (maybe inside the encoded saved string)
  local chunk = assert(loadstring(text, "@" .. path))
  local env = {}
  setfenv(chunk, env)
  local t = chunk()
  if type(t) == "table" then
    if type(t.snapshots) == "table" then return t.snapshots, t.presses, t.version end
    return t
  end
  return assert(B.findSnapshots(env), "no snapshots in " .. path)
end

----------------------------------------------------------------------------------------------
-- Помощники

local function first(plan)
  local st = plan and plan.steps and plan.steps[1]
  return st and st.key or "-"
end

function M.stepsText(plan)
  if not (plan and plan.steps) or #plan.steps == 0 then return "-" end
  local parts = {}
  for _, st in ipairs(plan.steps) do parts[#parts + 1] = ("%s@%.1f"):format(st.key, st.at or 0) end
  return table.concat(parts, " ")
end

local function median(xs)
  if #xs == 0 then return nil end
  local s = {}
  for i, x in ipairs(xs) do s[i] = x end
  table.sort(s)
  local n = #s
  if n % 2 == 1 then return s[(n + 1) / 2] end
  return (s[n / 2] + s[n / 2 + 1]) / 2
end
M.median = median

local function isEnemy(t) return t and t.exists and t.enemy end

-- тот же ли моб: тот же запас здоровья, здоровье не выросло
local function sameMob(a, b)
  local ta, tb = a.S.target, b.S.target
  return isEnemy(ta) and isEnemy(tb) and ta.hpMax and ta.hpMax == tb.hpMax and (tb.hp or 0) <= (ta.hp or 0)
    and not ta.dead
end

----------------------------------------------------------------------------------------------
-- Проверки

-- одна строка на снимок: что было в игре и что предлагает текущий код
function M.row(i, rec, t0, search, runtime)
  local S, plan = rec.S, rec.plan or { steps = {} }
  local t, p, b = S.target or {}, S.player or {}, S.buffs or {}
  local now = search.best(S, {})
  -- runtime may be nil (--suggest-only) or an older version without these checks (--baseline <ref>)
  local alert = runtime and runtime.alert and runtime.alert(S)
  local hint = runtime and runtime.idleHint and runtime.idleHint(plan, S, false)
  local flags = {}
  if isEnemy(t) and t.range == "melee" and S.swing and not S.swing.attacking then flags[#flags + 1] = "melee-no-autoattack" end
  if (p.manaMax or 0) > 0 and p.mana / p.manaMax < M.LOW_MANA then flags[#flags + 1] = "low-mana" end
  if isEnemy(t) and t.range == "far" then flags[#flags + 1] = "far" end
  return {
    i = i,
    time = (S.now or 0) - t0,
    level = p.level, targetLevel = t.level,
    mode = S.mode,
    range = t.exists and t.range or nil,
    attacking = S.swing and S.swing.attacking or false,
    mana = p.mana, manaMax = p.manaMax,
    hp = t.hp, hpMax = t.hpMax,
    ttd = t.ttd,
    fs = t.fs,
    mw = b.mw and b.mw.stacks or 0,
    shown = M.stepsText(plan), shownFirst = first(plan),
    trigger = plan.trigger and plan.trigger.kind or nil,
    now = M.stepsText(now), nowFirst = first(now),
    alert = alert and alert.key or nil,
    hint = hint and hint.key or nil,
    flags = flags,
    pressed = rec.pressed,
  }
end

-- Как в spec/stability_spec.lua: 3 с событий без нажатий, время до смерти врёт на ±20% на каждом
-- событии (свой LCG — одинаково везде). Считает смены первой кнопки, пока цель жива.
function M.stability(S0, seed, planner, model, util)
  local function rnd()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
  end
  local p, S, last, seq, changes = planner.new({}), util.copy(S0), nil, {}, 0
  for k = 1, M.STEPS do
    local dead = S.target.dead
    local s = util.copy(S)
    s.target.ttd = S.target.ttd * (1 + M.NOISE * (2 * rnd() - 1))
    local ev = k == 1 and { kind = "target" } or { kind = k % 2 == 0 and "swing" or "aura" }
    local f = first(p:update(s, ev))
    if not dead and last and f ~= last then changes = changes + 1 end
    last, seq[k] = f, (dead and "+" or "") .. f
    S = model.wait(S, M.STEP_DT)
  end
  return changes, table.concat(seq, " "), seed
end

-- мана по мобам: цепочки соседних снимков одного моба; траты делятся на подход (не в ближнем
-- бою) и ближний бой — по дальности в начале каждого промежутка
function M.mana(list, t0)
  local mobs, cur = {}, nil
  for i = 2, #list do
    local a, b = list[i - 1], list[i]
    if sameMob(a, b) then
      if not (cur and cur.last == i - 1) then
        cur = { from = i - 1, last = i - 1, pull = 0, melee = 0, hpMax = a.S.target.hpMax,
                hp0 = a.S.target.hp, mana0 = a.S.player.mana, t = (a.S.now or 0) - t0 }
        mobs[#mobs + 1] = cur
      end
      local spent = math.max(0, (a.S.player.mana or 0) - (b.S.player.mana or 0))
      if a.S.target.range == "melee" then cur.melee = cur.melee + spent else cur.pull = cur.pull + spent end
      cur.last, cur.hp1, cur.mana1 = i, b.S.target.hp, b.S.player.mana
      cur.seconds = (b.S.now or 0) - (list[cur.from].S.now or 0)
    end
  end
  local total = { pull = 0, melee = 0 }
  for _, m in ipairs(mobs) do total.pull, total.melee = total.pull + m.pull, total.melee + m.melee end
  return mobs, total
end

-- нажатия (поле pressed у снимков, ветка feat/export-presses); без него — nil
function M.presses(list)
  local n, hit, reactions, miss = 0, 0, {}, {}
  for _, rec in ipairs(list) do
    local pr = rec.pressed
    if type(pr) == "table" and pr.key then
      n = n + 1
      if pr.matched then
        hit = hit + 1
      else
        local k = first(rec.plan) .. " -> " .. pr.key
        miss[k] = (miss[k] or 0) + 1
      end
      if type(pr.after) == "number" then reactions[#reactions + 1] = pr.after end
    end
  end
  if n == 0 then return nil end
  local top = {}
  for k, c in pairs(miss) do top[#top + 1] = { pair = k, count = c } end
  table.sort(top, function(a, b) return a.count > b.count or (a.count == b.count and a.pair < b.pair) end)
  while #top > M.TOP do table.remove(top) end
  return { count = n, matched = hit, rate = hit / n, medianAfter = median(reactions), top = top }
end

-- журнал нажатий v2 (presses = { t, key, sug, at, hit, delay, cf }): совпадения и задержка
function M.pressLog(log)
  if type(log) ~= "table" or #log == 0 then return nil end
  local n, hit, delays, cf = 0, 0, {}, 0
  for _, e in ipairs(log) do
    n = n + 1
    if e.hit then hit = hit + 1 end
    if e.cf then cf = cf + 1 end
    if type(e.delay) == "number" then delays[#delays + 1] = e.delay end
  end
  return { count = n, hit = hit, confirmed = cf, medianDelay = median(delays) }
end

-- baseline: список подсказок ({ first, steps }) или записанные снимки (берётся их plan)
function M.suggestionsOf(list)
  local out = {}
  for i, x in ipairs(list or {}) do
    if x.plan then
      out[i] = { first = first(x.plan), steps = M.stepsText(x.plan) }
    else
      out[i] = { first = x.first or "-", steps = x.steps or "-" }
    end
  end
  return out
end

function M.diff(rows, baseline)
  local out = {}
  for _, r in ipairs(rows) do
    local b = baseline[r.i]
    if b and b.first ~= r.nowFirst then
      out[#out + 1] = { i = r.i, before = b.first, now = r.nowFirst, beforeSteps = b.steps, nowSteps = r.now }
    end
  end
  return out
end

-- list: снимки { S, plan[, pressed] }; opts.baseline — подсказки (M.suggestionsOf), opts.presses — журнал v2;
-- opts.suggestOnly — только подсказки search.best (прогон старой версии src/ для --baseline <ref>)
function M.analyze(list, opts)
  opts = opts or {}
  local search, planner, model, runtime, util = mods(opts.suggestOnly)
  local t0 = list[1] and list[1].S.now or 0
  local R = { count = #list, rows = {}, disagree = {}, stability = { runs = 0, changes = 0, list = {} }, alerts = {} }
  local seed = M.SEED
  for i, rec in ipairs(list) do
    local r = M.row(i, rec, t0, search, runtime)
    R.rows[i] = r
    if r.shownFirst ~= r.nowFirst then R.disagree[#R.disagree + 1] = r end
    if r.alert or r.hint or #r.flags > 0 then R.alerts[#R.alerts + 1] = r end
    local t = rec.S.target
    if not opts.suggestOnly and isEnemy(t) and t.ttd and t.ttd < M.DYING_TTD then
      local changes, seq
      changes, seq, seed = M.stability(rec.S, seed, planner, model, util)
      R.stability.runs = R.stability.runs + 1
      R.stability.changes = R.stability.changes + changes
      R.stability.list[#R.stability.list + 1] = { i = i, ttd = t.ttd, changes = changes, seq = seq }
    end
  end
  R.mobs, R.manaTotal = M.mana(list, t0)
  R.presses = M.presses(list)
  R.pressLog = M.pressLog(opts.presses)
  R.version = opts.version
  if opts.baseline then R.diff = M.diff(R.rows, opts.baseline) end
  return R
end

----------------------------------------------------------------------------------------------
-- Текст

local function num(x, fmt) if type(x) ~= "number" then return "-" end return (fmt or "%d"):format(x) end

function M.formatRow(r)
  local pr = ""
  if r.pressed then
    pr = (" | pressed %s +%ss%s"):format(r.pressed.key, num(r.pressed.after, "%.2f"), r.pressed.matched and "" or " MISS")
  end
  local mark = r.shownFirst ~= r.nowFirst and " *" or ""
  return ("#%-2d t=%6.1f L%s/%s %s %s %s mana %s/%s hp %s/%s ttd %s fs %s mw %d | game[%s]: %s | now: %s%s%s")
    :format(r.i, r.time, num(r.level), num(r.targetLevel), r.mode or "-", r.range or "none",
            r.attacking and "atk" or "noatk", num(r.mana), num(r.manaMax), num(r.hp), num(r.hpMax),
            num(r.ttd, "%.1f"), num(r.fs, "%.1f"), r.mw or 0, r.trigger or "-", r.shown, r.now, mark, pr)
end

function M.format(R)
  local out = {}
  local function add(s) out[#out + 1] = s end
  add(("%d snapshots%s  (* = the current code suggests another first button)"):format(R.count,
      R.version and (", addon " .. tostring(R.version)) or ""))
  for _, r in ipairs(R.rows) do add(M.formatRow(r)) end

  add("")
  add(("1. Disagreements (game vs current code, first button): %d of %d"):format(#R.disagree, R.count))
  for _, r in ipairs(R.disagree) do add(("  #%d %s -> %s   (%s  |  %s)"):format(r.i, r.shownFirst, r.nowFirst, r.shown, r.now)) end

  add("")
  add(("2. Stability (ttd < %d s, 3 s of events, ttd ±%d%%): %d first-button changes in %d runs")
    :format(M.DYING_TTD, M.NOISE * 100, R.stability.changes, R.stability.runs))
  for _, s in ipairs(R.stability.list) do
    add(("  #%d ttd %.1f: %d changes  %s"):format(s.i, s.ttd, s.changes, s.seq))
  end

  add("")
  add(("3. Alerts: %d snapshots"):format(#R.alerts))
  for _, r in ipairs(R.alerts) do
    add(("  #%d alert=%s hint=%s %s"):format(r.i, r.alert or "-", r.hint or "-", table.concat(r.flags, ",")))
  end

  add("")
  add(("4. Mana by mob: pull %d, melee %d"):format(R.manaTotal.pull, R.manaTotal.melee))
  for _, m in ipairs(R.mobs) do
    add(("  #%d-#%d t=%.1f %.1fs hpMax %d hp %d->%d: mana %d->%d, pull %d, melee %d")
      :format(m.from, m.last, m.t, m.seconds or 0, m.hpMax, m.hp0 or 0, m.hp1 or 0, m.mana0 or 0, m.mana1 or 0, m.pull, m.melee))
  end

  add("")
  if R.presses then
    local p = R.presses
    add(("5. Presses: %d/%d matched (%.0f%%), median reaction %s s"):format(p.matched, p.count, p.rate * 100, num(p.medianAfter, "%.2f")))
    for _, m in ipairs(p.top) do add(("  %dx shown %s"):format(m.count, m.pair)) end
  else
    add("5. Presses: no `pressed` field in the snapshots (recorded before the press log)")
  end
  if R.pressLog then
    local l = R.pressLog
    add(("   press log: %d presses, %d hit the suggestion, %d confirmed, median delay %s s")
      :format(l.count, l.hit, l.confirmed, num(l.medianDelay, "%.2f")))
  end

  if R.diff then
    add("")
    add(("6. Against the baseline: %d first buttons differ"):format(#R.diff))
    for _, d in ipairs(R.diff) do add(("  #%d %s -> %s   (%s  |  %s)"):format(d.i, d.before, d.now, d.beforeSteps, d.nowSteps)) end
  end
  return table.concat(out, "\n")
end

-- подсказки текущего кода как фикстура (для --save и --baseline)
function M.suggestionsFixture(R)
  local out = {}
  for i, r in ipairs(R.rows) do out[i] = { first = r.nowFirst, steps = r.now } end
  return "return " .. require("build").dump(out) .. "\n"
end

----------------------------------------------------------------------------------------------
-- Командная строка

local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

-- baseline по git-ссылке: src/ этой версии во временный каталог, подсказки считает отдельный процесс
function M.baselineFromRef(ref, input)
  local dir = os.tmpname()
  os.remove(dir)
  assert(os.execute("mkdir -p " .. shq(dir)) == 0, "mkdir failed")
  local ok = os.execute(("git archive %s src | tar -x -C %s"):format(shq(ref), shq(dir)))
  assert(ok == 0, "git archive " .. ref .. " failed")
  local out = dir .. "/suggestions.lua"
  local lua = (arg and arg[-1]) or "lua"
  local cmd = ("%s tools/report.lua %s --src %s --save %s --suggest-only --quiet"):format(shq(lua), shq(input), shq(dir .. "/src"), shq(out))
  assert(os.execute(cmd) == 0, "baseline run failed: " .. cmd)
  local t = dofile(out)
  os.execute("rm -rf " .. shq(dir))
  return t
end

function M.main(args)
  local input, baseline, save, src, quiet, suggestOnly
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--baseline" then baseline, i = args[i + 1], i + 1
    elseif a == "--save" then save, i = args[i + 1], i + 1
    elseif a == "--src" then src, i = args[i + 1], i + 1
    elseif a == "--quiet" then quiet = true
    elseif a == "--suggest-only" then suggestOnly = true
    else input = a end
    i = i + 1
  end
  if not input then
    print("usage: lua tools/report.lua <export string | WeakAuras.lua | fixture.lua> [--baseline <git-ref | fixture>] [--save <file>]")
    os.exit(1)
  end
  require("build") -- it puts src/ first in package.path: --src must come after it
  if src then package.path = src .. "/?.lua;" .. package.path end
  local list, presses, version = M.load(input)
  local opts = { presses = presses, version = version, suggestOnly = suggestOnly }
  if baseline then
    local t = exists(baseline) and dofile(baseline) or M.baselineFromRef(baseline, input)
    opts.baseline = M.suggestionsOf(t)
  end
  local R = M.analyze(list, opts)
  if save then
    local f = assert(io.open(save, "wb"))
    f:write(M.suggestionsFixture(R))
    f:close()
  end
  if not quiet then print(M.format(R)) end
end

if arg and arg[0] and arg[0]:match("report%.lua$") then M.main(arg) end

return M
