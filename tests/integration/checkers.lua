-- Checkers: a scripted game, in the shape chess's opening script has.
--
-- Two things here are not chess. The first is the **jump**, which takes a piece
-- standing on neither the square it left nor the square it lands on — written
-- with no new word, because a pattern is also a scope and the anchor follows the
-- piece: `down_right` read after `move_to:target` names the square flown over.
-- The second is the **chain**, which is a flow question rather than a targeting
-- one: a jump leaves `chaining` standing on the piece, the phase's own route
-- reads it and comes back to the same player, and the piece's gate
-- (`max:chaining@mine.board == chaining@self`) is what stops anybody else
-- moving while it is in the middle of one.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local phase = require("phase")
local actions = require("actions")
local geometry = require("geometry")
local predicate = require("predicate")
local targeting = require("targeting")

local M = {}

local board

local function start()
	flow.init("checkers.json", 1)
	board = zones.find("board")
end

local function sq(name)
	return geometry.slot_named(board, name)
end

-- Pieces are addressed by the square they stand on: twenty-four of them share
-- two templates, so where a man is is the only thing that tells it from another.
local function on(name)
	local occ = entity.get(sq(name)).occupant
	return occ and entity.get(occ)
end

local function at(name)
	local e = on(name)
	if not e then return nil end
	return (predicate.owner_of(e) == "player_red" and "red " or "white ") .. e.def_key
end

-- A man's abilities are step, jump left, jump right; a king's add the two
-- backward jumps. A test naming an index is naming one of those.
local function move(from, to, ability)
	local p = on(from)
	return p ~= nil and flow.activate(p.id, { sq(to) }, ability or 1)
end

