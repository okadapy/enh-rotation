-- Toy model honouring the model contract: direct-damage buttons, a shared cooldown group
-- and one DoT (tracked in S.target.fs). Numbers are chosen by each test.
local M = {}
M.GCD = 1.5
M.DOT_DPS = 10
M.SPELLS = {}

local function copy(t)
  if type(t) ~= "table" then return t end
  local n = {}
  for k, v in pairs(t) do n[k] = copy(v) end
  return n
end

function M.setup(spells) M.SPELLS = spells end

function M.state(o)
  o = o or {}
  local S = {
    now = 0, gcdRemains = o.gcdRemains or 0, castRemains = 0, mode = "group",
    player = { mana = 1000, manaMax = 1000 },
    buffs = { mw = { stacks = o.mw or 0, remains = 0 } },
    target = { hp = 1e6, hpMax = 1e6, fs = o.fs or 0, ttd = 60 },
    swing = { attacking = true, mh = { next = o.swing or 99, speed = 2 } },
    enemies = { melee = 1, nearby = 1 },
    totems = { fire = { remains = 0 }, water = { remains = 0 } },
    spells = {},
  }
  for k in pairs(M.SPELLS) do S.spells[k] = { cd = (o.cd and o.cd[k]) or 0 } end
  return S
end

local function tick(S, dt)
  local dmg = 0
  if S.target.fs > 0 then
    local t = math.min(dt, S.target.fs)
    dmg = t * M.DOT_DPS
    S.target.fs = S.target.fs - t
  end
  for _, sp in pairs(S.spells) do sp.cd = math.max(0, sp.cd - dt) end
  S.gcdRemains = math.max(0, S.gcdRemains - dt)
  S.swing.mh.next = S.swing.mh.next - dt
  if S.swing.mh.next <= 0 then S.swing.mh.next = S.swing.mh.next + S.swing.mh.speed end
  S.now = S.now + dt
  S.target.hp = math.max(0, S.target.hp - dmg)
  return dmg
end

function M.readyIn(S, key)
  local sp = S.spells[key]
  if not sp then return nil end
  return math.max(S.gcdRemains, S.castRemains, sp.cd)
end

function M.castTime(_, key) return (M.SPELLS[key] and M.SPELLS[key].cast) or 0 end

function M.wait(S, dt)
  local n = copy(S)
  return n, tick(n, dt)
end

function M.apply(S, key)
  local n = copy(S)
  local def = M.SPELLS[key]
  local direct = def.dmg or 0
  n.target.hp = math.max(0, n.target.hp - direct)
  if def.dot then n.target.fs = def.dot end
  for k, other in pairs(M.SPELLS) do
    if k == key or (def.shared and other.shared == def.shared) then n.spells[k].cd = def.cd or 0 end
  end
  n.player.mana = n.player.mana - (def.cost or 0)
  n.gcdRemains = M.GCD
  local dmg = direct + tick(n, M.GCD)
  return n, dmg, M.GCD
end

function M.actions(S)
  local keys = {}
  for k in pairs(S.spells) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    local r = M.readyIn(S, k)
    if r and r < 6 then out[#out + 1] = { key = k, readyIn = r } end
  end
  if S.swing.attacking and S.swing.mh.next < 6 then
    out[#out + 1] = { key = "waitSwing", readyIn = S.swing.mh.next + 0.01 }
  end
  return out
end

M.value = {
  step = function(_, _, dmg) return dmg end,
  terminal = function(S) return (S.target.fs or 0) * M.DOT_DPS * 0.5 end,
}

return M
