-- How many cards a move moves.
--
-- `destroy` could be told a number and `move` could not, so "send two of my
-- gems over there" had to be written as a kill beside a `fill` — two ops that
-- between them lose the cards, their history and any chance of the player
-- watching them travel. Puzzle Strike's Crash Bomb was written that way, which
-- is how the gap was found.
--
-- One optional argument, in the slot the position already used. "top" and
-- "bottom" are not numbers and nothing else in the grammar is a bare word
-- there, so a spelling that skips the count is unambiguous and every one
-- written before this still means what it meant.

local entity  = require("entity")
local zones   = require("zones")
local flow    = require("flow")
local actions = require("actions")

local M = {}

local GAME = [==[{
  "title": "Move Count",
  "players": [{ "card": "one" }],
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.20, 0.80, 0.50, 0.95] },
    { "key": "bag", "layout": "stack", "visibility": "secret", "pos": [0.55, 0.80, 0.65, 0.95] },
    { "key": "table", "layout": "stack", "pos": [0.75, 0.80, 0.85, 0.95] }
  ],
  "phases": [{ "key": "act", "type": "player_input", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "gem", "text": "Gem", "tags": ["gem"] },
    { "key": "rock", "text": "Rock", "tags": ["rock"] }
  ],
  "setup": {
    "place": [
      { "card": "gem", "zone": "hand" }, { "card": "gem", "zone": "hand" },
      { "card": "gem", "zone": "hand" }, { "card": "gem", "zone": "hand" },
      { "card": "rock", "zone": "hand" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_move_count.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_move_count.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function count(zone_key, def_key)
	local n = 0
	for _, id in ipairs(zones.find(zone_key).cards) do
		if not def_key or entity.get(id).def_key == def_key then n = n + 1 end
	end
	return n
end

local function order(zone_key)
	local out = {}
	for _, id in ipairs(zones.find(zone_key).cards) do out[#out + 1] = entity.get(id).def_key end
	return table.concat(out, ",")
end

function M.test_move_count_moves_exactly_that_many(check)
	with_game(function(name)
		flow.init(name, 1)
		actions.execute("move:hand.gem:table:2", {})
		check("two of the four gems went", count("table") == 2)
		check("and two stayed behind", count("hand", "gem") == 2)
		check("the rock was never in scope", count("hand", "rock") == 1)
	end)
end

function M.test_move_with_no_count_still_moves_everything(check)
	with_game(function(name)
		flow.init(name, 1)
		actions.execute("move:hand.gem:table", {})
		check("all four gems went, as move has always meant", count("table") == 4)
		check("and the rock stayed", order("hand") == "rock")
	end)
end

function M.test_a_count_larger_than_the_scope_moves_what_there_is(check)
	with_game(function(name)
		flow.init(name, 1)
		actions.execute("move:hand.gem:table:99", {})
		check("four asked for ninety-nine is four", count("table") == 4)
	end)
end

function M.test_a_position_still_reads_where_a_count_would_go(check)
	with_game(function(name)
		flow.init(name, 1)
		-- Every spelling written before the count existed still means what it
		-- meant, which is the whole reason the two can share a slot.
		actions.execute("move:hand.rock:bag", {})
		actions.execute("move:hand.gem:bag:bottom", {})
		check("the gems went under the rock", order("bag"):match("^gem,gem,gem,gem,rock$") ~= nil)
	end)
end

function M.test_a_count_and_then_a_position(check)
	with_game(function(name)
		flow.init(name, 1)
		actions.execute("move:hand.rock:bag", {})
		actions.execute("move:hand.gem:bag:2:bottom", {})
		check("two gems, buried", order("bag") == "gem,gem,rock")
		check("and two left in hand", count("hand", "gem") == 2)
	end)
end

function M.test_a_measured_count(check)
	with_game(function(name)
		flow.init(name, 1)
		-- An amount is one slot or five, so the position after one is not found
		-- by counting colons — the same trap `draw_from` already had.
		actions.execute("move:hand.gem:bag:count:rock@hand:bottom", {})
		check("one rock in hand meant one gem moved", order("bag") == "gem")
		check("with three gems left", count("hand", "gem") == 3)
	end)
end

function M.test_a_random_count_picks_that_many_different_cards(check)
	with_game(function(name)
		flow.init(name, 1)
		actions.execute("move:random.hand.gem:table:3", {})
		check("three different gems, not one gem three times", count("table") == 3)
		check("one gem left behind", count("hand", "gem") == 1)
	end)
end

function M.test_a_random_scope_with_no_count_still_means_one(check)
	with_game(function(name)
		flow.init(name, 1)
		actions.execute("move:random.hand.gem:table", {})
		check("one, as it always did", count("table") == 1)
	end)
end

return M
