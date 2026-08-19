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
    { "key": "bin", "type": "pile", "pos": [0.05, 0.26, 0.20, 0.30] },
    { "key": "stock", "type": "pile", "pos": [0.80, 0.26, 0.95, 0.30] },
    { "key": "commons", "type": "pile", "pos": [0.40, 0.26, 0.60, 0.30],
      "receive": { "action": ["set_owner:target:none"] } }
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
                    "where": ["row@target == 1"] },
        "action": ["move_to:target"] } },
    { "key": "blocker", "text": "Blocker", "tags": ["mark"],
      "activate": {
        "target": { "type": "slot", "count": 1, "zones": ["board"], "fill": "empty",
                    "where": ["row@target == 2", "count:mark@across >= 1"] },
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

-- A card is born owned and stays owned. Until this, ownership was *derived*
-- from wherever the card happened to be lying, so a piece played out of a
-- seat's own zone onto a shared board arrived belonging to nobody, and every
-- rule that says "mine" stopped seeing it.
function M.test_placement_a_piece_keeps_the_owner_it_was_born_with(check)
	with_game(function(name)
		flow.init(name, 3)
		local mine = put("one", "mark")
		check("dealt out of a seat's own zone, it is that seat's",
			predicate.owner_of(mine) == "one")

		zones.move_card(mine.id, zones.find_id("board"))
		check("and it still is on the shared board", predicate.owner_of(mine) == "one",
			tostring(predicate.owner_of(mine)))
		zones.move_card(mine.id, zones.find_id("bin"))
		check("and in a shared pile, because whose it is is not where it lies",
			predicate.owner_of(mine) == "one", tostring(predicate.owner_of(mine)))
	end)
end

-- The other half, and it is what keeps a discard pile a discard pile: Lost
-- Cities deals from one shared deck, so nothing it deals is ever anybody's and
-- either player may take from either pile.
function M.test_placement_a_card_from_a_shared_zone_is_nobodys(check)
	with_game(function(name)
		flow.init(name, 3)
		local stock = zones.find("stock")
		local loose = zones.add(stock, "mark")
		check("born in a shared zone, it belongs to nobody",
			predicate.owner_of(loose) == nil, tostring(predicate.owner_of(loose)))

		zones.move_card(loose.id, zones.find_id("board"))
		check("and moving does not hand it to anybody",
			predicate.owner_of(loose) == nil, tostring(predicate.owner_of(loose)))
		check("so either seat may reach it", flow.can_activate(loose.id))
	end)
end

-- The one thing that changes whose a card is, and the zone that says it. A pile
-- anybody may take from has to disown what lands in it, and saying that once on
-- the pile beats saying it in every card that might be thrown away — which is
-- what Lost Cities' four discards now do.
function M.test_placement_a_zone_can_disown_what_lands_in_it(check)
	with_game(function(name)
		flow.init(name, 3)
		local c = put("two", "mark")
		check("it starts as somebody's", predicate.owner_of(c) == "two")

		zones.move_card(c.id, zones.find_id("commons"))
		check("and the pile takes that away as it arrives",
			predicate.owner_of(c) == nil, tostring(predicate.owner_of(c)))
		check("nobody is 0, not absent — so it cannot fall back to the zone it lies in",
			c.stats.owner == 0, tostring(c.stats.owner))

		zones.move_card(c.id, zones.find_id("board"))
		check("and it stays nobody's when it moves on",
			predicate.owner_of(c) == nil, tostring(predicate.owner_of(c)))
	end)
end

-- The other direction, which is what the verb is really for: mind control.
function M.test_placement_set_owner_hands_a_card_over(check)
	with_game(function(name)
		flow.init(name, 3)
		local c = put("two", "mark")
		actions.execute("set_owner:each.stash:mine", {})
		check("the seat that is up takes it", predicate.owner_of(c) == "one",
			tostring(predicate.owner_of(c)))
		actions.execute("set_owner:each.stash:two", {})
		check("and a seat can be named outright", predicate.owner_of(c) == "two",
			tostring(predicate.owner_of(c)))
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