local function reach(from)
	local p, out = on(from), {}
	for _, sid in ipairs(targeting.moves_of(p.id)) do
		local s = entity.get(sid)
		out[#out + 1] = string.char(96 + s.stats.col) .. tostring(s.stats.row)
	end
	table.sort(out)
	return table.concat(out, " ")
end

-- A per-seat zone is addressed by its seat here rather than by "mine"/"anyone",
-- because which of the two trays a taken man went to is the thing under test.
local function tray(seat)
	for _, z in ipairs(zones.all_with_key("taken")) do
		if z.seat == seat then return z end
	end
end

local function button(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function done()
	return flow.activate(button("done_jumping").id, {}, 1)
end

local function play(moves)
	for _, m in ipairs(moves) do
		if not move(m[1], m[2], m[3]) then return m[1] .. "-" .. m[2] end
	end
end

-- Eight moves that walk a white man down to d3 and leave a second on f5, with
-- e4 and g6 empty behind them: the position a double jump needs.
local DOUBLE_JUMP_SET_UP = {
	{ "d3", "c4" }, { "g6", "f5" },
	{ "c4", "b5" }, { "f5", "e4" },
	{ "h3", "g4" }, { "e4", "d3" },
	{ "g4", "h5" }, { "e6", "f5" },
}

function M.test_checkers_opens_with_twelve_men_a_side_on_the_dark_squares(check)
	start()
	check("twenty-four men, red to move", #board.cards == 24 and zones.active_seat() == "player_red")
	check("each side fills its own three rows", at("b1") == "red man" and at("h3") == "red man"
		and at("a6") == "white man" and at("g8") == "white man")
	check("and the light squares are empty", on("a1") == nil and on("b8") == nil)
	check("a rank counts from a piece's own side, so both front rows are 3",
		on("b3").stats.rank == 3 and on("a6").stats.rank == 3)
	check("the back row has nowhere to go", reach("b1") == "")
	check("the front row steps forward, and only forward", reach("b3") == "a4 c4")
end

function M.test_checkers_a_man_steps_diagonally_forward(check)
	start()
	check("b3-c4, and the turn passes", move("b3", "c4") and at("c4") == "red man"
		and zones.active_seat() == "player_white")
	check("white may not move red's men", flow.can_activate(on("c4").id) == false)
	check("white steps the other way down the board", move("c6", "d5") and at("d5") == "white man")
	check("a man may not step back the way it came", move("c4", "b3") == false)
end

function M.test_checkers_a_jump_takes_the_piece_it_flies_over(check)
	start()
	check("the opening plays", play({ { "b3", "c4" }, { "e6", "d5" } }) == nil)
	local victim = on("d5")
	check("c4 takes d5 and lands on e6", move("c4", "e6", 3) and at("e6") == "red man" and on("d5") == nil)
	check("the taken man is in red's tray, off the board",
		entity.get(victim.id).zone_id == tray("player_red").id and #board.cards == 23)
	check("and a square the jump did not fly over keeps what stands on it", at("d7") == "white man")
end

function M.test_checkers_a_jump_keeps_the_turn_until_the_player_says_it_is_over(check)
	start()
	check("*Done jumping* is not offered while nobody is jumping",
		flow.can_activate(button("done_jumping").id) == false)
	check("the set-up plays", play(DOUBLE_JUMP_SET_UP) == nil)

	check("c2 takes d3 and lands on e4", move("c2", "e4", 3) and at("e4") == "red man")
	check("red is still to move", zones.active_seat() == "player_red" and phase.current().key == "red_move")
	check("and no other red man may move while that one is mid-jump",
		flow.can_activate(on("b5").id) == false and flow.can_activate(on("f3").id) == false)

	check("the same man takes f5 and lands on g6", move("e4", "g6", 3) and at("g6") == "red man")
	check("two white men are in the tray", #tray("player_red").cards == 2)
	check("*Done jumping* hands the turn over", done() and zones.active_seat() == "player_white")
	check("and the next turn starts with no chain standing", on("g6").stats.chaining == 0)
end

function M.test_checkers_the_far_row_crowns_a_man(check)
	start()
	check("the set-up plays", play(DOUBLE_JUMP_SET_UP) == nil)
	check("the double jump plays", move("c2", "e4", 3) and move("e4", "g6", 3) and done())
	check("the way to the far row opens", play({
		{ "f7", "e6" }, { "g6", "f7" },
		{ "h7", "g6" }, { "b3", "a4" },
		{ "g8", "h7" } }) == nil)

	check("f7-g8, and the man is crowned", move("f7", "g8") and at("g8") == "red king")
	check("the crowning ends the move", zones.active_seat() == "player_white"
		and on("g8").stats.chaining == 0)
	check("white replies", move("c6", "d5"))
	check("a king steps back the way a man may not", move("g8", "f7") and at("f7") == "red king")
end

function M.test_checkers_a_king_jumps_backwards_and_goes_on_jumping(check)
	start()
	check("the game up to the crowning plays", play(DOUBLE_JUMP_SET_UP) == nil
		and move("c2", "e4", 3) and move("e4", "g6", 3) and done()
		and play({ { "f7", "e6" }, { "g6", "f7" }, { "h7", "g6" }, { "b3", "a4" }, { "g8", "h7" },
			{ "f7", "g8" }, { "c6", "d5" }, { "g8", "f7" }, { "d5", "c4" } }) == nil)

	check("the king takes e6 backwards and lands on d5", move("f7", "d5", 4) and at("d5") == "red king")
	check("it is still red's move", zones.active_seat() == "player_red")
	check("and it takes c4 in the same turn", move("d5", "b3", 4) and at("b3") == "red king")
	check("four white men are in the tray", #tray("player_red").cards == 4)
	check("the turn passes when red says so", done() and zones.active_seat() == "player_white")
end

function M.test_checkers_the_last_man_taken_ends_the_game(check)
	start()
	check("red opens", move("b3", "c4"))
	check("white replies", move("c6", "d5"))
	-- The last twelve captures are a long script and prove nothing the one above
	-- does not; what is under test is the route, which reads the board and not
	-- how it got that way.
	actions.run({ "purge:each.enemy.board" }, { card_id = on("c4").id, targets = {} })
	check("red moves onto an empty board", move("c4", "b5"))
	check("and the game is over", phase.current().key == "reveal"
		and entity.get(zones.find("reveal").cards[1]).def_key == "red_wins")
end

return M
