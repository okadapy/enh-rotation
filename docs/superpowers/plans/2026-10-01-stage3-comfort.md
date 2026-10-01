# Этап 3 — удобство: план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Аддон удобен с первого входа: мастер первого запуска, режим «одна кнопка», карточки «что нового на уровне», профили на персонажа с автовыбором, кнопка у миникарты и оформление окон в стиле ElvUI, если он стоит.

**Architecture:** Всё — в `addon/`, кроме режима «одна кнопка»: его рисует лента (`src/timeline.lua`, опция `compact`, у ауры её нет). Новые модули аддона — чистые функции и окна с хостом-таблицей (как `panel.new(o, host)`); клиентские вызовы и SavedVariables держит `addon/core.lua`. Сообщения игроку идут через одну очередь (`addon/guide.lua`): одно окно за раз, только вне боя. Профили — в аккаунтовой `DoubtMyRotationDB.profiles`, выбор и правила — в новой `DoubtMyRotationCharDB` (`SavedVariablesPerCharacter`). Оформление ElvUI — один модуль `addon/skin.lua`, который по полю `kind` у виджетов зовёт `Skins`-функции ElvUI.

**Tech Stack:** Lua 5.1 (клиент 3.3.5a), busted 2.2.0 в Docker (`docker compose run --rm test …`), ElvUI Rebuffed 6.10 (только читать: `/home/okada/whitemane/FrostmourneRebuffed/Interface/AddOns/ElvUI`).

**Spec:** этап 3 дорожной карты `docs/superpowers/specs/2026-10-01-addon-roadmap.md` (пункт «Русский клиент» — не делаем, см. «Решения»); раздел «Чего не делать» там же. Перед работой прочитать `AGENTS.md`, `.claude/rules/ARCHITECTURE.md`, план аддона `docs/superpowers/plans/2026-10-01-addon.md` (как устроены `core`, `panel`, `settings`) и контракты исполнителей `docs/superpowers/plans/2026-10-01-stage3-contracts.md`.

## Решения (по умолчанию, пользователь может поправить до начала)

- **Порядок с этапом 1.** Этап 1 (`docs/superpowers/plans/2026-10-01-stage1-focus.md`) тоже меняет `addon/core.lua`, `addon/settings.lua`, `addon/panel.lua` и `tools/build.lua`. Этап 3 начинается от `feat/comfort` **после** слияния этапа 1. Если этап 1 задержится — волна 1 (новые файлы, `src/timeline.lua`) может идти, задача 2 и волна 2 — только после него (иначе конфликты в одних и тех же строках).
- **Русского перевода нет** (решение пользователя): тексты в игре — английские, правило «тексты в игре — на английском» в `AGENTS.md` не меняется; в дорожной карте пункт «Русский клиент» переезжает в «Потом» одной строкой (задача 9).
- **Профили.** Сами профили — аккаунтовые: `DoubtMyRotationDB.profiles[name] = { …значения опций… }`, альты делятся «Raid» / «Leveling». Что выбрано и правила автовыбора — на персонажа: новая `DoubtMyRotationCharDB = { profile, auto = { pvp, raid, party, leveling }, point, hidden, minimap = { angle }, wizard, cards = { [10] = true, … } }` (`## SavedVariablesPerCharacter` в `.toc`). Почему не всё в `SavedVariablesPerCharacter`: тогда каждый альт настраивается с нуля.
- **Переход без потери.** Первый вход новой версии: `db.profiles = { Default = копия db.config }`; сам `db.config` **не трогается** (откат на старую версию находит свои настройки); `db.point` / `db.hidden` — начальное место и видимость ленты у каждого персонажа при его первом входе. Значения проверяются как раньше (`settings.merge`): кривое → по умолчанию.
- **Настройки аккаунта, не профиля:** `updateCheck`, `minimap`, `levelCards`, `elvui` — в `db.ui` (одна кнопка у миникарты и один стиль на все профили). Всё остальное, включая `compact`, — в профиле.
- **Автовыбор.** Правила: «Battleground or arena», «In a raid», «In a dungeon», «While leveling (below 80)»; в открытом мире — профиль, выбранный вручную. Порядок: pvp → raid → party → leveling → выбранный вручную. Где персонаж — второе значение `IsInInstance()`: `"none"`, `"pvp"`, `"arena"`, `"party"`, `"raid"` (сверено по FrameXML 3.3.5a: `WorldStateFrame.lua:117` `local inInstance, instanceType = IsInInstance();`, `UIParent.lua:666–667` `instanceType == "arena"`). `GetInstanceInfo()` в 3.3.5a — `name, instanceType, difficulty, difficultyName, maxPlayers, playerDifficulty, isDynamicInstance` (`Minimap.lua:486`); для правил он не нужен, 10/25 и героик — «Потом». Уровень — аргумент `PLAYER_LEVEL_UP` (в момент события `UnitLevel` ещё старый), иначе `UnitLevel("player")`. Проверка — на `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`, `PLAYER_LEVEL_UP`. Смена профиля перезапускает движок, поэтому в бою (`InCombatLockdown()`) откладывается до `PLAYER_REGEN_ENABLED`; при автосмене — одна строка в чат.
- **Управление профилями** — своя страница «Profiles» под DoubtMyRotation в Interface → AddOns: выбор профиля персонажа, «Active now: … (почему)», имя + «New» / «Copy current», «Delete» (второе нажатие подтверждает, Default не удаляется), «Reset active profile», четыре списка правил. Изменения сразу, без Okay/Cancel (профиль — не значение, которое откатывают).
- **Режим «одна кнопка»** — единственная правка движка: опция `compact` → `timeline` рисует одну крупную иконку на месте черты (не едет), свечение «жми», подпись и алерт; без дорожки, черты, ударов, окна Bolt, полосы GCD и точек Maelstrom; рамка шириной `2 × nowX` (120). `runtime.timelineOptions` передаёт `compact`. Аура этой опции не получает (её нет в `tools/aura.lua`), код в строке импорта — сотни байт; запас сейчас 848 байт (62 152 из `B.MAX_IMPORT` = 63 000, сборка `v1.0.5-22`) — проверка в задаче 1.
- **Одно сообщение за раз, ничего в бою.** Очередь `guide`: окно мастера или карточки открывается, только если ничего не открыто и игрок не в бою (`InCombatLockdown()` или `UnitAffectingCombat("player")`); вход в бой (`PLAYER_REGEN_DISABLED`) прячет открытое окно и ставит его первым в очередь, после боя (`PLAYER_REGEN_ENABLED`) оно открывается снова на той же странице.
- **Мастер** — 4 экрана: лента; «жми у черты»; «перетащи сюда» (лента открепляется, уход с экрана закрепляет обратно; тут же галочка «One button mode»); «всё ли готово» — список этапа 1, если он есть, иначе короткий текст. Кнопки: «Back», «Next» / «Done», «Skip» (закрыть; покажется при следующем входе этим персонажем), «Don't show again» (никогда, ни на одном персонаже: `db.wizardOff`). «Done» — этому персонажу больше не показывать (`char.wizard = "done"`). Escape = «Skip». Открыть снова: `/dmr guide` и кнопка «Show the guide» на странице General.
- **Карточки** — 8 штук, на 10/20/30/40/50/60/70/80, тексты вручную в `addon/cards.lua`. Числа в текстах (уровни, кулдауны, длительности, заряды) — не руками, а подстановкой из `src/spells_data.lua`, `src/spells.lua`, `src/talents.lua`; список «new since level N» под текстом — из тех же данных. Заклинания-таланты (Stormstrike, Lava Lash, Shamanistic Rage, Feral Spirit) — по уровню стандартной прокачки `talents.standard`: 40, 45, 50, 60 (уровень ранга в `spells_data` у них — уровень заклинания, а не момент, когда его можно взять). Тест ловит название заклинания или таланта в тексте карточки раньше его уровня. Аддон поставлен на персонажа уровня N → карточки ≤ N помечаются виденными без показа; через несколько карточек разом (выключал опцию) — только последняя. Отметка — когда игрок закрыл карточку.
- **Кнопка у миникарты** — своя `Button` на `Minimap` (без LibDBIcon), стандартная разметка кнопки миникарты 3.3.5a (иконка 20×20, рамка `Interface\Minimap\MiniMap-TrackingBorder` 53×53). ЛКМ — окно настроек, ПКМ — показать/скрыть ленту, перетаскивание ЛКМ — по краю миникарты: по кругу, у квадратной (`GetMinimapShape() == "SQUARE"`, так её объявляет ElvUI: `Modules/Maps/Minimap.lua:447–449`) — по краю квадрата. Угол — `char.minimap.angle` (по умолчанию 200°). Отключается опцией `minimap` (General).
- **Окно настроек в бою не открываем** (ни `/dmr`, ни кнопкой у миникарты): `InterfaceOptionsFrame_OpenToCategory` из кода аддона в бою рискует taint стандартных страниц Interface Options. В бою — одна строка «the settings open after combat», окно открывается на `PLAYER_REGEN_ENABLED`.
- **ElvUI.** Сторонний аддон берёт движок из глобальной `ElvUI` (`Init.lua:38, 43`: `Engine[1] = AddOn`, `_G[AddOnName] = Engine`) → `E = ElvUI[1]`, `S = E:GetModule("Skins", true)` (AceAddon, `silent`). Модули ElvUI инициализируются в его обработчике `PLAYER_LOGIN` (`Init.lua:208–212` → `E:Initialize` → `InitializeModules`, `Core/Core.lua:1257–1281`); `S:Initialize` первой строкой ставит `S.Initialized = true` и вызывает колбэки `S:AddCallback` (`Modules/Skins/Skins.lua:960–1015`, `S:Initialize` — строка 989), позже добавленные колбэки уже никто не вызовет. Отсюда правило: `S.Initialized` — оформлять сразу, иначе один `S:AddCallback("DoubtMyRotation", …)`. В `.toc` — `## OptionalDeps: ElvUI`: ElvUI грузится раньше, его `PLAYER_LOGIN` срабатывает раньше нашего, окна оформляются сразу; без этого (другое имя папки) работает отложенный путь. Каждый вызов ElvUI — через `pcall`: несовместимая версия → одна строка в чат, окна остаются стандартными. Какие функции: `S:HandleSliderFrame(frame)` (ползунки), `S:HandleCheckBox(frame)` (галочки), `S:HandleDropDownBox(frame, width)` (списки), `S:HandleButton(button)` (кнопки), `S:HandleEditBox(frame)` (поле имени профиля), `S:HandleCloseButton(f)` и `S:HandleScrollBar(frame)` (окно экспорта), `frame:SetTemplate("Transparent")` (окна, подложка ленты; `SetTemplate` ElvUI вешает на метатаблицу всех рамок, `Core/Toolkit.lua:80, 309–330`). Сами страницы Interface Options ElvUI уже оформляет как контейнер (`Blizzard/BlizzardOptions.lua:72`), наши элементы на них — нет, их и оформляем. Опция `elvui` (Advanced, по умолчанию вкл.): включение — сразу, выключение — после `/reload` (снять стиль ElvUI нельзя). Подсветку кнопок на панелях ElvUI делает этап 1 — здесь её нет.
- **Хосты окон.** Каждое новое окно получает таблицу-хост (функции core), а не глобальные переменные: так окна тестируются без `core`, а `core` — с подменёнными окнами (`package.loaded.<модуль>`), как уже сделано для `panel` и `update`.

## Global Constraints

- Lua 5.1. В `src/` нельзя `pcall`, `loadstring`, `setfenv`, `getfenv`, `_G`, `SlashCmdList`, `package`, `io`, `debug` — даже в комментариях (`spec/build_spec.lua` «uses nothing the WeakAuras sandbox blocks»). Код `addon/` этой проверке не подлежит (`pcall`, `_G` можно), но `io`, `package`, `debug`, `require` в клиенте нет.
- API только 3.3.5a: никаких `C_Timer`, `SetShown`, `Settings.*`, `ActionButton_ShowOverlayGlow`; таймеры — через `OnUpdate`. Шаблоны — существующие в 3.3.5a FrameXML: `UIPanelButtonTemplate`, `UIPanelCloseButton`, `InputBoxTemplate`, `InterfaceOptionsCheckButtonTemplate`, `OptionsSliderTemplate`, `UIDropDownMenuTemplate`, `UIPanelScrollFrameTemplate` (сверено: `UIPanelTemplates.xml:18, 138, 285, 426`).
- Тексты в игре — на английском. Перевода нет.
- Ничего обучающего в бою; одно сообщение за раз; не трогать защищённые рамки и не нажимать ничего за игрока (раздел «Чего не делать» дорожной карты).
- Каждая фича этапа отключаема: `compact`, `minimap`, `levelCards`, `elvui` — опции окна настроек; мастер — «Don't show again»; автовыбор профиля — правила по умолчанию пустые.
- Строка импорта ауры — не длиннее `B.MAX_IMPORT` (63000); аддон в неё не входит.
- `src/spells_data.lua` руками не править.
- Все команды — в контейнере: `docker compose run --rm test busted …`, на хосте Lua нет.
- Коммиты — по-русски, в стиле `git log` (`Аддон: …`), без номеров задач и без упоминаний ИИ (`Co-Authored-By`, «Generated with» запрещены). Ветка — `feat/comfort`; в `main` — только через PR.
- Комментарии в коде — по-английски, объясняют «почему».

## Review Focus

1. **Бой.** Мастер и карточки не открываются в бою; вход в бой прячет открытое окно и возвращает его после (та же страница мастера, лента снова закреплена на время боя). Смена профиля в бою (зона, уровень, правило, кнопка на странице) откладывается до `PLAYER_REGEN_ENABLED` — движок не перезапускается посреди боя. `/dmr` и ЛКМ по кнопке у миникарты в бою не открывают Interface Options (одна строка, открытие после боя) (тесты — задачи 5, 8).
2. **Taint.** Ни один модуль не меняет скрипты и точки чужих рамок: кнопка у миникарты — наш ребёнок `Minimap`, `HookScript`/`SetScript` только на наших рамках; ElvUI оформляет только наши виджеты. `InterfaceOptionsFrame_OpenToCategory` не зовётся под `InCombatLockdown()` (тест — задача 8).
3. **Потеря настроек при переходе на профили.** `db.config` прошлой версии → профиль Default с теми же значениями, `db.config` остаётся; `db.point` / `db.hidden` → у каждого персонажа при его первом входе; второй вход ничего не перетирает; профиль, удалённый на другом персонаже, у этого падает на Default (и его правила снимаются); «Cancel» в окне настроек после смены профиля не копирует значения старого профиля в новый (`panel.reload`). Изменение `.toc` (новая `SavedVariablesPerCharacter`) клиент читает только при запуске игры: после обновления без перезапуска `DoubtMyRotationCharDB` не сохранится — аккаунтовая база при этом цела, README говорит «перезапустите игру» (тесты — задачи 3, 8; README — задача 9).
4. **ElvUI раньше / позже / нет.** Раньше (инициализирован к нашему `PLAYER_LOGIN`) → оформлено сразу; позже → ничего до его `S:Initialize`, потом всё одним колбэком (один `AddCallback`, сколько бы окон ни было); нет ElvUI → ни одного обращения, окна как раньше; опция выключена → ничего; функция ElvUI падает → одна строка в чат, без ошибки Lua, окна работают (тесты — задача 7, сквозной — задача 8).
5. **Одно сообщение за раз.** Мастер и карточка вместе не открываются; `/dmr guide` при открытой карточке — после неё; одна и та же карточка или мастер в очередь дважды не встают (тест — задача 5).
6. **Тексты карточек без выдумок.** Каждое название заклинания из `spells.CATALOG` и таланта из `talents.KEYS` в тексте карточки — не раньше уровня, на котором его можно получить; каждое число — подстановка из данных (тест — задача 4).
7. **Режим «одна кнопка»** включается и выключается на лету (движок перезапускается, лента переиспользуется) — дорожка, удары и точки возвращаются; строка импорта ауры ≤ `B.MAX_IMPORT` (тест — задача 1).

---

## Карта файлов

- Modify `spec/support/game_mock.lua` (задача 0) — методы рамок и функции клиента для окон этапа 3; метатаблица рамок `G.FRAME` (на неё мок ElvUI вешает `SetTemplate`).
- Modify `src/timeline.lua`, `src/runtime.lua` (`timelineOptions`) — режим `compact`; тесты `spec/timeline_spec.lua`, `spec/runtime_spec.lua`.
- Modify `addon/settings.lua` — `ADDON_OPTIONS`, `withExtra`, действие `guide`; `addon/panel.lua` — новые опции по разделам, кнопка «Show the guide», `kind` у кнопок, `main.widgets`, `panel.reload`; `tools/build.lua` `B.addonToc` — `SavedVariablesPerCharacter`, `OptionalDeps`. Тесты `spec/addon_settings_spec.lua`, `spec/addon_panel_spec.lua`, `spec/build_spec.lua` (toc).
- Create `addon/profiles.lua`, `addon/profilepage.lua`; `spec/addon_profiles_spec.lua`, `spec/addon_profilepage_spec.lua`.
- Create `addon/cards.lua`; `spec/addon_cards_spec.lua`.
- Create `addon/guide.lua`, `addon/wizard.lua`, `addon/coach.lua`; `spec/addon_guide_spec.lua`, `spec/addon_wizard_spec.lua`, `spec/addon_coach_spec.lua`.
- Create `addon/minimap.lua`; `spec/addon_minimap_spec.lua`.
- Create `addon/skin.lua`, `spec/support/elvui_mock.lua`; `spec/addon_skin_spec.lua`.
- Modify `addon/core.lua`, `spec/addon_core_spec.lua`; `tools/build.lua` `B.ADDON_MODULES`; сквозной тест в `spec/build_spec.lua` (блок `describe("addon build", …)`).
- Modify `README.md`, `AGENTS.md` (одна строка), `.claude/rules/ARCHITECTURE.md`, `docs/superpowers/specs/2026-10-01-addon-roadmap.md`.

---

### Task 0: Моки клиента для этапа 3

Делает интегратор до волны 1 прямо в `feat/comfort` (одним коммитом): все исполнители волны 1 опираются на эти методы, а `game_mock.lua` — общий файл.

**Files:**
- Modify: `spec/support/game_mock.lua` (`region`, `G.fontString`, `G.frame`, `CreateFrame`, `G.install`)

**Interfaces:**
- Produces: у регионов — `SetFrameLevel`/`GetFrameLevel`; у строк — `SetJustifyV`; у рамок — `GetChildren` (рамки, созданные с этим родителем), `GetCenter` (`f.center = { x, y }`), `GetEffectiveScale`, `RegisterForClicks`, `SetNormalTexture`/`SetHighlightTexture`/`SetPushedTexture`, `ClearFocus`, `SetToplevel`, `Enable`/`Disable`/`IsEnabled` (1 или nil, как в 3.3.5a); `G.FRAME` — общая метатаблица методов рамок (`__index`), очищается в `G.install`. Функции клиента: `InCombatLockdown` (`cfg.lockdown`), `IsInInstance` (`cfg.instance`, по умолчанию `"none"`), `GetInstanceInfo`, `GetCursorPosition` (`cfg.cursor`), `GetMinimapShape` (только если задан `cfg.minimapShape`), рамка `Minimap` (центр `cfg.minimapCenter` или `{ 1000, 700 }`), `UISpecialFrames = {}`; сброс глобальных `DoubtMyRotation{CharDB,Wizard,Card,MinimapButton,Guide,Coach,Events,PanelProfiles}`.
- Важно: `UnitAffectingCombat("player")` в моке по умолчанию отдаёт «в бою» (`cfg.inCombat ~= false`). Тесты, где окно должно открыться, ставят `inCombat = false`.

- [ ] **Step 1: Правка мока.** В `region(kind)` перед `return r`:

```lua
  function r:SetFrameLevel(l) self.level = l end
  function r:GetFrameLevel() return self.level or 1 end
```

В `G.fontString()` перед `return f`:

```lua
  function f:SetJustifyV(j) self.justifyV = j end
```

В `G.frame(kind, name)`: после строки `f.name, f.events, f.scripts, f.children = …` добавить `f.kids = {}`; перед `return f`:

```lua
  -- the windows of stage 3: child frames, the minimap button, edit boxes, buttons
  function f:GetChildren() return unpack(self.kids) end
  function f:GetCenter() local c = self.center or { 0, 0 }; return c[1], c[2] end
  function f:GetEffectiveScale() return self.scale or 1 end
  function f:RegisterForClicks(...) self.clicks = { ... } end
  function f:SetNormalTexture(p) self.normalTexture = p end
  function f:SetHighlightTexture(p) self.highlightTexture = p end
  function f:SetPushedTexture(p) self.pushedTexture = p end
  function f:ClearFocus() self.focused = false end
  function f:SetToplevel(t) self.toplevel = t end
  function f:Enable() self.disabled = false end
  function f:Disable() self.disabled = true end
  -- the 3.3.5a client gives 1 or nil
  function f:IsEnabled() return (not self.disabled) and 1 or nil end
  -- methods a UI addon puts on every frame's metatable (ElvUI's SetTemplate: spec/support/elvui_mock.lua)
  return setmetatable(f, { __index = G.FRAME })
```

(последнюю строку `return f` заменяет `return setmetatable(…)`). Над `function G.frame` объявить `G.FRAME = {}`.

В `_G.CreateFrame` после `f.template = template`:

```lua
    -- not f.parent: on an options page that field names the parent category (panel_mock sets it)
    if parent and parent.kids then parent.kids[#parent.kids + 1] = f end
```

В `G.install(cfg)` после `G.sent, G.printed = {}, {}`:

```lua
  for k in pairs(G.FRAME) do G.FRAME[k] = nil end
```

После `_G.WorldFrame = …`:

