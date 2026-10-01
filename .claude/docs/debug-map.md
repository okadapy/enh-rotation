# Debug Map

<!-- Add entries as recurring bug categories surface:
     ## If X is broken — see file1, file2, serviceY -->

## If the fight review shows odd losses or no review appears — see
- `addon/fightlog.lua` (thresholds `MIN_SECONDS`, `MIN_PRESSES`, `STALE`, `LATE`, `MAX_COPIES`)
- `src/search.lua` (`firstValue`), `src/planner.lua` (`last`), `src/runtime.lua` (`logPress` / `env.onPress`)
- `addon/review.lua` (events, valuing of copies out of combat)
