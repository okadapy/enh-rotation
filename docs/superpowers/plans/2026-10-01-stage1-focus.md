# Этап 1 — меньше внимания на ленту, понятнее почему: план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Игрок не ищет иконку глазами: нужная кнопка горит прямо на его панели (стандартной или ElvUI), под крупной иконкой ленты написана её клавиша, наведение на иконку объясняет «почему эта и что на втором месте», а окно «всё ли готово» и строка «к тренеру» ловят то, что ломает подсказку ещё до боя.

**Architecture:** Всё — только в аддоне (`addon/`): строка ауры у лимита (`B.MAX_IMPORT`). Движок `src/` меняется в одном месте — `planner` запоминает лучшую цепочку каждой первой кнопки из последнего поиска (`planner.alts`; `search` уже отдаёт её как `byFirst`), поиск не трогается вовсе. Помощники аддона читают движок только через `core.view()` (план, снимок, кэш имён, планировщик, крупная иконка ленты) и рисуют своими рамками и текстурами поверх чужих кнопок — ни одна защищённая рамка не меняется. Сопоставление кнопок — набор «источников» (`actionbars.SOURCES`): стандартные панели Blizzard и любые панели на LibActionButton-1.0 (ElvUI — `LibActionButton-1.0-ElvUI`; Bartender4 — тот же LAB); новый источник — одна запись.

**Tech Stack:** Lua 5.1 (клиент 3.3.5a, Interface 30300), busted 2.2.0 в Docker (`docker compose run --rm test …`).

**Spec:** этап 1 дорожной карты `docs/superpowers/specs/2026-10-01-addon-roadmap.md` (пункты «Подсветка нужной кнопки», «Почему эта кнопка», «Всё ли готово», «Ранги устарели»; «Разбор после боя» — вне этого плана) и её раздел «Чего не делать». Перед работой прочитать `AGENTS.md` (конвенции, «Поиск и скорость») и `.claude/rules/ARCHITECTURE.md` (карта). Контракты исполнителей — `docs/superpowers/plans/2026-10-01-stage1-contracts.md`.

## Решения (по умолчанию, пользователь может поправить до начала)

- **Вне объёма:** Разбор после боя — отдельная работа, файлы recorder/report и `/dmr last` не трогать.
- Ветка `feat/stage1-focus` от `main` после слияния PR #30 (`git fetch origin` — в `main` должен быть `addon/`); в `main` — только через PR.
- **Подсветка:** на всех видимых кнопках с нужным заклинанием (на двух панелях — обе) — своя рамка-текстура `Interface\Buttons\UI-ActionButton-Border` (как `timeline.GLOW`), режим `ADD`, мягкая пульсация. Горит, когда крупная иконка «пора жать» (до кнопки ≤ 0,3 с — тот же порог, что у свечения ленты `timeline.DEFAULTS.glowAt`), и только при враждебной цели. Свою рамку кладём поверх кнопки (`SetPoint("CENTER", button)`, слой и уровень — как у кнопки + 10), родитель — `UIParent`, у самой кнопки ничего не вызываем.
- **Клавиша:** первая привязка первой видимой кнопки с этим заклинанием, коротко (`SHIFT-E` → `S-E`, `CTRL-2` → `C-2`, `BUTTON4` → `M4`, колесо → `MwU`/`MwD`, `NUMPAD1` → `N1`). Пишется мелким контурным шрифтом (`NumberFontNormal`) **в нижней части крупной иконки** — прямо под иконкой уже стоит подпись «почему» (`timeline` рисует её на `ICON_Y - size/2 - 4`), а `timeline` (общий с аурой) не трогаем. Нет кнопки на панелях — клавиши нет.
- **`GetActionInfo(slot)` в 3.3.5a:** `"spell", <номер в книге>, "spell", <spellID>` (так читает его LibActionButton ElvUI: `Action.GetSpellId` берёт 4-й ответ), для макроса — `"macro", <номер макроса>`. Сопоставление — по **имени** заклинания (имена у всех рангов одни): `GetSpellInfo(spellID)`, без 4-го ответа — `GetSpellName(номер, "spell")`, у макроса — `GetMacroSpell(номер)`; имя → наш `key` через `cache.keyByName` движка (`snapshot.scan`). Так ранги, макросы и локализация сходятся без таблиц id. Проверка в игре — задача 6.
- **ElvUI:** кнопки берутся из реестра LAB (`LibStub("LibActionButton-1.0-ElvUI", true).buttonRegistry`, тот же для `LibActionButton-1.0`), а не по именам `ElvUI_Bar<N>Button<M>`: так видны все панели ElvUI (1–6 и будущие) и Bartender4. Действие кнопки — `button._state_type` / `button._state_action` (тип `"action"` → слот, `"spell"` → spellID, `"macro"` → номер), клавиша — `GetBindingKey(button.config.keyBoundTarget)` (ElvUI ставит `ACTIONBUTTON1`, `MULTIACTIONBAR2BUTTON3`, `ELVUIBAR6BUTTON5`…), иначе `GetBindingKey("CLICK <имя>:LeftButton")`. Скрытые панели (у ElvUI стандартные спрятаны в `UIHider`) отсекаются `IsVisible()`.
- **Подсказка при наведении:** лента мышь не берёт никогда (рамка `EnableMouse` не включается): раз в 0,1 с опрашиваем `IsMouseOver()` своей невидимой рамки над крупной иконкой. Вне боя — подсказка по наведению; в бою — только пока зажат Shift (в бою — никаких всплывашек сами по себе). Содержимое: название и клавиша; «Press now» / «Press in 1.2 s»; «Why: <search.reason>»; «Then: …» (следующие кнопки плана); «Runner-up: <кнопка> - 7% worse over the next 6 s» или «about as good». Второе место — лучшая цепочка другой первой кнопки из того же поиска (`planner.alts`), обе цепочки переигрываются `search.evaluate` на одном и том же состоянии (`planner:prepare(S)`); процент — от ценности плана внутри горизонта. Считается только пока подсказка открыта, раз в секунду.
- **«Всё ли готово»:** своё окно-список с галочками (`Interface\RaidFrame\ReadyCheck-Ready` / `ReadyCheck-NotReady`) и подсказкой «что сделать» под каждым красным пунктом: чары на правом и левом оружии, щит, тотем каждой стихии на панели Call of the Elements (с 30 ур., если заклинание выучено), таланты (вложены и узнаны), свежие ранги. Открывается само один раз — при первом входе шамана (через 3 с, не в бою; `DoubtMyRotationDB.readySeen`), дальше по `/dmr check`. Пока окно открыто — обновляется раз в секунду (повесил чары — пункт позеленел).
- **«Ранги устарели»:** есть ранг для твоего уровня (`src/spells_data.lua`, поле `level`), а у тебя ниже или нет вовсе → одна строка в чат при входе и при новом уровне: `the trainer has new ranks: Lightning Bolt 12, Earth Shock 7 - /dmr check`. Заклинания талантов (Stormstrike, Lava Lash, Shamanistic Rage, Feral Spirit) не в счёт. Одна и та же строка — не чаще раза за сессию.
- **Настройки** (все отключаемые, применяются сразу, без перезапуска движка): «Light up the button to press on your action bars» (`highlightButtons`), «Show its key on the big icon» (`showKeybind`), «Explain the big icon on mouse-over (Shift in combat)» (`hoverTips`) — страница General; «Show the checklist on first login» (`readyCheck`), «Tell me when the trainer has new ranks» (`rankWarning`) — Advanced. Всё по умолчанию включено. Новой страницы не заводим.
- **Слэш-команда:** `/dmr check` — окно «всё ли готово».
- Оформление окон под ElvUI (скины) — этап 3, здесь — стандартный `UI-DialogBox`.

### Ответы пользователя на открытые вопросы (2026-10-01)

1. Клавиша — внутри нижнего края крупной иконки (под иконкой — подпись «почему»), как в плане.
2. Бледной подсветки следующей кнопки заранее нет: подсветка — только «пора жать».
3. «Всё ли готово»: окно само — только при первом входе (`readySeen`), как в плане; **дополнительно** при следующих входах, если хоть один пункт красный, — одна строка в чат `something is not ready yet - /dmr check` (раз за сессию, вне боя, отключается той же опцией `readyCheck`).
4. Bartender4 через LibActionButton — допущение, проверяется на ElvUI у пользователя; Dominos вне объёма.
5. Проверки «только в игре» — в задаче 6 на клиенте пользователя (ElvUI Rebuffed 6.10).

## Global Constraints

- Lua 5.1. В `src/` нельзя `pcall`, `loadstring`, `setfenv`, `getfenv`, `_G`, `SlashCmdList`, `package`, `io`, `debug` — даже в комментариях (`spec/build_spec.lua`). В `addon/` `_G` можно (не песочница), но `io`, `package`, `debug`, `require` клиента нет — `require` даёт сборка.
- Только API 3.3.5a: никаких `ActionButton_ShowOverlayGlow`, `C_Timer`, `Settings.*`, `GetSpellBookItemName`, `RegisterAddonMessagePrefix`; таймеры — через `OnUpdate`. Сверять с FrameXML 3.3.5a (`https://raw.githubusercontent.com/wowgaming/3.3.5-interface-files/main/<файл>`).
- **Никаких действий с защищёнными рамками:** у кнопок Blizzard/ElvUI/LAB только чтение (`IsVisible`, `GetName`, `GetWidth`, `GetFrameLevel`, `GetFrameStrata`, `GetEffectiveScale`, поля `action`, `_state_type`, `_state_action`, `config`, `buttonType`) и привязка **своих** рамок к ним. Нельзя `SetParent`, `SetPoint`, `Show`/`Hide`, `SetAttribute`, `HookScript`, `CreateTexture`/`CreateFontString` у чужой кнопки, нельзя трогать `UISpecialFrames`.
- Своя рамка, накрывающая ленту, не берёт мышь (`EnableMouse(true)` не вызывать).
- `src/search.lua` не менять. Изменение `src/planner.lua` — только запоминание `alts`/`altsNow`; результаты бит в бит (`spec/recorded_spec.lua`, `spec/perf_spec.lua`, `spec/leveling_spec.lua`, `spec/wowsims_spec.lua` без правок ожиданий).
- Строка импорта ауры ≤ `B.MAX_IMPORT` (63000; сейчас ~60,7 КБ); новые модули — только в `B.ADDON_MODULES`, не в `B.MODULES`.
- Тексты в игре — на английском, мягко («can do better», без «bad»).
- Все команды — в контейнере: `docker compose run --rm test busted …`, на хосте Lua нет.
- Коммиты — по-русски, в стиле `git log` (`Аддон: …`), без номеров задач и без упоминаний ИИ (`Co-Authored-By`, «Generated with» запрещены).
- `src/spells_data.lua` руками не править.

## Review Focus

1. **Taint.** Ни одного вызова-записи у чужих кнопок (см. Global Constraints); тест задачи 4 проверяет, что у кнопок-моков не появилось ни точек привязки, ни дочерних регионов, ни скриптов, ни смены родителя. В игре — бой 2–3 минуты с подсветкой и подсказками при `/console taintLog 1`: в `Logs/taint.log` нет `DoubtMyRotation`, в чате нет «Interface action failed because of an AddOn» (задача 6).
2. **Клики в бою.** Рамка над иконкой мышь не берёт (`EnableMouse` не вызывается, тест задачи 2); клик по мобу «сквозь» ленту в бою выбирает моба (задача 6). Подсказка в бою — только с Shift.
3. **Скорость.** Подсветка: за кадр — поиск одного ключа в таблице и `SetAlpha` горящих рамок; пересканирование панелей — по событиям и не чаще раза в секунду (тест: число вызовов `scan`). Подсказка: `search.evaluate` (до 12 цепочек) — только пока она открыта, раз в секунду; тест `#perf` — `explain.rivals` в среднем ≤ 3 мс × `ENHROT_PERF_FACTOR` на 30 состояниях 80 уровня. `perf_spec` не меняется и зелёный.
4. **Бит в бит.** `planner` только запоминает ссылку на `byFirst` и время поиска; `recorded_spec`, `leveling_spec`, `wowsims_spec`, `perf_spec` — без правок ожиданий.
5. **Моки ≠ клиент** (каждое — пункт ручной проверки задачи 6): 4-й ответ `GetActionInfo` для заклинаний; `GetSpellName(i, "spell")`; `GetMacroSpell`; `GetMultiCastBarOffset() == 6` и слоты Call of the Elements 133–136 (`HasAction`); `IsMouseOver()` у рамки, привязанной к текстуре; `GameTooltip:IsOwned`; поля `_state_type`/`_state_action`/`config.keyBoundTarget` у кнопок ElvUI (LAB-ElvUI MINOR 67); `GetEffectiveScale` у кнопок ElvUI (рамка совпадает с кнопкой по размеру); шрифт `NumberFontNormal`.
6. **Без ElvUI / с ElvUI / с Bartender4.** Без ElvUI — стандартные панели; с ElvUI — его кнопки (стандартные скрыты и отсеяны); одно заклинание на двух панелях — горят обе; нет кнопки — нет подсветки и клавиши, ошибок нет; LibStub нет — источник LAB молчит.
7. **Перезапуск движка** (смена настройки, ошибка, сон за скрытой рамкой) — помощники берут свежий `core.view()` каждый раз; рамок-подсветок не больше, чем кнопок (по одной на кнопку на всю сессию); спящий/остановленный движок — ничего не горит.
8. **«Всё ли готово» не надоедает:** окно само — один раз за жизнь персонажа и не в бою; строка про ранги — раз за сессию на уровень; обе отключаются.
9. **Аура не меняется**, кроме двух строк `planner` (размер строки импорта — тест `build_spec`).