```lua
  _G.InCombatLockdown = function() return cfg.lockdown and 1 or nil end
  -- IsInInstance's second value: "none", "pvp", "arena", "party", "raid" (FrameXML WorldStateFrame.lua)
  _G.IsInInstance = function()
    local kind = cfg.instance or "none"
    return (kind ~= "none") and 1 or nil, kind
  end
  _G.GetInstanceInfo = function()
    local kind = cfg.instance or "none"
    return cfg.zone or "Northrend", kind, 1, "", kind == "raid" and 25 or 5, 0, false
  end
  _G.GetCursorPosition = function() local c = cfg.cursor or { 0, 0 }; return c[1], c[2] end
  _G.Minimap = G.frame("Frame", "Minimap")
  Minimap.center = cfg.minimapCenter or { 1000, 700 }
  -- the client has no GetMinimapShape; addons that reshape the minimap (ElvUI) define it
  _G.GetMinimapShape = cfg.minimapShape and function() return cfg.minimapShape end or nil
  _G.UISpecialFrames = {}
```

Список сброса глобальных аддона:

```lua
  for _, k in ipairs({ "Addon", "DB", "CharDB", "Loader", "Frame", "Timer", "Updates", "Panel", "PanelCombat",
                       "PanelAdvanced", "PanelProfiles", "Wizard", "Card", "MinimapButton", "Guide", "Coach", "Events" }) do
    _G["DoubtMyRotation" .. k] = nil
  end
```

- [ ] **Step 2: Прогон.** `docker compose run --rm test busted --exclude-tags=perf` — всё зелёное, как до правки (мок только расширен; метатаблица `G.FRAME` пуста, пока её не заполнит мок ElvUI).

- [ ] **Step 3: Коммит.** `Тесты: мок клиента для окон этапа 3 — дочерние рамки, миникарта, подземелья, бой`.

### Task 1: Режим «одна кнопка» — `compact` в `src/timeline.lua`

**Files:**
- Modify: `src/timeline.lua` (`M.options` ~20, `M.layout` ~66–110, `TL:setup` ~250, `TL:tick` ~330–390)
- Modify: `src/runtime.lua` (`M.timelineOptions` ~713)
- Test: `spec/timeline_spec.lua` (в конце `describe("timeline layout")` и `describe("timeline render")`), `spec/runtime_spec.lua` (блок `describe("runtime")`)

**Interfaces:**
- Produces: опция ленты `compact` (`true` / `nil`): `timeline.options({ compact = true })` → `icons = 1`, `width = 2 * nowX`; `timeline.layout(...)` → `L.compact = true`, одна иконка с `x = nowX` при любом времени, `L.ticks = {}`, `L.window = nil`, `L.gcd = nil`; `TL:tick` прячет дорожку, черту и точки Maelstrom; иконка, свечение, подпись и алерт — как обычно. `runtime.timelineOptions(config).compact` — `config.compact == true`.
- Consumes: ничего нового.

- [ ] **Step 1: Тесты.** В `spec/timeline_spec.lua`, в конце `describe("timeline layout", …)`:

```lua
  -- one button mode (the addon's option "compact"): the next button on the line, nothing else
  it("one button mode: one icon fixed on the line, no swings, no Bolt window, no GCD", function()
    local L = timeline.layout(plan({ "stormstrike", 2.0, "Stormstrike" }, { "lavaLash", 3.0 }),
      S({ gcdRemains = 1.0 }), { compact = true }, 0)
    assert.is_true(L.compact)
    assert.are.equal(1, #L.icons)
    assert.are.equal(60, L.icons[1].x)
    assert.are.equal("Stormstrike", L.reason)
    assert.are.equal(0, #L.ticks)
    assert.is_nil(L.window)
    assert.is_nil(L.gcd)
    local o = timeline.options({ compact = true, icons = 4 })
    assert.are.equal(1, o.icons)
    assert.are.equal(120, o.width)
    -- the same state without the option: swings, the Bolt window and the GCD band are there
    local full = timeline.layout(plan({ "stormstrike", 2.0 }, { "lavaLash", 3.0 }), S({ gcdRemains = 1.0 }), {}, 0)
    assert.is_true(#full.ticks > 0)
    assert.is_not_nil(full.window)
    assert.is_not_nil(full.gcd)
  end)
```

В конце `describe("timeline render", …)`:

```lua
  it("one button mode draws the big icon and the alert only; off again, the full timeline is back", function()
    local parent = CreateFrame("Frame")
    local fight = S({ target = { exists = true, enemy = true } })
    local p = plan({ "stormstrike", 0, "Stormstrike" }, { "lavaLash", 1.5 })
    local tl = timeline.new(parent, { compact = true })
    assert.is_false(tl.lane.shown) -- not even before the first plan
    tl:render(p, fight, 100)
    tl:setAlert({ icon = "Interface\\Icons\\X", reason = "Cast Lightning Shield" })
    tl:tick(0.016)
    assert.are.equal(120, tl.frame.w)
    assert.is_true(tl.icons[1].shown)
    assert.is_nil(tl.icons[2])
    assert.is_true(tl.glow.shown)
    assert.are.equal("Stormstrike", tl.reason.text)
    assert.is_true(tl.alert.shown)
    assert.is_false(tl.lane.shown)
    assert.is_false(tl.now.shown)
    for _, t in ipairs(tl.ticks) do assert.is_false(t.shown) end
    for _, d in ipairs(tl.dots) do assert.is_false(d.shown) end
    -- the option off: the addon restarts the engine, the timeline is reused
    tl:setup(parent, {})
    tl:render(p, fight, 100)
    tl:tick(0.016)
    assert.are.equal(340, tl.frame.w)
    assert.is_true(tl.lane.shown)
    assert.is_true(tl.now.shown)
    assert.is_true(tl.ticks[1].shown)
    assert.is_true(tl.dots[1].shown)
    assert.is_true(tl.icons[2].shown)
  end)
```

В `spec/runtime_spec.lua`, внутри `describe("runtime", …)`:

```lua
  it("one button mode reaches the timeline; without the option (the aura) it is off", function()
    assert.is_true(runtime.timelineOptions({ compact = true }).compact)
    assert.is_false(runtime.timelineOptions({}).compact)
  end)
```

- [ ] **Step 2: Красный прогон.** `docker compose run --rm test busted spec/timeline_spec.lua spec/runtime_spec.lua` — три новых теста падают (`compact` не читается: 2 иконки, ширина 340, `timelineOptions(...).compact` — `nil`).

- [ ] **Step 3: Реализация.** `src/timeline.lua`, в `M.options` перед `return o`:

```lua
  -- one button mode: one icon on a frame just wide enough for it (the alert sits left of it)
  if o.compact then o.icons, o.width = 1, 2 * o.nowX end
```

В `M.layout`: в таблицу `L` добавить поле `compact = o.compact`; в цикле по шагам вместо `local x = M.xOf(t, o)`:

```lua
      -- one button mode: the icon waits on the line, the glow says when (no lane to slide along)
      local x = o.compact and o.nowX or M.xOf(t, o)
```

и сразу после цикла по шагам (перед `local swings = …`):

```lua
  if o.compact then return L end
```

В `TL:setup` после `place(self.now, …)`:

```lua
  if o.compact then self:showLane(false) end
```

В `TL:tick` вместо `self:showLane(not L.idle)`:

```lua
  self:showLane(not L.idle and not L.compact)
```

и цикл точек Maelstrom:

```lua
  for i, d in ipairs(self.dots) do
    if L.compact then
      d:Hide()
    else
      d:SetVertexColor(unpack(i <= L.dots and M.COLORS.dotOn or M.COLORS.dotOff))
      d:Show()
    end
  end
```

`src/runtime.lua`:

```lua
function M.timelineOptions(config)
  return { icons = config.icons, seconds = config.seconds, scale = config.scale, showReason = config.showReason ~= false,
           compact = config.compact == true }
end
```

Комментарии — без запрещённых слов (`spec/build_spec.lua` проверяет и их).

- [ ] **Step 4: Зелёный прогон и размер ауры.** `docker compose run --rm test busted spec/timeline_spec.lua spec/runtime_spec.lua spec/build_spec.lua` — зелёные, включая «import string … ≤ MAX_IMPORT». `docker compose run --rm test lua tools/build.lua` — записать в отчёт новый размер `dist/DoubtMyRotation.txt` (было 62 152). Если вышло больше `B.MAX_IMPORT` — не поднимать потолок: ужать новый код (одна проверка `o.compact` в `layout`, без новых полей в `DEFAULTS`) и сообщить.

- [ ] **Step 5: Весь набор.** `docker compose run --rm test busted --exclude-tags=perf` — зелёный (поиск не тронут, «бит в бит» не меняется).

- [ ] **Step 6: Коммит.** `Лента: режим «одна кнопка» — только крупная иконка и алерт`.

### Task 2: Опции аддона, окно настроек, toc

**Files:**
- Modify: `addon/settings.lua` (`M.HELP`, `M.ACTIONS`, новые `M.ADDON_OPTIONS`, `M.withExtra`)
- Modify: `addon/panel.lua` (`M.ACTIONS`, `M.SECTIONS`, раскладка кнопок, `kind` у кнопок, `main.widgets`, новая `M.reload`)
- Modify: `tools/build.lua` (только `B.addonToc`)
- Test: `spec/addon_settings_spec.lua`, `spec/addon_panel_spec.lua`, `spec/build_spec.lua` (тест toc в блоке `describe("addon build", …)`)

**Interfaces:**
- Produces:
  - `settings.ADDON_OPTIONS` — опции только аддона, в этом порядке:
    `{ type = "toggle", key = "compact", name = "One button mode", desc = "Only the big icon and reminders: no lane, no swings, no stacks", default = false }`,
    `{ type = "toggle", key = "minimap", name = "Minimap button", desc = "Left-click: settings, right-click: show or hide the timeline, drag: move it", default = true }`,
    `{ type = "toggle", key = "levelCards", name = "What's new on level up", desc = "A short card at levels 10, 20 ... 80, out of combat, once", default = true }`,
    `{ type = "toggle", key = "elvui", name = "ElvUI style", desc = "Style these windows like ElvUI when it is installed. Turning it off takes a /reload", default = true }`;
  - `settings.withExtra(options, extra) -> list` — копия `options` и в конце опции из `extra`, ключей которых в `options` нет; входные списки не меняются;
  - `settings.ACTIONS.guide = true` (`/dmr guide` → `action = "guide"`), строка помощи `/dmr guide - the first-run guide again` (четвёртая в `settings.HELP`);
  - `panel.ACTIONS = { "lock", "export", "hide", "guide" }`, по 3 кнопки в ряд (`panel.PER_ROW = 3`); у каждой кнопки действия `b.kind = "button"`;
  - `panel.SECTIONS`: General — `scale, seconds, icons, showReason, showLust, compact, minimap, levelCards`; Combat — как было; Advanced — `weave, manaPolicy, record, printDebug, updateCheck, elvui`;
  - `main.widgets` — список всех элементов всех трёх страниц (элементы опций и кнопки действий) в порядке создания; у каждого есть `kind` (`"range"`, `"toggle"`, `"select"`, `"button"`) — по нему их оформляет `addon/skin.lua`;
  - `panel.reload(main)` — пришли настройки другого профиля: снимок для «Cancel», если был (окно открыто), выбрасывается и берётся заново с новыми значениями; если окно не открывалось — ничего;
  - `B.addonToc(version)` — плюс строки `## SavedVariablesPerCharacter: DoubtMyRotationCharDB` и `## OptionalDeps: ElvUI` (после `## SavedVariables: DoubtMyRotationDB`).
- Consumes: хост окна `{ config, set, replace, action, label, quiet }` — как сейчас; `host.label("guide")` даёт текст кнопки (core, задача 8).

- [ ] **Step 1: Тесты настроек.** В `spec/addon_settings_spec.lua`:

```lua
  it("the addon's own options: toggles with valid defaults, in a fixed order", function()
    local keys = {}
    for _, o in ipairs(settings.ADDON_OPTIONS) do
      assert.are.equal("toggle", o.type)
      assert.is_string(o.name)
      assert.is_true(settings.valid(o, o.default), o.key)
      keys[#keys + 1] = o.key
    end
    assert.are.same({ "compact", "minimap", "levelCards", "elvui" }, keys)
  end)

  it("withExtra adds the options not there yet, as a copy", function()
    local extra = { { type = "toggle", key = "showReason", name = "again", default = false },
                    { type = "toggle", key = "brandNew", name = "Brand new", default = true } }
    local list = settings.withExtra(OPTIONS, extra)
    assert.are.equal(#OPTIONS + 1, #list)
    assert.are.equal(OPTIONS[1], list[1])
    assert.are.equal("brandNew", list[#list].key)
    assert.are_not.equal(OPTIONS, list)
    assert.are.equal(3, #OPTIONS)
    assert.are.equal(2, #extra)
  end)
```

В тесте «plain words are actions» список — `{ "export", "lock", "unlock", "show", "hide", "guide" }`. В тесте «an empty line asks to open the window, help prints help» добавить:

```lua
    assert.are.equal("/dmr guide - the first-run guide again", r.lines[#r.lines])
```

- [ ] **Step 2: Тесты окна.** В `spec/addon_panel_spec.lua` тест «the real options all have a section» — и опции аддона:

```lua
  it("the real options all have a section", function()
    local aura = require("aura")
    local placed, where = {}, {}
    for _, sec in ipairs(panel.SECTIONS) do
      for _, k in ipairs(sec.options) do placed[k], where[k] = true, sec.key end
    end
    for _, o in ipairs(aura.OPTIONS) do
      if o.key ~= "export" then assert.is_true(placed[o.key], o.key) end
    end
    for _, o in ipairs(settings.ADDON_OPTIONS) do assert.is_true(placed[o.key], o.key) end
    assert.are.equal("advanced", where.updateCheck)
    assert.are.equal("general", where.compact)
    assert.are.equal("general", where.minimap)
    assert.are.equal("general", where.levelCards)
    assert.are.equal("advanced", where.elvui)
    assert.is_nil(placed.export)
  end)
```

Тест «the action buttons call the host and show its label»:

```lua
  it("the action buttons call the host and show its label, three in a row", function()
    local h = host()
    local f = panel.new({ options = OPTIONS }, h)
    f.refresh(f)
    assert.are.equal("Unlock timeline", f.buttons.lock.text)
    for _, name in ipairs({ "lock", "export", "hide", "guide" }) do
      f.buttons[name]:Click()
      assert.are.equal("button", f.buttons[name].kind)
    end
    assert.are.same({ "lock", "export", "hide", "guide" }, h.actions)
    assert.are.equal(f, f.buttons.lock:GetParent())
    -- the fourth starts the second row, under the first
    assert.are.equal(f.buttons.lock.point[4], f.buttons.guide.point[4])
    assert.is_true(f.buttons.guide.point[5] < f.buttons.lock.point[5])
  end)

  -- addon/skin.lua styles what is listed here, by kind
  it("lists every control and button of all pages in widgets", function()
    local f = panel.new({ options = OPTIONS }, host())
    local seen = {}
    for _, w in ipairs(f.widgets) do
      assert.is_string(w.kind)
      seen[w] = true
    end
    for _, c in pairs(f.controls) do assert.is_true(seen[c]) end
    for _, b in pairs(f.buttons) do assert.is_true(seen[b]) end
    assert.are.equal(#OPTIONS + #panel.ACTIONS, #f.widgets)
  end)

  -- another profile came in (addon/core.lua): Cancel goes back to it, not to the old profile
  it("reload takes a fresh snapshot for Cancel only when the window had one", function()
    local h = host()
    local f = panel.new({ options = OPTIONS }, h)
    panel.reload(f)
    assert.is_nil(f.opened)
    f.refresh(f)
    h.cfg = { scale = 2, mode = 2, showReason = false } -- the new profile's values
    panel.reload(f)
    f.controls.scale:SetValue(1.5)
    f.cancel(f)
    assert.are.same({ scale = 2, mode = 2, showReason = false }, h.cfg)
  end)
```

В `spec/build_spec.lua`, тест «the addon's toc: 3.3.5a, its SavedVariables, its one file» — две проверки:

```lua
    assert.truthy(toc:find("## SavedVariablesPerCharacter: DoubtMyRotationCharDB\n", 1, true))
    assert.truthy(toc:find("## OptionalDeps: ElvUI\n", 1, true))
```

- [ ] **Step 3: Красный прогон.** `docker compose run --rm test busted spec/addon_settings_spec.lua spec/addon_panel_spec.lua spec/build_spec.lua` — новые проверки падают (`ADDON_OPTIONS`, `withExtra`, `guide`, `widgets`, `reload`, строки toc).

- [ ] **Step 4: Реализация `addon/settings.lua`.**

```lua
M.HELP = {
  "/dmr list - settings; /dmr set <key> <value> - change one",
  "/dmr reset - defaults; /dmr export - copy window with snapshots",
  "/dmr lock | unlock - move the timeline; /dmr show | hide",
  "/dmr guide - the first-run guide again",
}
M.ACTIONS = { export = true, lock = true, unlock = true, show = true, hide = true, guide = true }

-- the addon's own options, on top of the aura's (tools/aura.lua M.OPTIONS): the aura has none of these
M.ADDON_OPTIONS = {
  { type = "toggle", key = "compact", name = "One button mode",
    desc = "Only the big icon and reminders: no lane, no swings, no stacks", default = false },
  { type = "toggle", key = "minimap", name = "Minimap button",
    desc = "Left-click: settings, right-click: show or hide the timeline, drag: move it", default = true },
  { type = "toggle", key = "levelCards", name = "What's new on level up",
    desc = "A short card at levels 10, 20 ... 80, out of combat, once", default = true },
  { type = "toggle", key = "elvui", name = "ElvUI style",
    desc = "Style these windows like ElvUI when it is installed. Turning it off takes a /reload", default = true },
}

-- options plus the extra ones not in it yet, as a new list: the build's list stays the aura's
function M.withExtra(options, extra)
  local list, have = {}, {}
  for i, o in ipairs(options) do list[i], have[o.key] = o, true end
  for _, o in ipairs(extra or {}) do
    if not have[o.key] then list[#list + 1], have[o.key] = o, true end
  end
  return list
end
```

- [ ] **Step 5: Реализация `addon/panel.lua`.**

```lua
M.ACTIONS = { "lock", "export", "hide", "guide" }
M.PER_ROW = 3

M.SECTIONS = {
  { key = "general",
    options = { "scale", "seconds", "icons", "showReason", "showLust", "compact", "minimap", "levelCards" }, actions = true },
  { key = "combat", title = "Combat",
    options = { "mode", "cdFeralSpirit", "cdFireElemental", "cdShamanisticRage", "shield" } },
  { key = "advanced", title = "Advanced",
    options = { "weave", "manaPolicy", "record", "printDebug", "updateCheck", "elvui" } },
}
```

В `M.new`: `local pages, controls, buttons, widgets = {}, {}, {}, {}`; после `controls[opt.key] = c` — `widgets[#widgets + 1] = c`; кнопки действий:

```lua
    if sec.actions then
      for j, act in ipairs(M.ACTIONS) do
        local b = CreateFrame("Button", "DoubtMyRotationPanel_" .. act, f, "UIPanelButtonTemplate")
        b.kind = "button"
        b:SetWidth(150)
        b:SetHeight(22)
        local col, line = (j - 1) % M.PER_ROW, math.floor((j - 1) / M.PER_ROW)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT + col * 160, M.TOP - #list * M.ROW - 8 - line * 28)
        b:SetScript("OnClick", function() host.action(act); main.refresh(main) end)
        buttons[act] = b
        widgets[#widgets + 1] = b
      end
    end
```

и `main.pages, main.controls, main.buttons, main.widgets = pages, controls, buttons, widgets`. После `M.new`:

```lua
-- another profile's settings came in (addon/core.lua): the snapshot taken for Cancel belongs to
-- the old profile, and Cancel would copy it over the new one. An open window takes a fresh one.
function M.reload(main)
  local open = main.opened ~= nil
  main.opened = nil
  if open then main.refresh(main) end
end
```

- [ ] **Step 6: Реализация `B.addonToc`.**

```lua
function B.addonToc(version)
  return table.concat({
    "## Interface: 30300",
    "## Title: DoubtMyRotation - Enh Shaman",
    "## Notes: Enhancement shaman rotation helper: a 6 s fight simulation, timeline and swing clock",
    "## Version: " .. (version or B.version()),
    "## SavedVariables: DoubtMyRotationDB",
    "## SavedVariablesPerCharacter: DoubtMyRotationCharDB",
    -- ElvUI first: its Skins module is up by our PLAYER_LOGIN (addon/skin.lua)
    "## OptionalDeps: ElvUI",
    "",
    "DoubtMyRotation.lua",
    "",
  }, "\n")
end
```

- [ ] **Step 7: Зелёный прогон.** `docker compose run --rm test busted spec/addon_settings_spec.lua spec/addon_panel_spec.lua spec/build_spec.lua`, затем `docker compose run --rm test busted --exclude-tags=perf` — зелёные. Сквозной тест сборки («runs as an addon …») ещё видит три страницы и старый `core` — он не меняется до задачи 8.

- [ ] **Step 8: Коммит.** `Аддон: опции этапа 3 в окне настроек, кнопка «Show the guide», toc для персонажа и ElvUI`.

### Task 3: Профили — `addon/profiles.lua`, `addon/profilepage.lua`

**Files:**
- Create: `addon/profiles.lua` (чистые функции над `DoubtMyRotationDB` и `DoubtMyRotationCharDB`)
- Create: `addon/profilepage.lua` (страница «Profiles» в Interface → AddOns)
- Test: `spec/addon_profiles_spec.lua`, `spec/addon_profilepage_spec.lua`

