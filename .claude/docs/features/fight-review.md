# Fight review

## Goal
After a fight (20 s and 10 presses minimum) the addon gives the player a short chat line and a window (`/dmr last`, `/dmr history`) with tips: which wrong button replaced the suggested one and what it cost, late presses, wasted Maelstrom Weapon, idle GCD, missing prep (shield, totems, enchants, auto-attack), Flame Shock uptime, plus a trend against previous fights on the same boss.

## Scope
- Engine hooks: `src/search.lua` (`result.firstValue`), `src/planner.lua` (`planner.last`), `src/runtime.lua` (`env.onPress` called from `logPress`, also when recording is off).
- Addon: `addon/fightlog.lua` (collector, no game API, deps injected), `addon/advice.lua` (pure tip functions, weights in damage), `addon/history.lua` (session list + per-boss records in `DoubtMyRotationDB.fights`, trend), `addon/fightwin.lua` (window, pure text functions), `addon/review.lua` (events, valuing copied presses out of combat one per frame, chat line).
- Wiring: `addon/core.lua` (`env.onPress`, `/dmr last|history`), `addon/settings.lua` + `addon/panel.lua` (option `fightSummary`), `tools/build.lua` `B.ADDON_MODULES`.
- Design: `docs/superpowers/specs/2026-10-01-fight-review-design.md`.

## Changes
- Added: the five addon modules above; specs `spec/addon_{fightlog,advice,history,fightwin,review}_spec.lua`.
- Modified: search/planner/runtime hooks, core/settings/panel, game mock, build registration.
- Removed: nothing.

## Risks
- A press is rated only against the last finished search (`planner.last`); if that search is older than `fightlog.STALE` (0.5 s) the press counts as "stale plan", not a mistake. A press later than `LATE` (1.5 s) after the button was due is "late", also not wrong.
- Presses whose key is missing in `firstValue` are copied (`recorder.copy(last.s)`, max `MAX_COPIES` = 30 per fight) and priced after combat; over the cap they are "unrated". A new fight starting before the copies are valued leaves the rest unrated.
- `firstValue` must stay in sync with `byFirst` in `search`; changing the search scoring changes the loss numbers (see decisions/price-press-from-first-value.md).
- History in SavedVariables is capped (`BOSS_FIGHTS`, `BOSS_MAX`); the shape of `DoubtMyRotationDB.fights` is persistent state.
- `src/` must stay free of `WeakAuras`/game API: the hook is `env.onPress`, supplied by the host.

## How to test
- [ ] `docker compose run --rm test busted spec/addon_fightlog_spec.lua spec/addon_advice_spec.lua spec/addon_history_spec.lua spec/addon_fightwin_spec.lua spec/addon_review_spec.lua`
- [ ] `busted spec/search_spec.lua spec/planner_spec.lua spec/runtime_spec.lua` (hooks)
- [ ] In game: fight a dummy 30+ s, check chat line, `/dmr last`, `/dmr history`, toggle the "Fight summary in chat" option.

## Related modules
- No module docs yet; see `.claude/rules/ARCHITECTURE.md` (addon table) and `overview.md` (fight review flow).