---

## Карта файлов

- Create `addon/actionbars.lua` — источники кнопок (Blizzard, LibActionButton), слот → имя заклинания, клавиши, `scan(keyByName) -> map`.
- Create `addon/highlight.lua` — рамки-подсветки над кнопками, клавиша на крупной иконке.
- Create `addon/explain.lua` — подсказка при наведении: `rivals` (второе место), `lines` (текст), опрос мыши.
- Create `addon/ready.lua` — «всё ли готово»: `ranks`, `items`, `gather`, окно, вход/новый уровень.
- Create `addon/helpers.lua` — опции помощников и их запуск одним вызовом из `core`.
- Modify `src/planner.lua` — `self.alts`, `self.altsNow` в `P:finish`.
- Create `spec/support/bars_mock.lua` — API панелей 3.3.5a поверх `game_mock` (кнопки Blizzard, кнопки ElvUI/LAB, `GetActionInfo`, `GetBindingKey`, `GetMacroSpell`, `GetSpellName`, `HasAction`, уровень и слой рамок, `IsMouseOver`, `GetEffectiveScale`).
- Create `spec/addon_actionbars_spec.lua`, `spec/addon_highlight_spec.lua`, `spec/addon_explain_spec.lua`, `spec/addon_ready_spec.lua`, `spec/addon_helpers_spec.lua`; Modify `spec/planner_spec.lua`.
- **Общие файлы, возможны конфликты с параллельной работой** (правки минимальные, только задача 5):
  - `addon/core.lua` — опции помощников к списку, `M.view()`, запуск `helpers.start` в `login`, действие `check` в `handle`;
  - `addon/settings.lua` — `ACTIONS.check`, строка в `HELP`;
  - `addon/panel.lua` — ключи новых опций в `M.SECTIONS` (General и Advanced);
  - `tools/build.lua` — пять модулей в `B.ADDON_MODULES` перед `core`;
  - `spec/support/game_mock.lua` — имена новых глобальных рамок в списке сброса `DoubtMyRotation*`;
  - `spec/addon_core_spec.lua`, `spec/addon_settings_spec.lua`, `spec/addon_panel_spec.lua`, `spec/build_spec.lua` (блок `describe("addon build", …)`) — новые тесты;
  - `README.md`, `.claude/rules/ARCHITECTURE.md`, `AGENTS.md`.

---

### Task 1: Источники кнопок — `addon/actionbars.lua`

**Files:**
- Create: `addon/actionbars.lua`
- Create: `spec/support/bars_mock.lua`
- Test: `spec/addon_actionbars_spec.lua`

**Interfaces:**
- Consumes: `cache.keyByName` движка (`snapshot.scan`: локализованное имя заклинания → `key`); клиентские `GetActionInfo`, `GetSpellInfo`, `GetSpellName`, `GetMacroSpell`, `GetBindingKey`, `ActionButton_GetPagedID`, `LibStub`.
- Produces:
  - `actionbars.short(binding) -> string | nil` — короткая запись клавиши.
  - `actionbars.spellOfSlot(slot) -> name | nil`.
  - `actionbars.blizzard`, `actionbars.lab` — источники: `{ name, buttons(out) }`, `buttons` добавляет в `out` записи `{ frame, name, spell, binding }` только видимых кнопок.
  - `actionbars.SOURCES = { actionbars.blizzard, actionbars.lab }`.
  - `actionbars.scan(keyByName, sources?) -> { [key] = { buttons = { entry… }, hotkey = "S-E" | nil } }`.
  - `bars_mock.install(cfg)` (после `G.install`), `bars_mock.blizzard(name, slot, shown?)`, `bars_mock.elvui(bar, i, kind, action, bindTarget?)`, `bars_mock.labs`; `cfg = { actions = { [slot] = { kind, id, sub, spellId } }, book = { [i] = name }, macros = { [i] = name }, bindings = { [command] = key }, lockdown, shift }`.

- [ ] **Step 1: Мок `spec/support/bars_mock.lua`.**

```lua
-- The action bars of the 3.3.5a client on top of game_mock: Blizzard buttons, LibActionButton
-- buttons (ElvUI), the action / binding / macro API, frame levels and the mouse-over test.
-- Call B.install(cfg) after G.install().
local B = {}

B.BLIZZARD = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
               "MultiBarRightButton", "MultiBarLeftButton" }

function B.install(cfg)
  cfg = cfg or {}
  B.cfg = cfg
  local create = _G.CreateFrame
  _G.CreateFrame = function(kind, name, parent, template)
    local f = create(kind, name, parent, template)
    f.frameName, f.parent, f.level, f.strata = name, parent, 1, "MEDIUM"
    function f:GetName() return self.frameName end
    function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameStrata(s) self.strata = s end
    function f:GetFrameStrata() return self.strata end
    function f:GetEffectiveScale() return self.effScale or 1 end
    function f:IsMouseOver() return self.mouseOver and true or false end
    return f
  end
  local actions = cfg.actions or {}
  _G.GetActionInfo = function(slot)
    local a = actions[slot]
    if a then return a[1], a[2], a[3], a[4] end
  end
  _G.HasAction = function(slot) return actions[slot] and 1 or nil end
  _G.GetSpellName = function(i) return (cfg.book or {})[i] end
  _G.GetMacroSpell = function(i) return (cfg.macros or {})[i] end
  _G.GetBindingKey = function(cmd) return (cfg.bindings or {})[cmd] end
  _G.InCombatLockdown = function() return cfg.lockdown and 1 or nil end
  _G.IsShiftKeyDown = function() return cfg.shift and 1 or nil end
  _G.NUM_ACTIONBAR_PAGES = 6
  _G.GetMultiCastBarOffset = function() return 6 end
  _G.ActionButton_GetPagedID = function(b) return b.action end
  for _, bar in ipairs(B.BLIZZARD) do for i = 1, 12 do _G[bar .. i] = nil end end
  for n = 1, 10 do for i = 1, 12 do _G[("ElvUI_Bar%dButton%d"):format(n, i)] = nil end end
  B.labs = {}
  local stub = _G.LibStub
  _G.LibStub = function(name, silent)
    if B.labs[name] then return B.labs[name] end
    return stub and stub(name, silent)
  end
end

-- someone else's button: a protected frame in the client. A test can see whether it was moved
-- to another parent (points, children, scripts and hooks are on the game_mock frame already)
local function protected(b)
  local setParent = b.SetParent
  function b:SetParent(p) self.parentSet = true; setParent(self, p) end
  return b
end

-- a Blizzard bar button on slot (its action field, as ActionButton_UpdateAction leaves it)
function B.blizzard(name, slot, shown)
  local b = protected(CreateFrame("CheckButton", name, UIParent, "ActionBarButtonTemplate"))
  b.action, b.w, b.h = slot, 36, 36
  if shown == false then b:Hide() end
  return b
end

-- an ElvUI button: in LibActionButton-1.0-ElvUI's registry, with its state and binding target
function B.elvui(bar, i, kind, action, bindTarget)
  local b = protected(CreateFrame("CheckButton", ("ElvUI_Bar%dButton%d"):format(bar, i), UIParent))
  b._state_type, b._state_action = kind, action
  b.config = { keyBoundTarget = bindTarget }
  b.w, b.h = 30, 30
  local major = "LibActionButton-1.0-ElvUI"
  B.labs[major] = B.labs[major] or { buttonRegistry = {} }
  B.labs[major].buttonRegistry[b] = true
  return b
end

return B
```

- [ ] **Step 2: Тест `spec/addon_actionbars_spec.lua`.**

```lua
local G = require("game_mock")
local B = require("bars_mock")
local spells = require("spells")
local actionbars = require("actionbars")

local function top(key) local r = spells.byKey[key].ranks; return r[#r] end
local NAMES = { ["Stormstrike"] = "stormstrike", ["Lava Lash"] = "lavaLash", ["Lightning Bolt"] = "lightningBolt" }

local function install(cfg)
  G.install({})
  B.install(cfg)
end

describe("action bar buttons", function()
  it("a standard bar button with a spell gives the spell's key and the button's key", function()
    install({ actions = { [3] = { "spell", 40, "spell", top("lightningBolt") } },
              bindings = { ACTIONBUTTON3 = "3" } })
    local b = B.blizzard("ActionButton3", 3)
    local map = actionbars.scan(NAMES)
    assert.are.equal(b, map.lightningBolt.buttons[1].frame)
    assert.are.equal("3", map.lightningBolt.hotkey)
  end)

  it("the bars ElvUI hides are skipped; its own buttons count, with ElvUI's binding target", function()
    install({ actions = { [1] = { "spell", 12, "spell", top("stormstrike") } },
              bindings = { ACTIONBUTTON1 = "SHIFT-E" } })
    B.blizzard("ActionButton1", 1, false)
    local e = B.elvui(1, 1, "action", 1, "ACTIONBUTTON1")
    local map = actionbars.scan(NAMES)
    assert.are.equal(1, #map.stormstrike.buttons)
    assert.are.equal(e, map.stormstrike.buttons[1].frame)
    assert.are.equal("S-E", map.stormstrike.hotkey)
  end)

  it("an ElvUI button with no key on its target takes its click binding", function()
    install({ actions = { [16] = { "spell", 9, "spell", top("lavaLash") } },
              bindings = { ["CLICK ElvUI_Bar2Button4:LeftButton"] = "CTRL-2" } })
    B.elvui(2, 4, "action", 16, "MULTIACTIONBAR2BUTTON4")
    assert.are.equal("C-2", actionbars.scan(NAMES).lavaLash.hotkey)
  end)

  it("LibActionButton spell and macro states are read too", function()
    install({ macros = { [2] = "Lava Lash" } })
    B.elvui(1, 5, "spell", top("stormstrike"))
    B.elvui(1, 6, "macro", 2)
    local map = actionbars.scan(NAMES)
    assert.is_truthy(map.stormstrike)
    assert.is_truthy(map.lavaLash)
  end)

  it("a macro on a slot counts as the spell it casts", function()
    install({ actions = { [5] = { "macro", 2 } }, macros = { [2] = "Lava Lash" } })
    B.blizzard("ActionButton5", 5)
    assert.is_truthy(actionbars.scan(NAMES).lavaLash)
  end)

  it("a spell slot without a spell id is read from the spellbook", function()
    install({ actions = { [7] = { "spell", 12, "spell" } }, book = { [12] = "Stormstrike" } })
    B.blizzard("ActionButton7", 7)
    assert.is_truthy(actionbars.scan(NAMES).stormstrike)
  end)

  it("items, empty slots and spells of no key are left out", function()
    install({ actions = { [1] = { "item", 33447 }, [2] = { "spell", 3, "spell", 6603 } } })
    B.blizzard("ActionButton1", 1)
    B.blizzard("ActionButton2", 2)
    B.blizzard("ActionButton4", 4)
    assert.are.same({}, actionbars.scan(NAMES))
  end)

  it("the same spell on two bars: both buttons, the first bound key", function()
    install({ actions = { [3] = { "spell", 40, "spell", top("lightningBolt") }, [27] = { "spell", 40, "spell", top("lightningBolt") } },
              bindings = { MULTIACTIONBAR2BUTTON3 = "F" } })
    B.blizzard("ActionButton3", 3)
    B.blizzard("MultiBarBottomRightButton3", 27)
    local m = actionbars.scan(NAMES).lightningBolt
    assert.are.equal(2, #m.buttons)
    assert.are.equal("F", m.hotkey)
  end)

  it("no bars and no LibStub: an empty map, no error", function()
    install({})
    _G.LibStub = nil
    assert.are.same({}, actionbars.scan(NAMES))
  end)

  it("another source is one more entry (Bartender, Dominos later)", function()
    install({})
    local f = CreateFrame("CheckButton", "OtherBarButton1", UIParent)
    local src = { name = "other", buttons = function(out) out[#out + 1] = { frame = f, name = "OtherBarButton1", spell = "Stormstrike", binding = "ALT-Q" } end }
    assert.are.equal("A-Q", actionbars.scan(NAMES, { src }).stormstrike.hotkey)
  end)

  it("short key names", function()
    local cases = { ["SHIFT-E"] = "S-E", ["CTRL-ALT-3"] = "C-A-3", BUTTON4 = "M4", ["SHIFT-BUTTON3"] = "S-M3",
                    MOUSEWHEELUP = "MwU", MOUSEWHEELDOWN = "MwD", NUMPAD1 = "N1", SPACE = "Spc", F = "F" }
    for long, short in pairs(cases) do assert.are.equal(short, actionbars.short(long), long) end
    assert.is_nil(actionbars.short(nil))
    assert.is_nil(actionbars.short(""))
  end)
end)
```