**Interfaces:**
- Produces:
  - `profiles.DEFAULT = "Default"`, `profiles.MAX_LEVEL = 80`, `profiles.NAME_MAX = 24`;
  - `profiles.ACCOUNT = { updateCheck = true, minimap = true, levelCards = true, elvui = true }` — ключи, которые живут в `db.ui`, а не в профиле;
  - `profiles.RULES = { "pvp", "raid", "party", "leveling" }` (порядок старшинства), `profiles.RULE_NAMES[rule]` — подписи на странице: `"Battleground or arena"`, `"In a raid"`, `"In a dungeon"`, `"While leveling (below 80)"`;
  - `profiles.migrate(db, char) -> db, char` — заполняет `db.profiles` (из `db.config`, если профилей ещё нет), `db.ui`, `char.profile`, `char.auto`, `char.point`, `char.hidden`; повторный вызов ничего не меняет; `db.config` не трогает;
  - `profiles.names(db) -> { "Default", …остальные по алфавиту }`;
  - `profiles.pick(db, char, where, level) -> name, why` — `where` — второе значение `IsInInstance()`; `why` ∈ `"pvp"`, `"raid"`, `"party"`, `"leveling"`, `"picked"`;
  - `profiles.view(options, db, name) -> config` — значения профиля и `db.ui` (для ключей `ACCOUNT`), проверенные `settings.merge`;
  - `profiles.store(options, db, name, config)` — обратно: каждый ключ опции — в `db.ui` или в профиль; профиля нет — ничего;
  - `profiles.create(db, name, from) -> name | nil, err` (имя обрезается по краям, 1–24 знака, не занятое; `from` — таблица значений для копии или `nil` — значения по умолчанию); `profiles.delete(db, char, name) -> true | nil, err` (Default — нельзя; у персонажа выбор → Default, его правила на это имя снимаются); `profiles.reset(db, name)` — профиль пустой (= значения по умолчанию).
  - `profilepage.new(host) -> page` — рамка `DoubtMyRotationPanelProfiles`, `page.name = "Profiles"`, `page.parent = "DoubtMyRotation"`, зарегистрирована `InterfaceOptions_AddCategory`, скрыта до показа; `page.controls` = `{ profile, name, new, copy, delete, reset, rule_pvp, rule_raid, rule_party, rule_leveling }`, `page.widgets` (у каждого `kind`: `"select"`, `"edit"`, `"button"`), `page.status` (строка «Active now: …» или ошибка), `page.refresh(page)`. Okay / Cancel / Defaults у страницы нет.
- Consumes: `settings.merge` (существующий); хост страницы — `{ list() -> names, current() -> имя, выбранное персонажем, active() -> name, why, pick(name), create(name, copyCurrent) -> name | nil, err, delete(name) -> true | nil, err, reset(), rule(rule) -> name | nil, setRule(rule, name | nil) }` (даёт core, задача 8; в тестах — свой).

- [ ] **Step 1: Тесты `spec/addon_profiles_spec.lua`.**

```lua
local profiles = require("profiles")
local settings = require("settings")

local OPTIONS = {
  { type = "range", key = "icons", name = "Icons", min = 1, max = 4, step = 1, default = 4 },
  { type = "toggle", key = "compact", name = "One button mode", default = false },
  { type = "toggle", key = "minimap", name = "Minimap button", default = true },
  { type = "toggle", key = "updateCheck", name = "Updates", default = true },
}

describe("addon profiles", function()
  -- the SavedVariables of the version before profiles: one account-wide config, place, hidden flag
  it("the old settings become the Default profile, nothing of them is lost", function()
    local db = { config = { icons = 2, compact = true, minimap = false }, point = { "TOP", nil, "TOP", 0, -50 }, hidden = true }
    local char = {}
    profiles.migrate(db, char)
    assert.are.same({ icons = 2, compact = true, minimap = false }, db.profiles.Default)
    assert.are_not.equal(db.config, db.profiles.Default)
    assert.are.same({ icons = 2, compact = true, minimap = false }, db.config) -- an older version still finds it
    assert.are.same({ minimap = false }, db.ui)
    assert.are.equal("Default", char.profile)
    assert.are.same({}, char.auto)
    assert.are.same({ "TOP", nil, "TOP", 0, -50 }, char.point)
    assert.is_true(char.hidden)
    local c = profiles.view(OPTIONS, db, "Default")
    assert.are.same({ icons = 2, compact = true, minimap = false, updateCheck = true }, c)
  end)

  it("a second run changes nothing; a new install starts empty", function()
    local db = { config = { icons = 2 } }
    local char = {}
    profiles.migrate(db, char)
    db.profiles.Default.icons = 3
    char.point = { "CENTER", nil, "CENTER", 1, 2 }
    db.point = { "TOP", nil, "TOP", 0, 0 }
    profiles.migrate(db, char)
    assert.are.equal(3, db.profiles.Default.icons)
    assert.are.same({ "CENTER", nil, "CENTER", 1, 2 }, char.point)
    local fresh, me = {}, {}
    profiles.migrate(fresh, me)
    assert.are.same({ Default = {} }, fresh.profiles)
    assert.is_nil(me.point)
    assert.is_false(me.hidden)
  end)

  -- profiles are the account's: another character may have deleted one this one uses
  it("a profile gone on another character falls back to Default, its rules go", function()
    local db = { profiles = { Default = {}, Raid = {} }, ui = {} }
    local char = { profile = "Leveling", auto = { raid = "Raid", party = "Gone" } }
    profiles.migrate(db, char)
    assert.are.equal("Default", char.profile)
    assert.are.same({ raid = "Raid" }, char.auto)
  end)

  it("pick: battleground, raid, dungeon, leveling, then the one picked by hand", function()
    local db = { profiles = { Default = {}, PvP = {}, Raid = {}, Dungeon = {}, Leveling = {}, Mine = {} } }
    local char = { profile = "Mine", auto = { pvp = "PvP", raid = "Raid", party = "Dungeon", leveling = "Leveling" } }
    assert.are.same({ "PvP", "pvp" }, { profiles.pick(db, char, "arena", 80) })
    assert.are.same({ "PvP", "pvp" }, { profiles.pick(db, char, "pvp", 70) })
    assert.are.same({ "Raid", "raid" }, { profiles.pick(db, char, "raid", 80) })
    assert.are.same({ "Dungeon", "party" }, { profiles.pick(db, char, "party", 60) })
    assert.are.same({ "Leveling", "leveling" }, { profiles.pick(db, char, "none", 79) })
    assert.are.same({ "Mine", "picked" }, { profiles.pick(db, char, "none", 80) })
    char.auto = {}
    assert.are.same({ "Mine", "picked" }, { profiles.pick(db, char, "raid", 80) })
    assert.are.same({ "Mine", "picked" }, { profiles.pick(db, char, nil, nil) })
  end)

  it("view checks every value, store puts each one where it lives", function()
    local db = { profiles = { Default = {}, Raid = { icons = 9, compact = true, minimap = true } }, ui = { minimap = false } }
    local c = profiles.view(OPTIONS, db, "Raid")
    assert.are.same({ icons = 4, compact = true, minimap = false, updateCheck = true }, c) -- 9 is out of range
    c.icons, c.minimap, c.updateCheck = 2, true, false
    profiles.store(OPTIONS, db, "Raid", c)
    assert.are.equal(2, db.profiles.Raid.icons)
    assert.is_true(db.ui.minimap)
    assert.is_false(db.ui.updateCheck)
    assert.is_nil(db.profiles.Raid.updateCheck)
    profiles.store(OPTIONS, db, "Gone", c)
    assert.is_nil(db.profiles.Gone)
  end)

  it("create, delete, reset and the list of names", function()
    local db = { profiles = { Default = { icons = 1 } }, ui = {} }
    local char = { profile = "Default", auto = {} }
    assert.are.equal("Raid", profiles.create(db, "  Raid ", { icons = 3 }))
    assert.are.same({ icons = 3 }, db.profiles.Raid)
    assert.are.equal("Alt", profiles.create(db, "Alt"))
    assert.are.same({}, db.profiles.Alt)
    assert.are.same({ nil, "Raid: there is one already" }, { profiles.create(db, "Raid") })
    assert.are.same({ nil, "a name of 1 to 24 letters" }, { profiles.create(db, "   ") })
    assert.are.same({ nil, "a name of 1 to 24 letters" }, { profiles.create(db, ("x"):rep(25)) })
    assert.are.same({ "Default", "Alt", "Raid" }, profiles.names(db))
    char.profile, char.auto.raid = "Raid", "Raid"
    assert.is_true(profiles.delete(db, char, "Raid"))
    assert.is_nil(db.profiles.Raid)
    assert.are.equal("Default", char.profile)
    assert.is_nil(char.auto.raid)
    assert.are.same({ nil, "Default stays" }, { profiles.delete(db, char, "Default") })
    assert.are.same({ nil, "Nope: no such profile" }, { profiles.delete(db, char, "Nope") })
    profiles.reset(db, "Default")
    assert.are.same({}, db.profiles.Default)
  end)
end)
```

- [ ] **Step 2: Тесты `spec/addon_profilepage_spec.lua`.**

```lua
local G = require("game_mock")
local P = require("panel_mock")
local profilepage = require("profilepage")

local function host()
  local h = { names = { "Default", "Raid" }, cur = "Default", act = "Default", why = "picked", rules = {}, calls = {} }
  local function log(...) h.calls[#h.calls + 1] = { ... } end
  h.list = function()
    local c = {}
    for i, n in ipairs(h.names) do c[i] = n end
    return c
  end
  h.current = function() return h.cur end
  h.active = function() return h.act, h.why end
  h.pick = function(n) log("pick", n); h.cur = n end
  h.create = function(n, copy)
    log("create", n, copy)
    if n == "" then return nil, "a name of 1 to 24 letters" end
    h.names[#h.names + 1] = n
    return n
  end
  h.delete = function(n) log("delete", n); return true end
  h.reset = function() log("reset") end
  h.rule = function(r) return h.rules[r] end
  h.setRule = function(r, n) log("rule", r, n); h.rules[r] = n end
  return h
end

describe("profiles page", function()
  before_each(function()
    G.install({})
    P.install()
  end)

  it("is a hidden page Profiles under DoubtMyRotation", function()
    local f = profilepage.new(host())
    assert.are.equal(f, DoubtMyRotationPanelProfiles)
    assert.are.equal(f, G.categories[1])
    assert.are.same({ "Profiles", "DoubtMyRotation" }, { f.name, f.parent })
    assert.is_false(f:IsShown())
    for _, w in ipairs(f.widgets) do assert.is_string(w.kind) end
    assert.are.equal("edit", f.controls.name.kind)
  end)

  it("shows the character's pick, the rules and what is active now", function()
    local h = host()
    h.cur, h.act, h.why, h.rules.raid = "Default", "Raid", "raid", "Raid"
    local f = profilepage.new(h)
    f.refresh(f)
    assert.are.equal("Default", f.controls.profile.ddText)
    assert.are.equal("Raid", f.controls.rule_raid.ddText)
    assert.are.equal("(no change)", f.controls.rule_party.ddText)
    assert.are.equal("Active now: Raid (in a raid)", f.status.text)
  end)

  it("a profile picked from the list goes to the host; a rule may be no rule", function()
    local h = host()
    local f = profilepage.new(h)
    local items = G.menu(f.controls.profile)
    assert.are.same({ "Default", "Raid" }, { items[1].text, items[2].text })
    items[2].func()
    local rule = G.menu(f.controls.rule_party)
    assert.are.equal("(no change)", rule[1].text)
    rule[3].func()
    rule[1].func()
    assert.are.same({ { "pick", "Raid" }, { "rule", "party", "Raid" }, { "rule", "party", nil } }, h.calls)
    assert.are.equal("Raid", f.controls.profile.ddText)
  end)

  it("New takes the name, Copy current copies; a bad name says why", function()
    local h = host()
    local f = profilepage.new(h)
    f.controls.name:SetText("Leveling")
    f.controls.new:Click()
    assert.are.equal("", f.controls.name:GetText())
    f.controls.name:SetText("Raid2")
    f.controls.copy:Click()
    f.controls.name:SetText("")
    f.controls.new:Click()
    assert.are.same({ { "create", "Leveling", false }, { "create", "Raid2", true }, { "create", "", false } }, h.calls)
    assert.are.equal("a name of 1 to 24 letters", f.status.text)
  end)

  it("Delete asks for a second click; Default is never deleted", function()
    local h = host()
    local f = profilepage.new(h)
    f.controls.delete:Click()
    assert.are.equal("Default stays", f.status.text)
    h.cur = "Raid"
    f.controls.delete:Click()
    assert.are.equal("Click again: delete Raid", f.controls.delete.text)
    assert.are.same({}, h.calls)
    f.controls.delete:Click()
    assert.are.same({ { "delete", "Raid" } }, h.calls)
    assert.are.equal("Delete", f.controls.delete.text)
    f.controls.reset:Click()
    assert.are.same({ "reset" }, h.calls[2])
  end)
end)
```

- [ ] **Step 3: Красный прогон.** `docker compose run --rm test busted spec/addon_profiles_spec.lua spec/addon_profilepage_spec.lua` — падают: `module 'profiles' not found`, `module 'profilepage' not found`.

- [ ] **Step 4: Реализация `addon/profiles.lua`.**

```lua
-- Profiles: whole sets of settings shared by the account's characters (DoubtMyRotationDB.profiles),
-- picked per character (DoubtMyRotationCharDB) by hand or by where the character is. Pure functions
-- over the two saved tables; the client's calls stay in addon/core.lua.
local settings = require("settings")

local M = {}
M.DEFAULT = "Default"
M.MAX_LEVEL = 80
M.NAME_MAX = 24
-- the addon's own look and chat, not the rotation: one value for the whole account
M.ACCOUNT = { updateCheck = true, minimap = true, levelCards = true, elvui = true }
-- the auto rules, the first that matches wins; in the open world the profile picked by hand
M.RULES = { "pvp", "raid", "party", "leveling" }
M.RULE_NAMES = { pvp = "Battleground or arena", raid = "In a raid", party = "In a dungeon",
                 leveling = "While leveling (below 80)" }
-- IsInInstance()'s second value -> rule
local WHERE = { pvp = "pvp", arena = "pvp", raid = "raid", party = "party" }

local function copy(t)
  local c = {}
  for k, v in pairs(t or {}) do c[k] = v end
  return c
end

-- Before profiles there was one account-wide config, place and hidden flag. The config becomes
-- the Default profile (a copy: db.config stays, an older version still finds its settings), the
-- place and the flag each character's own on its first login.
function M.migrate(db, char)
  local old = type(db.config) == "table" and db.config or nil
  if type(db.profiles) ~= "table" then db.profiles = { [M.DEFAULT] = copy(old) } end
  if type(db.profiles[M.DEFAULT]) ~= "table" then db.profiles[M.DEFAULT] = {} end
  if type(db.ui) ~= "table" then
    db.ui = {}
    for k in pairs(M.ACCOUNT) do
      if old and old[k] ~= nil then db.ui[k] = old[k] end
    end
  end
  if type(char.profile) ~= "string" or type(db.profiles[char.profile]) ~= "table" then char.profile = M.DEFAULT end
  if type(char.auto) ~= "table" then char.auto = {} end
  -- a profile deleted on another character: this one's rules for it go too
  for rule, name in pairs(char.auto) do
    if type(db.profiles[name]) ~= "table" then char.auto[rule] = nil end
  end
  if char.point == nil and type(db.point) == "table" then char.point = copy(db.point) end
  if char.hidden == nil then char.hidden = db.hidden == true end
  return db, char
end

function M.names(db)
  local list = {}
  for name in pairs(db.profiles) do
    if name ~= M.DEFAULT then list[#list + 1] = name end
  end
  table.sort(list)
  table.insert(list, 1, M.DEFAULT)
  return list
end

-- where: IsInInstance()'s second value ("none", "pvp", "arena", "party", "raid"); level: the player's
function M.pick(db, char, where, level)
  local auto = char.auto or {}
  local rule = WHERE[where or "none"]
  if rule and auto[rule] and db.profiles[auto[rule]] then return auto[rule], rule end
  if (level or M.MAX_LEVEL) < M.MAX_LEVEL and auto.leveling and db.profiles[auto.leveling] then
    return auto.leveling, "leveling"
  end
  return char.profile, "picked"
end

-- what the engine and the window see: the profile's values, the account's for M.ACCOUNT keys,
-- each checked against its option
function M.view(options, db, name)
  local p, ui, c = db.profiles[name] or {}, db.ui or {}, {}
  for _, o in ipairs(options) do
    if M.ACCOUNT[o.key] then c[o.key] = ui[o.key] else c[o.key] = p[o.key] end
  end
  return settings.merge(options, c)
end

-- and back, each value to where it lives
function M.store(options, db, name, config)
  local p = db.profiles[name]
  if not p then return end
  db.ui = db.ui or {}
  for _, o in ipairs(options) do
    if M.ACCOUNT[o.key] then db.ui[o.key] = config[o.key] else p[o.key] = config[o.key] end
  end
end

local function clean(name)
  if type(name) ~= "string" then return nil end
  name = name:match("^%s*(.-)%s*$")
  if name == "" or #name > M.NAME_MAX then return nil end
  return name
end

-- from: the values to copy (the current profile's), or nil for the defaults
function M.create(db, name, from)
  local n = clean(name)
  if not n then return nil, ("a name of 1 to %d letters"):format(M.NAME_MAX) end
  if db.profiles[n] then return nil, n .. ": there is one already" end
  db.profiles[n] = copy(from)
  return n
end

function M.delete(db, char, name)
  if name == M.DEFAULT then return nil, "Default stays" end
  if type(db.profiles[name]) ~= "table" then return nil, tostring(name) .. ": no such profile" end
  db.profiles[name] = nil
  if char.profile == name then char.profile = M.DEFAULT end
  for rule, n in pairs(char.auto or {}) do
    if n == name then char.auto[rule] = nil end
  end
  return true
end

function M.reset(db, name)
  if db.profiles[name] then db.profiles[name] = {} end
end

return M
```

- [ ] **Step 5: Реализация `addon/profilepage.lua`.**

```lua
-- The Profiles page under DoubtMyRotation in Interface - AddOns: this character's profile, the
-- auto rules, new / copy / delete / reset. Every change goes to the host at once: no Okay /
-- Cancel here, a profile is not a value to take back.
local profiles = require("profiles")

local M = {}
M.NAME = "DoubtMyRotationPanelProfiles"
M.TITLE = "Profiles"
M.PARENT = "DoubtMyRotation"
M.NONE = "(no change)"
M.LEFT, M.TOP, M.ROW = 16, -64, 46
M.WHY = { picked = "picked above", pvp = "battleground or arena", raid = "in a raid", party = "in a dungeon",
          leveling = "leveling" }

local function button(f, key, text, x, y, width, onClick)
  local b = CreateFrame("Button", M.NAME .. "_" .. key, f, "UIPanelButtonTemplate")
  b.kind = "button"
  b:SetWidth(width)
  b:SetHeight(22)
  b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- a list of the profile names; with none, its first entry is "(no change)" (no rule)
local function picker(f, key, label, y, get, set, none)
  local d = CreateFrame("Frame", M.NAME .. "_" .. key, f, "UIDropDownMenuTemplate")
  d.kind = "select"
  d:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT, y)
  d.label = d:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  d.label:SetPoint("BOTTOMLEFT", d, "TOPLEFT", 16, 3)
  d.label:SetText(label)
  UIDropDownMenu_SetWidth(d, 160)
  UIDropDownMenu_Initialize(d, function()
    local names = f.host.list()
    if none then table.insert(names, 1, false) end
    local current = get()
    for _, name in ipairs(names) do
      local info = UIDropDownMenu_CreateInfo()
      info.text, info.value = name or M.NONE, name or M.NONE
      info.checked = (name or nil) == current
      info.func = function()
        f.armed, f.message = nil, nil
        set(name or nil)
        f.refresh(f)
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  d.show = function(self, name)
    UIDropDownMenu_SetSelectedValue(self, name or M.NONE)
    UIDropDownMenu_SetText(self, name or M.NONE)
  end
  return d
end

function M.new(host)
  local f = CreateFrame("Frame", M.NAME, UIParent)
  -- Interface Options shows the page when it is picked; until then it must not sit on screen
  f:Hide()
  f.name, f.parent, f.host = M.TITLE, M.PARENT, host
  f.controls, f.widgets = {}, {}
  local function add(key, w)
    f.controls[key], f.widgets[#f.widgets + 1] = w, w
    return w
  end
  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT, -16)
  title:SetText(M.PARENT .. " - " .. M.TITLE)
  f.status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.status:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT, -38)
  local y = M.TOP
  add("profile", picker(f, "profile", "This character's profile", y, host.current, host.pick))
  y = y - M.ROW
  local edit = CreateFrame("EditBox", M.NAME .. "_name", f, "InputBoxTemplate")
  edit.kind = "edit"
  edit:SetWidth(160)
  edit:SetHeight(20)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(profiles.NAME_MAX)
  edit:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT + 22, y)
  add("name", edit)
  local function create(copyCurrent)
    f.armed = nil
    local ok, err = host.create(edit:GetText() or "", copyCurrent)
    f.message = (not ok) and err or nil
    if ok then
      edit:SetText("")
      edit:ClearFocus()
    end
    f.refresh(f)
  end
  add("new", button(f, "new", "New", M.LEFT + 200, y, 100, function() create(false) end))
  add("copy", button(f, "copy", "Copy current", M.LEFT + 310, y, 120, function() create(true) end))
  y = y - 32
  add("delete", button(f, "delete", "Delete", M.LEFT + 22, y, 170, function()
    local cur = host.current()
    f.message = nil
    if cur == profiles.DEFAULT then
      f.armed, f.message = nil, "Default stays"
    elseif f.armed ~= cur then
      f.armed = cur -- a slip of the mouse must not lose a profile: the second click deletes
    else
      f.armed = nil
      local ok, err = host.delete(cur)
      if not ok then f.message = err end
    end
    f.refresh(f)
  end))
  add("reset", button(f, "reset", "Reset active profile", M.LEFT + 200, y, 170, function()
    f.armed, f.message = nil, nil
    host.reset()
    f.refresh(f)
  end))
  y = y - 48
  local head = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  head:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT, y)
  head:SetText("Switch automatically (out of combat)")
  y = y - 34
  for i, rule in ipairs(profiles.RULES) do
    add("rule_" .. rule, picker(f, "rule_" .. rule, profiles.RULE_NAMES[rule], y - (i - 1) * M.ROW,
      function() return host.rule(rule) end, function(name) host.setRule(rule, name) end, true))
  end
  f.refresh = function()
    local cur = host.current()
    f.controls.profile:show(cur)
    for _, rule in ipairs(profiles.RULES) do f.controls["rule_" .. rule]:show(host.rule(rule)) end
    local active, why = host.active()
    f.status:SetText(f.message or ("Active now: %s (%s)"):format(active, M.WHY[why] or tostring(why)))
    f.controls.delete:SetText(f.armed == cur and ("Click again: delete " .. cur) or "Delete")
  end
  InterfaceOptions_AddCategory(f)
  return f
end

return M
```

