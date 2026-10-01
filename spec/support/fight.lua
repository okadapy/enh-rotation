-- Closed-loop fight for the stability specs: the model is the "game", a bot presses what the
-- planner shows. Maelstrom procs are random but seeded (the model's expected stacks, rounded at
-- random); events, pulse, throttle and the per-frame search budget work as in runtime.
local Sc = require("scenario")
local model = require("model")
local planner = require("planner")
local search = require("search")
local runtime = require("runtime")

local F = {}
F.FRAME = 1 / 60
F.LATE = 0.3 -- a change of the first button this close before its planned press counts as late
-- deterministic stand-in for the CPU clock: every model call the search makes costs MODEL_MS
F.MODEL_MS = 0.014

-- the model's expected Maelstrom gain turned into whole stacks at random
local function roll(S0, S1, key, rng)
  local base = (key == "lightningBolt" or key == "chainLightning") and 0 or math.floor((S0.buffs.mw.stacks or 0) + 1e-9)
  if (S0.buffs.mw.remains or 0) <= 0 then base = 0 end
  local g = (S1.buffs.mw.stacks or 0) - base
  if g < 0 then g = 0 end
  local n = math.floor(g + 1e-9)
  if rng() < g - n then n = n + 1 end
  local st = math.min(5, base + n)
  S1.buffs.mw.stacks = st
  if st == 0 then S1.buffs.mw.remains = 0 end
  return S1
end

-- a model whose every call advances a fake clock (search time without wall-clock noise)
local function metered()
  local calls = 0
  local m = setmetatable({}, { __index = model })
  for _, f in ipairs({ "apply", "wait", "peekApply", "peekApplyOver", "peekWait", "advance", "actions", "readyIn" }) do
    local real = model[f]
    m[f] = function(...) calls = calls + 1; return real(...) end
  end
  return m, function() return calls * F.MODEL_MS end
end

-- opts: seconds, seed, level, patch(S), budgetMs (nil = whole search at once), wrap(model) -> model the
-- planner searches with (a policy to compare against), hysteresis/hold/holdFactor, trace
function F.run(opts)
  local S = Sc.state(opts.level or 80)
  S.totems.fire = { kind = "magma", remains = 15 }
  if opts.patch then opts.patch(S) end
  local rng = Sc.lcg(opts.seed or 1)
  local m, clock = metered()
  if opts.wrap then m = opts.wrap(m) end
  local p = planner.new({ budgetMs = opts.budgetMs, searchOpts = { model = m, clock = clock },
                          hysteresis = opts.hysteresis, hold = opts.hold, holdFactor = opts.holdFactor })
  local rt = { pending = nil }
  runtime.mark(rt, "target")
  local elapsed, t = 0, 0
  local casting
  local r = { frames = 0, presses = 0, changes = 0, quiet = 0, late = 0, eventChanges = 0, searches = 0,
              frameSum = 0, frameMax = 0, mismatch = 0, dmg = 0, log = {} }
  local prevKey, prevAt
  local job, jobFrames
  local seconds = opts.seconds or 60
  while t < seconds - 1e-9 do
    elapsed = elapsed + F.FRAME
    local ev = rt.pending
    local replan = (ev and not (runtime.THROTTLED[ev.kind] and elapsed < runtime.MIN_GAP)) or elapsed >= runtime.PULSE - 1e-9
    if replan then
      rt.pending, elapsed = nil, 0
      p:update(S, ev or { kind = "pulse" })
    elseif p:busy() then
      p:work(opts.budgetMs)
    end
    -- search bookkeeping: frames per search, and the finished result against a whole search
    if p.job ~= job then
      if job and job.search.result then
        -- this frame finished it
        jobFrames = jobFrames + 1
        r.searches = r.searches + 1
        r.frameSum, r.frameMax = r.frameSum + jobFrames, math.max(r.frameMax, jobFrames)
        r.msSum = (r.msSum or 0) + (job.search.ms or 0)
        if opts.budgetMs then
          local whole = search.best(job.s, { model = model })
          local got = job.search.result
          local k1, k2 = whole.steps[1] and whole.steps[1].key, got.steps[1] and got.steps[1].key
          if k1 ~= k2 or math.abs(whole.value - got.value) > 1e-6 then r.mismatch = r.mismatch + 1 end
        end
      end
      job, jobFrames = p.job, 0
      if job then jobFrames = 1 end -- started (and run once) this frame
    elseif job then
      jobFrames = jobFrames + 1
    end
    local view = p:view(S.now)
    local st = view and view.steps[1]
    local key, at = st and st.key, st and st.at
    r.frames = r.frames + 1
    local pressedNow = false
    if prevKey ~= nil or key ~= nil then
      if key ~= prevKey then
        local trig = view and view.trigger and view.trigger.kind or "pulse"
        if not r.justPressed then
          r.changes = r.changes + 1
          if trig == "pulse" then r.quiet = r.quiet + 1 else r.eventChanges = r.eventChanges + 1 end
          if prevAt and prevAt <= F.LATE then r.late = r.late + 1 end
          if opts.trace then r.log[#r.log + 1] = ("t=%.2f %s -> %s (%s, was at %.2f)"):format(t, tostring(prevKey), tostring(key), trig, prevAt or -1) end
        end
      end
    end
    r.justPressed = false
    -- the bot presses the big icon once it says "now" and the button is ready
    local S1, d
    if key and at <= 1e-9 and (S.gcdRemains or 0) <= 1e-9 and (S.castRemains or 0) <= 1e-9 then
      local ready = model.readyIn(S, key)
      if ready and ready <= 1e-9 then
        S1, d = model.apply(S, key, F.FRAME)
        S1 = roll(S, S1, key, rng)
        r.presses = r.presses + 1
        pressedNow = true
        if (S1.castRemains or 0) > 1e-9 then casting = key end
        runtime.mark(rt, "cast", key)
      end
    end
    if not S1 then
      S1, d = model.wait(S, F.FRAME)
      S1 = roll(S, S1, nil, rng)
      if casting and (S1.castRemains or 0) <= 1e-9 then
        runtime.mark(rt, "cast", casting, true)
        casting = nil
      end
      for _, h in ipairs({ "mh", "oh" }) do
        if S.swing[h] and S1.swing[h] and S1.swing[h].next > S.swing[h].next then runtime.mark(rt, "swing") end
      end
    end
    if math.floor(S1.buffs.mw.stacks + 1e-9) ~= math.floor(S.buffs.mw.stacks + 1e-9) then runtime.mark(rt, "aura") end
    r.dmg = r.dmg + d
    S = S1
    t = t + F.FRAME
    -- the press shows up in the next frame: that change of the first button is no flip
    r.justPressed = pressedNow
    prevKey, prevAt = key, at
    if pressedNow then prevKey = key end
  end
  r.seconds = seconds
  return r
end

return F
