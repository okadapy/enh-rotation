-- The fight collector: counters over one fight (PLAYER_REGEN_DISABLED .. ENABLED) for the review
-- after it (addon/review.lua). The clock, the engine's state and the names come through deps:
-- nothing here reads the game API.
local recorder = require("recorder")
local search = require("search")

local M = {}
M.MIN_SECONDS = 20 -- shorter fights get no review
M.MIN_PRESSES = 10
M.STALE = 0.5 -- the last search older than this at a press: a stale plan, not a mistake
M.LATE = 1.5 -- a press later than this after its button became due: late, not wrong
M.MAX_COPIES = 30 -- searched states kept per fight for presses valued after it
M.SAMPLE = 0.5 -- seconds between samples of the engine's state
M.GRACE = 0.2 -- a due button not pressed for this long: the GCD is idle
M.MW_ID = 53817 -- Maelstrom Weapon, the buff
M.OPTION = { type = "toggle", key = "fightSummary", name = "Fight summary in chat after a fight", default = true }

local F = {}
F.__index = F

-- deps: now(), state() -> the engine's S or nil, due() -> { key, at } or nil, boss() -> name or
-- nil, targetName() -> name or nil, difficulty() -> e.g. "25 Player" or nil
function M.new(deps)
  return setmetatable({ deps = deps }, F)
end

function F:begin()
  local S = self.deps.state()
  local stacks = S and S.buffs and S.buffs.mw and S.buffs.mw.stacks or 0
  self.f = { started = self.deps.now(), presses = 0, suggested = 0, matched = 0, stale = 0, late = 0,
             delaySum = 0, delayN = 0, pairs = {}, lost = 0, unrated = 0, pending = {}, rateSum = 0, rateN = 0,
             mw = { wasted = 0, idle = 0, stacks = stacks }, gcdIdle = 0, swings = 0, fs = { seen = 0, up = 0 },
             prep = { shield = 0, totems = 0, enchants = 0, autoAttack = 0 }, names = {}, acc = 0 }
end

function F:active() return self.f ~= nil end

-- the best score of a firstValue table and its key (ties: the smaller key, deterministic)
function M.bestOf(fv)
  local best, bestKey
  for k, v in pairs(fv) do
    if best == nil or v > best or (v == best and k < bestKey) then best, bestKey = v, k end
  end
  return best, bestKey
end

local function pairOf(f, sug, key)
  local id = sug .. ">" .. key
  local p = f.pairs[id]
  if not p then
    p = { sug = sug, key = key, count = 0, lost = 0 }
    f.pairs[id] = p
  end
  return p
end

