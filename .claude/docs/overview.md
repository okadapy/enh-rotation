# System Overview

## Data Flows

### Fight review (addon)
1. The player presses a button; `runtime.logPress` calls `env.onPress({ t, key, sug, due, last })`, where `sug` is the first step of the shown plan and `last` is `planner.last` (the last finished search with `firstValue`).
2. `addon/core.lua` forwards it to `review:press`, which feeds `fightlog` (only between `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED`); `fightlog:tick` samples the engine state every 0.5 s (Maelstrom Weapon, GCD idle, prep, Flame Shock).
3. On `PLAYER_REGEN_ENABLED` (fight of 20 s and 10 presses or more) `review` values the copied presses one per frame, then `advice.tips` builds the tips and `history` stores the fight (session list, boss record in `DoubtMyRotationCharDB.fights`, trend).
4. Outcome: a chat line (option `fightSummary`) and the window `fightwin` via `/dmr last` or `/dmr history`.
