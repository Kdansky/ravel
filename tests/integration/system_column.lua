-- The engine's own column: a module merged into every game, at x 1.0, which is
-- where the board ends. It is the one thing a game gets without asking, so what
-- is worth testing is that it arrives, that it is made of ordinary cards, and
-- that a game cannot reach into the space it occupies.

local declaration = require("declaration")
local validate    = require("validate")
local zones       = require("zones")
local entity      = require("entity")
local flow        = require("flow")
local log         = require("log")
local tags        = require("tags")

local M = {}

local function card_in(zone_key, def_key)
	local z = zones.find(zone_key)
	for _, id in ipairs(z and z.cards or {}) do
		local c = entity.get(id)
		if c.def_key == def_key then return c end
	end
end

-- Every game, whether or not it says so, and without the word "include"
-- appearing in any of the seventeen files.
function M.test_system_every_game_carries_the_column(check)
	for _, game in ipairs({ "chess.json", "splendor.json", "the_crew.json", "menu.json" }) do
		flow.init(game, 3)
		local z = zones.find("menu")
		check(game .. " has the column", z ~= nil)
		check(game .. " has its three buttons", z and #z.cards == 3, z and #z.cards)
		check(game .. " keeps it outside the board", z and z.pos[1] >= 1.0, z and z.pos[1])
	end
end

-- The point of a module rather than chrome drawn beside the board: these are
-- cards in a zone, so everything that already knows about cards knows about
-- them — the inspector, the network, undo.
function M.test_system_the_buttons_are_ordinary_cards(check)
	flow.init("chess.json", 3)
	local save = card_in("menu", "sys_save")
	check("Save is a card", save ~= nil)
	check("and it is scenery, so nothing can target it",
		save and tags.entity_has(save, "immutable"))
	local logc = card_in("menu", "sys_log")
	check("the log card wears the engine's tag", logc and tags.entity_has(logc, "event_log"))
end

-- Not game state: the view is never saved, sent or undone, and clicking the card
-- is the same thing L has always done.
function M.test_system_the_log_card_says_how_much_to_show(check)
	flow.init("chess.json", 3)
	log.set_view("short")
	local short = #log.lines()
	local logc = card_in("menu", "sys_log")
	check("the click is the column's own, not a move", flow.use_system_card(logc.id))
	check("clicking it shows more", #log.lines() > short or log.count() <= short,
		("%d then %d of %d"):format(short, #log.lines(), log.count()))
	flow.use_system_card(logc.id)
	check("and again puts it back", log.view == "short", log.view)
	check("a card on the board is not the column's", flow.use_system_card(
		zones.find("board").cards[1]) == false)
end

-- The board is 0 to 1 and nothing else is. A game reaching past it would be
-- drawn underneath the column, which is a layout bug that looks like a
-- rendering one.
function M.test_system_a_game_may_not_reach_into_the_column(check)
	local path = "game/games/tmp_system_reach.json"
	local f = assert(io.open(path, "w"))
	f:write([[{
	  "title": "Reach",
	  "cards": [{ "key": "p1", "text": "One" }],
	  "players": [{ "card": "p1" }],
	  "zones": [{ "key": "hand", "layout": "row", "pos": [0.5, 0.05, 1.08, 0.5] }],
	  "phases": [{ "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
	  "setup": { "place": [{ "card": "p1", "zone": "hand" }] }
	}]])
	f:close()
	local problems = validate.check(declaration.parse("tmp_system_reach.json"))
	os.remove(path)
	local found = false
	for _, p in ipairs(problems) do
		if p:find("reaches past x 1.0", 1, true) then found = true end
	end
	check("a zone past x 1.0 is refused", found, table.concat(problems, "; "))
end

return M