- [ ] **Step 6: Зелёный прогон.** `docker compose run --rm test busted spec/addon_profiles_spec.lua spec/addon_profilepage_spec.lua`, затем `docker compose run --rm test busted --exclude-tags=perf`.

- [ ] **Step 7: Коммит.** `Аддон: профили настроек на аккаунт с выбором на персонажа и страница Profiles`.

### Task 4: Карточки «что нового на уровне» — `addon/cards.lua`

**Files:**
- Create: `addon/cards.lua`
- Test: `spec/addon_cards_spec.lua`

**Interfaces:**
- Produces:
  - `cards.CARDS` — 8 карточек `{ level, title, text }` на 10, 20, …, 80, по возрастанию; `text` — английский, с подстановками `{поле:ключ}`;
  - `cards.FIELDS` — подстановки: `lvl` (уровень, с которого есть заклинание или талант), `cd` (кулдаун старшего ранга из `spells_data`), `dur` (`spells.byKey[key].duration`), `charges`, `bonus`, `targets` (`maxTargets`) из `spells.byKey`; `cd` и `dur` — `"N s"` или `"N min"`;
  - `cards.HAND_LEVELS` — уровни у тренера для названий вне `spells.CATALOG`, которые встречаются в текстах: `["Flametongue Weapon"] = 10, ["Water Shield"] = 20, ["Windfury Weapon"] = 30, ["Bloodlust"] = 70, ["Heroism"] = 70`;
  - `cards.text(s) -> string` — подстановки; неизвестное поле или ключ — ошибка Lua (тест не даст ей дойти до игры);
  - `cards.talentLevel(key) -> level | nil` — первый уровень, на котором `talents.standard(level)[key] > 0`;
  - `cards.learned(key) -> level | nil` — для заклинаний-талантов (`stormstrike`, `lavaLash`, `shamanisticRage`, `feralSpirit`) — `talentLevel`, иначе уровень первого ранга в `spells_data`;
  - `cards.newSince(from, to) -> { { key, name, icon, level } }` — заклинания каталога с `from < learned ≤ to`, по уровню, потом по имени;
  - `cards.previous(level) -> number` — уровень предыдущей карточки или 0;
  - `cards.due(level, seen) -> card | nil` — самая старшая невиденная карточка с `card.level ≤ level`; младшие невиденные помечает виденными (`seen[l] = true`) — показывается одна; саму возвращённую не помечает;
  - `cards.firstRun(level, seen)` — помечает виденными все карточки `≤ level`;
  - `cards.window(host) -> w` — одно окно `DoubtMyRotationCard` на сессию (`w.kind = "window"`, `w.widgets`), `w:open(card, close)`, `w:hide()` (спрятать без `close` — бой), закрытие кнопкой «OK» или Escape зовёт `close()` один раз; галочка «Show a card at the next levels» → `host.set("levelCards", bool)`. Хост: `{ config() -> config, set(key, value) }`.
- Consumes: `src/spells_data.lua`, `src/spells.lua`, `src/talents.lua` (в сборке аддона они уже есть — `__require`).

- [ ] **Step 1: Тесты `spec/addon_cards_spec.lua`.**

```lua
local G = require("game_mock")
local P = require("panel_mock")
local cards = require("cards")
local spells = require("spells")
local talents = require("talents")

local function levels()
  local out = {}
  for i, c in ipairs(cards.CARDS) do out[i] = c.level end
  return out
end

describe("level cards", function()
  it("eight cards, at 10 to 80", function()
    assert.are.same({ 10, 20, 30, 40, 50, 60, 70, 80 }, levels())
    for _, c in ipairs(cards.CARDS) do
      assert.is_string(c.title)
      assert.is_string(c.text)
    end
  end)

  -- talents come on the standard leveling path (src/talents.lua M.STANDARD), not at the spell's rank level
  it("the levels and numbers in the text come from the spell and talent data", function()
    assert.are.equal("40", cards.text("{lvl:stormstrike}"))
    assert.are.equal("45", cards.text("{lvl:lavaLash}"))
    assert.are.equal("50", cards.text("{lvl:shamanisticRage}"))
    assert.are.equal("60", cards.text("{lvl:feralSpirit}"))
    assert.are.equal("55", cards.text("{lvl:maelstromWeapon}"))
    assert.are.equal("41", cards.text("{lvl:dualWield}"))
    assert.are.equal("68", cards.text("{lvl:fireElemental}"))
    assert.are.equal("3 min", cards.text("{cd:feralSpirit}"))
    assert.are.equal("10 min", cards.text("{cd:fireElemental}"))
    assert.are.equal("1 min", cards.text("{cd:shamanisticRage}"))
    assert.are.equal("6 s", cards.text("{cd:earthShock}"))
    assert.are.equal("18 s", cards.text("{dur:flameShock}"))
    assert.are.equal("2 min", cards.text("{dur:fireElemental}"))
    assert.are.equal("4", cards.text("{charges:stormstrike}"))
    assert.are.equal("20", cards.text("{bonus:stormstrike}"))
    assert.are.equal("3", cards.text("{targets:chainLightning}"))
    assert.has_error(function() cards.text("{cd:noSuchSpell}") end)
    assert.has_error(function() cards.text("{what:stormstrike}") end)
  end)

  it("every card's text resolves", function()
    for _, c in ipairs(cards.CARDS) do
      local t = cards.text(c.text)
      assert.is_nil(t:find("{", 1, true), c.level)
    end
  end)

  -- no invented facts: a card names a spell or a talent only once the player can have it
  it("no spell or talent in a card before its level", function()
    for _, c in ipairs(cards.CARDS) do
      local t = cards.text(c.title .. " " .. c.text)
      for _, s in ipairs(spells.CATALOG) do
        if t:find(s.name, 1, true) then
          assert.is_true(cards.learned(s.key) <= c.level, ("%s on the level %d card"):format(s.name, c.level))
        end
      end
      for _, k in ipairs(talents.KEYS) do
        if t:find(k.name, 1, true) then
          local l = cards.talentLevel(k.key)
          assert.is_true(l ~= nil and l <= c.level, ("%s on the level %d card"):format(k.name, c.level))
        end
      end
      for name, l in pairs(cards.HAND_LEVELS) do
        if t:find(name, 1, true) then assert.is_true(l <= c.level, ("%s on the level %d card"):format(name, c.level)) end
      end
    end
  end)

  it("what is new since the previous card, every spell on exactly one card", function()
    local function keys(list)
      local out = {}
      for i, s in ipairs(list) do out[i] = s.key end
      return out
    end
    assert.are.same({ "lightningBolt", "earthShock", "lightningShield", "flameShock", "searingTotem" }, keys(cards.newSince(0, 10)))
    assert.are.same({ "lavaLash", "shamanisticRage" }, keys(cards.newSince(40, 50)))
    assert.are.same({ "feralSpirit" }, keys(cards.newSince(50, 60)))
    assert.are.equal(0, cards.previous(10))
    assert.are.equal(40, cards.previous(50))
    local count = 0
    for _, c in ipairs(cards.CARDS) do count = count + #cards.newSince(cards.previous(c.level), c.level) end
    assert.are.equal(#spells.CATALOG, count)
  end)

  it("one card at a time: the newest unseen, older ones count as seen", function()
    local seen = {}
    assert.is_nil(cards.due(9, seen))
    assert.are.equal(10, cards.due(10, seen).level)
    assert.is_nil(seen[10]) -- marked when the player closes it
    assert.are.equal(30, cards.due(35, seen).level)
    assert.is_true(seen[10])
    assert.is_true(seen[20])
    assert.is_nil(seen[30])
    seen[30] = true
    assert.is_nil(cards.due(39, seen))
    local grown = {}
    cards.firstRun(45, grown)
    assert.are.same({ [10] = true, [20] = true, [30] = true, [40] = true }, grown)
    assert.are.equal(50, cards.due(50, grown).level)
  end)
end)

describe("level card window", function()
  local h
  before_each(function()
    G.install({})
    P.install()
    cards.frame = nil
    h = { cfg = { levelCards = true }, sets = {} }
    h.config = function() return h.cfg end
    h.set = function(k, v) h.sets[#h.sets + 1] = { k, v } end
  end)

  it("shows the card with the new spells; OK closes it once", function()
    local w = cards.window(h)
    assert.are.equal(w, DoubtMyRotationCard)
    assert.are.equal(w, cards.window(h))
    local closed = 0
    w:open(cards.CARDS[5], function() closed = closed + 1 end)
    assert.is_true(w:IsShown())
    assert.are.equal(cards.CARDS[5].title, w.title.text)
    assert.are.equal(cards.text(cards.CARDS[5].text), w.text.text)
    assert.are.equal("New since level 40: Lava Lash, Shamanistic Rage", w.names.text)
    assert.are.equal(spells.byKey.lavaLash.icon, w.icons[1].texture)
    assert.is_true(w.icons[2].shown)
    assert.is_false(w.icons[3].shown)
    w.ok:Click()
    assert.is_false(w:IsShown())
    assert.are.equal(1, closed)
    for _, x in ipairs(w.widgets) do assert.is_string(x.kind) end
  end)

  it("the check box turns the cards off; a fight hides it without closing; Escape closes", function()
    local w = cards.window(h)
    local closed = 0
    w:open(cards.CARDS[1], function() closed = closed + 1 end)
    assert.is_true(w.again:GetChecked() == 1)
    w.again:SetChecked(false)
    w.again:Click()
    assert.are.same({ { "levelCards", false } }, h.sets)
    w:hide()
    assert.are.equal(0, closed)
    w:open(cards.CARDS[1], function() closed = closed + 1 end)
    w:Hide() -- Escape (UISpecialFrames)
    assert.are.equal(1, closed)
    assert.are.equal("DoubtMyRotationCard", UISpecialFrames[1])
  end)
end)
```

- [ ] **Step 2: Красный прогон.** `docker compose run --rm test busted spec/addon_cards_spec.lua` — `module 'cards' not found`.

- [ ] **Step 3: Реализация `addon/cards.lua`.**

```lua
-- "What's new" cards: at levels 10, 20 ... 80 a short window, once per character - what the level
-- brought and how the rotation changes. The words are written by hand for 3.3.5a; which spells are
-- new and every number in the text (levels, cooldowns, durations) come from the spell data.
local data = require("spells_data")
local spells = require("spells")
local talents = require("talents")

local M = {}
M.NAME = "DoubtMyRotationCard"
M.WIDTH, M.HEIGHT = 400, 260
M.ICONS = 6
-- catalog spells that are talents: learned on the standard leveling path, not at their rank's level
M.TALENT_SPELLS = { stormstrike = true, lavaLash = true, shamanisticRage = true, feralSpirit = true }
-- names in the texts that are neither in spells.CATALOG nor talents: their trainer level (3.3.5a)
M.HAND_LEVELS = { ["Flametongue Weapon"] = 10, ["Water Shield"] = 20, ["Windfury Weapon"] = 30,
                  ["Bloodlust"] = 70, ["Heroism"] = 70 }

M.CARDS = {
  { level = 10, title = "Level 10: Flame Shock and totems",
    text = "Flame Shock burns the target for {dur:flameShock}; it shares one {cd:flameShock} cooldown with Earth Shock. "
      .. "Searing Totem shoots your target for {dur:searingTotem}. Put Flametongue Weapon on your weapon. "
      .. "From now on every level brings a talent point: Enhancement is the tree this addon plays." },
  { level = 20, title = "Level 20: Frost Shock and Water Shield",
    text = "Frost Shock slows the target and shares the shock cooldown: use it on a runner, the timeline picks the shock for damage. "
      .. "Water Shield gives mana back instead of damage: put it on when mana runs low, with the Shield option on auto the addon follows the shield you wear. "
      .. "Fire Nova (since level {lvl:fireNova}) needs a fire totem down and hits everything around the totem." },
  { level = 30, title = "Level 30: Windfury Weapon and the totem bar",
    text = "Put Windfury Weapon on your main hand. Call of the Elements drops up to four totems with one press: "
      .. "set them in the totem bar that comes with it. Magma Totem (since level {lvl:magmaTotem}) burns everything near it "
      .. "for {dur:magmaTotem}: with Fire Nova it is your answer to a pack." },
  { level = 40, title = "Level 40: Stormstrike",
    text = "Stormstrike (your talent at level {lvl:stormstrike}) hits with both weapons, and your next {charges:stormstrike} Nature hits "
      .. "on the target deal {bonus:stormstrike}% more: an Earth Shock or a Lightning Bolt right after it hits harder. "
      .. "Press it whenever it is ready ({cd:stormstrike} cooldown). Chain Lightning (since level {lvl:chainLightning}) hits up to "
      .. "{targets:chainLightning} enemies." },
  { level = 50, title = "Level 50: two weapons, Lava Lash, Shamanistic Rage",
    text = "Since level {lvl:dualWield} the Dual Wield talent gives you an off-hand weapon: Flametongue Weapon goes on it, Windfury Weapon "
      .. "stays on the main hand. Lava Lash (since level {lvl:lavaLash}) strikes with the off-hand weapon, harder with Flametongue on it. "
      .. "Shamanistic Rage: {dur:shamanisticRage} of less damage taken and mana back from your melee hits, every {cd:shamanisticRage} - "
      .. "your mana tool. The Combat settings say when the timeline offers it." },
  { level = 60, title = "Level 60: Maelstrom Weapon and Feral Spirit",
    text = "Maelstrom Weapon (talent, from level {lvl:maelstromWeapon}): melee hits stack it up to 5 times, each stack cuts the cast time "
      .. "of your next Lightning Bolt or Chain Lightning by 20%. At 5 stacks the cast is instant: the dots on the timeline count them. "
      .. "Feral Spirit calls two wolves for {dur:feralSpirit}, every {cd:feralSpirit}: for a boss or a long fight." },
  { level = 70, title = "Level 70: Fire Elemental and Bloodlust",
    text = "Fire Elemental Totem (since level {lvl:fireElemental}) burns for {dur:fireElemental}, every {cd:fireElemental}: "
      .. "drop it early on a boss. Bloodlust (Heroism on the Alliance) hastes your whole group and lands on a player once in 10 min: "
      .. "the raid leader calls it. The addon can show when it is ready (General: Show Bloodlust ready in group)." },
  { level = 80, title = "Level 80: the full rotation",
    text = "Visit the trainer for your last ranks. Roughly, by priority: Lightning Bolt at 5 Maelstrom stacks, Stormstrike, "
      .. "Flame Shock when it is not on the target, Earth Shock, Lava Lash, Fire Nova with a fire totem down, Lightning Shield "
      .. "when its charges run out. The timeline weighs these every moment for your gear and the fight: follow the big icon." },
}

function M.talentLevel(key)
  for level = 10, 80 do
    if (talents.standard(level)[key] or 0) > 0 then return level end
  end
  return nil
end

function M.learned(key)
  if M.TALENT_SPELLS[key] then return M.talentLevel(key) end
  local r = data[key] and data[key][1]
  return r and r.level
end

local function span(sec)
  if sec >= 60 and sec % 60 == 0 then return ("%d min"):format(sec / 60) end
  return ("%d s"):format(sec)
end

M.FIELDS = {
  lvl = function(key) return M.learned(key) or M.talentLevel(key) end,
  cd = function(key)
    local r = data[key]
    return r and span(r[#r].cdMs / 1000)
  end,
  dur = function(key)
    local s = spells.byKey[key]
    return s and s.duration and span(s.duration)
  end,
  charges = function(key) return spells.byKey[key] and spells.byKey[key].charges end,
  bonus = function(key) return spells.byKey[key] and spells.byKey[key].bonus end,
  targets = function(key) return spells.byKey[key] and spells.byKey[key].maxTargets end,
}

function M.text(s)
  return (s:gsub("{(%a+):(%a+)}", function(field, key)
    local f = M.FIELDS[field]
    local v = f and f(key)
    if v == nil then error(("cards: no %s for %s"):format(field, key)) end
    return tostring(v)
  end))
end

function M.newSince(from, to)
  local out = {}
  for _, s in ipairs(spells.CATALOG) do
    local l = M.learned(s.key)
    if l and l > from and l <= to then out[#out + 1] = { key = s.key, name = s.name, icon = s.icon, level = l } end
  end
  table.sort(out, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return a.name < b.name
  end)
  return out
end

function M.previous(level)
  local prev = 0
  for _, c in ipairs(M.CARDS) do
    if c.level < level then prev = c.level end
  end
  return prev
end

-- one card at a time: levels skipped past (the option was off) are old news
function M.due(level, seen)
  local card
  for _, c in ipairs(M.CARDS) do
    if c.level <= level and not seen[c.level] then
      if card then seen[card.level] = true end
      card = c
    end
  end
  return card
end

-- the addon put on a grown character: the cards behind it are old news
function M.firstRun(level, seen)
  for _, c in ipairs(M.CARDS) do
    if c.level <= level then seen[c.level] = true end
  end
end

local BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                   edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                   tile = true, tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } }

local W = {}

function W:open(card, close)
  self.close = close
  self.title:SetText(card.title)
  self.text:SetText(M.text(card.text))
  local prev = M.previous(card.level)
  local new = M.newSince(prev, card.level)
  local names = {}
  for i, s in ipairs(new) do names[i] = s.name end
  self.names:SetText(((prev > 0 and "New since level %d: " or "Your spells so far: "):format(prev)) .. table.concat(names, ", "))
  for i, ic in ipairs(self.icons) do
    if new[i] then
      ic:SetTexture(new[i].icon)
      ic:Show()
    else
      ic:Hide()
    end
  end
  self.again:SetChecked(self.host.config().levelCards ~= false)
  self:Show()
end

-- a fight began (addon/guide.lua): away without closing, the queue shows it again after
function W:hide()
  self.close = nil
  self:Hide()
end

function W:finish()
  local close = self.close
  self.close = nil
  self:Hide()
  if close then close() end
end

function M.window(host)
  local w = M.frame
  if w then
    w.host = host
    return w
  end
  w = CreateFrame("Frame", M.NAME, UIParent)
  w.kind, w.widgets, w.host = "window", {}, host
  w:SetWidth(M.WIDTH)
  w:SetHeight(M.HEIGHT)
  w:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  w:SetFrameStrata("DIALOG")
  w:SetBackdrop(BACKDROP)
  w:SetMovable(true)
  w:EnableMouse(true)
  w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", function(self) self:StartMoving() end)
  w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  w.title:SetPoint("TOP", w, "TOP", 0, -16)
  w.text = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  w.text:SetPoint("TOPLEFT", w, "TOPLEFT", 20, -44)
  w.text:SetWidth(M.WIDTH - 40)
  w.text:SetJustifyH("LEFT")
  w.icons = {}
  for i = 1, M.ICONS do
    local ic = w:CreateTexture(nil, "ARTWORK")
    ic:SetWidth(28)
    ic:SetHeight(28)
    ic:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 20 + (i - 1) * 32, 76)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ic:Hide()
    w.icons[i] = ic
  end
  w.names = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  w.names:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 20, 62)
  w.names:SetWidth(M.WIDTH - 40)
  w.names:SetJustifyH("LEFT")
  local again = CreateFrame("CheckButton", M.NAME .. "Again", w, "InterfaceOptionsCheckButtonTemplate")
  again.kind = "toggle"
  again:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 16, 14)
  _G[again:GetName() .. "Text"]:SetText("Show a card at the next levels")
  -- OnClick comes after the box has flipped; GetChecked gives 1 or nil
  again:SetScript("OnClick", function(self) w.host.set("levelCards", self:GetChecked() and true or false) end)
  w.again = again
  local ok = CreateFrame("Button", M.NAME .. "OK", w, "UIPanelButtonTemplate")
  ok.kind = "button"
  ok:SetWidth(96)
  ok:SetHeight(22)
  ok:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -16, 16)
  ok:SetText("OK")
  ok:SetScript("OnClick", function() w:finish() end)
  w.ok = ok
  w.widgets = { again, ok }
  for k, fn in pairs(W) do w[k] = fn end
  -- Escape closes it like OK (the client hides the frames listed in UISpecialFrames)
  w:SetScript("OnHide", function(self) if self.close then self:finish() end end)
  if UISpecialFrames then table.insert(UISpecialFrames, M.NAME) end
  w:Hide()
  M.frame = w
  return w
end

return M
```

- [ ] **Step 4: Зелёный прогон.** `docker compose run --rm test busted spec/addon_cards_spec.lua`, затем `docker compose run --rm test busted --exclude-tags=perf`. Если тест «no spell or talent in a card before its level» падает — менять текст карточки, а не уровни: данные `spells_data` / `talents.STANDARD` первичны.

- [ ] **Step 5: Коммит.** `Аддон: карточки «что нового» на 10–80 уровнях с числами из данных заклинаний`.

### Task 5: Очередь сообщений, мастер, расписание — `addon/guide.lua`, `addon/wizard.lua`, `addon/coach.lua`

