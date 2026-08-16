-- Whose a piece is, and which square it may take.
--
-- Three things that arrived together because one game asked all three at once,
-- and they are the same subject from three sides:
--
--   * a piece keeps its owner when it moves onto a shared board, so "a board can
--     be shared while the pieces on it are not" stays true after setup;
--   * "move:<scope>:<zone>" sends a set of cards somewhere, where until now only
--     the acting card and the ones a player chose could be moved;
--   * "where" narrows a slot target spec per candidate, which is how a rule about
--     the *destination* is said when nothing walks to it.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local actions = require("actions")
local predicate = require("predicate")
local targeting = require("targeting")

local M = {}

local GAME = [==[{
  "title": "Placement",
  "players": [{ "card": "one" }, { "card": "two" }],
  "patterns": {
    "across": { "vectors": [[0, 1], [0, -1]], "class": ["step"] }
  },
  "zones": [
    { "key": "stash", "type": "grid", "grid": [3, 1], "tags": ["per_seat", "activate"],
      "pos": [[0.05, 0.05, 0.95, 0.24], [0.05, 0.76, 0.95, 0.95]] },
    { "key": "board", "type": "grid", "grid": [3, 2], "tags": ["activate"],
      "pos": [0.05, 0.32, 0.95, 0.68] },
    { "key": "bin", "type": "pile", "pos": [0.05, 0.26, 0.20, 0.30] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "stash", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "two", "text": "Two" },
    { "key": "mark", "text": "Mark", "tags": ["mark"],
      "activate": {
        "target": { "type": "slot", "count": 1, "zones": ["board"], "fill": "empty",
                    "where": { "row@target": { "equals": 1 } } },
        "action": ["move_to:target"] } },
    { "key": "blocker", "text": "Blocker", "tags": ["mark"],
      "activate": {
        "target": { "type": "slot", "count": 1, "zones": ["board"], "fill": "empty",
                    "where": { "row@target": { "equals": 2 },
                               "count:mark@across": { "at_least": 1 } } },
        "action": ["move_to:target"] } }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_placement.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_placement.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function stash(seat)
	for _, z in ipairs(zones.all_with_key("stash")) do
		if z.seat == seat then return z end
	end
end

local function put(seat, key)
	return zones.add(stash(seat), key)
end

-- The candidates this card's own ability offers, read through the game file's
-- spec rather than a copy of it.
local function offered(card_id)
	local u = flow.usable_abilities(card_id)[1]
	return u and targeting.candidates(card_id, u.ability.target) or {}
end

-- Ownership is placement state, and until this it was only ever *written* by
-- setup: a card played out of a seat's own zone onto a shared board arrived
-- belonging to nobody, and every rule that says "mine" stopped seeing it.
function M.test_placement_a_piece_keeps_its_owner_on_a_shared_board(check)
	with_game(function(name)
		flow.init(name, 3)
		local mine = put("one", "mark")
		check("in its own stash it is the zone that says whose it is",
			predicate.owner_of(mine) == "one")

		zones.move_card(mine.id, zones.find_id("board"))
		check("and on the shared board it says so itself", predicate.owner_of(mine) == "one",
			tostring(predicate.owner_of(mine)))

		-- The exclusion that keeps a discard pile a discard pile: a card thrown
		-- into a shared stack is up for grabs, and an owner stamped there would
		-- refuse it to everybody else.
		local tossed = put("two", "mark")
		zones.move_card(tossed.id, zones.find_id("bin"))
		check("but a card dropped into a shared pile belongs to nobody",
			predicate.owner_of(tossed) == nil, tostring(predicate.owner_of(tossed)))
	end)
end

function M.test_placement_move_sends_a_whole_scope_home(check)
	with_game(function(name)
		flow.init(name, 3)
		local board = zones.find_id("board")
		local a, b = put("one", "mark"), put("two", "mark")
		zones.move_card(a.id, board)
		zones.move_card(b.id, board)
		check("both are out on the board", #entity.get(board).cards == 2)

		-- Written twice with opposite owner words, so between them they cover
		-- both seats whoever happens to be up.
		actions.execute("move:mine.board:mine.stash", {})
		actions.execute("move:enemy.board:enemy.stash", {})
		check("the board is clear", #entity.get(board).cards == 0)
		check("and each went to its own stash",
			a.zone_id == stash("one").id and b.zone_id == stash("two").id)
	end)
end

function M.test_placement_where_narrows_a_slot_to_the_row_it_names(check)
	with_game(function(name)
		flow.init(name, 3)
		local m = put("one", "mark")
		local all = offered(m.id)
		check("only the near row of a six-cell board is offered", #all == 3, tostring(#all))
		for _, sid in ipairs(all) do
			check("and every square offered is on it", entity.get(sid).stats.row == 1)
		end
	end)
end

-- The half a move rule could never do: "where" anchored on the *candidate*, so a
-- condition can ask what is standing opposite a square nothing has reached yet.
function M.test_placement_where_can_ask_about_the_square_itself(check)
	with_game(function(name)
		flow.init(name, 3)
		-- Both in one stash: whose piece it is decides whether a player may
		-- click it, and that is not what this test is about.
		local m = put("one", "mark")
		local b = put("one", "blocker")
		check("with the board empty there is nothing to meet", #offered(b.id) == 0)

		flow.activate(m.id, { offered(m.id)[2] })
		local col = entity.get(entity.get(m.id).slot_id).stats.col
		local now = offered(b.id)
		check("once one square is taken exactly one answers back", #now == 1, tostring(#now))
		check("and it is the far row, in that square's own column",
			entity.get(now[1]).stats.row == 2 and entity.get(now[1]).stats.col == col)
	end)
end

return M