- [ ] **Step 3: Красный прогон.** `docker compose run --rm test busted spec/addon_actionbars_spec.lua` — падает: `module 'actionbars' not found`.

- [ ] **Step 4: Реализация `addon/actionbars.lua`.**

```lua
-- Which action bar buttons carry which of our spells, and their keys. A source of buttons is
-- one entry in M.SOURCES: the standard Blizzard bars, and every bar built on LibActionButton-1.0
-- (ElvUI's own copy, Bartender4). Read only: nothing here changes a button (they are protected
-- frames; the overlays of addon/highlight.lua are frames of our own).
local M = {}

M.BLIZZARD = {
  { "ActionButton", "ACTIONBUTTON" },
  { "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON" },
  { "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON" },
  { "MultiBarRightButton", "MULTIACTIONBAR3BUTTON" },
  { "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON" },
}
M.LABS = { "LibActionButton-1.0", "LibActionButton-1.0-ElvUI" }
-- the order matters: the mouse wheel before BUTTON, modifiers first
M.SHORT = {
  { "SHIFT%-", "S-" }, { "CTRL%-", "C-" }, { "ALT%-", "A-" },
  { "MOUSEWHEELUP", "MwU" }, { "MOUSEWHEELDOWN", "MwD" }, { "BUTTON(%d+)", "M%1" },
  { "NUMPAD", "N" }, { "PAGEUP", "PgU" }, { "PAGEDOWN", "PgD" }, { "SPACE", "Spc" },
}

function M.short(key)
  if not key or key == "" then return nil end
  for _, r in ipairs(M.SHORT) do key = key:gsub(r[1], r[2]) end
  return key
end

-- The spell on an action slot, by name (the same for every rank and matched against the
-- engine's localized names). 3.3.5a: "spell", spellbook index, "spell", spell id; a macro:
-- "macro", its index. Items, empty slots and the rest: nil.
function M.spellOfSlot(slot)
  if not slot or not GetActionInfo then return nil end
  local kind, id, _, spellId = GetActionInfo(slot)
  if kind == "spell" then
    if type(spellId) == "number" and spellId > 0 then return (GetSpellInfo(spellId)) end
    if id and GetSpellName then return (GetSpellName(id, "spell")) end
  elseif kind == "macro" and id and GetMacroSpell then
    return (GetMacroSpell(id))
  end
  return nil
end

-- the first key bound to any of the commands
local function bound(a, b)
  if not GetBindingKey then return nil end
  return (a and GetBindingKey(a)) or (b and GetBindingKey(b)) or nil
end

M.blizzard = { name = "blizzard" }
function M.blizzard.buttons(out)
  for _, bar in ipairs(M.BLIZZARD) do
    for i = 1, 12 do
      local name = bar[1] .. i
      local b = _G[name]
      if b and b:IsVisible() then
        local slot = b.action or (ActionButton_GetPagedID and ActionButton_GetPagedID(b))
        out[#out + 1] = { frame = b, name = name, spell = M.spellOfSlot(slot),
                          binding = bound((b.buttonType or bar[2]) .. i, "CLICK " .. name .. ":LeftButton") }
      end
    end
  end
end

-- a LibActionButton button's current state: an action slot, a spell id or a macro index
local function labSpell(b)
  local kind, action = b._state_type, b._state_action
  if kind == nil and b.GetAction then kind, action = b:GetAction() end
  if kind == "action" then return M.spellOfSlot(action) end
  if kind == "spell" and action then return (GetSpellInfo(action)) end
  if kind == "macro" and action and GetMacroSpell then return (GetMacroSpell(action)) end
  return nil
end

M.lab = { name = "LibActionButton" }
function M.lab.buttons(out)
  if not LibStub then return end
  local seen, list = {}, {}
  for _, major in ipairs(M.LABS) do
    local lib = LibStub(major, true)
    for b in pairs(lib and lib.buttonRegistry or {}) do
      if not seen[b] then seen[b] = true; list[#list + 1] = b end
    end
  end
  -- by name: the same key wins every time (pairs has no order)
  table.sort(list, function(a, c) return (a:GetName() or "") < (c:GetName() or "") end)
  for _, b in ipairs(list) do
    if b:IsVisible() then
      local name = b:GetName()
      out[#out + 1] = { frame = b, name = name, spell = labSpell(b),
                        binding = bound(b.config and b.config.keyBoundTarget, name and ("CLICK " .. name .. ":LeftButton")) }
    end
  end
end

M.SOURCES = { M.blizzard, M.lab }

function M.scan(keyByName, sources)
  local list = {}
  for _, src in ipairs(sources or M.SOURCES) do src.buttons(list) end
  local map = {}
  for _, e in ipairs(list) do
    local key = e.spell and keyByName[e.spell]
    if key then
      local m = map[key]
      if not m then m = { buttons = {} }; map[key] = m end
      m.buttons[#m.buttons + 1] = e
      if not m.hotkey and e.binding then m.hotkey = M.short(e.binding) end
    end
  end
  return map
end

return M
```

- [ ] **Step 5: Зелёный прогон.** `docker compose run --rm test busted spec/addon_actionbars_spec.lua` — всё зелёное.

- [ ] **Step 6: Коммит.**

```bash
git add addon/actionbars.lua spec/support/bars_mock.lua spec/addon_actionbars_spec.lua
git commit -m "Аддон: кнопки панелей (Blizzard и LibActionButton/ElvUI) — какое заклинание и какая клавиша"
```

---

### Task 2: Второе место — `planner.alts` и подсказка при наведении `addon/explain.lua`

**Files:**
- Modify: `src/planner.lua` (`P:finish` ~110)
- Create: `addon/explain.lua`
- Test: `spec/planner_spec.lua`, `spec/addon_explain_spec.lua`

**Interfaces:**
- Produces (planner): после каждого законченного поиска `planner.alts = result.byFirst` (`{ [firstKey] = steps }`, `at` шагов — от начала поиска), `planner.altsNow = S.now` поиска; и когда новый план принят, и когда удержан старый.
- Consumes: `view = { plan, S, at, planner, frame, icon, active }` — как `core.view()` (задача 5); `search.evaluate(S, steps) -> value, steps, horizonValue`; `search.firstKey(step)`; `search.HORIZON`.
- Produces (explain):
  - `explain.OPTION = { type = "toggle", key = "hoverTips", name = "Explain the big icon on mouse-over (Shift in combat)", default = true }`;
  - `explain.rivals(view, evaluate?, firstKey?) -> nil | { value, horizon, second = nil | { key, afterSwing, value, loss, pct } }`;
  - `explain.lines(view, elapsed, hotkey, rivals) -> nil | { { text, r, g, b }, … }`;
  - `explain.new(deps) -> e`, `deps = { view(), enabled(), hotkey(key), now(), inCombat(), shift(), tooltip, over(frame)?, evaluate?, firstKey? }`; `e:start(frame)` — `OnUpdate` на своей рамке; `e:tick(dt)`; `e.hover` — рамка над иконкой.

- [ ] **Step 1: Тест планировщика.** В `spec/planner_spec.lua` после «weighs the held first button by its best new continuation…»:

```lua
  it("keeps the last search's best chain of every first button (alts) for the addon's tooltip", function()
    local s = stubSearch({ best = 100, bestKey = "a" })
    local byFirst = { a = later("a"), b = later("b") }
    function s.best() return { value = 100, steps = later("a"), byFirst = byFirst } end
    local p = planner.new({ search = s })
    p:update(at(100))
    assert.are.equal(byFirst, p.alts)
    assert.are.equal(100, p.altsNow)
    -- the new search is no better: the old plan is held, the alternatives are the new ones
    local byFirst2 = { a = later("a"), c = later("c") }
    function s.best() return { value = 100, steps = later("c"), byFirst = byFirst2 } end
    function s.evaluate(_, steps) return 100, steps, 100 end
    p:update(at(100.5), AURA)
    assert.are.equal("a", p:view(100.5).steps[1].key)
    assert.are.equal(byFirst2, p.alts)
    assert.are.equal(100.5, p.altsNow)
  end)
```

- [ ] **Step 2: Красный прогон.** `docker compose run --rm test busted spec/planner_spec.lua` — новый тест падает (`p.alts` — `nil`).

- [ ] **Step 3: Реализация в `src/planner.lua`.** В начале `P:finish`, после `self.job = nil`:

```lua
  -- the best chain of every first button and when it was planned: the addon's tooltip names the
  -- runner-up from it (read only, nothing here decides by it)
  self.alts, self.altsNow = fresh.byFirst, s.now
```

- [ ] **Step 4: Зелёный прогон и бит в бит.** `docker compose run --rm test busted spec/planner_spec.lua spec/recorded_spec.lua spec/stability_spec.lua` — зелёное; `docker compose run --rm test busted --tags=perf` — зелёное, числа как до правки.

- [ ] **Step 5: Тест `spec/addon_explain_spec.lua`.**