**Files:**
- Create: `addon/guide.lua` (очередь: одно окно за раз, вне боя)
- Create: `addon/wizard.lua` (окно мастера первого запуска)
- Create: `addon/coach.lua` (когда что показывать: мастер на входе, карточка на новом уровне)
- Test: `spec/addon_guide_spec.lua`, `spec/addon_wizard_spec.lua`, `spec/addon_coach_spec.lua`

**Interfaces:**
- Produces:
  - `guide.new(deps) -> q`, `deps.fighting() -> bool` (по умолчанию `InCombatLockdown()` или `UnitAffectingCombat("player")`); `q:push(item) -> bool` (`item = { id, show(close), hide() }`; тот же `id` в очереди или открыт — `false`); `q:pump()`; `q:combat()` (спрятать открытое через `item.hide()`, поставить первым); `q:start(frame)` — `PLAYER_REGEN_DISABLED` → `combat`, `PLAYER_REGEN_ENABLED` → `pump`; `q.current`, `q.items`.
  - `wizard.PAGES` (4 страницы `{ title, text, move?, compact?, checklist? }`), `wizard.new(host) -> w` — рамка `DoubtMyRotationWizard` (`w.kind = "window"`, `w.widgets`), `w:open(close)` (страница, на которой его спрятал бой, или первая), `w:page(n)`, `w:hide()` (бой: спрятать без `close`, ленту закрепить, страница остаётся), «Done» → `host.done()`, «Don't show again» → `host.never()`, «Skip» и Escape → только `close()`; `close()` — ровно один раз. Хост: `{ config(), set(key, value), unlocked() -> bool, move(on), checklist() -> { { ok, text } } | nil (необязательно), openChecklist() (необязательно), done(), never() }`.
  - `coach.new(deps) -> c`, `deps = { guide, db, char, level() -> number, enabled(key) -> bool, wizard() -> w, card() -> window }`; `c:login()` — первый раз на персонаже (`char.cards == nil`) все карточки ≤ уровня — виденные; мастер в очередь, если нет `db.wizardOff` и `char.wizard ~= "done"`; `c:levelUp(level)` — опция `levelCards` включена → `cards.due` → карточка в очередь, закрыта → `char.cards[level] = true`; выключена → `cards.firstRun(level, char.cards)`; `c:openGuide()` — мастер в очередь всегда; `c:start(frame)` — `PLAYER_LEVEL_UP` с уровнем из аргумента события.
- Consumes: `cards.due`, `cards.firstRun` (задача 4; в `spec/addon_coach_spec.lua` — подмена через `package.loaded.cards`), окно карточки `{ open(card, close), hide() }` (задача 4), окно мастера (эта задача).

- [ ] **Step 1: Тесты `spec/addon_guide_spec.lua`.**

```lua
local G = require("game_mock")
local guide = require("guide")

local function item(id, log)
  return { id = id,
           show = function(close) log[#log + 1] = "show " .. id; log[id] = close end,
           hide = function() log[#log + 1] = "hide " .. id end }
end

describe("message queue", function()
  local fighting, q, log
  before_each(function()
    fighting, log = false, {}
    q = guide.new({ fighting = function() return fighting end })
  end)

  it("one window at a time, in order", function()
    assert.is_true(q:push(item("wizard", log)))
    assert.is_true(q:push(item("card10", log)))
    assert.are.same({ "show wizard" }, { log[1], log[2] })
    log.wizard()
    assert.are.equal("show card10", log[2])
    log.card10()
    assert.is_nil(q.current)
  end)

  it("nothing opens in a fight; a fight hides the open one and brings it back after", function()
    fighting = true
    q:push(item("wizard", log))
    assert.are.equal(0, #log)
    fighting = false
    q:pump()
    assert.are.equal("show wizard", log[1])
    fighting = true
    q:combat()
    assert.are.equal("hide wizard", log[2])
    q:pump()
    assert.are.equal(2, #log)
    fighting = false
    q:pump()
    assert.are.equal("show wizard", log[3])
  end)

  it("the same message is not queued twice", function()
    q:push(item("card20", log))
    assert.is_false(q:push(item("card20", log)))
    q:push(item("wizard", log))
    assert.is_false(q:push(item("wizard", log)))
    assert.are.equal(1, #q.items)
  end)

  it("follows the fight events of its frame; by default the client says who fights", function()
    G.install({ inCombat = false, lockdown = true })
    local real = guide.new()
    local f = CreateFrame("Frame")
    real:start(f)
    assert.is_true(f.events.PLAYER_REGEN_DISABLED)
    assert.is_true(f.events.PLAYER_REGEN_ENABLED)
    real:push(item("wizard", log))
    assert.are.equal(0, #log)
    G.cfg.lockdown = false
    f.scripts.OnEvent(f, "PLAYER_REGEN_ENABLED")
    assert.are.equal("show wizard", log[1])
    f.scripts.OnEvent(f, "PLAYER_REGEN_DISABLED")
    assert.are.equal("hide wizard", log[2])
  end)
end)
```

- [ ] **Step 2: Тесты `spec/addon_wizard_spec.lua`.**

```lua
local G = require("game_mock")
local P = require("panel_mock")
local wizard = require("wizard")

local function host(extra)
  local h = { cfg = { compact = false }, sets = {}, moves = {}, isUnlocked = false, dones = 0, nevers = 0 }
  h.config = function() return h.cfg end
  h.set = function(k, v) h.sets[#h.sets + 1] = { k, v }; h.cfg[k] = v end
  h.unlocked = function() return h.isUnlocked end
  h.move = function(on) h.moves[#h.moves + 1] = on; h.isUnlocked = on end
  h.done = function() h.dones = h.dones + 1 end
  h.never = function() h.nevers = h.nevers + 1 end
  for k, v in pairs(extra or {}) do h[k] = v end
  return h
end

describe("first-run guide", function()
  local closed
  local function close() closed = closed + 1 end
  before_each(function()
    G.install({})
    P.install()
    closed = 0
  end)

  it("four pages; Done on the last closes it once and tells the host", function()
    local h = host()
    local w = wizard.new(h)
    assert.are.equal(w, DoubtMyRotationWizard)
    assert.are.equal(4, #wizard.PAGES)
    w:open(close)
    assert.are.equal(wizard.PAGES[1].title, w.title.text)
    assert.are.equal("1 / 4", w.step.text)
    assert.is_false(w.back.shown)
    assert.are.equal("Next", w.next.text)
    for _ = 1, 3 do w.next:Click() end
    assert.are.equal("4 / 4", w.step.text)
    assert.are.equal("Done", w.next.text)
    w.next:Click()
    assert.is_false(w:IsShown())
    assert.are.same({ 1, 1, 0 }, { closed, h.dones, h.nevers })
    for _, x in ipairs(w.widgets) do assert.is_string(x.kind) end
    assert.are.equal("window", w.kind)
  end)

  it("page 3 unlocks the timeline to be dragged and locks it again when left", function()
    local h = host()
    local w = wizard.new(h)
    w:open(close)
    w:page(3)
    assert.are.same({ true }, h.moves)
    w.next:Click()
    assert.are.same({ true, false }, h.moves)
    w.back:Click()
    w.skip:Click()
    assert.are.same({ true, false, true, false }, h.moves)
    assert.are.same({ 1, 0 }, { closed, h.dones })
    -- unlocked by the player before: the guide leaves it as it was
    local mine = host({ isUnlocked = true })
    local w2 = wizard.new(mine)
    w2:open(close)
    w2:page(3)
    w2:page(4)
    assert.are.same({}, mine.moves)
  end)

  it("offers one button mode on page 3 only", function()
    local h = host()
    local w = wizard.new(h)
    w:open(close)
    assert.is_false(w.compact.shown)
    w:page(3)
    assert.is_true(w.compact.shown)
    w.compact:SetChecked(true)
    w.compact:Click()
    assert.are.same({ { "compact", true } }, h.sets)
  end)

  it("the last page shows the ready check when the host has one", function()
    local opened = 0
    local h = host({ checklist = function() return { { ok = true, text = "Lightning Shield" }, { ok = false, text = "Off-hand imbue" } } end,
                     openChecklist = function() opened = opened + 1 end })
    local w = wizard.new(h)
    w:open(close)
    w:page(4)
    assert.truthy(w.list.text:find("Lightning Shield", 1, true))
    assert.truthy(w.list.text:find("Off-hand imbue", 1, true))
    assert.is_true(w.check.shown)
    w.check:Click()
    assert.are.equal(1, opened)
    local plain = wizard.new(host())
    plain:open(close)
    plain:page(4)
    assert.are.equal("", plain.list.text)
    assert.is_false(plain.check.shown)
  end)

  it("Don't show again tells the host; a fight hides it on its page; Escape is Skip", function()
    local h = host()
    local w = wizard.new(h)
    w:open(close)
    w.never:Click()
    assert.are.same({ 1, 1 }, { closed, h.nevers })
    w:open(close)
    assert.are.equal("1 / 4", w.step.text)
    w:page(3)
    w:hide()
    assert.is_false(w:IsShown())
    assert.are.equal(1, closed)
    assert.are.same({ true, false }, h.moves)
    w:open(close)
    assert.are.equal("3 / 4", w.step.text)
    w:Hide() -- Escape (UISpecialFrames)
    assert.are.same({ 2, 0 }, { closed, h.dones })
    assert.are.equal("DoubtMyRotationWizard", UISpecialFrames[1])
  end)
end)
```

- [ ] **Step 3: Тесты `spec/addon_coach_spec.lua`.**

```lua
local G = require("game_mock")
-- addon/cards.lua has its own spec: here a stand-in with a card every 10 levels
package.loaded.cards = {
  firstRun = function(level, seen) for l = 10, level, 10 do seen[l] = true end end,
  due = function(level, seen)
    local l = math.floor(level / 10) * 10
    if l >= 10 and not seen[l] then return { level = l } end
  end,
}
local coach = require("coach")
local guide = require("guide")

local function setup(opts)
  opts = opts or {}
  local s = { opened = {}, cardsOn = opts.cardsOn ~= false, level = opts.level or 1 }
  s.db, s.char = opts.db or {}, opts.char or {}
  s.q = guide.new({ fighting = function() return false end })
  s.wizard = { open = function(_, close) s.opened[#s.opened + 1] = "wizard"; s.close = close end, hide = function() end }
  s.card = { open = function(_, card, close) s.opened[#s.opened + 1] = "card" .. card.level; s.close = close end,
             hide = function() end }
  s.c = coach.new({ guide = s.q, db = s.db, char = s.char, level = function() return s.level end,
                    enabled = function(key) return key ~= "levelCards" or s.cardsOn end,
                    wizard = function() return s.wizard end, card = function() return s.card end })
  return s
end

describe("guide and cards schedule", function()
  it("a new character: the guide on login, nothing behind it to catch up on", function()
    local s = setup({ level = 1 })
    s.c:login()
    assert.are.same({ "wizard" }, s.opened)
    assert.are.same({}, s.char.cards)
  end)

  it("a grown character: the cards behind it count as seen, none shows on login", function()
    local s = setup({ level = 45, char = { wizard = "done" } })
    s.c:login()
    assert.are.same({}, s.opened)
    assert.are.same({ [10] = true, [20] = true, [30] = true, [40] = true }, s.char.cards)
    s.char.cards[50] = nil
    s.c:login() -- the second login leaves the record alone
    assert.is_nil(s.char.cards[50])
  end)

  it("the guide stays away once done here, or turned off for the account", function()
    local s = setup({ char = { wizard = "done" } })
    s.c:login()
    local t = setup({ db = { wizardOff = true } })
    t.c:login()
    assert.are.same({}, s.opened)
    assert.are.same({}, t.opened)
  end)

  it("a level brings its card; closing it marks it seen", function()
    local s = setup({ level = 19, char = { wizard = "done" } })
    s.c:login()
    s.c:levelUp(20)
    assert.are.same({ "card20" }, s.opened)
    assert.is_nil(s.char.cards[20])
    s.close()
    assert.is_true(s.char.cards[20])
    s.c:levelUp(21)
    assert.are.same({ "card20" }, s.opened)
  end)

  it("cards off: the levels passed count as seen, nothing shows", function()
    local s = setup({ level = 29, cardsOn = false, char = { wizard = "done" } })
    s.c:login()
    s.c:levelUp(30)
    assert.are.same({}, s.opened)
    assert.is_true(s.char.cards[30])
  end)

  it("/dmr guide brings the guide back even when done", function()
    local s = setup({ char = { wizard = "done" } })
    s.c:login()
    s.c:openGuide()
    assert.are.same({ "wizard" }, s.opened)
  end)

  -- UnitLevel still gives the old level while PLAYER_LEVEL_UP runs
  it("takes the new level from PLAYER_LEVEL_UP itself", function()
    G.install({})
    local s = setup({ level = 9, char = { wizard = "done" } })
    s.c:login()
    local f = CreateFrame("Frame")
    s.c:start(f)
    assert.is_true(f.events.PLAYER_LEVEL_UP)
    f.scripts.OnEvent(f, "PLAYER_LEVEL_UP", 10)
    assert.are.same({ "card10" }, s.opened)
  end)
end)
```

- [ ] **Step 4: Красный прогон.** `docker compose run --rm test busted spec/addon_guide_spec.lua spec/addon_wizard_spec.lua spec/addon_coach_spec.lua` — `module 'guide' / 'wizard' / 'coach' not found`.

- [ ] **Step 5: Реализация `addon/guide.lua`.**

```lua
-- One message window at a time, never in a fight: the first-run guide and the level cards wait
-- here. Entering combat hides the open one and puts it first in line; it comes back after.
local M = {}

local Q = {}
Q.__index = Q

local function fighting()
  if InCombatLockdown() then return true end
  return UnitAffectingCombat("player") and true or false
end

function M.new(deps)
  deps = deps or {}
  return setmetatable({ items = {}, current = nil, fighting = deps.fighting or fighting }, Q)
end

local function has(q, id)
  if q.current and q.current.id == id then return true end
  for _, it in ipairs(q.items) do
    if it.id == id then return true end
  end
  return false
end

-- item = { id, show = function(close) ... end, hide = function() ... end }: show opens the window and
-- calls close() once the player is done with it; hide puts it away without close (a fight began)
function Q:push(item)
  if has(self, item.id) then return false end
  self.items[#self.items + 1] = item
  self:pump()
  return true
end

function Q:pump()
  if self.current or #self.items == 0 or self.fighting() then return end
  local item = table.remove(self.items, 1)
  self.current = item
  item.show(function() self:finish(item) end)
end

function Q:finish(item)
  if self.current ~= item then return end
  self.current = nil
  self:pump()
end

function Q:combat()
  local item = self.current
  if not item then return end
  self.current = nil
  if item.hide then item.hide() end
  table.insert(self.items, 1, item)
end

function Q:start(frame)
  frame:RegisterEvent("PLAYER_REGEN_DISABLED")
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then self:combat() else self:pump() end
  end)
end

return M
```

- [ ] **Step 6: Реализация `addon/wizard.lua`.**

```lua
-- The first-run guide: four pages, out of combat (addon/guide.lua decides when). It points at the
-- timeline, unlocks it to be dragged on page 3 and offers one button mode there, and ends on the
-- ready check of stage 1 when the host has one.
local M = {}
M.NAME = "DoubtMyRotationWizard"
M.WIDTH, M.HEIGHT = 400, 250

M.PAGES = {
  { title = "This is the timeline",
    text = "Icons slide from the right toward the line on the left. The big icon is the button to press next, "
      .. "the small ones come after it. Marks on the bottom lane are your melee swings (gold: main hand, silver: off hand); "
      .. "a green bar there means a Lightning Bolt fits before the next swing. The dots at the top right count Maelstrom Weapon stacks." },
  { title = "Press it at the line",
    text = "When the big icon reaches the line and glows, press that button on your action bars. "
      .. "The plan is worked out again several times a second: just follow the big icon. "
      .. "An icon left of the line is a reminder - a missing shield or weapon imbue, auto-attack off, a target too far." },
  { title = "Put it where you look", move = true, compact = true,
    text = "The timeline is unlocked now: drag it close to your character, where your eyes already are. "
      .. "It locks again when you leave this page. /dmr unlock moves it later." },
  { title = "Ready to fight?", checklist = true,
    text = "Before a fight: Lightning Shield up, imbues on your weapons, auto-attack on (right-click the target). "
      .. "/dmr opens the settings, /dmr guide shows this guide again." },
}

local BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                   edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                   tile = true, tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } }

local function lines(items)
  local out = {}
  for i, it in ipairs(items) do out[i] = (it.ok and "|cff33ff33+|r " or "|cffff5555-|r ") .. tostring(it.text) end
  return table.concat(out, "\n")
end

local W = {}

function W:open(close)
  self.close = close
  self:Show()
  self:page(self.n or 1)
end

function W:page(n)
  n = math.max(1, math.min(#M.PAGES, n))
  local p = M.PAGES[n]
  self.n = n
  self:move(p.move == true)
  self.title:SetText(p.title)
  self.step:SetText(("%d / %d"):format(n, #M.PAGES))
  self.text:SetText(p.text)
  if p.compact then
    self.compact:SetChecked(self.host.config().compact == true)
    self.compact:Show()
  else
    self.compact:Hide()
  end
  local items = p.checklist and self.host.checklist and self.host.checklist()
  self.list:SetText(items and lines(items) or "")
  if items and self.host.openChecklist then self.check:Show() else self.check:Hide() end
  if n == 1 then self.back:Hide() else self.back:Show() end
  self.next:SetText(n == #M.PAGES and "Done" or "Next")
end

-- unlocks the timeline for page 3 and locks it after; only what the guide unlocked itself
function W:move(on)
  if on and not self.moving and not self.host.unlocked() then
    self.moving = true
    self.host.move(true)
  elseif not on and self.moving then
    self.moving = false
    self.host.move(false)
  end
end

-- a fight began (addon/guide.lua): away without closing; the page stays for after the fight
function W:hide()
  self.close = nil
  self:move(false)
  self:Hide()
end

function W:finish(how)
  local close = self.close
  self.close = nil
  self:move(false)
  self.n = nil
  self:Hide()
  if how == "done" then self.host.done() elseif how == "never" then self.host.never() end
  if close then close() end
end

local function button(w, key, text, point, x, width, onClick)
  local b = CreateFrame("Button", M.NAME .. key, w, "UIPanelButtonTemplate")
  b.kind = "button"
  b:SetWidth(width)
  b:SetHeight(22)
  b:SetPoint(point, w, point, x, 16)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  w.widgets[#w.widgets + 1] = b
  return b
end

function M.new(host)
  local w = CreateFrame("Frame", M.NAME, UIParent)
  w.kind, w.widgets, w.host = "window", {}, host
  w:SetWidth(M.WIDTH)
  w:SetHeight(M.HEIGHT)
  w:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
  w:SetFrameStrata("DIALOG")
  w:SetBackdrop(BACKDROP)
  w:SetMovable(true)
  w:EnableMouse(true)
  w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", function(self) self:StartMoving() end)
  w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  w.title:SetPoint("TOP", w, "TOP", 0, -16)
  w.step = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  w.step:SetPoint("TOPRIGHT", w, "TOPRIGHT", -16, -18)
  w.text = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  w.text:SetPoint("TOPLEFT", w, "TOPLEFT", 20, -44)
  w.text:SetWidth(M.WIDTH - 40)
  w.text:SetJustifyH("LEFT")
  w.list = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  w.list:SetPoint("TOPLEFT", w.text, "BOTTOMLEFT", 0, -8)
  w.list:SetWidth(M.WIDTH - 40)
  w.list:SetJustifyH("LEFT")
  local c = CreateFrame("CheckButton", M.NAME .. "Compact", w, "InterfaceOptionsCheckButtonTemplate")
  c.kind = "toggle"
  c:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 16, 44)
  _G[c:GetName() .. "Text"]:SetText("One button mode: only the big icon and reminders")
  -- OnClick comes after the box has flipped; GetChecked gives 1 or nil
  c:SetScript("OnClick", function(self) w.host.set("compact", self:GetChecked() and true or false) end)
  w.compact = c
  w.widgets[#w.widgets + 1] = c
  w.back = button(w, "Back", "Back", "BOTTOMLEFT", 16, 70, function() w:page(w.n - 1) end)
  w.skip = button(w, "Skip", "Skip", "BOTTOMLEFT", 90, 70, function() w:finish("skip") end)
  w.never = button(w, "Never", "Don't show again", "BOTTOMLEFT", 164, 124, function() w:finish("never") end)
  w.next = button(w, "Next", "Next", "BOTTOMRIGHT", -16, 90, function()
    if w.n < #M.PAGES then w:page(w.n + 1) else w:finish("done") end
  end)
  w.check = CreateFrame("Button", M.NAME .. "Check", w, "UIPanelButtonTemplate")
  w.check.kind = "button"
  w.check:SetWidth(160)
  w.check:SetHeight(22)
  w.check:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 16, 46)
  w.check:SetText("Open the ready check")
  w.check:SetScript("OnClick", function() if w.host.openChecklist then w.host.openChecklist() end end)
  w.widgets[#w.widgets + 1] = w.check
  for k, fn in pairs(W) do w[k] = fn end
  -- Escape is Skip (the client hides the frames listed in UISpecialFrames)
  w:SetScript("OnHide", function(self) if self.close then self:finish("skip") end end)
  if UISpecialFrames then table.insert(UISpecialFrames, M.NAME) end
  w:Hide()
  return w
end

return M
```

- [ ] **Step 7: Реализация `addon/coach.lua`.**

