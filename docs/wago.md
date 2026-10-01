# EnhRot — wago.io listing

Copy the sections below into the wago.io form. Title, then the description (wago renders Markdown).

**Title:** EnhRot — Enhancement Shaman rotation helper (3.3.5a)

**Game version:** Wrath of the Lich King, 3.3.5a (WeakAuras 5.22 backport). Not for WotLK Classic or Retail.

**Tags:** Shaman, Enhancement, Rotation, Swing timer, Leveling

---

## What it does

EnhRot shows, on one short timeline, what to press now and what comes next, together with your weapon swings and the window in which a Lightning Bolt fits without delaying a swing.

There is no fixed priority list inside. A small combat simulator tries sequences of buttons over the next 6 seconds and picks the one that deals the most damage. It accounts for mana, cooldowns, Maelstrom Weapon stacks, swing timing, totems, the number of enemies and how long the target will live.

- **Big icon** — press this. **Icons to the right** — what follows, each at its time.
- **Tick marks** — your coming main-hand (gold) and off-hand (grey) swings.
- **Green band** — start a 1–4 stack Lightning Bolt here and the swing is not delayed.
- **Dots** — Maelstrom Weapon stacks.
- **Alert icon with text** — auto-attack off, shield missing, weapon imbue missing, low mana, out of range, Bloodlust ready; when nothing is worth pressing it says why (`Move into melee`, `Drink`, `Out of mana`, `Auto-attack: save mana`).
- **Text under the icon** — why this button (e.g. `5 stacks: instant`, `pull: target out of melee`).

The suggestion changes only after a combat event, and only when the new plan is clearly better (8%). It does not flicker between two equal buttons.

## Modes

`auto` picks from your group: **solo** treats mana as something you will have to drink back and ignores damage past the mob's health. **group/raid** spend mana freely.

## Options (Custom Options tab)

Scale, timeline length, icons shown, mode, reason text. Feral Spirit / Fire Elemental / Shamanistic Rage: auto (bosses and long fights) / boss only / always / never. Weaving: the fewest Maelstrom stacks for a Lightning Bolt / Chain Lightning in melee — 3+ (default) / 5 / any (the model decides); at range and without the Maelstrom Weapon talent any stack count is allowed. Mana policy (solo): balanced (default, mana priced by the time to drink it back with your level's water) / save (1.5x the price: fewer spells, less drinking) / spend (0.5x: more spells, more drinking). Lightning Shield or Water Shield. Bloodlust-ready alert (off by default). Snapshot recording and export for bug reports.

## Status

- **Solo leveling** is tested on recorded in-game fights (levels 52–54).
- **Group / raid at 80** is checked against the wowsims/wotlk priority (18 situations) and a combat simulation, **not yet in a real raid**: treat it as beta and report what looks wrong.
- Any client language is supported for talents (read through spell IDs).
- **Not yet verified in game:** the swing rules behind weaving. The model assumes a Lightning Bolt / Chain Lightning with 1–4 Maelstrom stacks only *delays* the next swing to the end of the cast, while a 0-stack cast *resets* it (this rule comes from existing swing-timer packs). That is why the **Weaving** option defaults to 3+ stacks, the conservative choice until the rule is verified: 1–2 stack hard-casts are suggested only with Weaving set to "any (model decides)" (worth about 2% if the rule holds). If your server behaves differently, please report it with an export string.
- **Assumed, not measured:** Shamanistic Rage returns mana as a proc at 10 per minute per weapon (the 3.3.5a spell data; wowsims uses 15), and solo mana is priced by the drink of your level (time spent drinking instead of fighting). The solo **Mana policy** option shifts that price if you prefer to save or spend mana.

## First run

After import the bar sits a little below the screen centre. Move it: `/wa` → the `EnhRot` group → drag. Stand at a training dummy with auto-attack on: gold ticks are your coming swings, and the text next to any alert tells you what is missing.

## Not included

Interrupts, purges, healing, utility. Support totems (Windfury, Strength of Earth, …) are counted roughly, through Call of the Elements.

## Reporting a problem

Enable **Record snapshots**, repeat the situation, enable **Export snapshots** and paste the string into an issue: <https://github.com/okadapy/enh-rotation/issues>. It contains only the combat state, the shown plan and your presses.

## Source and credits

Source, tests and releases: <https://github.com/okadapy/enh-rotation> (MIT).

Swing timer ideas come from “WOTLK Swingtimer cast weaving indicator” by Ralgathor (<https://wago.io/joURtkngg>) and its 3.3.5a backport by chinpira (<https://wago.io/QwrJHa-h4>); the code was rewritten independently. Priorities and formulas are checked against [wowsims/wotlk](https://github.com/wowsims/wotlk) (MIT).

Not affiliated with Blizzard Entertainment.

---

## Publishing checklist (maintainer)

1. Import string: `EnhRot.txt` from the v1.0.0 GitHub release.
2. Screenshots: the bar in melee with ticks, the green window and a 3-stack Bolt; an alert with text; the options tab. A short pull GIF if possible.
3. After the first upload wago gives the aura a slug and version. The WeakAuras Companion app then offers updates for new wago versions: each release is uploaded as a new version of the same wago page (Import → "update existing").
4. Licence field: MIT.