```lua
local G = require("game_mock")
local Sc = require("scenario")
local planner = require("planner")
local search = require("search")
local explain = require("explain")

local function steps(...)
  local out = {}
  for i, k in ipairs({ ... }) do out[i] = { key = k, at = (i - 1) * 1.5, reason = k .. " because" } end
  return out
end

-- a planner stand-in: alts planned at altsNow, prepare marks the state it was given
local function view(planSteps, alts, altsNow)
  local S = { now = 100 }
  local p = { alts = alts, altsNow = altsNow or 100 }
  function p:prepare(s) return { now = s.now, prepared = true } end
  return { plan = { steps = planSteps }, S = S, at = 100, planner = p }
end

-- value by the chain's first key; nil: the chain cannot be played
local function evaluator(values, seen)
  return function(S, st)
    assert.is_true(S.prepared, "evaluated on the planner's state")
    if seen then seen[#seen + 1] = st end
    local v = values[st[1].key]
    if v == nil then return nil end
    return v, st, 200
  end
end
local firstKey = search.firstKey

describe("explain: the runner-up", function()
  it("the best other first button, its loss and its share of the plan's 6 s", function()
    local v = view(steps("stormstrike", "lavaLash"),
      { stormstrike = steps("stormstrike"), earthShock = steps("earthShock"), lavaLash = steps("lavaLash") })
    local r = explain.rivals(v, evaluator({ stormstrike = 1000, earthShock = 950, lavaLash = 900 }), firstKey)
    assert.are.equal(1000, r.value)
    assert.are.equal("earthShock", r.second.key)
    assert.are.equal(50, r.second.loss)
    assert.are.near(25, r.second.pct, 1e-9) -- 50 of the 200 the plan does inside the horizon
  end)

  it("the alternatives are moved on by the time since their search", function()
    local seen = {}
    local v = view(steps("stormstrike"), { earthShock = { { key = "earthShock", at = 1.0 } } }, 99.6)
    explain.rivals(v, evaluator({ stormstrike = 1, earthShock = 1 }, seen), firstKey)
    assert.are.near(0.6, seen[2][1].at, 1e-9)
  end)

  it("a chain that can no longer be played is skipped; none left: no runner-up", function()
    local v = view(steps("stormstrike"), { earthShock = steps("earthShock") })
    local r = explain.rivals(v, evaluator({ stormstrike = 1000 }), firstKey)
    assert.are.equal(1000, r.value)
    assert.is_nil(r.second)
  end)

  it("no plan, no state or no planner: nothing", function()
    assert.is_nil(explain.rivals({ plan = { steps = {} } }, evaluator({}), firstKey))
    assert.is_nil(explain.rivals({ plan = { steps = steps("stormstrike") } }, evaluator({}), firstKey))
  end)

  -- the shown plan is the search's best after fillIdle; the runner-up's chain may not have been
  -- filled, so "not better" is not asserted to the last bit: only that it is a real alternative
  it("on a real level-80 state the runner-up is another first button, with numbers #integration", function()
    G.install({})
    local S = Sc.state(80)
    local p = planner.new()
    p:update(S)
    local plan = p:view(S.now)
    local r = explain.rivals({ plan = plan, S = S, planner = p })
    assert.is_truthy(r.second)
    assert.are_not.equal(search.firstKey(plan.steps[1]), r.second.key .. (r.second.afterSwing and "+swing" or ""))
    assert.is_number(r.second.loss)
    assert.is_number(r.second.pct)
  end)

  it("is quick enough to run once a second while the tooltip is open #perf", function()
    G.install({})
    local factor = tonumber(os.getenv("ENHROT_PERF_FACTOR") or "") or 1
    local total, n = 0, 0
    for _, S in ipairs(Sc.randomStates(30)) do
      local p = planner.new()
      p:update(S)
      local v = { plan = p:view(S.now), S = S, planner = p }
      if v.plan.steps[1] then
        local t0 = os.clock()
        explain.rivals(v)
        total, n = total + (os.clock() - t0) * 1000, n + 1
      end
    end
    assert.is_true(total / n <= 3 * factor, ("%.2f ms"):format(total / n))
  end)
end)

describe("explain: the tooltip text", function()
  it("name and key, press now, why, then, runner-up", function()
    local v = view(steps("stormstrike", "lavaLash", "earthShock"))
    local r = { value = 1000, horizon = 200, second = { key = "earthShock", value = 986, loss = 14, pct = 7 } }
    local L = explain.lines(v, 0, "S-E", r)
    local text = {}
    for i, l in ipairs(L) do text[i] = l[1] end
    assert.are.same({ "Stormstrike [S-E]", "Press now", "Why: stormstrike because", "Then: Lava Lash, Earth Shock",
                      "Runner-up: Earth Shock - 7% worse over the next 6 s" }, text)
  end)

  it("a button due later says when; a close runner-up is about as good; no key, no brackets", function()
    local v = view({ { key = "lightningBolt", at = 1.6, reason = "5 Maelstrom: instant" } })
    local L = explain.lines(v, 0.4, nil, { value = 1, horizon = 1, second = { key = "lavaLash", value = 1, loss = 0.001, pct = 0.4 } })
    assert.are.equal("Lightning Bolt", L[1][1])
    assert.are.equal("Press in 1.2 s", L[2][1])
    assert.are.equal("Runner-up: Lava Lash - about as good", L[#L][1])
  end)

  it("no runner-up: says so; nothing to press: no tooltip", function()
    local L = explain.lines(view(steps("stormstrike")), 0, nil, { value = 1, horizon = 1 })
    assert.are.equal("No other first button comes close", L[#L][1])
    assert.is_nil(explain.lines(view({}), 0, nil, nil))
  end)
end)

describe("explain: on mouse-over", function()
  local tip, mouse, combat, shift, now
  local function tooltip()
    local t = { lines = {} }
    function t:SetOwner(o, a) self.owner, self.anchor, self.lines, self.shown = o, a, {}, false end
    function t:SetText(s) self.lines = { s } end
    function t:AddLine(s) self.lines[#self.lines + 1] = s end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    function t:IsOwned(o) return self.owner == o end
    return t
  end
  local function driver(enabled)
    G.install({})
    tip, mouse, combat, shift, now = tooltip(), true, false, false, 100
    local v = view(steps("stormstrike"))
    v.frame, v.icon, v.active = CreateFrame("Frame"), G.texture(), true
    local e = explain.new({
      view = function() return v end, enabled = function() return enabled ~= false end,
      hotkey = function() return "3" end, now = function() return now end,
      inCombat = function() return combat end, shift = function() return shift end,
      tooltip = tip, over = function() return mouse end,
      evaluate = evaluator({ stormstrike = 10 }), firstKey = firstKey,
    })
    return e, v
  end

  it("out of combat the hover shows the tooltip; leaving hides it", function()
    local e = driver()
    e:tick(0.2)
    assert.is_true(tip.shown)
    assert.are.equal("Stormstrike [3]", tip.lines[1])
    assert.are.equal(e.hover, tip.owner)
    mouse = false
    e:tick(0.2)
    assert.is_false(tip.shown)
  end)

  it("in combat only with Shift held", function()
    local e = driver()
    combat = true
    e:tick(0.2)
    assert.is_false(tip.shown)
    shift = true
    e:tick(0.2)
    assert.is_true(tip.shown)
  end)

  it("the hover area never takes the mouse: clicks go through the timeline", function()
    local e = driver()
    e:tick(0.2)
    assert.is_falsy(e.hover.mouse)
  end)

  it("someone else's tooltip is not hidden", function()
    local e = driver()
    mouse = false
    tip:SetOwner("another frame")
    tip:Show()
    e:tick(0.2)
    assert.is_true(tip.shown)
  end)

  it("the option off: no tooltip", function()
    local e = driver(false)
    e:tick(0.2)
    assert.is_false(tip.shown)
  end)

  it("the runner-up is worked out again once a second while open, not every poll", function()
    local e, v = driver()
    local calls = 0
    e.deps.evaluate = function(...) calls = calls + 1; return 10, {}, 10 end
    e:tick(0.2)
    local first = calls
    now = now + 0.5
    e:tick(0.2)
    assert.are.equal(first, calls)
    now = now + 0.6
    e:tick(0.2)
    assert.is_true(calls > first)
  end)
end)
```

- [ ] **Step 6: Красный прогон.** `docker compose run --rm test busted spec/addon_explain_spec.lua` — `module 'explain' not found`.

- [ ] **Step 7: Реализация `addon/explain.lua`.**

```lua
-- The big icon explained on mouse-over: what it is, when, why, what follows, and the runner-up
-- (the best chain of another first button from the same search, planner.alts) with how much
-- worse it is. The timeline never takes the mouse (no click is lost in a fight): the cursor is
-- polled over a frame of our own on the big icon. Out of combat on hover; in combat only with
-- Shift held (no popups by themselves in a fight).
local spells = require("spells")
local search = require("search")

local M = {}
M.OPTION = { type = "toggle", key = "hoverTips", name = "Explain the big icon on mouse-over (Shift in combat)", default = true }
M.POLL = 0.1      -- s between mouse checks
M.REFRESH = 1.0   -- s between runner-up updates while the tooltip is open
M.MAX_RIVALS = 12 -- chains replayed per update at most
M.NOW = 0.05      -- due within this: "Press now"
M.CLOSE = 1       -- % worse below this: "about as good"
M.MORE = 3        -- buttons listed after the first
M.GREY = { 0.7, 0.7, 0.7 }
M.GOLD = { 1, 0.82, 0 }

local function name(key)
  local m = spells.byKey[key]
  return m and m.name or key
end

local function shifted(steps, by)
  local out = {}
  for i, st in ipairs(steps) do
    out[i] = { key = st.key, at = math.max(0, st.at - by), reason = st.reason, afterSwing = st.afterSwing }
  end
  return out
end

-- The shown plan and the best chain of every other first button, replayed on one state (the
-- planner's view: its own casts in flight), so the two values compare.
function M.rivals(view, evaluate, firstKey)
  evaluate, firstKey = evaluate or search.evaluate, firstKey or search.firstKey
  local plan, p, S = view.plan, view.planner, view.S
  local st = plan and plan.steps and plan.steps[1]
  if not (st and S and p) then return nil end
  local s = p.prepare and p:prepare(S) or S
  local v, _, h = evaluate(s, plan.steps)
  if not v then return nil end
  local out = { value = v, horizon = h or v }
  local alts = p.alts
  if not alts then return out end
  local by = (S.now or 0) - (p.altsNow or S.now or 0)
  local mine, keys = firstKey(st), {}
  for f, chain in pairs(alts) do
    if f ~= mine and #chain > 0 then keys[#keys + 1] = f end
  end
  table.sort(keys) -- the same ones every time when there are more than MAX_RIVALS
  local best
  for i = 1, math.min(#keys, M.MAX_RIVALS) do
    local chain = alts[keys[i]]
    local w = evaluate(s, shifted(chain, by))
    if w and (not best or w > best.value) then
      best = { key = chain[1].key, afterSwing = chain[1].afterSwing, value = w }
    end
  end
  if best then
    best.loss = v - best.value
    local base = math.abs(out.horizon)
    best.pct = base > 0 and best.loss / base * 100 or 0
    out.second = best
  end
  return out
end

local function line(out, text, c) out[#out + 1] = { text, c[1], c[2], c[3] } end

function M.lines(view, elapsed, hotkey, r)
  local steps = view.plan and view.plan.steps
  local st = steps and steps[1]
  if not st then return nil end
  local out = {}
  line(out, hotkey and (name(st.key) .. " [" .. hotkey .. "]") or name(st.key), { 1, 1, 1 })
  local wait = (st.at or 0) - (elapsed or 0)
  line(out, wait <= M.NOW and "Press now" or ("Press in %.1f s"):format(wait), M.GOLD)
  if st.reason and st.reason ~= "" then line(out, "Why: " .. st.reason, { 1, 1, 1 }) end
  local after = {}
  for i = 2, math.min(#steps, M.MORE + 1) do after[#after + 1] = name(steps[i].key) end
  if #after > 0 then line(out, "Then: " .. table.concat(after, ", "), M.GREY) end
  local sec = r and r.second
  if sec then
    local what = name(sec.key) .. (sec.afterSwing and " after the swing" or "")
    if sec.pct < M.CLOSE then
      line(out, ("Runner-up: %s - about as good"):format(what), M.GREY)
    else
      line(out, ("Runner-up: %s - %d%% worse over the next %d s"):format(what, math.floor(sec.pct + 0.5), search.HORIZON), M.GREY)
    end
  elseif r then
    line(out, "No other first button comes close", M.GREY)
  end
  return out
end

local E = {}
E.__index = E

function M.new(deps)
  deps.over = deps.over or function(f) return f.IsMouseOver and f:IsMouseOver() end
  return setmetatable({ deps = deps, wait = 0, shown = false, refreshAt = -math.huge }, E)
end

function E:start(frame)
  self.driver = frame
  frame:SetScript("OnUpdate", function(_, dt) self:tick(dt) end)
end

-- a frame of our own over the big icon, never mouse-enabled (IsMouseOver works without it)
function E:area(view)
  local a = self.hover
  if not a or a.on ~= view.frame then
    a = CreateFrame("Frame", nil, view.frame)
    a.on = view.frame
    self.hover = a
  end
  if a.icon ~= view.icon then
    a:ClearAllPoints()
    a:SetAllPoints(view.icon)
    a.icon = view.icon
  end
  return a
end

function E:close()
  local tip = self.deps.tooltip
  if self.shown and (not tip.IsOwned or tip:IsOwned(self.hover)) then tip:Hide() end
  self.shown = false
end

function E:tick(dt)
  self.wait = self.wait - (dt or 0)
  if self.wait > 0 then return end
  self.wait = M.POLL
  local d = self.deps
  local view = d.enabled() and d.view()
  local st = view and view.active and view.plan and view.plan.steps[1]
  if not (st and view.icon and view.icon:IsShown()) then return self:close() end
  local a = self:area(view)
  if not (d.over(a) and (not d.inCombat() or d.shift())) then return self:close() end
  local now = d.now()
  if self.shown and now < self.refreshAt and self.first == st.key then return end
  self.refreshAt, self.first = now + M.REFRESH, st.key
  local L = M.lines(view, now - (view.at or now), d.hotkey(st.key), M.rivals(view, d.evaluate, d.firstKey))
  local tip = d.tooltip
  tip:SetOwner(a, "ANCHOR_TOP")
  tip:SetText(L[1][1], L[1][2], L[1][3], L[1][4])
  for i = 2, #L do tip:AddLine(L[i][1], L[i][2], L[i][3], L[i][4], true) end
  tip:Show()
  self.shown = true
end

return M
```