```lua
-- When the guide and the level cards come up: the first-run guide at login until it is done here
-- (or turned off for the account), a card when a level brings one. The windows come from deps,
-- one at a time and out of combat through the queue (addon/guide.lua).
local cards = require("cards")

local M = {}

local C = {}
C.__index = C

-- deps: guide (the queue), db, char (SavedVariables), level() -> number, enabled(key) -> bool,
-- wizard() -> the guide window, card() -> the card window (both built on first use)
function M.new(deps)
  return setmetatable({ deps = deps }, C)
end

function C:wizardItem()
  local d = self.deps
  return { id = "wizard",
           show = function(close) d.wizard():open(close) end,
           hide = function() d.wizard():hide() end }
end

function C:cardItem(card)
  local d = self.deps
  return { id = "card" .. card.level,
           show = function(close)
             d.card():open(card, function()
               d.char.cards[card.level] = true
               close()
             end)
           end,
           hide = function() d.card():hide() end }
end

function C:login()
  local d = self.deps
  -- the addon put on a grown character: the cards behind it are old news
  if type(d.char.cards) ~= "table" then
    d.char.cards = {}
    cards.firstRun(d.level(), d.char.cards)
  end
  if not d.db.wizardOff and d.char.wizard ~= "done" then d.guide:push(self:wizardItem()) end
end

function C:levelUp(level)
  local d = self.deps
  d.char.cards = d.char.cards or {}
  if not d.enabled("levelCards") then return cards.firstRun(level, d.char.cards) end
  local card = cards.due(level, d.char.cards)
  if card then d.guide:push(self:cardItem(card)) end
end

function C:openGuide()
  self.deps.guide:push(self:wizardItem())
end

-- UnitLevel still gives the old level while PLAYER_LEVEL_UP runs: the event's own argument
function C:start(frame)
  frame:RegisterEvent("PLAYER_LEVEL_UP")
  frame:SetScript("OnEvent", function(_, _, level) self:levelUp(tonumber(level) or self.deps.level()) end)
end

return M
```

- [ ] **Step 8: Зелёный прогон.** `docker compose run --rm test busted spec/addon_guide_spec.lua spec/addon_wizard_spec.lua spec/addon_coach_spec.lua`, затем `docker compose run --rm test busted --exclude-tags=perf`.

- [ ] **Step 9: Коммит.** `Аддон: мастер первого запуска и очередь сообщений вне боя`.

### Task 6: Кнопка у миникарты — `addon/minimap.lua`

**Files:**
- Create: `addon/minimap.lua`
- Test: `spec/addon_minimap_spec.lua`

**Interfaces:**
- Produces:
  - `minimap.NAME = "DoubtMyRotationMinimapButton"`, `minimap.RADIUS = 80`, `minimap.ANGLE = 200` (градусы, по умолчанию — слева снизу), `minimap.TIP` (текст подсказки);
  - `minimap.offset(angle, shape, radius) -> x, y` — смещение от центра миникарты: `shape == "SQUARE"` — по краю квадрата, иначе по кругу;
  - `minimap.angle(cx, cy, px, py) -> 0..360` — угол от центра `(cx, cy)` к точке `(px, py)`;
  - `minimap.new(host) -> button` — `Button` с родителем `Minimap`, `b.kind = "minimap"`, `b.icon`, `b.border` (их меняет `addon/skin.lua`), `b:place(angle)`; ЛКМ → `host.open()`, ПКМ → `host.toggle()`; перетаскивание ЛКМ двигает кнопку за курсором по краю (`OnUpdate` только во время перетаскивания), в конце → `host.save(angle)`; при наведении — подсказка `GameTooltip`. Хост: `{ open(), toggle(), angle() -> number | nil, save(angle) }`.
- Consumes: `Minimap`, `GetCursorPosition`, `GetMinimapShape` (если есть), `GameTooltip` — клиент 3.3.5a (мок — задача 0, `GameTooltip` — `spec/support/panel_mock.lua`).

- [ ] **Step 1: Тесты `spec/addon_minimap_spec.lua`.**

```lua
local G = require("game_mock")
local P = require("panel_mock")
local minimap = require("minimap")

local function host(saved)
  local h = { opens = 0, toggles = 0, saved = saved }
  h.open = function() h.opens = h.opens + 1 end
  h.toggle = function() h.toggles = h.toggles + 1 end
  h.angle = function() return h.saved end
  h.save = function(a) h.saved = a end
  return h
end

describe("minimap button", function()
  before_each(function()
    G.install({})
    P.install()
  end)

  it("sits on the rim: a circle, or the edge of a square minimap", function()
    local x, y = minimap.offset(0, "ROUND")
    assert.are.near(80, x, 1e-9)
    assert.are.near(0, y, 1e-9)
    x, y = minimap.offset(90, nil)
    assert.are.near(0, x, 1e-9)
    assert.are.near(80, y, 1e-9)
    x, y = minimap.offset(45, "ROUND")
    assert.are.near(80 / math.sqrt(2), x, 1e-9)
    x, y = minimap.offset(45, "SQUARE")
    assert.are.near(80, x, 1e-9)
    assert.are.near(80, y, 1e-9)
    assert.are.near(135, minimap.angle(0, 0, -1, 1), 1e-9)
    assert.are.near(270, minimap.angle(10, 10, 10, 0), 1e-9)
  end)

  it("is a child of the minimap at its saved angle, or the default one", function()
    local b = minimap.new(host())
    assert.are.equal(b, DoubtMyRotationMinimapButton)
    assert.are.equal("minimap", b.kind)
    local x, y = minimap.offset(minimap.ANGLE, "ROUND")
    assert.are.same({ "CENTER", Minimap, "CENTER", x, y }, b.point)
    assert.is_true(Minimap.kids[1] == b)
    local again = minimap.new(host(90))
    assert.are.near(80, again.point[5], 1e-9)
  end)

  it("left click opens the settings, right click shows or hides the timeline", function()
    local h = host()
    local b = minimap.new(h)
    b.scripts.OnClick(b, "LeftButton")
    b.scripts.OnClick(b, "RightButton")
    assert.are.same({ 1, 1 }, { h.opens, h.toggles })
    assert.are.same({ "LeftButtonUp", "RightButtonUp" }, b.clicks)
  end)

  it("dragged, it follows the cursor round the rim and saves where it stopped", function()
    local h = host()
    G.cfg.cursor = { 1000, 800 } -- straight above the minimap's center (1000, 700)
    local b = minimap.new(h)
    b.scripts.OnDragStart(b)
    assert.is_function(b.scripts.OnUpdate)
    b.scripts.OnUpdate(b, 0.016)
    assert.are.near(0, b.point[4], 1e-9)
    assert.are.near(80, b.point[5], 1e-9)
    b.scripts.OnDragStop(b)
    assert.is_nil(b.scripts.OnUpdate)
    assert.are.near(90, h.saved, 1e-9)
  end)

  it("a square minimap (ElvUI) puts it on the square's edge", function()
    G.install({ minimapShape = "SQUARE" })
    P.install()
    local b = minimap.new(host(45))
    assert.are.near(80, b.point[4], 1e-9)
    assert.are.near(80, b.point[5], 1e-9)
  end)

  it("says what its clicks do on hover", function()
    local b = minimap.new(host())
    b.scripts.OnEnter(b)
    assert.are.equal(minimap.TIP, G.tooltip.text)
    assert.truthy(G.tooltip.text:find("Right-click", 1, true))
    b.scripts.OnLeave(b)
    assert.is_false(G.tooltip.shown)
  end)
end)
```

- [ ] **Step 2: Красный прогон.** `docker compose run --rm test busted spec/addon_minimap_spec.lua` — `module 'minimap' not found`.

- [ ] **Step 3: Реализация `addon/minimap.lua`.**

```lua
-- A button on the minimap's rim: left click - the settings, right click - show or hide the
-- timeline, drag - move it round the rim. A frame of our own (no LibDBIcon), the usual minimap
-- button layout of 3.3.5a; the angle is saved per character by the host.
local M = {}
M.NAME = "DoubtMyRotationMinimapButton"
M.ICON = "Interface\\Icons\\Ability_Shaman_Stormstrike"
M.RADIUS = 80
M.ANGLE = 200
M.TIP = "DoubtMyRotation\nLeft-click: settings\nRight-click: show or hide the timeline\nDrag: move this button"

-- the offset from the minimap's center: round - on the circle; square (ElvUI's GetMinimapShape()
-- gives "SQUARE") - out to the square's edge
function M.offset(angle, shape, radius)
  radius = radius or M.RADIUS
  local a = math.rad(angle)
  local x, y = math.cos(a), math.sin(a)
  if shape == "SQUARE" then
    local m = math.max(math.abs(x), math.abs(y))
    x, y = x / m, y / m
  end
  return x * radius, y * radius
end

function M.angle(cx, cy, px, py)
  local d = math.deg(math.atan2(py - cy, px - cx))
  if d < 0 then d = d + 360 end
  return d
end

local function shape()
  return GetMinimapShape and GetMinimapShape() or "ROUND"
end

-- while dragged: the angle from the minimap's center to the cursor (the cursor is in screen
-- pixels, the minimap's center in its own scale)
local function follow(b)
  local cx, cy = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local s = Minimap:GetEffectiveScale()
  b.angle = M.angle(cx, cy, px / s, py / s)
  b:place(b.angle)
end

function M.new(host)
  local b = CreateFrame("Button", M.NAME, Minimap)
  b.kind, b.host = "minimap", host
  b:SetWidth(31)
  b:SetHeight(31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b.icon = b:CreateTexture(nil, "BACKGROUND")
  b.icon:SetTexture(M.ICON)
  b.icon:SetWidth(20)
  b.icon:SetHeight(20)
  b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)
  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b.border:SetWidth(53)
  b.border:SetHeight(53)
  b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  function b:place(angle)
    local x, y = M.offset(angle, shape())
    self:ClearAllPoints()
    self:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end
  b.angle = host.angle() or M.ANGLE
  b:place(b.angle)
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then host.toggle() else host.open() end
  end)
  -- OnUpdate only while dragged: an idle button costs nothing per frame
  b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", follow) end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    host.save(self.angle)
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(M.TIP)
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

return M
```

- [ ] **Step 4: Зелёный прогон.** `docker compose run --rm test busted spec/addon_minimap_spec.lua`, затем `docker compose run --rm test busted --exclude-tags=perf`.

- [ ] **Step 5: Коммит.** `Аддон: кнопка у миникарты — настройки, показать/скрыть ленту, перетаскивание по краю`.

### Task 7: Оформление ElvUI — `addon/skin.lua`

**Files:**
- Create: `addon/skin.lua`
- Create: `spec/support/elvui_mock.lua` (подмена ElvUI Rebuffed 6.10: глобальная `ElvUI`, модуль `Skins`, `SetTemplate` на метатаблице рамок)
- Test: `spec/addon_skin_spec.lua`

**Interfaces:**
- Produces:
  - `skin.CALLBACK = "DoubtMyRotation"` — имя колбэка `S:AddCallback`;
  - `skin.HANDLE[kind] = function(S, widget)` для `kind` ∈ `"range"` (`S:HandleSliderFrame`), `"toggle"` (`S:HandleCheckBox`), `"select"` (`S:HandleDropDownBox(w, w.skinWidth or 180)`), `"button"` (`S:HandleButton`), `"edit"` (`S:HandleEditBox`), `"close"` (`S:HandleCloseButton`), `"scroll"` (`S:HandleScrollBar`), `"window"` (`w:SetTemplate("Transparent")`), `"minimap"` (рамка кнопки прячется, `SetTemplate("Default")`, иконка на всю кнопку), `"timeline"` (вместо `f.bg` — дочерняя рамка с `SetTemplate("Transparent")`, видимость прежняя; `core` и дальше зовёт `f.bg:Show()/Hide()`);
  - `skin.new(deps) -> sk`, `deps = { enabled() -> bool, elv() -> глобальная ElvUI (по умолчанию ElvUI), say(line) }`;
  - `sk:frame(f)` — запомнить рамку и оформить её (`f.kind`) и `f.widgets` (у каждого `kind`) сейчас, если ElvUI инициализирован, иначе после его `S:Initialize`; каждую рамку — один раз; опция выключена или ElvUI нет — ничего;
  - `sk:refresh()` — оформить всё запомненное (опцию включили);
  - `sk:export(w)` — окно экспорта `EnhRotExportFrame` из `src/timeline.lua`: проставляет `kind` (окно, кнопка «Refresh» `w.again`, крестик — вторая кнопка-ребёнок, полоса прокрутки `EnhRotExportScrollScrollBar`) и зовёт `sk:frame(w)`;
  - ошибка в функции ElvUI → одна строка через `deps.say` («ElvUI style failed, the standard look stays: …»), дальше ничего не оформляется, ошибки Lua наружу нет.
  - `spec/support/elvui_mock.lua`: `X.install({ initialized = bool (по умолчанию true), fail = "<имя функции>" })` → `_G.ElvUI = { E, {}, {}, {}, {} }`, `X.S` (`calls`, `callbacks`, `Initialized`), `G.FRAME.SetTemplate`; `X.initialize()` — как `S:Initialize`: `Initialized = true`, колбэки вызываются; `X.remove()`.
- Consumes: виджеты с `kind` от `panel` (задача 2), `profilepage` (задача 3), `cards` (задача 4), `wizard` (задача 5), `minimap` (задача 6); рамка ленты `DoubtMyRotationFrame` с `f.bg` (core); `G.FRAME`, `GetChildren`, `SetFrameLevel` (задача 0).

- [ ] **Step 1: Мок `spec/support/elvui_mock.lua`.**

```lua
-- A stand-in for ElvUI Rebuffed 6.10 (3.3.5a): the global ElvUI = { E, L, V, P, G }, its Skins
-- module recording each Handle* call, and SetTemplate, which ElvUI's Toolkit puts on every frame's
-- metatable (here: game_mock's G.FRAME). Call X.install(cfg) after G.install().
local G = require("game_mock")

local X = {}
X.HANDLERS = { "HandleSliderFrame", "HandleCheckBox", "HandleDropDownBox", "HandleButton", "HandleEditBox",
               "HandleCloseButton", "HandleScrollBar" }

-- cfg: initialized (default true: ElvUI loaded before us), fail = the name of a function that errors
function X.install(cfg)
  cfg = cfg or {}
  local S = { Initialized = cfg.initialized ~= false, calls = {}, callbacks = {}, added = 0 }
  for _, name in ipairs(X.HANDLERS) do
    S[name] = function(self, w, ...)
      if cfg.fail == name then error("ElvUI: " .. name .. " broke") end
      self.calls[#self.calls + 1] = { name, w, ... }
      w.elv = name
    end
  end
  -- ElvUI refuses a name twice (Skins.lua S:AddCallback); here that is an error to see in tests
  function S:AddCallback(name, fn)
    if self.callbacks[name] then error("S:AddCallback: " .. name .. " is already registered") end
    self.callbacks[name] = fn
    self.added = self.added + 1
  end
  local E = { modules = { Skins = S } }
  function E:GetModule(name, silent)
    local m = self.modules[name]
    if not m and not silent then error("no module " .. name) end
    return m
  end
  _G.ElvUI = { E, {}, {}, {}, {} }
  G.FRAME.SetTemplate = function(self, template)
    if cfg.fail == "SetTemplate" then error("ElvUI: SetTemplate broke") end
    self.elvTemplate = template or "Default"
  end
  X.S, X.E = S, E
  return S
end

-- ElvUI's Skins module coming up (S:Initialize): Initialized first, then the callbacks
function X.initialize()
  X.S.Initialized = true
  for name, fn in pairs(X.S.callbacks) do
    X.S.callbacks[name] = nil
    fn(name)
  end
end

function X.remove()
  _G.ElvUI = nil
  G.FRAME.SetTemplate = nil
end

return X
```

- [ ] **Step 2: Тесты `spec/addon_skin_spec.lua`.**

```lua
local G = require("game_mock")
local X = require("elvui_mock")
local skin = require("skin")

local function widget(kind, objectType)
  local w = CreateFrame(objectType or "Frame", nil, UIParent)
  w.kind = kind
  return w
end

-- a window as the addon's modules make them: kind and widgets
local function window()
  local f = widget("window")
  f.widgets = { widget("range", "Slider"), widget("toggle", "CheckButton"), widget("select"), widget("button", "Button"),
                widget("edit", "EditBox") }
  return f
end

local function names(S)
  local out = {}
  for i, c in ipairs(S.calls) do out[i] = c[1] end
  return out
end

describe("ElvUI style", function()
  local said, on
  local function new() return skin.new({ enabled = function() return on end, say = function(l) said[#said + 1] = l end }) end
  before_each(function()
    G.install({})
    X.remove()
    said, on = {}, true
  end)

  it("without ElvUI nothing is touched", function()
    local f = window()
    new():frame(f)
    assert.is_nil(f.elvTemplate)
    for _, w in ipairs(f.widgets) do assert.is_nil(w.elv) end
    assert.are.equal(0, #said)
  end)

  -- ElvUI loaded first (OptionalDeps): its Skins module is up by our PLAYER_LOGIN
  it("ElvUI up: each widget gets its ElvUI function at once, a frame only once", function()
    local S = X.install()
    local f = window()
    local sk = new()
    sk:frame(f)
    sk:frame(f)
    assert.are.same({ "HandleSliderFrame", "HandleCheckBox", "HandleDropDownBox", "HandleButton", "HandleEditBox" }, names(S))
    assert.are.equal(180, S.calls[3][3])
    assert.are.equal("Transparent", f.elvTemplate)
    assert.are.equal(0, S.added)
  end)

  -- ElvUI loaded after us: Skins initializes later, its callbacks fire then (and only then)
  it("ElvUI not up yet: everything waits for one callback", function()
    local S = X.install({ initialized = false })
    local a, b = window(), window()
    local sk = new()
    sk:frame(a)
    sk:frame(b)
    assert.are.same({}, S.calls)
    assert.are.equal(1, S.added)
    X.initialize()
    assert.are.equal(10, #S.calls)
    assert.are.equal("Transparent", a.elvTemplate)
    assert.are.equal("Transparent", b.elvTemplate)
    -- a window made after ElvUI came up: at once
    local c = window()
    sk:frame(c)
    assert.are.equal(15, #S.calls)
  end)

  it("the option off: nothing; turned on: all known frames at once", function()
    local S = X.install()
    on = false
    local sk = new()
    local f = window()
    sk:frame(f)
    assert.are.same({}, S.calls)
    on = true
    sk:refresh()
    assert.are.equal(5, #S.calls)
  end)

  it("a broken ElvUI function: one line, no Lua error, the standard look for the rest", function()
    local S = X.install({ fail = "HandleCheckBox" })
    local sk = new()
    assert.has_no.errors(function()
      sk:frame(window())
      sk:frame(window())
    end)
    assert.are.equal(1, #said)
    assert.truthy(said[1]:find("ElvUI style failed", 1, true))
    assert.are.same({ "HandleSliderFrame" }, names(S))
  end)

  it("the export window: the engine's frame, its buttons and scroll bar found by kind", function()
    local S = X.install()
    local w = require("timeline").exportWindow("text", function() return "text" end)
    _G.EnhRotExportScrollScrollBar = CreateFrame("Slider", "EnhRotExportScrollScrollBar")
    new():export(w)
    assert.are.equal("Transparent", w.elvTemplate)
    assert.are.equal("HandleButton", w.again.elv)
    local close
    for _, c in ipairs({ w:GetChildren() }) do
      if c.template == "UIPanelCloseButton" then close = c end
    end
    assert.are.equal("HandleCloseButton", close.elv)
    assert.are.equal("HandleScrollBar", EnhRotExportScrollScrollBar.elv)
    assert.are.equal(3, #S.calls)
  end)

  -- core keeps calling frame.bg:Show() / Hide() on lock and unlock
  it("the timeline's backdrop while unlocked becomes ElvUI's panel, shown as it was", function()
    X.install()
    local f = CreateFrame("Frame", "DoubtMyRotationFrame", UIParent)
    f.kind = "timeline"
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:Hide()
    local plain = f.bg
    new():frame(f)
    assert.are_not.equal(plain, f.bg)
    assert.are.equal("Transparent", f.bg.elvTemplate)
    assert.is_false(f.bg:IsShown())
    assert.is_false(plain:IsShown())
    assert.are.equal(f:GetFrameLevel(), f.bg:GetFrameLevel())
  end)

  it("a broken SetTemplate leaves the plain backdrop in place", function()
    X.install({ fail = "SetTemplate" })
    local f = CreateFrame("Frame", nil, UIParent)
    f.kind = "timeline"
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    local plain = f.bg
    new():frame(f)
    assert.are.equal(plain, f.bg)
    assert.are.equal(1, #said)
  end)

  it("the minimap button: its round border goes, ElvUI's square frame instead", function()
    X.install()
    local b = CreateFrame("Button", nil, UIParent)
    b.kind = "minimap"
    b.icon, b.border = b:CreateTexture(), b:CreateTexture()
    new():frame(b)
    assert.is_false(b.border:IsShown())
    assert.are.equal("Default", b.elvTemplate)
    assert.are.same({ 0.08, 0.92, 0.08, 0.92 }, b.icon.coords)
  end)
end)
```

- [ ] **Step 3: Красный прогон.** `docker compose run --rm test busted spec/addon_skin_spec.lua` — `module 'skin' not found`.

- [ ] **Step 4: Реализация `addon/skin.lua`.**

