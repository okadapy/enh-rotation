# Price a press from the running search's firstValue

## Problem
The fight review needs to know how much damage a wrong button cost. Re-simulating every press against the suggestion in the addon would double the engine's work during combat and risk frame time (search budget is ~2 ms per frame).

## Decision
`search` returns `firstValue[firstButton]` (score of the best chain per first button, after `fillIdle` when it was filled) next to `byFirst`. The planner keeps the last finished search as `planner.last = { now, value, firstValue, s }`, and `runtime` passes it to `env.onPress`. Loss of a press = best `firstValue` minus the pressed key's value (`key` or `key+swing`, the larger). Presses with no entry are priced after combat from a copy of the searched state, one per frame.

## Reasoning
The search already computed these scores, so pricing costs nothing during combat. Using the same scores as the suggestion keeps the review consistent with what the player saw.

## Consequences
- Loss is only as good as the last search: staleness (>0.5 s) and lateness (>1.5 s) are classified separately instead of blamed on the player.
- Keys outside the beam are unpriced during combat; copies are capped (30 per fight), the rest is "unrated".
- Any change to how search scores chains alters review numbers; `spec/search_spec.lua` checks `firstValue`.
- Must not change search results bit for bit (see perf rules in `AGENTS.md`); `firstValue` only records existing scores.