- [ ] **Step 8: Зелёный прогон.** `docker compose run --rm test busted spec/addon_explain_spec.lua spec/planner_spec.lua`, затем `docker compose run --rm test busted --tags=perf` (включая новый `#perf` подсказки).

- [ ] **Step 9: Коммит.**

```bash
git add src/planner.lua spec/planner_spec.lua addon/explain.lua spec/addon_explain_spec.lua
git commit -m "Аддон: подсказка при наведении на крупную иконку — почему сейчас и что на втором месте"
```

---

### Task 3: «Всё ли готово» и ранги — `addon/ready.lua`

**Files:**
- Create: `addon/ready.lua`
- Test: `spec/addon_ready_spec.lua`

**Interfaces:**
- Consumes: `view = { S, cache }` (`core.view()`); `cache.known` (`{ [key] = { id, rank } }`), `cache.names`, `cache.talents` (`snapshot.scan`); `src/spells_data.lua` (`level` у рангов); `talents.spent`; клиентские `UnitLevel`, `HasAction`, `GetMultiCastBarOffset`, `NUM_ACTIONBAR_PAGES`, `UnitAffectingCombat`.
- Produces:
  - `ready.OPTIONS` — `readyCheck` («Show the checklist on first login», `true`), `rankWarning` («Tell me when the trainer has new ranks», `true`);
  - `ready.ranks(level, known, names) -> { { key, name, have, want, level }, … }` (порядок `spells.KEYS`, без `ready.TALENT`);
  - `ready.rankLine(list) -> string | nil`;
  - `ready.items(info) -> { { key, ok, label, hint }, … }`, `info = { level, S, known, names, talents = { spent, listed, recognized }, call = nil | { [slot 1..4] = bool } }`;
  - `ready.gather(view) -> info | nil`;
  - `ready.window(items) -> frame` (`DoubtMyRotationReady`);
  - `ready.new(deps) -> checker`, `deps = { view(), config(), db, say(line), now(), inCombat()? }`; `checker:start(frame)`, `checker:open()`, `checker:onEvent(event, ...)`, `checker:tick()`.

- [ ] **Step 1: Тест `spec/addon_ready_spec.lua`.**

```lua
local G = require("game_mock")
local spells = require("spells")
local data = require("spells_data")
local ready = require("ready")

local function rankAt(key, level)
  local n = 0
  for i, r in ipairs(data[key]) do if r.level <= level then n = i end end
  return n
end

-- everything learned at its newest rank for the level
local function knownAt(level)
  local k = {}
  for _, key in ipairs(spells.KEYS) do
    local n = rankAt(key, level)
    if n > 0 then k[key] = { id = spells.byKey[key].ranks[n], rank = n } end
  end
  return k
end

local function S(over)
  local s = { weapons = { mh = { enchant = "wf" }, oh = { enchant = "ft" } }, player = { shield = "lightning" },
              spells = { lightningShield = { cd = 0 } }, shieldPref = "auto" }
  for k, v in pairs(over or {}) do s[k] = v end
  return s
end

local function info(over)
  local i = { level = 80, S = S(), known = knownAt(80), talents = { spent = 71, listed = 80, recognized = true },
              call = { true, true, true, true } }
  for k, v in pairs(over or {}) do i[k] = v end
  return i
end

local function byKey(items)
  local out = {}
  for _, it in ipairs(items) do out[it.key] = it end
  return out
end

describe("ready: ranks", function()
  it("a spell one rank behind the level is listed, with the rank to buy", function()
    local known = knownAt(40)
    known.lightningBolt = { id = spells.byKey.lightningBolt.ranks[1], rank = 1 }
    local list = ready.ranks(40, known)
    assert.are.equal(1, #list)
    assert.are.same({ "lightningBolt", "Lightning Bolt", 1, rankAt("lightningBolt", 40) },
                    { list[1].key, list[1].name, list[1].have, list[1].want })
  end)

  it("a spell not learned at all counts; talent spells never do", function()
    local known = knownAt(80)
    known.earthShock, known.stormstrike, known.feralSpirit = nil, nil, nil
    local list = ready.ranks(80, known)
    assert.are.equal(1, #list)
    assert.are.equal("earthShock", list[1].key)
    assert.are.equal(0, list[1].have)
  end)

  it("the localized name when the client gave one", function()
    local known = knownAt(80)
    known.earthShock = nil
    assert.are.equal("Erdschock", ready.ranks(80, known, { earthShock = "Erdschock" })[1].name)
  end)

  it("up to date: nothing", function()
    for _, lvl in ipairs({ 1, 10, 30, 60, 80 }) do assert.are.same({}, ready.ranks(lvl, knownAt(lvl)), lvl) end
  end)

  it("the chat line names a few and counts the rest", function()
    local list = {}
    for i = 1, 6 do list[i] = { name = "Spell" .. i, have = i % 2, want = 3 } end
    assert.are.equal("the trainer has new ranks: Spell1 3, Spell2 (new), Spell3 3, Spell4 (new), +2 more - /dmr check",
                     ready.rankLine(list))
    assert.is_nil(ready.rankLine({}))
  end)
end)

describe("ready: the checklist", function()
  it("all green when all is there", function()
    for _, it in ipairs(ready.items(info())) do assert.is_true(it.ok, it.key); assert.is_nil(it.hint) end
  end)

  it("a missing imbue says which one to cast, by level", function()
    local s = S({ weapons = { mh = { enchant = nil }, oh = { enchant = nil } } })
    local it = byKey(ready.items(info({ S = s })))
    assert.are.equal("Cast Windfury Weapon on the main hand", it.mh.hint)
    assert.are.equal("Cast Flametongue Weapon on the off hand", it.oh.hint)
    it = byKey(ready.items(info({ S = s, level = 20, known = knownAt(20) })))
    assert.are.equal("Cast Flametongue Weapon on the main hand", it.mh.hint)
  end)

  it("no off hand weapon: no off hand row", function()
    local it = byKey(ready.items(info({ S = S({ weapons = { mh = { enchant = "wf", twoHand = true } } }) })))
    assert.is_nil(it.oh)
  end)

  it("no shield up: the one the settings want", function()
    local it = byKey(ready.items(info({ S = S({ player = {}, shieldPref = "water" }) })))
    assert.are.equal("Cast Water Shield", it.shield.hint)
  end)

  it("Call of the Elements: from 30, each empty element named", function()
    local it = byKey(ready.items(info({ call = { true, false, true, false } })))
    assert.is_false(it.totems.ok)
    assert.are.equal("Put a totem on each empty slot of the totem bar: Earth, Air", it.totems.hint)
    assert.is_nil(byKey(ready.items(info({ level = 29, known = knownAt(29), call = nil }))).totems)
  end)

  it("talents: none spent, or not recognized", function()
    local it = byKey(ready.items(info({ talents = { spent = 0, listed = 80, recognized = false } })))
    assert.are.equal("Spend your talent points", it.talents.hint)
    it = byKey(ready.items(info({ talents = { spent = 40, listed = 80, recognized = false } })))
    assert.are.equal("Talents not recognized - unsupported client language?", it.talents.hint)
    assert.is_nil(byKey(ready.items(info({ talents = { spent = 0, listed = 0, recognized = false } }))).talents)
  end)

  it("old ranks: visit the trainer", function()
    local known = knownAt(80)
    known.lightningBolt.rank = 10
    local it = byKey(ready.items(info({ known = known })))
    assert.are.equal("Visit the trainer: Lightning Bolt", it.ranks.hint)
  end)
end)

describe("ready: in game", function()
  local said, db, now, cfg, combat
  local function checker(snapshot)
    G.install({ level = 80 })
    said, db, now, cfg, combat = {}, {}, 100, { readyCheck = true, rankWarning = true }, false
    _G.DoubtMyRotationReady = nil
    _G.HasAction = function(slot) return slot >= 133 and slot <= 136 and 1 or nil end
    _G.NUM_ACTIONBAR_PAGES = 6
    _G.GetMultiCastBarOffset = function() return 6 end
    local known = knownAt(80)
    known.lightningBolt.rank = 10
    local v = { S = snapshot or S(), cache = { known = known, names = {}, talents = { x = 1 } } }
    local c = ready.new({ view = function() return v end, config = function() return cfg end, db = db,
                          say = function(l) said[#said + 1] = l end, now = function() return now end,
                          inCombat = function() return combat end })
    local f = CreateFrame("Frame")
    c:start(f)
    return c, f, v
  end
  local function after(f, s) now = now + s; f.scripts.OnUpdate(f, s) end

  it("the first login: the checklist once, a rank line, both after a short delay", function()
    local _, f = checker()
    after(f, 1)
    assert.is_nil(DoubtMyRotationReady)
    after(f, ready.DELAY)
    assert.is_true(DoubtMyRotationReady:IsShown())
    assert.is_true(db.readySeen)
    assert.are.equal(1, #said)
    assert.is_truthy(said[1]:find("Lightning Bolt", 1, true))
  end)

  it("the next login: no window, the rank line again", function()
    local _, f = checker()
    db.readySeen = true
    after(f, ready.DELAY + 1)
    assert.is_nil(DoubtMyRotationReady)
    assert.are.equal(1, #said)
  end)

  it("in combat at login: the window waits for the end of the fight", function()
    local c, f = checker()
    combat = true
    after(f, ready.DELAY + 1)
    assert.is_nil(DoubtMyRotationReady)
    combat = false
    c:onEvent("PLAYER_REGEN_ENABLED")
    after(f, 0.1)
    assert.is_true(DoubtMyRotationReady:IsShown())
  end)

  it("a level up says the line for the new level, the same line only once a session", function()
    local c, f = checker()
    after(f, ready.DELAY + 1)
    c:onEvent("PLAYER_LEVEL_UP", 80)
    after(f, ready.DELAY + 1)
    assert.are.equal(1, #said)
  end)

  it("options off: no window, no line", function()
    local _, f = checker()
    cfg.readyCheck, cfg.rankWarning = false, false
    after(f, ready.DELAY + 1)
    assert.is_nil(DoubtMyRotationReady)
    assert.are.equal(0, #said)
  end)

  it("/dmr check opens it any time; it turns green while open", function()
    local snap = S({ weapons = { mh = { enchant = nil }, oh = { enchant = "ft" } } })
    local c, f = checker(snap)
    db.readySeen = true
    c:open()
    local w = DoubtMyRotationReady
    assert.are.equal(ready.ICON_NO, w.rows[1].icon.texture)
    snap.weapons.mh.enchant = "wf"
    after(f, 1.1)
    assert.are.equal(ready.ICON_OK, w.rows[1].icon.texture)
  end)

  it("gather reads Call of the Elements from slots 133-136", function()
    local _, _, v = checker()
    v.cache.known.callOfElements = { id = 66842, rank = 1 }
    local asked = {}
    _G.HasAction = function(slot) asked[#asked + 1] = slot; return slot ~= 136 and 1 or nil end
    local i = ready.gather(v)
    assert.are.same({ 133, 134, 135, 136 }, asked)
    assert.are.same({ true, true, true, false }, i.call)
    assert.are.equal(80, i.level)
  end)
end)
```

- [ ] **Step 2: Красный прогон.** `docker compose run --rm test busted spec/addon_ready_spec.lua` — `module 'ready' not found`.

- [ ] **Step 3: Реализация `addon/ready.lua`.**