```lua
-- ElvUI's look for the addon's own windows, when ElvUI is installed and the option is on. ElvUI's
-- engine is the global ElvUI ({ E, L, V, P, G }); its Skins module styles one widget per call.
-- Loaded before us (OptionalDeps: ElvUI) it is up by our PLAYER_LOGIN; loaded after, the styling
-- waits for S:AddCallback, which S:Initialize fires once - so it is used only while S is not up.
-- Every ElvUI call is protected: another ElvUI version must not break our windows.
local M = {}
M.CALLBACK = "DoubtMyRotation"

M.HANDLE = {
  range = function(S, w) S:HandleSliderFrame(w) end,
  toggle = function(S, w) S:HandleCheckBox(w) end,
  select = function(S, w) S:HandleDropDownBox(w, w.skinWidth or 180) end,
  button = function(S, w) S:HandleButton(w) end,
  edit = function(S, w) S:HandleEditBox(w) end,
  close = function(S, w) S:HandleCloseButton(w) end,
  scroll = function(S, w) S:HandleScrollBar(w) end,
  window = function(_, w) w:SetTemplate("Transparent") end,
  minimap = function(_, b)
    b:SetTemplate("Default")
    if b.border then b.border:Hide() end
    if b.icon then
      b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      b.icon:ClearAllPoints()
      b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
      b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    end
  end,
  -- the timeline's backdrop while unlocked (addon/core.lua frame.bg): ElvUI's panel instead of the
  -- plain dark texture; swapped only once SetTemplate worked
  timeline = function(_, f)
    local bg = CreateFrame("Frame", nil, f)
    bg:SetAllPoints(f)
    bg:SetFrameLevel(f:GetFrameLevel())
    bg:SetTemplate("Transparent")
    local shown = f.bg and f.bg:IsShown()
    if f.bg then f.bg:Hide() end
    f.bg = bg
    if shown then bg:Show() else bg:Hide() end
  end,
}

local Skin = {}
Skin.__index = Skin

function M.new(deps)
  return setmetatable({ deps = deps or {}, frames = {}, done = {}, waiting = false, failed = false }, Skin)
end

function Skin:on()
  local enabled = self.deps.enabled
  return not enabled or enabled() ~= false
end

-- ElvUI's Skins module, or nil (not installed, or not ElvUI as we know it)
function Skin:skins()
  local g
  if self.deps.elv then g = self.deps.elv() else g = ElvUI end
  local E = type(g) == "table" and g[1]
  if type(E) ~= "table" or type(E.GetModule) ~= "function" then return nil end
  local ok, S = pcall(E.GetModule, E, "Skins", true)
  if ok and type(S) == "table" then return S end
  return nil
end

function Skin:fail(err)
  if self.failed then return end
  self.failed = true
  local say = self.deps.say or print
  say("ElvUI style failed, the standard look stays: " .. tostring(err))
end

function Skin:style(f, S)
  if self.done[f] or self.failed then return end
  self.done[f] = true
  local list = { f }
  for _, w in ipairs(f.widgets or {}) do list[#list + 1] = w end
  for _, w in ipairs(list) do
    local h = w.kind and M.HANDLE[w.kind]
    if h then
      local ok, err = pcall(h, S, w)
      if not ok then return self:fail(err) end
    end
  end
end

function Skin:refresh()
  if not self:on() then return end
  local S = self:skins()
  if not S then return end
  if not S.Initialized then
    if not self.waiting then
      self.waiting = true
      local ok, err = pcall(S.AddCallback, S, M.CALLBACK, function()
        self.waiting = false
        self:refresh()
      end)
      if not ok then self:fail(err) end
    end
    return
  end
  for _, f in ipairs(self.frames) do self:style(f, S) end
end

function Skin:frame(f)
  if not f then return end
  local known = false
  for _, g in ipairs(self.frames) do
    if g == f then known = true end
  end
  if not known then self.frames[#self.frames + 1] = f end
  self:refresh()
end

-- the copy window of src/timeline.lua: the engine builds it, so its parts are found here
function Skin:export(w)
  if not w then return end
  if not w.widgets then
    w.kind, w.widgets = "window", {}
    for _, c in ipairs({ w:GetChildren() }) do
      if c == w.again then
        c.kind = "button"
      elseif c:GetObjectType() == "Button" then
        c.kind = "close"
      end
      if c.kind then w.widgets[#w.widgets + 1] = c end
    end
    local bar = _G["EnhRotExportScrollScrollBar"]
    if bar then
      bar.kind = "scroll"
      w.widgets[#w.widgets + 1] = bar
    end
  end
  self:frame(w)
end

return M
```

- [ ] **Step 5: Зелёный прогон.** `docker compose run --rm test busted spec/addon_skin_spec.lua`, затем `docker compose run --rm test busted --exclude-tags=perf`.

- [ ] **Step 6: Коммит.** `Аддон: окна в стиле ElvUI, если он установлен`.

### Task 8: Связка — `addon/core.lua`, сборка, сквозной тест

**Files:**
- Modify: `addon/core.lua` (почти весь файл: SavedVariables персонажа, профили, новые модули)
- Modify: `tools/build.lua` (только `B.ADDON_MODULES`)
- Test: `spec/addon_core_spec.lua` (подмены и `before_each`, правка старых тестов, новые блоки), `spec/build_spec.lua` (тесты `names its folder and its modules` и `runs as an addon without WeakAuras and draws a plan #integration`)

**Interfaces:**
- Produces:
  - глобальные: `DoubtMyRotationDB = { config (прежний, не трогается), profiles, ui, saved, newest, wizardOff }`, `DoubtMyRotationCharDB = { profile, auto, point, hidden, minimap = { angle }, wizard, cards }`; рамки `DoubtMyRotationEvents`, `DoubtMyRotationGuide`, `DoubtMyRotationCoach` (и прежние);
  - `core.config` — значения активного профиля (то, что видят движок и окно; раньше это был `DoubtMyRotationDB.config`), `core.profile` — имя активного профиля, `core.why` — почему он (`profiles.pick`), `core.char`;
  - `core.choose(o, announce)` — профиль по месту и уровню; `core.switch(o, name, why, announce)` — смена (в бою — ничего, `PLAYER_REGEN_ENABLED` выберет снова); `core.changed(o, delay)` — значения изменились: сохранить в профиль / `db.ui`, кнопка миникарты и стиль ElvUI — по опциям, движок — перезапуск (с паузой `delay`); `core.move(on)` — открепить / закрепить ленту; `core.open()` — окно настроек, в бою — одна строка и открытие после боя;
  - хосты: `core.host(o)` (как было + `label("guide") = "Show the guide"`), `core.profileHost(o)`, `core.wizardHost(o)`, `core.cardHost(o)`, `core.miniHost(o)` — по интерфейсам задач 3–6;
  - `core.checklist` — то, что даёт этап 1 для последней страницы мастера: `{ items = function() -> { { ok = bool, text = string } }, open = function() }` или `nil`. Если интерфейс модуля «всё ли готово» этапа 1 (`addon/ready.lua`) другой — C пишет в `core.lua` адаптер к нему (до 15 строк), отдающий ровно этот вид; нет этапа 1 — `nil`, мастер показывает текст без списка;
  - `B.ADDON_MODULES` = LibSerialize, LibDeflate, `settings`, `profiles`, `panel`, `profilepage`, `update`, `guide`, `cards`, `wizard`, `coach`, `minimap`, `skin`, `core` (модули этапа 1 — на своих местах из его плана, перед `core`).
- Consumes: всё из задач 1–7 по их интерфейсам; в `spec/addon_core_spec.lua` окна `panel`, `profilepage`, `wizard` и модуль `cards` подменены через `package.loaded`, `profiles`, `guide`, `coach`, `minimap`, `skin` — настоящие.

- [ ] **Step 1: Подмены и общие помощники в `spec/addon_core_spec.lua`.** Вверху файла, рядом с подменами `panel` и `update`:

```lua
local reloads, pages, wizards, cardWindows = {}, {}, {}, {}
package.loaded.panel = {
  new = function(o, host)
    local f = CreateFrame("Frame", "DoubtMyRotationPanel")
    f.o, f.host = o, host
    f.widgets = { CreateFrame("Button") }
    f.widgets[1].kind = "button"
    panels[#panels + 1] = f
    return f
  end,
  reload = function(main) reloads[#reloads + 1] = main end,
}
package.loaded.profilepage = {
  new = function(host)
    local f = CreateFrame("Frame", "DoubtMyRotationPanelProfiles")
    f.host, f.refreshes = host, 0
    f.refresh = function(self) self.refreshes = self.refreshes + 1 end
    pages[#pages + 1] = f
    return f
  end,
}
package.loaded.wizard = {
  new = function(host)
    local w = CreateFrame("Frame", "DoubtMyRotationWizard")
    w.kind, w.widgets, w.host = "window", {}, host
    function w:open(close) self.close = close; self:Show() end
    function w:hide() self:Hide() end
    wizards[#wizards + 1] = w
    return w
  end,
}
package.loaded.cards = {
  firstRun = function(level, seen) for l = 10, level, 10 do seen[l] = true end end,
  due = function(level, seen)
    local l = math.floor(level / 10) * 10
    if l >= 10 and not seen[l] then return { level = l } end
  end,
  window = function(host)
    local w = DoubtMyRotationCard or CreateFrame("Frame", "DoubtMyRotationCard")
    w.kind, w.widgets, w.host = "window", {}, host
    function w:open(card, close) self.card, self.close = card, close; self:Show() end
    function w:hide() self:Hide() end
    cardWindows[#cardWindows + 1] = w
    return w
  end,
}
```

`before_each` обнуляет и новые поля: `core.char, core.config, core.profile, core.why, core.level, core.skin, core.mini, core.guide, core.coach, core.wizard, core.profilePage, core.openLater, core.checklist = nil, …` и списки `reloads, pages, wizards, cardWindows = {}, {}, {}, {}`, а также `require("elvui_mock").remove()` (упавший тест ElvUI не должен оставить его следующим). Помощник — вход вне боя (мок по умолчанию «в бою»):

```lua
local function calm(extra)
  extra = extra or {}
  extra.inCombat = false
  shaman(extra)
end
```

- [ ] **Step 2: Правка старых тестов под профили.** Везде `DoubtMyRotationDB.config` → `core.config` (то, что видит движок; сохранённое — `DoubtMyRotationDB.profiles.Default`); `DoubtMyRotationDB.point` → `DoubtMyRotationCharDB.point`; `DoubtMyRotationDB.hidden` → `DoubtMyRotationCharDB.hidden`. Конкретно:
  - «a shaman gets the timeline frame…»: `assert.are.same(settings.defaults(o.options), core.config)`;
  - «/dmr set restarts…»: `assert.are.equal(2, core.config.icons)` и `assert.are.equal(2, DoubtMyRotationDB.profiles.Default.icons)`;
  - «the saved position and hidden state come back after a reload» — оставить вход со старой базой `{ point = …, hidden = true, config = { icons = 3 } }` (это и есть переход с прошлой версии), ожидать `core.config.icons == 3`, рамку на месте и скрытой;
  - «unlock lets the frame be dragged…»: `DoubtMyRotationCharDB.point`;
  - «/dmr reset also puts the timeline back…»: `assert.is_nil(DoubtMyRotationCharDB.point)`;
  - «hide and show…», «the lock and hide buttons…»: `DoubtMyRotationCharDB.hidden`;
  - «set changes one value…»: `assert.are.equal(core.config, h.config())`;
  - «replace takes a whole config…»: `core.config.icons`, `assert.are.equal(core.config, core.rt.config)`;
  - «its option joins the settings…»: опций стало `n + 1 + #settings.ADDON_OPTIONS`, `o.options[n + 1].key == "updateCheck"`, `o.options[#o.options].key == "elvui"`, `core.config.updateCheck == true`.

- [ ] **Step 3: Новые тесты.** В `spec/addon_core_spec.lua`, новыми блоками внутри `describe("addon core", …)`:

```lua
  describe("profiles", function()
    -- the SavedVariables of the version before profiles
    it("the old settings become the Default profile and stay where they were", function()
      shaman()
      local old = { config = { icons = 2, showReason = false }, point = { "TOP", nil, "TOP", 0, -40 } }
      login(opts(), old)
      assert.are.equal("Default", core.profile)
      assert.are.equal(2, core.config.icons)
      assert.is_false(core.config.showReason)
      assert.are.same({ icons = 2, showReason = false }, DoubtMyRotationDB.config)
      assert.are.same({ "TOP", nil, "TOP", 0, -40 }, DoubtMyRotationCharDB.point)
      assert.are.same({ "TOP", UIParent, "TOP", 0, -40 }, core.frame.point)
    end)

    it("a dungeon picks the dungeon rule's profile, the open world the picked one", function()
      shaman({ instance = "party" })
      _G.DoubtMyRotationCharDB = { profile = "Default", auto = { party = "Dungeon" } }
      login(opts(), { profiles = { Default = {}, Dungeon = { icons = 1 } } })
      assert.are.equal("Dungeon", core.profile)
      assert.are.equal(1, core.rt.config.icons)
      local first = core.rt
      G.cfg.instance = "none"
      DoubtMyRotationEvents.scripts.OnEvent(DoubtMyRotationEvents, "PLAYER_ENTERING_WORLD")
      assert.are.equal("Default", core.profile)
      assert.are.equal(4, core.rt.config.icons)
      assert.are_not.equal(first, core.rt)
      assert.truthy(G.printed[#G.printed]:find("profile Default", 1, true))
      assert.are.same({ panels[1] }, reloads)
    end)

    it("in a fight the profile waits for the fight's end", function()
      shaman({ instance = "raid" })
      _G.DoubtMyRotationCharDB = { auto = { raid = "Raid" } }
      login(opts(), { profiles = { Default = {}, Raid = { icons = 2 } } })
      G.cfg.instance, G.cfg.lockdown = "none", true
      local before = core.rt
      DoubtMyRotationEvents.scripts.OnEvent(DoubtMyRotationEvents, "ZONE_CHANGED_NEW_AREA")
      assert.are.equal("Raid", core.profile)
      assert.are.equal(before, core.rt)
      G.cfg.lockdown = false
      DoubtMyRotationEvents.scripts.OnEvent(DoubtMyRotationEvents, "PLAYER_REGEN_ENABLED")
      assert.are.equal("Default", core.profile)
    end)

    -- UnitLevel still gives the old level while PLAYER_LEVEL_UP runs
    it("hitting 80 leaves the leveling profile, by the event's own level", function()
      shaman({ level = 79 })
      _G.DoubtMyRotationCharDB = { auto = { leveling = "Leveling" } }
      login(opts(), { profiles = { Default = {}, Leveling = { compact = true } } })
      assert.are.equal("Leveling", core.profile)
      DoubtMyRotationEvents.scripts.OnEvent(DoubtMyRotationEvents, "PLAYER_LEVEL_UP", 80)
      assert.are.equal("Default", core.profile)
    end)

    it("a value set goes into the active profile, the account's ones into db.ui", function()
      shaman()
      _G.DoubtMyRotationCharDB = { profile = "Raid" }
      login(opts(), { profiles = { Default = {}, Raid = {} } })
      SlashCmdList.DOUBTMYROTATION("set icons 3")
      SlashCmdList.DOUBTMYROTATION("set minimap off")
      assert.are.equal(3, DoubtMyRotationDB.profiles.Raid.icons)
      assert.is_nil(DoubtMyRotationDB.profiles.Default.icons)
      assert.is_false(DoubtMyRotationDB.ui.minimap)
      assert.is_false(DoubtMyRotationMinimapButton.shown)
    end)

    it("the Profiles page's host: new, copy, delete the active one, rules", function()
      shaman()
      login(opts())
      local h = pages[1].host
      SlashCmdList.DOUBTMYROTATION("set icons 2")
      assert.are.equal("Copy", h.create("Copy", true))
      assert.are.equal("Copy", core.profile)
      assert.are.equal(2, core.config.icons)
      assert.are.same({ nil, "Copy: there is one already" }, { h.create("Copy") })
      assert.are.same({ "Default", "Copy" }, h.list())
      assert.is_true(h.delete("Copy"))
      assert.are.equal("Default", core.profile)
      h.setRule("raid", "Default")
      assert.are.equal("Default", h.rule("raid"))
      assert.are.same({ "Default", "picked" }, { h.active() })
      assert.is_true(pages[1].refreshes > 0)
    end)
  end)

  describe("first-run guide and level cards", function()
    it("a new character out of combat gets the guide; Done keeps it away on this character", function()
      calm()
      login(opts())
      local w = wizards[1]
      assert.is_true(w:IsShown())
      w.host.done()
      w.close()
      assert.are.equal("done", DoubtMyRotationCharDB.wizard)
      -- the guide's page 3 moves the timeline through the host
      w.host.move(true)
      assert.is_true(core.frame.mouse)
      assert.is_true(w.host.unlocked())
      w.host.move(false)
      w.host.set("compact", true)
      assert.is_true(core.config.compact)
    end)

    it("not in a fight: the guide waits for the fight's end", function()
      shaman() -- the mock says: in combat
      login(opts())
      assert.is_nil(wizards[1])
      G.cfg.inCombat = false
      DoubtMyRotationGuide.scripts.OnEvent(DoubtMyRotationGuide, "PLAYER_REGEN_ENABLED")
      assert.is_true(wizards[1]:IsShown())
    end)

    it("Don't show again: no guide on any character; /dmr guide still opens it", function()
      calm()
      login(opts(), { wizardOff = true })
      assert.is_nil(wizards[1])
      SlashCmdList.DOUBTMYROTATION("guide")
      assert.is_true(wizards[1]:IsShown())
      wizards[1].host.never()
      assert.is_true(DoubtMyRotationDB.wizardOff)
    end)

    it("a level up brings its card once; the option off brings none", function()
      calm({ level = 19 })
      _G.DoubtMyRotationCharDB = { wizard = "done" }
      login(opts())
      DoubtMyRotationCoach.scripts.OnEvent(DoubtMyRotationCoach, "PLAYER_LEVEL_UP", 20)
      local w = cardWindows[#cardWindows]
      assert.are.equal(20, w.card.level)
      w.close()
      assert.is_true(DoubtMyRotationCharDB.cards[20])
      SlashCmdList.DOUBTMYROTATION("set levelCards off")
      DoubtMyRotationCoach.scripts.OnEvent(DoubtMyRotationCoach, "PLAYER_LEVEL_UP", 30)
      assert.are.equal(20, cardWindows[#cardWindows].card.level)
      assert.is_true(DoubtMyRotationCharDB.cards[30])
    end)

    it("the guide's last page lists stage 1's ready check when there is one", function()
      calm()
      core.checklist = { items = function() return { { ok = true, text = "Lightning Shield" } } end, open = function() end }
      login(opts())
      assert.are.same({ { ok = true, text = "Lightning Shield" } }, wizards[1].host.checklist())
      assert.is_function(wizards[1].host.openChecklist)
    end)
  end)

  describe("minimap button, combat and ElvUI", function()
    it("left click opens the settings, out of combat only; right click hides the timeline", function()
      shaman()
      login(opts())
      local b = DoubtMyRotationMinimapButton
      assert.is_true(b.shown)
      G.cfg.lockdown = true
      b.scripts.OnClick(b, "LeftButton")
      assert.is_nil(G.opened)
      assert.are.equal("|cff33ff99DoubtMyRotation|r the settings open after combat", G.printed[#G.printed])
      SlashCmdList.DOUBTMYROTATION("") -- asked again in the same fight: no second line
      assert.are.equal("|cff33ff99DoubtMyRotation|r the settings open after combat", G.printed[#G.printed])
      G.cfg.lockdown = false
      DoubtMyRotationEvents.scripts.OnEvent(DoubtMyRotationEvents, "PLAYER_REGEN_ENABLED")
      assert.are.equal(DoubtMyRotationPanel, G.opened)
      b.scripts.OnClick(b, "RightButton")
      assert.is_true(DoubtMyRotationCharDB.hidden)
      b.scripts.OnDragStop(b)
      assert.are.equal(200, DoubtMyRotationCharDB.minimap.angle)
    end)

    it("one button mode shrinks the frame to the icon", function()
      shaman()
      login(opts())
      assert.are.equal(340, core.frame.w)
      SlashCmdList.DOUBTMYROTATION("set compact on")
      assert.are.equal(120, core.frame.w)
      assert.is_true(core.rt.tl.o.compact)
    end)

    it("ElvUI loaded first: our windows, the minimap button and the backdrop get its look", function()
      shaman()
      local S = require("elvui_mock").install()
      login(opts())
      assert.are.equal("HandleButton", panels[1].widgets[1].elv)
      assert.are.equal("Default", DoubtMyRotationMinimapButton.elvTemplate)
      assert.are.equal("Transparent", core.frame.bg.elvTemplate)
      SlashCmdList.DOUBTMYROTATION("export")
      assert.are.equal("Transparent", EnhRotExportFrame.elvTemplate)
      assert.is_true(#S.calls >= 2)
      require("elvui_mock").remove()
    end)

    it("ElvUI style off: ElvUI is left alone", function()
      shaman()
      local S = require("elvui_mock").install()
      login(opts(), { ui = { elvui = false } })
      assert.are.same({}, S.calls)
      assert.is_nil(DoubtMyRotationMinimapButton.elvTemplate)
      require("elvui_mock").remove()
    end)
  end)
```

В `spec/build_spec.lua`, тест «names its folder and its modules»:

```lua
    assert.are.same({ { "LibSerialize", "vendor/LibSerialize.lua" }, { "LibDeflate", "vendor/LibDeflate.lua" },
                      { "settings", "addon/settings.lua" }, { "profiles", "addon/profiles.lua" },
                      { "panel", "addon/panel.lua" }, { "profilepage", "addon/profilepage.lua" },
                      { "update", "addon/update.lua" }, { "guide", "addon/guide.lua" }, { "cards", "addon/cards.lua" },
                      { "wizard", "addon/wizard.lua" }, { "coach", "addon/coach.lua" }, { "minimap", "addon/minimap.lua" },
                      { "skin", "addon/skin.lua" }, { "core", "addon/core.lua" } }, build.ADDON_MODULES)
```

(с модулями этапа 1 — на их местах). В сквозном тесте «runs as an addon without WeakAuras and draws a plan #integration» — `G.install({ …, inCombat = false, … })` и вместо `assert.are.equal(3, #G.categories)`:

