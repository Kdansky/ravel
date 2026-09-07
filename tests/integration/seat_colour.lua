-- Whose a zone is, said in colour.
--
-- Drawing is not tested here (tests/render_smoke.lua does that with a stubbed
-- love.graphics) — what is testable headless is the only decision involved:
-- which colour a seat gets, and which things get none.

local declaration = require("declaration")
local zones       = require("zones")
local flow        = require("flow")
local render      = require("render")

local M = {}

local CHOSEN = [==[{
	"title": "Colours",
	"zones": [
		{ "key": "box_one", "layout": "stack", "status": "board", "pos": [0, 0, 0.19, 0.3] },
		{ "key": "box_two", "layout": "stack", "status": "board", "pos": [0.8, 0, 0.99, 0.3] },
		{ "key": "table", "label": "Table", "layout": "row", "pos": [0.3, 0.3, 0.7, 0.6] },
		{ "key": "hand", "layout": "row", "copies": "per_seat",
			"pos": [[0.2, 0.8, 0.8, 0.95], [0.2, 0.05, 0.8, 0.2]] }
	],
	"players": [{ "card": "one" }, { "card": "two" }],
	"cards": [
		{ "key": "one", "text": "One", "asset": "circle:crimson" },
		{ "key": "two", "text": "Two", "asset": "auto" }
	],
	"setup": { "place": [{ "card": "one", "zone": "box_one" },
		{ "card": "two", "zone": "box_two" }] },
	"phases": [{ "key": "play", "type": "player_input" }]
}]==]

local function with(text, f)
	local path = "game/games/tmp_colour.json"
	local fh = assert(io.open(path, "w")) fh:write(text) fh:close()
	local ok, err = pcall(f)
	os.remove(path)
	if not ok then error(err, 2) end
end

local function same(a, b)
	return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

function M.test_seat_colour_two_players_are_two_colours(check)
	flow.init("spellstorm.json", 7)
	local seats = declaration.G.seat_list
	local one, two = render.seat_hue(seats[1]), render.seat_hue(seats[2])
	check("the first seat has a colour", one ~= nil)
	check("the second has one too", two ~= nil)
	check("and it is not the same colour", not same(one, two))

	-- A zone belonging to nobody is nobody's colour. That is most of the board
	-- in most games — a deck everyone draws from, a market, the rules — and a
	-- table where everything is tinted says no more than one where nothing is.
	check("a shared zone is neutral", render.seat_hue(zones.find("void").seat) == nil)
	check("and a per_seat zone is not", render.seat_hue(zones.find("hand").seat) ~= nil)
end

function M.test_seat_colour_a_solitaire_game_keeps_its_own(check)
	-- One seat is nobody to be told apart from, so the whole point is missing
	-- and the board stays the colour it has always been.
	flow.init("demo.json", 7)
	check("the only seat has no colour",
		render.seat_hue(declaration.G.seat_list[1]) == nil)
end

function M.test_seat_colour_every_seat_of_four_differs(check)
	flow.init("the_crew.json", 7)
	local seen = {}
	for _, seat in ipairs(declaration.G.seat_list) do
		local h = render.seat_hue(seat)
		check(seat .. " has a colour", h ~= nil)
		local word = h and table.concat(h, ",")
		check("and no one else's", word and not seen[word], word)
		seen[word or ""] = true
	end
end

function M.test_seat_colour_a_seat_that_names_its_own_is_believed(check)
	with(CHOSEN, function()
		flow.init("tmp_colour.json", 1)
		-- A seat is a card, so a game that has already chosen its players'
		-- colours has said so on the card, and the board agrees with it rather
		-- than picking a second colour for the same player.
		check("the seat's own asset colour wins",
			same(render.seat_hue("one"), require("art").colour("crimson")))
		-- "auto" is a hue derived from a card key, which nobody chose.
		check("but a generated one does not", not same(render.seat_hue("two"),
			require("art").colour("crimson")))
		check("it falls through to the palette", render.seat_hue("two") ~= nil)
	end)
end

return M