```lua
-- "Is everything ready": imbues on both weapons, a shield, a totem of each element on the Call
-- of the Elements bar (from 30), talents spent and recognized, the newest ranks the level
-- allows. Pure checks (ranks, items) over what gather() reads; a window of our own lists them on
-- the first login and on /dmr check; outdated ranks also get one chat line on login and on a
-- level up.
local spells = require("spells")
local data = require("spells_data")
local talents = require("talents")

local M = {}
M.OPTIONS = {
  { type = "toggle", key = "readyCheck", name = "Show the checklist on first login", default = true },
  { type = "toggle", key = "rankWarning", name = "Tell me when the trainer has new ranks", default = true },
}
M.TALENT = { stormstrike = true, lavaLash = true, shamanisticRage = true, feralSpirit = true }
M.ELEMENTS = { { 2, "Earth" }, { 1, "Fire" }, { 3, "Water" }, { 4, "Air" } } -- totem slot, name
M.CALL_LEVEL = 30
M.MAX_NAMES = 4
M.DELAY = 3     -- s after login or a level up: imbues and auras are read by then
M.REFRESH = 1   -- s between updates of the open window
M.ROW = 36
M.ICON_OK = "Interface\\RaidFrame\\ReadyCheck-Ready"
M.ICON_NO = "Interface\\RaidFrame\\ReadyCheck-NotReady"

function M.ranks(level, known, names)
  local out = {}
  for _, key in ipairs(spells.KEYS) do
    if not M.TALENT[key] then
      local list, want = data[key] or {}, 0
      for i, r in ipairs(list) do if (r.level or 0) <= level then want = i end end
      local have = known[key] and known[key].rank or 0
      if want > have then
        out[#out + 1] = { key = key, name = (names and names[key]) or spells.byKey[key].name,
                          have = have, want = want, level = list[want].level }
      end
    end
  end
  return out
end

local function names(list)
  local out = {}
  for i = 1, math.min(#list, M.MAX_NAMES) do out[i] = list[i].name end
  return table.concat(out, ", ")
end

function M.rankLine(list)
  if #list == 0 then return nil end
  local parts = {}
  for i = 1, math.min(#list, M.MAX_NAMES) do
    local r = list[i]
    parts[i] = r.have > 0 and ("%s %d"):format(r.name, r.want) or (r.name .. " (new)")
  end
  local more = #list > M.MAX_NAMES and (", +%d more"):format(#list - M.MAX_NAMES) or ""
  return "the trainer has new ranks: " .. table.concat(parts, ", ") .. more .. " - /dmr check"
end

local function imbue(level)
  return level >= 30 and "Windfury Weapon" or level >= 10 and "Flametongue Weapon" or "Rockbiter Weapon"
end

function M.items(info)
  local out = {}
  local function add(key, ok, label, hint)
    out[#out + 1] = { key = key, ok = ok and true or false, label = label, hint = (not ok) and hint or nil }
  end
  local S, lvl = info.S or {}, info.level or 80
  local w = S.weapons or {}
  if w.mh then add("mh", w.mh.enchant ~= nil, "Main hand imbue", "Cast " .. imbue(lvl) .. " on the main hand") end
  if w.oh then add("oh", w.oh.enchant ~= nil, "Off hand imbue", "Cast Flametongue Weapon on the off hand") end
  local water = S.shieldPref == "water"
  if water or (S.spells and S.spells.lightningShield) then
    add("shield", S.player and S.player.shield ~= nil, "Shield", "Cast " .. (water and "Water Shield" or "Lightning Shield"))
  end
  if lvl >= M.CALL_LEVEL and info.call then
    local missing = {}
    for _, e in ipairs(M.ELEMENTS) do if not info.call[e[1]] then missing[#missing + 1] = e[2] end end
    add("totems", #missing == 0, "Totems on Call of the Elements",
        "Put a totem on each empty slot of the totem bar: " .. table.concat(missing, ", "))
  end
  local t = info.talents
  if t and t.listed > 0 and lvl >= 10 then
    if t.spent == 0 then add("talents", false, "Talents", "Spend your talent points")
    else add("talents", t.recognized, "Talents recognized", "Talents not recognized - unsupported client language?") end
  end
  local old = M.ranks(lvl, info.known or {}, info.names)
  add("ranks", #old == 0, "Newest spell ranks",
      "Visit the trainer: " .. names(old) .. (#old > M.MAX_NAMES and ", ..." or ""))
  return out
end

function M.gather(view)
  local S = view and view.S
  if not S then return nil end
  local cache = view.cache or {}
  local spent, listed = talents.spent(GetNumTalentTabs, GetNumTalents, GetTalentInfo)
  local recognized = false
  for _, r in pairs(cache.talents or {}) do if r > 0 then recognized = true end end
  local info = { level = UnitLevel("player") or 1, S = S, known = cache.known or {}, names = cache.names,
                 talents = { spent = spent, listed = listed, recognized = recognized } }
  -- Call of the Elements: page 1 of the totem bar, action slots 133-136 in 3.3.5a
  -- (MultiCastActionBarFrame.lua: page NUM_ACTIONBAR_PAGES + GetMultiCastBarOffset(), slot = totem slot)
  if info.known.callOfElements and HasAction then
    local page = (NUM_ACTIONBAR_PAGES or 6) + (GetMultiCastBarOffset and GetMultiCastBarOffset() or 6)
    local base = (page - 1) * 12
    info.call = {}
    for slot = 1, 4 do info.call[slot] = HasAction(base + slot) and true or false end
  end
  return info
end

local function newWindow()
  local w = CreateFrame("Frame", "DoubtMyRotationReady", UIParent)
  w:SetWidth(380)
  w:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  w:SetFrameStrata("DIALOG")
  w:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                  tile = true, tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
  w:SetMovable(true)
  w:EnableMouse(true)
  w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", function(self) self:StartMoving() end)
  w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", w, "TOP", 0, -14)
  title:SetText("DoubtMyRotation: ready to fight?")
  local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", w, "TOPRIGHT", -4, -4)
  w.rows = {}
  return w
end

function M.window(items)
  local w = DoubtMyRotationReady or newWindow()
  for i, it in ipairs(items) do
    local r = w.rows[i]
    if not r then
      local y = -40 - (i - 1) * M.ROW
      r = { icon = w:CreateTexture(nil, "ARTWORK"),
            label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight"),
            hint = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") }
      r.icon:SetWidth(16)
      r.icon:SetHeight(16)
      r.icon:SetPoint("TOPLEFT", w, "TOPLEFT", 20, y)
      r.label:SetPoint("TOPLEFT", w, "TOPLEFT", 44, y)
      r.hint:SetPoint("TOPLEFT", w, "TOPLEFT", 44, y - 16)
      r.hint:SetWidth(310)
      r.hint:SetJustifyH("LEFT")
      w.rows[i] = r
    end
    r.icon:SetTexture(it.ok and M.ICON_OK or M.ICON_NO)
    r.icon:Show()
    r.label:SetText(it.label)
    r.label:Show()
    if it.hint then r.hint:SetText(it.hint); r.hint:Show() else r.hint:Hide() end
  end
  for i = #items + 1, #w.rows do
    local r = w.rows[i]
    r.icon:Hide(); r.label:Hide(); r.hint:Hide()
  end
  w:SetHeight(56 + #items * M.ROW)
  w:Show()
  return w
end

local R = {}
R.__index = R

function M.new(deps)
  deps.inCombat = deps.inCombat or function() return UnitAffectingCombat("player") end
  return setmetatable({ deps = deps, said = {} }, R)
end

function R:start(frame)
  frame:RegisterEvent("PLAYER_LEVEL_UP")
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:SetScript("OnEvent", function(_, event, ...) self:onEvent(event, ...) end)
  frame:SetScript("OnUpdate", function() self:tick() end)
  self.dueAt, self.login = self.deps.now() + M.DELAY, true
end

function R:onEvent(event, level)
  if event == "PLAYER_LEVEL_UP" then
    -- UnitLevel may still give the old level here: the event's own
    self.level, self.dueAt = tonumber(level), self.deps.now() + M.DELAY
  elseif event == "PLAYER_REGEN_ENABLED" and self.waiting then
    self.dueAt = self.deps.now()
  end
end

-- the rank line, the same text at most once a session
function R:sayRanks(info)
  if self.deps.config().rankWarning == false then return end
  local line = M.rankLine(M.ranks(info.level, info.known, info.names))
  if line and not self.said[line] then
    self.said[line] = true
    self.deps.say(line)
  end
end

function R:due()
  local d = self.deps
  local info = M.gather(d.view())
  if not info then self.dueAt = d.now() + 1; return end -- no snapshot yet
  if self.level then info.level = self.level end
  self:sayRanks(info)
  self.waiting = false
  if self.login and d.config().readyCheck ~= false and not d.db.readySeen then
    if d.inCombat() then self.waiting = true; return end
    d.db.readySeen = true
    self:show(info)
  end
  self.login = false
end

function R:show(info)
  self.win = M.window(M.items(info))
  self.refreshAt = self.deps.now() + M.REFRESH
end

function R:open()
  local info = M.gather(self.deps.view())
  if not info then return self.deps.say("no data yet - try again in a moment") end
  self:show(info)
end

function R:tick()
  local now = self.deps.now()
  if self.dueAt and now >= self.dueAt then
    self.dueAt = nil
    self:due()
  end
  if self.win and self.win:IsShown() and now >= (self.refreshAt or 0) then
    local info = M.gather(self.deps.view())
    if info then self:show(info) end
  end
end

return M
```

Замечание к тесту «in combat at login…»: после `PLAYER_REGEN_ENABLED` `dueAt = now`, следующий `tick` вызывает `due` с `self.login` ещё `true` (в ветке «в бою» `login` не сбрасывается — `return` раньше).

- [ ] **Step 4: Зелёный прогон.** `docker compose run --rm test busted spec/addon_ready_spec.lua`.

- [ ] **Step 5: Коммит.**

```bash
git add addon/ready.lua spec/addon_ready_spec.lua
git commit -m "Аддон: окно «всё ли готово» и строка «у тренера новые ранги»"
```

---

### Task 4: Подсветка кнопки и клавиша на крупной иконке — `addon/highlight.lua`

**Files:**
- Create: `addon/highlight.lua`
- Test: `spec/addon_highlight_spec.lua`

**Interfaces:**
- Исполнитель — тот же, что у задачи 1 (контракт A), после неё.
- Consumes: `actionbars.scan(keyByName) -> map` (задача 1); `view = { plan, S, at, cache, frame, icon, active }` (`core.view()`, задача 5); `bars_mock` (задача 1).
- Produces:
  - `highlight.OPTIONS` — `highlightButtons` («Light up the button to press on your action bars», `true`), `showKeybind` («Show its key on the big icon», `true`);
  - `highlight.due(view, now) -> key | nil`;
  - `highlight.new(deps) -> h`, `deps = { view(), config(), now(), scan? }`; `h:start(frame)` (события панелей и `OnUpdate` на своей рамке), `h:tick(dt)`, `h:hotkey(key) -> text | nil`, `h.overlays` (`{ [button] = frame }`), `h.keyText` (фонтстринг клавиши).

- [ ] **Step 1: Тест `spec/addon_highlight_spec.lua`.**

