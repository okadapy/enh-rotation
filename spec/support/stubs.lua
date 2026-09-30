local S = {}
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
    targets = function(S_, key)
      local n = math.max(1, (S_.enemies and S_.enemies.nearby) or 1)
      if key == "fireNova" or key == "magmaTotem" then return n elseif key == "chainLightning" then return math.min(n, 3) end
      return 1
    end,
  }
end
return S