-- e = { t, key, sug, due, last } (runtime's env.onPress)
function F:press(e)
  local f = self.f
  if not f then return end
  f.presses = f.presses + 1
  if e.sug == nil then return end
  f.suggested = f.suggested + 1
  local last = e.last
  local fv = last and last.firstValue
  local best, bestKey
  if fv then best, bestKey = M.bestOf(fv) end
  if best then f.rateSum, f.rateN = f.rateSum + best / search.HORIZON, f.rateN + 1 end
  local late = false
  if e.due then
    local d = e.t - e.due
    if d > M.LATE then
      late = true
      f.late = f.late + 1
    else
      f.delaySum, f.delayN = f.delaySum + math.max(0, d), f.delayN + 1
    end
  end
  if e.key == e.sug then
    f.matched = f.matched + 1
    return
  end
  if late then return end
  if not best or e.t - last.now > M.STALE then
    f.stale = f.stale + 1
    return
  end
  local a, b = fv[e.key], fv[e.key .. "+swing"]
  local pv = (a and b) and math.max(a, b) or a or b
  local p = pairOf(f, e.sug, e.key)
  p.count = p.count + 1
  if pv then
    local loss = math.max(0, best - pv)
    p.lost, f.lost = p.lost + loss, f.lost + loss
  elseif #f.pending < M.MAX_COPIES and last.s then
    f.pending[#f.pending + 1] = { s = recorder.copy(last.s), key = e.key, best = (bestKey:gsub("%+swing$", "")), pair = p }
  else
    f.unrated = f.unrated + 1
  end
end

local function add(t, k, x) t[k] = t[k] + x end

-- a sample of the engine's state every SAMPLE seconds of dt
function F:tick(dt)
  local f = self.f
  if not f then return end
  f.acc = f.acc + (dt or 0)
  if f.acc < M.SAMPLE then return end
  local step, d = f.acc, self.deps
  f.acc = 0
  local boss = d.boss()
  if boss then
    f.boss = boss
  else
    local name = d.targetName()
    if name then f.names[name] = (f.names[name] or 0) + step end
  end
  local S = d.state()
  if not S then return end
  local busy = (S.castRemains or 0) > 0
  local mw = S.buffs and S.buffs.mw and S.buffs.mw.stacks or 0
  if mw >= 5 and not busy then add(f.mw, "idle", step) end
  local due = d.due()
  if due and d.now() >= due.at + M.GRACE and (S.gcdRemains or 0) <= 0 and not busy then
    f.gcdIdle = f.gcdIdle + step
  end
  local t, sp = S.target or {}, S.spells or {}
  if not (t.exists and t.enemy) then return end
  if sp.flameShock then
    add(f.fs, "seen", step)
    if (t.fs or 0) > 0 then add(f.fs, "up", step) end
  end
  if t.range ~= "melee" then return end
  local pr = f.prep
  if sp.lightningShield and not (S.player and S.player.shield) then add(pr, "shield", step) end
  local fire = S.totems and S.totems.fire
  if (sp.searingTotem or sp.magmaTotem) and ((fire and fire.remains) or 0) <= 0 then add(pr, "totems", step) end
  local w = S.weapons
  if w and ((w.mh and not w.mh.enchant) or (w.oh and not w.oh.enchant)) then add(pr, "enchants", step) end
  if S.swing and S.swing.attacking == false then add(pr, "autoAttack", step) end
end

-- the player's Maelstrom Weapon in the combat log: a stack that comes at 5 is wasted
function F:aura(sub, amount)
  local mw = self.f and self.f.mw
  if not mw then return end
  if sub == "SPELL_AURA_APPLIED" then
    mw.stacks = 1
  elseif sub == "SPELL_AURA_APPLIED_DOSE" then
    if mw.stacks >= 5 and (amount or 5) <= mw.stacks then mw.wasted = mw.wasted + 1 end
    mw.stacks = amount or (mw.stacks + 1)
  elseif sub == "SPELL_AURA_REFRESH" then
    if mw.stacks >= 5 then mw.wasted = mw.wasted + 1 end
  elseif sub == "SPELL_AURA_REMOVED" then
    mw.stacks = 0
  end
end

-- a hard cast started (castTime in seconds): counted when in melee and it ends after the next
-- main-hand swing (S.swing.mh.next: seconds after S.now) - a cast that fits before it delays nothing
function F:castStart(castTime)
  local f = self.f
  if not f or (castTime or 0) <= 0 then return end
  local S = self.deps.state()
  if not (S and S.target and S.target.range == "melee") then return end
  local sw = S.swing
  if not (sw and sw.attacking ~= false and sw.mh and S.now) then return end
  if self.deps.now() + castTime > S.now + sw.mh.next then f.swings = f.swings + 1 end
end

-- the fight is over: its review data, or nil (too short, too few presses, never began)
function F:finish()
  local f, d = self.f, self.deps
  self.f = nil
  if not f then return nil end
  f.seconds = d.now() - f.started
  if f.seconds < M.MIN_SECONDS or f.presses < M.MIN_PRESSES then return nil end
  if f.boss then
    local dif = d.difficulty()
    f.name = f.boss
    f.key = (dif and dif ~= "") and (f.boss .. " " .. dif) or f.boss
  else
    local top, n
    for k, v in pairs(f.names) do
      if n == nil or v > n or (v == n and k < top) then top, n = k, v end
    end
    f.name, f.trash = top or "Unknown", true
  end
  f.dps = f.rateN > 0 and f.rateSum / f.rateN or 0
  f.delay = f.delayN > 0 and f.delaySum / f.delayN or nil
  f.rate = f.suggested > 0 and f.matched / f.suggested or nil
  f.names, f.acc = nil, nil
  return f
end

-- one copied press valued after the fight: the pressed button alone against the best first
-- button alone, on the searched state; evaluate(s, steps) -> value or nil. true: none left
function M.settle(f, evaluate)
  local item = table.remove(f.pending, 1)
  if not item then return true end
  local v1 = evaluate(item.s, { { key = item.key, at = 0 } })
  local v0 = evaluate(item.s, { { key = item.best, at = 0 } })
  if v0 and v1 then
    local loss = math.max(0, v0 - v1)
    item.pair.lost, f.lost = item.pair.lost + loss, f.lost + loss
  else
    f.unrated = f.unrated + 1
  end
  return #f.pending == 0
end

-- a new fight began before the copies were valued: the rest stays not rated
function M.abandon(f)
  f.unrated = f.unrated + #f.pending
  f.pending = {}
end

return M