```lua
local G = require("game_mock")
local B = require("bars_mock")
local spells = require("spells")
local highlight = require("highlight")

local function top(key) local r = spells.byKey[key].ranks; return r[#r] end

local now, cfg, v, scans, map
local function setup(over)
  G.install({})
  B.install({})
  now, cfg, scans = 100, { highlightButtons = true, showKeybind = true }, 0
  local b1, b2 = B.blizzard("ActionButton3", 3), B.elvui(1, 2, "action", 2)
  map = { stormstrike = { buttons = { { frame = b1 }, { frame = b2 } }, hotkey = "S-E" },
          lavaLash = { buttons = { { frame = b1 } }, hotkey = "2" } }
  local tl = CreateFrame("Frame")
  v = { plan = { steps = { { key = "stormstrike", at = 0 } } }, at = 100, active = true,
        S = { target = { exists = true, enemy = true } }, cache = { keyByName = {} },
        frame = tl, icon = G.texture() }
  for k, x in pairs(over or {}) do v[k] = x end
  local h = highlight.new({ view = function() return v end, config = function() return cfg end,
                            now = function() return now end,
                            scan = function() scans = scans + 1; return map end })
  return h, b1, b2
end

-- the button mocks keep what B.blizzard / B.elvui gave them: nothing set on a protected frame
local function untouched(b)
  assert.are.same({}, b.points)
  assert.are.same({}, b.children)
  assert.is_nil(b.allPoints)
  assert.is_nil(b.scripts.OnUpdate)
  assert.are.same({}, b.hooks)
  assert.is_nil(b.parentSet)
end

describe("highlight: when", function()
  it("the first button, once due within 0.3 s, with an enemy targeted", function()
    local _ = setup()
    assert.are.equal("stormstrike", highlight.due(v, 100))
    v.plan.steps[1].at = 1.0
    assert.is_nil(highlight.due(v, 100))
    assert.are.equal("stormstrike", highlight.due(v, 100.75))
    v.S.target.enemy = false
    assert.is_nil(highlight.due(v, 100.75))
  end)

  it("waits and empty plans light nothing", function()
    setup()
    v.plan.steps[1].key = "wait"
    assert.is_nil(highlight.due(v, 100))
    v.plan.steps = {}
    assert.is_nil(highlight.due(v, 100))
  end)
end)

describe("highlight: on the bars", function()
  it("an overlay of our own over every button with the spell; the buttons are not touched", function()
    local h, b1, b2 = setup()
    B.cfg.lockdown = true -- the same in combat
    h:tick(0.016)
    for _, b in ipairs({ b1, b2 }) do
      local o = h.overlays[b]
      assert.is_true(o:IsShown())
      assert.are.same({ "CENTER", b, "CENTER", 0, 0 }, o.point)
      assert.are.equal(UIParent, o.parent)
      assert.is_true(o.level > b.level)
      assert.is_falsy(o.mouse)
      untouched(b)
    end
  end)

  it("the next button: the old overlays go out", function()
    local h, b1, b2 = setup()
    h:tick(0.016)
    v.plan.steps[1].key = "lavaLash"
    h:tick(0.016)
    assert.is_true(h.overlays[b1]:IsShown())
    assert.is_false(h.overlays[b2]:IsShown())
  end)

  it("one overlay per button for the session", function()
    local h, b1 = setup()
    for _ = 1, 5 do
      v.plan.steps[1].key = "lavaLash"; h:tick(0.016)
      v.plan.steps[1].key = "stormstrike"; h:tick(0.016)
    end
    local n = 0
    for _ in pairs(h.overlays) do n = n + 1 end
    assert.are.equal(2, n)
    assert.is_truthy(h.overlays[b1])
  end)

  it("option off, engine asleep, or nothing due: nothing lit", function()
    local h, b1 = setup()
    cfg.highlightButtons = false
    h:tick(0.016)
    assert.is_true(h.overlays[b1] == nil or not h.overlays[b1]:IsShown())
    cfg.highlightButtons = true
    v.active = false
    h:tick(0.016)
    assert.is_true(h.overlays[b1] == nil or not h.overlays[b1]:IsShown())
  end)

  it("bars are read on an event and once a second, not every frame", function()
    local h = setup()
    local f = CreateFrame("Frame")
    h:start(f)
    for _ = 1, 30 do f.scripts.OnUpdate(f, 0.016); now = now + 0.016 end
    assert.are.equal(1, scans)
    f.scripts.OnEvent(f, "ACTIONBAR_SLOT_CHANGED", 3)
    f.scripts.OnUpdate(f, 0.016)
    assert.are.equal(2, scans)
    now = now + 1.01
    f.scripts.OnUpdate(f, 0.016)
    assert.are.equal(3, scans)
    assert.is_true(f.events.UPDATE_BINDINGS)
  end)
end)

describe("highlight: the key on the big icon", function()
  it("the first button's key at the bottom of the big icon", function()
    local h = setup()
    v.plan.steps[1].at = 2 -- shown whatever the time to it
    h:tick(0.016)
    assert.are.equal("S-E", h.keyText.text)
    assert.is_true(h.keyText:IsShown())
    assert.are.equal(v.icon, h.keyText.point[2])
    assert.are.equal("S-E", h:hotkey("stormstrike"))
  end)

  it("no key, the icon hidden, or the option off: no text", function()
    local h = setup()
    h:tick(0.016)
    assert.is_true(h.keyText:IsShown())
    map.stormstrike.hotkey = nil
    h:tick(0.016)
    assert.is_false(h.keyText:IsShown())
    map.stormstrike.hotkey = "S-E"
    v.icon:Hide()
    h:tick(0.016)
    assert.is_false(h.keyText:IsShown())
    v.icon:Show()
    cfg.showKeybind = false
    h:tick(0.016)
    assert.is_false(h.keyText:IsShown())
  end)
end)

describe("highlight with the real bars #integration", function()
  it("an ElvUI button with Stormstrike lights up", function()
    G.install({})
    B.install({ actions = { [1] = { "spell", 12, "spell", top("stormstrike") } }, bindings = { ACTIONBUTTON1 = "E" } })
    local e = B.elvui(1, 1, "action", 1, "ACTIONBUTTON1")
    local view = { plan = { steps = { { key = "stormstrike", at = 0 } } }, at = 100, active = true,
                   S = { target = { exists = true, enemy = true } }, cache = { keyByName = { Stormstrike = "stormstrike" } },
                   frame = CreateFrame("Frame"), icon = G.texture() }
    local h = highlight.new({ view = function() return view end, config = function() return {} end, now = function() return 100 end })
    h:tick(0.016)
    assert.is_true(h.overlays[e]:IsShown())
    assert.are.equal("E", h.keyText.text)
  end)
end)
```

(`parentSet` ставит обёртка `SetParent` у кнопок `bars_mock.blizzard` / `bars_mock.elvui` — задача 1.)

- [ ] **Step 2: Красный прогон.** `docker compose run --rm test busted spec/addon_highlight_spec.lua` — `module 'highlight' not found`.

- [ ] **Step 3: Реализация `addon/highlight.lua`.**

```lua
-- The button to press lit on the action bars (every source of addon/actionbars.lua) and its key
-- on the big icon. Frames and textures of our own laid over the buttons: nothing is ever set on
-- a button (protected frames), so it works the same in combat without taint.
local actionbars = require("actionbars")
local spells = require("spells")

local M = {}
M.OPTIONS = {
  { type = "toggle", key = "highlightButtons", name = "Light up the button to press on your action bars", default = true },
  { type = "toggle", key = "showKeybind", name = "Show its key on the big icon", default = true },
}
M.GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
M.SIZE = 1.8      -- the border art is a ring inside a larger square (the timeline's glow: 1.7)
M.COLOR = { 1, 0.82, 0.3 }
M.AT = 0.3        -- lit once due within this: the moment the timeline's big icon glows
M.RESCAN = 1      -- s: ElvUI pages its bars by a state driver, with no event to us
M.PULSE = 2       -- pulses a second
M.EVENTS = { "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BINDINGS",
             "UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }

function M.due(view, now)
  local st = view and view.plan and view.plan.steps and view.plan.steps[1]
  if not (st and spells.byKey[st.key]) then return nil end
  local t = view.S and view.S.target
  if not (t and t.exists and t.enemy) then return nil end
  if (st.at or 0) - (now - (view.at or now)) > M.AT then return nil end
  return st.key
end

local H = {}
H.__index = H

function M.new(deps)
  deps.scan = deps.scan or actionbars.scan
  return setmetatable({ deps = deps, map = {}, overlays = {}, lit = {}, litKey = false,
                        dirty = true, scanAt = -math.huge }, H)
end

function H:start(frame)
  for _, e in ipairs(M.EVENTS) do frame:RegisterEvent(e) end
  frame:SetScript("OnEvent", function() self.dirty = true end)
  frame:SetScript("OnUpdate", function(_, dt) self:tick(dt) end)
end

function H:hotkey(key)
  local m = self.map[key]
  return m and m.hotkey
end

-- ours, on UIParent, anchored to the button's center at its scale, one per button
function H:overlay(button)
  local o = self.overlays[button]
  if not o then
    o = CreateFrame("Frame", nil, UIParent)
    o.tex = o:CreateTexture(nil, "OVERLAY")
    o.tex:SetAllPoints(o)
    o.tex:SetTexture(M.GLOW)
    o.tex:SetBlendMode("ADD")
    o.tex:SetVertexColor(unpack(M.COLOR))
    o:Hide()
    self.overlays[button] = o
  end
  local s = (button.GetEffectiveScale and button:GetEffectiveScale() or 1)
    / (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1)
  if o.SetScale then o:SetScale(s) end
  local w = (button:GetWidth() or 36) * M.SIZE
  o:SetWidth(w)
  o:SetHeight(w)
  o:ClearAllPoints()
  o:SetPoint("CENTER", button, "CENTER", 0, 0)
  if button.GetFrameStrata then o:SetFrameStrata(button:GetFrameStrata()) end
  if button.GetFrameLevel then o:SetFrameLevel(button:GetFrameLevel() + 10) end
  return o
end

function H:light(key)
  for o in pairs(self.lit) do o:Hide(); self.lit[o] = nil end
  self.litKey = key
  local m = key and self.map[key]
  for _, e in ipairs(m and m.buttons or {}) do
    local o = self:overlay(e.frame)
    o:Show()
    self.lit[o] = true
  end
end

function H:keyOn(view, text)
  local f = self.keyFrame
  if not f or f.on ~= view.frame then
    f = CreateFrame("Frame", nil, view.frame)
    f.on = view.frame
    f:SetAllPoints(view.frame)
    self.keyFrame = f
    self.keyText = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    self.keyIcon = nil
  end
  local fs = self.keyText
  if self.keyIcon ~= view.icon then
    fs:ClearAllPoints()
    -- inside the icon's lower edge: right under it the timeline writes the reason
    fs:SetPoint("BOTTOM", view.icon, "BOTTOM", 0, 3)
    self.keyIcon = view.icon
  end
  fs:SetText(text)
  fs:Show()
end

function H:tick()
  local d = self.deps
  local now, view, c = d.now(), d.view(), d.config()
  if view and view.cache and (self.dirty or now - self.scanAt >= M.RESCAN) then
    self.map = d.scan(view.cache.keyByName or {})
    self.dirty, self.scanAt, self.litKey = false, now, false -- buttons may have changed: light again
  end
  local key = view and view.active and c.highlightButtons ~= false and M.due(view, now) or nil
  if key ~= self.litKey then self:light(key) end
  if next(self.lit) then
    local a = 0.65 + 0.35 * math.sin(now * M.PULSE * 2 * math.pi)
    for o in pairs(self.lit) do o:SetAlpha(a) end
  end
  local st = view and view.active and view.plan and view.plan.steps and view.plan.steps[1]
  local text = c.showKeybind ~= false and st and view.icon and view.icon:IsShown() and self:hotkey(st.key)
  if text then self:keyOn(view, text) elseif self.keyText then self.keyText:Hide() end
end

return M
```

- [ ] **Step 4: Зелёный прогон.** `docker compose run --rm test busted spec/addon_highlight_spec.lua spec/addon_actionbars_spec.lua`.

- [ ] **Step 5: Коммит.**

```bash
git add addon/highlight.lua spec/addon_highlight_spec.lua
git commit -m "Аддон: подсветка нужной кнопки на панелях и её клавиша на крупной иконке"
```

---

### Task 5: Связка — `addon/helpers.lua`, `core`, `settings`, `panel`, сборка, документация

**Files:**
- Create: `addon/helpers.lua`; Test: `spec/addon_helpers_spec.lua`
- Modify (общие): `addon/core.lua`, `addon/settings.lua`, `addon/panel.lua`, `tools/build.lua` (`B.ADDON_MODULES`), `spec/support/game_mock.lua` (список сброса), `spec/addon_core_spec.lua`, `spec/addon_settings_spec.lua`, `spec/addon_panel_spec.lua`, `spec/build_spec.lua` (блок `describe("addon build", …)`), `README.md`, `.claude/rules/ARCHITECTURE.md`, `AGENTS.md`

**Interfaces:**
- Consumes: `highlight.OPTIONS`, `highlight.new`, `h:start`, `h:hotkey` (задача 4); `explain.OPTION`, `explain.new`, `e:start` (задача 2); `ready.OPTIONS`, `ready.new`, `r:start`, `r:open` (задача 3).
- Produces:
  - `helpers.options() -> { option… }` — `highlightButtons`, `showKeybind`, `hoverTips`, `readyCheck`, `rankWarning` (в этом порядке);
  - `helpers.start(core, say) -> h` с полями `highlight`, `explain`, `ready` и методом `h.check()`; рамки `DoubtMyRotationHighlight`, `DoubtMyRotationExplain`, `DoubtMyRotationChecks`;
  - `core.view() -> nil | { plan, S, at, cache, planner, frame, icon, active }` (одна таблица, перезаполняется);
  - `core.helpers` — после `login` шамана; `/dmr check` → `core.helpers.check()`;
  - `settings.ACTIONS.check = true`, строка помощи `/dmr check - is everything ready (imbues, shield, totems, ranks)`;
  - `panel.SECTIONS`: General + `highlightButtons`, `showKeybind`, `hoverTips`; Advanced + `readyCheck`, `rankWarning`.

- [ ] **Step 1: Тест `spec/addon_helpers_spec.lua`.**