```lua
    assert.are.equal(4, #G.categories)
    assert.are.equal(DoubtMyRotationPanelProfiles, G.categories[4])
    assert.is_true(DoubtMyRotationMinimapButton.shown)
    assert.is_true(DoubtMyRotationWizard:IsShown()) -- a new character, out of combat
    assert.are.same({ Default = genv.DoubtMyRotationDB.profiles.Default }, genv.DoubtMyRotationDB.profiles)
    assert.is_table(genv.DoubtMyRotationCharDB)
```

(число страниц — с учётом страниц этапа 1, если он их добавил).

- [ ] **Step 4: Красный прогон.** `docker compose run --rm test busted spec/addon_core_spec.lua spec/build_spec.lua` — падают новые тесты и поправленные старые (`core.config` — `nil`, нет `DoubtMyRotationCharDB`, `DoubtMyRotationEvents`, кнопки у миникарты; сквозной видит 3 страницы).

- [ ] **Step 5: Реализация `addon/core.lua`.** Файл целиком (части этапа 1 — сохранить на своих местах):

```lua
-- The addon's entry: SavedVariables (the account's profiles in DoubtMyRotationDB, the character's
-- pick, place and progress in DoubtMyRotationCharDB), the timeline's frame, /dmr, the settings
-- window and its Profiles page, the update check, the first-run guide and level cards, the minimap
-- button, ElvUI's look, and the same engine the aura runs (runtime.start). The aura's host gives
-- the engine a region, saved data and a "show me" signal; here the frame is ours, always there,
-- and needs no signal (env.show stays nil).
local runtime = require("runtime")
local timeline = require("timeline")
local settings = require("settings")
local profiles = require("profiles")
local panel = require("panel")
local profilepage = require("profilepage")
local update = require("update")
local guide = require("guide")
local cards = require("cards")
local wizard = require("wizard")
local coach = require("coach")
local minimap = require("minimap")
local skin = require("skin")

local M = {}
M.NAME = "DoubtMyRotation"
M.TAG = "|cff33ff99DoubtMyRotation|r "
M.PAUSE = 0.3
M.EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED" }

local function say(line) print(M.TAG .. line) end

-- the build's option list plus the addon's own, as a copy: the caller's list stays the aura's
local function addonOptions(options)
  local extra = { update.OPTION }
  for _, opt in ipairs(settings.ADDON_OPTIONS) do extra[#extra + 1] = opt end
  return settings.withExtra(options, extra)
end

-- the saved place, or the default one under the screen's center
local function place(f, p)
  f:ClearAllPoints()
  -- the anchor's frame is saved as nil: a frame reference does not survive SavedVariables
  if p then f:SetPoint(p[1], UIParent, p[3], p[4], p[5]) else f:SetPoint("CENTER", UIParent, "CENTER", 0, -200) end
end

function M.newFrame(o, char)
  local f = CreateFrame("Frame", "DoubtMyRotationFrame", UIParent)
  f.kind = "timeline" -- addon/skin.lua: ElvUI's backdrop instead of f.bg
  f:SetWidth(o.width)
  f:SetHeight(o.height)
  place(f, char.point)
  -- dragged past the edge or a smaller resolution: it stays where it can be reached
  f:SetClampedToScreen(true)
  -- what there is to grab while unlocked
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints(f)
  f.bg:SetTexture(0, 0, 0, 0.4)
  f.bg:Hide()
  f:SetMovable(true)
  f:EnableMouse(false)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local a, _, b, x, y = self:GetPoint()
    char.point = { a, nil, b, x, y }
  end)
  return f
end

function M.load(o)
  local db = DoubtMyRotationDB or {}
  DoubtMyRotationDB = db
  -- a new SavedVariablesPerCharacter: the client reads the .toc only at its start
  local char = DoubtMyRotationCharDB or {}
  DoubtMyRotationCharDB = char
  profiles.migrate(db, char)
  db.saved = db.saved or {}
  M.db, M.char = db, char
  M.profile, M.why = char.profile, "picked"
  M.config = profiles.view(o.options, db, M.profile)
end

function M.save(o)
  profiles.store(o.options, M.db, M.profile, M.config)
end

local function start()
  -- one button mode: the frame shrinks to the icon (src/timeline.lua: 2 x nowX wide)
  M.frame:SetWidth(M.config.compact and 2 * timeline.DEFAULTS.nowX or M.width)
  M.rt = runtime.start(M.config, M.env)
  -- a fresh engine runs; behind a hidden frame it must sleep (OnHide will not fire again)
  -- (IsVisible, not IsShown: Alt+Z hides the whole interface, the frame stays "shown")
  if M.rt and not M.frame:IsVisible() then runtime.sleep(M.rt) end
end

function M.showMinimap()
  if not M.mini then return end
  if M.config.minimap ~= false then M.mini:Show() else M.mini:Hide() end
end

-- restart the engine with the current settings; with a delay, once the changes stop coming
-- (a slider dragged by the mouse sends dozens of values a second). The timer is a frame of its
-- own: the timeline's frame may be hidden, and a hidden frame gets no OnUpdate.
function M.apply(delay)
  if not M.rt then return end
  M.due = delay
  if not delay then return start() end
  local t = DoubtMyRotationTimer or CreateFrame("Frame", "DoubtMyRotationTimer")
  t:SetScript("OnUpdate", function(_, dt)
    if not M.due then return end
    M.due = M.due - (dt or 0)
    if M.due <= 0 then M.apply() end
  end)
end

-- values changed: saved where they live, the addon's own parts follow, the engine restarts
function M.changed(o, delay)
  M.save(o)
  M.showMinimap()
  if M.skin then M.skin:refresh() end
  M.apply(delay)
end

-- where the character is and its level pick the profile (addon/profiles.lua)
function M.choose(o, announce)
  local _, where = IsInInstance()
  local level = math.max(M.level or 0, UnitLevel("player") or 0)
  local name, why = profiles.pick(M.db, M.char, where, level)
  M.switch(o, name, why, announce)
end

function M.switch(o, name, why, announce)
  if name == M.profile then
    M.why = why
    if M.profilePage then M.profilePage.refresh(M.profilePage) end
    return
  end
  -- a new profile restarts the engine: not in the middle of a fight (PLAYER_REGEN_ENABLED picks again)
  if M.rt and InCombatLockdown() then return end
  M.save(o)
  M.profile, M.why = name, why
  M.config = profiles.view(o.options, M.db, name)
  if M.panel then panel.reload(M.panel) end
  if M.profilePage then M.profilePage.refresh(M.profilePage) end
  if not M.rt then return end
  if announce then say(("profile %s (%s)"):format(name, profiles.RULE_NAMES[why] or "picked")) end
  M.changed(o)
end

-- Interface Options opened by an addon in a fight can taint Blizzard's own pages: after the fight
function M.open()
  if InCombatLockdown() then
    if not M.openLater then say("the settings open after combat") end
    M.openLater = true
    return
  end
  M.openLater = nil
  InterfaceOptionsFrame_OpenToCategory(M.panel)
  InterfaceOptionsFrame_OpenToCategory(M.panel) -- the first call only expands the AddOns list
end

function M.move(on)
  M.frame:EnableMouse(on)
  if on then M.frame.bg:Show() else M.frame.bg:Hide() end
end

function M.handle(o, msg)
  if not M.db then return end
  if not M.frame then return say("shaman only") end
  local r = settings.command(o.options, M.config, msg)
  for _, line in ipairs(r.lines) do say(line) end
  local a = r.action
  if a == "open" then M.open()
  elseif a == "guide" then M.coach:openGuide()
  elseif a == "export" then
    runtime.showExport(M.env)
    M.skin:export(EnhRotExportFrame)
  elseif a == "unlock" or a == "lock" then M.move(a == "unlock")
  elseif a == "hide" then M.char.hidden = true; M.frame:Hide()
  elseif a == "show" then M.char.hidden = false; M.frame:Show() end
  -- reset: the place too, the one way back for a timeline lost off screen
  if (msg or ""):match("^%s*(%S*)"):lower() == "reset" then
    M.char.point = nil
    place(M.frame, nil)
  end
  if r.changed then M.changed(o) end
end

-- what the settings window (addon/panel.lua) may read and do
function M.host(o)
  return {
    config = function() return M.config end,
    set = function(key, value) M.config[key] = value; M.changed(o, M.PAUSE) end,
    replace = function(c) M.config = settings.merge(o.options, c); M.changed(o) end,
    -- one button each for lock/unlock and hide/show: it does what its label says
    action = function(name)
      if name == "lock" then name = M.frame:IsMouseEnabled() and "lock" or "unlock"
      elseif name == "hide" then name = M.frame:IsShown() and "hide" or "show" end
      M.handle(o, name)
    end,
    label = function(name)
      if name == "lock" then return M.frame:IsMouseEnabled() and "Lock timeline" or "Unlock timeline" end
      if name == "hide" then return M.frame:IsShown() and "Hide timeline" or "Show timeline" end
      if name == "guide" then return "Show the guide" end
      return "Export snapshots"
    end,
  }
end

-- the Profiles page (addon/profilepage.lua)
function M.profileHost(o)
  return {
    list = function() return profiles.names(M.db) end,
    current = function() return M.char.profile end,
    active = function() return M.profile, M.why end,
    pick = function(name) M.char.profile = name; M.choose(o, false) end,
    create = function(name, copyCurrent)
      local n, err = profiles.create(M.db, name, copyCurrent and M.config or nil)
      if not n then return nil, err end
      M.char.profile = n
      M.choose(o, false)
      return n
    end,
    -- the active profile deleted: save() finds no profile to write into, Default comes in
    delete = function(name)
      local ok, err = profiles.delete(M.db, M.char, name)
      if ok then M.choose(o, false) end
      return ok, err
    end,
    reset = function()
      profiles.reset(M.db, M.profile)
      M.config = profiles.view(o.options, M.db, M.profile)
      if M.panel then panel.reload(M.panel) end
      M.changed(o)
    end,
    rule = function(rule) return M.char.auto[rule] end,
    setRule = function(rule, name) M.char.auto[rule] = name; M.choose(o, false) end,
  }
end

-- the first-run guide (addon/wizard.lua); stage 1's ready check on its last page, when there is one
function M.wizardHost(o)
  local c = M.checklist
  return {
    config = function() return M.config end,
    set = function(key, value) M.config[key] = value; M.changed(o) end,
    unlocked = function() return M.frame:IsMouseEnabled() end,
    move = function(on) M.move(on) end,
    checklist = c and c.items or nil,
    openChecklist = c and c.open or nil,
    done = function() M.char.wizard = "done" end,
    never = function() M.db.wizardOff = true end,
  }
end

function M.cardHost(o)
  return {
    config = function() return M.config end,
    set = function(key, value) M.config[key] = value; M.changed(o) end,
  }
end

function M.miniHost(o)
  return {
    open = function() M.open() end,
    toggle = function() M.host(o).action("hide") end,
    angle = function() return M.char.minimap and M.char.minimap.angle end,
    save = function(angle) M.char.minimap = { angle = angle } end,
  }
end

local function coachDeps(o)
  return {
    guide = M.guide, db = M.db, char = M.char,
    level = function() return math.max(M.level or 0, UnitLevel("player") or 0) end,
    enabled = function(key) return M.config[key] ~= false end,
    wizard = function()
      M.wizard = M.wizard or wizard.new(M.wizardHost(o))
      M.skin:frame(M.wizard)
      return M.wizard
    end,
    card = function()
      local w = cards.window(M.cardHost(o))
      M.skin:frame(w)
      return w
    end,
  }
end

-- the zone and the level pick the profile; a fight's end lets a waiting switch and settings through
local function listen(o)
  local f = DoubtMyRotationEvents or CreateFrame("Frame", "DoubtMyRotationEvents")
  for _, e in ipairs(M.EVENTS) do f:RegisterEvent(e) end
  f:SetScript("OnEvent", function(_, event, arg)
    if event == "PLAYER_LEVEL_UP" then M.level = tonumber(arg) end
    if event == "PLAYER_REGEN_ENABLED" and M.openLater then M.open() end
    M.choose(o, true)
  end)
end

function M.login(o)
  local _, class = UnitClass("player")
  if class ~= "SHAMAN" then return end
  M.width = o.width
  M.choose(o, false) -- the profile for where the character is, before the engine starts
  M.frame = M.frame or M.newFrame(o, M.char)
  M.frame:Show()
  M.env = { region = M.frame, saved = M.db.saved, libs = o.libs }
  start()
  M.skin = M.skin or skin.new({ enabled = function() return M.config.elvui ~= false end, say = say })
  M.skin:frame(M.frame)
  M.panel = M.panel or panel.new(o, M.host(o))
  M.skin:frame(M.panel)
  M.profilePage = M.profilePage or profilepage.new(M.profileHost(o))
  M.skin:frame(M.profilePage)
  M.updates = M.updates or update.new(runtime.VERSION, {
    db = M.db, send = SendAddonMessage, say = say,
    enabled = function() return M.config.updateCheck ~= false end,
  })
  M.updates:start(DoubtMyRotationUpdates or CreateFrame("Frame", "DoubtMyRotationUpdates"))
  M.mini = M.mini or minimap.new(M.miniHost(o))
  M.skin:frame(M.mini)
  M.showMinimap()
  listen(o)
  M.guide = M.guide or guide.new()
  M.guide:start(DoubtMyRotationGuide or CreateFrame("Frame", "DoubtMyRotationGuide"))
  M.coach = M.coach or coach.new(coachDeps(o))
  M.coach:start(DoubtMyRotationCoach or CreateFrame("Frame", "DoubtMyRotationCoach"))
  M.coach:login()
  -- hidden last time: the frame's OnHide (hooked by runtime.start) puts the engine to sleep
  if M.char.hidden then M.frame:Hide() end
end

function M.boot(o)
  o.options = addonOptions(o.options)
  -- the aura (tools/build.lua B.initCode) stays idle while the addon is installed
  DoubtMyRotationAddon = M
  SLASH_DOUBTMYROTATION1 = "/dmr"
  SlashCmdList.DOUBTMYROTATION = function(msg) M.handle(o, msg) end
  local loader = DoubtMyRotationLoader or CreateFrame("Frame", "DoubtMyRotationLoader")
  loader:RegisterEvent("ADDON_LOADED")
  loader:RegisterEvent("PLAYER_LOGIN")
  loader:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == M.NAME then M.load(o)
    elseif event == "PLAYER_LOGIN" and M.db then M.login(o) end
  end)
  return loader
end

return M
```

- [ ] **Step 6: `B.ADDON_MODULES`.**

```lua
B.ADDON_MODULES = { { "LibSerialize", "vendor/LibSerialize.lua" }, { "LibDeflate", "vendor/LibDeflate.lua" },
                    { "settings", "addon/settings.lua" }, { "profiles", "addon/profiles.lua" },
                    { "panel", "addon/panel.lua" }, { "profilepage", "addon/profilepage.lua" },
                    { "update", "addon/update.lua" }, { "guide", "addon/guide.lua" }, { "cards", "addon/cards.lua" },
                    { "wizard", "addon/wizard.lua" }, { "coach", "addon/coach.lua" }, { "minimap", "addon/minimap.lua" },
                    { "skin", "addon/skin.lua" }, { "core", "addon/core.lua" } }
```

Порядок важен: модуль выполняется при сборке файла, `__require` находит только уже выполненные (`profiles` после `settings`, `profilepage` после `profiles`, `coach` после `cards`, `core` последним).

- [ ] **Step 7: Зелёный прогон.** `docker compose run --rm test busted spec/addon_core_spec.lua spec/build_spec.lua`, затем весь набор `docker compose run --rm test busted --exclude-tags=perf` и сборка `docker compose run --rm test lua tools/build.lua` (оба артефакта; размер строки ауры — в отчёт).

- [ ] **Step 8: Коммит.** `Аддон: профили, мастер, карточки, кнопка у миникарты и ElvUI в связке; настройки на персонажа`.

### Task 9: Документация

**Files:**
- Modify: `README.md` (раздел аддона)
- Modify: `AGENTS.md` (одна строка в «Конвенциях»)
- Modify: `.claude/rules/ARCHITECTURE.md` (таблица «Аддон (`addon/`)», SavedVariables)
- Modify: `docs/superpowers/specs/2026-10-01-addon-roadmap.md` (этап 3)

**Interfaces:**
- Produces: тексты по-русски, нейтрально; README и карта не дублируют друг друга; карта ≤ ~150 строк.
- Consumes: интерфейсы задач 1–8 (по этому плану, не по коду — задача идёт параллельно с задачей 8).

- [ ] **Step 1: README.** В разделе аддона — подразделы, по 2–5 строк каждый:
  - «Первый запуск» — мастер из 4 экранов, «Skip» / «Don't show again», `/dmr guide` и кнопка «Show the guide»;
  - «Режим одной кнопки» — что остаётся на экране, где включить (General → One button mode; предлагается в мастере);
  - «Что нового на уровне» — карточки на 10–80, один раз, вне боя, выключается (General → What's new on level up);
  - «Профили» — Interface → AddOns → DoubtMyRotation → Profiles: свой профиль у персонажа, общие для аккаунта, правила для подземелья, рейда, поля боя и прокачки; прежние настройки стали профилем Default; смена — вне боя;
  - «Кнопка у миникарты» — ЛКМ, ПКМ, перетаскивание, выключается (General → Minimap button);
  - «ElvUI» — окна в его стиле, выключается (Advanced → ElvUI style, нужен `/reload`);
  - в разделе установки/обновления: «после обновления до этой версии перезапустите игру (не `/reload`): клиент читает список сохраняемых данных аддона только при запуске — иначе настройки персонажа (место ленты, выбранный профиль) не сохранятся»;
  - в таблице команд `/dmr` — `guide`.
- [ ] **Step 2: `AGENTS.md`.** В конвенции про `addon/` после «Настройки аддона — опции `tools/aura.lua` `M.OPTIONS` без `export`» дописать: «плюс `settings.ADDON_OPTIONS` (только аддон); значения — в профилях `DoubtMyRotationDB.profiles`, выбор профиля и место ленты — в `DoubtMyRotationCharDB` (`addon/profiles.lua`)». Правило «Тексты в игре — на английском» не трогать.
- [ ] **Step 3: Карта.** В таблицу «Аддон (`addon/`)» — строки `profiles` (профили и их выбор, чистые функции), `profilepage` (страница Profiles), `guide` (очередь сообщений вне боя), `wizard` (мастер первого запуска), `coach` (когда показывать мастер и карточки), `cards` (карточки уровней), `minimap` (кнопка у миникарты), `skin` (стиль ElvUI); строку `core` — «… SavedVariables `DoubtMyRotationDB` (аккаунт) и `DoubtMyRotationCharDB` (персонаж) …»; в строку `timeline` модулей `src/` — «, режим одной кнопки (`compact`)».
- [ ] **Step 4: Дорожная карта.** В таблице этапа 3 строку «Русский клиент …» убрать; в «Потом, по желанию» — строку «Русский клиент: таблица переводов `L[…]` по `GetLocale()` — отложено решением пользователя (2026-10-01); правило "тексты в игре на английском" пока в силе.»; под заголовком этапа 3 — «План: `docs/superpowers/plans/2026-10-01-stage3-comfort.md`»; в «Потом» — «Профили по сложности и размеру рейда (`GetInstanceInfo`: difficulty, maxPlayers)», «Оформление ElvUI для окон этапа 1 (разбор боя) — тем же `addon/skin.lua`, если их виджеты несут `kind`».
- [ ] **Step 5: Проверка.** Карта ≤ ~150 строк (`wc -l .claude/rules/ARCHITECTURE.md`), ссылки на файлы существуют.
- [ ] **Step 6: Коммит.** `Документация: этап 3 — мастер, одна кнопка, карточки, профили, миникарта, ElvUI`.

## Проверка в игре (после мержа, руками)

1. Новый персонаж-шаман (или у существующего — при выключенной игре удалить `WTF/Account/<acc>/<realm>/<char>/SavedVariables/DoubtMyRotation.lua`): после входа вне боя — мастер; экран 3 открепляет ленту, её можно тащить; «Done» — после `/reload` мастера нет; на другом новом персонаже — есть; «Don't show again» — нет нигде.
2. Мастер открыт, ударить моба: окно исчезает; после боя — на той же странице.
3. Обновление со старой версии: настройки и место ленты прежние (профиль Default), после **перезапуска игры**; `/reload` после выхода из игры — место ленты сохранилось.
4. Профили: создать «Dungeon» (Copy current), правило «In a dungeon» → войти в подземелье — в чате `profile Dungeon (In a dungeon)`, выйти — обратно; зайти в подземелье в бою (рядом с мобом у входа) — профиль сменился только после боя.
5. Режим одной кнопки: одна иконка, свечение «жми», алерт слева; выключить — дорожка и удары вернулись без `/reload`.
6. Уровни у тренера (сверить с `cards.HAND_LEVELS`): Flametongue Weapon — 10, Water Shield — 20, Windfury Weapon — 30, Bloodlust/Heroism — 70. Не совпало — поправить `HAND_LEVELS` и текст карточки отдельным коммитом.
7. Карточка: персонаж 19 уровня, взять 20 — после боя карточка «Level 20…»; закрыть, `/reload` — не появляется снова.
8. Миникарта: ЛКМ — окно настроек, в бою — строка «the settings open after combat» и окно после боя; ПКМ — лента пропала/появилась; тащить по кругу; `/reload` — на месте. С ElvUI — кнопка по краю квадрата.
9. ElvUI Rebuffed 6.10: окно настроек (ползунки, галочки, списки, кнопки), Profiles, мастер, карточка, окно экспорта, подложка ленты при `/dmr unlock`, кнопка у миникарты — в стиле ElvUI; Advanced → ElvUI style off → `/reload` — стандартный вид. Без ElvUI — всё как раньше, ошибок нет (`/console scriptErrors 1`).
10. Taint: после боя с открытым и закрытым окном настроек, кнопкой у миникарты — ни одного «Interface action failed because of an AddOn» (`/console taintLog 1`, `Logs/taint.log`).
