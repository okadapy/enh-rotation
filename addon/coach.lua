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