```lua
local G = require("game_mock")

local made = {}
local function stub(name, extra)
  local m = extra or {}
  m.new = function(deps)
    local o = { deps = deps, name = name }
    function o:start(frame) self.frame = frame end
    function o:open() self.opened = true end
    function o:hotkey(k) return k == "stormstrike" and "S-E" or nil end
    made[name] = o
    return o
  end
  return m
end
package.loaded.highlight = stub("highlight", { OPTIONS = { { key = "highlightButtons" }, { key = "showKeybind" } } })
package.loaded.explain = stub("explain", { OPTION = { key = "hoverTips" } })
package.loaded.ready = stub("ready", { OPTIONS = { { key = "readyCheck" }, { key = "rankWarning" } } })

local helpers = require("helpers")

describe("addon helpers", function()
  before_each(function() G.install({}); made = {} end)

  it("their options, in order", function()
    local keys = {}
    for i, o in ipairs(helpers.options()) do keys[i] = o.key end
    assert.are.same({ "highlightButtons", "showKeybind", "hoverTips", "readyCheck", "rankWarning" }, keys)
  end)

  it("start runs each on a frame of its own, reading the engine through core.view", function()
    local view = {}
    local core = { view = function() return view end, db = { config = { hoverTips = false } } }
    local h = helpers.start(core, function() end)
    assert.are.equal(DoubtMyRotationHighlight, made.highlight.frame)
    assert.are.equal(DoubtMyRotationExplain, made.explain.frame)
    assert.are.equal(DoubtMyRotationChecks, made.ready.frame)
    assert.are.equal(view, made.highlight.deps.view())
    assert.is_false(made.explain.deps.enabled())
    assert.are.equal("S-E", made.explain.deps.hotkey("stormstrike"))
    assert.are.equal(core.db, made.ready.deps.db)
    h.check()
    assert.is_true(made.ready.opened)
  end)
end)
```

- [ ] **Step 2: Реализация `addon/helpers.lua`.**

```lua
-- The stage 1 helpers in one place: the lit action button and its key, the big icon's tooltip,
-- the checklist. core starts them once a shaman is logged in; each reads the engine only
-- through core.view() and its option live (an option change needs no engine restart).
local highlight = require("highlight")
local explain = require("explain")
local ready = require("ready")

local M = {}

function M.options()
  local list = {}
  for _, o in ipairs(highlight.OPTIONS) do list[#list + 1] = o end
  list[#list + 1] = explain.OPTION
  for _, o in ipairs(ready.OPTIONS) do list[#list + 1] = o end
  return list
end

local function frame(name) return _G[name] or CreateFrame("Frame", name) end

function M.start(core, say)
  local h = {}
  local function config() return core.db.config end
  h.highlight = highlight.new({ view = core.view, config = config, now = GetTime })
  h.highlight:start(frame("DoubtMyRotationHighlight"))
  h.explain = explain.new({
    view = core.view, now = GetTime, tooltip = GameTooltip,
    enabled = function() return config().hoverTips ~= false end,
    hotkey = function(key) return h.highlight:hotkey(key) end,
    inCombat = function() return UnitAffectingCombat("player") end,
    shift = function() return IsShiftKeyDown and IsShiftKeyDown() end,
  })
  h.explain:start(frame("DoubtMyRotationExplain"))
  h.ready = ready.new({ view = core.view, config = config, db = core.db, say = say, now = GetTime })
  h.ready:start(frame("DoubtMyRotationChecks"))
  h.check = function() h.ready:open() end
  return h
end

return M
```

- [ ] **Step 3: Правки общих файлов (минимальные).**

`addon/core.lua` — `require("helpers")`, `withUpdate` дополняется опциями помощников:

```lua
local helpers = require("helpers")
…
-- the build's option list plus the addon's own (the update check, the helpers), as a copy: the
-- caller's list stays the aura's
local function withUpdate(options)
  local list, have = {}, {}
  for i, opt in ipairs(options) do list[i], have[opt.key] = opt, true end
  local extra = { update.OPTION }
  for _, opt in ipairs(helpers.options()) do extra[#extra + 1] = opt end
  for _, opt in ipairs(extra) do
    if not have[opt.key] then list[#list + 1] = opt end
  end
  return list
end
```

Над `M.login`:

```lua
-- what the helpers (addon/helpers.lua) read of the running engine: one table, filled anew
local VIEW = {}
function M.view()
  local rt = M.rt
  if not rt then return nil end
  local tl = rt.tl
  VIEW.plan, VIEW.S, VIEW.planner = rt.plan, rt.S, rt.planner
  VIEW.cache = rt.ctx and rt.ctx.cache
  VIEW.at, VIEW.frame, VIEW.icon = tl and tl.at, tl and tl.frame, tl and tl.icons and tl.icons[1]
  VIEW.active = not (rt.sleeping or rt.stopped or rt.inactive)
  return VIEW
end
```

В `M.login` после `M.updates:start(…)`: `M.helpers = M.helpers or helpers.start(M, say)`. В `M.handle` после `elseif a == "export" …`: `elseif a == "check" then if M.helpers then M.helpers.check() end`.

`addon/settings.lua`: `M.ACTIONS` + `check = true`; в `M.HELP` строка `"/dmr check - is everything ready (imbues, shield, totems, ranks)"`.

`addon/panel.lua`, `M.SECTIONS`:

```lua
  { key = "general", options = { "scale", "seconds", "icons", "showReason", "showLust",
                                 "highlightButtons", "showKeybind", "hoverTips" }, actions = true },
  …
  { key = "advanced", title = "Advanced",
    options = { "weave", "manaPolicy", "record", "printDebug", "updateCheck", "readyCheck", "rankWarning" } },
```

`tools/build.lua`, `B.ADDON_MODULES` — перед `{ "core", "addon/core.lua" }`: `{ "actionbars", "addon/actionbars.lua" }, { "highlight", "addon/highlight.lua" }, { "explain", "addon/explain.lua" }, { "ready", "addon/ready.lua" }, { "helpers", "addon/helpers.lua" }`.

`spec/support/game_mock.lua` — в списке сброса `DoubtMyRotation*` добавить `"Highlight", "Explain", "Checks", "Ready"`.

- [ ] **Step 4: Тесты общих файлов.**

`spec/addon_core_spec.lua` — заглушка помощников рядом с заглушками `panel`/`update`:

```lua
local helperRuns = {}
package.loaded.helpers = {
  options = function() return { { type = "toggle", key = "highlightButtons", name = "Light up", default = true } } end,
  start = function(core, say)
    local h = { core = core, say = say, checks = 0 }
    h.check = function() h.checks = h.checks + 1 end
    helperRuns[#helperRuns + 1] = h
    return h
  end,
}
```

(в `before_each` — `core.helpers = nil; helperRuns = {}`) и тесты:

```lua
  it("the helpers start once on a shaman's login, their options are in the list", function()
    shaman()
    local o = opts()
    login(o, nil)
    assert.are.equal(1, #helperRuns)
    assert.are.equal(core, helperRuns[1].core)
    local keys = {}
    for _, opt in ipairs(o.options) do keys[opt.key] = true end
    assert.is_true(keys.highlightButtons)
    assert.is_true(keys.updateCheck)
    assert.is_true(DoubtMyRotationDB.config.highlightButtons)
  end)

  it("/dmr check opens the checklist", function()
    shaman()
    login(opts(), nil)
    SlashCmdList.DOUBTMYROTATION("check")
    assert.are.equal(1, helperRuns[1].checks)
  end)

  it("not a shaman: no helpers", function()
    shaman({ class = "WARRIOR" })
    login(opts(), nil)
    assert.are.equal(0, #helperRuns)
  end)

  it("view: the running engine's plan, snapshot, cache and big icon; nil before login", function()
    assert.is_nil(core.view())
    shaman()
    login(opts(), nil)
    local v = core.view()
    assert.are.equal(core.rt.tl.icons[1], v.icon)
    assert.are.equal(core.rt.ctx.cache, v.cache)
    assert.are.equal(core.rt.planner, v.planner)
    assert.is_true(v.active)
  end)
```

`spec/addon_settings_spec.lua`: `/dmr check` → `{ lines = {}, changed = false, action = "check" }`; в `/dmr help` есть строка с `/dmr check`.

`spec/addon_panel_spec.lua`, в «the real options all have a section»: помощники тоже на месте —

```lua
    for _, o in ipairs(require("helpers").options()) do assert.is_true(placed[o.key], o.key) end
    assert.are.equal("general", where.highlightButtons)
    assert.are.equal("advanced", where.readyCheck)
```

`spec/build_spec.lua`, блок `describe("addon build", …)`: в сквозном «runs as an addon without WeakAuras and draws a plan» после входа — `assert.is_truthy(DoubtMyRotationHighlight)`, `assert.is_truthy(DoubtMyRotationChecks)`, и прогон `DoubtMyRotationHighlight.scripts.OnUpdate(…, 0.016)`, `DoubtMyRotationExplain.scripts.OnUpdate(…, 0.2)`, `DoubtMyRotationChecks.scripts.OnUpdate(…)` без ошибок (в окружении без панелей и без `GetActionInfo`).

- [ ] **Step 5: Прогоны.** `docker compose run --rm test busted spec/addon_helpers_spec.lua spec/addon_core_spec.lua spec/addon_settings_spec.lua spec/addon_panel_spec.lua spec/build_spec.lua`; сборка `docker compose run --rm test lua tools/build.lua` — оба артефакта, строка ауры не выросла сверх `B.MAX_IMPORT`.

- [ ] **Step 6: Документация.**
  - `README.md` — раздел аддона: «Нужная кнопка горит на панели» (стандартные панели и ElvUI; клавиша на крупной иконке), «Наведи на крупную иконку — объяснение и второе место (в бою — с Shift)», «`/dmr check` — всё ли готово; при первом входе окно открывается само», «строка про новые ранги у тренера»; таблица команд — `/dmr check`; новые настройки — где их выключить (General / Advanced).
  - `.claude/rules/ARCHITECTURE.md` — в таблицу «Аддон (`addon/`)»: `actionbars`, `highlight`, `explain`, `ready`, `helpers`; строка: «помощники читают движок только через `core.view()`».
  - `AGENTS.md` — конвенция: «Кнопки чужих панелей — только чтение; подсветка и подсказки — свои рамки (`addon/highlight.lua`, `addon/explain.lua`); новый источник кнопок — запись в `actionbars.SOURCES`».

- [ ] **Step 7: Коммит.**

```bash
git add addon/helpers.lua spec/addon_helpers_spec.lua addon/core.lua addon/settings.lua addon/panel.lua tools/build.lua spec/support/game_mock.lua spec/addon_core_spec.lua spec/addon_settings_spec.lua spec/addon_panel_spec.lua spec/build_spec.lua README.md .claude/rules/ARCHITECTURE.md AGENTS.md
git commit -m "Аддон: помощники этапа 1 в сборке — подсветка, подсказка, /dmr check, настройки"
```

---

### Task 6: Интеграция и проверка в игре

**Files:** без новых; правки — только по найденному в игре (каждая с тестом в спеке модуля).

- [ ] **Step 1: Слияние** веток волн 1–2 в `feat/stage1-focus`; конфликты в общих файлах (`core`, `panel`, `settings`, `build`, `game_mock`, README/карта) — разрешить, сохранив и правки параллельной работы.
- [ ] **Step 2: Весь набор.** `docker compose run --rm test busted` (вместе с `perf`) — зелёный; `docker compose run --rm test lua tools/build.lua` — оба артефакта.
- [ ] **Step 3: В игре, макросами** (результат — в описание PR):
  - `/run print(GetActionInfo(1))` на слоте с Lightning Bolt → ожидаем `spell <n> spell <spellID>`; на макросе → `macro <n>`; `/run print(GetMacroSpell(<n>))`.
  - `/run print(NUM_ACTIONBAR_PAGES, GetMultiCastBarOffset(), HasAction(133), HasAction(136))` → `6 6 1 1` при выставленных тотемах.
  - ElvUI включён: подсветка на кнопке ElvUI, клавиша под крупной иконкой совпадает с подписью на кнопке; рамка подсветки — по размеру кнопки. ElvUI выключен: то же на стандартных панелях.
  - `/console taintLog 1`, `/reload`, бой 2–3 минуты с подсветкой и подсказкой (Shift + наведение) → в `Logs/taint.log` нет `DoubtMyRotation`, в чате нет «Interface action failed because of an AddOn».
  - В бою клик по мобу под лентой выбирает моба; без Shift подсказки нет.
  - Новый персонаж (или `/run DoubtMyRotationDB.readySeen=nil` + `/reload`) → окно через 3 с; снять чары → `/dmr check` красный пункт → наложить → зелёный за секунду.
  - Персонаж с устаревшим рангом → строка про тренера при входе, одна.
- [ ] **Step 4: Независимое ревью** ветки по Review Focus; находки — с регресс-тестом.
- [ ] **Step 5: PR** в `main`; в сообщении мерж-коммита — `[minor]`.
