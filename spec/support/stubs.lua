local S = {}
-- как damage.totemTargets: цель в ближнем бою — все nearby, иначе только те, кто бьёт игрока в ближнем
local function totemTargets(S_)
  local t = S_.target
  if t and t.exists and t.enemy and t.range == "melee" then return math.max(1, (S_.enemies and S_.enemies.nearby) or 1) end
  return (S_.enemies and S_.enemies.melee) or 0
end
-- damage: фиксированные числа, не зависят от характеристик
function S.damage(over)
  local N = { stormstrike = 2000, lavaLash = 1500, earthShock = 1800, flameShock = 900, frostShock = 1600,
              lightningBolt = 2500, chainLightning = 2200, searingTotem = 0, magmaTotem = 0, fireNova = 900,
              fireElemental = 0, callOfElements = 0, lightningShield = 0, shamanisticRage = 0, feralSpirit = 0 }
  for k, v in pairs(over or {}) do N[k] = v end
  return {
    action = function(_, key) return N[key] or 0 end,
    dot = function(_, key)
      if key == "flameShock" then return 300, 4, 3 elseif key == "magmaTotem" then return 400, 10, 2
      elseif key == "searingTotem" then return 250, 24, 2.5 end
      return 0, 0, 1
    end,
    periodic = function(_, src) return ({ flameShock = 100, magmaTotem = 200, searingTotem = 100, fireElemental = 500, feralSpirit = 400 })[src] or 0 end,
    auto = function(_, hand) return hand == "oh" and 400 or 800 end,
    mwPerSwing = function() return 0.3 end,
    totemTargets = totemTargets,
    targets = function(S_, key)
      if key == "fireNova" or key == "magmaTotem" then return totemTargets(S_) end
      local n = math.max(1, (S_.enemies and S_.enemies.nearby) or 1)
      if key == "chainLightning" then return math.min(n, 3) end
      return 1
    end,
  }
end
return S
